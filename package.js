Package.describe({
  name: 'peerlibrary:peerdb',
  summary: "Reactive database layer with references, generators, triggers, migrations, etc.",
  version: '0.25.0',
  git: 'https://github.com/peerlibrary/meteor-peerdb.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.4.4.5');

  // Core dependencies.
  api.use([
    'coffeescript@2.0.3_3',
    'ecmascript',
    'underscore',
    'minimongo',
    'mongo',
    'ddp',
    'logging',
    'promise'
  ]);

  // 3rd party dependencies.
  api.use([
    'peerlibrary:assert@0.2.5',
    'peerlibrary:stacktrace@1.3.1_2',
    'peerlibrary:util@0.5.0'
  ]);

  api.export('Document');

  api.addFiles([
    'lib.coffee'
  ]);

  api.addFiles([
    'server.coffee'
  ], 'server');

  api.addFiles([
    'client.coffee'
  ], 'client');
});

Package.onTest(function (api) {
  api.versionsFrom('METEOR@1.4.4.5');

  api.use([
    'coffeescript@2.0.3_3',
    'ecmascript',
    'tinytest',
    'test-helpers',
    'insecure',
    'accounts-base',
    'accounts-password',
    'underscore',
    'random',
    'logging',
    'ejson',
    'mongo',
    'ddp'
  ]);

  // Internal dependencies.
  api.use([
    'peerlibrary:peerdb'
  ]);

  // 3rd party dependencies.
  api.use([
    'peerlibrary:assert@0.2.5'
  ]);

  api.addFiles([
    'tests_defined.js',
    'tests.coffee'
  ]);
});
