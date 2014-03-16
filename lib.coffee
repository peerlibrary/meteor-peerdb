globals = @

RESERVED_FIELDS = ['document', 'parent']
INVALID_TARGET = "Invalid target document"
MAX_RETRIES = 1000

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

removeUndefined = (obj) ->
  assert isPlainObject obj

  res = {}
  for key, value of obj
    if _.isUndefined value
      continue
    else if isPlainObject value
      res[key] = removeUndefined value
    else
      res[key] = value
  res

startsWith = (string, start) ->
  string.lastIndexOf(start, 0) is 0

removePrefix = (string, prefix) ->
  string.substring prefix.length

getCurrentLocation = ->
  # TODO: Does this work on the client side as well? Should we use Log._getCallerDetails?
  lines = (new Error().stack).split('\n')
  thisFile = (lines[1].match(/\((.*\/.+\.(coffee|js)).*\)$/))[1]
  for line in lines[2..] when line.indexOf(thisFile) is -1
    return line.trim().replace(/^at\s*/, '')
  assert false

getCollection = (name, document, replaceParent) ->
  transform = (doc) => new document doc

  if _.isString(name)
    if Document._collections[name]
      methodHandlers = Document._collections[name]._connection.method_handlers or Document._collections[name]._connection._methodHandlers
      for method of methodHandlers
        if startsWith method, Document._collections[name]._prefix
          if replaceParent
            delete methodHandlers[method]
          else
            throw new Error "Reuse of a collection without replaceParent set"
      if Document._collections[name]._connection.registerStore
        if replaceParent
          delete Document._collections[name]._connection._stores[name]
        else
          throw new Error "Reuse of a collection without replaceParent set"
    collection = new Meteor.Collection name, transform: transform
    Document._collections[name] = collection
  else if name is null
    collection = new Meteor.Collection name, transform: transform
  else
    collection = name
    if collection._peerdb and not replaceParent
      throw new Error "Reuse of a collection without replaceParent set"
    collection._transform = Deps._makeNonreactive transform
    collection._peerdb = true

  collection

