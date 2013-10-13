Document._Reference = class extends Document._Reference
  updateSource: (id, fields) =>
    selector = {}
    selector["#{ @sourceField }._id"] = id

    update = {}
    for field, value of fields
      if @isArray
        field = "#{ @sourceField }.$.#{ field }"
      else
        field = "#{ @sourceField }.#{ field }"
      if _.isUndefined value
        update['$unset'] ?= {}
        update['$unset'][field] = ''
      else
        update['$set'] ?= {}
        update['$set'][field] = value

    @sourceDocument.Meta.collection.update selector, update, multi: true

  removeSource: (id) =>
    selector = {}
    selector["#{ @sourceField }._id"] = id

    if @isArray
      field = "#{ @sourceField }.$"
      update =
        $unset: {}
      update['$unset'][field] = ''

      # MongoDB supports removal of array elements only in two steps
      # First, we set all removed references to null
      @sourceDocument.Meta.collection.update selector, update, multi: true

      # Then we remove all null elements
      selector = {}
      selector[@sourceField] = null
      update =
        $pull: {}
      update['$pull'][@sourceField] = null

      @sourceDocument.Meta.collection.update selector, update, multi: true

    else
      @sourceDocument.Meta.collection.remove selector

  setupTargetObservers: =>
    referenceFields =
      _id: 1 # In the case we want only id, that is, detect deletions
    for field in @fields
      referenceFields[field] = 1

    @targetDocument.Meta.collection.find({}, fields: referenceFields).observeChanges
      added: (id, fields) =>
        return if _.isEmpty fields

        @updateSource id, fields

      changed: (id, fields) =>
        @updateSource id, fields

      removed: (id) =>
        @removeSource id

Document = class extends Document
  @sourceFieldUpdatedWithValue: (id, reference, value) ->

    unless _.isObject(value) and _.isString(value._id)
      # Special case: when elements are being deleted from the array they are temporary set to null value, so we are ignoring this
      return if _.isNull(value) and reference.isArray

      # Optional field
      return if _.isNull(value) and not reference.required

      Log.warn "Document's '#{ id }' field '#{ reference.sourceField }' was updated with invalid value: #{ util.inspect value }"
      return

    # Only _id is requested, we do not have to do anything
    return if _.isEmpty reference.fields

    referenceFields = {}
    for field in reference.fields
      referenceFields[field] = 1

    target = reference.targetDocument.Meta.collection.findOne value._id,
      fields: referenceFields
      transform: null

    unless target
      Log.warn "Document's '#{ id }' field '#{ reference.sourceField }' is referencing nonexistent document '#{ value._id }'"
      # TODO: Should we call reference.removeSource here?
      return

    reference.updateSource target._id, _.pick target, reference.fields

  @sourceFieldUpdated: (id, field, value) ->
    return if _.isUndefined value

    reference = @Meta.fields[field]
    if reference.isArray
      unless _.isArray value
        Log.warn "Document's '#{ id }' field '#{ field }' was updated with non-array value: #{ util.inspect value }"
        return
    else
      value = [value]

    for v in value
      @sourceFieldUpdatedWithValue(id, reference, v)

  @sourceUpdated: (id, fields) ->
    for field, value of fields
      @sourceFieldUpdated id, field, value

  @setupSourceObservers: ->
    return if _.isEmpty @Meta.fields

    sourceFields = {}
    for field, reference of @Meta.fields
      sourceFields[reference.sourceField] = 1

    @Meta.collection.find({}, fields: sourceFields).observeChanges
      added: (id, fields) =>
        @sourceUpdated id, fields

      changed: (id, fields) =>
        @sourceUpdated id, fields

setupObservers = ->
  for document in Document.Meta.list
    for field, reference of document.Meta.fields
      reference.setupTargetObservers()

    document.setupSourceObservers()

Meteor.startup ->
  setupObservers()
