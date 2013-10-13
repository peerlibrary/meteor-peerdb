PeerDB
======

Meteor smart package which provides database support for collaborative documents. Planned features are:
 * references between documents
 * versioning of all changes to documents

Adding this package to your [Meteor](http://www.meteor.com/) application adds `Document` object into the global scope.

Example
-------

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
          author: @Reference Persons, ['username']
          subscribers: [@Reference Persons]
          reviewers: [@Reference Persons, ['username']]

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
