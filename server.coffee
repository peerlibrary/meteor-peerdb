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

MESSAGES_TTL = 60 # seconds

# We augment the cursor so that it matches our extra method in documents manager.
MeteorCursor = Object.getPrototypeOf(MongoInternals.defaultRemoteCollectionDriver().mongo.find()).constructor
MeteorCursor::exists = ->
  # You can only observe a tailable cursor.
  throw new Error "Cannot call exists on a tailable cursor" if @_cursorDescription.options.tailable

  unless @_synchronousCursorForExists
    # A special cursor with limit forced to 1 and fields to only _id.
    cursorDescription = _.clone @_cursorDescription
    cursorDescription.options = _.clone cursorDescription.options
    cursorDescription.options.limit = 1
    cursorDescription.options.fields =
      _id: 1
    @_synchronousCursorForExists = @_mongo._createSynchronousCursor cursorDescription,
      selfForIteration: @
      useTransform: false

  @_synchronousCursorForExists._rewind()
  !!@_synchronousCursorForExists._nextObject()

# Fields:
#   created
#   type
#   data
# We use a lower case collection name to signal it is a system collection
globals.Document.Messages = new Mongo.Collection 'peerdb.messages'

# Auto-expire messages after MESSAGES_TTL seconds
globals.Document.Messages._ensureIndex
  created: 1
,
  expireAfterSeconds: MESSAGES_TTL

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
globals.Document._observerCallback = (f) ->
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
    added: globals.Document._observerCallback (id, fields) =>
      @updateSource id, fields if updateAll or not initializing

  unless updateAll
    observers.changed = globals.Document._observerCallback (id, fields) =>
      @updateSource id, fields

    observers.removed = globals.Document._observerCallback (id) =>
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
    added: globals.Document._observerCallback (document) =>
      @trigger document, new @document({}) unless initializing

    changed: globals.Document._observerCallback (newDocument, oldDocument) =>
      @trigger newDocument, oldDocument

    removed: globals.Document._observerCallback (oldDocument) =>
      @trigger new @document({}), oldDocument

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
      Log.error "Document '#{ @sourceDocument.Meta._name }' '#{ id }' field '#{ @sourcePath }' was updated with an invalid value: #{ util.inspect value }"
      return

    # Only _id is requested, we do not have to do anything
    unless _.isEmpty @fields
      referenceFields = fieldsToProjection @fields
      target = @targetCollection.findOne value._id,
        fields: referenceFields
        transform: null

      unless target
        Log.error "Document '#{ @sourceDocument.Meta._name }' '#{ id }' field '#{ @sourcePath }' is referencing a nonexistent document '#{ value._id }'"
        # TODO: Should we call reference.removeSource here? And remove from reverse fields?
        return

      # We omit _id because that field cannot be changed, or even $set to the same value, but is in target
      @updateSource target._id, _.omit target, '_id'

    return unless @reverseName

    # TODO: Current code is run too many times, for any update of source collection reverse field is updated

    # We add other fields (@reverseFields) to the reverse field array only the first time,
    # when we are adding the new subdocument to the array. Keeping them updated later on is done
    # by reference fields configured through Meta._reverseFields. This assures subdocuments in
    # the reverse field array always match the schema, from the very beginning.

    selector =
      _id: value._id
    selector["#{ @reverseName }._id"] =
      $ne: id

    update = {}
    update[@reverseName] =
      _id: id

    # Only _id is requested, we do not have to do anything more
    unless _.isEmpty @reverseFields
      referenceFields = fieldsToProjection @reverseFields
      source = @sourceCollection.findOne id,
        fields: referenceFields
        transform: null

      unless source
        Log.error "Document '#{ @sourceDocument.Meta._name }' '#{ id }' document disappeared while fetching reverse fields for field '#{ @sourcePath }' ('#{ @reverseName }')"
        # TODO: Should we call reference.removeSource here? And remove from reverse fields?

        # No need adding it to the reverse field because it does not exist anymore.
        return

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

      query =
        _id:
          $nin: ids
      query["#{ field.reverseName }._id"] = id

      update = {}
      update[field.reverseName] =
        _id: id

      field.targetCollection.update query, {$pull: update}, multi: true

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
          Log.error "Document '#{ @Meta._name }' '#{ id }' field '#{ name }' was updated with a non-array value: #{ util.inspect value }"
          return
      else
        value = [value]

      for v in value
        field.updatedWithValue id, v

      if field.reverseName
        # In updatedWithValue we added possible new entry/ies to reverse fields, but here
        # we have also to remove those which were maybe removed from the value and are
        # not referencing anymore a document which got added the entry to its reverse
        # field in the past. So we make sure that only those documents which are still in
        # the value have the entry in their reverse fields by creating a query which pulls
        # the entry from all other.

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
      added: globals.Document._observerCallback (id, fields) =>
        @_sourceUpdated id, fields if updateAll or not initializing

    unless updateAll
      observers.changed = globals.Document._observerCallback (id, fields) =>
        @_sourceUpdated id, fields

    handle = @Meta.collection.find({}, fields: sourceFields).observeChanges observers

    initializing = false

    handle.stop() if updateAll

  @updateAll: ->
    sendMessage 'updateAll'

  @_updateAll: ->
    # It is only reasonable to run anything if this instance
    # is not disabled. Otherwise we would still go over all
    # documents, just we would not process any.
    return if globals.Document.instanceDisabled

    Log.info "Updating all references..."
    setupObservers true
    Log.info "Done"

  prepared = false
  prepareList = []
  started = false
  startList = []

  @prepare: (f) ->
    if prepared
      f()
    else
      prepareList.push f

  @runPrepare: ->
    assert not prepared
    prepared = true

    prepare() for prepare in prepareList
    return

  @startup: (f) ->
    if started
      f()
    else
      startList.push f

  @runStartup: ->
    assert not started
    started = true

    start() for start in startList
    return

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

sendMessage = (type, data) ->
  globals.Document.Messages.insert
    created: moment.utc().toDate()
    type: type
    data: data

setupMessages = ->
  initializing = true

  globals.Document.Messages.find({}).observeChanges
    added: (id, fields) ->
      return if initializing

      switch fields.type
        when 'updateAll'
          globals.Document._updateAll()
        else
          Log.error "Unknown message type '#{ fields.type }': " + util.inspect _.extend({}, {_id: id}, fields), false, null

  initializing = false

globals.Document.instanceDisabled = INSTANCES is 0
globals.Document.instances = INSTANCES

Meteor.startup ->
  # To try delayed references one last time, throwing any exceptions
  # (Otherwise setupObservers would trigger strange exceptions anyway)
  globals.Document.defineAll()

  # We first have to setup messages, so that migrations can run properly
  # (if they call updateAll, the message should be listened for)
  setupMessages() unless globals.Document.instanceDisabled

  globals.Document.runPrepare()

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

  globals.Document.runStartup()

Document = globals.Document

assert globals.Document._ReferenceField.prototype instanceof globals.Document._TargetedFieldsObservingField
assert globals.Document._GeneratedField.prototype instanceof globals.Document._TargetedFieldsObservingField
