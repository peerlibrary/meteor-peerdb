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
catchErrors = (f) ->
  return (args...) ->
    try
      f args...
    catch e
      Log.error "PeerDB exception: #{ e }: #{ util.inspect args, depth: 10 }"

Document._TargetedFieldsObservingField = class extends Document._TargetedFieldsObservingField
  setupTargetObservers: =>
    referenceFields = fieldsToProjection @fields
    @targetCollection.find({}, fields: referenceFields).observeChanges
      added: catchErrors (id, fields) =>
        @updateSource id, fields

      changed: catchErrors (id, fields) =>
        @updateSource id, fields

      removed: catchErrors (id) =>
        @removeSource id

# Have to refresh with new methods from TargetedFieldsObservingField
_.extend Document._ReferenceField.prototype,
  _.omit(Document._TargetedFieldsObservingField.prototype, 'constructor'),
  _.omit(Document._ReferenceField.prototype, 'constructor')
_.extend Document._GeneratedField.prototype,
  _.omit(Document._TargetedFieldsObservingField.prototype, 'constructor'),
  _.omit(Document._GeneratedField.prototype, 'constructor')

Document._ReferenceField = class extends Document._ReferenceField
  updateSource: (id, fields) =>
    # Just to be sure
    return if _.isEmpty fields

    selector = {}
    selector["#{ @sourcePath }._id"] = id

    update = {}
    for field, value of fields
      selectorPath = "#{ @sourcePath }.#{ field }"
      if @inArray
        path = "#{ @ancestorArray }.$#{ @arraySuffix }.#{ field }"
      else
        path = selectorPath

      if _.isUndefined value
        update.$unset ?= {}
        update.$unset[path] = ''

        s = {}
        if @inArray
          # We have cannot use top-level $or with $elemMatch so we do it differently than for $and below
          # See: https://jira.mongodb.org/browse/SERVER-11537

          selector[@ancestorArray] ?= {}
          selector[@ancestorArray].$elemMatch ?=
            $or: []

          # We have to repeat id selector here as well
          # See: https://jira.mongodb.org/browse/SERVER-11536
          s["#{ @arraySuffix }._id".substring(1)] = id
          # Remove initial dot with substring(1)
          s["#{ @arraySuffix }.#{ field }".substring(1)] =
            $exists: true

          selector[@ancestorArray].$elemMatch.$or.push s
        else
          s[selectorPath] =
            $exists: true

          selector.$or ?= []
          selector.$or.push s
      else
        update.$set ?= {}
        update.$set[path] = value

        s = {}
        if @inArray
          s[@ancestorArray] =
            $elemMatch: {}
          # We have to repeat id selector here as well
          # See: https://jira.mongodb.org/browse/SERVER-11536
          s[@ancestorArray].$elemMatch["#{ @arraySuffix }._id".substring(1)] = id
          # Remove initial dot with substring(1)
          s[@ancestorArray].$elemMatch["#{ @arraySuffix }.#{ field }".substring(1)] =
            $ne: value
        else
          s[selectorPath] =
            $ne: value

        selector.$and ?= []
        selector.$and.push s

    # $ operator updates only the first matching element in the array.
    # So if we are in the array, we have to loop until nothing changes.
    # See: https://jira.mongodb.org/browse/SERVER-1243
    loop
      break unless @sourceCollection.update selector, update, multi: true
      break unless @inArray

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
    return if _.isEmpty @fields

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

Document._GeneratedField = class extends Document._GeneratedField
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

Document = class extends Document
  @_sourceFieldUpdated: (id, name, value, field) ->
    # TODO: Should we check if field still exists but just value is undefined, so that it is the same as null? Or can this happen only when removing the field?
    return if _.isUndefined value

    field = field or @Meta.fields[name]

    # We should be subscribed only to those updates which are defined in @Meta.fields
    assert field

    if field instanceof Document._ObservingField
      if field.ancestorArray and name is field.ancestorArray
        unless _.isArray value
          Log.error "Document's '#{ id }' field '#{ name }' was updated with a non-array value: #{ util.inspect value }"
          return
      else
        value = [value]

      for v in value
        field.updatedWithValue id, v

    else if field not instanceof Document._Field
      value = [value] unless _.isArray value

      # If value is an array but it should not be, we cannot do much else.
      # Same goes if the value does not match structurally fields.
      for v in value
        for n, f of field
          # TODO: Should we skip calling @_sourceFieldUpdated if we already called it with exactly the same parameters this run?
          @_sourceFieldUpdated id, "#{ name }.#{ n }", v[n], f

  @_sourceUpdated: (id, fields) ->
    for name, value of fields
      @_sourceFieldUpdated id, name, value

  @setupSourceObservers: ->
    return if _.isEmpty @Meta.fields

    sourceFields =
      _id: 1 # To make sure we do not pass empty set of fields

    sourceFieldsWalker = (obj) ->
      for name, field of obj
        if field instanceof Document._ObservingField
          sourceFields[field.sourcePath] = 1
        else if field not instanceof Document._Field
          sourceFieldsWalker field

    sourceFieldsWalker @Meta.fields

    @Meta.collection.find({}, fields: sourceFields).observeChanges
      added: catchErrors (id, fields) =>
        @_sourceUpdated id, fields

      changed: catchErrors (id, fields) =>
        @_sourceUpdated id, fields

  @setupMigrations: ->
    @Meta.collection.find({}, fields: _id: 1).observeChanges
      added: catchErrors (id, fields) =>
        @Meta.collection.update id,
          $set:
            _schema: '1.0.0'

setupObservers = ->
  setupTargetObservers = (fields) ->
    for name, field of fields
      # There are no arrays anymore here, just objects (for subdocuments) or fields
      if field instanceof Document._ObservingField
        field.setupTargetObservers()
      else if field not instanceof Document._Field
        setupTargetObservers field

  for document in Document.Meta.list
    setupTargetObservers document.Meta.fields
    document.setupSourceObservers()

setupMigrations = ->
  for document in Document.Meta.list
    document.setupMigrations()

migrations = ->
  # We use a lower case collection name to signal it is a system collection
  Migrations = new Meteor.Collection 'migrations'

  # We fake support for migrations which will come in later versions
  if Migrations.find({}, limit: 1).count() == 0
    Migrations.insert
      serial: 1
      timestamp: moment.utc().toDate()
      all: 0
      migrated: 0

  setupMigrations()

Meteor.startup ->
  # To try delayed references one last time, this time we throw any exceptions
  # (Otherwise setupObservers would trigger strange exceptions anyway)
  Document._retryDelayed true

  migrations()

  # TODO: Use official API when it will be available: https://github.com/meteor/meteor/issues/180
  if process.env.NODE_ENV is 'production' or Meteor.settings?.production or Meteor.settings?.public?.production
    # Setup observers and run all initial updates in blocking mode on production
    setupObservers()
  else
    # Otherwise do it in the background
    Meteor.defer ->
      setupObservers()
