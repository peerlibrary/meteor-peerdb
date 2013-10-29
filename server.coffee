Document._Reference = class extends Document._Reference
  updateSource: (id, fields) =>
    selector = {}
    selector["#{ @sourcePath }._id"] = id

    update = {}
    for field, value of fields
      if @isArray
        path = "#{ @sourcePath }.$.#{ field }"
      else
        path = "#{ @sourcePath }.#{ field }"
      if _.isUndefined value
        update['$unset'] ?= {}
        update['$unset'][path] = ''
      else
        update['$set'] ?= {}
        update['$set'][path] = value

    @sourceCollection.update selector, update, multi: true

  removeSource: (id) =>
    selector = {}
    selector["#{ @sourcePath }._id"] = id

    # If it is an array, we remove references
    if @isArray
      path = "#{ @sourcePath }.$"
      update =
        $unset: {}
      update['$unset'][path] = ''

      # MongoDB supports removal of array elements only in two steps
      # First, we set all removed references to null
      @sourceCollection.update selector, update, multi: true

      # Then we remove all null elements
      selector = {}
      selector[@sourcePath] = null
      update =
        $pull: {}
      update['$pull'][@sourcePath] = null

      @sourceCollection.update selector, update, multi: true

    # If it is an optional reference, we set it to null
    else if not @required
      update =
        $set: {}
      update['$set'][@sourcePath] = null

      @sourceCollection.update selector, update, multi: true

    # Else, we remove the whole document
    else
      @sourceCollection.remove selector

  setupTargetObservers: =>
    referenceFields =
      _id: 1 # In the case we want only id, that is, detect deletions
    for field in @fields
      referenceFields[field] = 1

    @targetCollection.find({}, fields: referenceFields).observeChanges
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

      # TODO: This is not triggered if required field simply do not exist or is set to undefined (does MongoDB support undefined value?)
      Log.warn "Document's '#{ id }' field '#{ reference.sourcePath }' was updated with invalid value: #{ util.inspect value }"
      return

    # Only _id is requested, we do not have to do anything
    return if _.isEmpty reference.fields

    referenceFields = {}
    for field in reference.fields
      referenceFields[field] = 1

    target = reference.targetCollection.findOne value._id,
      fields: referenceFields
      transform: null

    unless target
      Log.warn "Document's '#{ id }' field '#{ reference.sourcePath }' is referencing nonexistent document '#{ value._id }'"
      # TODO: Should we call reference.removeSource here?
      return

    reference.updateSource target._id, _.pick target, reference.fields

  @sourceFieldUpdated: (id, field, value, reference) ->
    # TODO: Should we check if field still exists but just value is undefined, so that it is the same as null? Or can this happen only when removing the field?
    return if _.isUndefined value

    reference = reference or @Meta.fields[field]

    # We should be subscribed only to those updates which are defined in @Meta.fields
    assert reference

    if reference instanceof Document._Reference
      if reference.isArray
        unless _.isArray value
          Log.warn "Document's '#{ id }' field '#{ field }' was updated with non-array value: #{ util.inspect value }"
          return
      else
        value = [value]

      for v in value
        @sourceFieldUpdatedWithValue id, reference, v
    else
      for f, r of reference
        @sourceFieldUpdated id, "#{ field }.#{ f }", value[f], r

  @sourceUpdated: (id, fields) ->
    for field, value of fields
      @sourceFieldUpdated id, field, value

  @setupSourceObservers: ->
    return if _.isEmpty @Meta.fields

    sourceFields = {}

    sourceFieldsWalker = (obj) ->
      for field, reference of obj
        if reference instanceof Document._Reference
          sourceFields[reference.sourcePath] = 1
        else
          sourceFieldsWalker reference

    sourceFieldsWalker @Meta.fields

    @Meta.collection.find({}, fields: sourceFields).observeChanges
      added: (id, fields) =>
        @sourceUpdated id, fields

      changed: (id, fields) =>
        @sourceUpdated id, fields

setupObservers = ->
  setupTargetObservers = (fields) ->
    for field, reference of fields
      # There are no arrays anymore here, just objects (for subdocuments) or references
      if reference instanceof Document._Reference
        reference.setupTargetObservers()
      else
        setupTargetObservers reference

  for document in Document.Meta.list
    setupTargetObservers document.Meta.fields
    document.setupSourceObservers()

Meteor.startup ->
  # To try delayed references one last time, this time we throw any exceptions
  # (Otherwise setupObservers would trigger strange exceptions anyway)
  Document._retryDelayed true

  setupObservers()
