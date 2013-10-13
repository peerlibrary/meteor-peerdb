class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Reference: class
    constructor: (@targetCollection, @fields, @required) ->
      @fields ?= []
      @required ?= true

    contributeToClass: (@sourceCollection, @sourceField, @isArray) =>
      throw new Meteor.Error 500, "Only non-array values can be optional" if @isArray and not @required

  @Reference: (args...) ->
    new @_Reference args...

  @Meta: (meta) ->
    # First we register the current document into a global list (Document.Meta.list)
    @Meta.list.push @

    # Then we override Meta for the current document
    @Meta = meta
    @_initialize()

  @Meta.list = []

  @_initialize: ->
    fields = {}
    for field, reference of @Meta.fields or {}
      isArray = _.isArray reference
      reference = reference[0] if isArray
      reference.contributeToClass @Meta.collection, field, isArray
      fields[field] = reference
    @Meta.fields = fields

@Document = Document