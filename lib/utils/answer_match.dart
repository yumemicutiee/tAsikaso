import 'dart:math' as math;

/// How a typed answer compares with the right one, judged on the phone
/// (the study server judges by meaning when it's available).
enum AnswerVerdict { correct, partly, wrong }

/// Judges [typed] against [answer] and any [acceptable] alternatives: the
/// same words give or take case, punctuation, spacing, a leading article
/// and a typo or two count as correct; most of the key words count as
/// partly right.
AnswerVerdict judgeAnswer(
  String typed,
  String answer, {
  List<String> acceptable = const [],
}) {
  final t = normalizeAnswer(typed);
  if (t.isEmpty) return AnswerVerdict.wrong;
  var partly = false;
  for (final a in [answer, ...acceptable]) {
    final n = normalizeAnswer(a);
    if (n.isEmpty) continue;
    if (t == n) return AnswerVerdict.correct;
    // A short right answer inside a longer typed one ("it's the mitochondria").
    if (n.length >= 4 && t.contains(n)) return AnswerVerdict.correct;
    // A typo or two: about one per eight characters.
    final allowed = n.length < 5 ? 0 : math.min(3, n.length ~/ 8);
    if (allowed > 0 && _editDistance(t, n, allowed) <= allowed) {
      return AnswerVerdict.correct;
    }
    if (_sharesMostWords(t, n)) partly = true;
  }
  return partly ? AnswerVerdict.partly : AnswerVerdict.wrong;
}

final _punctuation = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final _article = RegExp(r'^(the|an|a|ang|mga|si|yung) ');

/// Lower case, letters and digits only, single spaces, no leading article.
String normalizeAnswer(String s) {
  var out = s
      .toLowerCase()
      .replaceAll(_punctuation, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  out = out.replaceFirst(_article, '');
  return out;
}

/// True if at least half of [answer]'s words of three letters or more
/// appear in [typed].
bool _sharesMostWords(String typed, String answer) {
  final key = answer.split(' ').where((w) => w.length >= 3).toList();
  if (key.isEmpty) return false;
  final have = typed.split(' ').toSet();
  final hits = key.where(have.contains).length;
  return hits * 2 >= key.length;
}

/// Levenshtein distance, stopping early once it passes [limit].
int _editDistance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      rowMin = math.min(rowMin, cur[j]);
    }
    if (rowMin > limit) return limit + 1;
    final swap = prev;
    prev = cur;
    cur = swap;
  }
  return prev[b.length];
}
