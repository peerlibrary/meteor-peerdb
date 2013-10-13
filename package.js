Package.describe({
  summary: "Database support for collaborative documents"
});

Package.on_use(function (api) {
  api.use(['coffeescript', 'underscore'], ['client', 'server']);

  api.export('Document');

  api.add_files([
    'lib.coffee'
  ], ['client', 'server']);
  api.add_files([
    'server.coffee'
  ], 'server');
});

Package.on_test(function (api) {
  api.use(['peerdb', 'tinytest', 'test-helpers', 'coffeescript'], ['client', 'server']);
  api.add_files('tests.js', ['client', 'server']);
  api.add_files('tests_client.coffee', 'client');
  api.add_files('tests_server.coffee', 'server');
});