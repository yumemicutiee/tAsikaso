import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/analysis_screen.dart';
import 'package:study_app/screens/capture/capture_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/screens/plans_screen.dart';
import 'package:study_app/screens/settings_screen.dart';
import 'package:study_app/services/screen_awake.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/utils/card_suggestions.dart';
import 'package:study_app/widgets/bottom_nav.dart';

void main() {
  // The timer controller watches the app lifecycle, so it needs a binding
  // even in plain unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScreenAwake.enabled = false;
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

    await tester.tap(find.byTooltip('Reset Timer'));
    await tester.pump();
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
    expect(find.text('Start 7-Day Free Trial'), findsOneWidget);
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
      expect(loaded.custom?.summary, '40 · 10 · 30');

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
}
