Tinytest.add('peerdb - defined', function (test) {
  var isDefined = false;
  try {
    Document;
    isDefined = true;
  }
  catch (e) {
  }
  test.isTrue(isDefined, "Document is not defined");
  test.isTrue(Package['peerlibrary:peerdb'].Document, "Package.peerlibrary:peerdb.Document is not defined");
});
