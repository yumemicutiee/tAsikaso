import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/data/storage/local_storage.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/loading_screen.dart';
import 'package:study_app/screens/welcome/intro_slides.dart';
import 'package:study_app/screens/welcome/welcome_screen.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/services/haptics.dart';
import 'package:study_app/services/screen_awake.dart';
import 'package:study_app/theme/app_colors.dart';

/// A new install: no test data, the welcome (Google or no account), the
/// slides about the app once, and the loading screen when the app opens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;

  // The app's own fonts, so text is as wide as on a phone.
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

  void phoneSize(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  /// A brand-new install, as the app starts it.
  Future<void> newInstall([LocalStorage? storage]) async {
    AppStore.samplesOnFirstLaunch = false;
    try {
      await store.init(storage ?? MemoryStorage());
    } finally {
      AppStore.samplesOnFirstLaunch = true;
    }
  }

  group('No test data', () {
    test('a new install starts empty, and not yet welcomed', () async {
      await newInstall();
      expect(store.folders, isEmpty);
      expect(store.activeTasks, isEmpty);
      expect(store.completedTasks, isEmpty);
      expect(store.notes, isEmpty);
      expect(store.sets, isEmpty);
      expect(store.currentTask, isNull);
      expect(store.prefs.welcomed, isFalse);
      expect(store.prefs.userName, isEmpty);
    });

    test('the sample data of older versions goes, unless it was used',
        () async {
      // Data saved by 0.7.0, which started with the samples: one sample
      // folder has a set in it and one sample task was focused on.
      final storage = MemoryStorage();
      await store.init(storage); // the samples (tests start with them)
      final biology = store.folders.firstWhere((f) => f.id == 'f-biology');
      await store.addSet(
        title: 'Cells',
        folderId: biology.id,
        cards: const [Flashcard(id: 'c1', front: 'Cell', back: 'The unit of life')],
      );
      final cert = store.task('t-cert')!;
      store.updateTask(cert.copyWith(pomodorosDone: 5, focusMinutes: 125));
      store.selectTask('t-mod1');
      final mine = store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.pendingSaves;
      final old = jsonDecode((await storage.readJson())!) as Map<String, Object?>;
      old.remove('noSamples');
      (old['prefs'] as Map<String, Object?>).remove('welcomed');
      await storage.writeJson(jsonEncode(old));

      await store.init(storage);

      expect(store.folders.map((f) => f.id), unorderedEquals([biology.id, mine.id]));
      expect(store.activeTasks.map((t) => t.id), ['t-cert']);
      expect(store.task('t-cert')!.pomodorosDone, 5);
      expect(store.currentTask?.id, 't-cert'); // the picked task was removed
      expect(store.sets.single.title, 'Cells');
      // Old installs see the welcome once too.
      expect(store.prefs.welcomed, isFalse);

      // Saved without them, and never looked at again.
      await store.pendingSaves;
      final saved = jsonDecode((await storage.readJson())!) as Map<String, Object?>;
      expect(saved['noSamples'], isTrue);
      expect((saved['folders'] as List).length, 2);
    });

    test('a folder the user made later is never taken for a sample', () async {
      final storage = MemoryStorage();
      await newInstall(storage);
      store.addFolder('Biology', 0xFFA8DCC1);
      store.addTask('Study Module 1', 6);
      await store.pendingSaves;
      await store.init(storage);
      expect(store.folders.single.name, 'Biology');
      expect(store.activeTasks.single.title, 'Study Module 1');
    });

    test('the welcome is remembered, and kept in backups', () {
      const prefs = AppPrefs(welcomed: true);
      expect(AppPrefs.fromJson(prefs.toJson()).welcomed, isTrue);
      expect(AppPrefs.fromJson(const AppPrefs().toJson()).welcomed, isFalse);
    });
  });

  group('Welcome', () {
    testWidgets('a new install opens on the welcome, not the app',
        (tester) async {
      phoneSize(tester);
      await newInstall();
      await tester.pumpWidget(const StudyApp());
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Sign up or log in'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue without an account'), findsOneWidget);
    });

    testWidgets('without an account: a name, the slides once, then the app',
        (tester) async {
      phoneSize(tester);
      await newInstall();
      await tester.pumpWidget(const StudyApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue without an account'));
      await tester.pumpAndSettle();
      expect(find.text('What should we call you?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Budi Santoso ');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(store.prefs.userName, 'Budi Santoso');
      expect(find.byType(IntroSlides), findsOneWidget);
      expect(find.text('Welcome, Budi!'), findsOneWidget);
      expect(store.prefs.welcomed, isFalse); // not until the slides are done

      final titles = [
        for (final s in IntroSlides.slides('Budi')) s.title,
      ];
      for (final title in titles.skip(1)) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Next'), findsNothing);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(IntroSlides), findsNothing);
      expect(store.prefs.welcomed, isTrue);
      // Back can't return to the welcome.
      expect(Navigator.of(tester.element(find.byType(HomeShell))).canPop(),
          isFalse);

      // Opened again: straight into the app.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const StudyApp());
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('the name can be left empty, and the slides skipped',
        (tester) async {
      phoneSize(tester);
      await newInstall();
      await tester.pumpWidget(const StudyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without an account'));
      await tester.pumpAndSettle();
      // Back to the choice, and on again.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.tap(find.text('Continue without an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to tAsikaso!'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(store.prefs.welcomed, isTrue);
      expect(store.prefs.userName, isEmpty);
    });

    group('with Google', () {
      late MemoryDriveStore drive;
      setUp(() async {
        drive = MemoryDriveStore()..name = 'Ana Cruz';
        DriveSync.debugStore = drive;
        await DriveSync.instance.resetForTesting();
      });
      tearDown(() async {
        await DriveSync.instance.resetForTesting();
        DriveSync.debugStore = null;
      });

      testWidgets("signs in and takes the account's name", (tester) async {
        phoneSize(tester);
        await newInstall();
        await tester.pumpWidget(const StudyApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();

        expect(DriveSync.instance.isSignedIn, isTrue);
        expect(store.prefs.userName, 'Ana Cruz');
        expect(find.text('Welcome, Ana!'), findsOneWidget);
      });

      testWidgets('without a name from Google, asks for one', (tester) async {
        phoneSize(tester);
        drive.name = null;
        await newInstall();
        await tester.pumpWidget(const StudyApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(find.text('What should we call you?'), findsOneWidget);
        expect(find.text('Signed in as student@example.com'), findsOneWidget);
        expect(find.text('Back'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Rina');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome, Rina!'), findsOneWidget);
      });

      testWidgets('data on Google Drive can be brought back', (tester) async {
        phoneSize(tester);
        // This account's data from another phone.
        await drive.upload(
          DriveSync.dataName,
          utf8.encode(jsonEncode({
            'version': 1,
            'noSamples': true,
            'folders': [
              {'id': 'f-1', 'name': 'History', 'color': 0xFFF9C9A3},
            ],
            'prefs': {'name': 'Ana', 'welcomed': true},
          })),
        );
        await newInstall();
        await tester.pumpWidget(const StudyApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome Back'), findsOneWidget);
        await tester.tap(find.text('Bring It Back'));
        await tester.pumpAndSettle();

        expect(store.folders.single.name, 'History');
        expect(find.byType(IntroSlides), findsOneWidget);
        expect(find.text('Welcome, Ana!'), findsOneWidget);
      });
    });

    for (final (label, size, scale) in [
      ('a small phone', const Size(320, 568), 1.0),
      ('large text', const Size(360, 740), 1.3),
    ]) {
      testWidgets('nothing overflows on $label', (tester) async {
        phoneSize(tester, size: size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await newInstall();
        await tester.pumpWidget(const StudyApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue without an account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        for (var i = 1; i < IntroSlides.slides('').length; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const MaterialApp(home: LoadingScreen()));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Loading screen', () {
    testWidgets('shows while the app gets ready, then the app opens',
        (tester) async {
      phoneSize(tester);
      var loaded = false;
      var ready = false;
      await tester.pumpWidget(AppLoader(
        load: () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          loaded = true;
        },
        onReady: () => ready = true,
        minimum: const Duration(milliseconds: 800),
      ));
      expect(find.byType(LoadingScreen), findsOneWidget);
      expect(find.text('tAsikaso'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(loaded, isTrue);
      // Still up: it stays for a moment so it doesn't just flash.
      expect(find.byType(LoadingScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(LoadingScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget); // tests are welcomed
      expect(ready, isTrue);
    });

    testWidgets('a new install goes from the loading screen to the welcome',
        (tester) async {
      phoneSize(tester);
      AppStore.samplesOnFirstLaunch = false;
      addTearDown(() => AppStore.samplesOnFirstLaunch = true);
      await tester.pumpWidget(AppLoader(
        load: () => store.init(MemoryStorage()),
        minimum: const Duration(milliseconds: 200),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });
}
