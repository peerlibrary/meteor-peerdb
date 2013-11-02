Persons = new Meteor.Collection 'Persons', transform: (doc) => new Person doc
Posts = new Meteor.Collection 'Posts', transform: (doc) => new Post doc
UserLinks = new Meteor.Collection 'UserLinks', transform: (doc) => new UserLink doc
PostLinks = new Meteor.Collection 'PostLinks', transform: (doc) => new PostLink doc
CircularFirsts = new Meteor.Collection 'CircularFirsts', transform: (doc) => new CircularFirst doc
CircularSeconds = new Meteor.Collection 'CircularSeconds', transform: (doc) => new CircularSecond doc
Recursives = new Meteor.Collection 'Recursives', transform: (doc) => new Recursive doc

if Meteor.isServer
  # Initialize the database
  Persons.remove {}
  Posts.remove {}
  UserLinks.remove {}
  PostLinks.remove {}
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
    PostLinks.find()
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
  #   subdocument
  #     body

  @Meta =>
    collection: Posts
    fields:
      # We can reference other document
      author: @ReferenceField Person, ['username']
      # Or an array of documents
      subscribers: [@ReferenceField Person]
      # Fields can be arbitrary MongoDB projections
      reviewers: [@ReferenceField Person, [username: 1]]
      subdocument:
        person: @ReferenceField Person, ['username'], false
      slug: @GeneratedField 'self', ['body', 'subdocument.body'], (fields) ->
        if _.isUndefined(fields.body) or _.isUndefined(fields.subdocument?.body)
          [fields._id, undefined]
        else if _.isNull(fields.body) or _.isNull(fields.subdocument.body)
          [fields._id, null]
        else
          [fields._id, "prefix-#{ fields.body.toLowerCase() }-#{ fields.subdocument.body.toLowerCase() }-suffix"]

# To test MixinMeta when initial Meta is delayed
class Post extends Post
  @MixinMeta (meta) =>
    meta.fields.subdocument.persons = [@ReferenceField Person, ['username']]
    meta

class UserLink extends Document
  @Meta
    collection: UserLinks
    fields:
      # We can reference just a collection
      user: @ReferenceField Meteor.users, ['username'], false

class PostLink extends Document
  @Meta
    collection: PostLinks

# To test MixinMeta when initial Meta is not a function
class PostLink extends PostLink
  @MixinMeta (meta) =>
    meta.fields ?= {}
    meta.fields.post = @ReferenceField Posts, ['subdocument.person', 'subdocument.persons']
    meta

class CircularFirst extends Document
  # Other fields:
  #   content

  @Meta =>
    collection: CircularFirsts

# To test MixinMeta when initial Meta is a function
class CircularFirst extends CircularFirst
  @MixinMeta (meta) =>
    meta.fields ?= {}
    # We can reference circular documents
    meta.fields.second = @ReferenceField CircularSecond, ['content']
    meta

class CircularSecond extends Document
  # Other fields:
  #   content

  @Meta =>
    collection: CircularSeconds
    fields:
      # But of course one should not be required so that we can insert without warnings
      first: @ReferenceField CircularFirst, ['content'], false

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
      other: @ReferenceField 'self', ['content'], false

Document.redefineAll()

