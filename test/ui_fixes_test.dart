import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/analysis_screen.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/flashcards/quiz_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/widgets/dialogs.dart';

/// Device storage whose saves of the data file wait while [gate] is set,
/// like a slow phone in the middle of a big restore.
class _SlowStorage extends MemoryStorage {
  Completer<void>? gate;

  @override
  Future<void> writeJson(String json) async {
    final wait = gate;
    if (wait != null) await wait.future;
    return super.writeJson(json);
  }
}

/// Device storage that is full: no PDF or photo can be written.
class _FullStorage extends MemoryStorage {
  @override
  Future<void> writeBytes(String key, Uint8List bytes) async =>
      throw StateError('No space left on device');
}

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

  tearDown(() {
    ScanService.debugRead = null;
    StudyAi.debugClient = null;
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<Flashcard> cards(int n) => [
        for (var i = 0; i < n; i++)
          Flashcard(
              id: 'c$i',
              front: 'Question number $i',
              back: 'The answer to question number $i'),
      ];

  QuizQuestion typed(String prompt, String answer, String cardId) =>
      QuizQuestion(
          type: QuestionType.typed,
          prompt: prompt,
          answer: answer,
          cardId: cardId);

  Future<void> answerTyped(WidgetTester tester, String answer) async {
    await tester.enterText(find.byType(TextField), answer);
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
  }

  group('Quiz', () {
    testWidgets('the next typed question gets the keyboard again',
        (tester) async {
      usePhoneSize(tester);
      final deck = await store.addSet(
          title: 'Spanish', folderId: store.folders.first.id, cards: cards(2));
      await tester.pumpWidget(MaterialApp(
          home: QuizScreen(setId: deck.id, questions: [
        typed('One?', 'Uno', 'c0'),
        typed('Two?', 'Dos', 'c1'),
      ])));
      await tester.pumpAndSettle();
      bool focused() => tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode
          .hasFocus;
      expect(focused(), isTrue);

      await answerTyped(tester, 'uno');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Two?'), findsOneWidget);
      // The box was switched off while the answer showed; it is focused
      // again, so the keyboard opens without a tap.
      expect(focused(), isTrue);
    });

    testWidgets('a card asked about twice moves on one step, not two',
        (tester) async {
      usePhoneSize(tester);
      final deck = await store.addSet(
          title: 'Spanish', folderId: store.folders.first.id, cards: cards(2));
      final questions = [
        typed('One?', 'Uno', 'c0'),
        typed('Say one in Spanish.', 'Uno', 'c0'),
      ];
      await tester.pumpWidget(MaterialApp(
          home: QuizScreen(setId: deck.id, questions: questions)));
      await tester.pumpAndSettle();
      int interval() =>
          store.setById(deck.id)!.cards.firstWhere((c) => c.id == 'c0').interval;

      await answerTyped(tester, 'uno');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await answerTyped(tester, 'uno');
      await tester.tap(find.text('See Results'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      // New card, known once in this quiz: back tomorrow, not in 3 days.
      expect(interval(), 1);

      // Another round counts once more, like studying the set again.
      await tester.tap(find.text('Try Again (Shuffled)'));
      await tester.pumpAndSettle();
      await answerTyped(tester, 'uno');
      expect(interval(), 3);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await answerTyped(tester, 'uno');
      expect(interval(), 3);
    });
  });

  group('Set screen', () {
    testWidgets('deleting a card takes its quiz questions with it',
        (tester) async {
      usePhoneSize(tester);
      final deck = await store.addSet(
        title: 'Cells',
        folderId: store.folders.first.id,
        cards: cards(4),
        quiz: [
          typed('What is question number 1?', 'The answer to it', 'c1'),
          typed('What is question number 2?', 'The answer to it', 'c2'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      expect(find.text('Take a Quiz (2 questions)'), findsOneWidget);

      // From the card's ⋮ menu.
      final card = find.text('Question number 2');
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.ancestor(of: card, matching: find.byType(Row)).first,
        matching: find.byTooltip('More'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.setById(deck.id)!.quiz.single.cardId, 'c1');
      await tester.scrollUntilVisible(find.text('Take a Quiz (1 question)'), -200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Take a Quiz (1 question)'), findsOneWidget);

      // From the card editor.
      await tester.ensureVisible(find.text('Question number 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Question number 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.setById(deck.id)!.cards.length, 2);
      expect(store.setById(deck.id)!.quiz, isEmpty);
    });

    testWidgets('making cards with AI again keeps the quiz on the cards the '
        'set already has', (tester) async {
      usePhoneSize(tester);
      store.updatePrefs(store.prefs
          .copyWith(aiServerUrl: 'https://study.test', aiToken: 'secret'));
      // The server writes the same two cards again, and a quiz on them.
      StudyAi.debugClient = () => MockClient((req) async => http.Response(
            jsonEncode({
              'kit': {
                'title': 'Cells',
                'summary': 'Two questions.',
                'notes': '',
                'concepts': <Object>[],
                'cards': [
                  {'front': 'Question number 0', 'back': 'The answer'},
                  {'front': 'Question number 1', 'back': 'The answer'},
                ],
                'quiz': [
                  for (var i = 0; i < 2; i++)
                    {
                      'type': 'typed',
                      'prompt': 'Which is question number $i?',
                      'options': <String>[],
                      'answerIndex': -1,
                      'answer': 'Question number $i',
                      'cardIndex': i,
                    },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final deck = await store.addSet(
        title: 'Cells',
        folderId: store.folders.first.id,
        cards: cards(2),
        sourceText: 'Question number 0 - the answer\nQuestion number 1 - the answer',
      );
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.byTooltip('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Cards with AI'));
      await tester.pumpAndSettle();

      expect(find.text('No new cards to add.'), findsOneWidget);
      final saved = store.setById(deck.id)!;
      expect(saved.cards.map((c) => c.id), ['c0', 'c1']);
      expect(saved.quiz.map((q) => q.cardId), ['c0', 'c1']);
      expect(find.text('Take a Quiz (2 questions)'), findsOneWidget);
    });
  });

  testWidgets('a restore still says it worked after the screen was closed',
      (tester) async {
    usePhoneSize(tester);
    final zip = await store.createBackup();
    final slow = _SlowStorage();
    await store.init(slow);
    final originalPick = BackupScreen.pickFile;
    BackupScreen.pickFile = () async => zip;
    addTearDown(() => BackupScreen.pickFile = originalPick);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openBackup(context),
              child: const Text('Open Backup'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore from Backup'));
    await tester.pumpAndSettle();

    slow.gate = Completer<void>(); // the restore takes its time
    await tester.tap(find.text('Choose File'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BackupScreen), findsNothing);

    slow.gate!.complete();
    slow.gate = null;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Backup restored.'), findsOneWidget);
  });

  testWidgets('Productive Hours: a Pomodoro across the hour adds up to its '
      'minutes', (tester) async {
    usePhoneSize(tester);
    final now = DateTime.now();
    // 10:50:30 to 11:15:30: nine and a half minutes, then fifteen and a half.
    store.recordFocusSession(25,
        endedAt: DateTime(now.year, now.month, now.day, 11, 15, 30));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: AnalysisScreen()));
    // The card after it, so its cells are well inside the screen.
    await tester.scrollUntilVisible(find.text('Focus / Break'), 300,
        scrollable: find
            .descendant(
                of: find.byType(AnalysisScreen),
                matching: find.byType(Scrollable))
            .last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('10 AM: 10m'), findsOneWidget);
    expect(find.bySemanticsLabel('11 AM: 15m'), findsOneWidget);
    semantics.dispose();
  });

  group('A progress dialog closes even when another opened on top', () {
    testWidgets('waiting on the study server', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const Scaffold();
        }),
      ));
      final work = Completer<int>();
      final result = runWithProgress(context, 'Working…', (_) => work.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // What the app shell does when a save fails meanwhile.
      unawaited(showInfoDialog(context,
          title: "Couldn't Save", message: 'The device is full.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      work.complete(7);
      expect(await result, 7);
      await tester.pumpAndSettle();
      expect(find.text('Working…'), findsNothing);
      expect(find.text("Couldn't Save"), findsOneWidget);
    });

    testWidgets('saving a scan that fails', (tester) async {
      usePhoneSize(tester);
      await store.init(_FullStorage());
      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(230, 230, 230));
      final page =
          CapturedPage(id: 1, bytes: img.encodePng(image), width: 40, height: 30);
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page])));
      // While the text is read, the app shell reports a failed save.
      ScanService.debugRead = (jpegs) async {
        unawaited(showInfoDialog(tester.element(find.byType(ReviewScreen)),
            title: "Couldn't Save", message: 'The device is full.'));
        return [for (final _ in jpegs) const RecognizedPage()];
      };
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as PDF'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 150; i++) {
          if (find.textContaining("Couldn't create the PDF").evaluate().isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't create the PDF"), findsOneWidget);
      expect(find.text('Creating your PDF…'), findsNothing);
      expect(find.text("Couldn't Save"), findsOneWidget);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(store.notes, isEmpty);
    });
  });
}
