import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/profile_screen.dart';
import 'package:study_app/screens/welcome/welcome_screen.dart';
import 'package:study_app/services/account_data.dart';
import 'package:study_app/services/accounts.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/theme/app_colors.dart';

import 'accounts_test.dart' show FakeAccounts;

// The account keeps the profile, preferences, Pomodoro settings, tasks and
// statistics: saved as they change, cleared at Log Out, back on sign-in.

Uint8List photo() {
  final image = img.Image(width: 900, height: 900);
  img.fill(image, color: img.ColorRgb8(30, 120, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  late FakeAccounts accounts;

  // The app's own fonts, so text is as wide as on a phone (Log Out ends on
  // the welcome screen, whose wordmark is sized for them).
  setUpAll(() async {
    const fonts = {
      'Inter': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'PlusJakartaSans': ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'],
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
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/$file.ttf')))
          .load();
    }
  });

  setUp(() async {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    await DriveSync.instance.resetForTesting();
    DriveSync.debugStore = null;
    AccountData.instance.resetForTesting();
    accounts = FakeAccounts()
      ..userId = 'google-user'
      ..isAnonymous = false;
    Accounts.useForTesting(accounts);
  });

  tearDown(() {
    Accounts.useForTesting(null);
    AccountData.instance.resetForTesting();
    DriveSync.debugStore = null;
  });

  /// A student who has used the app: a task, Pomodoros on it, a break,
  /// cards reviewed, their own name, colours and Pomodoro length.
  StudyTask useTheApp() {
    final task = store.addTask('Bio reviewer', 4);
    store.selectTask(task.id);
    store.recordFocusSession(25, endedAt: DateTime(2026, 11, 20, 9));
    store.recordFocusSession(25, endedAt: DateTime(2026, 11, 21, 9));
    store.recordBreak(5, long: false, endedAt: DateTime(2026, 11, 21, 9, 5));
    store.recordCardsReviewed(12);
    store.updatePrefs(store.prefs.copyWith(
      userName: 'Kristine',
      palette: 'plum',
      appearance: Appearance.dark,
      timerAlerts: true,
      alarmSound: false,
      vibrateOnFinish: true,
      aiServerUrl: 'https://mine.test',
      aiToken: 'phone-token',
      installId: 'phone-install-id',
    ));
    store.updateSettings(store.settings.copyWith(focusMinutes: 30));
    return task;
  }

  group('What the account keeps', () {
    test('profile, preferences, Pomodoro settings, tasks and statistics; not '
        'study materials or what belongs to the phone', () {
      useTheApp();
      store.startPlan(PlusPlan.monthly);
      final j = store.accountDataToJson();
      expect(j.keys, containsAll(['prefs', 'settings', 'tasks', 'currentTask',
          'sessions', 'breaks', 'focusLog', 'reviewLog', 'suggestedLog']));
      expect(j.keys, isNot(contains('folders')));
      expect(j.keys, isNot(contains('notes')));
      expect(j.keys, isNot(contains('sets')));
      expect(j.keys, isNot(contains('timer')));
      final prefs = j['prefs']! as Map<String, Object?>;
      expect(prefs['name'], 'Kristine');
      expect(prefs['palette'], 'plum');
      expect(prefs['alarm'], false, reason: 'When Time Is Up goes along');
      expect(prefs.containsKey('aiToken'), isFalse);
      expect(prefs.containsKey('aiUrl'), isFalse);
      expect(prefs.containsKey('install'), isFalse);
      expect(prefs.containsKey('plan'), isFalse, reason: "the plan is the server's");
      expect((j['sessions']! as List), hasLength(2));
      expect((j['settings']! as Map)['focus'], isNotNull);
    });
  });

  group('Saving', () {
    test('saves the data and the photo (made small), and only again after a '
        'change', () async {
      useTheApp();
      await store.setProfilePhoto(photo());
      expect(await AccountData.instance.save(), isTrue);
      final row = accounts.rows['google-user']!;
      expect(((row['data']! as Map)['sessions'] as List), hasLength(2));
      final saved = img.decodeJpg(base64Decode(row['photo']! as String))!;
      expect(saved.width, 512, reason: 'at most 512 px for the account');
      expect(accounts.saves, 1);

      expect(await AccountData.instance.save(), isTrue);
      expect(accounts.saves, 1, reason: 'nothing changed, nothing sent');

      store.recordFocusSession(25, endedAt: DateTime(2026, 11, 22, 9));
      await AccountData.instance.save();
      expect(accounts.saves, 2);
      expect(((accounts.rows['google-user']!['data']! as Map)['sessions'] as List),
          hasLength(3));
    });

    test('saved by itself a moment after a change', () async {
      AccountData.delay = const Duration(milliseconds: 10);
      addTearDown(() => AccountData.delay = const Duration(seconds: 8));
      AccountData.instance.init();
      store.recordFocusSession(25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(accounts.saves, 1);
    });

    test('without an account nothing is sent', () async {
      accounts.userId = null;
      useTheApp();
      expect(await AccountData.instance.save(), isFalse);
      expect(accounts.saves, 0);
    });

    test('a failed save says so, and is tried again next time', () async {
      useTheApp();
      accounts.saveFails = true;
      expect(await AccountData.instance.save(), isFalse);
      accounts.saveFails = false;
      expect(await AccountData.instance.save(), isTrue);
      expect(accounts.saves, 1);
    });
  });

  group('Log out, then back in', () {
    test('everything personal clears, and comes back on signing in', () async {
      final task = useTheApp();
      await store.setProfilePhoto(photo());
      final folders = store.folders.length;
      final notes = store.notes.length;
      await AccountData.instance.save();

      // Log Out: cleared from the phone.
      await accounts.signOut();
      AccountData.instance.forget();
      await store.resetAccountData();
      expect(store.sessions, isEmpty);
      expect(store.breaks, isEmpty);
      expect(store.activeTasks, isEmpty);
      expect(store.focusMinutesOn(DateTime(2026, 11, 21)), 0);
      expect(store.cardsReviewedToday, 0);
      expect(store.prefs.userName, '');
      expect(store.prefs.palette, 'navy');
      expect(store.prefs.appearance, Appearance.system);
      expect(store.settings.focusMinutes, 25);
      expect(store.profilePhoto, isNull);
      expect(store.subscription, isNull);
      expect(store.folders, hasLength(folders), reason: 'study materials stay');
      expect(store.notes, hasLength(notes));
      expect(store.prefs.installId, 'phone-install-id', reason: "the phone's own");
      expect(store.prefs.aiServerUrl, 'https://mine.test');

      // Back in with Google: the same account's data comes back.
      accounts.userId = 'google-user';
      expect(await AccountData.instance.bringIn(), isTrue);
      expect(store.sessions, hasLength(2));
      expect(store.breaks, hasLength(1));
      final back = store.activeTasks.where((t) => t.id == task.id).single;
      expect(back.title, 'Bio reviewer');
      expect(back.pomodorosDone, 2);
      expect(store.currentTask?.id, task.id);
      expect(store.focusMinutesOn(DateTime(2026, 11, 21)), 25);
      expect(store.cardsReviewedToday, 12);
      expect(store.prefs.userName, 'Kristine');
      expect(store.prefs.palette, 'plum');
      expect(store.prefs.appearance, Appearance.dark);
      expect(store.prefs.alarmSound, isFalse);
      expect(store.settings.focusMinutes, 30);
      expect(store.profilePhoto, isNotNull);
      expect(store.prefs.installId, 'phone-install-id',
          reason: "the account doesn't carry another phone's id");
    });

    test('on a new phone, the account and the phone are joined, each Pomodoro '
        'once', () async {
      useTheApp();
      await AccountData.instance.save();
      // Another phone: its own Pomodoro today, and one the account has too.
      store.resetForTesting();
      AccountData.instance.forget();
      store.recordFocusSession(25, endedAt: DateTime(2026, 11, 21, 9)); // same
      store.recordFocusSession(50, endedAt: DateTime(2026, 11, 23, 15)); // new
      expect(await AccountData.instance.bringIn(), isTrue);
      expect(store.sessions.map((s) => s.minutes), [25, 25, 50]);
      expect(store.focusMinutesOn(DateTime(2026, 11, 21)), 25,
          reason: 'the day log keeps the larger count, not the sum');
      final saved = (accounts.rows['google-user']!['data']! as Map)['sessions'] as List;
      expect(saved, hasLength(3), reason: 'the joined data is saved back');
    });

    test("when the account can't be read, nothing changes or is overwritten",
        () async {
      useTheApp();
      await AccountData.instance.save();
      final before = jsonEncode(accounts.rows['google-user']);
      await store.resetAccountData();
      accounts.loadFails = true;
      expect(await AccountData.instance.bringIn(), isFalse);
      expect(store.sessions, isEmpty);
      expect(jsonEncode(accounts.rows['google-user']), before);
    });
  });

  group('Log Out in Profile', () {
    Future<void> openProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProfileScreen())));
      await tester.pumpAndSettle();
    }

    Future<void> tapLogOut(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
    }

    testWidgets('with a Google account: saved, cleared, back to the welcome',
        (tester) async {
      DriveSync.debugStore = MemoryDriveStore();
      await tester.runAsync(() => DriveSync.instance.debugSignIn());
      useTheApp();
      await openProfile(tester);
      await tapLogOut(tester);
      expect(find.textContaining('saved to your account'), findsOneWidget);
      await tester.tap(find.text('Log Out').last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      final saved = accounts.rows['google-user']!['data']! as Map;
      expect(saved['sessions'] as List, hasLength(2));
      expect((saved['prefs'] as Map)['name'], 'Kristine');
      expect(store.sessions, isEmpty);
      expect(store.prefs.userName, '');
      expect(accounts.signOuts, 1);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets("offline: asks before logging out, and Cancel keeps everything",
        (tester) async {
      DriveSync.debugStore = MemoryDriveStore();
      await tester.runAsync(() => DriveSync.instance.debugSignIn());
      useTheApp();
      accounts.saveFails = true;
      await openProfile(tester);
      await tapLogOut(tester);
      await tester.tap(find.text('Log Out').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't Save to Your Account"), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(2));
      expect(accounts.signOuts, 0);
    });

    testWidgets("without an account: warns that you can't log back in; Cancel keeps everything",
        (tester) async {
      accounts.isAnonymous = true;
      useTheApp();
      await openProfile(tester);
      await tapLogOut(tester);
      expect(find.text("You Can't Log Back In"), findsOneWidget);
      expect(find.text('Sign In with Google'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(2));
      expect(store.prefs.userName, 'Kristine');
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('without an account: Log Out and Delete deletes everything',
        (tester) async {
      accounts.isAnonymous = true;
      useTheApp();
      await openProfile(tester);
      await tapLogOut(tester);
      await tester.tap(find.text('Log Out and Delete'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(store.sessions, isEmpty);
      expect(store.prefs.userName, '');
      expect(store.prefs.welcomed, isFalse);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('without an account: Sign In with Google keeps everything',
        (tester) async {
      DriveSync.debugStore = MemoryDriveStore();
      accounts.isAnonymous = true;
      useTheApp();
      await openProfile(tester);
      await tapLogOut(tester);
      await tester.tap(find.text('Sign In with Google'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(DriveSync.instance.isSignedIn, isTrue);
      expect(store.sessions, hasLength(2));
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.textContaining('Signed in as'), findsOneWidget);
    });
  });
}
