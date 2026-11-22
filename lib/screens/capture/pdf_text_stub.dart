import 'dart:typed_data';

// Phones and tests: the text of an imported PDF is read from its pages
// with text recognition instead (see pdf_import.dart).

/// The PDF's own text layer; not read here.
Future<String> pdfTextLayer(Uint8List pdf, int maxPages) async => '';
