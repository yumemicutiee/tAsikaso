import '../models/models.dart';
import 'format.dart';

/// Finds likely flashcards in text read from lecture notes.
///
/// Notes usually hold definitions in a few common shapes, so these are
/// looked for line by line:
///   - `Q: What is …?` followed by `A: …`
///   - a line ending in `?` followed by its answer
///   - `Term - definition`, `Term – definition`, `Term: definition`,
///     `Term = definition`, `Term -> definition`
///
/// A definition can continue on the next lines if they start in lower case.
/// Suggestions are shown to the user to add or skip; nothing is added on its
/// own, so a few misses are fine.
List<Flashcard> suggestCards(String text, {int max = 30}) {
  final lines = [
    for (final raw in text.split('\n'))
      if (_clean(raw).isNotEmpty) _clean(raw),
  ];
  final cards = <Flashcard>[];
  final seen = <String>{};

  void add(String rawFront, String rawBack) {
    final front = _trimEnd(rawFront);
    final back = _trimEnd(rawBack);
    if (front.length < 2 || back.length < 2) return;
    if (!seen.add(front.toLowerCase())) return;
    cards.add(Flashcard(id: newId(), front: front, back: back));
  }

  /// The answer on line [i] plus any lower-case continuation lines.
  (String, int) takeAnswer(int i, String first) {
    final parts = [first];
    var j = i + 1;
    while (j < lines.length &&
        parts.length < 3 &&
        _startsLower(lines[j]) &&
        _split(lines[j]) == null &&
        !_isQuestion(lines[j])) {
      parts.add(lines[j]);
      j++;
    }
    return (parts.join(' '), j);
  }

  var i = 0;
  while (i < lines.length && cards.length < max) {
    final line = lines[i];

    // Q: … / A: …
    final q = _qa.firstMatch(line);
    if (q != null && q.group(1)!.toLowerCase() == 'q' && i + 1 < lines.length) {
      final a = _qa.firstMatch(lines[i + 1]);
      if (a != null && a.group(1)!.toLowerCase() == 'a') {
        final (answer, next) = takeAnswer(i + 1, a.group(2)!);
        add(q.group(2)!, answer);
        i = next;
        continue;
      }
    }

    // A question followed by its answer.
    if (_isQuestion(line) && i + 1 < lines.length && !_isQuestion(lines[i + 1])) {
      final (answer, next) = takeAnswer(i + 1, lines[i + 1]);
      add(line, answer);
      i = next;
      continue;
    }

    // Term – definition.
    final split = _split(line);
    if (split != null) {
      final (answer, next) = takeAnswer(i, split.$2);
      add(split.$1, answer);
      i = next;
      continue;
    }

    i++;
  }
  return cards;
}

final _qa = RegExp(r'^(q|a)\s*[:.)]\s*(.+)$', caseSensitive: false);

/// Bullets and numbering at the start of a line.
/// "Q." / "A." are left alone so question/answer pairs are still found.
final _bullet =
    RegExp(r'^\s*(?:[-•*·▪●◦]+|\d{1,2}[.)]|(?![QqAa][.)])[a-zA-Z][.)])\s+');

/// Separators between a term and its definition, most specific first.
final _separators = [
  RegExp(r'\s+(?:->|→|=>)\s+'),
  RegExp(r'\s+[–—]\s+'),
  RegExp(r'\s+-\s+'),
  RegExp(r'\s+=\s+'),
  RegExp(r':\s+'),
];

String _clean(String line) =>
    line.replaceFirst(_bullet, '').replaceAll(RegExp(r'\s+'), ' ').trim();

String _trimEnd(String s) => s.trim().replaceFirst(RegExp(r'[\s,;:–—-]+$'), '');

bool _isQuestion(String line) => line.length > 6 && line.endsWith('?');

bool _startsLower(String line) {
  final c = line.codeUnitAt(0);
  return c >= 0x61 && c <= 0x7A; // a–z
}

/// Splits "Term – definition" into its two parts if it looks like one.
(String, String)? _split(String line) {
  for (final sep in _separators) {
    final m = sep.firstMatch(line);
    if (m == null) continue;
    final term = line.substring(0, m.start).trim();
    final def = line.substring(m.end).trim();
    final words = term.split(' ').length;
    // A term is short; a definition has some substance. Skip times like
    // "10:30" and plain numbers.
    if (term.isEmpty || words > 6 || term.length > 60) return null;
    if (RegExp(r'^[\d\s.,:/]+$').hasMatch(term)) return null;
    if (def.length < 3) return null;
    return (term, def);
  }
  return null;
}
