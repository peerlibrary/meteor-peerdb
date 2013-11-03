PeerDB
======

Meteor smart package which provides database support for collaborative documents. Implemented features are:
 * references between documents
 * auto-generated fields from other fields
 
Planned features are:
 * versioning of all changes to documents
 * schema migrations
 * integration with [full-text search](http://www.elasticsearch.org/)

Adding this package to your [Meteor](http://www.meteor.com/) application adds `Document` object into the global scope.

References
----------

You can define two documents:

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
          # We can reference other document
          author: @ReferenceField Person, ['username']
          # Or an array of documents
          subscribers: [@ReferenceField Person]
          reviewers: [@ReferenceField Person, ['username']]

Using `@Meta` you define main collection for each document and possible fields which are referencing
other documents. The idea is that a small subset of fields of referenced documents are kept synced
across all documents. Those fields are often those you almost always need when reading the main document
(for example, to be able to create a link to a profile page) and doing multiple queries every time would
be inefficient.

In above definition, `author` field will be a subdocument containing `_id` (always added) and `username`
fields. If `username` field in referenced `Person` document is changed, `author` field in all related
`Post` documents will be automatically updated.

`subscribers` field is an array of references to `Person` documents, where every element in the array will
be a subdocument containing only `_id` field.

If your order of definitions cannot be controlled or if you have circular definitions, you can pass to
`@Meta` a function which returns the metadata when called.

    class CircularFirst extends Document
      # Other fields:
      #   content

      @Meta =>
        collection: CircularFirsts
        fields:
          # We can reference circular documents
          second: @ReferenceField CircularSecond, ['content']

    class CircularSecond extends Document
      # Other fields:
      #   content

      @Meta =>
        collection: CircularSeconds
        fields:
          # But of course one should not be required so that we can insert without warnings
          first: @ReferenceField CircularFirst, ['content'], false

If the function throws an exception that a variable is not yet defined, PeerDB will retry later. You can
also call `Document.redefineAll()` after all your definitions to assure all your delayed definitions are
processed. You can call this function if you for some reason want to redo all metadata definitions
(only those defined as functions). For example, if you overrode (or monkey patch) document definitions and
would like metadata to use those new document definitions.

If you want to reference the same document recursively, use string `'self'` as an argument to `@ReferenceField`.

    class Recursive extends Document
      # Other fields:
      #   content

      @Meta
        collection: Recursives
        fields:
          other: @ReferenceField 'self', ['content'], false

Auto-generated fields
---------------------

You can define auto-generated fields:

    class Post extends Document
      # Other fields:
      #   title

      @Meta =>
        collection: Posts
        fields:
          slug: @GeneratedField 'self', ['title'], (fields) ->
            unless fields.title
              [fields._id, fields.title]
            else
              [fields._id, "prefix-#{ fields.title.toLowerCase() }-suffix"]

Last argument of `GeneratedField` is a function which receives an object populated with values based on the list of
fields you are interested in. In the example above, this is one field named `title` from the `Posts` collection. Field
`_id` is always available in `fields`. Generator function receives or just `_id` (when document containing fields is being
removed) or all fields requested. Generator function should return two values, a selector (often just ID of a document)
and a new value. If value is undefined, auto-generated field is removed. If selector is undefined, nothing is done.

Those fields are auto-generated and stored in the database. You should make sure not to override auto-generated
fields with some other value after they have been generated.