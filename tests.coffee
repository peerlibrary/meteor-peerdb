if Meteor.isServer
  __meteor_runtime_config__.WAIT_TIME = WAIT_TIME = process?.env?.WAIT_TIME or 500
else
  WAIT_TIME = __meteor_runtime_config__?.WAIT_TIME or 500

# The order of documents here tests delayed definitions

# Just to make sure things are sane
assert.equal Document._delayed.length, 0

class Post extends Document
  # Other fields:
  #   body
  #   subdocument
  #     body
  #   nested
  #     body

  @Meta
    name: 'Post'
    fields: =>
      # We can reference other document
      author: @ReferenceField Person, ['username', 'displayName', 'field1', 'field2'], true, 'posts', ['body', 'subdocument.body', 'nested.body']
      # Or an array of documents
      subscribers: [@ReferenceField Person]
      # Fields can be arbitrary MongoDB projections
      reviewers: [@ReferenceField Person, [username: 1]]
      subdocument:
        person: @ReferenceField Person, ['username', 'displayName', 'field1', 'field2'], false
        slug: @GeneratedField 'self', ['body', 'subdocument.body'], (fields) ->
          if _.isUndefined(fields.body) or _.isUndefined(fields.subdocument?.body)
            [fields._id, undefined]
          else if _.isNull(fields.body) or _.isNull(fields.subdocument.body)
            [fields._id, null]
          else
            [fields._id, "subdocument-prefix-#{ fields.body.toLowerCase() }-#{ fields.subdocument.body.toLowerCase() }-suffix"]
      nested: [
        required: @ReferenceField Person, ['username', 'displayName', 'field1', 'field2'], true, 'nestedPosts', ['body', 'subdocument.body', 'nested.body']
        optional: @ReferenceField Person, ['username'], false
        slug: @GeneratedField 'self', ['body', 'nested.body'], (fields) ->
          for nested in fields.nested or []
            if _.isUndefined(fields.body) or _.isUndefined(nested.body)
              [fields._id, undefined]
            else if _.isNull(fields.body) or _.isNull(nested.body)
              [fields._id, null]
            else
              [fields._id, "nested-prefix-#{ fields.body.toLowerCase() }-#{ nested.body.toLowerCase() }-suffix"]
      ]
      slug: @GeneratedField 'self', ['body', 'subdocument.body'], (fields) ->
        if _.isUndefined(fields.body) or _.isUndefined(fields.subdocument?.body)
          [fields._id, undefined]
        else if _.isNull(fields.body) or _.isNull(fields.subdocument.body)
          [fields._id, null]
        else
          [fields._id, "prefix-#{ fields.body.toLowerCase() }-#{ fields.subdocument.body.toLowerCase() }-suffix"]
      tags: [
        @GeneratedField 'self', ['body', 'subdocument.body', 'nested.body'], (fields) ->
          tags = []
          if fields.body and fields.subdocument?.body
            tags.push "tag-#{ tags.length }-prefix-#{ fields.body.toLowerCase() }-#{ fields.subdocument.body.toLowerCase() }-suffix"
          if fields.body and fields.nested and _.isArray fields.nested
            for nested in fields.nested when nested.body
              tags.push "tag-#{ tags.length }-prefix-#{ fields.body.toLowerCase() }-#{ nested.body.toLowerCase() }-suffix"
          [fields._id, tags]
      ]

# Store away for testing
_TestPost = Post

# Extending delayed document
class Post extends Post
  @Meta
    name: 'Post'
    replaceParent: true
    fields: (fields) =>
      fields.subdocument.persons = [@ReferenceField Person, ['username', 'displayName', 'field1', 'field2']]
      fields

# Store away for testing
_TestPost2 = Post

class User extends Document
  @Meta
    name: 'User'
    # Specifying collection directly
    collection: Meteor.users

class UserLink extends Document
  @Meta
    name: 'UserLink'
    fields: =>
      user: @ReferenceField User, ['username'], false

class PostLink extends Document
  @Meta
    name: 'PostLink'

# Store away for testing
_TestPostLink = PostLink

# To test extending when initial document has no fields
class PostLink extends PostLink
  @Meta
    name: 'PostLink'
    replaceParent: true
    fields: =>
      post: @ReferenceField Post, ['subdocument.person', 'subdocument.persons']

class CircularFirst extends Document
  # Other fields:
  #   content

  @Meta
    name: 'CircularFirst'

# Store away for testing
_TestCircularFirst = CircularFirst

# To test extending when initial document has no fields and fields will be delayed
class CircularFirst extends CircularFirst
  @Meta
    name: 'CircularFirst'
    replaceParent:  true
    fields: (fields) =>
      # We can reference circular documents
      fields.second = @ReferenceField CircularSecond, ['content']
      fields

class CircularSecond extends Document
  # Other fields:
  #   content

  @Meta
    name: 'CircularSecond'
    fields: =>
      # But of course one should not be required so that we can insert without warnings
      first: @ReferenceField CircularFirst, ['content'], false

class Person extends Document
  # Other fields:
  #   username
  #   displayName
  #   field1
  #   field2

  @Meta
    name: 'Person'
    fields: =>
      count: @GeneratedField 'self', ['posts', 'nestedPosts'], (fields) ->
        [fields._id, (fields.posts?.length or 0) + (fields.nestedPosts?.length or 0)]

  formatName: ->
    "#{ @username }-#{ @displayName or "none" }"

class Recursive extends Document
  # Other fields:
  #   content

  @Meta
    name: 'Recursive'
    fields: =>
      other: @ReferenceField 'self', ['content'], false

class IdentityGenerator extends Document
  # Other fields:
  #   source

  @Meta
    name: 'IdentityGenerator'
    fields: =>
      result: @GeneratedField 'self', ['source'], (fields) ->
        throw new Error "Test exception" if fields.source is 'exception'
        return [fields._id, fields.source]
      results: [
        @GeneratedField 'self', ['source'], (fields) ->
          return [fields._id, fields.source]
      ]

# Extending and renaming the class, this creates new collection as well
class SpecialPost extends Post
  @Meta
    name: 'SpecialPost'
    fields: =>
      special: @ReferenceField Person

Document.defineAll()

# Just to make sure things are sane
assert.equal Document._delayed.length, 0

if Meteor.isServer
  # Initialize the database
  Post.documents.remove {}
  User.documents.remove {}
  UserLink.documents.remove {}
  PostLink.documents.remove {}
  CircularFirst.documents.remove {}
  CircularSecond.documents.remove {}
  Person.documents.remove {}
  Recursive.documents.remove {}
  IdentityGenerator.documents.remove {}
  SpecialPost.documents.remove {}

  Meteor.publish null, ->
    Post.documents.find()
  # User is already published as Meteor.users
  Meteor.publish null, ->
    UserLink.documents.find()
  Meteor.publish null, ->
    PostLink.documents.find()
  Meteor.publish null, ->
    CircularFirst.documents.find()
  Meteor.publish null, ->
    CircularSecond.documents.find()
  Meteor.publish null, ->
    Person.documents.find()
  Meteor.publish null, ->
    Recursive.documents.find()
  Meteor.publish null, ->
    IdentityGenerator.documents.find()
  Meteor.publish null, ->
    SpecialPost.documents.find()

ALL = [User, UserLink, PostLink, CircularSecond, CircularFirst, Person, Post, Recursive, IdentityGenerator, SpecialPost]

testDocumentList = (test, list) ->
  test.equal Document.list, list, "expected: #{ (d.Meta._name for d in list) } vs. actual: #{ (d.Meta._name for d in Document.list) }"

