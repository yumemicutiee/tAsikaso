import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'package:study_app/models/models.dart';
import 'package:study_app/screens/capture/notes_pdf.dart';
import 'package:study_app/services/recognized_text.dart';

/// The PDF as text, with its compressed streams inflated so the drawing
/// operators inside pages can be checked.
String inflated(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final out = StringBuffer(text);
  for (final m in RegExp(r'stream\r?\n').allMatches(text)) {
    var end = text.indexOf('endstream', m.end);
    if (end < 0) continue;
    while (end > m.end && (text[end - 1] == '\n' || text[end - 1] == '\r')) {
      end--;
    }
    try {
      out.write(latin1.decode(
          const ZLibDecoder().decodeBytes(pdf.sublist(m.end, end)),
          allowInvalid: true));
    } catch (_) {
      // Not a deflated stream (an image, say).
    }
  }
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = img.encodeJpg(img.Image(width: 400, height: 300));

  test('a scan PDF carries the recognised text invisibly, one page per photo',
      () async {
    const page = RecognizedPage(lines: [
      RecognizedLine(text: 'Osmosis', left: 40, top: 30, right: 160, bottom: 56),
      RecognizedLine(text: 'moves water', left: 40, top: 70, right: 220, bottom: 96),
    ]);
    final pdf = await buildNotesPdf([photo, photo], title: 'Bio',
        text: [page, const RecognizedPage()]);
    expect(pdfPageCount(pdf), 2);
    final text = inflated(pdf);
    // Text rendering mode 3 = invisible: selectable, searchable, not drawn.
    expect(RegExp(r'\b3 Tr\b').hasMatch(text), isTrue);
    expect(RegExp(r'\bTj\b|\bTJ\b').hasMatch(text), isTrue);

    final plain = await buildNotesPdf([photo], title: 'Bio');
    expect(RegExp(r'\b3 Tr\b').hasMatch(inflated(plain)), isFalse);
  });

  test('a text PDF lays out headings, bullets and paragraphs over pages',
      () async {
    final fonts = await PdfFonts.load();
    final blocks = textBlocks(
      '# Cells\n\n## Parts\n- Nucleus\n- Ribosome\n\nPlain line.',
      fonts: fonts,
      body: pw.TextStyle(font: fonts.body, fontSize: 11),
    );
    // Heading, spacer, section, two bullets, spacer, paragraph.
    expect(blocks.length, 7);
    expect(blocks.whereType<pw.SizedBox>().length, 2);

    final short = await buildTextPdf(
      title: 'Cells',
      text: '# Cells\n- Nucleus holds DNA',
      summary: 'A short set of notes.',
      concepts: const [Concept(term: 'Nucleus', explanation: 'Holds the DNA.')],
      date: DateTime(2026, 10, 21),
    );
    expect(pdfPageCount(short), 1);
    expect(RegExp(r'\bTj\b|\bTJ\b').hasMatch(inflated(short)), isTrue);

    final long = await buildTextPdf(
      title: 'Long',
      text: List.generate(120, (i) => '- Point number $i about the cell').join('\n'),
    );
    expect(pdfPageCount(long), greaterThan(1));
  });

  test('plain text read from the pages still makes a document', () async {
    final pdf = await buildTextPdf(title: 'Raw', text: 'line one\nline two');
    expect(pdfPageCount(pdf), 1);
  });
}
