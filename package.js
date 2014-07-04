Package.describe({
  summary: "Database support for collaborative documents"
});

Package.on_use(function (api) {
  api.use(['coffeescript', 'underscore', 'minimongo', 'assert', 'stacktrace'], ['client', 'server']);

  api.export('Document');

  api.add_files([
    'lib.coffee'
  ], ['client', 'server']);

  api.use(['logging', 'random', 'util', 'moment', 'blocking', 'ejson'], 'server');
  api.add_files([
    'direct.coffee',
    'server.coffee'
  ], 'server');
});

Package.on_test(function (api) {
  api.use(['peerdb', 'tinytest', 'test-helpers', 'coffeescript', 'insecure', 'accounts-base', 'accounts-password', 'assert', 'blocking', 'underscore'], ['client', 'server']);
  api.add_files([
    'tests_defined.js',
    'tests.coffee'
  ], ['client', 'server']);

  api.add_files([
    'direct.coffee',
    'tests_direct.coffee',
    'tests_migrations.coffee'
  ], 'server');
});
