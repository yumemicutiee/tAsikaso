import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
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

// Android fixes a channel's vibration when it is first created, so the
// "Vibrate When Time Is Up" setting picks one of two channels.
final _timerDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'timer',
    'Timer',
    channelDescription: 'When a Pomodoro or a break ends',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 400, 200, 400]),
  ),
  iOS: const DarwinNotificationDetails(presentSound: true),
);

const _quietTimerDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'timer_quiet',
    'Timer (no vibration)',
    channelDescription: 'When a Pomodoro or a break ends, without vibrating',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    enableVibration: false,
  ),
  iOS: DarwinNotificationDetails(presentSound: true),
);

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
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // Permission is asked for from Settings, when the user turns alerts on.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  _ready = true;
}

Future<bool> requestPermission() async {
  await init();
  if (Platform.isAndroid) {
    return await _android?.requestNotificationsPermission() ?? true;
  }
  final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  return await ios?.requestPermissions(alert: true, sound: true) ?? false;
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

/// Exact timing when Android allows it (see [requestExactTiming]);
/// otherwise Android may deliver it a little late.
Future<AndroidScheduleMode> _mode() async {
  return await exactTimingAllowed()
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;
}

Future<void> scheduleTimerEnd(DateTime at, String title, String body,
    {required bool isBreak, required bool vibrate}) async {
  await init();
  final id = isBreak ? _breakEndId : _focusEndId;
  await _plugin.cancel(id: id);
  if (!at.isAfter(clock.now())) return;
  await _plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
    notificationDetails: vibrate ? _timerDetails : _quietTimerDetails,
    androidScheduleMode: await _mode(),
    title: title,
    body: body,
  );
}

Future<void> cancelTimerEnd() async {
  await init();
  await _plugin.cancel(id: _focusEndId);
  await _plugin.cancel(id: _breakEndId);
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