testDefinition = (test) ->
  test.equal Post.Meta._name, 'Post'
  test.equal Post.Meta.parent, _TestPost.Meta
  test.equal Post.Meta.collection._name, 'Posts'
  test.equal _.size(Post.Meta.fields), 7
  test.instanceOf Post.Meta.fields.author, Person._ReferenceField
  test.isNull Post.Meta.fields.author.ancestorArray, Post.Meta.fields.author.ancestorArray
  test.isTrue Post.Meta.fields.author.required
  test.equal Post.Meta.fields.author.sourcePath, 'author'
  test.equal Post.Meta.fields.author.sourceDocument, Post
  test.equal Post.Meta.fields.author.targetDocument, Person
  test.equal Post.Meta.fields.author.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.author.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.author.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.author.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.author.fields, ['username', 'displayName', 'field1', 'field2']
  test.equal Post.Meta.fields.author.reverseName, 'posts'
  test.equal Post.Meta.fields.author.reverseFields, ['body', 'subdocument.body', 'nested.body']
  test.instanceOf Post.Meta.fields.subscribers, Person._ReferenceField
  test.equal Post.Meta.fields.subscribers.ancestorArray, 'subscribers'
  test.isTrue Post.Meta.fields.subscribers.required
  test.equal Post.Meta.fields.subscribers.sourcePath, 'subscribers'
  test.equal Post.Meta.fields.subscribers.sourceDocument, Post
  test.equal Post.Meta.fields.subscribers.targetDocument, Person
  test.equal Post.Meta.fields.subscribers.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.subscribers.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.subscribers.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.subscribers.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.subscribers.fields, []
  test.isNull Post.Meta.fields.subscribers.reverseName
  test.equal Post.Meta.fields.subscribers.reverseFields, []
  test.instanceOf Post.Meta.fields.reviewers, Person._ReferenceField
  test.equal Post.Meta.fields.reviewers.ancestorArray, 'reviewers'
  test.isTrue Post.Meta.fields.reviewers.required
  test.equal Post.Meta.fields.reviewers.sourcePath, 'reviewers'
  test.equal Post.Meta.fields.reviewers.sourceDocument, Post
  test.equal Post.Meta.fields.reviewers.targetDocument, Person
  test.equal Post.Meta.fields.reviewers.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.reviewers.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.reviewers.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.reviewers.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.reviewers.fields, [username: 1]
  test.isNull Post.Meta.fields.reviewers.reverseName
  test.equal Post.Meta.fields.reviewers.reverseFields, []
  test.equal _.size(Post.Meta.fields.subdocument), 3
  test.instanceOf Post.Meta.fields.subdocument.person, Person._ReferenceField
  test.isNull Post.Meta.fields.subdocument.person.ancestorArray, Post.Meta.fields.subdocument.person.ancestorArray
  test.isFalse Post.Meta.fields.subdocument.person.required
  test.equal Post.Meta.fields.subdocument.person.sourcePath, 'subdocument.person'
  test.equal Post.Meta.fields.subdocument.person.sourceDocument, Post
  test.equal Post.Meta.fields.subdocument.person.targetDocument, Person
  test.equal Post.Meta.fields.subdocument.person.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.person.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.subdocument.person.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.person.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.subdocument.person.fields, ['username', 'displayName', 'field1', 'field2']
  test.isNull Post.Meta.fields.subdocument.person.reverseName
  test.equal Post.Meta.fields.subdocument.person.reverseFields, []
  test.instanceOf Post.Meta.fields.subdocument.persons, Person._ReferenceField
  test.equal Post.Meta.fields.subdocument.persons.ancestorArray, 'subdocument.persons'
  test.isTrue Post.Meta.fields.subdocument.persons.required
  test.equal Post.Meta.fields.subdocument.persons.sourcePath, 'subdocument.persons'
  test.equal Post.Meta.fields.subdocument.persons.sourceDocument, Post
  test.equal Post.Meta.fields.subdocument.persons.targetDocument, Person
  test.equal Post.Meta.fields.subdocument.persons.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.persons.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.subdocument.persons.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.persons.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.subdocument.persons.fields, ['username', 'displayName', 'field1', 'field2']
  test.isNull Post.Meta.fields.subdocument.persons.reverseName
  test.equal Post.Meta.fields.subdocument.persons.reverseFields, []
  test.instanceOf Post.Meta.fields.subdocument.slug, Person._GeneratedField
  test.isNull Post.Meta.fields.subdocument.slug.ancestorArray, Post.Meta.fields.subdocument.slug.ancestorArray
  test.isTrue _.isFunction Post.Meta.fields.subdocument.slug.generator
  test.equal Post.Meta.fields.subdocument.slug.sourcePath, 'subdocument.slug'
  test.equal Post.Meta.fields.subdocument.slug.sourceDocument, Post
  test.equal Post.Meta.fields.subdocument.slug.targetDocument, Post
  test.equal Post.Meta.fields.subdocument.slug.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.slug.targetCollection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.slug.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.slug.targetDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.subdocument.slug.fields, ['body', 'subdocument.body']
  test.isUndefined Post.Meta.fields.subdocument.slug.reverseName
  test.isUndefined Post.Meta.fields.subdocument.slug.reverseFields
  test.equal _.size(Post.Meta.fields.nested), 3
  test.instanceOf Post.Meta.fields.nested.required, Person._ReferenceField
  test.equal Post.Meta.fields.nested.required.ancestorArray, 'nested'
  test.isTrue Post.Meta.fields.nested.required.required
  test.equal Post.Meta.fields.nested.required.sourcePath, 'nested.required'
  test.equal Post.Meta.fields.nested.required.sourceDocument, Post
  test.equal Post.Meta.fields.nested.required.targetDocument, Person
  test.equal Post.Meta.fields.nested.required.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.nested.required.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.nested.required.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.nested.required.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.nested.required.fields, ['username', 'displayName', 'field1', 'field2']
  test.equal Post.Meta.fields.nested.required.reverseName, 'nestedPosts'
  test.equal Post.Meta.fields.nested.required.reverseFields, ['body', 'subdocument.body', 'nested.body']
  test.instanceOf Post.Meta.fields.nested.optional, Person._ReferenceField
  test.equal Post.Meta.fields.nested.optional.ancestorArray, 'nested'
  test.isFalse Post.Meta.fields.nested.optional.required
  test.equal Post.Meta.fields.nested.optional.sourcePath, 'nested.optional'
  test.equal Post.Meta.fields.nested.optional.sourceDocument, Post
  test.equal Post.Meta.fields.nested.optional.targetDocument, Person
  test.equal Post.Meta.fields.nested.optional.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.nested.optional.targetCollection._name, 'Persons'
  test.equal Post.Meta.fields.nested.optional.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.nested.optional.targetDocument.Meta.collection._name, 'Persons'
  test.equal Post.Meta.fields.nested.optional.fields, ['username']
  test.isNull Post.Meta.fields.nested.optional.reverseName
  test.equal Post.Meta.fields.nested.optional.reverseFields, []
  test.instanceOf Post.Meta.fields.nested.slug, Person._GeneratedField
  test.equal Post.Meta.fields.nested.slug.ancestorArray, 'nested'
  test.isTrue _.isFunction Post.Meta.fields.nested.slug.generator
  test.equal Post.Meta.fields.nested.slug.sourcePath, 'nested.slug'
  test.equal Post.Meta.fields.nested.slug.sourceDocument, Post
  test.equal Post.Meta.fields.nested.slug.targetDocument, Post
  test.equal Post.Meta.fields.nested.slug.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.nested.slug.targetCollection._name, 'Posts'
  test.equal Post.Meta.fields.nested.slug.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.nested.slug.targetDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.nested.slug.fields, ['body', 'nested.body']
  test.isUndefined Post.Meta.fields.nested.slug.reverseName
  test.isUndefined Post.Meta.fields.nested.slug.reverseFields
  test.instanceOf Post.Meta.fields.slug, Person._GeneratedField
  test.isNull Post.Meta.fields.slug.ancestorArray, Post.Meta.fields.slug.ancestorArray
  test.isTrue _.isFunction Post.Meta.fields.slug.generator
  test.equal Post.Meta.fields.slug.sourcePath, 'slug'
  test.equal Post.Meta.fields.slug.sourceDocument, Post
  test.equal Post.Meta.fields.slug.targetDocument, Post
  test.equal Post.Meta.fields.slug.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.slug.targetCollection._name, 'Posts'
  test.equal Post.Meta.fields.slug.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.slug.targetDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.slug.fields, ['body', 'subdocument.body']
  test.isUndefined Post.Meta.fields.slug.reverseName
  test.isUndefined Post.Meta.fields.slug.reverseFields
  test.instanceOf Post.Meta.fields.tags, Person._GeneratedField
  test.equal Post.Meta.fields.tags.ancestorArray, 'tags'
  test.isTrue _.isFunction Post.Meta.fields.tags.generator
  test.equal Post.Meta.fields.tags.sourcePath, 'tags'
  test.equal Post.Meta.fields.tags.sourceDocument, Post
  test.equal Post.Meta.fields.tags.targetDocument, Post
  test.equal Post.Meta.fields.tags.sourceCollection._name, 'Posts'
  test.equal Post.Meta.fields.tags.targetCollection._name, 'Posts'
  test.equal Post.Meta.fields.tags.sourceDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.tags.targetDocument.Meta.collection._name, 'Posts'
  test.equal Post.Meta.fields.tags.fields, ['body', 'subdocument.body', 'nested.body']
  test.isUndefined Post.Meta.fields.tags.reverseName
  test.isUndefined Post.Meta.fields.tags.reverseFields

  test.equal User.Meta._name, 'User'
  test.isFalse User.Meta.parent
  test.equal User.Meta.collection._name, 'users'
  test.equal _.size(User.Meta.fields), 0

  test.equal UserLink.Meta._name, 'UserLink'
  test.isFalse UserLink.Meta.parent
  test.equal UserLink.Meta.collection._name, 'UserLinks'
  test.equal _.size(UserLink.Meta.fields), 1
  test.instanceOf UserLink.Meta.fields.user, UserLink._ReferenceField
  test.isNull UserLink.Meta.fields.user.ancestorArray, UserLink.Meta.fields.user.ancestorArray
  test.isFalse UserLink.Meta.fields.user.required
  test.equal UserLink.Meta.fields.user.sourcePath, 'user'
  test.equal UserLink.Meta.fields.user.sourceDocument, UserLink
  test.equal UserLink.Meta.fields.user.targetDocument, User
  test.equal UserLink.Meta.fields.user.sourceCollection._name, 'UserLinks'
  test.equal UserLink.Meta.fields.user.targetCollection._name, 'users'
  test.equal UserLink.Meta.fields.user.sourceDocument.Meta.collection._name, 'UserLinks'
  test.equal UserLink.Meta.fields.user.fields, ['username']
  test.isNull UserLink.Meta.fields.user.reverseName
  test.equal UserLink.Meta.fields.user.reverseFields, []

  test.equal PostLink.Meta._name, 'PostLink'
  test.equal PostLink.Meta.parent, _TestPostLink.Meta
  test.equal PostLink.Meta.collection._name, 'PostLinks'
  test.equal _.size(PostLink.Meta.fields), 1
  test.instanceOf PostLink.Meta.fields.post, PostLink._ReferenceField
  test.isNull PostLink.Meta.fields.post.ancestorArray, PostLink.Meta.fields.post.ancestorArray
  test.isTrue PostLink.Meta.fields.post.required
  test.equal PostLink.Meta.fields.post.sourcePath, 'post'
  test.equal PostLink.Meta.fields.post.sourceDocument, PostLink
  test.equal PostLink.Meta.fields.post.targetDocument, Post
  test.equal PostLink.Meta.fields.post.sourceCollection._name, 'PostLinks'
  test.equal PostLink.Meta.fields.post.targetCollection._name, 'Posts'
  test.equal PostLink.Meta.fields.post.sourceDocument.Meta.collection._name, 'PostLinks'
  test.equal PostLink.Meta.fields.post.fields, ['subdocument.person', 'subdocument.persons']
  test.isNull PostLink.Meta.fields.post.reverseName
  test.equal PostLink.Meta.fields.post.reverseFields, []

  test.equal CircularFirst.Meta._name, 'CircularFirst'
  test.equal CircularFirst.Meta.parent, _TestCircularFirst.Meta
  test.equal CircularFirst.Meta.collection._name, 'CircularFirsts'
  test.equal _.size(CircularFirst.Meta.fields), 1
  test.instanceOf CircularFirst.Meta.fields.second, CircularFirst._ReferenceField
  test.isNull CircularFirst.Meta.fields.second.ancestorArray, CircularFirst.Meta.fields.second.ancestorArray
  test.isTrue CircularFirst.Meta.fields.second.required
  test.equal CircularFirst.Meta.fields.second.sourcePath, 'second'
  test.equal CircularFirst.Meta.fields.second.sourceDocument, CircularFirst
  test.equal CircularFirst.Meta.fields.second.targetDocument, CircularSecond
  test.equal CircularFirst.Meta.fields.second.sourceCollection._name, 'CircularFirsts'
  test.equal CircularFirst.Meta.fields.second.targetCollection._name, 'CircularSeconds'
  test.equal CircularFirst.Meta.fields.second.sourceDocument.Meta.collection._name, 'CircularFirsts'
  test.equal CircularFirst.Meta.fields.second.targetDocument.Meta.collection._name, 'CircularSeconds'
  test.equal CircularFirst.Meta.fields.second.fields, ['content']
  test.isNull CircularFirst.Meta.fields.second.reverseName
  test.equal CircularFirst.Meta.fields.second.reverseFields, []

  test.equal CircularSecond.Meta._name, 'CircularSecond'
  test.isFalse CircularSecond.Meta.parent
  test.equal CircularSecond.Meta.collection._name, 'CircularSeconds'
  test.equal _.size(CircularSecond.Meta.fields), 1
  test.instanceOf CircularSecond.Meta.fields.first, CircularSecond._ReferenceField
  test.isNull CircularSecond.Meta.fields.first.ancestorArray, CircularSecond.Meta.fields.first.ancestorArray
  test.isFalse CircularSecond.Meta.fields.first.required
  test.equal CircularSecond.Meta.fields.first.sourcePath, 'first'
  test.equal CircularSecond.Meta.fields.first.sourceDocument, CircularSecond
  test.equal CircularSecond.Meta.fields.first.targetDocument, CircularFirst
  test.equal CircularSecond.Meta.fields.first.sourceCollection._name, 'CircularSeconds'
  test.equal CircularSecond.Meta.fields.first.targetCollection._name, 'CircularFirsts'
  test.equal CircularSecond.Meta.fields.first.sourceDocument.Meta.collection._name, 'CircularSeconds'
  test.equal CircularSecond.Meta.fields.first.targetDocument.Meta.collection._name, 'CircularFirsts'
  test.equal CircularSecond.Meta.fields.first.fields, ['content']
  test.isNull CircularSecond.Meta.fields.first.reverseName
  test.equal CircularSecond.Meta.fields.first.reverseFields, []

  test.equal Person.Meta._name, 'Person'
  test.isFalse Person.Meta.parent
  test.equal Person.Meta._name, 'Person'
  test.equal Person.Meta.collection._name, 'Persons'
  test.equal _.size(Person.Meta.fields), 3
  test.instanceOf Person.Meta.fields.posts, Person._ReferenceField
  test.equal Person.Meta.fields.posts.ancestorArray, 'posts'
  test.isTrue Person.Meta.fields.posts.required
  test.equal Person.Meta.fields.posts.sourcePath, 'posts'
  test.equal Person.Meta.fields.posts.sourceDocument, Person
  test.equal Person.Meta.fields.posts.targetDocument, Post
  test.equal Person.Meta.fields.posts.sourceCollection._name, 'Persons'
  test.equal Person.Meta.fields.posts.targetCollection._name, 'Posts'
  test.equal Person.Meta.fields.posts.sourceDocument.Meta.collection._name, 'Persons'
  test.equal Person.Meta.fields.posts.targetDocument.Meta.collection._name, 'Posts'
  test.equal Person.Meta.fields.posts.fields, ['body', 'subdocument.body', 'nested.body']
  test.isNull Person.Meta.fields.posts.reverseName
  test.equal Person.Meta.fields.posts.reverseFields, []
  test.instanceOf Person.Meta.fields.nestedPosts, Person._ReferenceField
  test.equal Person.Meta.fields.nestedPosts.ancestorArray, 'nestedPosts'
  test.isTrue Person.Meta.fields.nestedPosts.required
  test.equal Person.Meta.fields.nestedPosts.sourcePath, 'nestedPosts'
  test.equal Person.Meta.fields.nestedPosts.sourceDocument, Person
  test.equal Person.Meta.fields.nestedPosts.targetDocument, Post
  test.equal Person.Meta.fields.nestedPosts.sourceCollection._name, 'Persons'
  test.equal Person.Meta.fields.nestedPosts.targetCollection._name, 'Posts'
  test.equal Person.Meta.fields.nestedPosts.sourceDocument.Meta.collection._name, 'Persons'
  test.equal Person.Meta.fields.nestedPosts.targetDocument.Meta.collection._name, 'Posts'
  test.equal Person.Meta.fields.nestedPosts.fields, ['body', 'subdocument.body', 'nested.body']
  test.isNull Person.Meta.fields.nestedPosts.reverseName
  test.equal Person.Meta.fields.nestedPosts.reverseFields, []
  test.instanceOf Person.Meta.fields.count, Person._GeneratedField
  test.isNull Person.Meta.fields.count.ancestorArray, Person.Meta.fields.count.ancestorArray
  test.isTrue _.isFunction Person.Meta.fields.count.generator
  test.equal Person.Meta.fields.count.sourcePath, 'count'
  test.equal Person.Meta.fields.count.sourceDocument, Person
  test.equal Person.Meta.fields.count.targetDocument, Person
  test.equal Person.Meta.fields.count.sourceCollection._name, 'Persons'
  test.equal Person.Meta.fields.count.targetCollection._name, 'Persons'
  test.equal Person.Meta.fields.count.sourceDocument.Meta.collection._name, 'Persons'
  test.equal Person.Meta.fields.count.targetDocument.Meta.collection._name, 'Persons'
  test.equal Person.Meta.fields.count.fields, ['posts', 'nestedPosts']
  test.isUndefined Person.Meta.fields.count.reverseName
  test.isUndefined Person.Meta.fields.count.reverseFields

  test.equal Recursive.Meta._name, 'Recursive'
  test.isFalse Recursive.Meta.parent
  test.equal Recursive.Meta.collection._name, 'Recursives'
  test.equal _.size(Recursive.Meta.fields), 1
  test.instanceOf Recursive.Meta.fields.other, Recursive._ReferenceField
  test.isNull Recursive.Meta.fields.other.ancestorArray, Recursive.Meta.fields.other.ancestorArray
  test.isFalse Recursive.Meta.fields.other.required
  test.equal Recursive.Meta.fields.other.sourcePath, 'other'
  test.equal Recursive.Meta.fields.other.sourceDocument, Recursive
  test.equal Recursive.Meta.fields.other.targetDocument, Recursive
  test.equal Recursive.Meta.fields.other.sourceCollection._name, 'Recursives'
  test.equal Recursive.Meta.fields.other.targetCollection._name, 'Recursives'
  test.equal Recursive.Meta.fields.other.sourceDocument.Meta.collection._name, 'Recursives'
  test.equal Recursive.Meta.fields.other.targetDocument.Meta.collection._name, 'Recursives'
  test.equal Recursive.Meta.fields.other.fields, ['content']
  test.isNull Recursive.Meta.fields.other.reverseName
  test.equal Recursive.Meta.fields.other.reverseFields, []

  test.equal IdentityGenerator.Meta._name, 'IdentityGenerator'
  test.isFalse IdentityGenerator.Meta.parent
  test.equal IdentityGenerator.Meta.collection._name, 'IdentityGenerators'
  test.equal _.size(IdentityGenerator.Meta.fields), 2
  test.instanceOf IdentityGenerator.Meta.fields.result, IdentityGenerator._GeneratedField
  test.isNull IdentityGenerator.Meta.fields.result.ancestorArray, IdentityGenerator.Meta.fields.result.ancestorArray
  test.isTrue _.isFunction IdentityGenerator.Meta.fields.result.generator
  test.equal IdentityGenerator.Meta.fields.result.sourcePath, 'result'
  test.equal IdentityGenerator.Meta.fields.result.sourceDocument, IdentityGenerator
  test.equal IdentityGenerator.Meta.fields.result.targetDocument, IdentityGenerator
  test.equal IdentityGenerator.Meta.fields.result.sourceCollection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.result.targetCollection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.result.sourceDocument.Meta.collection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.result.targetDocument.Meta.collection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.result.fields, ['source']
  test.isUndefined IdentityGenerator.Meta.fields.result.reverseName
  test.isUndefined IdentityGenerator.Meta.fields.result.reverseFields
  test.instanceOf IdentityGenerator.Meta.fields.results, IdentityGenerator._GeneratedField
  test.equal IdentityGenerator.Meta.fields.results.ancestorArray, 'results'
  test.isTrue _.isFunction IdentityGenerator.Meta.fields.results.generator
  test.equal IdentityGenerator.Meta.fields.results.sourcePath, 'results'
  test.equal IdentityGenerator.Meta.fields.results.sourceDocument, IdentityGenerator
  test.equal IdentityGenerator.Meta.fields.results.targetDocument, IdentityGenerator
  test.equal IdentityGenerator.Meta.fields.results.sourceCollection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.results.targetCollection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.results.sourceDocument.Meta.collection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.results.targetDocument.Meta.collection._name, 'IdentityGenerators'
  test.equal IdentityGenerator.Meta.fields.results.fields, ['source']
  test.isUndefined IdentityGenerator.Meta.fields.results.reverseName
  test.isUndefined IdentityGenerator.Meta.fields.results.reverseFields

  test.equal SpecialPost.Meta._name, 'SpecialPost'
  test.equal SpecialPost.Meta.parent, _TestPost2.Meta
  test.equal SpecialPost.Meta.collection._name, 'SpecialPosts'
  test.equal _.size(SpecialPost.Meta.fields), 8
  test.instanceOf SpecialPost.Meta.fields.author, Person._ReferenceField
  test.isNull SpecialPost.Meta.fields.author.ancestorArray, SpecialPost.Meta.fields.author.ancestorArray
  test.isTrue SpecialPost.Meta.fields.author.required
  test.equal SpecialPost.Meta.fields.author.sourcePath, 'author'
  test.equal SpecialPost.Meta.fields.author.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.author.targetDocument, Person
  test.equal SpecialPost.Meta.fields.author.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.author.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.author.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.author.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.author.fields, ['username', 'displayName', 'field1', 'field2']
  test.equal SpecialPost.Meta.fields.author.reverseName, 'posts'
  test.equal SpecialPost.Meta.fields.author.reverseFields, ['body', 'subdocument.body', 'nested.body']
  test.instanceOf SpecialPost.Meta.fields.subscribers, Person._ReferenceField
  test.equal SpecialPost.Meta.fields.subscribers.ancestorArray, 'subscribers'
  test.isTrue SpecialPost.Meta.fields.subscribers.required
  test.equal SpecialPost.Meta.fields.subscribers.sourcePath, 'subscribers'
  test.equal SpecialPost.Meta.fields.subscribers.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.subscribers.targetDocument, Person
  test.equal SpecialPost.Meta.fields.subscribers.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subscribers.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subscribers.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subscribers.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subscribers.fields, []
  test.isNull SpecialPost.Meta.fields.subscribers.reverseName
  test.equal SpecialPost.Meta.fields.subscribers.reverseFields, []
  test.instanceOf SpecialPost.Meta.fields.reviewers, Person._ReferenceField
  test.equal SpecialPost.Meta.fields.reviewers.ancestorArray, 'reviewers'
  test.isTrue SpecialPost.Meta.fields.reviewers.required
  test.equal SpecialPost.Meta.fields.reviewers.sourcePath, 'reviewers'
  test.equal SpecialPost.Meta.fields.reviewers.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.reviewers.targetDocument, Person
  test.equal SpecialPost.Meta.fields.reviewers.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.reviewers.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.reviewers.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.reviewers.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.reviewers.fields, [username: 1]
  test.isNull SpecialPost.Meta.fields.reviewers.reverseName
  test.equal SpecialPost.Meta.fields.reviewers.reverseFields, []
  test.equal _.size(SpecialPost.Meta.fields.subdocument), 3
  test.instanceOf SpecialPost.Meta.fields.subdocument.person, Person._ReferenceField
  test.isNull SpecialPost.Meta.fields.subdocument.person.ancestorArray, SpecialPost.Meta.fields.subdocument.person.ancestorArray
  test.isFalse SpecialPost.Meta.fields.subdocument.person.required
  test.equal SpecialPost.Meta.fields.subdocument.person.sourcePath, 'subdocument.person'
  test.equal SpecialPost.Meta.fields.subdocument.person.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.subdocument.person.targetDocument, Person
  test.equal SpecialPost.Meta.fields.subdocument.person.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.person.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subdocument.person.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.person.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subdocument.person.fields, ['username', 'displayName', 'field1', 'field2']
  test.isNull SpecialPost.Meta.fields.subdocument.person.reverseName
  test.equal SpecialPost.Meta.fields.subdocument.person.reverseFields, []
  test.instanceOf SpecialPost.Meta.fields.subdocument.persons, Person._ReferenceField
  test.equal SpecialPost.Meta.fields.subdocument.persons.ancestorArray, 'subdocument.persons'
  test.isTrue SpecialPost.Meta.fields.subdocument.persons.required
  test.equal SpecialPost.Meta.fields.subdocument.persons.sourcePath, 'subdocument.persons'
  test.equal SpecialPost.Meta.fields.subdocument.persons.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.subdocument.persons.targetDocument, Person
  test.equal SpecialPost.Meta.fields.subdocument.persons.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.persons.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subdocument.persons.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.persons.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.subdocument.persons.fields, ['username', 'displayName', 'field1', 'field2']
  test.isNull SpecialPost.Meta.fields.subdocument.persons.reverseName
  test.equal SpecialPost.Meta.fields.subdocument.persons.reverseFields, []
  test.instanceOf SpecialPost.Meta.fields.subdocument.slug, Person._GeneratedField
  test.isNull SpecialPost.Meta.fields.subdocument.slug.ancestorArray, SpecialPost.Meta.fields.subdocument.slug.ancestorArray
  test.isTrue _.isFunction SpecialPost.Meta.fields.subdocument.slug.generator
  test.equal SpecialPost.Meta.fields.subdocument.slug.sourcePath, 'subdocument.slug'
  test.equal SpecialPost.Meta.fields.subdocument.slug.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.subdocument.slug.targetDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.subdocument.slug.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.slug.targetCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.slug.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.slug.targetDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.subdocument.slug.fields, ['body', 'subdocument.body']
  test.isUndefined SpecialPost.Meta.fields.subdocument.slug.reverseName
  test.isUndefined SpecialPost.Meta.fields.subdocument.slug.reverseFields
  test.equal _.size(SpecialPost.Meta.fields.nested), 3
  test.instanceOf SpecialPost.Meta.fields.nested.required, Person._ReferenceField
  test.equal SpecialPost.Meta.fields.nested.required.ancestorArray, 'nested'
  test.isTrue SpecialPost.Meta.fields.nested.required.required
  test.equal SpecialPost.Meta.fields.nested.required.sourcePath, 'nested.required'
  test.equal SpecialPost.Meta.fields.nested.required.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.nested.required.targetDocument, Person
  test.equal SpecialPost.Meta.fields.nested.required.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.required.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.nested.required.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.required.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.nested.required.fields, ['username', 'displayName', 'field1', 'field2']
  test.equal SpecialPost.Meta.fields.nested.required.reverseName, 'nestedPosts'
  test.equal SpecialPost.Meta.fields.nested.required.reverseFields, ['body', 'subdocument.body', 'nested.body']
  test.instanceOf SpecialPost.Meta.fields.nested.optional, Person._ReferenceField
  test.equal SpecialPost.Meta.fields.nested.optional.ancestorArray, 'nested'
  test.isFalse SpecialPost.Meta.fields.nested.optional.required
  test.equal SpecialPost.Meta.fields.nested.optional.sourcePath, 'nested.optional'
  test.equal SpecialPost.Meta.fields.nested.optional.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.nested.optional.targetDocument, Person
  test.equal SpecialPost.Meta.fields.nested.optional.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.optional.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.nested.optional.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.optional.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.nested.optional.fields, ['username']
  test.isNull SpecialPost.Meta.fields.nested.optional.reverseName
  test.equal SpecialPost.Meta.fields.nested.optional.reverseFields, []
  test.instanceOf SpecialPost.Meta.fields.nested.slug, Person._GeneratedField
  test.equal SpecialPost.Meta.fields.nested.slug.ancestorArray, 'nested'
  test.isTrue _.isFunction SpecialPost.Meta.fields.nested.slug.generator
  test.equal SpecialPost.Meta.fields.nested.slug.sourcePath, 'nested.slug'
  test.equal SpecialPost.Meta.fields.nested.slug.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.nested.slug.targetDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.nested.slug.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.slug.targetCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.slug.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.slug.targetDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.nested.slug.fields, ['body', 'nested.body']
  test.isUndefined SpecialPost.Meta.fields.nested.slug.reverseName
  test.isUndefined SpecialPost.Meta.fields.nested.slug.reverseFields
  test.instanceOf SpecialPost.Meta.fields.slug, Person._GeneratedField
  test.isNull SpecialPost.Meta.fields.slug.ancestorArray, SpecialPost.Meta.fields.slug.ancestorArray
  test.isTrue _.isFunction SpecialPost.Meta.fields.slug.generator
  test.equal SpecialPost.Meta.fields.slug.sourcePath, 'slug'
  test.equal SpecialPost.Meta.fields.slug.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.slug.targetDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.slug.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.slug.targetCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.slug.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.slug.targetDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.slug.fields, ['body', 'subdocument.body']
  test.isUndefined SpecialPost.Meta.fields.slug.reverseName
  test.isUndefined SpecialPost.Meta.fields.slug.reverseFields
  test.instanceOf SpecialPost.Meta.fields.tags, Person._GeneratedField
  test.equal SpecialPost.Meta.fields.tags.ancestorArray, 'tags'
  test.isTrue _.isFunction SpecialPost.Meta.fields.tags.generator
  test.equal SpecialPost.Meta.fields.tags.sourcePath, 'tags'
  test.equal SpecialPost.Meta.fields.tags.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.tags.targetDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.tags.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.tags.targetCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.tags.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.tags.targetDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.tags.fields, ['body', 'subdocument.body', 'nested.body']
  test.isUndefined SpecialPost.Meta.fields.tags.reverseName
  test.isUndefined SpecialPost.Meta.fields.tags.reverseFields
  test.instanceOf SpecialPost.Meta.fields.special, Person._ReferenceField
  test.isNull SpecialPost.Meta.fields.special.ancestorArray, SpecialPost.Meta.fields.special.ancestorArray
  test.isTrue SpecialPost.Meta.fields.special.required
  test.equal SpecialPost.Meta.fields.special.sourcePath, 'special'
  test.equal SpecialPost.Meta.fields.special.sourceDocument, SpecialPost
  test.equal SpecialPost.Meta.fields.special.targetDocument, Person
  test.equal SpecialPost.Meta.fields.special.sourceCollection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.special.targetCollection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.special.sourceDocument.Meta.collection._name, 'SpecialPosts'
  test.equal SpecialPost.Meta.fields.special.targetDocument.Meta.collection._name, 'Persons'
  test.equal SpecialPost.Meta.fields.special.fields, []
  test.isNull SpecialPost.Meta.fields.special.reverseName
  test.equal SpecialPost.Meta.fields.special.reverseFields, []

  testDocumentList test, ALL