class globals.Document
  # TODO: When we will require all fields to be specified and have validator support to validate new objects, we can also run validation here and check all data, reference fields and others
  @objectify: (parent, ancestorArray, obj, fields) ->
    throw new Error "Document does not match schema, not a plain object" unless isPlainObject obj

    for name, field of fields
      # Not all fields are necessary provided
      continue unless obj[name]

      path = if parent then "#{ parent }.#{ name }" else name

      if field instanceof globals.Document._ReferenceField
        throw new Error "Document does not match schema, sourcePath does not match: #{ field.sourcePath } vs. #{ path }" if field.sourcePath isnt path

        if field.isArray
          throw new Error "Document does not match schema, not an array" unless _.isArray obj[name]
          obj[name] = _.map obj[name], (o) => new field.targetDocument o
        else
          throw new Error "Document does not match schema, ancestorArray does not match: #{ field.ancestorArray } vs. #{ ancestorArray }" if field.ancestorArray isnt ancestorArray
          throw new Error "Document does not match schema, not a plain object" unless isPlainObject obj[name]
          obj[name] = new field.targetDocument obj[name]

      else if isPlainObject field
        if _.isArray obj[name]
          throw new Error "Document does not match schema, an unexpected array" unless _.some field, (f) => f.ancestorArray is path
          throw new Error "Document does not match schema, nested arrays are not supported" if ancestorArray
          obj[name] = _.map obj[name], (o) => @objectify path, path, o, field
        else
          throw new Error "Document does not match schema, expected an array" if _.some field, (f) => f.ancestorArray is path
          obj[name] = @objectify path, ancestorArray, obj[name], field

    obj

  constructor: (doc) ->
    _.extend @, @constructor.objectify '', null, (doc or {}), (@constructor?.Meta?.fields or {})

  @_Field: class
    contributeToClass: (@sourceDocument, @sourcePath, @ancestorArray) =>
      @_metaLocation = @sourceDocument.Meta._location
      @sourceCollection = @sourceDocument.Meta.collection

    validate: =>
      throw new Error "Missing meta location" unless @_metaLocation
      throw new Error "Missing source path (from #{ @_metaLocation })" unless @sourcePath
      throw new Error "Missing source document (for #{ @sourcePath } from #{ @_metaLocation })" unless @sourceDocument
      throw new Error "Missing source collection (for #{ @sourcePath } from #{ @_metaLocation })" unless @sourceCollection
      throw new Error "Source document not defined (for #{ @sourcePath } from #{ @_metaLocation })" unless @sourceDocument.Meta._listIndex?

      assert not @sourceDocument.Meta._replaced
      assert not @sourceDocument.Meta._delayIndex?
      assert.equal @sourceDocument.Meta.document, @sourceDocument
      assert.equal @sourceDocument.Meta.document.Meta, @sourceDocument.Meta

  @_ObservingField: class extends @_Field

  @_TargetedFieldsObservingField: class extends @_ObservingField
    constructor: (targetDocument, @fields) ->
      super()

      @fields ?= []

      if targetDocument is 'self'
        @targetDocument = 'self'
        @targetCollection = null
      else if _.isFunction(targetDocument) and targetDocument.prototype instanceof globals.Document
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
      throw new Error "Target document not defined (for #{ @sourcePath } from #{ @_metaLocation })" unless @targetDocument.Meta._listIndex?

      assert not @targetDocument.Meta._replaced
      assert not @targetDocument.Meta._delayIndex?
      assert.equal @targetDocument.Meta.document, @targetDocument
      assert.equal @targetDocument.Meta.document.Meta, @targetDocument.Meta

  @_ReferenceField: class extends @_TargetedFieldsObservingField
    constructor: (targetDocument, fields, @required, @reverseName, @reverseFields) ->
      super targetDocument, fields

      @required ?= true
      @reverseName ?= null
      @reverseFields ?= []

    contributeToClass: (sourceDocument, sourcePath, ancestorArray) =>
      super sourceDocument, sourcePath, ancestorArray

      throw new Error "Reference field directly in an array cannot be optional (for #{ @sourcePath } from #{ @_metaLocation })" if @ancestorArray and @sourcePath is @ancestorArray and not @required

      return unless @reverseName

      # We return now because contributeToClass will be retried sooner or later with replaced document again
      return if @targetDocument.Meta._replaced

      for reverse in @targetDocument.Meta._reverseFields
        return if _.isEqual(reverse.reverseName, @reverseName) and _.isEqual(reverse.reverseFields, @reverseFields) and reverse.sourceDocument is @sourceDocument

      @targetDocument.Meta._reverseFields.push @

      # If target document is already defined, we queue it for a retry.
      # We do not queue children, because or children replace a parent
      # (and reverse fields will be defined there), or reference is
      # pointing to this target document and we want reverse defined
      # only once and only on exact target document and not its
      # children.
      if @targetDocument.Meta._listIndex?
        globals.Document.list.splice @targetDocument.Meta._listIndex, 1

        delete @targetDocument.Meta._replaced
        delete @targetDocument.Meta._listIndex

        # Renumber documents
        for doc, i in globals.Document.list
          doc.Meta._listIndex = i

        globals.Document._addDelayed @targetDocument

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
    return unless globals.Document._delayed.length

    @_clearDelayedCheck()

    globals.Document._delayedCheckTimeout = Meteor.setTimeout ->
      if globals.Document._delayed.length
        delayed = [] # Display friendly list of delayed documents
        for document in globals.Document._delayed
          delayed.push "#{ document.Meta._name } from #{ document.Meta._location }"
        Log.error "Not all delayed document definitions were successfully retried:\n#{ delayed.join('\n') }"
    , 1000 # ms

  @_clearDelayedCheck: ->
    Meteor.clearTimeout globals.Document._delayedCheckTimeout if globals.Document._delayedCheckTimeout

  @_processFields: (fields, parent, ancestorArray) ->
    assert fields
    assert isPlainObject fields

    ancestorArray = ancestorArray or null

    res = {}
    for name, field of fields
      throw new Error "Field names cannot contain '.' (for #{ name } from #{ @Meta._location })" if name.indexOf('.') isnt -1

      path = if parent then "#{ parent }.#{ name }" else name
      array = ancestorArray

      if _.isArray field
        throw new Error "Array field has to contain exactly one element, not #{ field.length } (for #{ path } from #{ @Meta._location })" if field.length isnt 1
        field = field[0]

        if array
          # TODO: Support nested arrays
          # See: https://jira.mongodb.org/browse/SERVER-831
          throw new Error "Field cannot be in a nested array (for #{ path } from #{ @Meta._location })"

        array = path

      if field instanceof globals.Document._Field
        field.contributeToClass @, path, array
        res[name] = field
      else if _.isObject field
        res[name] = @_processFields field, path, array
      else
        throw new Error "Invalid value for field (for #{ path } from #{ @Meta._location })"

    res

  @_fieldsUseDocument: (fields, document) ->
    assert fields
    assert isPlainObject fields

    for name, field of fields
      if field instanceof globals.Document._TargetedFieldsObservingField
        return true if field.sourceDocument is document
        return true if field.targetDocument is document
      else if field instanceof globals.Document._Field
        return true if field.sourceDocument is document
      else
        assert isPlainObject field
        return true if @_fieldsUseDocument field, document

    false

  @_retryAllUsing: (document) ->
    documents = globals.Document.list
    globals.Document.list = []

    for doc in documents
      if @_fieldsUseDocument doc.Meta.fields, document
        delete doc.Meta._replaced
        delete doc.Meta._listIndex
        @_addDelayed doc
      else
        globals.Document.list.push doc
        doc.Meta._listIndex = globals.Document.list.length - 1

  @_retryDelayed: (throwErrors) ->
    @_clearDelayedCheck()

    # We store the delayed list away, so that we can iterate over it
    delayed = globals.Document._delayed
    # And set it back to the empty list, we will add to it again as necessary
    globals.Document._delayed = []

    for document in delayed
      delete document.Meta._delayIndex

    processedCount = 0

    for document in delayed
      assert not document.Meta._listIndex?

      if document.Meta._replaced
        continue

      try
        fields = document.Meta._fields.call document, {}
        if fields and isPlainObject fields
          # We run _processFields first, so that _reverseFields for this document is populated as well
          document._processFields fields

          reverseFields = {}
          for reverse in document.Meta._reverseFields
            reverseFields[reverse.reverseName] = [globals.Document.ReferenceField reverse.sourceDocument, reverse.reverseFields]

          # And now we run _reverseFields for real on all fields
          document.Meta.fields = document._processFields _.extend fields, reverseFields
      catch e
        if not throwErrors and (e.message is INVALID_TARGET or e instanceof ReferenceError)
          @_addDelayed document
          continue
        else
          throw new Error "Invalid fields (from #{ document.Meta._location }): #{ if e.stack then "#{ e.stack }\n---" else e.stringOf?() or e }"

      throw new Error "No fields returned (from #{ document.Meta._location })" unless fields
      throw new Error "Returned fields should be a plain object (from #{ document.Meta._location })" unless isPlainObject fields

      if document.Meta.replaceParent and not document.Meta.parent?._replaced
        throw new Error "Replace parent set, but no parent known (from #{ document.Meta._location })" unless document.Meta.parent

        document.Meta.parent._replaced = true

        if document.Meta.parent._listIndex?
          globals.Document.list.splice document.Meta.parent._listIndex, 1
          delete document.Meta.parent._listIndex

          # Renumber documents
          for doc, i in globals.Document.list
            doc.Meta._listIndex = i

        else if document.Meta.parent._delayIndex?
          globals.Document._delayed.splice document.Meta.parent._delayIndex, 1
          delete document.Meta.parent._delayIndex

          # Renumber documents
          for doc, i in globals.Document._delayed
            doc.Meta._delayIndex = i

        @_retryAllUsing document.Meta.parent.document

      globals.Document.list.push document
      document.Meta._listIndex = globals.Document.list.length - 1
      delete document.Meta._delayIndex

      assert not document.Meta._replaced

      processedCount++

    @_setDelayedCheck()

    processedCount

  @_addDelayed: (document) ->
    @_clearDelayedCheck()

    assert not document.Meta._replaced
    assert not document.Meta._listIndex?

    globals.Document._delayed.push document
    document.Meta._delayIndex = globals.Document._delayed.length - 1

    @_setDelayedCheck()

  @_validateFields: (obj) ->
    for name, field of obj
      if field instanceof globals.Document._Field
        field.validate()
      else
        @_validateFields field

  @Meta: (meta) ->
    for field in RESERVED_FIELDS or startsWith field, '_'
      throw "Reserved meta field name: #{ field }" if field of meta

    throw new Error "Missing document name" unless meta.name
    throw new Error "Document name does not match class name" if @name and @name isnt meta.name
    throw new Error "replaceParent set without a parent" if meta.replaceParent and not @Meta._name

    name = meta.name
    currentFields = meta.fields or (fs) -> fs
    meta = _.omit meta, 'name', 'fields'
    meta._name = name # "name" is a reserved property name on functions in some environments (eg. node.js), so we use "_name"
    # For easier debugging and better error messages
    meta._location = getCurrentLocation()
    meta.document = @

    if meta.collection is null or meta.collection
      meta.collection = getCollection meta.collection, @, meta.replaceParent
    else
      meta.collection = getCollection "#{ name }s", @, meta.replaceParent

    parentMeta = @Meta

    if @Meta._name
      meta.parent = parentMeta

    if parentMeta._fields
      fields = (fs) ->
        newFs = parentMeta._fields fs
        removeUndefined deepExtend fs, newFs, currentFields newFs
    else
      fields = currentFields

    meta._fields = fields # Fields function

    if not meta.replaceParent
      # If we are not replacing the parent, we override _reverseFields with an empty set
      # because we want reverse fields only on exact target document and not its children.
      meta._reverseFields = []
    else
      meta._reverseFields = _.clone parentMeta._reverseFields

    clonedParentMeta = -> parentMeta.apply @, arguments
    filteredParentMeta = _.omit parentMeta, '_listIndex', '_delayIndex', '_replaced', 'parent', 'replaceParent'
    @Meta = _.extend clonedParentMeta, filteredParentMeta, meta

    assert @Meta._reverseFields

    @documents = new @_Manager @Meta

    @_addDelayed @
    @_retryDelayed()

  @list = []
  @_delayed = []
  @_delayedCheckTimeout = null
  @_collections = {}

  @validateAll: ->
    for document in globals.Document.list
      throw new Error "Missing fields (from #{ document.Meta._location })" unless document.Meta.fields
      @_validateFields document.Meta.fields

  @defineAll: (dontThrowDelayedErrors) ->
    for i in [0..MAX_RETRIES]
      if i is MAX_RETRIES
        throw new Error "Possible infinite loop" unless dontThrowDelayedErrors
        break

      globals.Document._retryDelayed not dontThrowDelayedErrors

      break unless globals.Document._delayed.length

    globals.Document.validateAll()

    assert dontThrowDelayedErrors or globals.Document._delayed.length is 0

Document = globals.Document

assert globals.Document._ReferenceField.prototype instanceof globals.Document._TargetedFieldsObservingField
assert globals.Document._GeneratedField.prototype instanceof globals.Document._TargetedFieldsObservingField
