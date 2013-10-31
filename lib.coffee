INVALID_TARGET = "Invalid target document or collection"

class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Field: class
    contributeToClass: (@sourceDocument, @sourcePath, @isArray) =>
      @sourceCollection = @sourceDocument.Meta.collection

  @_ObservingField: class extends @_Field

  @_Reference: class extends @_ObservingField
    constructor: (targetDocumentOrCollection, @fields, @required) ->
      super arguments...

      @fields ?= []
      @required ?= true

      if targetDocumentOrCollection is 'self'
        @targetDocument = 'self'
        @targetCollection = null
      else if _.isFunction(targetDocumentOrCollection) and new targetDocumentOrCollection instanceof Document
        @targetDocument = targetDocumentOrCollection
        @targetCollection = targetDocumentOrCollection.Meta.collection
      else if targetDocumentOrCollection
        @targetDocument = null
        @targetCollection = targetDocumentOrCollection
      else
        throw new Error INVALID_TARGET

    contributeToClass: (sourceDocument, sourcePath, isArray) =>
      super sourceDocument, sourcePath, isArray

      throw new Error "Only non-array values can be optional" if @isArray and not @required

      if @targetDocument is 'self'
        @targetDocument = @sourceDocument
        @targetCollection = @sourceCollection

  @Reference: (args...) ->
    new @_Reference args...

  @Meta: (meta, dontList, throwErrors) ->
    if _.isFunction meta
      originalMeta = @Meta
      try
        @Meta = meta()
        @Meta._meta = originalMeta
        @Meta._metaData = meta
      catch e
        if not throwErrors and (e.message == INVALID_TARGET or e instanceof ReferenceError)
          @_addDelayed @, meta
          return
        else
          throw e
    else
      @Meta = meta
    @_initialize()

    # If initialization was successful, we register the current document into the global list (Document.Meta.list)
    Document.Meta.list.push @ unless dontList

    @_retryDelayed()

  @Meta.list = []
  @Meta.delayed = []
  @Meta._delayedCheckTimeout = null

  @_processFields: (fields, parent) ->
    res = {}
    for name, field of fields or {}
      throw new Error "Field names cannot contain '.': #{ name }" if name.indexOf('.') isnt -1

      path = if parent then "#{ parent }.#{ name }" else name
      isArray = _.isArray field
      if not isArray and _.isObject(field) and not (field instanceof @_Field)
        res[name] = @_processFields field, path
      else
        if isArray
          throw new Error "Array field has to contain exactly one element, not #{ field.length }" if field.length isnt 1
          field = field[0]

        field.contributeToClass @, path, isArray
        res[name] = field
    res

  @_initialize: ->
    @Meta.fields = @_processFields @Meta.fields

  @_addDelayed: (document, meta) ->
    Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

    Document.Meta.delayed.push [document, meta]

    Document.Meta._delayedCheckTimeout = Meteor.setTimeout ->
      if Document.Meta.delayed.length
        delayed = []
        for [document, meta] in Document.Meta.delayed
          delayed.push document.name or document
        Log.error "Not all delayed document definitions were successfully retried: #{ delayed }"
    , 1000 # ms

  @_retryDelayed: (throwErrors) ->
    Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

    # We store the delayed list away, so that we can iterate over it
    delayed = Document.Meta.delayed
    # And set it back to empty list, document.Meta will populate it again as necessary
    Document.Meta.delayed = []
    for [document, meta] in delayed
      document.Meta meta, false, throwErrors

  @redefineAll: (throwErrors) ->
    Document._retryDelayed throwErrors

    for document in Document.Meta.list when document.Meta._meta
      metadata = document.Meta._metaData
      document.Meta = document.Meta._meta
      document.Meta metadata, true

@Document = Document
