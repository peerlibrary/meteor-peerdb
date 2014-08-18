semver = Npm.require 'semver'
Future = Npm.require 'fibers/future'

globals = @

# From Meteor's random/random.js
UNMISTAKABLE_CHARS = '23456789ABCDEFGHJKLMNPQRSTWXYZabcdefghijkmnopqrstuvwxyz'

INSTANCES = parseInt(process.env.PEERDB_INSTANCES ? 1)
INSTANCE = parseInt(process.env.PEERDB_INSTANCE ? 0)

throw new Error "Invalid number of instances: #{ INSTANCES }" unless 0 <= INSTANCES <= UNMISTAKABLE_CHARS.length
throw new Error "Invalid instance index: #{ INSTANCE }" unless (INSTANCES is 0 and INSTANCE is 0) or 0 <= INSTANCE < INSTANCES

# TODO: Support also other types of _id generation (like ObjectID)
# TODO: We could do also a hash of an ID and then split, this would also prevent any DOS attacks by forcing IDs of a particular form
PREFIX = UNMISTAKABLE_CHARS.split ''

if INSTANCES > 1
  range = UNMISTAKABLE_CHARS.length / INSTANCES
  PREFIX = PREFIX[Math.round(INSTANCE * range)...Math.round((INSTANCE + 1) * range)]

# Fields:
#   serial
#   migrationName
#   oldCollectionName
#   newCollectionName
#   oldVersion
#   newVersion
#   timestamp
#   migrated
#   all
# We use a lower case collection name to signal it is a system collection
globals.Document.Migrations = new Meteor.Collection 'migrations'

fieldsToProjection = (fields) ->
  projection =
    _id: 1 # In the case we want only id, that is, detect deletions
  for field in fields
    if _.isString field
      projection[field] = 1
    else
      _.extend projection, field
  projection

# TODO: Should we add retry?
observerCallback = (f) ->
  return (obj, args...) ->
    try
      id = if _.isObject obj then obj._id else obj
      # We call f only if the first character of id is in PREFIX.
      # By that we allow each instance to operate only on a subset
      # of documents, allowing simple coordination while scaling.
      f obj, args... if id[0] in PREFIX
    catch e
      Log.error "PeerDB exception: #{ e }: #{ util.inspect args, depth: 10 }"
      Log.error e.stack

extractValue = (obj, path) ->
  while path.length
    obj = obj[path[0]]
    path = path[1..]
  obj

# Cannot use => here because we are not in the globals.Document._TargetedFieldsObservingField context.
# We have to modify prototype directly because there are classes which already inherit from the class
# and we cannot just override the class as we are doing for other server-side only methods.
globals.Document._TargetedFieldsObservingField::_setupTargetObservers = (updateAll) ->
  if not updateAll and @ instanceof globals.Document._ReferenceField
    index = {}
    index["#{ @sourcePath }._id"] = 1
    @sourceCollection._ensureIndex index

    if @reverseName
      index = {}
      index["#{ @reverseName }._id"] = 1
      @targetCollection._ensureIndex index

  initializing = true

  observers =
    added: observerCallback (id, fields) =>
      @updateSource id, fields if updateAll or not initializing

  unless updateAll
    observers.changed = observerCallback (id, fields) =>
      @updateSource id, fields

    observers.removed = observerCallback (id) =>
      @removeSource id

  referenceFields = fieldsToProjection @fields
  handle = @targetCollection.find({}, fields: referenceFields).observeChanges observers

  initializing = false

  handle.stop() if updateAll

# Cannot use => here because we are not in the globals.Document._Trigger context.
# We are modifying prototype directly to match code style of
# _TargetedFieldsObservingField::_setupTargetObservers but in this case it is not
# really needed, because there are no already existing classes which would inherit
# from globals.Document._Trigger.
globals.Document._Trigger::_setupObservers = ->
  initializing = true

  queryFields = fieldsToProjection @fields
  @collection.find({}, fields: queryFields).observe
    added: observerCallback (document) =>
      @trigger document, {} unless initializing

    changed: observerCallback (newDocument, oldDocument) =>
      @trigger newDocument, oldDocument

    removed: observerCallback (oldDocument) =>
      @trigger {}, oldDocument

  initializing = false

