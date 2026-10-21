import 'dart:math';

import '../models/models.dart';

/// Makes quiz questions from a set's own cards, for when the study server
/// isn't set up or can't be reached. Each card gets at most one question
/// and the [types] (all four unless given) take turns; a card that can't
/// make any of them is left out.
List<QuizQuestion> buildLocalQuiz(
  List<Flashcard> cards, {
  int count = 12,
  Set<QuestionType>? types,
  Random? random,
}) {
  final rng = random ?? Random();
  final usable = [
    for (final c in cards)
      if (c.front.trim().isNotEmpty && c.back.trim().isNotEmpty) c,
  ]..shuffle(rng);

  final order = [
    for (final t in const [
      QuestionType.multipleChoice,
      QuestionType.typed,
      QuestionType.trueFalse,
      QuestionType.fillBlank,
    ])
      if (types == null || types.contains(t)) t,
  ];
  final out = <QuizQuestion>[];
  var turn = 0;
  for (final card in usable) {
    if (out.length >= count) break;
    // The next type in turn, or another one if this card can't make it.
    QuizQuestion? q;
    for (var i = 0; i < order.length && q == null; i++) {
      q = switch (order[(turn + i) % order.length]) {
        QuestionType.multipleChoice => _multipleChoice(card, usable, rng),
        QuestionType.trueFalse => _trueFalse(card, usable, rng),
        QuestionType.fillBlank => _fillBlank(card),
        QuestionType.typed => _typed(card),
      };
    }
    if (q != null) {
      out.add(q);
      turn++;
    }
  }
  return out;
}

String _norm(String s) => s.trim().toLowerCase();

/// Other cards' answers, as wrong choices for [card].
List<String> _otherAnswers(Flashcard card, List<Flashcard> all, Random rng) {
  final seen = {_norm(card.back)};
  final out = <String>[];
  for (final c in all) {
    if (c.id == card.id) continue;
    if (seen.add(_norm(c.back))) out.add(c.back.trim());
  }
  return out..shuffle(rng);
}

QuizQuestion? _multipleChoice(Flashcard card, List<Flashcard> all, Random rng) {
  final wrong = _otherAnswers(card, all, rng).take(3).toList();
  if (wrong.length < 2) return null;
  final answer = card.back.trim();
  final options = [answer, ...wrong]..shuffle(rng);
  return QuizQuestion(
    type: QuestionType.multipleChoice,
    prompt: card.front.trim(),
    options: options,
    answerIndex: options.indexOf(answer),
    answer: answer,
    cardId: card.id,
  );
}

QuizQuestion? _trueFalse(Flashcard card, List<Flashcard> all, Random rng) {
  final others = _otherAnswers(card, all, rng);
  final swap = others.isNotEmpty && rng.nextBool();
  final shown = swap ? others.first : card.back.trim();
  return QuizQuestion(
    type: QuestionType.trueFalse,
    prompt: '${card.front.trim()}\n$shown',
    options: const ['True', 'False'],
    answerIndex: swap ? 1 : 0,
    answer: swap ? 'False' : 'True',
    explanation: swap ? 'The right answer: ${card.back.trim()}' : '',
    cardId: card.id,
  );
}

final _edges = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);

/// Blanks out the longest word (four letters or more) of the answer.
QuizQuestion? _fillBlank(Flashcard card) {
  final words = card.back.trim().split(RegExp(r'\s+'));
  if (words.length < 3) return null;
  var best = -1;
  var bestCore = '';
  for (var i = 0; i < words.length; i++) {
    final core = words[i].replaceAll(_edges, '');
    if (core.length >= 4 && core.length > bestCore.length) {
      best = i;
      bestCore = core;
    }
  }
  if (best < 0) return null;
  final blanked = List.of(words)
    ..[best] = words[best].replaceFirst(bestCore, '____');
  return QuizQuestion(
    type: QuestionType.fillBlank,
    prompt: '${card.front.trim()}\n${blanked.join(' ')}',
    answer: bestCore,
    cardId: card.id,
  );
}

QuizQuestion _typed(Flashcard card) => QuizQuestion(
      type: QuestionType.typed,
      prompt: card.front.trim(),
      answer: card.back.trim(),
      cardId: card.id,
    );
