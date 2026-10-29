import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Faz o navegador baixar [bytes] como um arquivo chamado [filename].
void downloadFile(Uint8List bytes, String filename, {String type = 'text/csv'}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}