class globals.Document._Trigger extends globals.Document._Trigger
  trigger: (newDocument, oldDocument) =>
    @generator newDocument, oldDocument

class globals.Document._ReferenceField extends globals.Document._ReferenceField
  updateSource: (id, fields) =>
    # Just to be sure
    return if _.isEmpty fields

    selector = {}
    selector["#{ @sourcePath }._id"] = id

    update = {}
    if @inArray
      for field, value of fields
        path = "#{ @ancestorArray }.$#{ @arraySuffix }.#{ field }"

        if _.isUndefined value
          update.$unset ?= {}
          update.$unset[path] = ''
        else
          update.$set ?= {}
          update.$set[path] = value

        # We cannot use top-level $or with $elemMatch
        # See: https://jira.mongodb.org/browse/SERVER-11537
        selector[@ancestorArray] ?= {}
        selector[@ancestorArray].$elemMatch ?=
          $or: []

        s = {}
        # We have to repeat id selector here as well
        # See: https://jira.mongodb.org/browse/SERVER-11536
        s["#{ @arraySuffix }._id".substring(1)] = id
        # Remove initial dot with substring(1)
        if _.isUndefined value
          s["#{ @arraySuffix }.#{ field }".substring(1)] =
            $exists: true
        else
          s["#{ @arraySuffix }.#{ field }".substring(1)] =
            $ne: value

        selector[@ancestorArray].$elemMatch.$or.push s

      # $ operator updates only the first matching element in the array,
      # so we have to loop until nothing changes
      # See: https://jira.mongodb.org/browse/SERVER-1243
      loop
        break unless @sourceCollection.update selector, update, multi: true

    else
      for field, value of fields
        path = "#{ @sourcePath }.#{ field }"

        s = {}
        if _.isUndefined value
          update.$unset ?= {}
          update.$unset[path] = ''

          s[path] =
            $exists: true
        else
          update.$set ?= {}
          update.$set[path] = value

          s[path] =
            $ne: value

        selector.$or ?= []
        selector.$or.push s

      @sourceCollection.update selector, update, multi: true

  removeSource: (id) =>
    selector = {}
    selector["#{ @sourcePath }._id"] = id

    # If it is an array or a required field of a subdocument is in an array, we remove references from an array
    if @isArray or (@required and @inArray)
      update =
        $pull: {}
      update.$pull[@ancestorArray] = {}
      # @arraySuffix starts with a dot, so with .substring(1) we always remove a dot
      update.$pull[@ancestorArray]["#{ @arraySuffix or '' }._id".substring(1)] = id

      @sourceCollection.update selector, update, multi: true

    # If it is an optional field of a subdocument in an array, we set it to null
    else if not @required and @inArray
      path = "#{ @ancestorArray }.$#{ @arraySuffix }"
      update =
        $set: {}
      update.$set[path] = null

      # $ operator updates only the first matching element in the array.
      # So we have to loop until nothing changes.
      # See: https://jira.mongodb.org/browse/SERVER-1243
      loop
        break unless @sourceCollection.update selector, update, multi: true

    # If it is an optional reference, we set it to null
    else if not @required
      update =
        $set: {}
      update.$set[@sourcePath] = null

      @sourceCollection.update selector, update, multi: true

    # Else, we remove the whole document
    else
      @sourceCollection.remove selector

  updatedWithValue: (id, value) =>
    unless _.isObject(value) and _.isString(value._id)
      # Optional field
      return if _.isNull(value) and not @required

      # TODO: This is not triggered if required field simply do not exist or is set to undefined (does MongoDB support undefined value?)
      Log.error "Document's '#{ id }' field '#{ @sourcePath }' was updated with an invalid value: #{ util.inspect value }"
      return

    # Only _id is requested, we do not have to do anything
    unless _.isEmpty @fields
      referenceFields = fieldsToProjection @fields
      target = @targetCollection.findOne value._id,
        fields: referenceFields
        transform: null

      unless target
        Log.error "Document's '#{ id }' field '#{ @sourcePath }' is referencing a nonexistent document '#{ value._id }'"
        # TODO: Should we call reference.removeSource here?
        return

      # We omit _id because that field cannot be changed, or even $set to the same value, but is in target
      @updateSource target._id, _.omit target, '_id'

    return unless @reverseName

    reverseFields = fieldsToProjection @reverseFields
    source = @sourceCollection.findOne id,
      fields: reverseFields
      transform: null

    selector =
      _id: value._id
    selector["#{ @reverseName }._id"] =
      $ne: id

    update = {}
    update[@reverseName] = source

    @targetCollection.update selector,
      $addToSet: update

