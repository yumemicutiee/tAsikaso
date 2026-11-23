import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/backup.dart';
import 'package:study_app/data/plans.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/actions.dart';
import 'package:study_app/screens/folder_screen.dart';
import 'package:study_app/screens/notebook_screen.dart';
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/flashcards/quiz_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/note_viewer_screen.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/utils/format.dart';

import 'support/read_pages.dart';

const ocrText = 'Osmosis: movement of water across a membrane\n'
    'Diffusion - particles spread out';

/// A study kit as the server sends it.
Map<String, Object?> kitReply({
  String notes = '# Transport\n- Osmosis: water across a membrane',
  String summary = 'How things move.',
  List<Map<String, String>> cards = const [],
  List<Map<String, Object?>> quiz = const [],
}) =>
    {
      'kit': {
        'title': 'Transport',
        'summary': summary,
        'notes': notes,
        'concepts': [
          {'term': 'Osmosis', 'explanation': 'Water through a membrane.'},
        ],
        'cards': cards,
        'quiz': quiz,
      },
    };

const twoCards = [
  {'front': 'What is osmosis?', 'back': 'Water moving across a membrane'},
  {'front': 'What is diffusion?', 'back': 'Particles spreading out'},
];

Map<String, Object?> typedQuestion(String prompt, String answer, int card) => {
      'type': 'typed',
      'prompt': prompt,
      'options': <String>[],
      'answerIndex': -1,
      'answer': answer,
      'acceptable': <String>[],
      'explanation': '',
      'cardIndex': card,
    };

