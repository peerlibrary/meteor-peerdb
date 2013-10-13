Document._Reference = class extends Document._Reference
  updateSource: (id, fields) =>
    selector = {}
    selector["#{ @sourceField }._id"] = id

    update = {}
    for field, value of fields
      if @isList
        field = "#{ @sourceField }.$.#{ field }"
      else
        field = "#{ @sourceField }.#{ field }"
      if _.isUndefined value
        update['$unset'] ?= {}
        update['$unset'][field] = ''
      else
        update['$set'] ?= {}
        update['$set'][field] = value

    @sourceCollection.update selector, update, multi: true

  removeSource: (id) =>
    selector = {}
    selector["#{ @sourceField }._id"] = id

    if @isList
      field = "#{ @sourceField }.$"
      update =
        $unset: {}
      update['$unset'][field] = ''

      # MongoDB supports removal of list elements only in two steps
      # First, we set all removed references to null
      @sourceCollection.update selector, update, multi: true

      # Then we remove all null elements
      selector = {}
      selector[@sourceField] = null
      update =
        $pull: {}
      update['$pull'][@sourceField] = null

      @sourceCollection.update selector, update, multi: true

    else
      @sourceCollection.remove selector

  setupObserver: =>
    fields =
      _id: 1 # In the case we want only id, that is, detect deletions
    for field in @fields
      fields[field] = 1

    @targetCollection.find({}, fields: fields).observeChanges
      added: (id, fields) =>
        return if _.isEmpty fields

        @updateSource id, fields

      changed: (id, fields) =>
        @updateSource id, fields

      removed: (id) =>
        @removeSource id

setupObservers = ->
  for document in Document.Meta.list
    for field, reference of document.Meta.fields
      reference.setupObserver()

Meteor.startup ->
  setupObservers()
