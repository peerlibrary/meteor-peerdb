Package.describe({
  summary: "Reactive database layer with references, generators, triggers, migrations, etc."
});

Package.on_use(function (api) {
  api.use(['coffeescript', 'underscore', 'minimongo', 'assert', 'stacktrace'], ['client', 'server']);

  api.export('Document');

  api.add_files([
    'lib.coffee'
  ], ['client', 'server']);

  api.use(['logging', 'util', 'moment', 'directcollection'], 'server');
  api.add_files([
    'server.coffee'
  ], 'server');
});

Package.on_test(function (api) {
  api.use(['peerdb', 'tinytest', 'test-helpers', 'coffeescript', 'insecure', 'accounts-base', 'accounts-password', 'assert', 'underscore', 'directcollection'], ['client', 'server']);
  api.add_files([
    'tests_defined.js',
    'tests.coffee'
  ], ['client', 'server']);

  api.add_files([
    'tests_migrations.coffee'
  ], 'server');
});
