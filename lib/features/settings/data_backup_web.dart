// Web-only implementation — never imported on non-web platforms.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void triggerWebDownload(List<int> bytes, String fileName) {
  final jsArray = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [jsArray].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
