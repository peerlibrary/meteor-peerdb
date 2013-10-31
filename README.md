PeerDB
======

Meteor smart package which provides database support for collaborative documents. Planned features are:
 * references between documents
 * auto-generated fields from other fields
 * versioning of all changes to documents
 * schema migrations

Adding this package to your [Meteor](http://www.meteor.com/) application adds `Document` object into the global scope.

Usage
-----

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
          author: @Reference Person, ['username']
          # Or an array of documents
          subscribers: [@Reference Person]
          reviewers: [@Reference Person, ['username']]

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
          second: @Reference CircularSecond, ['content']

    class CircularSecond extends Document
      # Other fields:
      #   content

      @Meta =>
        collection: CircularSeconds
        fields:
          # But of course one should not be required so that we can insert without warnings
          first: @Reference CircularFirst, ['content'], false

If the function throws an exception that a variable is not yet defined, PeerDB will retry later. You can
also call `Document.redefineAll()` after all your definitions to assure all your delayed definitions are
processed. You can call this function if you for some reason want to redo all metadata definitions
(only those defined as functions). For example, if you overrode (or monkey patch) document definitions and
would like metadata to use those new document definitions.

If you want to reference the same document recursively, use string `'self'` as an argument to `@Reference`.

    class Recursive extends Document
      # Other fields:
      #   content

      @Meta
        collection: Recursives
        fields:
          other: @Reference 'self', ['content'], false
