Package.describe({
  summary: "Reactive database layer with references, generators, triggers, migrations, etc.",
  version: '0.17.0',
  name: 'peerlibrary:peerdb',
  git: 'https://github.com/peerlibrary/meteor-peerdb.git'
});

Package.on_use(function (api) {
  api.versionsFrom('METEOR@1.0');
  api.use(['coffeescript', 'underscore', 'minimongo', 'mongo', 'ddp', 'peerlibrary:assert@0.2.5', 'peerlibrary:stacktrace@0.1.3'], ['client', 'server']);
  api.use(['random'], 'server');

  api.export('Document');

  api.add_files([
    'lib.coffee'
  ], ['client', 'server']);

  api.use(['logging', 'peerlibrary:util@0.2.3', 'mrt:moment@2.8.1'], 'server');
  api.add_files([
    'server.coffee'
  ], 'server');
});

Package.on_test(function (api) {
  api.use(['peerlibrary:peerdb', 'tinytest', 'test-helpers', 'coffeescript', 'insecure', 'accounts-base', 'accounts-password', 'peerlibrary:assert@0.2.5', 'underscore', 'random'], ['client', 'server']);

  api.add_files([
    'tests_defined.js',
    'tests.coffee'
  ], ['client', 'server']);
});
