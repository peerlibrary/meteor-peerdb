INVALID_TARGET = "Invalid target document or collection"

isPlainObject = (obj) ->
  if not _.isObject(obj) or _.isArray(obj) or _.isFunction(obj)
    return false

  if obj.constructor isnt Object
    return false

  return true

deepExtend = (obj, args...) ->
  _.each args, (source) ->
    _.each source, (value, key) ->
      if obj[key] and value and isPlainObject(obj[key]) and isPlainObject(value)
        obj[key] = deepExtend obj[key], value
      else
        obj[key] = value
  obj

startsWith = (string, start) ->
  string.lastIndexOf(start, 0) is 0

removePrefix = (string, prefix) ->
  string.substring prefix.length

class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Field: class
    contributeToClass: (@sourceDocument, @sourcePath, @ancestorArray) =>
      @sourceCollection = @sourceDocument.Meta.collection

    validate: =>
      throw new Error "Undefined source document" unless @sourceDocument
      throw new Error "Undefined source path" unless @sourcePath

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

    contributeToClass: (sourceDocument, sourcePath, ancestorArray) =>
      super sourceDocument, sourcePath, ancestorArray

      if @targetDocument is 'self'
        @targetDocument = @sourceDocument
        @targetCollection = @sourceCollection

      # Helpful values to know where and what the field is
      @inArray = @ancestorArray and startsWith @sourcePath, @ancestorArray
      @isArray = @ancestorArray and @sourcePath is @ancestorArray
      @arraySuffix = removePrefix @sourcePath, @ancestorArray if @inArray

    validate: =>
      super()

      throw new Error "Undefined target collection" unless @targetCollection
      throw new Error "Undefined target document" if _.isUndefined @targetDocument

  @_ReferenceField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocumentOrCollection, fields, @required) ->
      super targetDocumentOrCollection, fields

      @required ?= true

    contributeToClass: (sourceDocument, sourcePath, ancestorArray) =>
      super sourceDocument, sourcePath, ancestorArray

      throw new Error "Reference field directly in an array cannot be optional" if @ancestorArray and @sourcePath is @ancestorArray and not @required

  @ReferenceField: (args...) ->
    new @_ReferenceField args...

  @_GeneratedField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocumentOrCollection, fields, @generator) ->
      super targetDocumentOrCollection, fields

  @GeneratedField: (args...) ->
    new @_GeneratedField args...

  @Meta: (meta, dontList, throwErrors) ->
    originalMeta = @Meta

    if _.isFunction meta
      try
        @Meta = meta()
      catch e
        if not throwErrors and (e.message is INVALID_TARGET or e instanceof ReferenceError)
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

  @_ExtendMeta: (mixin, additionalMeta) ->
    mergeMeta = (first, second) ->
      deepExtend first, second

    unless _.isUndefined @Meta._delayed
      # We have been delayed
      [document, meta] = Document.Meta.delayed[@Meta._delayed]

      # Only functions can be delayed
      assert _.isFunction meta

      if _.isFunction additionalMeta
        newMeta = => additionalMeta meta()
      else
        newMeta = => mergeMeta meta(), additionalMeta

      if mixin
        # Let us just update the list
        Document.Meta.delayed[@Meta._delayed] = [@, newMeta]
      else
        @_addDelayed @, newMeta

      # @_retryDelayed is called inside @Meta as well below
      @_retryDelayed()

    else if not _.isUndefined @Meta._initialized
      # We have been already initialized
      document = Document.Meta.list[@Meta._initialized]

      # We remove it from the list because @Meta below will add it back
      Document.Meta.list.splice @Meta._initialized, 1 if mixin

      @Meta = document.Meta._meta
      metadata = document.Meta._metaData

      if _.isFunction document.Meta._metaData
        if _.isFunction additionalMeta
          @Meta => additionalMeta metadata()
        else
          @Meta => mergeMeta metadata(), additionalMeta
      else
        # We do not want to override metadata if it maybe shared among classes
        if _.isFunction additionalMeta
          @Meta => additionalMeta _.clone metadata
        else
          @Meta => mergeMeta _.clone(metadata), additionalMeta

    else
      # Not delayed and not initialized - there was some exception when initializing somewhere so we should not really get here
      assert false

  @ExtendMeta: (additionalMeta) ->
    @_ExtendMeta false, additionalMeta

  @MixinMeta: (additionalMeta) ->
    @_ExtendMeta true, additionalMeta

  @_processFields: (fields, parent, ancestorArray) ->
    ancestorArray = ancestorArray or null

    res = {}
    for name, field of fields or {}
      throw new Error "Field names cannot contain '.': #{ name }" if name.indexOf('.') isnt -1

      path = if parent then "#{ parent }.#{ name }" else name
      array = ancestorArray

      if _.isArray field
        throw new Error "Array field has to contain exactly one element, not #{ field.length }: #{ path }" if field.length isnt 1
        field = field[0]

        if array
          # TODO: Support nested arrays
          # See: https://jira.mongodb.org/browse/SERVER-831
          throw new Error "Field cannot be in a nested array: #{ path }"

        array = path

      if field instanceof @_Field
        field.contributeToClass @, path, array
        res[name] = field
      else if _.isObject field
        res[name] = @_processFields field, path, array
      else
        throw new Error "Invalid value for field: #{ path }"

    res

  @_initialize: ->
    @Meta.fields = @_processFields @Meta.fields

  @_addDelayed: (document, meta) ->
    Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

    Document.Meta.delayed.push [document, meta]
    # _delayed must be a subclass value, we do not want to change global Document.Meta
    document.Meta = class extends document.Meta
      @_delayed: Document.Meta.delayed.length - 1

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

  @_validateFields: (obj) ->
    for name, field of obj
      if field instanceof Document._Field
        field.validate()
      else
        @_validateFields field

  @validateAll: ->
    for document in Document.Meta.list
      @_validateFields document.Meta.fields

  @redefineAll: (throwErrors) ->
    Document._retryDelayed throwErrors

    for document, i in Document.Meta.list when _.isFunction document.Meta._metaData
      metadata = document.Meta._metaData
      document.Meta = document.Meta._meta
      document.Meta metadata, true
      document.Meta._initialized = i

    Document.validateAll()

@Document = Document
