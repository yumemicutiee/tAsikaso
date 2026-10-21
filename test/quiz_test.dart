import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/models/models.dart';
import 'package:study_app/utils/answer_match.dart';
import 'package:study_app/utils/quiz_builder.dart';

final cards = [
  const Flashcard(id: 'a', front: 'What makes ATP?', back: 'The mitochondria'),
  const Flashcard(id: 'b', front: 'Osmosis', back: 'Movement of water across a membrane'),
  const Flashcard(id: 'c', front: 'Ribosome', back: 'Makes proteins in the cell'),
  const Flashcard(id: 'd', front: 'Nucleus', back: 'Holds the DNA and controls the cell'),
  const Flashcard(id: 'e', front: 'Diffusion', back: 'Particles spread from high to low concentration'),
];

void main() {
  group('Quiz from the cards themselves', () {
    test('mixes the types, one question per card, each pointing at its card',
        () {
      final quiz = buildLocalQuiz(cards, count: 8, random: Random(1));
      expect(quiz.length, cards.length);
      expect(quiz.map((q) => q.cardId).toSet(), cards.map((c) => c.id).toSet());
      expect(quiz.map((q) => q.type).toSet().length, greaterThanOrEqualTo(3));

      for (final q in quiz) {
        final card = cards.firstWhere((c) => c.id == q.cardId);
        switch (q.type) {
          case QuestionType.multipleChoice:
            expect(q.options.length, 4);
            expect(q.options[q.answerIndex], card.back);
            expect(q.options.toSet().length, 4, reason: 'distinct choices');
          case QuestionType.trueFalse:
            expect(q.options, ['True', 'False']);
            expect(q.answer, q.answerIndex == 0 ? 'True' : 'False');
          case QuestionType.fillBlank:
            expect(q.prompt, contains('____'));
            expect(q.answer.length, greaterThanOrEqualTo(4));
            expect(card.back, contains(q.answer));
          case QuestionType.typed:
            expect(q.answer, card.back);
        }
      }
    });

    test('stops at the asked-for count', () {
      expect(buildLocalQuiz(cards, count: 2, random: Random(3)).length, 2);
    });

    test('one card can still make a question, just not a multiple choice', () {
      final quiz = buildLocalQuiz([cards.first], random: Random(2));
      expect(quiz.length, 1);
      expect(quiz.single.type, isNot(QuestionType.multipleChoice));
    });

    test('cards with an empty side are skipped', () {
      expect(buildLocalQuiz([const Flashcard(id: 'x', front: '', back: 'y')]), isEmpty);
    });
  });

  group('Judging a typed answer on the phone', () {
    test('the same words, give or take case, punctuation and an article', () {
      expect(judgeAnswer('the mitochondria', 'Mitochondria'), AnswerVerdict.correct);
      expect(judgeAnswer('Mitochondria!', 'the mitochondria'), AnswerVerdict.correct);
      expect(judgeAnswer('  movement of   water ', 'Movement of water'),
          AnswerVerdict.correct);
    });

    test('a typo or two is fine, a different word is not', () {
      expect(judgeAnswer('mitochondira', 'mitochondria'), AnswerVerdict.correct);
      expect(judgeAnswer('ribosome', 'mitochondria'), AnswerVerdict.wrong);
      expect(judgeAnswer('cat', 'cap'), AnswerVerdict.wrong); // too short to forgive
    });

    test('the right answer inside a longer sentence counts', () {
      expect(judgeAnswer("I think it's the mitochondria", 'mitochondria'),
          AnswerVerdict.correct);
    });

    test('most of the key words is partly right', () {
      expect(
        judgeAnswer('water moves across membrane', 'Movement of water across a membrane'),
        AnswerVerdict.partly,
      );
      expect(judgeAnswer('cell', 'Movement of water across a membrane'),
          AnswerVerdict.wrong);
    });

    test('the other accepted answers count too, and nothing is never right',
        () {
      expect(judgeAnswer('powerhouse', 'mitochondria', acceptable: ['the powerhouse']),
          AnswerVerdict.correct);
      expect(judgeAnswer('   ', 'mitochondria'), AnswerVerdict.wrong);
    });
  });

  group('Saving and loading', () {
    test('a quiz question survives a round trip; broken ones are left out',
        () {
      const q = QuizQuestion(
        type: QuestionType.multipleChoice,
        prompt: 'What makes ATP?',
        options: ['Ribosome', 'Mitochondria', 'Nucleus', 'Golgi'],
        acceptable: [],
        answerIndex: 1,
        answer: 'Mitochondria',
        explanation: 'Cellular respiration happens there.',
        cardId: 'a',
      );
      final back = QuizQuestion.fromJson(q.toJson());
      expect(back.type, q.type);
      expect(back.options, q.options);
      expect(back.answerIndex, 1);
      expect(back.cardId, 'a');

      final list = QuizQuestion.listFromJson([
        q.toJson(),
        {'type': 'nope', 'prompt': 'x', 'answer': 'y'},
        {'type': 'typed', 'prompt': '', 'answer': 'y'},
        {'type': 'typed', 'prompt': 'Q', 'answer': 'A', 'answerIndex': 7},
        'junk',
      ]);
      expect(list.length, 2);
      expect(list.last.answerIndex, -1); // out of range → none
    });

    test('a set keeps its source text, summary, concepts and quiz', () {
      final set = FlashcardSet(
        id: 's',
        title: 'Cells',
        folderId: 'f',
        createdAt: DateTime(2026, 10, 21),
        cards: cards,
        sourceText: 'raw ocr',
        summary: 'About cells.',
        concepts: const [Concept(term: 'ATP', explanation: 'Energy')],
        quiz: buildLocalQuiz(cards, count: 3, random: Random(1)),
      );
      final back = FlashcardSet.fromJson(set.toJson());
      expect(back.sourceText, 'raw ocr');
      expect(back.summary, 'About cells.');
      expect(back.concepts.single.term, 'ATP');
      expect(back.quiz.length, 3);
      expect(back.quiz.first.cardId, set.quiz.first.cardId);

      // Older save files have none of these.
      final old = FlashcardSet.fromJson(const {'id': 'o', 'title': 'Old'});
      expect(old.quiz, isEmpty);
      expect(old.concepts, isEmpty);
      expect(old.sourceText, '');
    });

    test('a note keeps its typed-up text, summary and concepts', () {
      final note = Note(
        id: 'n',
        title: 'Notes',
        folderId: 'f',
        createdAt: DateTime(2026),
        text: 'raw',
        cleanText: '# Cells\n- one',
        summary: 'Short.',
        concepts: const [Concept(term: 'Cell', explanation: 'Unit of life')],
      );
      final back = Note.fromJson(note.toJson());
      expect(back.cleanText, '# Cells\n- one');
      expect(back.displayText, '# Cells\n- one');
      expect(back.summary, 'Short.');
      expect(back.concepts.single.explanation, 'Unit of life');
      expect(Note.fromJson(const {'id': 'o', 'text': 'raw'}).displayText, 'raw');
    });

    test('preferences keep the study server settings', () {
      const p = AppPrefs(useAi: false, aiServerUrl: 'https://s.test', aiToken: 't');
      final back = AppPrefs.fromJson(p.toJson());
      expect(back.useAi, isFalse);
      expect(back.aiServerUrl, 'https://s.test');
      expect(back.aiToken, 't');
      expect(AppPrefs.fromJson(const {}).useAi, isTrue);
    });
  });
}
