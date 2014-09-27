PeerDB
======

Meteor smart package which provides a reactive database layer with references, generators, triggers, migrations, etc.
Meteor provides a great way to code in a reactive style and this package brings reactivity to your database as well.
You can now define inside you application along with the rest of your program logic also how your data should be updated
on any change and how various aspects of your data should be kept in sync and consistent no matter where the change comes
from.

Implemented features are:
 * reactive references between documents
 * reactive reverse references between documents
 * reactive auto-generated fields from other fields
 * reactive triggers
 * migrations

Planned features are:
 * versioning of all changes to documents
 * integration with [full-text search](http://www.elasticsearch.org/)
 * [strict-typed schema validation](https://github.com/balderdashy/anchor)

Adding this package to your [Meteor](http://www.meteor.com/) application adds `Document` object into the global scope.

Both client and server side.

Installation
------------

```
mrt add peerdb
```

Documents
---------

Instead of Meteor collections with PeerDB you are defining PeerDB documents by extending `Document`. Internally it
defines a Meteor collection, but also all returned documents are then an instance of that PeerDB documents class.

Minimal definition:

```coffee
class Person extends Document
  @Meta
    name: 'Person'
```

This would create in your database a MongoDB collection called `Persons`. `name` must match class name. `@Meta` is
used for PeerDB and in addition you can define arbitrary class or object methods for your document which will then be
available on documents returned from the database:

```coffee
class Person extends Document
  # Other fields:
  #   username
  #   displayName
  #   email
  #   homepage

  @Meta
    name: 'Person'

  # Class methods
  @verboseName: ->
    @Meta._name.toLowerCase()

  @verboseNamePlural: ->
    "#{ @verboseName() }s"

  # Instance method
  getDisplayName: =>
    @displayName or @username
```

Querying
--------

PeerDB provides an alternative to Meteor collections query methods. You should be using them to access documents. You
can access them through `documents` property of your document class. For example, like:

```coffee
Person.documents.find({}).forEach (person, i, cursor) =>
  console.log person.constructor.verboseName(), person.getDisplayName()

Person.documents.findOne().getDisplayName()

Person.documents.findOne().email
```

Functions and arguments available are the same as those available for Meteor collections, with addition of:

* `.documents.exists(query)` – efficient check if any document matches given `query`

`Person.Meta` gives you back document metadata and `Person.documents` give you access to all documents.

All this is just an easy way to define documents and collections in a unified fashion, but it becomes interesting
when you start defining relations between documents.

References
----------

In traditional SQL world of relational databases you do joins between related documents every time you read them from
the database. This makes reading slower, your database management system is redoing same and same computation of joins
for every read, and also horizontal scaling of a database to many instances is harder because every read can potentially
have to talk to other instances.

NoSQL databases like MongoDB removes relations between documents and leave to users to resolve relations on their own.
This often means fetching one document, observing which other documents it references, and fetching those as well.
Because each of those documents are stand-alone and static it is relatively easy and quick for a database management
system like MongoDB to find an instance holding it and return it. Such approach is quick and it scales easily. But the
downside is multiple round trips you have to do in your code to get all documents you are interested in. Those
round trips become even worse when those queries are coming over the Internet from the client's browser that Meteor
supports, because Internet latency is much higher.

For a general case you can move this fetching of related documents to the server side into Meteor publish functions by
using libraries like [meteor-related](https://github.com/peerlibrary/meteor-related). It provides an easy way to fetch
related documents reactively, so when dependencies change, your published documents will be updated accordingly. While
latency to your database instances is hopefully better on your server, we did not really improve much from the SQL
world: you are effectively recomputing joins and now even in a much less efficient way, especially if you are reading
multiple documents at the same time.

Luckily, in many cases we can observe that we are mostly interested only in few fields of a related document, again
and again. Instead of recomputing joins every time we read, we could use MongoDB sub-documents feature to embed
those fields along with the reference. Instead of just storing the `_id` of a related document, we could store also
those few often used fields. For example, if you are displaying blog posts you want to display its name together
with a blog post. You will not really need only a blog post without author's name at all. Example blog post document
could then look like:

```json
{
  "_id": "frqejWeGWjDTPMj7P",
  "body": "A simple blog post",
  "author": {
    "_id": "yeK7R5Lws6MSeRQad",
    "username": "wesley",
    "displayName": "Wesley Crusher"
  },
  "subscribers": [
    {
      "_id": "k7cgWtxQpPQ3gLgxa"
    },
    {
      "_id": "KMYNwr7TsZvEboXCw"
    },
    {
      "_id": "tMgj8mF2zF3gjCftS"
    }
  ],
  "reviewers": [
    {
      "_id": "tMgj8mF2zF3gjCftS",
      "username": "deanna",
      "displayName": "Deanna Troi"
    }
  ]
```

Great! Now we have to fetch only this one document and we have everything needed to display a blog post. It is easy
for us to publish it with Meteor and use it as any other document, with direct access to author's fields.

Now, storing user's name along with all references to the user document brings an issue. What if user changes their
name? Then you have to update all those fields in documents referencing the user. So you would have to make sure that
anywhere in your code where you are changing the name, you are also updating fields in references. What about changes
to the database coming from outside of your code? Here is when PeerDB comes into action. With PeerDB you define those
references once and then PeerDB makes sure they stay in sync. It does not matter where the changes come from, it will
detect them and update fields in reference sub-documents accordingly.

If we have two documents:

```coffee
class Person extends Document
  # Other fields:
  #   username
  #   displayName
  #   email
  #   homepage

  @Meta
    name: 'Person'

class Post extends Document
  # Other fields:
  #   body

  @Meta
    name: 'Post'
    fields: =>
      # We can reference other document
      author: @ReferenceField Person, ['username', 'displayName']
      # Or an array of documents
      subscribers: [@ReferenceField Person]
      reviewers: [@ReferenceField Person, ['username', 'displayName']]
```

We are using `@Meta`'s `fields` argument to define references.

In above definition, `author` field will be a subdocument containing `_id` (always added) and `username`
and `displayName` fields. If `displayName` field in referenced `Person` document is changed, `author` field
in all related `Post` documents will be automatically updated with the new value for `displayName` field.

```coffee
Person.documents.update 'tMgj8mF2zF3gjCftS',
  $set:
    displayName: 'Deanna Troi-Riker'

# Returns "Deanna Troi-Riker"
Post.documents.fetchOne('frqejWeGWjDTPMj7P').reviewers[0].displayName

# Returns "Deanna Troi-Riker", sub-documents are objectified into document instances as well
Post.documents.fetchOne('frqejWeGWjDTPMj7P').reviewers[0].getDisplayName()
```

`subscribers` field is an array of references to `Person` documents, where every element in the array will
be a subdocument containing only `_id` field.

Circular references are possible as well:

```coffee
class CircularFirst extends Document
  # Other fields:
  #   content

  @Meta
    name: 'CircularFirst'
    fields: =>
      # We can reference circular documents
      second: @ReferenceField CircularSecond, ['content']

class CircularSecond extends Document
  # Other fields:
  #   content

  @Meta
    name: 'CircularSecond'
    fields: =>
      # But of course one should not be required so that we can insert without warnings
      first: @ReferenceField CircularFirst, ['content'], false
```

If you want to reference the same document recursively, use string `'self'` as an argument to `@ReferenceField`.

```coffee
class Recursive extends Document
  # Other fields:
  #   content

  @Meta
    name: 'Recursive'
    fields: =>
      other: @ReferenceField 'self', ['content'], false
```

All those references between documents can be tricky as you might want to reference documents defined afterwards
and JavaScript symbols might not even exist yet in the scope, and PeerDB works hard to still allow you to do that.
But to make sure all symbols are correctly resolved you should call `Document.defineAll()` after all your definitions.
The best is to put it in the filename which is loaded last.

`ReferenceField` accepts the following arguments:

* `targetDocument` – target document class, or `'self'`
* `fields` – list of fields to sync in a reference's sub-document; instead of a field name you can use a MongoDB projection as well, like `emails: {$slice: 1}`
* `required` – should the reference be required (default) or not, if required, when referenced document is removed, this document will be removed as well, if not required, reference will be set to `null`
* `reverseName` – name of a field for a reverse reference; specify to enable a reverse reference
* `reverseFields` – list of fields to sync for a reference reference

What are reverse references?

Reverse references
------------------

Sometimes you want also to have easy access to information about all the documents referencing a given document.
For example, for each author you might want to have a list of all blog posts they made, as part of their document.

```coffee
class Post extends Post
  @Meta
    name: 'Post'
    replaceParent: true
    fields: (fields) =>
      fields.author = @ReferenceField Person, ['username', 'displayName'], true, 'posts'
      fields
```

We [redefine](#abstract-documents-and-replaceparent) `Post` document and replace it with a new definition which has for `author` field reverse references
enabled. Now `Person.documents.findOne('yeK7R5Lws6MSeRQad')` returns:

```json
{
  "_id": "yeK7R5Lws6MSeRQad",
  "username": "wesley",
  "displayName": "Wesley Crusher",
  "email": "wesley@enterprise.starfleet",
  "homepage": "https://gww.enterprise.starfleet/~wesley/",
  "posts": [
    {
      "_id": "frqejWeGWjDTPMj7P"
    }
  ]
}
```

Auto-generated fields
---------------------

Sometimes you need fields in a document which are based on another fields. PeerDB allows you an easy way to define
such auto-generated fields:

```coffee
class Post extends Post
  # Other fields:
  #   title

  @Meta
    name: 'Post'
    replaceParent: true
    fields: (fields) =>
      fields.slug = @GeneratedField 'self', ['title'], (fields) ->
        unless fields.title
          [fields._id, undefined]
        else
          [fields._id, "prefix-#{ fields.title.toLowerCase() }-suffix"]
      fields
```

Last argument of `GeneratedField` is a function which receives an object populated with values based on the list of
fields you are interested in. In the example above, this is one field named `title` from the `Posts` collection. Field
`_id` is always available in `fields`. Generator function receives or just `_id` (when document containing fields is being
removed) or all fields requested. Generator function should return two values, a selector (often just ID of a document)
and a new value. If value is undefined, auto-generated field is removed. If selector is undefined, nothing is done.

You can define auto-generated fields across documents. Furthermore, you can combine reactivity. Maybe you want to also
have a count of all posts made by a person?

```coffee
class Person extends Person
  @Meta
    name: 'Person'
    replaceParent: true
    fields: (fields) =>
      fields.postsCount = @GeneratedField 'self', ['posts'], (fields) ->
        [fields._id, fields.posts?.length or 0]
      fields
```

Triggers
--------

You can define triggers which are run every time any of the specified fields changes:

```coffee
class Post extends Post
  # Other fields:
  #   updatedAt

  @Meta
    name: 'Post'
    replaceParent: true
    triggers: =>
      updateUpdatedAt: @Trigger ['title', 'body'], (newDocument, oldDocument) ->
        # Don't do anything when document is removed
        return unless newDocument._id

        timestamp = new Date()
        Post.documents.update
          _id: newDocument._id
          updatedAt:
            $lt: timestamp
        ,
          $set:
            updatedAt: timestamp
```

Return value is ignored. Triggers are useful when you want arbitrary code to be run when fields change.
This could be implemented directly with [observe](http://docs.meteor.com/#observe), but triggers
simplify that and provide an alternative API in the PeerDB spirit.

Why we are using a trigger here and not an auto-generated field? The main reason is that we want to assure
`updatedAt` really just increases, so a more complicated update query is needed. Additionally, reference
fields and auto-generated fields should be without side-effects and should be allowed to be called at any
time. This is to assure that we can re-sync any broken references as needed. If you would use an
auto-generated field it could be called again at a later time, updating `updatedAt` to a later time
without any content of a document really changing.

PeerDB does not really re-sync any broken references (made while your Meteor application was not running)
automatically. If you believe such references exist (eg., after a hard crash of your application), you
can trigger re-syncing by calling `Document.updateAll()`. All references will be resynced and all
auto-generated fields rerun. But not triggers. It is a quite heavy operation.

Abstract documents and `replaceParent`
--------------------------------------

You can define abstract documents by setting `abstract` `Meta` flag to `true`. Such documents will not create
a MongoDB collection. They are useful to define common fields and methods you want to reuse in multiple
documents.

We skimmed over `replaceParent` before. You should set it to `true` when you are defining a document with the
same name as a document you are extending (parent). It is a kind of a sanity check that you know what you are
doing and that you are promising you are not holding a reference to the extended (and replaced) document somewhere
and you expect it to work when using it. How much `replaceParent` is really useful is a good question, but it
allows you to define a common (client and server side) document and then augment it on the server side with
server side specific code.

Migrations
----------

In any large project your documents' schemas will evolve through time. While MongoDB does not really enforce
any schema, your program logic might require one. It is error prone to allow documents with various versions
of schemas to exist at the same time and it makes your program code more complicated.

To address this, PeerDB provides you with a way to define schema migrations. They are applied automatically on
a startup of your application to migrate any documents necessary. To know which documents are at which schema
version, PeerDB adds a field `_schema` to all documents with a [semantic version](http://semver.org/) number.

To define a migration, extend a class `Document.PatchMigration`, `Document.MinorMigration`, or
`Document.MajorMigration`, depending if your schema change is a backwards-compatible bug fix,
you are adding functionality in a backwards-compatible manner, or you are making an incompatible
change, respectively. By default migrations just update schema version:

```coffee
class Migration extends Document.PatchMigration
  name: "Migration not really doing anything with data"

  forward: (document, collection, currentSchema, newSchema) =>
    migrated: 0
    all: collection.update {_schema: currentSchema}, {$set: _schema: newSchema}, {multi: true}

  backward: (document, collection, currentSchema, oldSchema) =>
    migrated: 0
    all: collection.update {_schema: currentSchema}, {$set: _schema: oldSchema}, {multi: true}

Post.addMigration new Migration()
```

Base migrations class uses migration definitions above. You have to define both `forward` and `backward`
methods, but you can leave them undefined to use inherited definitions. Methods should return an
object containing `migrated` and `all` counts. `migrated` is count of all documents which were migrated,
while `all` include documents which were not really migrated (maybe because they were not applicable
for the given migration), but they still exist in the collection and only their schema version was updated.
Method must update schema version on all documents in a collection. (Easy pattern is to first migrate
applicable documents and then call `super` for the rest, returning combined counts.)

Inside a migration method you should use [DirectCollection](https://github.com/peerlibrary/meteor-directcollection)
provided to you as a `collection` argument. If you need access to other collections in your migrations,
you should use DirectCollection as well. DirectCollection is a library which provides a Meteor-like API for accessing
MongoDB, but bypasses Meteor completely, allowing you direct interaction with the database. This is necessary
in migrations because collection names could be changing during migrations and Meteor cannot really handle that.

You should call `addMigration` in the order you want migrations to be applied. The easiest way to assure that is
to create a directory `server/migrations/` in your project and have multiple files with `XXXX-description.coffee`
filenames, where `XXXX` is a consecutive number for the order you want, each file adding one migration.

There are some migration classes predefined:

* `AddReferenceFieldsMigration` – you are adding fields to a reference to be synced and you want to trigger resyncing of fields
* `RemoveReferenceFieldsMigration` – you are removing fields from a reference and you want to trigger resyncing of fields
* `AddGeneratedFieldsMigration` – you are adding auto-generated fields and you want to trigger generation of fields, you should pass a list of fields' names
* `ModifyGeneratedFieldsMigration` – you are modifying auto-generated fields and you want to trigger regeneration of fields, you should pass a list of fields' names
* `RemoveGeneratedFieldsMigration` – you are removing auto-generated fields, you should pass a list of fields' names
* `AddOptionalFieldsMigration` – you are adding optional fields, you should pass a list of fields' names
* `AddRequiredFieldsMigration` – you are adding required fields, you should pass a map between new fields' names and their initial values
* `RemoveFieldsMigration` – you are removing fields, you should pass a map between fields' names to be removed, and their values which should be set when reverting the migration
* `RenameFieldsMigration` – you are renaming fields, you should pass a map between current fields' names and new names

To rename a collection backing the document, use `renameCollectionMigration`:

```
Post.renameCollectionMigration 'oldPosts', 'Posts'
```

Settings
--------

### `PEERDB_INSTANCES=1` ###

As your application grows you might want to run specialized Meteor instances just to do PeerDB reactive MongoDB
queries. To distribute PeerDB load, configure number of PeerDB instances using `PEERDB_INSTANCES` environment variable.
Suggested setting is that your web-facing instances disable PeerDB by setting `PEERDB_INSTANCES` to 0, and then you have
dedicated PeerDB instances.

### `PEERDB_INSTANCE=0` ###

If you are running multiple PeerDB instances, which instance is this? It is zero-based index so if you configured
`PEERDB_INSTANCES=2`, you have to have two instances, one with `PEERDB_INSTANCE=0` and another with `PEERDB_INSTANCE=1`.

### `PEERDB_MIGRATIONS_DISABLED=` ###

If you want migrations to not run, set `PEERDB_MIGRATIONS_DISABLED` to a true value. Recommended setting is that only
*one* web-facing instance has migrations enabled and all other, including PeerDB instances, have them disabled. This
prevents any possible conflicts which could happen because of running migrations in parallel (but you are writing all
your migrations in a way that conflicts will never happen, using the
[Update If Current pattern](http://docs.mongodb.org/manual/tutorial/isolate-sequence-of-operations/#update-if-current),
aren't you?).

Disabling migrations just disables running them, documents are still populated with the `_schema` field.

### `MONGO_OPLOG_URL` and `MONGO_URL` ###

When running multiple instances you want to connect them all to the same database. You have to configure both normal
MongoDB connection and also oplog connection. You can use your own MongoDB instance or connect to one provided by
running Meteor in development mode. In the latter case the recommended way is that one web-facing instance runs
MongoDB and all other instances connect to that MongoDB.

```
MONGO_OPLOG_URL=mongodb://127.0.0.1:3001/local
MONGO_URL=mongodb://127.0.0.1:3001/meteor
```

Examples
--------

See [tests](https://github.com/peerlibrary/meteor-peerdb/blob/master/tests.coffee) for many examples. See
[document definitions in PeerLibrary](https://github.com/peerlibrary/peerlibrary/tree/development/lib/documents) for
real-world definitions, and [their migrations](https://github.com/peerlibrary/peerlibrary/tree/development/server/migrations).

Related projects
----------------

* [meteor-collection-hooks](https://github.com/matb33/meteor-collection-hooks) – provides an alternative way to
attach additional program logic on changes to your data, but it hooks into collection API methods so if a change comes
from the outside, hooks are not called; additionally, collection API methods are delayed for the time of all hooks to
be executed while in PeerDB hooks run in parallel in or even in a separate process (or processes), allowing your code to
return quickly while PeerDB assures that data will be eventually consistent (this has a downside of course as well,
so if you do not want that API calls return before all hooks run, meteor-collection-hooks might be more suitable for
you)
* [meteor-related](https://github.com/peerlibrary/meteor-related) – while PeerDB allows easy way to embed referenced
documents as subdocuments it requires that those relations are the same for all users; if you want dynamic relations
between documents, meteor-related provides an easy way to fetch related documents reactively on the server side, so
when dependencies change, your published documents will be updated accordingly