testDefinition = (test) ->
  test.equal Person.Meta.collection, Persons
  test.equal Person.Meta.fields, {}

  test.equal Post.Meta.collection, Posts
  test.equal _.size(Post.Meta.fields), 5
  test.instanceOf Post.Meta.fields.author, Person._ReferenceField
  test.isFalse Post.Meta.fields.author.isArray
  test.isTrue Post.Meta.fields.author.required
  test.equal Post.Meta.fields.author.sourcePath, 'author'
  test.equal Post.Meta.fields.author.sourceDocument, Post
  test.equal Post.Meta.fields.author.targetDocument, Person
  test.equal Post.Meta.fields.author.sourceCollection, Posts
  test.equal Post.Meta.fields.author.targetCollection, Persons
  test.equal Post.Meta.fields.author.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.author.targetDocument.Meta.collection, Persons
  test.equal Post.Meta.fields.author.fields, ['username']
  test.instanceOf Post.Meta.fields.subscribers, Person._ReferenceField
  test.isTrue Post.Meta.fields.subscribers.isArray
  test.isTrue Post.Meta.fields.subscribers.required
  test.equal Post.Meta.fields.subscribers.sourcePath, 'subscribers'
  test.equal Post.Meta.fields.subscribers.sourceDocument, Post
  test.equal Post.Meta.fields.subscribers.targetDocument, Person
  test.equal Post.Meta.fields.subscribers.sourceCollection, Posts
  test.equal Post.Meta.fields.subscribers.targetCollection, Persons
  test.equal Post.Meta.fields.subscribers.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.subscribers.targetDocument.Meta.collection, Persons
  test.equal Post.Meta.fields.subscribers.fields, []
  test.isTrue Post.Meta.fields.reviewers.isArray
  test.isTrue Post.Meta.fields.reviewers.required
  test.equal Post.Meta.fields.reviewers.sourcePath, 'reviewers'
  test.equal Post.Meta.fields.reviewers.sourceDocument, Post
  test.equal Post.Meta.fields.reviewers.targetDocument, Person
  test.equal Post.Meta.fields.reviewers.sourceCollection, Posts
  test.equal Post.Meta.fields.reviewers.targetCollection, Persons
  test.equal Post.Meta.fields.reviewers.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.reviewers.targetDocument.Meta.collection, Persons
  test.equal Post.Meta.fields.reviewers.fields, [username: 1]
  test.equal _.size(Post.Meta.fields.subdocument), 2
  test.isFalse Post.Meta.fields.subdocument.person.isArray
  test.isFalse Post.Meta.fields.subdocument.person.required
  test.equal Post.Meta.fields.subdocument.person.sourcePath, 'subdocument.person'
  test.equal Post.Meta.fields.subdocument.person.sourceDocument, Post
  test.equal Post.Meta.fields.subdocument.person.targetDocument, Person
  test.equal Post.Meta.fields.subdocument.person.sourceCollection, Posts
  test.equal Post.Meta.fields.subdocument.person.targetCollection, Persons
  test.equal Post.Meta.fields.subdocument.person.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.subdocument.person.targetDocument.Meta.collection, Persons
  test.equal Post.Meta.fields.subdocument.person.fields, ['username']
  test.isTrue Post.Meta.fields.subdocument.persons.isArray
  test.isTrue Post.Meta.fields.subdocument.persons.required
  test.equal Post.Meta.fields.subdocument.persons.sourcePath, 'subdocument.persons'
  test.equal Post.Meta.fields.subdocument.persons.sourceDocument, Post
  test.equal Post.Meta.fields.subdocument.persons.targetDocument, Person
  test.equal Post.Meta.fields.subdocument.persons.sourceCollection, Posts
  test.equal Post.Meta.fields.subdocument.persons.targetCollection, Persons
  test.equal Post.Meta.fields.subdocument.persons.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.subdocument.persons.targetDocument.Meta.collection, Persons
  test.equal Post.Meta.fields.subdocument.persons.fields, ['username']
  test.isFalse Post.Meta.fields.slug.isArray
  test.isTrue _.isFunction Post.Meta.fields.slug.generator
  test.equal Post.Meta.fields.slug.sourcePath, 'slug'
  test.equal Post.Meta.fields.slug.sourceDocument, Post
  test.equal Post.Meta.fields.slug.targetDocument, Post
  test.equal Post.Meta.fields.slug.sourceCollection, Posts
  test.equal Post.Meta.fields.slug.targetCollection, Posts
  test.equal Post.Meta.fields.slug.sourceDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.slug.targetDocument.Meta.collection, Posts
  test.equal Post.Meta.fields.slug.fields, ['body', 'subdocument.body']

  test.equal UserLink.Meta.collection, UserLinks
  test.equal _.size(UserLink.Meta.fields), 1
  test.instanceOf UserLink.Meta.fields.user, UserLink._ReferenceField
  test.isFalse UserLink.Meta.fields.user.isArray
  test.isFalse UserLink.Meta.fields.user.required
  test.equal UserLink.Meta.fields.user.sourcePath, 'user'
  test.equal UserLink.Meta.fields.user.sourceDocument, UserLink
  test.equal UserLink.Meta.fields.user.targetDocument, null # We are referencing just a collection
  test.equal UserLink.Meta.fields.user.sourceCollection, UserLinks
  test.equal UserLink.Meta.fields.user.targetCollection, Meteor.users
  test.equal UserLink.Meta.fields.user.sourceDocument.Meta.collection, UserLinks
  test.equal UserLink.Meta.fields.user.fields, ['username']

  test.equal PostLink.Meta.collection, PostLinks
  test.equal _.size(PostLink.Meta.fields), 1
  test.instanceOf PostLink.Meta.fields.post, PostLink._ReferenceField
  test.isFalse PostLink.Meta.fields.post.isArray
  test.isTrue PostLink.Meta.fields.post.required
  test.equal PostLink.Meta.fields.post.sourcePath, 'post'
  test.equal PostLink.Meta.fields.post.sourceDocument, PostLink
  test.equal PostLink.Meta.fields.post.targetDocument, null # We are referencing just a collection
  test.equal PostLink.Meta.fields.post.sourceCollection, PostLinks
  test.equal PostLink.Meta.fields.post.targetCollection, Posts
  test.equal PostLink.Meta.fields.post.sourceDocument.Meta.collection, PostLinks
  test.equal PostLink.Meta.fields.post.fields, ['subdocument.person', 'subdocument.persons']

  test.equal CircularFirst.Meta.collection, CircularFirsts
  test.equal _.size(CircularFirst.Meta.fields), 1
  test.instanceOf CircularFirst.Meta.fields.second, CircularFirst._ReferenceField
  test.isFalse CircularFirst.Meta.fields.second.isArray
  test.isTrue CircularFirst.Meta.fields.second.required
  test.equal CircularFirst.Meta.fields.second.sourcePath, 'second'
  test.equal CircularFirst.Meta.fields.second.sourceDocument, CircularFirst
  test.equal CircularFirst.Meta.fields.second.targetDocument, CircularSecond
  test.equal CircularFirst.Meta.fields.second.sourceCollection, CircularFirsts
  test.equal CircularFirst.Meta.fields.second.targetCollection, CircularSeconds
  test.equal CircularFirst.Meta.fields.second.sourceDocument.Meta.collection, CircularFirsts
  test.equal CircularFirst.Meta.fields.second.targetDocument.Meta.collection, CircularSeconds
  test.equal CircularFirst.Meta.fields.second.fields, ['content']

  test.equal CircularSecond.Meta.collection, CircularSeconds
  test.equal _.size(CircularSecond.Meta.fields), 1
  test.instanceOf CircularSecond.Meta.fields.first, CircularSecond._ReferenceField
  test.isFalse CircularSecond.Meta.fields.first.isArray
  test.isFalse CircularSecond.Meta.fields.first.required
  test.equal CircularSecond.Meta.fields.first.sourcePath, 'first'
  test.equal CircularSecond.Meta.fields.first.sourceDocument, CircularSecond
  test.equal CircularSecond.Meta.fields.first.targetDocument, CircularFirst
  test.equal CircularSecond.Meta.fields.first.sourceCollection, CircularSeconds
  test.equal CircularSecond.Meta.fields.first.targetCollection, CircularFirsts
  test.equal CircularSecond.Meta.fields.first.sourceDocument.Meta.collection, CircularSeconds
  test.equal CircularSecond.Meta.fields.first.targetDocument.Meta.collection, CircularFirsts
  test.equal CircularSecond.Meta.fields.first.fields, ['content']

  test.equal Recursive.Meta.collection, Recursives
  test.equal _.size(Recursive.Meta.fields), 1
  test.instanceOf Recursive.Meta.fields.other, Recursive._ReferenceField
  test.isFalse Recursive.Meta.fields.other.isArray
  test.isFalse Recursive.Meta.fields.other.required
  test.equal Recursive.Meta.fields.other.sourcePath, 'other'
  test.equal Recursive.Meta.fields.other.sourceDocument, Recursive
  test.equal Recursive.Meta.fields.other.targetDocument, Recursive
  test.equal Recursive.Meta.fields.other.sourceCollection, Recursives
  test.equal Recursive.Meta.fields.other.targetCollection, Recursives
  test.equal Recursive.Meta.fields.other.sourceDocument.Meta.collection, Recursives
  test.equal Recursive.Meta.fields.other.targetDocument.Meta.collection, Recursives
  test.equal Recursive.Meta.fields.other.fields, ['content']

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]

  test.equal UserLink.Meta._initialized, 0
  test.equal PostLink.Meta._initialized, 1
  test.equal CircularSecond.Meta._initialized, 2
  test.equal Person.Meta._initialized, 3
  test.equal CircularFirst.Meta._initialized, 4
  test.equal Recursive.Meta._initialized, 5
  test.equal Post.Meta._initialized, 6

  test.isUndefined UserLink.Meta._delayed
  test.isUndefined PostLink.Meta._delayed
  test.isUndefined CircularSecond.Meta._delayed
  test.isUndefined Person.Meta._delayed
  test.isUndefined CircularFirst.Meta._delayed
  test.isUndefined Recursive.Meta._delayed
  test.isUndefined Post.Meta._delayed

  test.isUndefined UserLink.Meta._meta._delayed
  test.isUndefined PostLink.Meta._meta._delayed
  test.isUndefined CircularSecond.Meta._meta._delayed
  test.isUndefined Person.Meta._meta._delayed
  test.isUndefined CircularFirst.Meta._meta._delayed
  test.isUndefined Recursive.Meta._meta._delayed
  test.isUndefined Post.Meta._meta._delayed

