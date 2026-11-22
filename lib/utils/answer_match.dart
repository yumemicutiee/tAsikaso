import 'dart:math' as math;

/// How a typed answer compares with the right one, judged on the phone
/// (the study server judges by meaning when it's available).
enum AnswerVerdict { correct, partly, wrong }

/// The phone's judgement of a typed answer.
///
/// [exact] means the answer is the right one (or an accepted alternative)
/// once case, spacing, punctuation and a leading article are set aside.
/// Anything less certain (a forgiven typo, the answer inside a longer
/// sentence, some of the key words) is a guess the study server should
/// check when it can.
class AnswerJudgement {
  const AnswerJudgement(this.verdict, {this.exact = false});

  final AnswerVerdict verdict;
  final bool exact;
}

/// Judges [typed] against [answer] and any [acceptable] alternatives.
AnswerVerdict judgeAnswer(
  String typed,
  String answer, {
  List<String> acceptable = const [],
}) =>
    judgeAnswerDetailed(typed, answer, acceptable: acceptable).verdict;

/// Judges [typed] against [answer] and any [acceptable] alternatives:
///
/// - the same words, give or take case, punctuation, spacing and a leading
///   article, are correct (and [AnswerJudgement.exact]);
/// - the right answer as whole words inside a longer reply is correct,
///   unless the reply negates it ("not proteins");
/// - a small typo in a long word is forgiven, but never in a number, a sign
///   or a symbol (-3 is not 3, 10^22 is not 10^23), never in the first two
///   letters (efferent is not afferent), and never in a short word;
/// - at least half of the answer's key words is partly right.
AnswerJudgement judgeAnswerDetailed(
  String typed,
  String answer, {
  List<String> acceptable = const [],
}) {
  final t = normalizeAnswer(typed);
  if (t.isEmpty) return const AnswerJudgement(AnswerVerdict.wrong);
  final tWords = t.split(' ');
  final negated = tWords.any(_negations.contains);

  var best = AnswerVerdict.wrong;
  for (final a in [answer, ...acceptable]) {
    final n = normalizeAnswer(a);
    if (n.isEmpty) continue;
    if (t == n) return const AnswerJudgement(AnswerVerdict.correct, exact: true);
    final nWords = n.split(' ');
    // A "no"/"not" the right answer doesn't have turns the reply around.
    final turned = negated && !nWords.any(_negations.contains);

    if (!turned) {
      // A short right answer inside a longer reply ("it's the mitochondria").
      if (n.replaceAll(' ', '').length >= 4 && ' $t '.contains(' $n ')) {
        // Hedging between answers ("stroma or thylakoid") is only partly right.
        final hedged = tWords.contains('or') && !nWords.contains('or');
        if (!hedged) return const AnswerJudgement(AnswerVerdict.correct);
        best = AnswerVerdict.partly;
        continue;
      }
      if (_sameWordsWithTypos(tWords, nWords)) {
        return const AnswerJudgement(AnswerVerdict.correct);
      }
    }
    if (!turned && _sharesMostWords(tWords, nWords)) best = AnswerVerdict.partly;
  }
  return AnswerJudgement(best);
}

/// Words that turn an answer around. "hindi" is Filipino for "not".
const _negations = {'not', 'no', 'never', 'none', 'without', 'isnt', 'arent', 'hindi', 'wala'};

/// Characters kept as their own word because they change the meaning:
/// signs, operators and comparisons.
final _symbol = RegExp(r'[+\-^/*=<>%]');
final _otherPunctuation = RegExp(r'[^\p{L}\p{N}\s+\-^/*=<>%.]', unicode: true);
final _article = RegExp(r'^(the|an|a|ang|mga|si|yung) ');

/// Lower case, single spaces, no leading article. Letters and digits are
/// kept; so are signs and operators (as words of their own), the decimal
/// point inside a number, and the minus sign in front of one. Other
/// punctuation, apostrophes and hyphens between letters are dropped.
String normalizeAnswer(String s) {
  var out = s
      .toLowerCase()
      // Typographic minus and dashes, multiplication and division signs.
      .replaceAll(RegExp('[−‒–—]'), '-')
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      // Apostrophes join words ("isn't" → "isnt").
      .replaceAll(RegExp("['’]"), '')
      // A thousands separator inside a number ("1,000").
      .replaceAllMapped(RegExp(r'(\d),(?=\d{3}\b)'), (m) => m[1]!)
      // A hyphen between letters is a word break ("light-dependent").
      .replaceAllMapped(RegExp(r'(\p{L})-(?=\p{L})', unicode: true), (m) => '${m[1]} ')
      // A point that isn't a decimal point.
      .replaceAllMapped(RegExp(r'\.(?!\d)|(?<!\d)\.'), (_) => ' ')
      .replaceAll(_otherPunctuation, ' ')
      // Signs and operators as words of their own.
      .replaceAllMapped(_symbol, (m) => ' ${m[0]} ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  out = out.replaceFirst(_article, '');
  // "6.022 x 10^23": an x between two numbers means times.
  final words = out.split(' ');
  for (var i = 1; i + 1 < words.length; i++) {
    if (words[i] == 'x' && _isNumber(words[i - 1]) && _isNumber(words[i + 1])) {
      words[i] = '*';
    }
  }
  // A plus sign in front of a number changes nothing ("+1" is 1).
  if (words.length > 1 && words.first == '+' && _isNumber(words[1])) {
    words.removeAt(0);
  }
  return words.join(' ');
}

bool _isNumber(String w) => RegExp(r'^\d+(\.\d+)?$').hasMatch(w);

/// The same words in the same order, each the same or a long word (6+
/// letters, nothing but letters) with a small typo after its first two
/// letters: one for six letters, about one per six letters, at most three.
bool _sameWordsWithTypos(List<String> typed, List<String> answer) {
  if (typed.length != answer.length) return false;
  var forgiven = false;
  for (var i = 0; i < typed.length; i++) {
    final t = typed[i], a = answer[i];
    if (t == a) continue;
    final wordsOnly = RegExp(r'^\p{L}+$', unicode: true);
    if (a.length < 6 || !wordsOnly.hasMatch(a) || !wordsOnly.hasMatch(t)) return false;
    if (t.length < 2 || t.substring(0, 2) != a.substring(0, 2)) return false;
    final allowed = math.max(1, math.min(3, a.length ~/ 6));
    if (_editDistance(t, a, allowed) > allowed) return false;
    forgiven = true;
  }
  return forgiven;
}

/// True if at least half of the answer's key words (three characters or
/// more, with a letter: a number is right or wrong, never partly) appear in
/// the typed words.
bool _sharesMostWords(List<String> typed, List<String> answer) {
  final letter = RegExp(r'\p{L}', unicode: true);
  final key = answer.where((w) => w.length >= 3 && letter.hasMatch(w)).toList();
  if (key.isEmpty) return false;
  final have = typed.toSet();
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
