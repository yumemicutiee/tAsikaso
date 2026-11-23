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
import 'package:study_app/screens/capture/reading_screen.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/flashcards/quiz_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/note_viewer_screen.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/widgets/bottom_nav.dart';

import 'support/read_pages.dart';

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
    await tapNextAndRead(tester);
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
    testWidgets('after Next, the sheet only asks for the folder', (tester) async {
      readsText();
      await openSaveSheet(tester);
      expect(find.text('Save Notes'), findsNWidgets(2)); // the title and button
      expect(find.text('1 page'), findsOneWidget);
      expect(find.text("Saved in the folder's Notebook"), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<StudyFolder>), findsOneWidget);
      for (final gone in ['Text Notes', 'Flashcards', 'Scan PDF', 'Title']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.textContaining('words read'), findsNothing);
    });

    testWidgets('where text is not read (the web), the sheet says so',
        (tester) async {
      await openSaveSheet(tester);
      expect(find.text('1 page, text is read in the phone app'), findsOneWidget);
    });

    testWidgets('Next shows the pages being read, then what was read',
        (tester) async {
      readsText();
      usePhoneSize(tester);
      ReadingScreen.pause = Duration.zero;
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page()])));
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ReadingScreen), findsOneWidget);
      expect(find.text('Reading your notes…'), findsOneWidget);
      expect(find.text('Read on your phone. Nothing is uploaded.'), findsOneWidget);
      await tester.runAsync(() async {
        for (var i = 0; i < 300 && find.byType(SaveSheet).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.byType(ReadingScreen), findsNothing);
      expect(find.byType(SaveSheet), findsOneWidget);

      // Closing the sheet and tapping Next again doesn't read them again.
      var reads = 0;
      ScanService.debugRead = (jpegs) async {
        reads++;
        return [for (final _ in jpegs) const RecognizedPage()];
      };
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byType(SaveSheet), findsOneWidget);
    });

    testWidgets('Cancel on the reading screen goes back to the pages',
        (tester) async {
      readsText();
      usePhoneSize(tester);
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page()])));
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadingScreen), findsNothing);
      expect(find.byType(SaveSheet), findsNothing);
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('saved as Text Notes titled from their first line, opened on '
        'the text with the pages kept', (tester) async {
      readsText();
      await openSaveSheet(tester);
      await tester.tap(find.text('Save Notes').last);
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);

      final note = store.notes.single;
      expect(note.textNote, isTrue);
      expect(note.title, 'Osmosis: movement of water across a membrane');
      expect(note.text, ocrText);
      expect(note.pageCount, 1);
      // The photos are kept as the note's PDF.
      expect((await store.readPdf(note))!.length, greaterThan(1000));
      expect(find.byType(NoteTextScreen), findsOneWidget);
      expect(find.text('Text Notes'), findsOneWidget); // the screen's title
      // The title and the first line of the text.
      expect(find.textContaining('Osmosis: movement of water'), findsNWidgets(2));
      expect(find.byTooltip('View Pages'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.text('Make Flashcards'), findsOneWidget);
    });

    testWidgets('Text Notes are typed up by the study server, with concepts',
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
      await tester.tap(find.text('Save Notes').last);
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);

      final note = store.notes.single;
      expect(note.textNote, isTrue);
      expect(note.title, 'Transport'); // the study server's title
      expect(note.cleanText, startsWith('# Transport'));
      expect(note.summary, 'How things move.');
      expect(note.concepts.single.term, 'Osmosis');
      expect(note.displayText, note.cleanText);
      expect(note.pageCount, 1);
      expect(find.text('Key Concepts'), findsOneWidget);
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