testAsyncMulti 'meteor-peerdb - references', [
  (test, expect) ->
    testDefinition test

    # We should be able to call redefineAll multiple times
    Document.redefineAll()

    testDefinition test

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

    # Sleep so that observers have time to run (but no post is yet made, so nothing really happens)
    # We want to wait here so that we catch possible errors in source observers, otherwise target
    # observers can patch things up, for example, if we create a post first and target observers
    # (triggered by person inserts, but pending) run afterwards, then they can patch things which
    # should in fact be done by source observers (on post), like setting usernames in post's
    # references to persons
    Meteor.setTimeout expect(), 500
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
      subdocument:
        person:
          _id: @person2._id
        persons: [
          _id: @person2._id
        ,
          _id: @person3._id
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

    # We inserted the document only with ids - subdocuments should be
    # automatically populated with additional fields as defined in @ReferenceField
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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

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

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged togetger to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

    Persons.remove @person3Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

    Persons.remove @person2Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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
      subdocument:
        person: null
        persons: []
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

    Persons.remove @person1Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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
          reviewers: [@ReferenceField Person, ['username'], false]
  , /Only non-array fields can be optional/

  # Invalid document should not be added to the list
  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]

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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf(@circularFirstId) isnt -1
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update document
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
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

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' is referencing nonexistent document 'nonexistent'"
    test.equal intercepted.level, 'warn'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Posts.insert
      subscribers: 'foobar'

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'subscribers' was updated with non-array value: 'foobar'"
    test.equal intercepted.level, 'warn'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Posts.insert
      author: null

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' was updated with invalid value: null"
    test.equal intercepted.level, 'warn'

    Log._intercept 1

    userLinkId = UserLinks.insert
      user: null

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(500)

    intercepted = Log._intercepted()

    # There should be no warning because user is optional
    test.equal intercepted.length, 0, intercepted

testAsyncMulti 'meteor-peerdb - delayed defintion', [
  (test, expect) ->
    class BadPost extends Document
      @Meta =>
        collection: Posts
        fields:
          author: @ReferenceField undefined, ['username']

    Log._intercept 2 # Two to see if we catch more than expected

    # Sleep so that error is shown
    Meteor.setTimeout expect(), 1000 # We need 1000 here because we have a check which runs after 1000 ms to check for delayed defintions
,
  (test, expect) ->
    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Not all delayed document definitions were successfully retried: BadPost"
    test.equal intercepted.level, 'error'

    test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]
    test.equal Document.Meta.delayed.length, 1

    # Clear delayed so that we can retry tests without errors
    Document.Meta.delayed = []
    Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout
]

