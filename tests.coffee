Persons = new Meteor.Collection 'Persons', transform: (doc) => new Person doc
Posts = new Meteor.Collection 'Posts', transform: (doc) => new Post doc
UserLinks = new Meteor.Collection 'UserLinks', transform: (doc) => new UserLink doc
CircularFirsts = new Meteor.Collection 'CircularFirsts', transform: (doc) => new CircularFirst doc
CircularSeconds = new Meteor.Collection 'CircularSeconds', transform: (doc) => new CircularSecond doc
Recursives = new Meteor.Collection 'Recursives', transform: (doc) => new Recursive doc

if Meteor.isServer
  # Initialize the database
  Persons.remove {}
  Posts.remove {}
  UserLinks.remove {}
  CircularFirsts.remove {}
  CircularSeconds.remove {}
  Recursives.remove {}
  Meteor.users.remove {}

  Meteor.publish null, ->
    Persons.find()
  Meteor.publish null, ->
    Posts.find()
  Meteor.publish null, ->
    UserLinks.find()
  Meteor.publish null, ->
    CircularFirsts.find()
  Meteor.publish null, ->
    CircularSeconds.find()
  Meteor.publish null, ->
    Recursives.find()

# The order of documents here tests delayed definitions

class Post extends Document
  # Other fields:
  #   body

  @Meta =>
    collection: Posts
    fields:
      # We can reference other document
      author: @Reference Person, ['username']
      # Or an array of documents
      subscribers: [@Reference Person]
      reviewers: [@Reference Person, ['username']]

class UserLink extends Document
  @Meta
    collection: UserLinks
    fields:
      # We can reference just a collection
      user: @Reference Meteor.users, ['username'], false

class CircularFirst extends Document
  # Other fields:
  #   content

  @Meta =>
    collection: CircularFirsts
    fields:
      # We can reference circular documents
      second: @Reference CircularSecond, ['content']

class CircularSecond extends Document
  # Other fields:
  #   content

  @Meta =>
    collection: CircularSeconds
    fields:
      # But of course one should not be required so that we can insert without warnings
      first: @Reference CircularFirst, ['content'], false

class Person extends Document
  # Other fields:
  #   username
  #   displayName

  @Meta
    collection: Persons

class Recursive extends Document
  # Other fields:
  #   content

  @Meta
    collection: Recursives
    fields:
      other: @Reference 'self', ['content'], false

Document.redefineAll()

# sleep function from fibers docs
sleep = (ms) ->
  Fiber = Npm.require 'fibers'
  fiber = Fiber.current
  setTimeout ->
    fiber.run()
  , ms
  Fiber.yield()

