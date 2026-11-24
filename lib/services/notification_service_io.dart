import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

// Android & iOS. (Also compiled for tests and desktop, where it's switched
// off by [isSupported].)

bool get isSupported => Platform.isAndroid || Platform.isIOS;

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

const _focusEndId = 1;
const _reminderId = 2;
const _breakEndId = 3;

// "When Time Is Up" (Settings): Android fixes a channel's sound and
// vibration when it is first created, so each choice has its own channel.
// The alarm channels use the phone's own alarm sound on the alarm volume
// (it rings even on silent, like an alarm clock). The alarm and the
// vibration keep going, like an alarm clock's, until the student stops them:
// Stop on the notification, tapping it, or swiping it away (FLAG_INSISTENT,
// no time limit).

/// The phone's alarm sound, as chosen in its Clock app.
const _alarmSound = UriAndroidNotificationSound('content://settings/system/alarm_alert');

/// Android's Notification.FLAG_INSISTENT: the sound and the vibration repeat
/// until the user does something with the notification.
final _insistent = Int32List.fromList([4]);
final _buzz = Int64List.fromList([0, 600, 300, 600, 300, 600]);

/// Silences the alert without opening the app (needs the plugin's
/// ActionBroadcastReceiver in AndroidManifest.xml; tool/setup_android.dart).
const _stopAction = <AndroidNotificationAction>[
  AndroidNotificationAction('stop', 'Stop', cancelNotification: true),
];

final _alarmAndVibrationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'timer_alarm_vibrate',
    'Timer: alarm and vibration',
    channelDescription: 'When a Pomodoro or a break ends: the alarm sound and vibration',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    sound: _alarmSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: true,
    vibrationPattern: _buzz,
    additionalFlags: _insistent,
    actions: _stopAction,
  ),
  iOS: const DarwinNotificationDetails(presentSound: true),
);

final _alarmDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'timer_alarm',
    'Timer: alarm',
    channelDescription: 'When a Pomodoro or a break ends: the alarm sound',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    sound: _alarmSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: false,
    additionalFlags: _insistent,
    actions: _stopAction,
  ),
  iOS: const DarwinNotificationDetails(presentSound: true),
);

final _vibrationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'timer_vibrate',
    'Timer: vibration only',
    channelDescription: 'When a Pomodoro or a break ends: vibration, no sound',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    playSound: false,
    enableVibration: true,
    vibrationPattern: _buzz,
    // Keeps vibrating until stopped, like the alarm.
    additionalFlags: _insistent,
    actions: _stopAction,
  ),
  iOS: const DarwinNotificationDetails(presentSound: false),
);

/// The three timer channels, made at start-up (Android only makes a channel
/// when its first alert shows otherwise), so they're in the phone's
/// notification settings from the start and match the alerts above.
final _timerChannels = [
  AndroidNotificationChannel(
    'timer_alarm_vibrate',
    'Timer: alarm and vibration',
    description: 'When a Pomodoro or a break ends: the alarm sound and vibration',
    importance: Importance.max,
    sound: _alarmSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: true,
    vibrationPattern: _buzz,
  ),
  const AndroidNotificationChannel(
    'timer_alarm',
    'Timer: alarm',
    description: 'When a Pomodoro or a break ends: the alarm sound',
    importance: Importance.max,
    sound: _alarmSound,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: false,
  ),
  AndroidNotificationChannel(
    'timer_vibrate',
    'Timer: vibration only',
    description: 'When a Pomodoro or a break ends: vibration, no sound',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
    vibrationPattern: _buzz,
  ),
];

/// The notification for a "When Time Is Up" choice; null for Off.
NotificationDetails? _timerDetailsFor({required bool sound, required bool vibrate}) =>
    sound
        ? (vibrate ? _alarmAndVibrationDetails : _alarmDetails)
        : (vibrate ? _vibrationDetails : null);

const _reminderDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminder',
    'Study reminder',
    channelDescription: 'A daily nudge to study',
  ),
  iOS: DarwinNotificationDetails(),
);

Future<void> init() async {
  if (_ready) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      // A white-on-transparent glyph (res/drawable/ic_stat_notify.xml); the
      // launcher icon would show as a white blob in the status bar.
      android: AndroidInitializationSettings('ic_stat_notify'),
      // Permission is asked for from Settings, when the user turns alerts on.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  _ready = true;
  final android = _android;
  if (android != null) {
    for (final channel in _timerChannels) {
      try {
        await android.createNotificationChannel(channel);
      } catch (_) {
        // Made with the first alert instead.
      }
    }
    // The channels of 0.5.0 and older ("Timer", "Timer (no vibration)"),
    // replaced by the three above: gone from the phone's settings.
    for (final old in _oldTimerChannels) {
      try {
        await android.deleteNotificationChannel(channelId: old);
      } catch (_) {
        // Never made on this phone, or already gone.
      }
    }
  }
}

/// Timer channels from before "When Time Is Up".
const _oldTimerChannels = ['timer', 'timer_quiet'];

Future<bool> requestPermission() async {
  await init();
  if (Platform.isAndroid) {
    return await _android?.requestNotificationsPermission() ?? true;
  }
  final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  return await ios?.requestPermissions(alert: true, sound: true) ?? false;
}

/// Whether the phone lets this app show notifications right now (the
/// student can turn them off in the phone's settings at any time).
Future<bool> notificationsEnabled() async {
  await init();
  if (Platform.isAndroid) {
    return await _android?.areNotificationsEnabled() ?? true;
  }
  final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  final granted = await ios?.checkPermissions();
  return granted?.isEnabled ?? true;
}

const _settingsChannel = MethodChannel('tasikaso/settings');

