RESERVED_FIELDS = ['list', 'parent', 'delayed']
INVALID_TARGET = "Invalid target document"

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

getCurrentLocation = ->
  # TODO: Does this work on the client side as well? Should we use Log._getCallerDetails?
  lines = (new Error().stack).split('\n')
  thisFile = (lines[2].match(/\((.*peerdb\/lib\.coffee).*\)$/))[1]
  for line in lines[1..] when line.indexOf(thisFile) is -1
    return line.trim().replace(/^at\s*/, '')

collections = {}
getCollection = (name, document) ->
  transform = (doc) => new document doc

  if collections[name]
    collection = _.clone collections[name]
    collection._transform = Deps._makeNonreactive transform
  else
    collection = new Meteor.Collection name, transform: transform
    collections[name] = collection

  collection

class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Field: class
    contributeToClass: (@sourceDocument, @sourcePath, @ancestorArray) =>
      @_metaLocation = @sourceDocument._metaLocation
      @sourceCollection = @sourceDocument.Meta.collection

    validate: =>
      throw new Error "Missing meta location" unless @_metaLocation
      throw new Error "Missing source path (from #{ @_metaLocation })" unless @sourcePath
      throw new Error "Missing source document (for #{ @sourcePath } from #{ @_metaLocation })" unless @sourceDocument
      throw new Error "Missing source collection (for #{ @sourcePath } from #{ @_metaLocation })" unless @sourceCollection

  @_ObservingField: class extends @_Field

  @_TargetedFieldsObservingField: class extends @_ObservingField
    constructor: (targetDocument, @fields) ->
      super()

      @fields ?= []

      if targetDocument is 'self'
        @targetDocument = 'self'
        @targetCollection = null
      else if _.isFunction(targetDocument) and new targetDocument() instanceof Document
        @targetDocument = targetDocument
        @targetCollection = targetDocument.Meta.collection
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

      throw new Error "Missing target document (for #{ @sourcePath } from #{ @_metaLocation })" unless @targetDocument
      throw new Error "Missing target collection (for #{ @sourcePath } from #{ @_metaLocation })" unless @targetCollection

  @_ReferenceField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocument, fields, @required) ->
      super targetDocument, fields

      @required ?= true

    contributeToClass: (sourceDocument, sourcePath, ancestorArray) =>
      super sourceDocument, sourcePath, ancestorArray

      throw new Error "Reference field directly in an array cannot be optional (for #{ @sourcePath } from #{ @_metaLocation })" if @ancestorArray and @sourcePath is @ancestorArray and not @required

  @ReferenceField: (args...) ->
    new @_ReferenceField args...

  @_GeneratedField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocument, fields, @generator) ->
      super targetDocument, fields

  @GeneratedField: (args...) ->
    new @_GeneratedField args...

  @_Manager: class
    constructor: (@meta) ->

    find: (args...) =>
      @meta.collection.find args...

    findOne: (args...) =>
      @meta.collection.findOne args...

    insert: (args...) =>
      @meta.collection.insert args...

    update: (args...) =>
      @meta.collection.update args...

    upsert: (args...) =>
      @meta.collection.upsert args...

    remove: (args...) =>
      @meta.collection.remove args...

  @_setDelayedCheck: ->
    return unless Document.Meta.delayed.length

    @_clearDelayedCheck()

    Document.Meta._delayedCheckTimeout = Meteor.setTimeout ->
      if Document.Meta.delayed.length
        delayed = [] # Display friendly list of delayed documents
        for [document, fields] in Document.Meta.delayed
          delayed.push "#{ document.Meta._name } from #{ document._metaLocation }"
        Log.error "Not all delayed document definitions were successfully retried:\n#{ delayed.join('\n') }"
    , 1000 # ms

  @_clearDelayedCheck: ->
    Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

  @_processFields: (fields, parent, ancestorArray) ->
    assert fields
    assert isPlainObject fields

    ancestorArray = ancestorArray or null

    res = {}
    for name, field of fields
      throw new Error "Field names cannot contain '.' (for #{ name } from #{ @_metaLocation })" if name.indexOf('.') isnt -1

      path = if parent then "#{ parent }.#{ name }" else name
      array = ancestorArray

      if _.isArray field
        throw new Error "Array field has to contain exactly one element, not #{ field.length } (for #{ path } from #{ @_metaLocation })" if field.length isnt 1
        field = field[0]

        if array
          # TODO: Support nested arrays
          # See: https://jira.mongodb.org/browse/SERVER-831
          throw new Error "Field cannot be in a nested array (for #{ path } from #{ @_metaLocation })"

        array = path

      if field instanceof @_Field
        field.contributeToClass @, path, array
        res[name] = field
      else if _.isObject field
        res[name] = @_processFields field, path, array
      else
        throw new Error "Invalid value for field (for #{ path } from #{ @_metaLocation })"

    res

  @_retryDelayed: (throwErrors) ->
    @_clearDelayedCheck()

    # We store the delayed list away, so that we can iterate over it
    delayed = Document.Meta.delayed
    # And set it back to the empty list, we will add to it again as necessary
    Document.Meta.delayed = []

    for [document, fieldsFunction] in delayed
      try
        fields = fieldsFunction.call document, {}
      catch e
        if not throwErrors and (e.message is INVALID_TARGET or e instanceof ReferenceError)
          @_addDelayed document, fieldsFunction
          continue
        else
          throw new Error "Invalid fields (from #{ document._metaLocation }): #{ if e.stack then "#{ e.stack }\n---" else e.stringOf?() or e }"

      throw new Error "No fields returned (from #{ document._metaLocation })" unless fields
      throw new Error "Returned fields should be a plain object (from #{ document._metaLocation })" unless isPlainObject fields

      document.Meta.fields = document._processFields fields

    @_setDelayedCheck()

  @_addDelayed: (document, fields) ->
    @_clearDelayedCheck()

    Document.Meta.delayed.push [document, fields]

    @_setDelayedCheck()

  @_validateFields: (obj) ->
    for name, field of obj
      if field instanceof Document._Field
        field.validate()
      else
        @_validateFields field

  @Meta: (meta) ->
    # For easier debugging and better error messages
    @_metaLocation = getCurrentLocation()

    for field in RESERVED_FIELDS or startsWith field, '_'
      throw "Reserved meta field name: #{ field }" if field of meta

    throw new Error "Missing document name" unless meta.name
    throw new Error "Document name does not match class name" if @name and @name isnt meta.name

    name = meta.name
    currentFields = meta.fields or (fs) -> fs
    parentFields = @Meta._fields
    if parentFields
      fields = (fs) -> currentFields parentFields fs
    else
      fields = currentFields

    meta = _.omit meta, 'name', 'fields'
    meta._fields = fields # Fields function
    meta._name = name # "name" is a reserved property name on functions in some environments (eg. node.js), so we use "_name"

    if _.isString meta.collection
      meta.collection = getCollection meta.collection, @
    else if not meta.collection
      meta.collection = getCollection "#{ name }s", @

    if @Meta._name
      meta.parent = @Meta

    parentMeta = @Meta
    clonedParentMeta = -> parentMeta.apply @, arguments
    @Meta = _.extend clonedParentMeta, @Meta, meta

    @documents = new @_Manager @Meta

    @_addDelayed @, fields

    Document.Meta.list.push @

    @_retryDelayed()

  @Meta.list = []
  @Meta.delayed = []
  @Meta._delayedCheckTimeout = null

  @validateAll: ->
    for document in Document.Meta.list
      throw new Error "Missing fields (from #{ document._metaLocation })" unless document.Meta.fields
      @_validateFields document.Meta.fields

  @defineAll: (dontThrowErrors) ->
    Document._retryDelayed not dontThrowErrors
    Document.validateAll()

@Document = Document
