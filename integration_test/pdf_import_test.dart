// Import PDF on a real phone (Android emulator): pages are rendered by the
// printing package and their text read by ML Kit. Run by
// .github/workflows/feature-check.yml.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:study_app/screens/capture/pdf_import.dart';
import 'package:study_app/services/scan_service.dart';

Future<Uint8List> lecturePdf(List<String> pages) async {
  final doc = pw.Document();
  for (final text in pages) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Text(text, style: const pw.TextStyle(fontSize: 24)),
    ));
  }
  return doc.save();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a text PDF is rendered and its text read on the phone',
      (tester) async {
    final bytes = await lecturePdf([
      'Osmosis: movement of water across a membrane',
      'Diffusion: particles spread out',
    ]);
    final pdf = await readPdf('Lecture.pdf', bytes);
    expect(ScanService.canReadText, isTrue);
    expect(pdf.pages, hasLength(2));
    expect(pdf.more, isFalse);
    final text = pdf.text.toLowerCase();
    expect(text, contains('osmosis'));
    expect(text, contains('diffusion'));
    // Rendered on white: a JPEG of a reasonable size.
    expect(pdf.pages.first.length, greaterThan(5000));
  });

  testWidgets('only the first pages of a long PDF are read', (tester) async {
    final bytes = await lecturePdf([
      for (var i = 1; i <= kPdfImportPageLimit + 2; i++) 'Page $i',
    ]);
    final pdf = await readPdf('Long.pdf', bytes);
    expect(pdf.pages, hasLength(kPdfImportPageLimit));
    expect(pdf.more, isTrue);
  });
}