class globals.Document._GeneratedField extends globals.Document._GeneratedField
  _updateSourceField: (id, fields) =>
    [selector, sourceValue] = @generator fields

    return unless selector

    if @isArray and not _.isArray sourceValue
      Log.error "Generated field '#{ @sourcePath }' defined as an array with selector '#{ selector }' was updated with a non-array value: #{ util.inspect sourceValue }"
      return

    if not @isArray and _.isArray sourceValue
      Log.error "Generated field '#{ @sourcePath }' not defined as an array with selector '#{ selector }' was updated with an array value: #{ util.inspect sourceValue }"
      return

    update = {}
    if _.isUndefined sourceValue
      update.$unset = {}
      update.$unset[@sourcePath] = ''
    else
      update.$set = {}
      update.$set[@sourcePath] = sourceValue

    @sourceCollection.update selector, update, multi: true

  _updateSourceNestedArray: (id, fields) =>
    assert @arraySuffix # Should be non-null

    values = @generator fields

    unless _.isArray values
      Log.error "Value returned from the generator for field '#{ @sourcePath }' is not a nested array despite field being nested in an array: #{ util.inspect values }"
      return

    for [selector, sourceValue], i in values
      continue unless selector

      if _.isArray sourceValue
        Log.error "Generated field '#{ @sourcePath }' not defined as an array with selector '#{ selector }' was updated with an array value: #{ util.inspect sourceValue }"
        continue

      path = "#{ @ancestorArray }.#{ i }#{ @arraySuffix }"

      update = {}
      if _.isUndefined sourceValue
        update.$unset = {}
        update.$unset[path] = ''
      else
        update.$set = {}
        update.$set[path] = sourceValue

      break unless @sourceCollection.update selector, update, multi: true

  updateSource: (id, fields) =>
    if _.isEmpty fields
      fields._id = id
    # TODO: Not completely correct when @fields contain multiple fields from same subdocument or objects with projections (they will be counted only once) - because Meteor always passed whole subdocuments we could count only top-level fields in @fields, merged with objects?
    else if _.size(fields) isnt @fields.length
      targetFields = fieldsToProjection @fields
      fields = @targetCollection.findOne id,
        fields: targetFields
        transform: null

      # There is a slight race condition here, document could be deleted in meantime.
      # In such case we set fields as they are when document is deleted.
      unless fields
        fields =
          _id: id
    else
      fields._id = id

    # Only if we are updating value nested in a subdocument of an array we operate
    # on the array. Otherwise we simply set whole array to the value returned.
    if @inArray and not @isArray
      @_updateSourceNestedArray id, fields
    else
      @_updateSourceField id, fields

  removeSource: (id) =>
    @updateSource id, {}

  updatedWithValue: (id, value) =>
    # Do nothing. Code should not be updating generated field by itself anyway.

