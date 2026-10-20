import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../theme/brand.dart';

/// Builds an A4 PDF with one cropped page photo per page. A page is turned
/// landscape when its photo is wider than tall (a whiteboard, say), so the
/// photo fills the page instead of sitting small in the middle.
Future<Uint8List> buildNotesPdf(
  List<Uint8List> pageJpegs, {
  required String title,
}) {
  final doc = pw.Document(title: title, creator: kAppName);
  for (final jpg in pageJpegs) {
    final image = pw.MemoryImage(jpg);
    final wide = (image.width ?? 0) > (image.height ?? 0);
    doc.addPage(
      pw.Page(
        pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }
  return doc.save();
}

/// "Biology – Cell structure" → "Biology - Cell structure.pdf"
String pdfFileName(String title) {
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|–—]'), '-').trim();
  return '${safe.isEmpty ? 'Notes' : safe}.pdf';
}
