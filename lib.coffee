class Document
  constructor: (doc) ->
    _.extend @, doc

  @_Reference: class
    constructor: (@targetDocument, @fields, @required) ->
      @fields ?= []
      @required ?= true

    contributeToClass: (@sourceDocument, @sourceField, @isArray) =>
      throw new Meteor.Error 500, "Only non-array values can be optional" if @isArray and not @required

  @Reference: (args...) ->
    new @_Reference args...

  @Meta: (meta) ->
    # First we store away the global list
    list = @Meta.list

    # Then we override Meta for the current document
    @Meta = meta
    @_initialize()

    # If initialization was successful, we register the current document into the global list (Document.Meta.list)
    list.push @

  @Meta.list = []

  @_initialize: ->
    fields = {}
    for field, reference of @Meta.fields or {}
      isArray = _.isArray reference
      reference = reference[0] if isArray
      reference.contributeToClass @, field, isArray
      fields[field] = reference
    @Meta.fields = fields

@Document = Document