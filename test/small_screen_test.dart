import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/analysis_screen.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/capture/capture_screen.dart';
import 'package:study_app/screens/flashcards/quiz_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/flashcards/study_cards_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/screens/folder_screen.dart';
import 'package:study_app/screens/help_screen.dart';
import 'package:study_app/screens/note_viewer_screen.dart';
import 'package:study_app/screens/plans_screen.dart';
import 'package:study_app/screens/settings_screen.dart';
import 'package:study_app/services/haptics.dart';
import 'package:study_app/services/screen_awake.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/widgets/bottom_nav.dart';

/// Every main screen on a small phone (320 × 568 dp), at normal text size
/// and at the large text many phones are set to: nothing may overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;

  // The app's own fonts: the test font draws every letter a full square
  // wide, which would make text far wider than on a phone.
  setUpAll(() async {
    const fonts = {
      'Inter': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'PlusJakartaSans': ['Medium', 'SemiBold', 'Bold', 'ExtraBold'],
    };
    for (final MapEntry(key: family, value: weights) in fonts.entries) {
      final loader = FontLoader(family);
      for (final w in weights) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
    for (final (family, file) in [
      ('PhosphorLight', 'Phosphor-Light'),
      ('PhosphorFill', 'Phosphor-Fill'),
    ]) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/$file.ttf')))
          .load();
    }
  });

  setUp(() {
    ScreenAwake.enabled = false;
    Haptics.enabled = false;
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    PomodoroController.instance.resetForTesting();
  });

  /// Opens each screen in turn and returns what overflowed, with where.
  Future<List<String>> overflowsOn(WidgetTester tester, double textScale) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final cameras = CaptureScreen.loadCameras;
    CaptureScreen.loadCameras = () async => [];
    addTearDown(() => CaptureScreen.loadCameras = cameras);

    final folder = store.folders.first;
    final cards = [
      for (var i = 0; i < 4; i++)
        Flashcard(
          id: 'c$i',
          front: 'What does the mitochondrion make for the cell? ($i)',
          back: 'Energy, as ATP, through cellular respiration',
        ),
    ];
    final quiz = [
      const QuizQuestion(
        type: QuestionType.multipleChoice,
        prompt: 'Which part of the cell makes most of its energy?',
        answer: 'Mitochondrion',
        options: ['Nucleus', 'Mitochondrion', 'Ribosome', 'Cell wall'],
        answerIndex: 1,
        cardId: 'c0',
      ),
    ];
    final deck = await store.addSet(
      title: 'Cell Biology: Organelles and Their Jobs',
      folderId: folder.id,
      cards: cards,
      quiz: quiz,
      summary: 'How the parts of a cell work together.',
      concepts: const [
        Concept(term: 'Mitochondrion', explanation: 'Makes energy (ATP).'),
      ],
    );
    final thumbnail =
        Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 56)));
    final note = await store.addNote(
      title: 'Lecture 3: Photosynthesis and Respiration',
      folderId: folder.id,
      pdf: Uint8List(8),
      thumbnail: thumbnail,
      pageCount: 3,
      text: 'Photosynthesis makes sugar from light.\nRespiration releases it.',
    );

    final problems = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      final where = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(text)?[0];
      problems.add('${details.exceptionAsString().split('\n').first}'
          '${where == null ? '' : ' ($where)'}');
    };
    try {
      await _walk(tester, problems, folder.id, deck.id, note.id, quiz);
    } finally {
      // Before the test ends, or flutter_test can't report anything.
      FlutterError.onError = previous;
    }
    PomodoroController.instance.resetForTesting();
    return problems;
  }

  testWidgets('at normal text size', (tester) async {
    expect(await overflowsOn(tester, 1.0), isEmpty);
  });

  testWidgets('at large text (1.3×)', (tester) async {
    expect(await overflowsOn(tester, 1.3), isEmpty);
  });
}

/// Opens the tabs and then every other main screen, noting [problems].
Future<void> _walk(WidgetTester tester, List<String> problems, String folderId,
    String setId, String noteId, List<QuizQuestion> quiz) async {
  Future<void> look(String name) async {
    final before = problems.length;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = before; i < problems.length; i++) {
      problems[i] = '$name: ${problems[i]}';
    }
  }

  await tester.pumpWidget(const StudyApp());
  await look('Dashboard');
  for (final tab in [AppTab.library, AppTab.study, AppTab.profile]) {
    await tester.tap(find.byIcon(tab.icon));
    await look(tab.label);
    if (tab == AppTab.study) {
      // Today's summary is shown whole, not cut short with "…".
      final today = tester
          .renderObject<RenderParagraph>(find.textContaining('Today ·'));
      if (today.didExceedMaxLines) problems.add('Study: today strip cut short');
    }
  }

  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  final screens = <String, Widget>{
    'Folder': FolderScreen(folderId: folderId),
    'Set': SetScreen(setId: setId),
    'Study Cards': StudyCardsScreen(setId: setId),
    'Quiz': QuizScreen(setId: setId, questions: quiz),
    'Note Text': NoteTextScreen(noteId: noteId),
    'Analysis': const AnalysisScreen(),
    'Settings': const SettingsScreen(),
    'Backup & Sync': const BackupScreen(),
    'Plans': const PlansScreen(),
    'Help': const HelpScreen(),
    'Camera': const CaptureScreen(),
    'Focus Mode': const FocusScreen(),
  };
  for (final MapEntry(key: name, value: screen) in screens.entries) {
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    await look(name);
    navigator.pop();
    await tester.pump(const Duration(seconds: 1));
  }
}
