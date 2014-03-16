class MigrationTest extends Document
  # Other fields:
  #   test

  @Meta
    name: 'MigrationTest'

class Migration1 extends Document.PatchMigration
  name: 'Migration 1'

MigrationTest.addMigration new Migration1()

class Migration2 extends Document.PatchMigration
  name: 'Migration 2'

MigrationTest.addMigration new Migration2()

MigrationTest.renameCollectionMigration 'OlderMigrationTests', 'OldMigrationTests'

class Migration3 extends Document.MinorMigration
  name: 'Migration 3'

MigrationTest.addMigration new Migration3()

class Migration4 extends Document.MajorMigration
  name: 'Migration 4'

MigrationTest.addMigration new Migration4()

MigrationTest.renameCollectionMigration 'OldMigrationTests', 'MigrationTests'

class Migration5 extends Document.MajorMigration
  name: 'Migration 5'

MigrationTest.addMigration new Migration5()

class Migration6 extends Document.MinorMigration
  name: 'Migration 6'

MigrationTest.addMigration new Migration6()

class Migration7 extends Document.MinorMigration
  name: 'Migration 7'

MigrationTest.addMigration new Migration7()

class Migration8 extends Document.PatchMigration
  name: 'Migration 8'

MigrationTest.addMigration new Migration8()

class MigrationTest extends MigrationTest
  @Meta
    name: 'MigrationTest'
    replaceParent: true

@ALL.push MigrationTest
