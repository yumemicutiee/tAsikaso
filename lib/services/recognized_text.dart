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

/// What text recognition found on one page, in reading order.
@immutable
class RecognizedPage {
  const RecognizedPage({this.lines = const []});

  final List<RecognizedLine> lines;

  bool get isEmpty => lines.isEmpty;

  /// The page's text, one recognised line per line.
  String get text => lines.map((l) => l.text).join('\n');

  /// All pages' text, pages separated by a blank line; empty pages skipped.
  static String join(List<RecognizedPage> pages) => [
        for (final p in pages)
          if (!p.isEmpty) p.text,
      ].join('\n\n');
}
