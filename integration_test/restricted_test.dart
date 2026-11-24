// The permission states most students will really have, which the main
// emulator run (everything allowed) doesn't see. tool/emulator_tests.sh
// sets the phone up with adb and runs this file once per state:
//   RESTRICTED=exact          Android 14's default: Alarms & reminders off
//                             (the alarm still rings: USE_EXACT_ALARM)
//   RESTRICTED=notifications  the student tapped "Don't allow" for
//                             notifications (fixed, so no dialog appears)
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // Straight into the app (the welcome is phone_test's).
    store.updatePrefs(store.prefs.copyWith(welcomed: true));
    await NotificationService.init();
  });

  testWidgets("Android 14's default (Alarms & reminders off): the alarm still "
      'rings on time, thanks to USE_EXACT_ALARM', (tester) async {
    if (mode != 'exact') {
      markTestSkipped('Runs with RESTRICTED=exact.');
      return;
    }
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!;
    // The script switched "Alarms & reminders" off; the timer app's own
    // permission, granted at install, still allows the alarm clock alarm.
    expect(await NotificationService.exactTimingAllowed(), isTrue,
        reason: 'USE_EXACT_ALARM must allow exact alarms without the setting');
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

    // Settings no longer needs to offer Allow Exact Timing.
    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    openSettings(tester.element(find.byType(HomeShell)),
        section: SettingsSection.notifications);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Allow Exact Timing'), findsNothing);

    // An alarm due in 5 s rings on time: the app's own, not a notification.
    const alarm = MethodChannel('tasikaso/alarm');
    final due = clock.now().add(const Duration(seconds: 5));
    await NotificationService.scheduleTimerEnd(due, 'Pomodoro done', 'On time.',
        isBreak: false, sound: true, vibrate: true);
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 60) &&
        !(await alarm.invokeMethod<bool>('ringing') ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final late = clock.now().difference(due).inSeconds;
    debugPrint('Alarm rang about $late s after it was due');
    expect(await alarm.invokeMethod<bool>('ringing'), isTrue,
        reason: 'the alarm must ring without Alarms & reminders switched on');
    expect(late, lessThan(15), reason: 'on time, not held back');
    await NotificationService.cancelTimerEnd();
    expect(await alarm.invokeMethod<bool>('ringing'), isFalse);
    await plugin.cancelAll();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('notifications refused: START says why the timer cannot ring, '
      'and keeps Timer Alerts on for when they are allowed', (tester) async {
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

    // Alerts on, and "already asked" as in settings brought back from an
    // account or a backup: the phone's real permission is checked anyway.
    store.updatePrefs(store.prefs
        .copyWith(timerAlerts: true, askedNotifications: true));
    final timer = PomodoroController.instance..resetForTesting();
    final said = <String>[];
    timer.onMessage = said.add;

    timer.start();
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 20) && said.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    timer.pause();
    timer.reset();

    expect(said.join(' '), contains("notifications aren't allowed"));
    expect(store.prefs.timerAlerts, isTrue,
        reason: 'allowing notifications later must make the timer ring');
  });
}
