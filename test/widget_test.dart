import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/backup.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/data/storage/local_storage_idb.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/analysis_screen.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/capture/capture_screen.dart';
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/capture/scan_flow.dart';
import 'package:study_app/screens/dashboard_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/flashcards/study_cards_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/screens/plans_screen.dart';
import 'package:study_app/screens/settings_screen.dart';
import 'package:study_app/services/haptics.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/screen_awake.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/utils/card_suggestions.dart';
import 'package:study_app/utils/spaced_review.dart';
import 'package:study_app/widgets/bottom_nav.dart';

void main() {
  // The timer controller watches the app lifecycle, so it needs a binding
  // even in plain unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScreenAwake.enabled = false;
    Haptics.enabled = false;
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    AppStore.instance.resetForTesting();
    PomodoroController.instance.resetForTesting();
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('Bottom navigation switches screens', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    expect(find.text("Today's Focus"), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);

    await tester.tap(find.byIcon(AppTab.library.icon));
    await tester.pumpAndSettle();
    expect(find.text('Folders (5)'), findsOneWidget);

    await tester.tap(find.byIcon(AppTab.study.icon));
    await tester.pumpAndSettle();
    expect(find.text('START'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
  });

  testWidgets('Capture button opens the capture screen', (tester) async {
    usePhoneSize(tester);
    // No camera in tests: pretend the device has none.
    final original = CaptureScreen.loadCameras;
    CaptureScreen.loadCameras = () async => [];
    addTearDown(() => CaptureScreen.loadCameras = original);

    await tester.pumpWidget(const StudyApp());

    await tester.tap(find.byType(CameraButton));
    // The screen should still open and offer the gallery instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Single'), findsOneWidget);
    expect(find.text('Multiple'), findsOneWidget);
    expect(find.text('Import Photos'), findsOneWidget);
  });

  testWidgets('Pomodoro counts down, pauses and resets', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    await tester.tap(find.byIcon(AppTab.study.icon));
    await tester.pumpAndSettle();

    // START opens Focus Mode with a growing circle.
    await tester.tap(find.text('START'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(FocusScreen), findsOneWidget);
    expect(find.text('25:00'), findsNothing);
    expect(PomodoroController.instance.running, isTrue);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Resume'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    expect(PomodoroController.instance.running, isTrue);

    // Closing Focus Mode (✕) pauses the timer and returns to Study.
    await tester.tap(find.byTooltip('Close Focus Mode'));
    await tester.pump(); // starts the closing animation
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FocusScreen), findsNothing);
    expect(PomodoroController.instance.running, isFalse);
    expect(find.text('RESUME'), findsOneWidget);

    // Reset asks first, since the Pomodoro would start over.
    await tester.tap(find.byTooltip('Reset Timer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reset This Pomodoro?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
  });

  testWidgets('Adding a task from the Study tab', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    await tester.tap(find.byIcon(AppTab.study.icon));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Task'));
    await tester.pumpAndSettle();
    // The first field is the task name (the second is the Pomodoro count).
    await tester.enterText(find.byType(TextField).first, 'Read Chapter 4');
    await tester.pump();
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();

    expect(find.text('Read Chapter 4'), findsWidgets);
    expect(AppStore.instance.currentTask?.title, 'Read Chapter 4');
  });

  testWidgets('Dashboard greets by name and opens the Plus plans',
      (tester) async {
    usePhoneSize(tester);
    final store = AppStore.instance;
    store.updatePrefs(store.prefs.copyWith(userName: 'Budi'));
    await tester.pumpWidget(const StudyApp());

    expect(find.textContaining('Budi'), findsOneWidget);
    // Below the fold: finders skip list items outside the viewport, so look
    // offstage too, then scroll it into view before tapping.
    final plus = find.text('Try tAsikaso+ free', skipOffstage: false);
    await tester.ensureVisible(plus);
    await tester.pumpAndSettle();
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.byType(PlansScreen), findsOneWidget);
    // The trial button is below the plan comparison: scroll down to it.
    final trial = find.text('Start 7-Day Free Trial');
    await tester.scrollUntilVisible(
      trial,
      300,
      scrollable: find
          .descendant(
              of: find.byType(PlansScreen), matching: find.byType(Scrollable))
          .first,
    );
    expect(trial, findsOneWidget);
  });

  testWidgets('Dashboard search opens from the search button', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Bio');
    await tester.pump();
    expect(find.text("Today's Focus"), findsNothing);

    await tester.tap(find.byTooltip('Close Search'));
    await tester.pump();
    expect(find.text("Today's Focus"), findsOneWidget);
  });

  testWidgets('Start Focus on the Dashboard starts a Pomodoro', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());

    await tester.tap(find.text('Start Focus'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FocusScreen), findsOneWidget);
    expect(PomodoroController.instance.running, isTrue);

    PomodoroController.instance.pause(); // no timers left running
    await tester.pump();
  });

  testWidgets('Settings opens from Profile and changes apply', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const StudyApp());
    await tester.tap(find.byIcon(AppTab.profile.icon));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Daily Focus Goal'), findsOneWidget);

    // Minutes can be typed, not just stepped. The row is below the colors
    // and presets, and list items off screen aren't found, so scroll first.
    await tester.scrollUntilVisible(
      find.text('Focus'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final focusField = find.descendant(
      of: find.ancestor(of: find.text('Focus'), matching: find.byType(Row)).first,
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(focusField);
    await tester.pumpAndSettle();
    await tester.enterText(focusField, '37');
    await tester.pump();
    expect(AppStore.instance.settings.focusMinutes, 37);
    await tester.enterText(focusField, '999'); // out of range…
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(AppStore.instance.settings.focusMinutes,
        PomodoroSettings.focusRange.$2); // …is capped

    expect(AppStore.instance.prefs.keepScreenOn, isTrue);
    await tester.ensureVisible(find.text('Keep Screen On'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Screen On'));
    await tester.pump();
    expect(AppStore.instance.prefs.keepScreenOn, isFalse);
  });

  testWidgets('Dark mode follows the Appearance setting', (tester) async {
    usePhoneSize(tester);
    final store = AppStore.instance;
    await tester.pumpWidget(const StudyApp());
    expect(AppColors.isDark, isFalse);

    // Dark, from Settings.
    await tester.tap(find.byIcon(AppTab.profile.icon));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(store.prefs.appearance, Appearance.dark);
    expect(AppColors.isDark, isTrue);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.dark);

    // System follows the phone.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isFalse);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
  });

  testWidgets('Color themes need tAsikaso+', (tester) async {
    usePhoneSize(tester);
    final store = AppStore.instance;
    await tester.pumpWidget(const StudyApp());

    // Without Plus a chosen theme stays locked to the default.
    store.updatePrefs(store.prefs.copyWith(palette: 'plum'));
    await tester.pumpAndSettle();
    expect(store.palette, Palette.navy);
    expect(AppColors.palette, Palette.navy);

    // With Plus it applies straight away.
    store.updatePrefs(store.prefs.copyWith(plus: true));
    await tester.pumpAndSettle();
    expect(store.palette, Palette.plum);
    expect(AppColors.palette, Palette.plum);
    expect(AppColors.primary, Color(Palette.plum.fill));
  });

  testWidgets('Pomodoro Analysis shows the week', (tester) async {
    usePhoneSize(tester);
    AppStore.instance.recordFocusSession(25);
    await tester.pumpWidget(const StudyApp());
    await tester.tap(find.byIcon(AppTab.study.icon));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Analysis'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisScreen), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('25m'), findsWidgets);
    expect(find.text('Productive Hours'), findsOneWidget);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('This Month'), findsOneWidget);
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('This Year'), findsOneWidget);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text(AppStore.instance.sessions.single.taskTitle!),
        findsOneWidget);
  });

  group('Suggested cards', () {
    test('finds definitions, questions and Q/A pairs', () {
      final cards = suggestCards('''
Cell Biology
- Mitochondria - the powerhouse of the cell
Ribosome: makes proteins
What is osmosis?
movement of water across a membrane
Q: Largest organ?
A: The skin
Meeting at 10:30 today
''');
      final byFront = {for (final c in cards) c.front: c.back};
      expect(byFront['Mitochondria'], 'the powerhouse of the cell');
      expect(byFront['Ribosome'], 'makes proteins');
      expect(byFront['What is osmosis?'], 'movement of water across a membrane');
      expect(byFront['Largest organ?'], 'The skin');
      expect(cards.length, 4);
    });

    test('ignores empty text', () {
      expect(suggestCards(''), isEmpty);
    });
  });

  group('AppStore', () {
    test('a finished Pomodoro counts for today and the current task', () {
      final store = AppStore.instance;
      final task = store.currentTask!;
      store.recordFocusSession(25);

      expect(store.focusMinutesToday, 25);
      expect(store.streakDays, 1);
      final updated = store.activeTasks.firstWhere((t) => t.id == task.id);
      expect(updated.pomodorosDone, task.pomodorosDone + 1);
      expect(updated.focusMinutes, task.focusMinutes + 25);
    });

    test('data survives saving and loading again', () async {
      final storage = MemoryStorage();
      final store = AppStore.instance;
      await store.init(storage);

      final folder = store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.addSet(
        title: 'Acids and Bases',
        folderId: folder.id,
        cards: const [Flashcard(id: 'c1', front: 'pH of pure water?', back: '7')],
      );
      store.recordCardsReviewed(3);
      await store.pendingSaves; // let the saves finish

      store.resetForTesting();
      expect(store.folders.any((f) => f.name == 'Chemistry'), isFalse);

      await store.init(storage);
      expect(store.folders.any((f) => f.name == 'Chemistry'), isTrue);
      expect(store.sets.single.cards.single.back, '7');
      expect(store.cardsReviewedToday, 3);
    });

    test('finished Pomodoros are kept for the analysis', () {
      final store = AppStore.instance;
      final task = store.currentTask!;
      store.recordFocusSession(25);
      store.recordFocusSession(25);

      expect(store.sessions, hasLength(2));
      expect(store.sessions.first.taskTitle, task.title);
      expect(store.activeOn(DateTime.now()), isTrue);
      expect(store.longestStreak, 1);
    });

    test('recently studied sets come first', () async {
      final store = AppStore.instance;
      final folder = store.addFolder('Bio', 0xFFA9CFF5);
      const card = Flashcard(id: 'c', front: 'Q', back: 'A');
      final older = await store.addSet(
          title: 'Older', folderId: folder.id, cards: const [card]);
      final newer = await store.addSet(
          title: 'Newer', folderId: folder.id, cards: const [card]);
      expect(store.recentSets(5).map((s) => s.id),
          containsAll([older.id, newer.id])); // none studied yet

      store.markSetStudied(older.id, known: 1, seen: 1);
      final recent = store.recentSets(5);
      expect(recent.first.id, older.id);
      expect(recent.first.lastKnown, 1);
      expect(recent.first.lastStudiedAt, isNotNull);
    });

    test('Delete All Data leaves nothing behind', () async {
      final store = AppStore.instance;
      store.addFolder('Chemistry', 0xFFA9CFF5);
      store.updatePrefs(store.prefs.copyWith(userName: 'Budi'));
      await store.eraseEverything();

      expect(store.folders, isEmpty);
      expect(store.activeTasks, isEmpty);
      expect(store.prefs.userName, isEmpty);
    });

    test('choosing a task moves it to the top', () {
      final store = AppStore.instance;
      final last = store.activeTasks.last;
      store.selectTask(last.id);
      expect(store.activeTasks.first.id, last.id);
      expect(store.currentTask?.id, last.id);
    });

    test('the current task is listed first even after loading', () async {
      final store = AppStore.instance;
      final storage = MemoryStorage();
      await store.init(storage);
      final picked = store.activeTasks.last;
      store.selectTask(picked.id);
      await store.pendingSaves;

      // An older save kept the chosen task at the bottom of the list.
      final saved = jsonDecode((await storage.readJson())!) as Map<String, Object?>;
      final tasks = (saved['tasks'] as List<Object?>).toList();
      tasks.add(tasks.removeAt(0));
      saved['tasks'] = tasks;
      await storage.writeJson(jsonEncode(saved));

      await store.init(storage);
      expect(store.currentTask?.id, picked.id);
      expect(store.activeTasks.first.id, picked.id);

      // Finishing the current task hands "current" to the next one on top.
      store.updateTask(store.currentTask!.copyWith(done: true));
      expect(store.activeTasks.first.id, store.currentTask!.id);
    });

    test('deleting a task can be undone', () {
      final store = AppStore.instance;
      final task = store.currentTask!;
      final removed = store.deleteTask(task.id)!;
      expect(store.activeTasks.any((t) => t.id == task.id), isFalse);
      store.restoreTask(removed);
      expect(store.currentTask?.id, task.id);
    });

    test('Pomodoro presets, custom lengths and reset', () {
      const base = PomodoroSettings();
      expect(base.preset, PomodoroPreset.classic);

      final deep = base.withPreset(PomodoroPreset.deepWork);
      expect(deep.focusMinutes, 50);
      expect(deep.preset, PomodoroPreset.deepWork);

      final custom = deep.copyWith(
        focusMinutes: 40,
        custom: const PomodoroPreset('Custom', 40, 10, 30),
      );
      expect(custom.preset, isNull);
      final loaded = PomodoroSettings.fromJson(custom.toJson());
      expect(loaded.custom?.summary, '40 – 10 – 30');

      final reset = loaded.copyWith(dailyGoalMinutes: 90).reset();
      expect(reset.preset, PomodoroPreset.classic);
      expect(reset.dailyGoalMinutes, 90); // the goal is kept
      expect(reset.custom?.focus, 40); // and so are your own lengths
    });

    test('a custom color is built from one hue', () {
      final c = ThemeColors.fromHue(330);
      expect(c, ThemeColors.fromHue(330));
      expect(c == ThemeColors.fromHue(200), isFalse);
      final store = AppStore.instance;
      store.updatePrefs(
          store.prefs.copyWith(palette: 'custom', customHue: 330, plus: true));
      expect(store.palette, Palette.custom);
      expect(store.themeColors, c);
    });

    test('breaks are recorded for the focus / break split', () {
      final store = AppStore.instance;
      store.recordBreak(5, long: false);
      store.recordBreak(15, long: true);
      store.recordBreak(0, long: false); // ignored
      expect(store.breaks, hasLength(2));
      expect(store.breaks.last.long, isTrue);
    });

    test('deleting a folder removes its notes and sets', () async {
      final store = AppStore.instance;
      final folder = store.addFolder('Temp', 0xFFA9CFF5);
      await store.addSet(title: 'Deck', folderId: folder.id);
      expect(store.setCountIn(folder.id), 1);

      await store.deleteFolder(folder.id);
      expect(store.folder(folder.id), isNull);
      expect(store.sets, isEmpty);
    });
  });

  group('Saved data is never lost', () {
    test('unreadable records are left out, not everything', () async {
      final store = AppStore.instance;
      final storage = MemoryStorage();
      final raw = jsonEncode({
        'version': 1,
        'folders': [
          {'id': 'f1', 'name': 'Chemistry', 'color': 0xFFA9CFF5},
          {'name': 'No id, so unreadable'},
        ],
      });
      await storage.writeJson(raw);
      final now = DateTime(2026, 1, 2);
      await withClock(Clock.fixed(now), () => store.init(storage));

      expect(store.folders.single.name, 'Chemistry');
      expect(store.problem.value?.title, "Some Data Couldn't Be Loaded");
      expect(store.problem.value?.message, startsWith('1 item'));
      // The whole file was kept before anything was left out.
      final copy = await storage
          .readBytes('recovery/${now.millisecondsSinceEpoch}.json');
      expect(utf8.decode(copy!), raw);
    });

    test('a file that can\'t be read is kept, not replaced by samples',
        () async {
      final store = AppStore.instance;
      final storage = MemoryStorage();
      await storage.writeJson('{"folders": [');
      final now = DateTime(2026, 1, 2);
      await withClock(Clock.fixed(now), () => store.init(storage));

      expect(store.folders, isEmpty); // no sample folders
      expect(store.activeTasks, isEmpty);
      expect(store.problem.value?.title, "Saved Data Couldn't Be Read");
      final copy = await storage
          .readBytes('recovery/${now.millisecondsSinceEpoch}.json');
      expect(utf8.decode(copy!), '{"folders": [');
    });

    test('the last copy that worked is brought back', () async {
      final store = AppStore.instance;
      final storage = MemoryStorage();
      await store.init(storage); // first launch
      store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.pendingSaves;
      await store.init(storage); // next launch keeps a good copy

      await storage.writeJson('garbage'); // the save file breaks
      store.resetForTesting();
      await store.init(storage);

      expect(store.folders.any((f) => f.name == 'Chemistry'), isTrue);
      expect(store.problem.value?.title, 'Data Restored');
      await store.pendingSaves; // the restored data is saved again
      expect(await storage.readJson(), contains('Chemistry'));

      // Delete All Data removes the copies too.
      await store.eraseEverything();
      expect(await storage.readBytes('backup/data.json'), isNull);
    });

    test('data from a newer app version is left alone', () async {
      final store = AppStore.instance;
      final storage = _PersistentMemoryStorage();
      const raw = '{"version": 99, "folders": []}';
      await storage.writeJson(raw);
      await store.init(storage);

      expect(store.problem.value?.title, 'Update tAsikaso');
      expect(store.isPersistent, isFalse);
      store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.pendingSaves;
      expect(await storage.readJson(), raw);
    });

    test('a failed save is reported, once until saving works again',
        () async {
      final store = AppStore.instance;
      final storage = _FailingStorage();
      await store.init(storage); // first launch saves, and fails
      await store.pendingSaves;
      expect(store.problem.value?.title, "Couldn't Save");

      store.problem.value = null;
      store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.pendingSaves;
      expect(store.problem.value, isNull); // already told

      storage.failing = false;
      store.addFolder('Biology', 0xFFA9CFF5);
      await store.pendingSaves;
      expect(await storage.readJson(), contains('Chemistry'));

      storage.failing = true;
      store.addFolder('Physics', 0xFFA9CFF5);
      await store.pendingSaves;
      expect(store.problem.value?.title, "Couldn't Save");
    });
  });

  group('Pomodoro timer', () {
    test('a running Pomodoro carries on after the app is closed', () async {
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      final storage = MemoryStorage();
      await store.init(storage);
      final start = DateTime(2026, 3, 9, 9);
      withClock(Clock.fixed(start), timer.start);
      await store.pendingSaves;

      // The phone closes the app, which is opened again 10 minutes later.
      timer.resetForTesting();
      store.resetForTesting();
      await store.init(storage);
      withClock(Clock.fixed(start.add(const Duration(minutes: 10))),
          timer.restore);

      expect(timer.running, isTrue);
      expect(timer.remaining, 15 * 60);
      timer.pause();
    });

    test('a Pomodoro that ended while closed counts on the day it ended',
        () async {
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      final storage = MemoryStorage();
      await store.init(storage);
      final task = store.currentTask!;
      withClock(Clock.fixed(DateTime(2026, 3, 9, 23)), timer.start);
      await store.pendingSaves;

      // Opened again after midnight.
      timer.resetForTesting();
      store.resetForTesting();
      await store.init(storage);
      withClock(Clock.fixed(DateTime(2026, 3, 10, 0, 40)), timer.restore);

      expect(store.sessions.single.endedAt, DateTime(2026, 3, 9, 23, 25));
      expect(store.focusMinutesOn(DateTime(2026, 3, 9)), 25);
      expect(store.focusMinutesOn(DateTime(2026, 3, 10)), 0);
      expect(store.task(task.id)!.pomodorosDone, task.pomodorosDone + 1);
      expect(timer.mode, TimerMode.shortBreak);
      expect(timer.running, isFalse); // the break waits for START
      expect(timer.takePendingMessage(), contains('while tAsikaso was closed'));
    });

    testWidgets('a Pomodoro counts for the task it was started on',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      final first = store.currentTask!;
      await tester.pumpWidget(const StudyApp());

      timer.start();
      await tester.pump();
      // A new task becomes current halfway through (as "Add Task" does).
      final other = store.addTask('Read Chapter 4', 2);
      store.selectTask(other.id);
      await tester.pump();
      expect(find.textContaining('still counts for "${first.title}"'),
          findsOneWidget);
      expect(timer.taskTitle, first.title);

      await tester.pump(const Duration(minutes: 25));
      await tester.pump();
      expect(store.sessions.single.taskId, first.id);
      expect(store.task(first.id)!.pomodorosDone, first.pomodorosDone + 1);
      expect(store.task(other.id)!.pomodorosDone, 0);
    });

    testWidgets('switching mode or skipping asks before losing a Pomodoro',
        (tester) async {
      usePhoneSize(tester);
      final timer = PomodoroController.instance;
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.study.icon));
      await tester.pumpAndSettle();
      timer.start();
      await tester.pump(const Duration(seconds: 3));

      // The mode that's already on: nothing happens.
      await tester.tap(find.text('Pomodoro'));
      await tester.pump();
      expect(timer.running, isTrue);
      expect(timer.remaining, lessThan(25 * 60));

      // Another mode asks first; Cancel keeps the Pomodoro.
      await tester.tap(find.text('Short Break'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Switch to Short Break?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(timer.mode, TimerMode.pomodoro);
      expect(timer.running, isTrue);

      // Skip asks too.
      await tester.tap(find.byTooltip('Skip to Break'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Skip This Pomodoro?'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(timer.mode, TimerMode.shortBreak);
      expect(AppStore.instance.sessions, isEmpty);
    });
  });

  group('Phase 1 fixes', () {
    Finder settingsScrollable() => find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    testWidgets('typing a length keeps the saved Custom rhythm',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.profile.icon));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Focus'), 200,
          scrollable: settingsScrollable());
      await tester.pumpAndSettle();
      final focusField = find.descendant(
        of: find.ancestor(of: find.text('Focus'), matching: find.byType(Row)).first,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(focusField);
      await tester.pumpAndSettle();

      // "40", one key at a time, then Done.
      await tester.enterText(focusField, '4');
      await tester.enterText(focusField, '40');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(store.settings.custom?.focus, 40);

      // "25" passes through "2" on the way, and lands on Classic. The
      // custom rhythm must still be 40.
      await tester.enterText(focusField, '2');
      await tester.enterText(focusField, '25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(store.settings.preset, PomodoroPreset.classic);
      expect(store.settings.custom?.focus, 40);

      // The Custom card is above the lengths (and may not be built yet).
      await tester.scrollUntilVisible(find.text('40 – 5 – 15'), -200,
          scrollable: settingsScrollable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('40 – 5 – 15'));
      await tester.pump();
      expect(store.settings.focusMinutes, 40);
    });

    testWidgets('the Plus strip can be hidden and is not shown to members',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      await tester.pumpWidget(const StudyApp());
      final dashboard = find
          .descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(find.text('Try tAsikaso+ free'), 200,
          scrollable: dashboard);
      await tester.pumpAndSettle();
      expect(find.text('Try tAsikaso+ free'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide'));
      await tester.pump();
      expect(find.text('Try tAsikaso+ free'), findsNothing);
      expect(store.prefs.hidePlusBanner, isTrue);

      // Members never see it, hidden or not.
      store.updatePrefs(store.prefs.copyWith(hidePlusBanner: false, plus: true));
      await tester.pump();
      expect(find.text('Try tAsikaso+ free'), findsNothing);
    });

    testWidgets('Start Focus during a paused break starts a Pomodoro',
        (tester) async {
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      await tester.pumpWidget(const StudyApp());
      timer.selectMode(TimerMode.shortBreak);
      timer.start();
      await tester.pump(const Duration(minutes: 2));
      timer.pause();
      expect(timer.mode, TimerMode.shortBreak);

      timer.startFocus();
      expect(timer.mode, TimerMode.pomodoro);
      expect(timer.running, isTrue);
      // The two minutes of break taken still count.
      expect(store.breaks.single.minutes, 2);
      timer.pause();
    });

    test('Delete All Data also clears a save file that could not be read',
        () async {
      final store = AppStore.instance;
      final storage = _PersistentMemoryStorage();
      await storage.writeJson('{"version": 99, "folders": []}');
      await storage.writeBytes('notes/old.pdf', Uint8List.fromList([1, 2, 3]));
      await store.init(storage);
      expect(store.isPersistent, isFalse); // saving is paused

      expect(await store.eraseEverything(), isTrue);
      expect(await storage.readBytes('notes/old.pdf'), isNull);
      // A clean slate: saving works again.
      expect(store.isPersistent, isTrue);
      store.addFolder('Chemistry', 0xFFA9CFF5);
      await store.pendingSaves;
      expect(await storage.readJson(), contains('Chemistry'));
    });

    test('saved PDFs still open while saving is paused', () async {
      final store = AppStore.instance;
      final storage = _PersistentMemoryStorage();
      final pdf = Uint8List.fromList([37, 80, 68, 70]);
      await storage.writeJson('{"version": 99}');
      await storage.writeBytes('notes/n1.pdf', pdf);
      await store.init(storage);
      expect(store.isPersistent, isFalse);

      final note = Note(
          id: 'n1', title: 'Notes', folderId: 'f', createdAt: DateTime(2026));
      expect(await store.readPdf(note), pdf);
    });

    testWidgets('editing a task keeps a Pomodoro finished meanwhile',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final task = store.currentTask!;
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.study.icon));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Task'));
      await tester.pumpAndSettle();

      // A Pomodoro finishes for this task while the sheet is open.
      store.recordFocusSession(25, taskId: task.id);
      await tester.enterText(
          find.byType(TextField).first, 'Do More Certifications');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = store.task(task.id)!;
      expect(saved.title, 'Do More Certifications');
      expect(saved.pomodorosDone, task.pomodorosDone + 1);
    });

    testWidgets('when the scanner cannot open, the camera opens instead',
        (tester) async {
      usePhoneSize(tester);
      final original = CaptureScreen.loadCameras;
      CaptureScreen.loadCameras = () async => [];
      ScanService.debugScannerAvailable = true;
      ScanService.debugScan = () async => throw Exception('No Play services');
      addTearDown(() {
        CaptureScreen.loadCameras = original;
        ScanService.debugScannerAvailable = null;
        ScanService.debugScan = null;
      });

      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byType(CameraButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('camera opened instead'), findsOneWidget);
      expect(find.text('Import Photos'), findsOneWidget);
    });

    test('a scanned page that cannot be read is left out, not the whole scan',
        () async {
      final good = img.encodePng(img.Image(width: 4, height: 4));
      final bad = Uint8List.fromList([1, 2, 3]);
      final (pages, failed) = await preparePages([bad, good, bad], 5);
      expect(pages.length, 1);
      expect(pages.single.id, 5);
      expect(failed, 2);
    });

    testWidgets('a photo that cannot be opened does not stop the import',
        (tester) async {
      usePhoneSize(tester);
      final originalCameras = CaptureScreen.loadCameras;
      final originalPick = CaptureScreen.pickImages;
      CaptureScreen.loadCameras = () async => [];
      final good = img.encodePng(img.Image(width: 4, height: 4));
      CaptureScreen.pickImages = () async => [
            XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'bad.jpg'),
            XFile.fromData(good, name: 'good.png'),
          ];
      addTearDown(() {
        CaptureScreen.loadCameras = originalCameras;
        CaptureScreen.pickImages = originalPick;
      });

      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byType(CameraButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await tester.tap(find.text('Import Photos'));
        // Decoding runs in another isolate, so give it real time.
        for (var i = 0;
            i < 100 && find.byType(ReviewScreen).evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text("1 photo couldn't be opened."), findsOneWidget);
    });

    testWidgets('Notifications & Reminders opens Settings at that section',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.profile.icon));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications & Reminders'));
      await tester.pumpAndSettle();
      expect(find.text('Timer Alerts').hitTestable(), findsOneWidget);
    });

    testWidgets('a name can be cleared again', (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      store.updatePrefs(store.prefs.copyWith(userName: 'Kristine'));
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.profile.icon));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kristine'));
      await tester.pumpAndSettle();
      final field = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(field, findsOneWidget);
      await tester.enterText(field, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.prefs.userName, '');
      expect(find.text('Add Your Name'), findsOneWidget);
    });

    test('the estimate never reads as less than what was done', () {
      final task = StudyTask(
        id: 't',
        title: 'Read',
        pomodorosTotal: 8,
        createdAt: DateTime(2026),
        pomodorosDone: 5,
        focusMinutes: 101,
      );
      expect(task.estimatedMinutes(25), 200);
      expect(task.estimatedMinutes(1), 101); // not "101 / 8"
    });
  });

  group('Phase 2 fixes', () {
    testWidgets('the long-break rhythm starts over after a long pause',
        (tester) async {
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      store.updateSettings(store.settings.copyWith(focusMinutes: 1));
      await tester.pumpWidget(const StudyApp());

      timer.start();
      await tester.pump(const Duration(seconds: 61));
      expect(timer.session, 2); // one Pomodoro done, break waiting

      // Back the same evening: still the same sitting.
      await tester.pump(const Duration(minutes: 30));
      timer.selectMode(TimerMode.pomodoro);
      timer.start();
      expect(timer.session, 2);
      timer.pause();

      // The next morning: a fresh sitting.
      await tester.pump(const Duration(hours: 10));
      timer.reset();
      timer.start();
      expect(timer.session, 1);
      timer.pause();
    });

    testWidgets('a break cut short by Reset still counts for the time taken',
        (tester) async {
      final store = AppStore.instance;
      final timer = PomodoroController.instance;
      await tester.pumpWidget(const StudyApp());
      timer.selectMode(TimerMode.shortBreak);
      timer.start();
      await tester.pump(const Duration(minutes: 2));

      timer.reset();
      expect(store.breaks.single.minutes, 2);
      expect(timer.mode, TimerMode.shortBreak);
      expect(timer.atStart, isTrue);

      // The same when switching mode part-way through a break.
      timer.start();
      await tester.pump(const Duration(minutes: 1));
      timer.selectMode(TimerMode.pomodoro);
      expect(store.breaks.length, 2);
      expect(store.breaks.last.minutes, 1);
    });

    test('the timer remembers when its last phase ended', () {
      final end = DateTime(2026, 3, 9, 9, 25);
      final json = const TimerSnapshot(
        mode: TimerMode.shortBreak,
        phaseSeconds: 300,
        remainingSeconds: 300,
        completed: 1,
      ).toJson();
      expect(json.containsKey('lastEnd'), isFalse);
      final back = TimerSnapshot.fromJson(TimerSnapshot(
        mode: TimerMode.shortBreak,
        phaseSeconds: 300,
        remainingSeconds: 300,
        completed: 1,
        lastPhaseEnd: end,
      ).toJson());
      expect(back.lastPhaseEnd, end);
    });

    test('crop corners cannot cross each other', () {
      final corners = [
        const Offset(0, 0),
        const Offset(0.5, 0),
        const Offset(0.5, 1),
        const Offset(0, 1),
      ];
      // Top-left dragged past top-right stops short of it.
      final tl = CapturedPage.constrainCorner(corners, 0, const Offset(0.8, 0));
      expect(tl.dx, closeTo(0.5 - CapturedPage.minCropGap, 1e-9));
      // Bottom-right dragged above top-right stays below it.
      final br = CapturedPage.constrainCorner(corners, 2, const Offset(0.5, -0.2));
      expect(br.dy, closeTo(CapturedPage.minCropGap, 1e-9));
      // Ordinary moves inside the page are left alone.
      final bl = CapturedPage.constrainCorner(corners, 3, const Offset(0.1, 0.9));
      expect(bl, const Offset(0.1, 0.9));
    });

    testWidgets('Focus by Task keeps a renamed task as one row',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final task = store.currentTask!;
      store.recordFocusSession(10, taskId: task.id, taskTitle: task.title);
      store.updateTask(task.copyWith(title: 'Certifications, Renamed'));
      store.recordFocusSession(5, taskId: task.id, taskTitle: 'Certifications, Renamed');

      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.text('This Week'));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Focus by Task'), 300,
          scrollable: find
              .descendant(
                of: find.byType(AnalysisScreen),
                matching: find.byType(Scrollable),
              )
              .first);
      await tester.pumpAndSettle();
      expect(find.text('Certifications, Renamed'), findsOneWidget);
      expect(find.text(task.title), findsNothing);
      expect(find.text('15m'), findsWidgets);
    });

    testWidgets('a folder can be deleted from its edit sheet', (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.library.icon));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Biology'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Folder'), findsOneWidget);
      await tester.tap(find.text('Delete Folder'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Biology"?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.folders.any((f) => f.name == 'Biology'), isFalse);
      expect(find.text('Folders (4)'), findsOneWidget);
    });

    testWidgets('the flashcard score is for a whole round, counted once',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final folder = store.folders.first;
      final deck = await store.addSet(
        title: 'Bonds',
        folderId: folder.id,
        cards: const [
          Flashcard(id: 'c1', front: 'Ionic', back: 'Transfer'),
          Flashcard(id: 'c2', front: 'Covalent', back: 'Share'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: StudyCardsScreen(setId: deck.id)));

      await tester.tap(find.text('Show Answer'));
      await tester.pump();
      await tester.tap(find.text('Got It'));
      await tester.pump();
      // One card in: counted as reviewed, but no score yet.
      expect(store.cardsReviewedToday, 1);
      expect(store.setById(deck.id)!.lastStudiedAt, isNull);

      await tester.tap(find.text('Show Answer'));
      await tester.pump();
      await tester.tap(find.text('Got It'));
      await tester.pump();
      expect(find.text('Set complete!'), findsOneWidget);
      expect(store.setById(deck.id)!.lastKnown, 2);
      expect(store.setById(deck.id)!.lastSeen, 2);

      // Another round doesn't count the same cards as reviewed again.
      await tester.tap(find.text('Study Again (Shuffled)'));
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Show Answer'));
        await tester.pump();
        await tester.tap(find.text('Again'));
        await tester.pump();
      }
      expect(store.cardsReviewedToday, 2);
    });
  });

  group('Phase 3: saving on web', () {
    test('IndexedDB storage keeps files and the JSON document', () async {
      final storage = IdbStorage(newIdbFactoryMemory());
      expect(storage.isPersistent, isTrue);
      expect(await storage.readJson(), isNull);

      await storage.writeJson('{"version": 1}');
      await storage.writeBytes('notes/a.pdf', Uint8List.fromList([1, 2]));
      await storage.writeBytes('notes/a.jpg', Uint8List.fromList([3]));
      await storage.writeBytes('sets/s/0.jpg', Uint8List.fromList([4]));

      expect(await storage.readJson(), '{"version": 1}');
      expect(await storage.readBytes('notes/a.pdf'), [1, 2]);
      expect((await storage.list('notes/'))..sort(), ['notes/a.jpg', 'notes/a.pdf']);
      expect(await storage.list(''), isNot(contains('data.json')));

      await storage.delete('notes/a.jpg');
      expect(await storage.readBytes('notes/a.jpg'), isNull);
      await storage.deletePrefix('sets/');
      expect(await storage.list('sets/'), isEmpty);
      expect(await storage.readBytes('notes/a.pdf'), [1, 2]);
    });
  });

  group('Phase 3: smart review', () {
    test('a known card comes back later and later, a missed one tomorrow', () {
      expect(nextInterval(0, knewIt: true), 1);
      expect(nextInterval(1, knewIt: true), 3);
      expect(nextInterval(3, knewIt: true), 7);
      expect(nextInterval(180, knewIt: true), 180);
      expect(nextInterval(30, knewIt: false), 1);
    });

    test('cards are due on their day, and new cards are always due', () {
      final today = DateTime(2026, 10, 20);
      const fresh = Flashcard(id: 'a', front: 'f', back: 'b');
      expect(fresh.isDue(today), isTrue);
      final later = fresh.scheduled(interval: 3, due: DateTime(2026, 10, 23));
      expect(later.isDue(today), isFalse);
      expect(later.isDue(DateTime(2026, 10, 23)), isTrue);
      // The schedule survives saving.
      final back = Flashcard.fromJson(later.toJson());
      expect(back.interval, 3);
      expect(back.due, DateTime(2026, 10, 23));
    });

    test('answering schedules the card and the set counts what is due',
        () async {
      final store = AppStore.instance;
      final folder = store.folders.first;
      final deck = await store.addSet(
        title: 'Bonds',
        folderId: folder.id,
        cards: const [
          Flashcard(id: 'c1', front: 'Ionic', back: 'Transfer'),
          Flashcard(id: 'c2', front: 'Covalent', back: 'Share'),
        ],
      );
      final now = DateTime(2026, 10, 20, 9);
      withClock(Clock.fixed(now), () {
        store.scheduleCard(deck.id, 'c1', knewIt: true);
        store.scheduleCard(deck.id, 'c2', knewIt: false);
        final updated = store.setById(deck.id)!;
        expect(updated.cards[0].due, DateTime(2026, 10, 21));
        expect(updated.cards[1].due, DateTime(2026, 10, 21));
        expect(store.dueCards(updated), isEmpty);
      });
      withClock(Clock.fixed(DateTime(2026, 10, 21, 8)), () {
        expect(store.dueCards(store.setById(deck.id)!).length, 2);
      });
    });

    testWidgets('a set offers to review just the cards that are due',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final folder = store.folders.first;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final deck = await store.addSet(
        title: 'Bonds',
        folderId: folder.id,
        cards: [
          const Flashcard(id: 'c1', front: 'Ionic', back: 'Transfer'),
          const Flashcard(id: 'c2', front: 'Covalent', back: 'Share')
              .scheduled(interval: 3, due: tomorrow),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.pump();
      expect(find.text('Review 1 Card Due'), findsOneWidget);
      expect(find.text('Study all 2 cards'), findsOneWidget);

      await tester.tap(find.text('Review 1 Card Due'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 seen'), findsOneWidget);
      expect(find.text('Ionic'), findsOneWidget);
    });
  });

  group('Phase 3: backup & restore', () {
    test('a backup file holds the data and every file, and reads back',
        () {
      final zip = packBackup(
        json: '{"version": 1, "folders": []}',
        files: {
          'notes/a.pdf': Uint8List.fromList([1, 2, 3]),
          'sets/s/0.jpg': Uint8List.fromList([4]),
          'backup/data.json': Uint8List.fromList([9]), // never included
        },
        createdAt: DateTime(2026, 10, 20),
        appVersion: '0.1.0',
      );
      final back = unpackBackup(zip);
      expect(back.json, '{"version": 1, "folders": []}');
      expect(back.files.keys.toList()..sort(), ['notes/a.pdf', 'sets/s/0.jpg']);
      expect(back.files['notes/a.pdf'], [1, 2, 3]);
      expect(backupFileName(DateTime(2026, 10, 5)),
          'tAsikaso-backup-2026-10-05.zip');
    });

    test('something that is not a backup is refused', () {
      expect(() => unpackBackup(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });

    test('everything comes back after a restore, even on a fresh device',
        () async {
      final store = AppStore.instance;
      final storage = MemoryStorage();
      await store.init(storage);
      final folder = store.addFolder('Chemistry', 0xFFA9CFF5);
      final pdf = Uint8List.fromList([37, 80, 68, 70]);
      final note = await store.addNote(
        title: 'Bonds',
        folderId: folder.id,
        pdf: pdf,
        thumbnail: Uint8List.fromList([1]),
        pageCount: 1,
      );
      store.addTask('Read Chapter 4', 2);
      final zip = await store.createBackup();

      // A new phone: nothing but the sample data.
      store.resetForTesting();
      final fresh = MemoryStorage();
      await store.init(fresh);
      expect(store.notes, isEmpty);

      await store.restoreBackup(zip);
      expect(store.folders.any((f) => f.name == 'Chemistry'), isTrue);
      expect(store.notes.single.title, 'Bonds');
      expect(await store.readPdf(note), pdf);
      expect(store.thumbnail(note.id), [1]);
      expect(store.activeTasks.any((t) => t.title == 'Read Chapter 4'), isTrue);
      await store.pendingSaves;
      expect(await fresh.readJson(), contains('Chemistry'));
    });

    test('a backup from a newer version is refused and nothing changes',
        () async {
      final store = AppStore.instance;
      await store.init(MemoryStorage());
      store.addFolder('Chemistry', 0xFFA9CFF5);
      final zip = packBackup(
        json: '{"version": 99}',
        files: const {},
        createdAt: DateTime(2026),
        appVersion: '9.0.0',
      );
      await expectLater(store.restoreBackup(zip), throwsFormatException);
      expect(store.folders.any((f) => f.name == 'Chemistry'), isTrue);
    });

    testWidgets('Back Up Now hands over a file; Restore brings it back',
        (tester) async {
      usePhoneSize(tester);
      final store = AppStore.instance;
      final originalShare = BackupScreen.share;
      final originalPick = BackupScreen.pickFile;
      Uint8List? shared;
      BackupScreen.share = (bytes, name) async {
        shared = bytes;
        expect(name, endsWith('.zip'));
        return true;
      };
      BackupScreen.pickFile = () async => shared;
      addTearDown(() {
        BackupScreen.share = originalShare;
        BackupScreen.pickFile = originalPick;
      });

      store.addFolder('Chemistry', 0xFFA9CFF5);
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.profile.icon));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup & Sync'));
      await tester.pumpAndSettle();
      expect(find.text('Never'), findsOneWidget);

      await tester.tap(find.text('Back Up Now'));
      await tester.pumpAndSettle();
      expect(shared, isNotNull);
      expect(store.prefs.lastBackupAt, isNotNull);
      expect(find.text('Never'), findsNothing);

      // Lose everything, then restore it.
      await store.eraseEverything();
      await tester.pump();
      expect(store.folders, isEmpty);
      await tester.tap(find.text('Restore from Backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose File'));
      await tester.pumpAndSettle();
      expect(store.folders.any((f) => f.name == 'Chemistry'), isTrue);
      expect(find.text('Backup restored.'), findsOneWidget);
    });
  });
}

/// Memory storage that claims to be persistent, like a phone's.
class _PersistentMemoryStorage extends MemoryStorage {
  @override
  bool get isPersistent => true;
}

/// Storage whose saves fail while [failing] is true (e.g. a full disk).
class _FailingStorage extends MemoryStorage {
  bool failing = true;

  @override
  Future<void> writeJson(String json) async {
    if (failing) throw Exception('No space left on device');
    await super.writeJson(json);
  }
}
