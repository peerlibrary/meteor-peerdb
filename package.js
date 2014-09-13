Package.describe({
  summary: "Reactive database layer with references, generators, triggers, migrations, etc.",
  version: '0.14.3',
  name: 'mrt:peerdb',
  git: 'https://github.com/peerlibrary/meteor-peerdb.git'
});

Package.on_use(function (api) {
  api.imply('peerlibrary:peerdb@0.14.3');
});
