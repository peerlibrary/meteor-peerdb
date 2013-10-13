Tinytest.add('meteor-peerdb - defined', function (test) {
  var isDefined = false;
  try {
    Document;
    isDefined = true;
  }
  catch (e) {
  }
  test.isTrue(isDefined, "Document is not defined");
  test.isTrue(Package.peerdb.Document, "Package.peerdb.Document is not defined");
});