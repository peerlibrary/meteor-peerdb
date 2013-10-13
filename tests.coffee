Persons = new Meteor.Collection 'Persons', transform: (doc) => new Person doc
Posts = new Meteor.Collection 'Posts', transform: (doc) => new Post doc

if Meteor.isServer
  Meteor.publish null, ->
    Persons.find()
  Meteor.publish null, ->
    Posts.find()

class Person extends Document
  # Other fields:
  #   username
  #   displayName

  @Meta
    collection: Persons

class Post extends Document
  # Other fields:
  #   body

  @Meta
    collection: Posts
    fields:
      author: @Reference Person, ['username']
      subscribers: [@Reference Person]
      reviewers: [@Reference Person, ['username']]

# sleep function from fibers docs
sleep = (ms) ->
  Fiber = Npm.require 'fibers'
  fiber = Fiber.current
  setTimeout ->
    fiber.run()
  , ms
  Fiber.yield()

testAsyncMulti 'meteor-peerdb - queries', [
  (test, expect) ->
    test.equal Person.Meta.collection, Persons
    test.equal Person.Meta.fields, {}
    test.equal Post.Meta.collection, Posts
    test.instanceOf Post.Meta.fields.author, Person._Reference
    test.isFalse Post.Meta.fields.author.isArray
    test.equal Post.Meta.fields.author.sourceField, 'author'
    test.equal Post.Meta.fields.author.sourceDocument, Post
    test.equal Post.Meta.fields.author.targetDocument, Person
    test.equal Post.Meta.fields.author.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.author.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.author.fields, ['username']
    test.instanceOf Post.Meta.fields.subscribers, Person._Reference
    test.isTrue Post.Meta.fields.subscribers.isArray
    test.equal Post.Meta.fields.subscribers.sourceField, 'subscribers'
    test.equal Post.Meta.fields.subscribers.sourceDocument, Post
    test.equal Post.Meta.fields.subscribers.targetDocument, Person
    test.equal Post.Meta.fields.subscribers.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.subscribers.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.subscribers.fields, []
    test.isTrue Post.Meta.fields.reviewers.isArray
    test.equal Post.Meta.fields.reviewers.sourceField, 'reviewers'
    test.equal Post.Meta.fields.reviewers.sourceDocument, Post
    test.equal Post.Meta.fields.reviewers.targetDocument, Person
    test.equal Post.Meta.fields.reviewers.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.reviewers.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.reviewers.fields, ['username']

    test.equal Document.Meta.list, [Person, Post]

    Persons.insert
      username: 'person1'
      displayName: 'Person 1'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error
        test.isTrue person1Id
        @person1Id = person1Id

    Persons.insert
      username: 'person2'
      displayName: 'Person 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error
        test.isTrue person2Id
        @person2Id = person2Id

    Persons.insert
      username: 'person3'
      displayName: 'Person 3'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error
        test.isTrue person3Id
        @person3Id = person3Id
,
  (test, expect) ->
    @person1 = Persons.findOne @person1Id
    @person2 = Persons.findOne @person2Id
    @person3 = Persons.findOne @person3Id

    test.instanceOf @person1, Person
    test.equal @person1.username, 'person1'
    test.equal @person1.displayName, 'Person 1'
    test.instanceOf @person2, Person
    test.equal @person2.username, 'person2'
    test.equal @person2.displayName, 'Person 2'
    test.instanceOf @person3, Person
    test.equal @person3.username, 'person3'
    test.equal @person3.displayName, 'Person 3'

    Posts.insert
      author:
        _id: @person1._id
      subscribers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      body: 'FooBar'
    , expect (error, postId) =>
        test.isFalse error, error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # We inserted the document only with ids - subdocuments should be
    # automatically populated with additional fields as defined in @Reference
    test.equal @post,
      _id: @postId
      author:
        _id: @person1._id
        username: @person1.username
      # subscribers have only ids
      subscribers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      # But reviewers have usernames as well
      reviewers: [
        _id: @person2._id
        username: @person2.username
      ,
        _id: @person3._id
        username: @person3.username
      ]
      body: 'FooBar'

    Persons.update @person1Id,
      $set:
        username: 'person1a'
    , expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    Persons.update @person2Id,
      $set:
        username: 'person2a'
    , expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    Persons.update @person3Id,
      $set:
        username: 'person3a'
    , expect (error, res) =>
        test.isFalse error, error
        test.isTrue res
,
  (test, expect) ->
    @person1 = Persons.findOne @person1Id
    @person2 = Persons.findOne @person2Id
    @person3 = Persons.findOne @person3Id

    test.instanceOf @person1, Person
    test.equal @person1.username, 'person1a'
    test.equal @person1.displayName, 'Person 1'
    test.instanceOf @person2, Person
    test.equal @person2.username, 'person2a'
    test.equal @person2.displayName, 'Person 2'
    test.instanceOf @person3, Person
    test.equal @person3.username, 'person3a'
    test.equal @person3.displayName, 'Person 3'

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # All persons had usernames changed, they should
    # be updated in the post as well, automatically
    test.equal @post,
      _id: @postId
      author:
        _id: @person1._id
        username: @person1.username
      subscribers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
        username: @person2.username
      ,
        _id: @person3._id
        username: @person3.username
      ]
      body: 'FooBar'

    Persons.remove @person3Id

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # person3 was removed, references should be removed as well, automatically
    test.equal @post,
      _id: @postId
      author:
        _id: @person1._id
        username: @person1.username
      subscribers: [
        _id: @person2._id
      ]
      reviewers: [
        _id: @person2._id
        username: @person2.username
      ]
      body: 'FooBar'

    Persons.remove @person2Id

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
, (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # person2 was removed, references should be removed as well, automatically,
    # but lists should be kept as empty lists
    test.equal @post,
      _id: @postId
      author:
        _id: @person1._id
        username: @person1.username
      subscribers: []
      reviewers: []
      body: 'FooBar'

    Persons.remove @person1Id

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # If directly referenced document is removed, dependency is removed as well
    test.isFalse @post
]

Tinytest.add 'meteor-peerdb - invalid optional', (test) ->
  test.throws ->
    class BadPost extends Document
      @Meta
        collection: Posts
        fields:
          reviewers: [@Reference Person, ['username'], false]
  , /Only non-array values can be optional/

  # Invalid document should not be added to the list
  test.equal Document.Meta.list, [Person, Post]
