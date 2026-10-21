import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/flashcards/quiz_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/widgets/bottom_nav.dart';

const ocrText = 'Osmosis: movement of water across a membrane\n'
    'Diffusion - particles spread out';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;

  setUp(() {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    ScanService.debugRead = null;
    StudyAi.debugClient = null;
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Pretend text recognition reads [ocrText] off every page.
  void readsText() {
    ScanService.debugRead = (jpegs) async => [
          for (final _ in jpegs)
            const RecognizedPage(lines: [
              RecognizedLine(
                  text: 'Osmosis: movement of water across a membrane',
                  left: 10, top: 10, right: 300, bottom: 30),
              RecognizedLine(
                  text: 'Diffusion - particles spread out',
                  left: 10, top: 40, right: 250, bottom: 60),
            ]),
        ];
  }

  /// A study server that answers every request with [body] and [status].
  void serverAnswers(int status, Object body) {
    store.updatePrefs(store.prefs
        .copyWith(aiServerUrl: 'https://study.test', aiToken: 'secret'));
    StudyAi.debugClient = () => MockClient((req) async =>
        http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'}));
  }

  CapturedPage page() {
    final image = img.Image(width: 40, height: 30);
    img.fill(image, color: img.ColorRgb8(230, 230, 230));
    return CapturedPage(
        id: 1, bytes: img.encodePng(image), width: 40, height: 30);
  }

  Future<void> openSaveSheet(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page()])));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  /// Saving renders pages in another isolate, so wait in real time; then
  /// let the screens that follow finish opening.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 150 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  group('Save Notes As', () {
    testWidgets('offers Scan PDF, Text PDF and Flashcards', (tester) async {
      await openSaveSheet(tester);
      expect(find.text('Scan PDF'), findsOneWidget);
      expect(find.text('Text PDF'), findsOneWidget);
      expect(find.text('Flashcards'), findsOneWidget);
      // No text recognition here, so Text PDF can't be chosen.
      expect(find.text('Needs text recognition (Android or iOS)'), findsOneWidget);
      expect(find.text('Save as PDF'), findsOneWidget);
    });

    testWidgets('a scan PDF keeps the text that was read, and no server is '
        'needed', (tester) async {
      readsText();
      await openSaveSheet(tester);
      await tester.tap(find.text('Save as PDF'));
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);

      final note = store.notes.single;
      expect(note.text, ocrText);
      expect(note.cleanText, '');
      expect(note.pageCount, 1);
      expect(find.textContaining('Saved to'), findsOneWidget);
      expect((await store.readPdf(note))!.length, greaterThan(1000));
    });

    testWidgets('a text PDF is typed up by the study server, with concepts',
        (tester) async {
      readsText();
      serverAnswers(200, {
        'kit': {
          'title': 'Transport',
          'summary': 'How things move.',
          'notes': '# Transport\n- Osmosis: water across a membrane',
          'concepts': [
            {'term': 'Osmosis', 'explanation': 'Water through a membrane.'},
          ],
          'cards': <Object>[],
          'quiz': <Object>[],
        },
      });
      await openSaveSheet(tester);
      await tester.tap(find.text('Text PDF'));
      await tester.pump();
      await tester.tap(find.text('Save as PDF'));
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);

      final note = store.notes.single;
      expect(note.cleanText, startsWith('# Transport'));
      expect(note.summary, 'How things move.');
      expect(note.concepts.single.term, 'Osmosis');
      expect(note.displayText, note.cleanText);
      expect(note.pageCount, greaterThanOrEqualTo(1));
    });

    testWidgets('flashcards come from the study server when it is on',
        (tester) async {
      readsText();
      serverAnswers(200, {
        'kit': {
          'title': 'Transport',
          'summary': 'How things move.',
          'notes': '# Transport',
          'concepts': [
            {'term': 'Osmosis', 'explanation': 'Water through a membrane.'},
          ],
          'cards': [
            {'front': 'What is osmosis?', 'back': 'Water moving across a membrane'},
            {'front': 'What is diffusion?', 'back': 'Particles spreading out'},
          ],
          'quiz': [
            {
              'type': 'typed',
              'prompt': 'What is osmosis?',
              'options': <String>[],
              'answerIndex': -1,
              'answer': 'Water moving across a membrane',
              'acceptable': <String>[],
              'explanation': '',
              'cardIndex': 0,
            },
          ],
        },
      });
      await openSaveSheet(tester);
      await tester.tap(find.text('Flashcards'));
      await tester.pump();
      await tester.tap(find.text('Make Flashcards'));
      await tester.pump();
      await waitFor(tester, () => store.sets.isNotEmpty);

      final deck = store.sets.single;
      expect(deck.cards.length, 2);
      expect(deck.suggestions, isEmpty);
      expect(deck.concepts.single.term, 'Osmosis');
      expect(deck.quiz.single.cardId, deck.cards.first.id);
      expect(deck.sourceText, ocrText);
      expect(find.byType(SetScreen), findsOneWidget);
      expect(find.textContaining('2 flashcards made for you'), findsOneWidget);
    });

    testWidgets('when the study server fails, cards are suggested from the '
        'text instead', (tester) async {
      readsText();
      serverAnswers(500, {
        'error': {'code': 'upstream', 'message': 'Claude returned an error.'},
      });
      await openSaveSheet(tester);
      await tester.tap(find.text('Flashcards'));
      await tester.pump();
      await tester.tap(find.text('Make Flashcards'));
      await tester.pump();
      await waitFor(tester, () => store.sets.isNotEmpty);

      final deck = store.sets.single;
      expect(deck.cards, isEmpty);
      expect(deck.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(find.textContaining('Claude returned an error.'), findsOneWidget);
      expect(find.textContaining('suggested from the text instead'), findsOneWidget);
    });
  });

  group('Quiz', () {
    Future<FlashcardSet> threeCards() async {
      final folder = store.folders.first;
      return store.addSet(title: 'Cells', folderId: folder.id, cards: const [
        Flashcard(id: 'a', front: 'What makes ATP?', back: 'The mitochondria'),
        Flashcard(id: 'b', front: 'Ribosome', back: 'Makes proteins'),
        Flashcard(id: 'c', front: 'Nucleus', back: 'Holds the DNA'),
      ]);
    }

    testWidgets('answers a multiple choice and a typed question, then shows '
        'the score', (tester) async {
      usePhoneSize(tester);
      final deck = await threeCards();
      const questions = [
        QuizQuestion(
          type: QuestionType.multipleChoice,
          prompt: 'What makes ATP?',
          options: ['Ribosome', 'The mitochondria', 'Nucleus', 'Golgi'],
          answerIndex: 1,
          answer: 'The mitochondria',
          explanation: 'Respiration happens there.',
          cardId: 'a',
        ),
        QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What does a ribosome do?',
          answer: 'Makes proteins',
          cardId: 'b',
        ),
      ];
      await tester.pumpWidget(
          MaterialApp(home: QuizScreen(setId: deck.id, questions: questions)));

      expect(find.text('Question 1 of 2'), findsOneWidget);
      expect(find.text('Multiple Choice'), findsOneWidget);
      await tester.tap(find.text('The mitochondria'));
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pump();
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('Respiration happens there.'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'builds the cell wall');
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Right answer: Makes proteins'), findsOneWidget);

      await tester.tap(find.text('See Results'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('You got 1 of 2 questions right.'), findsOneWidget);
      expect(find.text('What does a ribosome do?'), findsOneWidget); // to look at again

      // A right answer schedules the card like "Got It"; a wrong one like "Again".
      final saved = store.setById(deck.id)!;
      expect(saved.cards.firstWhere((c) => c.id == 'a').interval, 1);
      expect(saved.cards.firstWhere((c) => c.id == 'b').interval, 1);
      expect(saved.lastKnown, 1);
      expect(saved.lastSeen, 2);
      expect(store.cardsReviewedToday, 2);
    });

    testWidgets('the set screen makes a quiz from the cards when there is no '
        'study server', (tester) async {
      usePhoneSize(tester);
      final deck = await threeCards();
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      expect(find.text('Take a Quiz'), findsOneWidget);
      await tester.tap(find.text('Take a Quiz'));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(store.setById(deck.id)!.quiz, isNotEmpty);
      expect(find.text('Question 1 of ${store.setById(deck.id)!.quiz.length}'),
          findsOneWidget);
    });

    testWidgets('a typed answer is judged by the study server when it is on',
        (tester) async {
      usePhoneSize(tester);
      final deck = await threeCards();
      serverAnswers(200, {
        'check': {'verdict': 'correct', 'feedback': 'Yes, protein synthesis.'},
      });
      const questions = [
        QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What does a ribosome do?',
          answer: 'Makes proteins',
          cardId: 'b',
        ),
      ];
      await tester.pumpWidget(
          MaterialApp(home: QuizScreen(setId: deck.id, questions: questions)));
      await tester.enterText(find.byType(TextField), 'protein synthesis');
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('Yes, protein synthesis.'), findsOneWidget);
    });
  });

  testWidgets('Settings has a Smart Study section with the server address',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    await tester.tap(find.byIcon(AppTab.profile.icon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Smart Study'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Study Server'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Flashcards & Quizzes with AI'), findsOneWidget);
  });
}
