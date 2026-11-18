// The permission states most students will really have, which the main
// emulator run (everything allowed) doesn't see. tool/emulator_tests.sh
// sets the phone up with adb and runs this file once per state:
//   RESTRICTED=exact          Android 14's default: exact alarms not allowed
//   RESTRICTED=notifications  the student tapped "Don't allow" for
//                             notifications (fixed, so no dialog appears)
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/data/storage/local_storage.dart';
import 'package:study_app/screens/actions.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/settings_screen.dart';
import 'package:study_app/services/notification_service.dart';

const mode = String.fromEnvironment('RESTRICTED');
final store = AppStore.instance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await store.init(createDeviceStorage());
    await NotificationService.init();
  });

  testWidgets('exact alarms not allowed: the alert still comes, and Settings '
      'offers Allow Exact Timing', (tester) async {
    if (mode != 'exact') {
      markTestSkipped('Runs with RESTRICTED=exact.');
      return;
    }
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!;
    expect(await NotificationService.exactTimingAllowed(), isFalse,
        reason: "exact alarms are allowed: the test script's setup didn't take");
    // The script grants notifications when it sees this (a grant doesn't
    // restart the app; tool/emulator_tests.sh).
    debugPrint('TASIKASO_SETUP grant-notifications');
    final granted = Stopwatch()..start();
    while (!(await android.areNotificationsEnabled() ?? false) &&
        granted.elapsed < const Duration(seconds: 60)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(await android.areNotificationsEnabled(), isTrue,
        reason: 'the test script grants notifications for this run');

    // Settings shows the row that leads to the phone's own setting.
    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    openSettings(tester.element(find.byType(HomeShell)),
        section: SettingsSection.notifications);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Allow Exact Timing'), findsOneWidget);
    expect(find.text('Alerts may be late'), findsOneWidget);

    // An alert due in 5 s still arrives without exact timing; how late it is
    // goes to the log (a real phone in a pocket can be later still).
    final due = clock.now().add(const Duration(seconds: 5));
    await NotificationService.scheduleTimerEnd(due, 'Pomodoro done', 'Late check.',
        isBreak: false, vibrate: false);
    var shown = <ActiveNotification>[];
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(minutes: 12) &&
        !shown.any((n) => n.id == 1)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      shown = await android.getActiveNotifications();
    }
    final late = clock.now().difference(due).inSeconds;
    debugPrint('Alert without exact timing arrived about $late s after it was due');
    expect(shown.map((n) => n.id), contains(1),
        reason: 'the alert must still come, just maybe later');
    await NotificationService.cancelTimerEnd();
    await plugin.cancelAll();
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('notifications refused: START switches Timer Alerts off and '
      'says why', (tester) async {
    if (mode != 'notifications') {
      markTestSkipped('Runs with RESTRICTED=notifications.');
      return;
    }
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()!;
    expect(await android.areNotificationsEnabled(), isFalse,
        reason: 'a fresh install has not been granted notifications');
    // The script marks them "Don't allow" (fixed) when it sees this, so
    // Android refuses at once instead of asking; that doesn't restart the app.
    debugPrint('TASIKASO_SETUP fix-notifications-refused');
    await Future<void>.delayed(const Duration(seconds: 8));

    // As on a fresh install: alerts on, never asked yet.
    store.updatePrefs(store.prefs
        .copyWith(timerAlerts: true, askedNotifications: false));
    final timer = PomodoroController.instance..resetForTesting();
    final said = <String>[];
    timer.onMessage = said.add;

    timer.start();
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 20) &&
        store.prefs.timerAlerts) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    timer.pause();
    timer.reset();

    expect(store.prefs.timerAlerts, isFalse,
        reason: "the switch mustn't promise alerts that can't be shown");
    expect(said.join(' '), contains("notifications aren't allowed"));
    expect((await FlutterLocalNotificationsPlugin().pendingNotificationRequests())
        .where((r) => r.id == 1), isEmpty,
        reason: 'the scheduled alert was taken back');
  });
}