testAsyncMulti 'meteor-peerdb - references', [
  (test, expect) ->
    test.equal Person.Meta.collection, Persons
    test.equal Person.Meta.fields, {}

    test.equal Post.Meta.collection, Posts
    test.instanceOf Post.Meta.fields.author, Person._Reference
    test.isFalse Post.Meta.fields.author.isArray
    test.isTrue Post.Meta.fields.author.required
    test.equal Post.Meta.fields.author.sourceField, 'author'
    test.equal Post.Meta.fields.author.sourceDocument, Post
    test.equal Post.Meta.fields.author.targetDocument, Person
    test.equal Post.Meta.fields.author.sourceCollection, Posts
    test.equal Post.Meta.fields.author.targetCollection, Persons
    test.equal Post.Meta.fields.author.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.author.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.author.fields, ['username']
    test.instanceOf Post.Meta.fields.subscribers, Person._Reference
    test.isTrue Post.Meta.fields.subscribers.isArray
    test.isTrue Post.Meta.fields.subscribers.required
    test.equal Post.Meta.fields.subscribers.sourceField, 'subscribers'
    test.equal Post.Meta.fields.subscribers.sourceDocument, Post
    test.equal Post.Meta.fields.subscribers.targetDocument, Person
    test.equal Post.Meta.fields.subscribers.sourceCollection, Posts
    test.equal Post.Meta.fields.subscribers.targetCollection, Persons
    test.equal Post.Meta.fields.subscribers.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.subscribers.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.subscribers.fields, []
    test.isTrue Post.Meta.fields.reviewers.isArray
    test.isTrue Post.Meta.fields.reviewers.required
    test.equal Post.Meta.fields.reviewers.sourceField, 'reviewers'
    test.equal Post.Meta.fields.reviewers.sourceDocument, Post
    test.equal Post.Meta.fields.reviewers.targetDocument, Person
    test.equal Post.Meta.fields.reviewers.sourceCollection, Posts
    test.equal Post.Meta.fields.reviewers.targetCollection, Persons
    test.equal Post.Meta.fields.reviewers.sourceDocument.Meta.collection, Posts
    test.equal Post.Meta.fields.reviewers.targetDocument.Meta.collection, Persons
    test.equal Post.Meta.fields.reviewers.fields, ['username']

    test.equal UserLink.Meta.collection, UserLinks
    test.instanceOf UserLink.Meta.fields.user, UserLink._Reference
    test.isFalse UserLink.Meta.fields.user.isArray
    test.isFalse UserLink.Meta.fields.user.required
    test.equal UserLink.Meta.fields.user.sourceField, 'user'
    test.equal UserLink.Meta.fields.user.sourceDocument, UserLink
    test.equal UserLink.Meta.fields.user.targetDocument, null # We are referencing just a collection
    test.equal UserLink.Meta.fields.user.sourceCollection, UserLinks
    test.equal UserLink.Meta.fields.user.targetCollection, Meteor.users
    test.equal UserLink.Meta.fields.user.sourceDocument.Meta.collection, UserLinks
    test.equal UserLink.Meta.fields.user.fields, ['username']

    test.equal CircularFirst.Meta.collection, CircularFirsts
    test.instanceOf CircularFirst.Meta.fields.second, CircularFirst._Reference
    test.isFalse CircularFirst.Meta.fields.second.isArray
    test.isTrue CircularFirst.Meta.fields.second.required
    test.equal CircularFirst.Meta.fields.second.sourceField, 'second'
    test.equal CircularFirst.Meta.fields.second.sourceDocument, CircularFirst
    test.equal CircularFirst.Meta.fields.second.targetDocument, CircularSecond
    test.equal CircularFirst.Meta.fields.second.sourceCollection, CircularFirsts
    test.equal CircularFirst.Meta.fields.second.targetCollection, CircularSeconds
    test.equal CircularFirst.Meta.fields.second.sourceDocument.Meta.collection, CircularFirsts
    test.equal CircularFirst.Meta.fields.second.targetDocument.Meta.collection, CircularSeconds
    test.equal CircularFirst.Meta.fields.second.fields, ['content']

    test.equal CircularSecond.Meta.collection, CircularSeconds
    test.instanceOf CircularSecond.Meta.fields.first, CircularSecond._Reference
    test.isFalse CircularSecond.Meta.fields.first.isArray
    test.isFalse CircularSecond.Meta.fields.first.required
    test.equal CircularSecond.Meta.fields.first.sourceField, 'first'
    test.equal CircularSecond.Meta.fields.first.sourceDocument, CircularSecond
    test.equal CircularSecond.Meta.fields.first.targetDocument, CircularFirst
    test.equal CircularSecond.Meta.fields.first.sourceCollection, CircularSeconds
    test.equal CircularSecond.Meta.fields.first.targetCollection, CircularFirsts
    test.equal CircularSecond.Meta.fields.first.sourceDocument.Meta.collection, CircularSeconds
    test.equal CircularSecond.Meta.fields.first.targetDocument.Meta.collection, CircularFirsts
    test.equal CircularSecond.Meta.fields.first.fields, ['content']

    test.equal Recursive.Meta.collection, Recursives
    test.instanceOf Recursive.Meta.fields.other, Recursive._Reference
    test.isFalse Recursive.Meta.fields.other.isArray
    test.isFalse Recursive.Meta.fields.other.required
    test.equal Recursive.Meta.fields.other.sourceField, 'other'
    test.equal Recursive.Meta.fields.other.sourceDocument, Recursive
    test.equal Recursive.Meta.fields.other.targetDocument, Recursive
    test.equal Recursive.Meta.fields.other.sourceCollection, Recursives
    test.equal Recursive.Meta.fields.other.targetCollection, Recursives
    test.equal Recursive.Meta.fields.other.sourceDocument.Meta.collection, Recursives
    test.equal Recursive.Meta.fields.other.targetDocument.Meta.collection, Recursives
    test.equal Recursive.Meta.fields.other.fields, ['content']

    test.equal Document.Meta.list, [UserLink, CircularSecond, Person, CircularFirst, Recursive, Post]

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
    ,
      expect (error, postId) =>
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
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    Persons.update @person2Id,
      $set:
        username: 'person2a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    Persons.update @person3Id,
      $set:
        username: 'person3a'
    ,
      expect (error, res) =>
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

    Persons.remove @person3Id,
      expect (error) =>
        test.isFalse error, error

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

    Persons.remove @person2Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
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

    Persons.remove @person1Id,
      expect (error) =>
        test.isFalse error, error

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
  test.equal Document.Meta.list, [UserLink, CircularSecond, Person, CircularFirst, Recursive, Post]

testAsyncMulti 'meteor-peerdb - delayed defintion', [
  (test, expect) ->
    class BadPost extends Document
      @Meta =>
        collection: Posts
        fields:
          author: @Reference undefined, ['username']

    Log._intercept 2 # Two to see if we catch more than expected

    # Sleep so that error is shown
    pollUntil expect, ->
      false
    , 1100, 100, true
,
  (test, expect) ->
    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Not all delayed document definitions were successfully retried: BadPost"
    test.equal intercepted.level, 'error'

    test.equal Document.Meta.list, [UserLink, CircularSecond, Person, CircularFirst, Recursive, Post]
    test.equal Document.Meta.delayed.length, 1

    # Clear delayed so that we can retry tests without errors
    Document.Meta.delayed = []
]

testAsyncMulti 'meteor-peerdb - circular changes', [
  (test, expect) ->
    Log._intercept 3 if Meteor.isServer # Three to see if we catch more than expected

    CircularFirsts.insert
      second: null
      content: 'FooBar 1'
    ,
      expect (error, circularFirstId) =>
        test.isFalse error, error
        test.isTrue circularFirstId
        @circularFirstId = circularFirstId

    CircularSeconds.insert
      first: null
      content: 'FooBar 2'
    ,
      expect (error, circularSecondId) =>
        test.isFalse error, error
        test.isTrue circularSecondId
        @circularSecondId = circularSecondId

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf @circularFirstId isnt -1
      intercepted = EJSON.parse i

      test.equal intercepted.message, "Document's '#{ @circularFirstId }' field 'second' was updated with invalid value: null"
      test.equal intercepted.level, 'warn'

    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second: null
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      first: null
      content: 'FooBar 2'

    CircularFirsts.update @circularFirstId,
      $set:
        second:
          _id: @circularSecondId
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      first: null
      content: 'FooBar 2'

    CircularSeconds.update @circularSecondId,
      $set:
        first:
          _id: @circularFirstId
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      first:
        _id: @circularFirstId
        content: 'FooBar 1'
      content: 'FooBar 2'

    CircularFirsts.update @circularFirstId,
      $set:
        content: 'FooBar 1a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1a'
    test.equal @circularSecond,
      _id: @circularSecondId
      first:
        _id: @circularFirstId
        content: 'FooBar 1a'
      content: 'FooBar 2'

    CircularSeconds.update @circularSecondId,
      $set:
        content: 'FooBar 2a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2a'
      content: 'FooBar 1a'
    test.equal @circularSecond,
      _id: @circularSecondId
      first:
        _id: @circularFirstId
        content: 'FooBar 1a'
      content: 'FooBar 2a'

    CircularSeconds.remove @circularSecondId,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.isFalse @circularSecond

    # If directly referenced document is removed, dependency is removed as well
    test.isFalse @circularFirst

    Log._intercept 1 if Meteor.isServer

    CircularSeconds.insert
      first: null
      content: 'FooBar 2'
    ,
      expect (error, circularSecondId) =>
        test.isFalse error, error
        test.isTrue circularSecondId
        @circularSecondId = circularSecondId
,
  (test, expect) ->
    CircularFirsts.insert
      second:
        _id: @circularSecondId
      content: 'FooBar 1'
    ,
      expect (error, circularFirstId) =>
        test.isFalse error, error
        test.isTrue circularFirstId
        @circularFirstId = circularFirstId

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      test.equal intercepted.length, 0, intercepted

    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      first: null
      content: 'FooBar 2'

    CircularSeconds.update @circularSecondId,
      $set:
        first:
          _id: @circularFirstId
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      first:
        _id: @circularFirstId
        content: 'FooBar 1'
      content: 'FooBar 2'

    CircularFirsts.remove @circularFirstId,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @circularFirst = CircularFirsts.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSeconds.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.isFalse @circularFirst

    # If directly referenced but optional document is removed, dependency is not removed as well, but set to null
    test.equal @circularSecond,
      _id: @circularSecondId
      first: null
      content: 'FooBar 2'
]

testAsyncMulti 'meteor-peerdb - recursive two', [
  (test, expect) ->
    Recursives.insert
      other: null
      content: 'FooBar 1'
    ,
      expect (error, recursive1Id) =>
        test.isFalse error, error
        test.isTrue recursive1Id
        @recursive1Id = recursive1Id

    Recursives.insert
      other: null
      content: 'FooBar 2'
    ,
      expect (error, recursive2Id) =>
        test.isFalse error, error
        test.isTrue recursive2Id
        @recursive2Id = recursive2Id

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      other: null
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      other: null
      content: 'FooBar 2'

    Recursives.update @recursive1Id,
      $set:
        other:
          _id: @recursive2Id
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      other: null
      content: 'FooBar 2'

    Recursives.update @recursive2Id,
      $set:
        other:
          _id: @recursive1Id
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      other:
        _id: @recursive1Id
        content: 'FooBar 1'
      content: 'FooBar 2'

    Recursives.update @recursive1Id,
      $set:
        content: 'FooBar 1a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1a'
    test.equal @recursive2,
      _id: @recursive2Id
      other:
        _id: @recursive1Id
        content: 'FooBar 1a'
      content: 'FooBar 2'

    Recursives.update @recursive2Id,
      $set:
        content: 'FooBar 2a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      other:
        _id: @recursive2Id
        content: 'FooBar 2a'
      content: 'FooBar 1a'
    test.equal @recursive2,
      _id: @recursive2Id
      other:
        _id: @recursive1Id
        content: 'FooBar 1a'
      content: 'FooBar 2a'

    Recursives.remove @recursive2Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive1 = Recursives.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursives.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.isFalse @recursive2

    test.equal @recursive1,
      _id: @recursive1Id
      other: null
      content: 'FooBar 1a'
]

testAsyncMulti 'meteor-peerdb - recursive one', [
  (test, expect) ->
    Recursives.insert
      other: null
      content: 'FooBar'
    ,
      expect (error, recursiveId) =>
        test.isFalse error, error
        test.isTrue recursiveId
        @recursiveId = recursiveId

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive = Recursives.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      other: null
      content: 'FooBar'

    Recursives.update @recursiveId,
      $set:
        other:
          _id: @recursiveId
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive = Recursives.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      other:
        _id: @recursiveId
        content: 'FooBar'
      content: 'FooBar'

    Recursives.update @recursiveId,
      $set:
        content: 'FooBara'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive = Recursives.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      other:
        _id: @recursiveId
        content: 'FooBara'
      content: 'FooBara'

    Recursives.remove @recursiveId,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update the document
    pollUntil expect, ->
      false
    , 500, 100, true
,
  (test, expect) ->
    @recursive = Recursives.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.isFalse @recursive
]

if Meteor.isServer
  Tinytest.add 'meteor-peerdb - warnings', (test) ->
    Log._intercept 2 # Two to see if we catch more than expected

    postId = Posts.insert
      author:
        _id: 'nonexistent'

    # Sleep so that observers have time to update the document
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' is referencing nonexistent document 'nonexistent'"
    test.equal intercepted.level, 'warn'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Posts.insert
      subscribers: 'foobar'

    # Sleep so that observers have time to update the document
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'subscribers' was updated with non-array value: 'foobar'"
    test.equal intercepted.level, 'warn'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Posts.insert
      author: null

    # Sleep so that observers have time to update the document
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' was updated with invalid value: null"
    test.equal intercepted.level, 'warn'

    Log._intercept 1

    userLinkId = UserLinks.insert
      user: null

    # Sleep so that observers have time to update the document
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    # There should be no warning because user is optional
    test.equal intercepted.length, 0, intercepted