testAsyncMulti 'meteor-peerdb - subdocument fields', [
  (test, expect) ->
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
      subdocument:
        person:
          _id: @person2._id
        persons: [
          _id: @person2._id
        ,
          _id: @person3._id
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

    PostLinks.insert
      post:
        _id: @post._id
    ,
      expect (error, postLinkId) =>
        test.isFalse error, error
        test.isTrue postLinkId
        @postLinkId = postLinkId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @postLink = PostLinks.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      post:
        _id: @post._id
        subdocument:
          person:
            _id: @person2._id
            username: @person2.username
          persons: [
            _id: @person2._id
            username: @person2.username
          ,
            _id: @person3._id
            username: @person3.username
          ]

    Persons.update @person2Id,
      $set:
        username: 'person2a'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @person2 = Persons.findOne @person2Id

    test.instanceOf @person2, Person
    test.equal @person2.username, 'person2a'
    test.equal @person2.displayName, 'Person 2'

    @postLink = PostLinks.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      post:
        _id: @post._id
        subdocument:
          person:
            _id: @person2._id
            username: @person2.username
          persons: [
            _id: @person2._id
            username: @person2.username
          ,
            _id: @person3._id
            username: @person3.username
          ]

    Persons.remove @person2Id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @postLink = PostLinks.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      post:
        _id: @post._id
        subdocument:
          person: null
          persons: [
            _id: @person3._id
            username: @person3.username
          ]

    Posts.remove @post._id,
      expect (error) =>
        test.isFalse error, error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @postLink = PostLinks.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.isFalse @postLink
]

testAsyncMulti 'meteor-peerdb - generated fields', [
  (test, expect) ->
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
      subdocument:
        person:
          _id: @person2._id
        persons: [
          _id: @person2._id
        ,
          _id: @person3._id
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'

    Posts.update @postId,
      $set:
        body: 'FooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobar-suffix'

    Posts.update @postId,
      $set:
        body: null
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
      body: null
      slug: null

    Posts.update @postId,
      $unset:
        body: ''
    ,
      expect (error, res) =>
        test.isFalse error, error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), 500
,
  (test, expect) ->
    @post = Posts.findOne @postId,
      transform: null # So that we can use test.equal

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
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
        persons: [
          _id: @person2._id
          username: @person2.username
        ,
          _id: @person3._id
          username: @person3.username
        ]
        body: 'SubdocumentFooBar'
]

Tinytest.add 'meteor-peerdb - chain of extended classes', (test) ->
  list = _.clone Document.Meta.list

  firstReferenceA = undefined # To force delayed
  secondReferenceA = undefined # To force delayed
  firstReferenceB = undefined # To force delayed
  secondReferenceB = undefined # To force delayed

  class First extends Document
    @Meta =>
      collection: Posts
      fields:
        first: @ReferenceField firstReferenceA

  class Second extends First
    # We can return object as well and it be merged
    @ExtendMeta
      fields:
        second: @ReferenceField Post # It cannot be undefined, but overall meta will still be delayed

  class Third extends Second
    @ExtendMeta (meta) =>
      meta.fields.third = @ReferenceField secondReferenceA
      meta

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]
  test.equal Document.Meta.delayed.length, 3
  test.equal Document.Meta.delayed[0][0], First
  test.equal Document.Meta.delayed[1][0], Second
  test.equal Document.Meta.delayed[2][0], Third

  test.isUndefined Document.Meta._delayed
  test.equal First.Meta._delayed, 0
  test.equal Second.Meta._delayed, 1
  test.equal Third.Meta._delayed, 2

  class First extends First
    @MixinMeta (meta) =>
      meta.fields.first = @ReferenceField firstReferenceB
      meta

  class Second extends Second
    # We can return object as well and it will be merged
    @MixinMeta
      fields:
        second: @ReferenceField Person # It cannot be undefined, but overall meta will still be delayed

  class Third extends Third
    @MixinMeta (meta) =>
      meta.fields.third = @ReferenceField secondReferenceB
      meta

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]
  test.equal Document.Meta.delayed.length, 3
  test.equal Document.Meta.delayed[0][0], First
  test.equal Document.Meta.delayed[1][0], Second
  test.equal Document.Meta.delayed[2][0], Third

  test.isUndefined Document.Meta._delayed
  test.equal First.Meta._delayed, 0
  test.equal Second.Meta._delayed, 1
  test.equal Third.Meta._delayed, 2

  class Third extends Third
    @MixinMeta (meta) =>
      meta.fields.third = @ReferenceField Person
      meta

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]
  test.equal Document.Meta.delayed.length, 3
  test.equal Document.Meta.delayed[0][0], First
  test.equal Document.Meta.delayed[1][0], Second
  test.equal Document.Meta.delayed[2][0], Third

  test.isUndefined Document.Meta._delayed
  test.equal First.Meta._delayed, 0
  test.equal Second.Meta._delayed, 1
  test.equal Third.Meta._delayed, 2

  class First extends First
    @MixinMeta (meta) =>
      meta.fields.first = @ReferenceField Person
      meta

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post]
  test.equal Document.Meta.delayed.length, 3
  test.equal Document.Meta.delayed[0][0], First
  test.equal Document.Meta.delayed[1][0], Second
  test.equal Document.Meta.delayed[2][0], Third

  test.isUndefined Document.Meta._delayed
  test.equal First.Meta._delayed, 0
  test.equal Second.Meta._delayed, 1
  test.equal Third.Meta._delayed, 2

  firstReferenceA = First
  Document._retryDelayed()

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post, Second]
  test.equal Document.Meta.delayed.length, 2
  test.equal Document.Meta.delayed[0][0], First
  test.equal Document.Meta.delayed[1][0], Third

  test.isUndefined Document.Meta._delayed
  test.equal First.Meta._delayed, 0
  test.isUndefined Second.Meta._delayed
  test.equal Third.Meta._delayed, 1

  test.equal Second.Meta.collection, Posts
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.isArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection, Posts
  test.isUndefined Second.Meta.fields.first.targetCollection # Currently target collection is still undefined
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.isUndefined Second.Meta.fields.first.targetDocument.Meta.collection # Currently target collection is still undefined
  test.equal Second.Meta.fields.first.fields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.isArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection, Posts
  test.equal Second.Meta.fields.second.targetCollection, Persons
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection, Persons
  test.equal Second.Meta.fields.second.fields, []

  firstReferenceB = Posts
  Document._retryDelayed()

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post, Second, First]
  test.equal Document.Meta.delayed.length, 1
  test.equal Document.Meta.delayed[0][0], Third

  test.isUndefined Document.Meta._delayed
  test.isUndefined First.Meta._delayed
  test.isUndefined Second.Meta._delayed
  test.equal Third.Meta._delayed, 0

  test.equal Second.Meta.collection, Posts
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.isArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection, Posts
  test.isUndefined Second.Meta.fields.first.targetCollection # Currently target collection is still undefined
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection, Posts # Now it gets defined because First gets defined
  test.equal Second.Meta.fields.first.fields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.isArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection, Posts
  test.equal Second.Meta.fields.second.targetCollection, Persons
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection, Persons
  test.equal Second.Meta.fields.second.fields, []

  test.equal First.Meta.collection, Posts
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.isArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection, Posts
  test.equal First.Meta.fields.first.targetCollection, Persons
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal First.Meta.fields.first.targetDocument.Meta.collection, Persons
  test.equal First.Meta.fields.first.fields, []

  secondReferenceA = First
  Document._retryDelayed()

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post, Second, First]
  test.equal Document.Meta.delayed.length, 1
  test.equal Document.Meta.delayed[0][0], Third

  test.isUndefined Document.Meta._delayed
  test.isUndefined First.Meta._delayed
  test.isUndefined Second.Meta._delayed
  test.equal Third.Meta._delayed, 0

  test.equal Second.Meta.collection, Posts
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.isArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection, Posts
  test.isUndefined Second.Meta.fields.first.targetCollection # Currently target collection is still undefined
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.fields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.isArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection, Posts
  test.equal Second.Meta.fields.second.targetCollection, Persons
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection, Persons
  test.equal Second.Meta.fields.second.fields, []

  test.equal First.Meta.collection, Posts
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.isArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection, Posts
  test.equal First.Meta.fields.first.targetCollection, Persons
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal First.Meta.fields.first.targetDocument.Meta.collection, Persons
  test.equal First.Meta.fields.first.fields, []

  secondReferenceB = Posts
  Document._retryDelayed()

  test.equal Document.Meta.list, [UserLink, PostLink, CircularSecond, Person, CircularFirst, Recursive, Post, Second, First, Third]
  test.equal Document.Meta.delayed.length, 0

  test.isUndefined Document.Meta._delayed
  test.isUndefined First.Meta._delayed
  test.isUndefined Second.Meta._delayed
  test.isUndefined Third.Meta._delayed

  test.equal Second.Meta.collection, Posts
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.isArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection, Posts
  test.isUndefined Second.Meta.fields.first.targetCollection # Currently target collection is still undefined
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.fields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.isArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection, Posts
  test.equal Second.Meta.fields.second.targetCollection, Persons
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection, Persons
  test.equal Second.Meta.fields.second.fields, []

  test.equal First.Meta.collection, Posts
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.isArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection, Posts
  test.equal First.Meta.fields.first.targetCollection, Persons
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal First.Meta.fields.first.targetDocument.Meta.collection, Persons
  test.equal First.Meta.fields.first.fields, []

  test.equal Third.Meta.collection, Posts
  test.equal _.size(Third.Meta.fields), 3
  test.instanceOf Third.Meta.fields.first, Third._ReferenceField
  test.isFalse Third.Meta.fields.first.isArray
  test.isTrue Third.Meta.fields.first.required
  test.equal Third.Meta.fields.first.sourcePath, 'first'
  test.equal Third.Meta.fields.first.sourceDocument, Third
  test.equal Third.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Third.Meta.fields.first.sourceCollection, Posts
  test.equal Third.Meta.fields.first.targetCollection, Posts # Here it is already defined because First was defined at the time when Third got defined (after a delay)
  test.equal Third.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.first.targetDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.first.fields, []
  test.instanceOf Third.Meta.fields.second, Third._ReferenceField
  test.isFalse Third.Meta.fields.second.isArray
  test.isTrue Third.Meta.fields.second.required
  test.equal Third.Meta.fields.second.sourcePath, 'second'
  test.equal Third.Meta.fields.second.sourceDocument, Third
  test.equal Third.Meta.fields.second.targetDocument, Post
  test.equal Third.Meta.fields.second.sourceCollection, Posts
  test.equal Third.Meta.fields.second.targetCollection, Posts
  test.equal Third.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.second.targetDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.second.fields, []
  test.instanceOf Third.Meta.fields.third, Third._ReferenceField
  test.isFalse Third.Meta.fields.third.isArray
  test.isTrue Third.Meta.fields.third.required
  test.equal Third.Meta.fields.third.sourcePath, 'third'
  test.equal Third.Meta.fields.third.sourceDocument, Third
  test.equal Third.Meta.fields.third.targetDocument, Person
  test.equal Third.Meta.fields.third.sourceCollection, Posts
  test.equal Third.Meta.fields.third.targetCollection, Persons
  test.equal Third.Meta.fields.third.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.third.targetDocument.Meta.collection, Persons
  test.equal Third.Meta.fields.third.fields, []

  Document.redefineAll()

  test.equal Second.Meta.collection, Posts
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.isArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection, Posts
  test.equal Second.Meta.fields.first.targetCollection, Posts
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.first.fields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.isArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection, Posts
  test.equal Second.Meta.fields.second.targetCollection, Persons
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection, Persons
  test.equal Second.Meta.fields.second.fields, []

  test.equal First.Meta.collection, Posts
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.isArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection, Posts
  test.equal First.Meta.fields.first.targetCollection, Persons
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal First.Meta.fields.first.targetDocument.Meta.collection, Persons
  test.equal First.Meta.fields.first.fields, []

  test.equal Third.Meta.collection, Posts
  test.equal _.size(Third.Meta.fields), 3
  test.instanceOf Third.Meta.fields.first, Third._ReferenceField
  test.isFalse Third.Meta.fields.first.isArray
  test.isTrue Third.Meta.fields.first.required
  test.equal Third.Meta.fields.first.sourcePath, 'first'
  test.equal Third.Meta.fields.first.sourceDocument, Third
  test.equal Third.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Third.Meta.fields.first.sourceCollection, Posts
  test.equal Third.Meta.fields.first.targetCollection, Posts
  test.equal Third.Meta.fields.first.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.first.targetDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.first.fields, []
  test.instanceOf Third.Meta.fields.second, Third._ReferenceField
  test.isFalse Third.Meta.fields.second.isArray
  test.isTrue Third.Meta.fields.second.required
  test.equal Third.Meta.fields.second.sourcePath, 'second'
  test.equal Third.Meta.fields.second.sourceDocument, Third
  test.equal Third.Meta.fields.second.targetDocument, Post
  test.equal Third.Meta.fields.second.sourceCollection, Posts
  test.equal Third.Meta.fields.second.targetCollection, Posts
  test.equal Third.Meta.fields.second.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.second.targetDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.second.fields, []
  test.instanceOf Third.Meta.fields.third, Third._ReferenceField
  test.isFalse Third.Meta.fields.third.isArray
  test.isTrue Third.Meta.fields.third.required
  test.equal Third.Meta.fields.third.sourcePath, 'third'
  test.equal Third.Meta.fields.third.sourceDocument, Third
  test.equal Third.Meta.fields.third.targetDocument, Person
  test.equal Third.Meta.fields.third.sourceCollection, Posts
  test.equal Third.Meta.fields.third.targetCollection, Persons
  test.equal Third.Meta.fields.third.sourceDocument.Meta.collection, Posts
  test.equal Third.Meta.fields.third.targetDocument.Meta.collection, Persons
  test.equal Third.Meta.fields.third.fields, []

  # Restore
  Document.Meta.list = list
  Document.Meta.delayed = []
  Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

  # Verify we are back to normal
  testDefinition test

Tinytest.add 'meteor-peerdb - invalid documents', (test) ->
  list = _.clone Document.Meta.list

  class First extends Document
    @Meta =>
      fields:
        first: @ReferenceField First

  test.throws ->
    Document.redefineAll()
  , /Undefined target collection/

  # Restore
  Document.Meta.list = _.clone list
  Document.Meta.delayed = []
  Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

  class First extends Document
    @Meta =>
      collection: Posts
      fields:
        first: @ReferenceField undefined # To force delayed

  class Second extends Document
    @Meta =>
      collection: Posts
      fields:
        first: @ReferenceField First

  test.throws ->
    Document.redefineAll()
  , /Undefined target collection/

  # Restore
  Document.Meta.list = _.clone list
  Document.Meta.delayed = []
  Meteor.clearTimeout Document.Meta._delayedCheckTimeout if Document.Meta._delayedCheckTimeout

  # Verify we are back to normal
  testDefinition test