/// A study server that never answers, until the app hangs up (closes the
/// client), as a real connection would end.
class SilentServer extends http.BaseClient {
  int requests = 0;
  bool closed = false;
  final _hangUp = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    await _hangUp.future;
    throw http.ClientException('Connection closed', request.url);
  }

  @override
  void close() {
    closed = true;
    if (!_hangUp.isCompleted) _hangUp.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  final requests = <http.Request>[];

  setUp(() {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    ScanService.debugRead = null;
    StudyAi.debugClient = null;
    requests.clear();
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

  void setServer() => store.updatePrefs(store.prefs
      .copyWith(aiServerUrl: 'https://study.test', aiToken: 'secret'));

  /// A study server that answers every request with what [reply] makes.
  void serverAnswers(Object Function(Map<String, Object?> sent) reply,
      {int status = 200}) {
    setServer();
    StudyAi.debugClient = () => MockClient((req) async {
          requests.add(req);
          final sent = jsonDecode(req.body) as Map<String, Object?>;
          return http.Response(jsonEncode(reply(sent)), status,
              headers: {'content-type': 'application/json'});
        });
  }

  SilentServer silentServer() {
    setServer();
    final server = SilentServer();
    StudyAi.debugClient = () => server;
    return server;
  }

  Map<String, Object?> lastSent() =>
      jsonDecode(requests.last.body) as Map<String, Object?>;

  Future<Note> addNote({
    String title = 'Bio Notes',
    String text = ocrText,
    String cleanText = '',
    String summary = '',
    List<Concept> concepts = const [],
    bool textNote = false,
  }) =>
      store.addNote(
        title: title,
        folderId: store.folders.first.id,
        pdf: Uint8List(0),
        thumbnail: Uint8List(0),
        pageCount: 1,
        text: text,
        cleanText: cleanText,
        summary: summary,
        concepts: concepts,
        textNote: textNote,
      );

  /// Make Flashcards on a note, then Make Flashcards on the sheet that asks
  /// where they go (a new set, in the note's folder).
  Future<void> makeCardsHere(WidgetTester tester) async {
    await tester.tap(find.text('Make Flashcards'));
    await tester.pumpAndSettle();
    expect(find.text('New Set'), findsOneWidget);
    await tester.tap(find.text('Make Flashcards').last);
    await tester.pumpAndSettle();
  }

  List<Flashcard> cards(int n) => [
        for (var i = 0; i < n; i++)
          Flashcard(
              id: 'c$i',
              front: 'Question number $i',
              back: 'The answer to question number $i'),
      ];

  Future<FlashcardSet> addSet({
    List<Flashcard> cards = const [],
    String sourceText = '',
    List<QuizQuestion> quiz = const [],
  }) =>
      store.addSet(
        title: 'Cells',
        folderId: store.folders.first.id,
        cards: cards,
        sourceText: sourceText,
        quiz: quiz,
      );

  /// Opens the set screen's ⋮ menu (not a card's).
  Future<void> openSetMenu(WidgetTester tester) async {
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byTooltip('More')));
    await tester.pumpAndSettle();
  }

  group('Cards for a set and for a note', () {
    testWidgets('Make Cards with AI adds the study server\'s cards, concepts '
        'and quiz to a set', (tester) async {
      usePhoneSize(tester);
      serverAnswers((_) => kitReply(
            cards: twoCards,
            quiz: [typedQuestion('What is osmosis?', 'Water moving', 0)],
          ));
      final deck = await addSet(sourceText: ocrText);
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await openSetMenu(tester);
      await tester.tap(find.text('Make Cards with AI'));
      await tester.pumpAndSettle();

      final saved = store.setById(deck.id)!;
      expect(saved.cards.map((c) => c.front),
          ['What is osmosis?', 'What is diffusion?']);
      expect(saved.concepts.single.term, 'Osmosis');
      expect(saved.summary, 'How things move.');
      expect(saved.quiz.single.cardId, saved.cards.first.id);
      expect(find.text('2 cards added.'), findsOneWidget);
      expect(lastSent()['text'], ocrText);
      expect(lastSent()['maxCards'], kFreeSuggestedCardsPerMonth);
      expect(store.suggestedCardsLeft, kFreeSuggestedCardsPerMonth - 2);
    });

    testWidgets('without the study server, cards are suggested from the '
        "set's text to add or skip", (tester) async {
      usePhoneSize(tester);
      final deck = await addSet(sourceText: ocrText);
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await openSetMenu(tester);
      expect(find.text('Make Cards with AI'), findsNothing);
      await tester.tap(find.text('Suggest Cards from Photos'));
      await tester.pumpAndSettle();

      final saved = store.setById(deck.id)!;
      expect(saved.cards, isEmpty);
      expect(saved.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(find.text('2 cards suggested from the text.'), findsOneWidget);
      expect(find.text('Suggested Cards (2)'), findsOneWidget);
    });

    testWidgets("Make Flashcards on a note's text makes a set and opens it",
        (tester) async {
      usePhoneSize(tester);
      serverAnswers((_) => kitReply(cards: twoCards));
      final note = await addNote();
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await makeCardsHere(tester);

      final deck = store.sets.single;
      expect(deck.title, 'Bio Notes');
      expect(deck.folderId, note.folderId);
      expect(deck.cards.length, 2);
      expect(deck.sourceText, ocrText);
      expect(deck.concepts.single.term, 'Osmosis');
      expect(find.byType(SetScreen), findsOneWidget);
      expect(find.text('2 cards made from "Bio Notes".'), findsOneWidget);
    });

    testWidgets("Make Flashcards offline suggests cards from the note's text",
        (tester) async {
      usePhoneSize(tester);
      final note = await addNote();
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await makeCardsHere(tester);

      final deck = store.sets.single;
      expect(deck.cards, isEmpty);
      expect(deck.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(find.text('2 cards suggested from the text.'), findsOneWidget);
    });
  });

  group('Where flashcards from a note go', () {
    testWidgets('a new set can go in another folder', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(textNote: true);
      final other = store.addFolder('Chemistry', 0xFFF5C2A9);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Make Flashcards'));
      await tester.pumpAndSettle();
      // The note's own folder is picked first.
      expect(find.text(store.folder(note.folderId)!.name), findsWidgets);
      await tester.tap(find.byType(DropdownButtonFormField<StudyFolder>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chemistry').last);
      await tester.pumpAndSettle();
      expect(find.text('The note stays in its own Notebook.'), findsOneWidget);
      await tester.tap(find.text('Make Flashcards').last);
      await tester.pumpAndSettle();

      final deck = store.sets.single;
      expect(deck.folderId, other.id);
      expect(store.note(note.id)!.folderId, isNot(other.id));
      expect(deck.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(find.byType(SetScreen), findsOneWidget);
    });

    testWidgets('cards can be added to a set you already have', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(textNote: true);
      final deck = await store.addSet(
          title: 'Cell Biology',
          folderId: note.folderId,
          cards: cards(2),
          sourceText: 'Old: text');
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Make Flashcards'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to a Set'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cell Biology'), findsOneWidget);
      await tester.tap(find.text('Add Cards'));
      await tester.pumpAndSettle();

      expect(store.sets, hasLength(1), reason: 'no new set');
      final saved = store.setById(deck.id)!;
      expect(saved.cards, hasLength(2));
      expect(saved.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(saved.sourceText, 'Old: text\n\n$ocrText');
      expect(find.byType(SetScreen), findsOneWidget);
      expect(find.text('2 cards suggested from the text.'), findsOneWidget);
    });

    testWidgets('with no sets yet, only a new set can be made', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(textNote: true);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Make Flashcards'));
      await tester.pumpAndSettle();
      expect(find.text('You have no flashcard sets yet'), findsOneWidget);
      await tester.tap(find.text('Add to a Set'));
      await tester.pumpAndSettle();
      expect(find.text('Make Flashcards'), findsNWidgets(3)); // still New Set
    });

    testWidgets('closing the sheet makes nothing', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(textNote: true);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Make Flashcards'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // outside the sheet
      await tester.pumpAndSettle();
      expect(store.sets, isEmpty);
      expect(find.byType(NoteTextScreen), findsOneWidget);
    });
  });

  group('Notebook', () {
    testWidgets("a folder's notes are in its Notebook", (tester) async {
      usePhoneSize(tester);
      // A real thumbnail: the Notebook shows it.
      final note = await store.addNote(
        title: 'Cells Lecture',
        folderId: store.folders.first.id,
        pdf: Uint8List(0),
        thumbnail: Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 6))),
        pageCount: 1,
        text: ocrText,
        textNote: true,
      );
      final folder = store.folder(note.folderId)!;
      await tester.pumpWidget(MaterialApp(home: FolderScreen(folderId: folder.id)));
      expect(find.text('Notebook'), findsOneWidget);
      // The Notebook card: how many notes, and the latest one's title.
      expect(find.text('1 note'), findsNWidgets(2)); // the folder's line too
      expect(find.text('Cells Lecture'), findsOneWidget);

      await tester.tap(find.text('Notebook'));
      await tester.pumpAndSettle();
      expect(find.byType(NotebookScreen), findsOneWidget);
      expect(find.text('${folder.name} Notebook'), findsOneWidget);
      await tester.tap(find.text('Cells Lecture'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteTextScreen), findsOneWidget);
    });

    testWidgets('an empty Notebook says how to fill it', (tester) async {
      usePhoneSize(tester);
      final folder = store.addFolder('History', 0xFFA9CFF5);
      await tester.pumpWidget(MaterialApp(home: FolderScreen(folderId: folder.id)));
      expect(find.text('No notes yet'), findsOneWidget);
      await tester.tap(find.text('Notebook'));
      await tester.pumpAndSettle();
      expect(find.text('History Notebook'), findsOneWidget);
      expect(find.textContaining('This notebook is empty'), findsOneWidget);
      expect(find.text('Scan Notes'), findsOneWidget);
    });
  });

  group('Text Notes', () {
    test('remember that they are Text Notes, and edited, in a backup', () {
      final note = Note(
          id: 'n1',
          title: 'Cells',
          folderId: 'f1',
          createdAt: DateTime(2026),
          text: 'Mitosis',
          textNote: true,
          edited: true);
      final back = Note.fromJson(note.toJson());
      expect(back.textNote, isTrue);
      expect(back.edited, isTrue);
      final plain = Note.fromJson(note.copyWith(textNote: false, edited: false).toJson());
      expect(plain.textNote, isFalse);
      expect(plain.toJson().containsKey('textNote'), isFalse);
    });

    testWidgets('open on their text; other notes open on their PDF',
        (tester) async {
      usePhoneSize(tester);
      final textNote = await addNote(textNote: true);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openNote(context, textNote),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteTextScreen), findsOneWidget);
      expect(find.byType(NoteViewerScreen), findsNothing);
      expect(find.text('Text Notes'), findsOneWidget);
      expect(find.text('View the original page'), findsOneWidget);

      await tester.tap(find.byTooltip('View Pages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // the page slides in
      expect(find.byType(NoteViewerScreen), findsOneWidget);
      expect(find.text('Original Pages'), findsOneWidget);
      // No way back to the text but Back, and no second menu.
      expect(find.byTooltip('View Text'), findsNothing);
    });

    testWidgets('Edit fixes a misread word, and cards are made from the fixed '
        'text', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(
          text: 'Osmosls: movement of water across a membrane', textNote: true);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      expect(find.textContaining('Tap Edit to fix a word'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField),
          'Osmosis: movement of water across a membrane');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = store.note(note.id)!;
      expect(saved.text, 'Osmosis: movement of water across a membrane');
      expect(saved.edited, isTrue);
      expect(find.byType(NoteTextScreen), findsOneWidget);
      expect(find.text('Edited by you.'), findsOneWidget);
      expect(find.text('Notes saved'), findsOneWidget);

      await makeCardsHere(tester);
      final deck = store.sets.single;
      expect(deck.suggestions.single.front, 'Osmosis');
      expect(deck.sourceText, 'Osmosis: movement of water across a membrane');
    });

    testWidgets('Edit changes the typed-up notes when they are shown',
        (tester) async {
      usePhoneSize(tester);
      final note = await addNote(
          text: 'raw', cleanText: '# Cells\n- Mitocondria', textNote: true);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lines starting with #'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '# Cells\n- Mitochondria');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = store.note(note.id)!;
      expect(saved.cleanText, '# Cells\n- Mitochondria');
      expect(saved.text, 'raw');
    });

    testWidgets('leaving Edit with changes asks first', (tester) async {
      usePhoneSize(tester);
      final note = await addNote(textNote: true);
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Something else');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard Changes?'), findsOneWidget);

      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(store.note(note.id)!.text, ocrText);
      expect(store.note(note.id)!.edited, isFalse);
    });
  });

  group('Note text', () {
    testWidgets('switches between the typed-up notes and the text as read',
        (tester) async {
      usePhoneSize(tester);
      final note = await addNote(
        text: 'mitochondria make atp',
        cleanText: '# Cells\n- Mitochondria make ATP',
        summary: 'About cells.',
        concepts: const [Concept(term: 'ATP', explanation: 'Cell energy.')],
      );
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      expect(find.text('About cells.'), findsOneWidget);
      expect(find.text('Key Concepts'), findsOneWidget);
      expect(find.textContaining('Mitochondria make ATP'), findsOneWidget);
      // Smart Study is off: nothing to type up with.
      expect(find.text('Type Up Again'), findsNothing);

      await tester.tap(find.text('Show the text as read'));
      await tester.pump();
      expect(find.text('mitochondria make atp'), findsOneWidget);
      expect(find.text('About cells.'), findsNothing);
      expect(find.text('Key Concepts'), findsNothing);

      await tester.tap(find.text('Show the typed-up notes'));
      await tester.pump();
      expect(find.text('About cells.'), findsOneWidget);
    });

    testWidgets('Type Up with AI types up a note saved offline, without '
        'using suggested cards', (tester) async {
      usePhoneSize(tester);
      serverAnswers((_) => kitReply(
          notes: '# Transport\n- Osmosis moves water', summary: 'All about it.'));
      final note = await addNote();
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      expect(find.text('Show the text as read'), findsNothing);
      await tester.tap(find.text('Type Up with AI'));
      await tester.pumpAndSettle();

      final saved = store.note(note.id)!;
      expect(saved.cleanText, '# Transport\n- Osmosis moves water');
      expect(saved.summary, 'All about it.');
      expect(saved.concepts.single.term, 'Osmosis');
      expect(saved.text, ocrText); // the text as read stays
      expect(lastSent()['text'], ocrText);
      expect(lastSent()['maxCards'], 0);
      expect(lastSent()['quizCount'], 0);
      expect(store.suggestedCardsLeft, kFreeSuggestedCardsPerMonth);

      expect(find.text('Your notes are typed up.'), findsOneWidget);
      expect(find.text('All about it.'), findsOneWidget);
      expect(find.text('Type Up Again'), findsOneWidget);
      expect(find.text('Show the text as read'), findsOneWidget);
    });

    testWidgets("Type Up with AI shows the server's message when it fails",
        (tester) async {
      usePhoneSize(tester);
      serverAnswers(
        (_) => {
          'error': {'code': 'unauthorized', 'message': "This app isn't allowed."},
        },
        status: 401,
      );
      final note = await addNote();
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Type Up with AI'));
      await tester.pumpAndSettle();
      expect(find.text("This app isn't allowed."), findsOneWidget);
      expect(store.note(note.id)!.cleanText, '');
    });
  });

  group('Cancel', () {
    testWidgets('Cancel drops the request and saves nothing', (tester) async {
      usePhoneSize(tester);
      final server = silentServer();
      final note = await addNote();
      await tester.pumpWidget(MaterialApp(home: NoteTextScreen(noteId: note.id)));
      await tester.tap(find.text('Type Up with AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // the dialog opens
      expect(find.text('Typing up your notes…'), findsOneWidget);
      expect(server.requests, 1);
      expect(server.closed, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Typing up your notes…'), findsNothing);
      expect(server.closed, isTrue); // the connection is closed
      expect(store.note(note.id)!.cleanText, '');
      expect(find.byType(SnackBar), findsNothing); // no error to show
    });

    testWidgets('Cancel while a quiz is written opens no quiz and keeps none',
        (tester) async {
      usePhoneSize(tester);
      final server = silentServer();
      final deck = await addSet(cards: cards(3));
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.tap(find.text('Take a Quiz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // the dialog opens
      expect(find.text('Writing your quiz…'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.closed, isTrue);
      expect(find.byType(QuizScreen), findsNothing);
      expect(store.setById(deck.id)!.quiz, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Saving a scan', () {
    CapturedPage page() {
      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(230, 230, 230));
      return CapturedPage(
          id: 1, bytes: img.encodePng(image), width: 40, height: 30);
    }

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

    Future<void> openSaveSheet(WidgetTester tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page()])));
      await tapNextAndRead(tester);
    }

    /// Saving renders pages in another isolate, so wait in real time.
    Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 150 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
    }

    testWidgets('with no text read, the pages are still saved, for the notes '
        'to be typed in', (tester) async {
      ScanService.debugRead =
          (jpegs) async => [for (final _ in jpegs) const RecognizedPage()];
      await openSaveSheet(tester);
      expect(find.text('1 page, no text found'), findsOneWidget);
      await tester.tap(find.text('Save Notes').last);
      await tester.pump();
      await waitUntil(tester, () => store.notes.isNotEmpty);
      await tester.pumpAndSettle();

      final note = store.notes.single;
      expect(note.text, isEmpty);
      expect(note.title, endsWith(formatNoteDate(DateTime.now())));
      expect(find.byType(NoteTextScreen), findsOneWidget);
      expect(find.text("No text was read from this note's pages."), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });

    testWidgets('Cancel while typing up still saves the notes, as read',
        (tester) async {
      readsText();
      final server = silentServer();
      // Read on the phone, so the one wait is the typing up.
      store.updatePrefs(store.prefs.copyWith(aiReading: false));
      await openSaveSheet(tester);
      await tester.tap(find.text('Save Notes').last);
      await tester.pump();
      await waitUntil(tester, () => server.requests > 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // Cancel shows
      expect(find.text('Typing up your notes…'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await waitUntil(tester, () => store.notes.isNotEmpty);
      await tester.pumpAndSettle();

      expect(server.closed, isTrue);
      final note = store.notes.single;
      expect(note.cleanText, isEmpty);
      expect(note.text, contains('Osmosis'));
      expect(find.byType(NoteTextScreen), findsOneWidget);
      expect(find.textContaining('The AI step was skipped.'), findsOneWidget);
    });
  });

  group('Read Photos with Claude', () {
    CapturedPage page(int id) {
      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(230, 230, 230));
      return CapturedPage(
          id: id, bytes: img.encodePng(image), width: 40, height: 30);
    }

    /// The phone's OCR finds one misread line on every page.
    void phoneReads() {
      ScanService.debugRead = (jpegs) async => [
            for (final _ in jpegs)
              const RecognizedPage(lines: [
                RecognizedLine(
                    text: 'Osm0sis: rnovement of waler',
                    left: 2, top: 2, right: 30, bottom: 8),
              ]),
          ];
    }

    const claudeText = 'Osmosis: movement of water across a membrane\n\n'
        '- Diffusion: particles spread out';

    /// The study server: Claude reads pages with [read] (null: reads them
    /// as [claudeText]); study kits answer as usual.
    void server({http.Response Function(int page)? read}) {
      var pages = 0;
      setServer();
      StudyAi.debugClient = () => MockClient((req) async {
            requests.add(req);
            if (req.url.path == '/v1/read-page') {
              final n = ++pages;
              return read?.call(n) ??
                  http.Response(jsonEncode({'page': {'text': claudeText}}), 200,
                      headers: {'content-type': 'application/json'});
            }
            return http.Response(jsonEncode(kitReply()), 200,
                headers: {'content-type': 'application/json'});
          });
    }

    Iterable<http.Request> reads() =>
        requests.where((r) => r.url.path == '/v1/read-page');

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save Notes').last);
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 150 && store.notes.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }

    Future<void> scan(WidgetTester tester, int pages) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: ReviewScreen(pages: [for (var i = 1; i <= pages; i++) page(i)])));
      await tapNextAndRead(tester);
    }

    testWidgets("Claude's reading of the photo becomes the note's text",
        (tester) async {
      phoneReads();
      server();
      await scan(tester, 1);

      final sent = reads().single;
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['mediaType'], 'image/jpeg');
      final photo = base64Decode(body['image']! as String);
      expect(photo.sublist(0, 2), [0xFF, 0xD8], reason: 'the cropped page, as a JPEG');
      expect(sent.headers['authorization'], 'Bearer secret');

      await save(tester);
      final note = store.notes.single;
      expect(note.text, claudeText, reason: "Claude's text, not the phone's misreading");
      expect(note.text, isNot(contains('Osm0sis')));
      // The study kit is made from Claude's text.
      final kitBody = jsonDecode(
              requests.lastWhere((r) => r.url.path == '/v1/study-kit').body)
          as Map<String, Object?>;
      expect(kitBody['text'], claudeText);
    });

    testWidgets('every page is read by Claude, and the pages keep their order',
        (tester) async {
      phoneReads();
      server(
          read: (n) => http.Response(
              jsonEncode({'page': {'text': 'Page text $n'}}), 200,
              headers: {'content-type': 'application/json'}));
      await scan(tester, 4);
      expect(reads(), hasLength(4));
      await save(tester);
      expect(store.notes.single.text,
          'Page text 1\n\nPage text 2\n\nPage text 3\n\nPage text 4');
    });

    testWidgets("a page Claude can't read keeps the phone's text, and the save "
        'sheet says why', (tester) async {
      phoneReads();
      server(
          read: (_) => http.Response(
              jsonEncode({
                'error': {
                  'code': 'daily_limit',
                  'message': "You've reached today's limit of 100 pages read "
                      'by Claude. Try again tomorrow.',
                },
              }),
              429,
              headers: {'content-type': 'application/json'}));
      await scan(tester, 3);
      expect(reads(), hasLength(1),
          reason: 'after a daily limit the other pages are not sent');
      expect(
          find.textContaining('The pages were read on your phone instead of by Claude. '
              "You've reached today's limit of 100 pages"),
          findsOneWidget);
      await save(tester);
      expect(store.notes.single.text, contains('Osm0sis'),
          reason: "the phone's text, as before Claude");
    });

    testWidgets('a blank answer from Claude keeps what the phone found',
        (tester) async {
      phoneReads();
      server(
          read: (_) => http.Response(jsonEncode({'page': {'text': '  '}}), 200,
              headers: {'content-type': 'application/json'}));
      await scan(tester, 1);
      await save(tester);
      expect(store.notes.single.text, contains('Osm0sis'));
    });

    testWidgets('switched off, no photo is sent', (tester) async {
      phoneReads();
      server();
      store.updatePrefs(store.prefs.copyWith(aiReading: false));
      await scan(tester, 2);
      expect(reads(), isEmpty);
      await save(tester);
      expect(store.notes.single.text, contains('Osm0sis'));
    });

    testWidgets('with Smart Study off, no photo is sent', (tester) async {
      phoneReads();
      server();
      store.updatePrefs(store.prefs.copyWith(useAi: false));
      await scan(tester, 1);
      expect(reads(), isEmpty);
    });

    testWidgets('the setting is saved, and on by default', (tester) async {
      final prefs = AppPrefs.fromJson(
          store.prefs.copyWith(aiReading: false).toJson());
      expect(prefs.aiReading, isFalse);
      expect(AppPrefs.fromJson(const {}).aiReading, isTrue,
          reason: 'on for old save files and new installs');
    });
  });

  group('Quizzes', () {
    const mcQuestion = QuizQuestion(
      type: QuestionType.multipleChoice,
      prompt: 'Which one is question number 0?',
      options: ['The answer to question number 0', 'Nope', 'No', 'Never'],
      answerIndex: 0,
      answer: 'The answer to question number 0',
      cardId: 'c0',
    );

    Future<void> answerAll(WidgetTester tester, String option) async {
      await tester.tap(find.text(option));
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pump();
      await tester.tap(find.text('See Results'));
      await tester.pumpAndSettle();
    }

    testWidgets('Try Again starts the same quiz over', (tester) async {
      usePhoneSize(tester);
      final deck = await addSet(cards: cards(3));
      await tester.pumpWidget(MaterialApp(
          home: QuizScreen(setId: deck.id, questions: const [mcQuestion])));
      await answerAll(tester, 'Nope');
      expect(find.text('0%'), findsOneWidget);

      await tester.tap(find.text('Try Again (Shuffled)'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 1'), findsOneWidget);
      await answerAll(tester, 'The answer to question number 0');
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('You got 1 of 1 question right.'), findsOneWidget);
    });

    testWidgets('New Quiz asks how many questions and which types',
        (tester) async {
      usePhoneSize(tester);
      final deck = await addSet(cards: cards(6));
      await tester.pumpWidget(MaterialApp(
          home: QuizScreen(setId: deck.id, questions: const [mcQuestion])));
      await answerAll(tester, 'The answer to question number 0');
      await tester.tap(find.text('New Quiz'));
      await tester.pumpAndSettle();

      // Six cards make at most six questions offline.
      expect(find.widgetWithText(ChoiceChip, '5'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '6'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '10'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '5'));
      await tester.pump();
      for (final t in ['Multiple Choice', 'True or False', 'Fill in the Blank']) {
        await tester.tap(find.widgetWithText(FilterChip, t));
        await tester.pump();
      }
      // The last type can't be turned off.
      await tester.tap(find.widgetWithText(FilterChip, 'Type the Answer'));
      await tester.pump();
      expect(find.text('At least one type stays on.'), findsOneWidget);

      await tester.tap(find.text('Make Quiz'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 5'), findsOneWidget);
      expect(find.text('Type the Answer'), findsOneWidget);
      final quiz = store.setById(deck.id)!.quiz;
      expect(quiz.length, 5);
      expect(quiz.every((q) => q.type == QuestionType.typed), isTrue);
    });

    testWidgets("New Quiz sends the count and types to the study server, "
        'and keeps only those types', (tester) async {
      usePhoneSize(tester);
      serverAnswers((_) => {
            'quiz': {
              'questions': [
                typedQuestion('What is question number 1?',
                    'The answer to question number 1', 1),
                {
                  'type': 'multiple_choice',
                  'prompt': 'Not asked for',
                  'options': ['a', 'b', 'c', 'd'],
                  'answerIndex': 0,
                  'answer': 'a',
                  'cardIndex': 0,
                },
              ],
            },
          });
      final deck = await addSet(cards: cards(3));
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      // With the server, thin sets are fine.
      expect(find.text('Add a few more cards for a better quiz.'), findsNothing);
      await openSetMenu(tester);
      await tester.tap(find.text('New Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '5'));
      await tester.tap(find.widgetWithText(FilterChip, 'Multiple Choice'));
      await tester.pump();
      await tester.tap(find.text('Make Quiz'));
      await tester.pumpAndSettle();

      expect(lastSent()['count'], 5);
      expect(lastSent()['types'], ['true_false', 'fill_blank', 'typed']);
      expect(find.byType(QuizScreen), findsOneWidget);
      expect(find.text('Question 1 of 1'), findsOneWidget);
      expect(store.setById(deck.id)!.quiz.single.type, QuestionType.typed);
    });

    testWidgets('when the server fails, the quiz says so at the top instead '
        'of a toast over the Check button', (tester) async {
      usePhoneSize(tester);
      serverAnswers(
        (_) => {
          'error': {'code': 'upstream', 'message': 'Claude returned an error.'},
        },
        status: 500,
      );
      final deck = await addSet(cards: cards(4));
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.tap(find.text('Take a Quiz'));
      await tester.pumpAndSettle();

      expect(find.byType(QuizScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
          find.text('Claude returned an error. The quiz was made from your '
              'cards instead.'),
          findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.textContaining('Claude returned an error.'), findsNothing);
      expect(find.text('Check'), findsOneWidget);
    });

    testWidgets('a partly right answer counts as half, and as not known for '
        'smart review', (tester) async {
      usePhoneSize(tester);
      final deck = await store.addSet(
        title: 'Cells',
        folderId: store.folders.first.id,
        cards: [
          const Flashcard(id: 'a', front: 'What makes ATP?', back: 'The mitochondria'),
          const Flashcard(id: 'b', front: 'Osmosis', back: 'Movement of water across a membrane')
              .scheduled(interval: 3, due: DateTime(2026)),
          const Flashcard(id: 'c', front: 'Ribosome', back: 'Makes proteins'),
        ],
      );
      const questions = [
        QuizQuestion(
          type: QuestionType.multipleChoice,
          prompt: 'What makes ATP?',
          options: ['The mitochondria', 'Ribosome', 'Nucleus', 'Golgi'],
          answerIndex: 0,
          answer: 'The mitochondria',
          cardId: 'a',
        ),
        QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What is osmosis?',
          answer: 'Movement of water across a membrane',
          cardId: 'b',
        ),
        QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What does a ribosome do?',
          answer: 'Makes proteins',
          cardId: 'c',
        ),
      ];
      await tester.pumpWidget(
          MaterialApp(home: QuizScreen(setId: deck.id, questions: questions)));

      await tester.tap(find.text('The mitochondria'));
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'water moves across membrane');
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Partly right'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'builds the cell wall');
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See Results'));
      await tester.pumpAndSettle();

      expect(find.text('50%'), findsOneWidget); // (1 + ½) of 3
      expect(find.text('You got 1 right and 1 partly right of 3 questions.'),
          findsOneWidget);
      expect(find.text('A partly right answer counts as half.'), findsOneWidget);
      final saved = store.setById(deck.id)!;
      // Known, it would have gone from 3 days to 7; partly right starts over.
      expect(saved.cards.firstWhere((c) => c.id == 'b').interval, 1);
      expect(saved.lastKnown, 1);
      expect(saved.lastSeen, 3);
    });

    test('the score: a right answer is a point, a partly right one half', () {
      expect(quizPercent(correct: 2, partly: 1, of: 4), 63); // 62.5
      expect(quizPercent(correct: 0, partly: 2, of: 2), 50);
      expect(quizPercent(correct: 0, partly: 0, of: 0), 0);
    });
  });

  group('Set screen', () {
    testWidgets('the saved quiz can be looked through, and a bad question '
        'deleted', (tester) async {
      usePhoneSize(tester);
      final deck = await addSet(cards: cards(4), quiz: const [
        QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What is question number 1?',
          answer: 'The answer to question number 1',
          cardId: 'c1',
        ),
        QuizQuestion(
          type: QuestionType.trueFalse,
          prompt: 'A badly written question',
          options: ['True', 'False'],
          answerIndex: 0,
          answer: 'True',
          cardId: 'c2',
        ),
      ]);
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Quiz Questions (2)'), 200,
          scrollable: list);
      await tester.pumpAndSettle();
      // Folded away at first.
      expect(find.text('A badly written question'), findsNothing);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('A badly written question'), 200,
          scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text('True or False'), findsOneWidget);
      expect(find.text('Answer: True'), findsOneWidget);
      expect(find.text('Answer: The answer to question number 1'), findsOneWidget);

      final delete = find.descendant(
        of: find.ancestor(
            of: find.text('A badly written question'),
            matching: find.byType(Row)).first,
        matching: find.byTooltip('Delete Question'),
      );
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete Question?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final quiz = store.setById(deck.id)!.quiz;
      expect(quiz.single.prompt, 'What is question number 1?');
      expect(find.text('Quiz Questions (1)'), findsOneWidget);
      expect(find.text('A badly written question'), findsNothing);
    });

    testWidgets('a set with few cards and no study server suggests adding '
        'more for a better quiz', (tester) async {
      usePhoneSize(tester);
      final deck = await addSet(cards: cards(3));
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      expect(find.text('Add a few more cards for a better quiz.'), findsOneWidget);
      expect(find.text('Take a Quiz'), findsOneWidget); // it still works

      store.updateSet(store.setById(deck.id)!.copyWith(cards: cards(4)));
      await tester.pump();
      expect(find.text('Add a few more cards for a better quiz.'), findsNothing);
    });
  });

  group('Search', () {
    test('finds notes by their typed-up text, summary and key concepts',
        () async {
      final note = await addNote(
        text: 'raw ocr',
        cleanText: '# Cells\n- The nucleus holds DNA',
        summary: 'Organelles and what they do.',
        concepts: const [
          Concept(term: 'Mitochondria', explanation: 'The powerhouse of the cell'),
        ],
      );
      expect(store.searchNotes('nucleus').single.id, note.id);
      expect(store.searchNotes('ORGANELLES').single.id, note.id);
      expect(store.searchNotes('mitochondria').single.id, note.id);
      expect(store.searchNotes('powerhouse').single.id, note.id);
      expect(store.searchNotes('photosynthesis'), isEmpty);
    });

    test('finds sets by their summary and key concepts', () async {
      final deck = await store.addSet(
        title: 'Bio',
        folderId: store.folders.first.id,
        summary: 'How cells make energy.',
        concepts: const [Concept(term: 'ATP', explanation: 'Energy currency')],
      );
      expect(store.searchSets('make energy').single.id, deck.id);
      expect(store.searchSets('atp').single.id, deck.id);
      expect(store.searchSets('currency').single.id, deck.id);
      expect(store.searchSets('photosynthesis'), isEmpty);
    });
  });

  group("The study server's app token", () {
    final sync = DriveSync.instance;
    late MemoryDriveStore drive;

    setUp(() async {
      drive = MemoryDriveStore();
      DriveSync.debugStore = drive;
      await sync.resetForTesting();
      store.updatePrefs(store.prefs
          .copyWith(aiServerUrl: 'https://mine.test', aiToken: 'secret-token'));
    });

    tearDown(() async {
      await sync.resetForTesting();
      DriveSync.debugStore = null;
    });

    test('stays out of backup files, and a restore keeps this device\'s '
        'server', () async {
      final zip = await store.createBackup();
      final data = unpackBackup(zip).json;
      expect(data, isNot(contains('secret-token')));
      expect(data, contains('https://mine.test'));
      expect(store.exportJson(), isNot(contains('secret-token')));
      // The device's own save file keeps it.
      expect(store.prefs.aiToken, 'secret-token');

      store.updatePrefs(store.prefs
          .copyWith(aiServerUrl: 'https://other.test', aiToken: 'other-token'));
      await store.restoreBackup(zip);
      expect(store.prefs.aiServerUrl, 'https://other.test');
      expect(store.prefs.aiToken, 'other-token');

      // A new phone with no server set takes the backup's address (it isn't
      // a secret), but no token comes with it.
      store.updatePrefs(store.prefs.copyWith(aiServerUrl: '', aiToken: ''));
      await store.restoreBackup(zip);
      expect(store.prefs.aiServerUrl, 'https://mine.test');
      expect(store.prefs.aiToken, '');
    });

    test('stays out of the copy on Google Drive, and a restore from Drive '
        'keeps it', () async {
      store.startPlan(PlusPlan.yearly); // syncing is tAsikaso+
      await sync.debugSignIn();
      expect(await sync.syncNow(), isNull);
      final uploaded = utf8.decode(drive.byName[DriveSync.dataName]!);
      expect(uploaded, isNot(contains('secret-token')));
      expect(uploaded, contains('"version"'));

      expect(await sync.restoreFromDrive(), isNull);
      expect(store.prefs.aiServerUrl, 'https://mine.test');
      expect(store.prefs.aiToken, 'secret-token');
    });
  });
}
