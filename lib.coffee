INVALID_TARGET = "Invalid target document or collection"

class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Field: class
    contributeToClass: (@sourceDocument, @sourcePath, @isArray) =>
      @sourceCollection = @sourceDocument.Meta.collection

  @_ObservingField: class extends @_Field

  @_TargetedFieldsObservingField: class extends @_ObservingField
    constructor: (targetDocumentOrCollection, @fields) ->
      super()

      @fields ?= []

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

      if @targetDocument is 'self'
        @targetDocument = @sourceDocument
        @targetCollection = @sourceCollection

  @_ReferenceField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocumentOrCollection, fields, @required) ->
      super targetDocumentOrCollection, fields

      @required ?= true

    contributeToClass: (sourceDocument, sourcePath, isArray) =>
      super sourceDocument, sourcePath, isArray

      throw new Error "Only non-array fields can be optional" if @isArray and not @required

  @ReferenceField: (args...) ->
    new @_ReferenceField args...

  @_GeneratedField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocumentOrCollection, fields, @generator) ->
      super targetDocumentOrCollection, fields

    contributeToClass: (sourceDocument, sourcePath, isArray) =>
      super sourceDocument, sourcePath, isArray

      throw new Error "Generated fields cannot be array fields" if @isArray

  @GeneratedField: (args...) ->
    new @_GeneratedField args...

  @Meta: (meta, dontList, throwErrors) ->
    originalMeta = @Meta

    if _.isFunction meta
      try
        @Meta = meta()
      catch e
        if not throwErrors and (e.message == INVALID_TARGET or e instanceof ReferenceError)
          @_addDelayed @, meta
          return
        else
          throw e
    else
      @Meta = meta

    # Store original so othat we can rerun or extend
    # We can assign directly, because we overrode @Meta at this point
    @Meta._meta = originalMeta
    @Meta._metaData = meta

    @_initialize()

    # If initialization was successful, we register the current document into the global list (Document.Meta.list)
    unless dontList
      Document.Meta.list.push @
      # Store location in the list and that we have been successfully initialized
      @Meta._initialized = Document.Meta.list.length - 1

    @_retryDelayed()

  @Meta.list = []
  @Meta.delayed = []
  @Meta._delayedCheckTimeout = null

  @ExtendMeta = (additionalMeta) ->
    unless _.isUndefined @Meta._delayed
      # We have been delayed, let us just update the list
      [document, meta] = Document.Meta.delayed[@Meta._delayed]

      # Only functions can be delayed
      assert _.isFunction meta

      if _.isFunction additionalMeta
        Document.Meta.delayed[@Meta._delayed] = [@, => additionalMeta meta()]
      else
        Document.Meta.delayed[@Meta._delayed] = [@, => _.extend meta(), additionalMeta]

      # @_retryDelayed is called inside @Meta as well below
      @_retryDelayed()

    else if not _.isUndefined @Meta._initialized
      # We have been already initialized
      document = Document.Meta.list[@Meta._initialized]
      # We remove it from the list because @Meta below will add it back
      Document.Meta.list.splice @Meta._initialized, 1

      @Meta = document.Meta._meta
      metadata = document.Meta._metaData

      if _.isFunction document.Meta._metaData
        if _.isFunction additionalMeta
          @Meta => additionalMeta metadata()
        else
          @Meta => _.extend metadata(), additionalMeta
      else
        # We do not want to override metadata if it maybe shared among classes
        if _.isFunction additionalMeta
          @Meta => additionalMeta _.clone metadata
        else
          @Meta => _.extend {}, metadata, additionalMeta

    else
      # Not delayed and not initialized - there was some exception when initializing somewhere so we should not really get here
      assert false

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
    # TODO: What if there is a chain of extended classes which are all delayed, are we then overriding parent _delayed?
    if Document.Meta is document.Meta # We subclass only once
      # _delayed must be a subclass value, we do not want to change global Document.Meta
      document.Meta = class extends document.Meta
        @_delayed: Document.Meta.delayed.length - 1
    else
      # We have already subclassed, we can set _delayed directly
      document.Meta._delayed = Document.Meta.delayed.length - 1

    Document.Meta._delayedCheckTimeout = Meteor.setTimeout ->
      if Document.Meta.delayed.length
        delayed = [] # Display friendly list of delayed documents
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
      delete document.Meta._delayed if _.has document.Meta, '_delayed'
      document.Meta meta, false, throwErrors

  @redefineAll: (throwErrors) ->
    Document._retryDelayed throwErrors

    for document, i in Document.Meta.list when _.isFunction document.Meta._metaData
      metadata = document.Meta._metaData
      document.Meta = document.Meta._meta
      document.Meta metadata, true
      document.Meta._initialized = i

@Document = Document