plainObject = (obj) ->
  return obj unless _.isObject obj

  return (plainObject o for o in obj) if _.isArray obj

  keys = _.keys obj
  values = (plainObject o for o in _.values obj)

  _.object keys, values

testAsyncMulti 'meteor-peerdb - references', [
  (test, expect) ->
    testDefinition test

    # We should be able to call defineAll multiple times
    Document.defineAll()

    testDefinition test

    Person.documents.insert
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person1Id
        @person1Id = person1Id

    Person.documents.insert
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person2Id
        @person2Id = person2Id

    Person.documents.insert
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person3Id
        @person3Id = person3Id

    # Sleep so that observers have time to run (but no post is yet made, so nothing really happens)
    # We want to wait here so that we catch possible errors in source observers, otherwise target
    # observers can patch things up, for example, if we create a post first and target observers
    # (triggered by person inserts, but pending) run afterwards, then they can patch things which
    # should in fact be done by source observers (on post), like setting usernames in post's
    # references to persons
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
      count: 0
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      count: 0
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      count: 0

    Post.documents.insert
      author:
        _id: @person1._id
        # To test what happens if all fields are not up to date
        username: 'wrong'
        displayName: 'wrong'
        field1: 'wrong'
        field2: 'wrong'
      subscribers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
        username: 'wrong'
      ,
        _id: @person3._id
        username: 'wrong'
      ]
      subdocument:
        person:
          _id: @person2._id
          username: 'wrong'
        persons: [
          _id: @person2._id
        ,
          _id: @person3._id
        ]
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: 'wrong'
          displayName: 'wrong'
        optional:
          _id: @person3._id
          username: 'wrong'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # We inserted the document only with ids - subdocuments should be
    # automatically populated with additional fields as defined in @ReferenceField
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
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
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person1Id,
      $set:
        username: 'person1a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    Person.documents.update @person2Id,
      $set:
        username: 'person2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged together to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    Person.documents.update @person3Id,
      $set:
        username: 'person3a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1a'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
      posts: [
        _id: @postId
        body: 'FooBar'
        nested: [
          body: 'NestedFooBar'
        ]
        subdocument:
          body: 'SubdocumentFooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2a'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      nestedPosts: [
        _id: @postId
        body: 'FooBar'
        nested: [
          body: 'NestedFooBar'
        ]
        subdocument:
          body: 'SubdocumentFooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3a'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      count: 0

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # All persons had usernames changed, they should
    # be updated in the post as well, automatically
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
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
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.remove @person3Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # person3 was removed, references should be removed as well, automatically
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
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
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional: null
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.remove @person2Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # person2 was removed, references should be removed as well, automatically,
    # but lists should be kept as empty lists
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: []
      reviewers: []
      subdocument:
        person: null
        persons: []
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: []
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
      ]

    Person.documents.remove @person1Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # If directly referenced document is removed, dependency is removed as well
    test.isFalse @post, @post
]