class globals.Document extends globals.Document
  @_sourceFieldProcessDeleted: (field, id, ancestorSegments, pathSegments, value) ->
    if ancestorSegments.length
      assert ancestorSegments[0] is pathSegments[0]
      @_sourceFieldProcessDeleted field, id, ancestorSegments[1..], pathSegments[1..], value[ancestorSegments[0]]
    else
      value = [value] unless _.isArray value

      ids = (extractValue(v, pathSegments)._id for v in value when extractValue(v, pathSegments)?._id)

      assert field.reverseName

      update = {}
      update[field.reverseName] =
        _id: id

      field.targetCollection.update
        _id:
          $nin:
            ids
      ,
        $pull: update
      ,
        multi: true

  @_sourceFieldUpdated: (id, name, value, field, originalValue) ->
    # TODO: Should we check if field still exists but just value is undefined, so that it is the same as null? Or can this happen only when removing the field?
    if _.isUndefined value
      if field?.reverseName
        @_sourceFieldProcessDeleted field, id, [], name.split('.')[1..], originalValue
      return

    field = field or @Meta.fields[name]

    # We should be subscribed only to those updates which are defined in @Meta.fields
    assert field

    originalValue = originalValue or value

    if field instanceof globals.Document._ObservingField
      if field.ancestorArray and name is field.ancestorArray
        unless _.isArray value
          Log.error "Document's '#{ id }' field '#{ name }' was updated with a non-array value: #{ util.inspect value }"
          return
      else
        value = [value]

      for v in value
        field.updatedWithValue id, v

      if field.reverseName
        pathSegments = name.split('.')

        if field.ancestorArray
          ancestorSegments = field.ancestorArray.split('.')

          assert ancestorSegments[0] is pathSegments[0]

          @_sourceFieldProcessDeleted field, id, ancestorSegments[1..], pathSegments[1..], originalValue
        else
          @_sourceFieldProcessDeleted field, id, [], pathSegments[1..], originalValue

    else if field not instanceof globals.Document._Field
      value = [value] unless _.isArray value

      # If value is an array but it should not be, we cannot do much else.
      # Same goes if the value does not match structurally fields.
      for v in value
        for n, f of field
          # TODO: Should we skip calling @_sourceFieldUpdated if we already called it with exactly the same parameters this run?
          @_sourceFieldUpdated id, "#{ name }.#{ n }", v[n], f, originalValue

  @_sourceUpdated: (id, fields) ->
    for name, value of fields
      @_sourceFieldUpdated id, name, value

  @_setupSourceObservers: (updateAll) ->
    return if _.isEmpty @Meta.fields

    indexes = []
    sourceFields =
      _id: 1 # To make sure we do not pass empty set of fields

    sourceFieldsWalker = (obj) ->
      for name, field of obj
        if field instanceof globals.Document._ObservingField
          sourceFields[field.sourcePath] = 1
          if field instanceof globals.Document._ReferenceField
            index = {}
            index["#{ field.sourcePath }._id"] = 1
            indexes.push index
        else if field not instanceof globals.Document._Field
          sourceFieldsWalker field

    sourceFieldsWalker @Meta.fields

    unless updateAll
      for index in indexes
        @Meta.collection._ensureIndex index

    initializing = true

    observers =
      added: observerCallback (id, fields) =>
        @_sourceUpdated id, fields if updateAll or not initializing

    unless updateAll
      observers.changed = observerCallback (id, fields) =>
        @_sourceUpdated id, fields

    handle = @Meta.collection.find({}, fields: sourceFields).observeChanges observers

    initializing = false

    handle.stop() if updateAll

  @_Migration: class
    updateAll: (document, collection, currentSchema, intoSchema) =>
      @_updateAll = true

    forward: (document, collection, currentSchema, newSchema) =>
      migrated: 0
      all: collection.update {_schema: currentSchema}, {$set: _schema: newSchema}, {multi: true}

    backward: (document, collection, currentSchema, oldSchema) =>
      migrated: 0
      all: collection.update {_schema: currentSchema}, {$set: _schema: oldSchema}, {multi: true}

  @PatchMigration: class extends @_Migration

  @MinorMigration: class extends @_Migration

  @MajorMigration: class extends @_Migration

  @AddSyncedFieldsMigration: class extends @MinorMigration
    forward: (document, collection, currentSchema, newSchema) =>
      @updateAll document, collection, currentSchema, newSchema

      counts = super
      counts.migrated = counts.all
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      @updateAll document, collection, currentSchema, oldSchema

      counts = super
      counts.migrated = counts.all
      counts

  @RemoveSyncedFieldsMigration: class extends @MajorMigration
    forward: (document, collection, currentSchema, newSchema) =>
      @updateAll document, collection, currentSchema, newSchema

      counts = super
      counts.migrated = counts.all
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      @updateAll document, collection, currentSchema, oldSchema

      counts = super
      counts.migrated = counts.all
      counts

  @AddAutoFieldsMigration: class extends @MinorMigration
    # Fields is an array
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      assert @fields

      @updateAll document, collection, currentSchema, newSchema

      counts = super
      counts.migrated = counts.all
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      update =
        $unset: {}
        $set:
          _schema: oldSchema

      for field in @fields
        update.$unset[field] = ''

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

  @ModifyAutoFieldsMigration: class extends @MinorMigration
    # Fields is an array
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      assert @fields

      @updateAll document, collection, currentSchema, newSchema

      counts = super
      counts.migrated = counts.all
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      assert @fields

      @updateAll document, collection, currentSchema, oldSchema

      counts = super
      counts.migrated = counts.all
      counts

  @RemoveAutoFieldsMigration: class extends @MajorMigration
    # Fields is an array
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      update =
        $unset: {}
        $set:
          _schema: newSchema

      for field in @fields
        update.$unset[field] = ''

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      assert @fields

      @updateAll document, collection, currentSchema, newSchema

      counts = super
      counts.migrated = counts.all
      counts

  @AddOptionalFieldsMigration: class extends @MinorMigration
    # Fields is an array
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      assert @fields
      super

    backward: (document, collection, currentSchema, oldSchema) =>
      update =
        $unset: {}
        $set:
          _schema: oldSchema

      for field in @fields
        update.$unset[field] = ''

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

  @AddRequiredFieldsMigration: class extends @MinorMigration
    # Fields is an object
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      selector =
        _schema: currentSchema
      for field, value of @fields
        selector[field] =
          $exists: false

      update =
        $set:
          _schema: newSchema
      for field, value of @fields
        if _.isFunction value
          update.$set[field] = value()
        else
          update.$set[field] = value

      count = collection.update selector, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      update =
        $unset: {}
        $set:
          _schema: oldSchema

      for field, value of @fields
        update.$unset[field] = ''

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

  @RemoveFieldsMigration: class extends @MajorMigration
    # Fields is an object
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      update =
        $unset: {}
        $set:
          _schema: newSchema

      for field, value of @fields
        update.$unset[field] = ''

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      selector =
        _schema: currentSchema
      for field, value of @fields
        selector[field] =
          $exists: false

      update =
        $set:
          _schema: oldSchema
      for field, value of @fields
        if _.isFunction value
          update.$set[field] = value()
        else
          update.$set[field] = value

      count = collection.update selector, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

  @RenameFieldsMigration: class extends @MajorMigration
    # Fields is object
    constructor: (fields) ->
      @fields = fields if fields
      super

    forward: (document, collection, currentSchema, newSchema) =>
      update =
        $set:
          _schema: newSchema
        $rename: {}

      for from, to of @fields
        update.$rename[from] = to

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

    backward: (document, collection, currentSchema, oldSchema) =>
      update =
        $set:
          _schema: oldSchema
        $rename: {}

      for from, to of @fields
        # Reversed
        update.$rename[to] = from

      count = collection.update {_schema: currentSchema}, update, {multi: true}

      counts = super
      counts.migrated += count
      counts.all += count
      counts

  @_RenameCollectionMigration: class extends @MajorMigration
    constructor: (@oldName, @newName) ->
      @name = "Renaming collection from '#{ @oldName }' to '#{ @newName }'"

    _rename: (mongoCollection, to, callback) =>
      mongoCollection.rename to, (error, collection) =>
        if error
          return callback error unless /source namespace does not exist/.test "#{ error }"
        callback null

    forward: (document, collection, currentSchema, newSchema) =>
      assert.equal collection.name, @oldName

      mongoCollection = MongoInternals.defaultRemoteCollectionDriver().mongo._getCollection @oldName

      future = new Future()
      @_rename mongoCollection, @newName, future.resolver()
      future.wait()

      collection.name = @newName

      # We renamed the collection, so let's update all documents to new schema version
      counts = super
      # We migrated everything
      counts.migrated = counts.all
      counts

    backward: (document, collection, currentSchema, newSchema) =>
      assert.equal collection.name, @newName

      mongoCollection = MongoInternals.defaultRemoteCollectionDriver().mongo._getCollection @newName

      future = new Future()
      @_rename mongoCollection, @oldName, future.resolver()
      future.wait()

      collection.name = @oldName

      # We renamed the collection, so let's update all documents to old schema version
      counts = super
      # We migrated everything
      counts.migrated = counts.all
      counts

  @addMigration: (migration) ->
    throw new Error "Migration is missing a name" unless migration.name
    throw new Error "Migration is not a migration instance" unless migration instanceof @_Migration
    throw new Error "Migration with the name '#{ migration.name }' already exists" if migration.name in _.pluck @Meta.migrations, 'name'

    @Meta.migrations.push migration

  @renameCollectionMigration: (oldName, newName) ->
    @addMigration new @_RenameCollectionMigration oldName, newName

  @migrateForward: (untilName) ->
    # TODO: Implement
    throw new Error "Not implemented yet"

  @migrateBackward: (untilName) ->
    # TODO: Implement
    throw new Error "Not implemented yet"

  @migrate: ->
    schemas = ['1.0.0']
    currentSchema = '1.0.0'
    currentSerial = 0

    initialName = @Meta.collection._name
    for migration in @Meta.migrations by -1 when migration instanceof @_RenameCollectionMigration
      throw new Error "Incosistent document renaming, renaming from '#{ migration.oldName }' to '#{ migration.newName }', but current name is '#{ initialName }' (new name and current name should match)" if migration.newName isnt initialName
      initialName = migration.oldName

    migrationsPending = Number.POSITIVE_INFINITY
    currentName = initialName
    for migration, i in @Meta.migrations
      if migration instanceof @PatchMigration
        newSchema = semver.inc currentSchema, 'patch'
      else if migration instanceof @MinorMigration
        newSchema = semver.inc currentSchema, 'minor'
      else if migration instanceof @MajorMigration
        newSchema = semver.inc currentSchema, 'major'

      if migration instanceof @_RenameCollectionMigration
        newName = migration.newName
      else
        newName = currentName

      migrations = globals.Document.Migrations.find(
        serial:
          $gt: currentSerial
        oldCollectionName:
          $in: [currentName, newName]
      ,
        sort: [
          ['serial', 'asc']
        ]
      ).fetch()

      if migrations[0]
        throw new Error "Unexpected migration recorded: #{ util.inspect migrations[0], depth: 10 }" if migrationsPending < Number.POSITIVE_INFINITY

        if migrations[0].migrationName is migration.name and migrations[0].oldCollectionName is currentName and migrations[0].newCollectionName is newName and migrations[0].oldVersion is currentSchema and migrations[0].newVersion is newSchema
          currentSerial = migrations[0].serial
        else
          throw new Error "Incosistent migration recorded, expected migrationName='#{ migration.name }', oldCollectionName='#{ currentName }', newCollectionName='#{ newName }', oldVersion='#{ currentSchema }', newVersion='#{ newSchema }', got: #{ util.inspect migrations[0], depth: 10 }"
      else if migrationsPending is Number.POSITIVE_INFINITY
        # This is the collection name recorded as the last, so we start with it
        initialName = currentName
        migrationsPending = i

      currentSchema = newSchema
      schemas.push currentSchema
      currentName = newName

    unknownSchema = _.pluck @Meta.collection.find(
      _schema:
        $nin: schemas
        $exists: true
    ,
      fields:
        _id: 1
    ).fetch(), '_id'

    throw new Error "Documents with unknown schema version: #{ unknownSchema }" if unknownSchema.length

    updateAll = false

    currentSchema = '1.0.0'
    currentSerial = 0
    currentName = initialName
    for migration, i in @Meta.migrations
      if migration instanceof @PatchMigration
        newSchema = semver.inc currentSchema, 'patch'
      else if migration instanceof @MinorMigration
        newSchema = semver.inc currentSchema, 'minor'
      else if migration instanceof @MajorMigration
        newSchema = semver.inc currentSchema, 'major'

      if i < migrationsPending and migration instanceof @_RenameCollectionMigration
        # We skip all already done rename migrations (but we run other old migrations again, just with the last known collection name)
        currentSchema = newSchema
        currentName = migration.newName
        continue

      if migration instanceof @_RenameCollectionMigration
        newName = migration.newName
      else
        newName = currentName

      if globals.Document.migrationsDisabled
        # Migrations are disabled but we are still running
        # the code just to compute the latest schema version
        currentSchema = newSchema
        currentName = newName
        continue

      migration._updateAll = false

      counts = migration.forward @, new DirectCollection(currentName), currentSchema, newSchema
      throw new Error "Invalid return value from migration: #{ util.inspect counts }" unless 'migrated' of counts and 'all' of counts

      updateAll = true if counts.migrated and migration._updateAll

      if i < migrationsPending
        count = globals.Document.Migrations.update
          migrationName: migration.name
          oldCollectionName: currentName
          newCollectionName: newName
          oldVersion: currentSchema
          newVersion: newSchema
        ,
          $inc:
            migrated: counts.migrated
            all: counts.all
        ,
          multi: true # To catch any errors

        throw new Error "Incosistent migration record state, missing migrationName='#{ migration.name }', oldCollectionName='#{ currentName }', newCollectionName='#{ newName }', oldVersion='#{ currentSchema }', newVersion='#{ newSchema }'" unless count is 1
      else
        count = globals.Document.Migrations.find(
          migrationName: migration.name
          oldCollectionName: currentName
          newCollectionName: newName
          oldVersion: currentSchema
          newVersion: newSchema
        ).count()

        throw new Error "Incosistent migration record state, unexpected migrationName='#{ migration.name }', oldCollectionName='#{ currentName }', newCollectionName='#{ newName }', oldVersion='#{ currentSchema }', newVersion='#{ newSchema }'" unless count is 0

        globals.Document.Migrations.insert
          # Things should not be running in parallel here anyway, so we can get next serial in this way
          serial: globals.Document.Migrations.findOne({}, {sort: [['serial', 'desc']]}).serial + 1
          migrationName: migration.name
          oldCollectionName: currentName
          newCollectionName: newName
          oldVersion: currentSchema
          newVersion: newSchema
          migrated: counts.migrated
          all: counts.all
          timestamp: moment.utc().toDate()

      if migration instanceof @_RenameCollectionMigration
        Log.info "Renamed collection '#{ currentName }' to '#{ newName }'"
        Log.info "Migrated #{ counts.migrated }/#{ counts.all } document(s) (from #{ currentSchema } to #{ newSchema }): #{ migration.name }" if counts.all
      else
        Log.info "Migrated #{ counts.migrated }/#{ counts.all } document(s) in '#{ currentName }' collection (from #{ currentSchema } to #{ newSchema }): #{ migration.name }" if counts.all

      currentSchema = newSchema
      currentName = newName

    # We do not check for not migrated documents if migrations are disabled
    unless globals.Document.migrationsDisabled
      # For all those documents which lack schema information we assume they have the last schema
      @Meta.collection.update
        _schema:
          $exists: false
      ,
        $set:
          _schema: currentSchema
      ,
        multi: true

      notMigrated = _.pluck @Meta.collection.find(
        _schema:
          $ne: currentSchema
      ,
        fields:
          _id: 1
      ).fetch(), '_id'

      throw new Error "Not all documents migrated to the latest schema version (#{ currentSchema }): #{ notMigrated }" if notMigrated.length

    @Meta.schema = currentSchema

    # Return if updateAll should be called
    updateAll

  @_setupMigrations: ->
    updateAll = @migrate()

    unless globals.Document.instanceDisabled
      @Meta.collection.find(
        _schema:
          $exists: false
      ,
        fields:
          _id: 1
          _schema: 1
      ).observeChanges
        added: observerCallback (id, fields) =>
          # TODO: Check if schema is known and complain if not
          # TODO: We could automatically migrate old documents if we know of newer schema
          return if fields._schema

          @Meta.collection.update id,
            $set:
              _schema: @Meta.schema

    # Return if updateAll should be called
    updateAll

  @updateAll: ->
    # It is only reasonable to run anything if this instance
    # is not disabled. Otherwise we would still go over all
    # documents, just we would not process any.
    setupObservers true unless globals.Document.instanceDisabled