/// Opens the phone's notification settings for the app (Android). After a
/// "Don't allow", Android never shows its question again; this is the way.
Future<bool> openNotificationSettings() async {
  if (!Platform.isAndroid) return false;
  return await _settingsChannel.invokeMethod<bool>('openNotificationSettings') ??
      false;
}

AndroidFlutterLocalNotificationsPlugin? get _android =>
    _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

/// Android 14+ denies exact alarms by default; elsewhere they're allowed.
Future<bool> exactTimingAllowed() async {
  if (!Platform.isAndroid) return true;
  await init();
  return await _android?.canScheduleExactNotifications() ?? true;
}

/// Opens the system page where the user can allow exact alarms.
Future<bool> requestExactTiming() async {
  if (!Platform.isAndroid) return true;
  await init();
  return await _android?.requestExactAlarmsPermission() ?? false;
}

/// For the notification fallback (the app's own alarm is used when exact
/// timing is allowed, see [scheduleTimerEnd]): set like an alarm clock's
/// alarm when allowed, otherwise Android may deliver it late.
Future<AndroidScheduleMode> _mode() async {
  return await exactTimingAllowed()
      ? AndroidScheduleMode.alarmClock
      : AndroidScheduleMode.inexactAllowWhileIdle;
}

/// The timer's alarm rung by the app itself on Android (TimerAlarm.kt):
/// the alarm sound on the ALARM volume and an ALARM vibration, repeating
/// until Stop, so silent mode or a muted notification can't silence it.
const _alarm = MethodChannel('tasikaso/alarm');

/// Sets the app's own alarm; false when it can't (no exact alarms allowed,
/// or not Android), and the notification is scheduled instead.
Future<bool> _scheduleOwnAlarm(int id, DateTime at, String title, String body,
    {required bool sound, required bool vibrate}) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _alarm.invokeMethod<bool>('schedule', {
          'id': id,
          'at': at.millisecondsSinceEpoch,
          'title': title,
          'body': body,
          'sound': sound,
          'vibrate': vibrate,
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

Future<void> _cancelOwnAlarm(int id) async {
  if (!Platform.isAndroid) return;
  try {
    await _alarm.invokeMethod<void>('cancel', {'id': id});
  } catch (_) {
    // Nothing set.
  }
}

/// Told when the timer's alarm can't be rung the reliable way (set in
/// main.dart to send a report, so problems on real phones are seen).
void Function(String message)? problemHook;

/// Rings the app's own alarm now (the timer ended with the app on screen),
/// taking back the scheduled one for [isBreak]'s slot. False if it couldn't.
Future<bool> ringNow(String title, String body,
    {required bool isBreak, required bool sound, required bool vibrate}) async {
  if (!Platform.isAndroid || (!sound && !vibrate)) return false;
  final id = isBreak ? _breakEndId : _focusEndId;
  bool rang;
  try {
    rang = await _alarm.invokeMethod<bool>('ringNow', {
          'id': id,
          'title': title,
          'body': body,
          'sound': sound,
          'vibrate': vibrate,
        }) ??
        false;
  } catch (e) {
    rang = false;
  }
  if (rang) {
    // Rung already: the scheduled one for this moment mustn't ring again.
    await _cancelOwnAlarm(id);
    await _plugin.cancel(id: id);
  } else {
    problemHook?.call('Timer alarm: could not ring with the app open');
  }
  return rang;
}

/// Stops the app's own alarm if it is ringing.
Future<void> stopRinging() async {
  if (!Platform.isAndroid) return;
  try {
    await _alarm.invokeMethod<void>('stop');
  } catch (_) {
    // Not ringing.
  }
}

Future<void> scheduleTimerEnd(DateTime at, String title, String body,
    {required bool isBreak, required bool sound, required bool vibrate}) async {
  await init();
  final id = isBreak ? _breakEndId : _focusEndId;
  await _plugin.cancel(id: id);
  await _cancelOwnAlarm(id);
  final details = _timerDetailsFor(sound: sound, vibrate: vibrate);
  if (details == null || !at.isAfter(clock.now())) return;
  // The app's own alarm when the phone allows exact alarms; otherwise the
  // notification below, which Android may deliver late.
  if (await _scheduleOwnAlarm(id, at, title, body, sound: sound, vibrate: vibrate)) {
    return;
  }
  if (Platform.isAndroid) {
    problemHook?.call('Timer alarm: fell back to a notification '
        '(exact alarms allowed: ${await exactTimingAllowed()}, '
        'notifications on: ${await notificationsEnabled()})');
  }
  await _plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
    notificationDetails: details,
    androidScheduleMode: await _mode(),
    title: title,
    body: body,
  );
}

Future<void> cancelTimerEnd() async {
  await init();
  await _plugin.cancel(id: _focusEndId);
  await _plugin.cancel(id: _breakEndId);
  await _cancelOwnAlarm(_focusEndId);
  await _cancelOwnAlarm(_breakEndId);
  await stopRinging();
}

Future<void> setDailyReminder(int? minuteOfDay) async {
  await init();
  await _plugin.cancel(id: _reminderId);
  if (minuteOfDay == null) return;

  // Next occurrence of that time (local), then repeat daily at the same time.
  // Scheduled in UTC so no time-zone database is needed; in places that
  // change clocks for daylight saving it shifts by an hour until the app is
  // next opened (main() schedules it again on every start).
  final now = clock.now();
  var at = DateTime(now.year, now.month, now.day, minuteOfDay ~/ 60, minuteOfDay % 60);
  if (!at.isAfter(now)) at = DateTime(at.year, at.month, at.day + 1, at.hour, at.minute);
  await _plugin.zonedSchedule(
    id: _reminderId,
    scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
    notificationDetails: _reminderDetails,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
    title: 'Time to study',
    body: 'A short Pomodoro keeps your streak going.',
  );
}
