import 'package:flutter/foundation.dart';

/// A line of text found on a page photo and where it sits, in pixels of
/// that photo (so a PDF can lay invisible text over the right spot).
@immutable
class RecognizedLine {
  const RecognizedLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

/// What was read from one page: the lines the phone's text recognition
/// found and where they sit (lit up on the reading screen, and the Scan
/// PDF's hidden text), and, when Claude read the photo, its [transcript].
@immutable
class RecognizedPage {
  const RecognizedPage({this.lines = const [], this.transcript});

  final List<RecognizedLine> lines;

  /// The page's text as Claude wrote it out from the photo (see
  /// `StudyAi.readPage`), or null when it was read on the phone only.
  final String? transcript;

  /// Claude wrote out this page's text.
  bool get byClaude => transcript != null && transcript!.trim().isNotEmpty;

  bool get isEmpty => lines.isEmpty && !byClaude;

  /// The page's text: Claude's when it read the photo, else the lines the
  /// phone found, one per line.
  String get text =>
      byClaude ? transcript!.trim() : lines.map((l) => l.text).join('\n');

  /// This page with [transcript] as its text, its lines kept.
  RecognizedPage withTranscript(String transcript) =>
      RecognizedPage(lines: lines, transcript: transcript);

  /// All pages' text, pages separated by a blank line; empty pages skipped.
  static String join(List<RecognizedPage> pages) => [
        for (final p in pages)
          if (!p.isEmpty) p.text,
      ].join('\n\n');
}