Tinytest.add 'meteor-peerdb - invalid optional', (test) ->
  test.throws ->
    class BadPost extends Document
      @Meta
        name: 'BadPost'
        fields: =>
          reviewers: [@ReferenceField Person, ['username'], false]
  , /Reference field directly in an array cannot be optional/

  # Invalid document should not be added to the list
  testDocumentList test, ALL

  # Should not try to define invalid document again
  Document.defineAll()

Tinytest.add 'meteor-peerdb - invalid nested arrays', (test) ->
  test.throws ->
    class BadPost extends Document
      @Meta
        name: 'BadPost'
        fields: =>
          nested: [
            many: [@ReferenceField Person, ['username']]
          ]
  , /Field cannot be in a nested array/

  # Invalid document should not be added to the list
  testDocumentList test, ALL

  # Should not try to define invalid document again
  Document.defineAll()

Tinytest.add 'meteor-peerdb - invalid name', (test) ->
  test.throws ->
    class BadPost extends Document
      @Meta
        name: 'Post'
  , /Document name does not match class name/

  # Invalid document should not be added to the list
  testDocumentList test, ALL

  # Should not try to define invalid document again
  Document.defineAll()

testAsyncMulti 'meteor-peerdb - circular changes', [
  (test, expect) ->
    Log._intercept 3 if Meteor.isServer # Three to see if we catch more than expected

    CircularFirst.documents.insert
      second: null
      content: 'FooBar 1'
    ,
      expect (error, circularFirstId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue circularFirstId
        @circularFirstId = circularFirstId

    CircularSecond.documents.insert
      first: null
      content: 'FooBar 2'
    ,
      expect (error, circularSecondId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue circularSecondId
        @circularSecondId = circularSecondId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf(@circularFirstId) isnt -1
      test.isTrue _.isString(i), i
      intercepted = EJSON.parse i

      test.equal intercepted.message, "Document's '#{ @circularFirstId }' field 'second' was updated with an invalid value: null"
      test.equal intercepted.level, 'error'

    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second: null
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first: null
      content: 'FooBar 2'

    CircularFirst.documents.update @circularFirstId,
      $set:
        second:
          _id: @circularSecondId
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first: null
      content: 'FooBar 2'

    CircularSecond.documents.update @circularSecondId,
      $set:
        first:
          _id: @circularFirstId
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first:
        _id: @circularFirstId
        content: 'FooBar 1'
      content: 'FooBar 2'

    CircularFirst.documents.update @circularFirstId,
      $set:
        content: 'FooBar 1a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1a'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first:
        _id: @circularFirstId
        content: 'FooBar 1a'
      content: 'FooBar 2'

    CircularSecond.documents.update @circularSecondId,
      $set:
        content: 'FooBar 2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2a'
      content: 'FooBar 1a'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first:
        _id: @circularFirstId
        content: 'FooBar 1a'
      content: 'FooBar 2a'

    CircularSecond.documents.remove @circularSecondId,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.isFalse @circularSecond, @circularSecond

    # If directly referenced document is removed, dependency is removed as well
    test.isFalse @circularFirst, @circularFirst

    Log._intercept 1 if Meteor.isServer

    CircularSecond.documents.insert
      first: null
      content: 'FooBar 2'
    ,
      expect (error, circularSecondId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue circularSecondId
        @circularSecondId = circularSecondId
,
  (test, expect) ->
    CircularFirst.documents.insert
      second:
        _id: @circularSecondId
      content: 'FooBar 1'
    ,
      expect (error, circularFirstId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue circularFirstId
        @circularFirstId = circularFirstId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      test.equal intercepted.length, 0, intercepted

    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first: null
      content: 'FooBar 2'

    CircularSecond.documents.update @circularSecondId,
      $set:
        first:
          _id: @circularFirstId
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.equal @circularFirst,
      _id: @circularFirstId
      _schema: '1.0.0'
      second:
        _id: @circularSecondId
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first:
        _id: @circularFirstId
        content: 'FooBar 1'
      content: 'FooBar 2'

    CircularFirst.documents.remove @circularFirstId,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update document
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @circularFirst = CircularFirst.documents.findOne @circularFirstId,
      transform: null # So that we can use test.equal
    @circularSecond = CircularSecond.documents.findOne @circularSecondId,
      transform: null # So that we can use test.equal

    test.isFalse @circularFirst, @circularFirst

    # If directly referenced but optional document is removed, dependency is not removed as well, but set to null
    test.equal @circularSecond,
      _id: @circularSecondId
      _schema: '1.0.0'
      first: null
      content: 'FooBar 2'
]

testAsyncMulti 'meteor-peerdb - recursive two', [
  (test, expect) ->
    Recursive.documents.insert
      other: null
      content: 'FooBar 1'
    ,
      expect (error, recursive1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue recursive1Id
        @recursive1Id = recursive1Id

    Recursive.documents.insert
      other: null
      content: 'FooBar 2'
    ,
      expect (error, recursive2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue recursive2Id
        @recursive2Id = recursive2Id

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other: null
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      _schema: '1.0.0'
      other: null
      content: 'FooBar 2'

    Recursive.documents.update @recursive1Id,
      $set:
        other:
          _id: @recursive2Id
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      _schema: '1.0.0'
      other: null
      content: 'FooBar 2'

    Recursive.documents.update @recursive2Id,
      $set:
        other:
          _id: @recursive1Id
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1'
    test.equal @recursive2,
      _id: @recursive2Id
      _schema: '1.0.0'
      other:
        _id: @recursive1Id
        content: 'FooBar 1'
      content: 'FooBar 2'

    Recursive.documents.update @recursive1Id,
      $set:
        content: 'FooBar 1a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other:
        _id: @recursive2Id
        content: 'FooBar 2'
      content: 'FooBar 1a'
    test.equal @recursive2,
      _id: @recursive2Id
      _schema: '1.0.0'
      other:
        _id: @recursive1Id
        content: 'FooBar 1a'
      content: 'FooBar 2'

    Recursive.documents.update @recursive2Id,
      $set:
        content: 'FooBar 2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other:
        _id: @recursive2Id
        content: 'FooBar 2a'
      content: 'FooBar 1a'
    test.equal @recursive2,
      _id: @recursive2Id
      _schema: '1.0.0'
      other:
        _id: @recursive1Id
        content: 'FooBar 1a'
      content: 'FooBar 2a'

    Recursive.documents.remove @recursive2Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive1 = Recursive.documents.findOne @recursive1Id,
      transform: null # So that we can use test.equal
    @recursive2 = Recursive.documents.findOne @recursive2Id,
      transform: null # So that we can use test.equal

    test.isFalse @recursive2, @recursive2

    test.equal @recursive1,
      _id: @recursive1Id
      _schema: '1.0.0'
      other: null
      content: 'FooBar 1a'
]

testAsyncMulti 'meteor-peerdb - recursive one', [
  (test, expect) ->
    Recursive.documents.insert
      other: null
      content: 'FooBar'
    ,
      expect (error, recursiveId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue recursiveId
        @recursiveId = recursiveId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive = Recursive.documents.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      _schema: '1.0.0'
      other: null
      content: 'FooBar'

    Recursive.documents.update @recursiveId,
      $set:
        other:
          _id: @recursiveId
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive = Recursive.documents.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      _schema: '1.0.0'
      other:
        _id: @recursiveId
        content: 'FooBar'
      content: 'FooBar'

    Recursive.documents.update @recursiveId,
      $set:
        content: 'FooBara'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive = Recursive.documents.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.equal @recursive,
      _id: @recursiveId
      _schema: '1.0.0'
      other:
        _id: @recursiveId
        content: 'FooBara'
      content: 'FooBara'

    Recursive.documents.remove @recursiveId,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @recursive = Recursive.documents.findOne @recursiveId,
      transform: null # So that we can use test.equal

    test.isFalse @recursive, @recursive
]

if Meteor.isServer
  Tinytest.add 'meteor-peerdb - errors', (test) ->
    Log._intercept 2 # Two to see if we catch more than expected

    postId = Post.documents.insert
      author:
        _id: 'nonexistent'

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(WAIT_TIME)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    test.isTrue _.isString(intercepted[0]), intercepted[0]
    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' is referencing a nonexistent document 'nonexistent'"
    test.equal intercepted.level, 'error'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Post.documents.insert
      subscribers: 'foobar'

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(WAIT_TIME)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    test.isTrue _.isString(intercepted[0]), intercepted[0]
    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'subscribers' was updated with a non-array value: 'foobar'"
    test.equal intercepted.level, 'error'

    Log._intercept 2 # Two to see if we catch more than expected

    postId = Post.documents.insert
      author: null

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(WAIT_TIME)

    intercepted = Log._intercepted()

    test.equal intercepted.length, 1, intercepted

    test.isTrue _.isString(intercepted[0]), intercepted[0]
    intercepted = EJSON.parse intercepted[0]

    test.equal intercepted.message, "Document's '#{ postId }' field 'author' was updated with an invalid value: null"
    test.equal intercepted.level, 'error'

    Log._intercept 1

    userLinkId = UserLink.documents.insert
      user: null

    # Sleep so that observers have time to update documents
    Meteor._sleepForMs(WAIT_TIME)

    intercepted = Log._intercepted()

    # There should be no warning because user is optional
    test.equal intercepted.length, 0, intercepted

testAsyncMulti 'meteor-peerdb - delayed defintion', [
  (test, expect) ->
    class BadPost extends Document
      @Meta
        name: 'BadPost'
        fields: =>
          author: @ReferenceField undefined, ['username']

    Log._intercept 2 # Two to see if we catch more than expected

    # Sleep so that error is shown
    Meteor.setTimeout expect(), 1000 # We need 1000 here because we have a check which runs after 1000 ms to check for delayed defintions
,
  (test, expect) ->
    intercepted = Log._intercepted()

    # One or two because we could intercepted something else as well
    test.isTrue 1 <= intercepted.length <= 2, intercepted

    # Let's find it
    for i in intercepted
      break if i.indexOf('BadPost') isnt -1
    test.isTrue _.isString(i), i
    intercepted = EJSON.parse i

    test.equal intercepted.message.lastIndexOf("Not all delayed document definitions were successfully retried:\nBadPost from"), 0, intercepted.message
    test.equal intercepted.level, 'error'

    testDocumentList test, ALL
    test.equal Document._delayed.length, 1

    # Clear delayed so that we can retry tests without errors
    Document._delayed = []
    Document._clearDelayedCheck()
]

testAsyncMulti 'meteor-peerdb - subdocument fields', [
  (test, expect) ->
    Person.documents.insert
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person1Id
        @person1Id = person1Id

    Person.documents.insert
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person2Id
        @person2Id = person2Id

    Person.documents.insert
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person3Id
        @person3Id = person3Id

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
      count: 0
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      count: 0
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      count: 0

    Post.documents.insert
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
      nested: [
        required:
          _id: @person2._id
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
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
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    PostLink.documents.insert
      post:
        _id: @post._id
    ,
      expect (error, postLinkId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postLinkId
        @postLinkId = postLinkId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @postLink = PostLink.documents.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      _schema: '1.0.0'
      post:
        _id: @post._id
        subdocument:
          person:
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
            field1: @person2.field1
            field2: @person2.field2
          persons: [
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
            field1: @person2.field1
            field2: @person2.field2
          ,
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
            field1: @person3.field1
            field2: @person3.field2
          ]

    Person.documents.update @person2Id,
      $set:
        username: 'person2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal

    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2a'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      nestedPosts: [
        _id: @postId
        body: 'FooBar'
        nested: [
          body: 'NestedFooBar'
        ]
        subdocument:
          body: 'SubdocumentFooBar'
      ]
      count: 1

    @postLink = PostLink.documents.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      _schema: '1.0.0'
      post:
        _id: @post._id
        subdocument:
          person:
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
            field1: @person2.field1
            field2: @person2.field2
          persons: [
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
            field1: @person2.field1
            field2: @person2.field2
          ,
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
            field1: @person3.field1
            field2: @person3.field2
          ]

    Person.documents.remove @person2Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @postLink = PostLink.documents.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.equal @postLink,
      _id: @postLinkId
      _schema: '1.0.0'
      post:
        _id: @post._id
        subdocument:
          person: null
          persons: [
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
            field1: @person3.field1
            field2: @person3.field2
          ]

    Post.documents.remove @post._id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @postLink = PostLink.documents.findOne @postLinkId,
      transform: null # So that we can use test.equal

    test.isFalse @postLink, @postLink
]

testAsyncMulti 'meteor-peerdb - generated fields', [
  (test, expect) ->
    Person.documents.insert
      username: 'person1'
      displayName: 'Person 1'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person1Id
        @person1Id = person1Id

    Person.documents.insert
      username: 'person2'
      displayName: 'Person 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person2Id
        @person2Id = person2Id

    Person.documents.insert
      username: 'person3'
      displayName: 'Person 3'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person3Id
        @person3Id = person3Id

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1'
      displayName: 'Person 1'
      count: 0
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2'
      displayName: 'Person 2'
      count: 0
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3'
      displayName: 'Person 3'
      count: 0

    Post.documents.insert
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
      nested: [
        required:
          _id: @person2._id
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        body: 'FooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged together to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # All persons had usernames changed, they should
    # be updated in the post as well, automatically
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobar-suffix'
        'tag-1-prefix-foobarz-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'subdocument.body': 'SubdocumentFooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged together to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), WAIT_TIME
,
   (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # All persons had usernames changed, they should
    # be updated in the post as well, automatically
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobarz-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'nested.0.body': 'NestedFooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged together to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), WAIT_TIME
,
   (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    # All persons had usernames changed, they should
    # be updated in the post as well, automatically
    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobarz-nestedfoobarz-suffix'
      ]

    Post.documents.update @postId,
      $set:
        body: null
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: null
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: null
        body: 'NestedFooBarZ'
      ]
      body: null
      slug: null
      tags: []

    Post.documents.update @postId,
      $unset:
        body: ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        body: 'NestedFooBarZ'
      ]
      tags: []
]

Tinytest.add 'meteor-peerdb - chain of extended classes', (test) ->
  list = _.clone Document.list

  firstReferenceA = undefined # To force delayed
  secondReferenceA = undefined # To force delayed
  firstReferenceB = undefined # To force delayed
  secondReferenceB = undefined # To force delayed

  class First extends Document
    @Meta
      name: 'First'
      fields: =>
        first: @ReferenceField firstReferenceA

  class Second extends First
    @Meta
      name: 'Second'
      fields: (fields) =>
        fields.second = @ReferenceField Post # Not undefined, but overall meta will still be delayed
        fields

  class Third extends Second
    @Meta
      name: 'Third'
      fields: (fields) =>
        fields.third = @ReferenceField secondReferenceA
        fields

  testDocumentList test, ALL
  test.equal Document._delayed.length, 3
  test.equal Document._delayed[0][0], First
  test.equal Document._delayed[1][0], Second
  test.equal Document._delayed[2][0], Third

  _TestFirst = First

  class First extends First
    @Meta
      name: 'First'
      replaceParent: true
      fields: (fields) =>
        fields.first = @ReferenceField firstReferenceB
        fields

  _TestSecond = Second

  class Second extends Second
    @Meta
      name: 'Second'
      fields: (fields) =>
        fields.second = @ReferenceField Person # Not undefined, but overall meta will still be delayed
        fields

  _TestThird = Third

  class Third extends Third
    @Meta
      name: 'Third'
      replaceParent: true
      fields: (fields) =>
        fields.third = @ReferenceField secondReferenceB
        fields

  testDocumentList test, ALL
  test.equal Document._delayed.length, 6
  test.equal Document._delayed[0][0], _TestFirst
  test.equal Document._delayed[1][0], _TestSecond
  test.equal Document._delayed[2][0], _TestThird
  test.equal Document._delayed[3][0], First
  test.equal Document._delayed[4][0], Second
  test.equal Document._delayed[5][0], Third

  _TestThird2 = Third

  class Third extends Third
    @Meta
      name: 'Third'
      fields: (fields) =>
        fields.third = @ReferenceField Person
        fields

  testDocumentList test, ALL
  test.equal Document._delayed.length, 7
  test.equal Document._delayed[0][0], _TestFirst
  test.equal Document._delayed[1][0], _TestSecond
  test.equal Document._delayed[2][0], _TestThird
  test.equal Document._delayed[3][0], First
  test.equal Document._delayed[4][0], Second
  test.equal Document._delayed[5][0], _TestThird2
  test.equal Document._delayed[6][0], Third

  _TestFirst2 = First

  class First extends First
    @Meta
      name: 'First'
      fields: (fields) =>
        fields.first = @ReferenceField Person
        fields

  testDocumentList test, ALL
  test.equal Document._delayed.length, 8
  test.equal Document._delayed[0][0], _TestFirst
  test.equal Document._delayed[1][0], _TestSecond
  test.equal Document._delayed[2][0], _TestThird
  test.equal Document._delayed[3][0], _TestFirst2
  test.equal Document._delayed[4][0], Second
  test.equal Document._delayed[5][0], _TestThird2
  test.equal Document._delayed[6][0], Third
  test.equal Document._delayed[7][0], First

  firstReferenceA = First
  Document._retryDelayed()

  testDocumentList test, ALL.concat [_TestFirst, _TestSecond, Second]
  test.equal Document._delayed.length, 5
  test.equal Document._delayed[0][0], _TestThird
  test.equal Document._delayed[1][0], _TestFirst2
  test.equal Document._delayed[2][0], _TestThird2
  test.equal Document._delayed[3][0], Third
  test.equal Document._delayed[4][0], First

  test.equal Second.Meta._name, 'Second'
  test.equal Second.Meta.parent, _TestSecond.Meta
  test.equal Second.Meta.collection._name, 'Seconds'
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.ancestorArray, Second.Meta.fields.first.ancestorArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Second.Meta.fields.first.fields, []
  test.isNull Second.Meta.fields.first.reverseName
  test.equal Second.Meta.fields.first.reverseFields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.ancestorArray, Second.Meta.fields.second.ancestorArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetCollection._name, 'Persons'
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection._name, 'Persons'
  test.equal Second.Meta.fields.second.fields, []
  test.isNull Second.Meta.fields.second.reverseName
  test.equal Second.Meta.fields.second.reverseFields, []

  firstReferenceB = Post
  Document._retryDelayed()

  testDocumentList test, ALL.concat [_TestSecond, Second, _TestFirst2, First]
  test.equal Document._delayed.length, 3
  test.equal Document._delayed[0][0], _TestThird
  test.equal Document._delayed[1][0], _TestThird2
  test.equal Document._delayed[2][0], Third

  test.equal Second.Meta._name, 'Second'
  test.equal Second.Meta.parent, _TestSecond.Meta
  test.equal Second.Meta.collection._name, 'Seconds'
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.ancestorArray, Second.Meta.fields.first.ancestorArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Second.Meta.fields.first.fields, []
  test.isNull Second.Meta.fields.first.reverseName
  test.equal Second.Meta.fields.first.reverseFields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.ancestorArray, Second.Meta.fields.second.ancestorArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetCollection._name, 'Persons'
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection._name, 'Persons'
  test.equal Second.Meta.fields.second.fields, []
  test.isNull Second.Meta.fields.second.reverseName
  test.equal Second.Meta.fields.second.reverseFields, []

  test.equal First.Meta._name, 'First'
  test.equal First.Meta.parent, _TestFirst2.Meta
  test.equal First.Meta.collection._name, 'Firsts'
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.ancestorArray, First.Meta.fields.first.ancestorArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetCollection._name, 'Persons'
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetDocument.Meta.collection._name, 'Persons'
  test.equal First.Meta.fields.first.fields, []
  test.isNull First.Meta.fields.first.reverseName
  test.equal First.Meta.fields.first.reverseFields, []

  secondReferenceA = First
  Document._retryDelayed()

  testDocumentList test, ALL.concat [_TestSecond, Second, _TestFirst2, First, _TestThird]
  test.equal Document._delayed.length, 2
  test.equal Document._delayed[0][0], _TestThird2
  test.equal Document._delayed[1][0], Third

  test.equal Second.Meta._name, 'Second'
  test.equal Second.Meta.parent, _TestSecond.Meta
  test.equal Second.Meta.collection._name, 'Seconds'
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.ancestorArray, Second.Meta.fields.first.ancestorArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Second.Meta.fields.first.fields, []
  test.isNull Second.Meta.fields.first.reverseName
  test.equal Second.Meta.fields.first.reverseFields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.ancestorArray, Second.Meta.fields.second.ancestorArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetCollection._name, 'Persons'
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection._name, 'Persons'
  test.equal Second.Meta.fields.second.fields, []
  test.isNull Second.Meta.fields.second.reverseName
  test.equal Second.Meta.fields.second.reverseFields, []

  test.equal First.Meta._name, 'First'
  test.equal First.Meta.parent, _TestFirst2.Meta
  test.equal First.Meta.collection._name, 'Firsts'
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.ancestorArray, First.Meta.fields.first.ancestorArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetCollection._name, 'Persons'
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetDocument.Meta.collection._name, 'Persons'
  test.equal First.Meta.fields.first.fields, []
  test.isNull First.Meta.fields.first.reverseName
  test.equal First.Meta.fields.first.reverseFields, []

  secondReferenceB = Post
  Document._retryDelayed()

  testDocumentList test, ALL.concat [_TestSecond, Second, _TestFirst2, First, _TestThird2, Third]
  test.equal Document._delayed.length, 0

  test.equal Second.Meta._name, 'Second'
  test.equal Second.Meta.parent, _TestSecond.Meta
  test.equal Second.Meta.collection._name, 'Seconds'
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.ancestorArray, Second.Meta.fields.first.ancestorArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Second.Meta.fields.first.fields, []
  test.isNull Second.Meta.fields.first.reverseName
  test.equal Second.Meta.fields.first.reverseFields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.ancestorArray, Second.Meta.fields.second.ancestorArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetCollection._name, 'Persons'
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection._name, 'Persons'
  test.equal Second.Meta.fields.second.fields, []
  test.isNull Second.Meta.fields.second.reverseName
  test.equal Second.Meta.fields.second.reverseFields, []

  test.equal First.Meta._name, 'First'
  test.equal First.Meta.parent, _TestFirst2.Meta
  test.equal First.Meta.collection._name, 'Firsts'
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.ancestorArray, First.Meta.fields.first.ancestorArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetCollection._name, 'Persons'
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetDocument.Meta.collection._name, 'Persons'
  test.equal First.Meta.fields.first.fields, []
  test.isNull First.Meta.fields.first.reverseName
  test.equal First.Meta.fields.first.reverseFields, []

  test.equal Third.Meta._name, 'Third'
  test.equal Third.Meta.parent, _TestThird2.Meta
  test.equal Third.Meta.collection._name, 'Thirds'
  test.equal _.size(Third.Meta.fields), 3
  test.instanceOf Third.Meta.fields.first, Third._ReferenceField
  test.isFalse Third.Meta.fields.first.ancestorArray, Third.Meta.fields.first.ancestorArray
  test.isTrue Third.Meta.fields.first.required
  test.equal Third.Meta.fields.first.sourcePath, 'first'
  test.equal Third.Meta.fields.first.sourceDocument, Third
  test.equal Third.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Third.Meta.fields.first.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Third.Meta.fields.first.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Third.Meta.fields.first.fields, []
  test.isNull Third.Meta.fields.first.reverseName
  test.equal Third.Meta.fields.first.reverseFields, []
  test.instanceOf Third.Meta.fields.second, Third._ReferenceField
  test.isFalse Third.Meta.fields.second.ancestorArray, Third.Meta.fields.second.ancestorArray
  test.isTrue Third.Meta.fields.second.required
  test.equal Third.Meta.fields.second.sourcePath, 'second'
  test.equal Third.Meta.fields.second.sourceDocument, Third
  test.equal Third.Meta.fields.second.targetDocument, Post
  test.equal Third.Meta.fields.second.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.second.targetCollection._name, 'Posts'
  test.equal Third.Meta.fields.second.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.second.targetDocument.Meta.collection._name, 'Posts'
  test.equal Third.Meta.fields.second.fields, []
  test.isNull Third.Meta.fields.second.reverseName
  test.equal Third.Meta.fields.second.reverseFields, []
  test.instanceOf Third.Meta.fields.third, Third._ReferenceField
  test.isFalse Third.Meta.fields.third.ancestorArray, Third.Meta.fields.third.ancestorArray
  test.isTrue Third.Meta.fields.third.required
  test.equal Third.Meta.fields.third.sourcePath, 'third'
  test.equal Third.Meta.fields.third.sourceDocument, Third
  test.equal Third.Meta.fields.third.targetDocument, Person
  test.equal Third.Meta.fields.third.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.third.targetCollection._name, 'Persons'
  test.equal Third.Meta.fields.third.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.third.targetDocument.Meta.collection._name, 'Persons'
  test.equal Third.Meta.fields.third.fields, []
  test.isNull Third.Meta.fields.third.reverseName
  test.equal Third.Meta.fields.third.reverseFields, []

  Document.defineAll()

  test.equal Second.Meta._name, 'Second'
  test.equal Second.Meta.parent, _TestSecond.Meta
  test.equal Second.Meta.collection._name, 'Seconds'
  test.equal _.size(Second.Meta.fields), 2
  test.instanceOf Second.Meta.fields.first, Second._ReferenceField
  test.isFalse Second.Meta.fields.first.ancestorArray, Second.Meta.fields.first.ancestorArray
  test.isTrue Second.Meta.fields.first.required
  test.equal Second.Meta.fields.first.sourcePath, 'first'
  test.equal Second.Meta.fields.first.sourceDocument, Second
  test.equal Second.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Second.Meta.fields.first.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Second.Meta.fields.first.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Second.Meta.fields.first.fields, []
  test.isNull Second.Meta.fields.first.reverseName
  test.equal Second.Meta.fields.first.reverseFields, []
  test.instanceOf Second.Meta.fields.second, Second._ReferenceField
  test.isFalse Second.Meta.fields.second.ancestorArray, Second.Meta.fields.second.ancestorArray
  test.isTrue Second.Meta.fields.second.required
  test.equal Second.Meta.fields.second.sourcePath, 'second'
  test.equal Second.Meta.fields.second.sourceDocument, Second
  test.equal Second.Meta.fields.second.targetDocument, Person
  test.equal Second.Meta.fields.second.sourceCollection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetCollection._name, 'Persons'
  test.equal Second.Meta.fields.second.sourceDocument.Meta.collection._name, 'Seconds'
  test.equal Second.Meta.fields.second.targetDocument.Meta.collection._name, 'Persons'
  test.equal Second.Meta.fields.second.fields, []
  test.isNull Second.Meta.fields.second.reverseName
  test.equal Second.Meta.fields.second.reverseFields, []

  test.equal First.Meta._name, 'First'
  test.equal First.Meta.parent, _TestFirst2.Meta
  test.equal First.Meta.collection._name, 'Firsts'
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.ancestorArray, First.Meta.fields.first.ancestorArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, Person
  test.equal First.Meta.fields.first.sourceCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetCollection._name, 'Persons'
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetDocument.Meta.collection._name, 'Persons'
  test.equal First.Meta.fields.first.fields, []
  test.isNull First.Meta.fields.first.reverseName
  test.equal First.Meta.fields.first.reverseFields, []

  test.equal Third.Meta._name, 'Third'
  test.equal Third.Meta.parent, _TestThird2.Meta
  test.equal Third.Meta.collection._name, 'Thirds'
  test.equal _.size(Third.Meta.fields), 3
  test.instanceOf Third.Meta.fields.first, Third._ReferenceField
  test.isFalse Third.Meta.fields.first.ancestorArray, Third.Meta.fields.first.ancestorArray
  test.isTrue Third.Meta.fields.first.required
  test.equal Third.Meta.fields.first.sourcePath, 'first'
  test.equal Third.Meta.fields.first.sourceDocument, Third
  test.equal Third.Meta.fields.first.targetDocument, firstReferenceA
  test.equal Third.Meta.fields.first.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal Third.Meta.fields.first.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal Third.Meta.fields.first.fields, []
  test.isNull Third.Meta.fields.first.reverseName
  test.equal Third.Meta.fields.first.reverseFields, []
  test.instanceOf Third.Meta.fields.second, Third._ReferenceField
  test.isFalse Third.Meta.fields.second.ancestorArray, Third.Meta.fields.second.ancestorArray
  test.isTrue Third.Meta.fields.second.required
  test.equal Third.Meta.fields.second.sourcePath, 'second'
  test.equal Third.Meta.fields.second.sourceDocument, Third
  test.equal Third.Meta.fields.second.targetDocument, Post
  test.equal Third.Meta.fields.second.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.second.targetCollection._name, 'Posts'
  test.equal Third.Meta.fields.second.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.second.targetDocument.Meta.collection._name, 'Posts'
  test.equal Third.Meta.fields.second.fields, []
  test.isNull Third.Meta.fields.second.reverseName
  test.equal Third.Meta.fields.second.reverseFields, []
  test.instanceOf Third.Meta.fields.third, Third._ReferenceField
  test.isFalse Third.Meta.fields.third.ancestorArray, Third.Meta.fields.third.ancestorArray
  test.isTrue Third.Meta.fields.third.required
  test.equal Third.Meta.fields.third.sourcePath, 'third'
  test.equal Third.Meta.fields.third.sourceDocument, Third
  test.equal Third.Meta.fields.third.targetDocument, Person
  test.equal Third.Meta.fields.third.sourceCollection._name, 'Thirds'
  test.equal Third.Meta.fields.third.targetCollection._name, 'Persons'
  test.equal Third.Meta.fields.third.sourceDocument.Meta.collection._name, 'Thirds'
  test.equal Third.Meta.fields.third.targetDocument.Meta.collection._name, 'Persons'
  test.equal Third.Meta.fields.third.fields, []
  test.isNull Third.Meta.fields.third.reverseName
  test.equal Third.Meta.fields.third.reverseFields, []

  # Restore
  Document.list = list
  Document._delayed = []
  Document._clearDelayedCheck()

  # Verify we are back to normal
  testDefinition test

testAsyncMulti 'meteor-peerdb - errors for generated fields', [
  (test, expect) ->
    Log._intercept 3 if Meteor.isServer # Three to see if we catch more than expected

    IdentityGenerator.documents.insert
      source: 'foobar'
    ,
      expect (error, identityGeneratorId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue identityGeneratorId
        @identityGeneratorId = identityGeneratorId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf(@identityGeneratorId) isnt -1
      test.isTrue _.isString(i), i
      intercepted = EJSON.parse i

      test.equal intercepted.message, "Generated field 'results' defined as an array with selector '#{ @identityGeneratorId }' was updated with a non-array value: 'foobar'"
      test.equal intercepted.level, 'error'

    @identityGenerator = IdentityGenerator.documents.findOne @identityGeneratorId,
      transform: null # So that we can use test.equal

    test.equal @identityGenerator,
      _id: @identityGeneratorId
      _schema: '1.0.0'
      source: 'foobar'
      result: 'foobar'

    Log._intercept 3 if Meteor.isServer # Three to see if we catch more than expected

    IdentityGenerator.documents.update @identityGeneratorId,
      $set:
        source: ['foobar2']
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf(@identityGeneratorId) isnt -1
      test.isTrue _.isString(i), i
      intercepted = EJSON.parse i

      test.equal intercepted.message, "Generated field 'result' not defined as an array with selector '#{ @identityGeneratorId }' was updated with an array value: [ 'foobar2' ]"
      test.equal intercepted.level, 'error'

    @identityGenerator = IdentityGenerator.documents.findOne @identityGeneratorId,
      transform: null # So that we can use test.equal

    test.equal @identityGenerator,
      _id: @identityGeneratorId
      _schema: '1.0.0'
      source: ['foobar2']
      result: 'foobar'
      results: ['foobar2']
]

Tinytest.add 'meteor-peerdb - tricky references', (test) ->
  list = _.clone Document.list

  # You can in fact use class name instead of "self", but you have to
  # make sure things work out at the end and class is really defined
  class First extends Document
    @Meta
      name: 'First'
      fields: =>
        first: @ReferenceField First

  Document.defineAll()

  test.equal First.Meta._name, 'First'
  test.isFalse First.Meta.parent
  test.equal First.Meta.collection._name, 'Firsts'
  test.equal _.size(First.Meta.fields), 1
  test.instanceOf First.Meta.fields.first, First._ReferenceField
  test.isFalse First.Meta.fields.first.ancestorArray, First.Meta.fields.first.ancestorArray
  test.isTrue First.Meta.fields.first.required
  test.equal First.Meta.fields.first.sourcePath, 'first'
  test.equal First.Meta.fields.first.sourceDocument, First
  test.equal First.Meta.fields.first.targetDocument, First
  test.equal First.Meta.fields.first.sourceCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetCollection._name, 'Firsts'
  test.equal First.Meta.fields.first.sourceDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.targetDocument.Meta.collection._name, 'Firsts'
  test.equal First.Meta.fields.first.fields, []

  # Restore
  Document.list = _.clone list
  Document._delayed = []
  Document._clearDelayedCheck()

  class First extends Document
    @Meta
      name: 'First'
      fields: =>
        first: @ReferenceField undefined # To force delayed

  class Second extends Document
    @Meta
      name: 'Second'
      fields: =>
        first: @ReferenceField First

  test.throws ->
    Document.defineAll true
  , /Target document not defined/

  test.throws ->
    Document.defineAll()
  , /Invalid fields/

  # Restore
  Document.list = _.clone list
  Document._delayed = []
  Document._clearDelayedCheck()

  # Verify we are back to normal
  testDefinition test

testAsyncMulti 'meteor-peerdb - duplicate values in lists', [
  (test, expect) ->
    Person.documents.insert
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person1Id
        @person1Id = person1Id

    Person.documents.insert
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person2Id
        @person2Id = person2Id

    Person.documents.insert
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person3Id
        @person3Id = person3Id

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
      count: 0
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      count: 0
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      count: 0

    Post.documents.insert
      author:
        _id: @person1._id
        # To test what happens if fields are partially not up to date
        username: 'wrong'
        displayName: 'wrong'
      subscribers: [
        _id: @person2._id
      ,
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ,
        _id: @person3._id
      ]
      subdocument:
        person:
          _id: @person2._id
        persons: [
          _id: @person2._id
          username: 'wrong'
          displayName: 'wrong'
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: 'wrong'
        ,
          _id: @person3._id
          # To test if the second person3 value will be updated
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
        ]
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: 'wrong'
          displayName: 'wrong'
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
        optional:
          _id: @person2._id
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
        optional:
          _id: @person2._id
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: 'wrong'
        optional:
          _id: @person2._id
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person1Id,
      $set:
        username: 'person1a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    Person.documents.update @person2Id,
      $set:
        username: 'person2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    # so that persons updates are not merged together to better
    # test the code for multiple updates
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    Person.documents.update @person3Id,
      $set:
        username: 'person3a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1a'
      displayName: 'Person 1'
      field1: 'Field 1 - 1'
      field2: 'Field 1 - 2'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2a'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3a'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

  (test, expect) ->
    Person.documents.update @person1Id,
      $set:
        # Updating two fields at the same time
        field1: 'Field 1 - 1a'
        field2: 'Field 1 - 2a'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1a'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person1Id,
      $unset:
        username: ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person2Id,
      $unset:
        username: ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal

    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
      ,
        _id: @person3._id
        username: @person3.username
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person3Id,
      $unset:
        username: ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ,
        _id: @person3._id
      ]
      subdocument:
        person:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person1Id,
      $set:
        username: 'person1b'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
      ,
        _id: @person3._id
      ,
        _id: @person3._id
      ]
      subdocument:
        person:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person2Id,
      $set:
        username: 'person2b'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal

    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1'
      field2: 'Field 2 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
        _id: @person2._id
      ,
        _id: @person3._id
      ]
      reviewers: [
        _id: @person2._id
        username: @person2.username
      ,
        _id: @person3._id
      ,
        _id: @person3._id
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Person.documents.update @person3Id,
      $set:
        username: 'person3b'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

  (test, expect) ->
    Person.documents.update @person2Id,
      $unset:
        # Removing two fields at the same time
        field1: ''
        field2: ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal

    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

  (test, expect) ->
    Person.documents.update @person2Id,
      $set:
        # Restoring two fields at the same time
        field1: 'Field 2 - 1b'
        field2: 'Field 2 - 2b'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal

    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBar'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'subdocument.body': 'SubdocumentFooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'nested.0.body': 'NestedFooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobar-nestedfoobarz-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'nested.4.body': 'NestedFooBarA'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobara-suffix'
        body: 'NestedFooBarA'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobar-nestedfoobarz-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
        'tag-5-prefix-foobar-nestedfoobara-suffix'
        'tag-6-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        'nested.3.body': null
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NestedFooBar'
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: null
        body: null
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobara-suffix'
        body: 'NestedFooBarA'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobar-nestedfoobarz-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobar-suffix'
        'tag-4-prefix-foobar-nestedfoobara-suffix'
        'tag-5-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $unset:
        'nested.2.body': ''
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: null
        body: null
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobar-nestedfoobara-suffix'
        body: 'NestedFooBarA'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobar-nestedfoobarz-suffix'
        'tag-2-prefix-foobar-nestedfoobar-suffix'
        'tag-3-prefix-foobar-nestedfoobara-suffix'
        'tag-4-prefix-foobar-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $set:
        body: 'FooBarZ'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: null
        body: null
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobarz-nestedfoobara-suffix'
        body: 'NestedFooBarA'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobarz-nestedfoobarz-suffix'
        'tag-2-prefix-foobarz-nestedfoobar-suffix'
        'tag-3-prefix-foobarz-nestedfoobara-suffix'
        'tag-4-prefix-foobarz-nestedfoobar-suffix'
      ]

    Post.documents.update @postId,
      $push:
        nested:
          required:
            _id: @person2._id
          optional:
            _id: @person3._id
          body: 'NewFooBar'
    ,
      expect (error, res) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue res

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person2 = Person.documents.findOne @person2Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NewFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1
    test.equal @person2,
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2b'
      displayName: 'Person 2'
      field1: 'Field 2 - 1b'
      field2: 'Field 2 - 2b'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NewFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          body: 'NestedFooBarZ'
        ,
          body: 'NestedFooBar'
        ,
          {}
        ,
          body: null
        ,
          body: 'NestedFooBarA'
        ,
          body: 'NestedFooBar'
        ,
          body: 'NewFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person2._id
      ,
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
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobarz-suffix'
        body: 'NestedFooBarZ'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: null
        body: null
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person2._id
          username: @person2.username
        slug: 'nested-prefix-foobarz-nestedfoobara-suffix'
        body: 'NestedFooBarA'
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ,
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
          field1: @person2.field1
          field2: @person2.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-newfoobar-suffix'
        body: 'NewFooBar'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobarz-nestedfoobarz-suffix'
        'tag-2-prefix-foobarz-nestedfoobar-suffix'
        'tag-3-prefix-foobarz-nestedfoobara-suffix'
        'tag-4-prefix-foobarz-nestedfoobar-suffix'
        'tag-5-prefix-foobarz-newfoobar-suffix'
      ]

    Person.documents.remove @person2Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal
    @person3 = Person.documents.findOne @person3Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          {}
        ,
          body: null
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1
    test.equal @person3,
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3b'
      displayName: 'Person 3'
      field1: 'Field 3 - 1'
      field2: 'Field 3 - 2'
      nestedPosts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: [
          {}
        ,
          body: null
        ,
          body: 'NestedFooBar'
        ]
        body: 'FooBarZ'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: [
        _id: @person3._id
      ]
      reviewers: [
        _id: @person3._id
        username: @person3.username
      ,
        _id: @person3._id
        username: @person3.username
      ]
      subdocument:
        person: null
        persons: [
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        ]
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: [
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional: null
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional: null
        slug: null
        body: null
      ,
        required:
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
          field1: @person3.field1
          field2: @person3.field2
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobarz-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
        'tag-1-prefix-foobarz-nestedfoobar-suffix'
      ]

    Person.documents.remove @person3Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id,
      transform: null # So that we can use test.equal

    test.equal @person1,
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1b'
      displayName: 'Person 1'
      field1: 'Field 1 - 1a'
      field2: 'Field 1 - 2a'
      posts: [
        _id: @postId
        subdocument:
          body: 'SubdocumentFooBarZ'
        nested: []
        body: 'FooBarZ'
      ]
      count: 1

    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.equal @post,
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
        field1: @person1.field1
        field2: @person1.field2
      subscribers: []
      reviewers: []
      subdocument:
        person: null
        persons: []
        slug: 'subdocument-prefix-foobarz-subdocumentfoobarz-suffix'
        body: 'SubdocumentFooBarZ'
      nested: []
      body: 'FooBarZ'
      slug: 'prefix-foobarz-subdocumentfoobarz-suffix'
      tags: [
        'tag-0-prefix-foobarz-subdocumentfoobarz-suffix'
      ]

    Person.documents.remove @person1Id,
      expect (error) =>
        test.isFalse error, error?.toString?() or error

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId,
      transform: null # So that we can use test.equal

    test.isFalse @post, @post
]

testAsyncMulti 'meteor-peerdb - exception while processing', [
  (test, expect) ->
    Log._intercept 3 if Meteor.isServer # Three to see if we catch more than expected

    IdentityGenerator.documents.insert
      source: 'exception'
    ,
      expect (error, identityGeneratorId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue identityGeneratorId
        @identityGeneratorId = identityGeneratorId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    if Meteor.isServer
      intercepted = Log._intercepted()

      # One or two because it depends if the client tests are running at the same time
      test.isTrue 1 <= intercepted.length <= 2, intercepted

      # We are testing only the server one, so let's find it
      for i in intercepted
        break if i.indexOf(@identityGeneratorId) isnt -1
      test.isTrue _.isString(i), i
      intercepted = EJSON.parse i

      test.isTrue intercepted.message.lastIndexOf('PeerDB exception: Error: Test exception', 0) is 0, intercepted.message
      test.equal intercepted.level, 'error'
]

testAsyncMulti 'meteor-peerdb - instances', [
  (test, expect) ->
    testDefinition test

    Person.documents.insert
      username: 'person1'
      displayName: 'Person 1'
    ,
      expect (error, person1Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person1Id
        @person1Id = person1Id

    Person.documents.insert
      username: 'person2'
      displayName: 'Person 2'
    ,
      expect (error, person2Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person2Id
        @person2Id = person2Id

    Person.documents.insert
      username: 'person3'
      displayName: 'Person 3'
    ,
      expect (error, person3Id) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue person3Id
        @person3Id = person3Id

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @person1 = Person.documents.findOne @person1Id
    @person2 = Person.documents.findOne @person2Id
    @person3 = Person.documents.findOne @person3Id

    test.instanceOf @person1, Person
    test.instanceOf @person2, Person
    test.instanceOf @person3, Person

    test.equal plainObject(@person1),
      _id: @person1Id
      _schema: '1.0.0'
      username: 'person1'
      displayName: 'Person 1'
      count: 0
    test.equal plainObject(@person2),
      _id: @person2Id
      _schema: '1.0.0'
      username: 'person2'
      displayName: 'Person 2'
      count: 0
    test.equal plainObject(@person3),
      _id: @person3Id
      _schema: '1.0.0'
      username: 'person3'
      displayName: 'Person 3'
      count: 0

    test.equal @person1.formatName(), 'person1-Person 1'
    test.equal @person2.formatName(), 'person2-Person 2'
    test.equal @person3.formatName(), 'person3-Person 3'

    Post.documents.insert
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
      nested: [
        required:
          _id: @person2._id
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = Post.documents.findOne @postId

    test.instanceOf @post, Post
    test.instanceOf @post.author, Person
    test.instanceOf @post.subscribers[0], Person
    test.instanceOf @post.subscribers[1], Person
    test.instanceOf @post.reviewers[0], Person
    test.instanceOf @post.reviewers[1], Person
    test.instanceOf @post.subdocument.person, Person
    test.instanceOf @post.subdocument.persons[0], Person
    test.instanceOf @post.subdocument.persons[1], Person
    test.instanceOf @post.nested[0].required, Person
    test.instanceOf @post.nested[0].optional, Person

    test.equal @post.author.formatName(), "#{ @person1.username }-#{ @person1.displayName }"

    test.equal plainObject(@post),
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]

    SpecialPost.documents.insert
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
      nested: [
        required:
          _id: @person2._id
        optional:
          _id: @person3._id
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      special:
        _id: @person1._id
    ,
      expect (error, postId) =>
        test.isFalse error, error?.toString?() or error
        test.isTrue postId
        @postId = postId

    # Sleep so that observers have time to update documents
    Meteor.setTimeout expect(), WAIT_TIME
,
  (test, expect) ->
    @post = SpecialPost.documents.findOne @postId

    test.instanceOf @post, SpecialPost
    test.instanceOf @post.author, Person
    test.instanceOf @post.subscribers[0], Person
    test.instanceOf @post.subscribers[1], Person
    test.instanceOf @post.reviewers[0], Person
    test.instanceOf @post.reviewers[1], Person
    test.instanceOf @post.subdocument.person, Person
    test.instanceOf @post.subdocument.persons[0], Person
    test.instanceOf @post.subdocument.persons[1], Person
    test.instanceOf @post.nested[0].required, Person
    test.instanceOf @post.nested[0].optional, Person
    test.instanceOf @post.special, Person

    test.equal @post.author.formatName(), "#{ @person1.username }-#{ @person1.displayName }"

    test.equal plainObject(@post),
      _id: @postId
      _schema: '1.0.0'
      author:
        _id: @person1._id
        username: @person1.username
        displayName: @person1.displayName
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
          displayName: @person2.displayName
        persons: [
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        ,
          _id: @person3._id
          username: @person3.username
          displayName: @person3.displayName
        ]
        slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
        body: 'SubdocumentFooBar'
      nested: [
        required:
          _id: @person2._id
          username: @person2.username
          displayName: @person2.displayName
        optional:
          _id: @person3._id
          username: @person3.username
        slug: 'nested-prefix-foobar-nestedfoobar-suffix'
        body: 'NestedFooBar'
      ]
      body: 'FooBar'
      slug: 'prefix-foobar-subdocumentfoobar-suffix'
      tags: [
        'tag-0-prefix-foobar-subdocumentfoobar-suffix'
        'tag-1-prefix-foobar-nestedfoobar-suffix'
      ]
      special:
        _id: @person1._id
]

Tinytest.add 'meteor-peerdb - bad instances', (test) ->
  # Empty document should be always possible to create
  for document in Document.list
    test.isTrue new document

  # Something simple
  test.isTrue new Post
    author:
      _id: Random.id()
      username: 'Foobar'

  test.throws ->
    new Post
      author: [
        _id: Random.id()
        username: 'Foobar'
      ]
  , /Document does not match schema, not a plain object/

  test.throws ->
    new Post
      subscribers: [
        Random.id()
      ]
  , /Document does not match schema, not a plain object/

  test.throws ->
    new Post
      subdocument: []
  , /Document does not match schema, an unexpected array/

  test.throws ->
    new Post
      subdocument: [
        persons: []
      ]
  , /Document does not match schema, an unexpected array/

  test.throws ->
    new Post
      subdocument: [[
        persons: []
      ]]
  , /Document does not match schema, an unexpected array/

  test.throws ->
    new Post
      subdocument:
        persons: [
          Random.id()
        ]
  , /Document does not match schema, not a plain object/

  test.throws ->
    new Post
      nested:
        _id: Random.id()
  , /Document does not match schema, expected an array/

  test.throws ->
    new Post
      nested: [
        required: Random.id()
      ]
  , /Document does not match schema, not a plain object/

  test.throws ->
    new Post
      nested:
        required: [
          _id: Random.id()
        ]
  , /Document does not match schema, expected an array/

  test.throws ->
    new Post
      nested:
        required:
          _id: Random.id()
  , /Document does not match schema, expected an array/

  test.throws ->
    new Post
      nested: [
        required: [
          _id: Random.id()
        ]
      ]
  , /Document does not match schema, not a plain object/

if Meteor.isServer
  testAsyncMulti 'meteor-peerdb - update all', [
    (test, expect) ->
      testDefinition test

      Person.documents.insert
        username: 'person1'
        displayName: 'Person 1'
      ,
        expect (error, person1Id) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue person1Id
          @person1Id = person1Id

      Person.documents.insert
        username: 'person2'
        displayName: 'Person 2'
      ,
        expect (error, person2Id) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue person2Id
          @person2Id = person2Id

      Person.documents.insert
        username: 'person3'
        displayName: 'Person 3'
      ,
        expect (error, person3Id) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue person3Id
          @person3Id = person3Id

      # Sleep so that observers have time to update documents
      Meteor.setTimeout expect(), WAIT_TIME
  ,
    (test, expect) ->
      @person1 = Person.documents.findOne @person1Id
      @person2 = Person.documents.findOne @person2Id
      @person3 = Person.documents.findOne @person3Id

      Post.documents.insert
        author:
          _id: @person1._id
          # To test what happens if one field is already up to date, but the other is not
          username: @person1.username
          displayName: 'wrong'
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
        nested: [
          required:
            _id: @person2._id
          optional:
            _id: @person3._id
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
      ,
        expect (error, postId) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue postId
          @postId = postId

      # Sleep so that observers have time to update documents
      Meteor.setTimeout expect(), WAIT_TIME
  ,
    (test, expect) ->
      @post = Post.documents.findOne @postId,
        transform: null # So that we can use test.equal

      test.equal @post,
        _id: @postId
        _schema: '1.0.0'
        author:
          _id: @person1._id
          username: @person1.username
          displayName: @person1.displayName
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
            displayName: @person2.displayName
          persons: [
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          ,
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
          ]
          slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
          body: 'SubdocumentFooBar'
        nested: [
          required:
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          optional:
            _id: @person3._id
            username: @person3.username
          slug: 'nested-prefix-foobar-nestedfoobar-suffix'
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
        slug: 'prefix-foobar-subdocumentfoobar-suffix'
        tags: [
          'tag-0-prefix-foobar-subdocumentfoobar-suffix'
          'tag-1-prefix-foobar-nestedfoobar-suffix'
        ]

      Post.documents.update @postId,
        $set:
          'author.username': 'wrong'
          'reviewers.0.username': 'wrong'
          'reviewers.1.username': 'wrong'
          'subdocument.person.username': 'wrong'
          'subdocument.persons.0.username': 'wrong'
          'subdocument.persons.1.username': 'wrong'
          'nested.0.required.username': 'wrong'
          'nested.0.optional.username': 'wrong'
          slug: 'wrong'
          tags: 'wrong'
      ,
        expect (error, res) =>
          test.isFalse error, error?.toString?() or error
          test.isTrue res

      # Sleep so that observers have time to update documents
      Meteor.setTimeout expect(), WAIT_TIME
  ,
    (test, expect) ->
      @post = Post.documents.findOne @postId,
        transform: null # So that we can use test.equal

      # Reference fields are automatically updated back, but generated fields are not
      test.equal @post,
        _id: @postId
        _schema: '1.0.0'
        author:
          _id: @person1._id
          username: @person1.username
          displayName: @person1.displayName
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
            displayName: @person2.displayName
          persons: [
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          ,
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
          ]
          slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
          body: 'SubdocumentFooBar'
        nested: [
          required:
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          optional:
            _id: @person3._id
            username: @person3.username
          slug: 'nested-prefix-foobar-nestedfoobar-suffix'
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
        slug: 'wrong'
        tags: 'wrong'

        # Update all fields back (a blocking operation)
        Document.updateAll()
  ,
    (test, expect) ->
      @post = Post.documents.findOne @postId,
        transform: null # So that we can use test.equal

      test.equal @post,
        _id: @postId
        _schema: '1.0.0'
        author:
          _id: @person1._id
          username: @person1.username
          displayName: @person1.displayName
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
            displayName: @person2.displayName
          persons: [
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          ,
            _id: @person3._id
            username: @person3.username
            displayName: @person3.displayName
          ]
          slug: 'subdocument-prefix-foobar-subdocumentfoobar-suffix'
          body: 'SubdocumentFooBar'
        nested: [
          required:
            _id: @person2._id
            username: @person2.username
            displayName: @person2.displayName
          optional:
            _id: @person3._id
            username: @person3.username
          slug: 'nested-prefix-foobar-nestedfoobar-suffix'
          body: 'NestedFooBar'
        ]
        body: 'FooBar'
        slug: 'prefix-foobar-subdocumentfoobar-suffix'
        tags: [
          'tag-0-prefix-foobar-subdocumentfoobar-suffix'
          'tag-1-prefix-foobar-nestedfoobar-suffix'
        ]
  ]