# TODO: What happens if this is called multiple times? We should make sure that for each document observrs are made only once
setupObservers = (updateAll) ->
  setupTriggerObserves = (triggers) ->
    for name, trigger of triggers
      trigger._setupObservers()

  setupTargetObservers = (fields) ->
    for name, field of fields
      # There are no arrays anymore here, just objects (for subdocuments) or fields
      if field instanceof globals.Document._TargetedFieldsObservingField
        field._setupTargetObservers updateAll
      else if field not instanceof globals.Document._Field
        setupTargetObservers field

  for document in globals.Document.list
    # We setup triggers only when we are not updating all
    setupTriggerObserves document.Meta.triggers unless updateAll
    # For fields we pass updateAll on
    setupTargetObservers document.Meta.fields
    document._setupSourceObservers updateAll

# TODO: What happens if this is called multiple times? We should make sure that for each document observrs are made only once
setupMigrations = ->
  updateAll = false
  # Migrate all except local collections
  for document in globals.Document.list when document.Meta.collection._name isnt null
    # Always run setupMigrations, don't short circuit
    updateAll = document._setupMigrations() or updateAll

  if updateAll
    Log.info "Migrations requested updating all references..."
    globals.Document.updateAll()
    Log.info "Done"

migrations = ->
  if globals.Document.Migrations.find({}, limit: 1).count() == 0
    globals.Document.Migrations.insert
      serial: 1
      migrationName: null
      oldCollectionName: null
      newCollectionName: null
      oldVersion: null
      newVersion: null
      timestamp: moment.utc().toDate()
      migrated: 0
      all: 0

  setupMigrations()

globals.Document.migrationsDisabled = !!process.env.PEERDB_MIGRATIONS_DISABLED
globals.Document.instanceDisabled = INSTANCES is 0
globals.Document.instances = INSTANCES

Meteor.startup ->
  # To try delayed references one last time, throwing any exceptions
  # (Otherwise setupObservers would trigger strange exceptions anyway)
  globals.Document.defineAll()

  Log.info "Skipped migrations" if globals.Document.migrationsDisabled
  # We still run the code to determine schema version and setup
  # observer to set schema version when inserting new documents,
  # but we then inside the code skip running migrations themselves
  migrations()

  if globals.Document.instanceDisabled
    Log.info "Skipped observers"
    # To make sure everything is really skipped
    PREFIX = []
  else
    if globals.Document.instances is 1
      Log.info "Enabling observers..."
    else
      Log.info "Enabling observers, instance #{ INSTANCE }/#{ globals.Document.instances }, matching ID prefix: #{ PREFIX.join '' }"
    setupObservers()
    Log.info "Done"

Document = globals.Document

assert globals.Document._ReferenceField.prototype instanceof globals.Document._TargetedFieldsObservingField
assert globals.Document._GeneratedField.prototype instanceof globals.Document._TargetedFieldsObservingField
