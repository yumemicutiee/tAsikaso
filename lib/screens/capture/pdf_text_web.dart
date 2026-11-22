import 'dart:js_interop';

import 'package:flutter/foundation.dart';

// The web: the text of an imported PDF comes from its text layer, read by
// pdf.js (served from the site, see web/index.html). A scanned PDF has none.

@JS('tasikasoPdfText')
external JSPromise<JSString> _pdfText(JSUint8Array data, JSNumber maxPages);

/// The text of the first [maxPages] pages of [pdf], pages separated by a
/// blank line. Empty if it has none or it can't be read.
Future<String> pdfTextLayer(Uint8List pdf, int maxPages) async {
  try {
    final text = await _pdfText(pdf.toJS, maxPages.toJS).toDart;
    return text.toDart;
  } catch (e) {
    debugPrint('Could not read the text of the PDF: $e');
    return '';
  }
}
