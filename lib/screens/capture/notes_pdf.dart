import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/models.dart';
import '../../services/recognized_text.dart';
import '../../theme/brand.dart';
import '../../utils/format.dart';

/// The app's fonts for PDFs (Inter and Plus Jakarta Sans), loaded once.
/// Embedding them means every character the phone read can be written,
/// not just the Latin letters the built-in PDF fonts know.
class PdfFonts {
  PdfFonts._(this.body, this.bold, this.heading);

  final pw.Font body;
  final pw.Font bold;
  final pw.Font heading;

  static Future<PdfFonts>? _loading;

  static Future<PdfFonts> load() => _loading ??= _load();

  static Future<PdfFonts> _load() async {
    try {
      Future<pw.Font> ttf(String asset) async =>
          pw.Font.ttf(await rootBundle.load(asset));
      return PdfFonts._(
        await ttf('assets/fonts/Inter-Regular.ttf'),
        await ttf('assets/fonts/Inter-SemiBold.ttf'),
        await ttf('assets/fonts/PlusJakartaSans-Bold.ttf'),
      );
    } catch (e) {
      // The built-in fonts still make a PDF; only unusual characters suffer.
      debugPrint('PDF fonts could not be loaded: $e');
      _loading = null; // try again next time
      return PdfFonts._(
        pw.Font.helvetica(),
        pw.Font.helveticaBold(),
        pw.Font.helveticaBold(),
      );
    }
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(base: body, bold: bold);
}

const _margin = 24.0;

/// Builds an A4 PDF with one cropped page photo per page. A page is turned
/// landscape when its photo is wider than tall (a whiteboard, say), so the
/// photo fills the page instead of sitting small in the middle.
///
/// With [text] (one entry per photo), each recognised line is written
/// invisibly over the place it was read from, so the text can be selected,
/// searched and copied in any PDF viewer, like a scan from CamScanner.
Future<Uint8List> buildNotesPdf(
  List<Uint8List> pageJpegs, {
  required String title,
  List<RecognizedPage>? text,
}) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document(title: title, creator: kAppName, theme: fonts.theme);
  final hidden = pw.TextStyle(
    font: fonts.body,
    fontSize: 10,
    renderingMode: PdfTextRenderingMode.invisible,
  );

  for (var i = 0; i < pageJpegs.length; i++) {
    final image = pw.MemoryImage(pageJpegs[i]);
    final imageW = math.max(1, image.width ?? 1).toDouble();
    final imageH = math.max(1, image.height ?? 1).toDouble();
    final wide = imageW > imageH;
    final format = wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final lines =
        text != null && i < text.length ? text[i].lines : const <RecognizedLine>[];

    // Where the photo lands: fitted inside the margins, centred.
    final boxW = format.width - 2 * _margin;
    final boxH = format.height - 2 * _margin;
    final scale = math.min(boxW / imageW, boxH / imageH);
    final w = imageW * scale;
    final h = imageH * scale;
    final ox = (boxW - w) / 2;
    final oy = (boxH - h) / 2;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(_margin),
        build: (context) => pw.Stack(
          children: [
            pw.Positioned(
              left: ox,
              top: oy,
              child: pw.Image(image, width: w, height: h),
            ),
            for (final l in lines)
              if (l.width > 0 && l.height > 0)
                pw.Positioned(
                  left: ox + l.left * scale,
                  top: oy + l.top * scale,
                  child: pw.SizedBox(
                    width: l.width * scale,
                    height: l.height * scale,
                    // Stretched to the line's box so a selection in a
                    // viewer covers the words in the photo.
                    child: pw.FittedBox(
                      fit: pw.BoxFit.fill,
                      child: pw.Text(l.text, style: hidden),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Builds an A4 PDF of typed-up notes: the title, when they were made, a
/// summary if there is one, the notes, and the key concepts at the end.
///
/// [text] uses the study server's line format — `# ` heading, `## `
/// section, `- ` bullet, blank line between blocks — and plain text read
/// from the pages works too (every line becomes a paragraph).
Future<Uint8List> buildTextPdf({
  required String title,
  required String text,
  String summary = '',
  List<Concept> concepts = const [],
  DateTime? date,
}) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document(title: title, creator: kAppName, theme: fonts.theme);
  const muted = PdfColor.fromInt(0xFF6B7085);
  final body = pw.TextStyle(font: fonts.body, fontSize: 11, lineSpacing: 3);
  final bold = pw.TextStyle(font: fonts.bold, fontSize: 11, lineSpacing: 3);
  final small = pw.TextStyle(font: fonts.body, fontSize: 9, color: muted);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
            style: small),
      ),
      build: (context) => [
        pw.Text(title,
            style: pw.TextStyle(font: fonts.heading, fontSize: 22)),
        pw.SizedBox(height: 4),
        pw.Text('${formatNoteDate(date ?? DateTime.now())} · $kAppName',
            style: small),
        if (summary.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(summary,
              style: pw.TextStyle(
                  font: fonts.body, fontSize: 11, lineSpacing: 3, color: muted)),
        ],
        pw.SizedBox(height: 18),
        ...textBlocks(text, fonts: fonts, body: body),
        if (concepts.isNotEmpty) ...[
          pw.SizedBox(height: 22),
          pw.Text('Key Concepts',
              style: pw.TextStyle(font: fonts.heading, fontSize: 15)),
          pw.SizedBox(height: 8),
          for (final c in concepts)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(text: '${c.term}: ', style: bold),
                  pw.TextSpan(text: c.explanation, style: body),
                ]),
              ),
            ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// One widget per line of [text]: headings, bullets and paragraphs.
@visibleForTesting
List<pw.Widget> textBlocks(
  String text, {
  required PdfFonts fonts,
  required pw.TextStyle body,
}) {
  final out = <pw.Widget>[];
  var blank = false;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      blank = true;
      continue;
    }
    if (blank && out.isNotEmpty) out.add(pw.SizedBox(height: 6));
    blank = false;

    if (line.startsWith('# ')) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
        child: pw.Text(line.substring(2).trim(),
            style: pw.TextStyle(font: fonts.heading, fontSize: 16)),
      ));
    } else if (line.startsWith('## ')) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
        child: pw.Text(line.substring(3).trim(),
            style: pw.TextStyle(font: fonts.heading, fontSize: 13)),
      ));
    } else if (line.startsWith('- ') || line.startsWith('• ')) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 6, bottom: 3),
        child: pw.Bullet(
          text: line.substring(2).trim(),
          style: body,
          bulletSize: 3,
          bulletMargin: const pw.EdgeInsets.only(top: 5, left: 2, right: 8),
          padding: pw.EdgeInsets.zero,
          margin: pw.EdgeInsets.zero,
        ),
      ));
    } else {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(line, style: body),
      ));
    }
  }
  return out;
}

/// How many pages a PDF made here has (its page objects are written in
/// plain text, so they can be counted).
int pdfPageCount(Uint8List pdf) {
  final text = String.fromCharCodes(pdf);
  final n = RegExp(r'/Type\s*/Page(?![s\w])').allMatches(text).length;
  return n < 1 ? 1 : n;
}

/// "Biology – Cell structure" → "Biology - Cell structure.pdf"
String pdfFileName(String title) {
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|–—]'), '-').trim();
  return '${safe.isEmpty ? 'Notes' : safe}.pdf';
}
