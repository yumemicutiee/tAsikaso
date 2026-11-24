import 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_io.dart' as impl;

/// Timer alerts and the daily study reminder, shown by the phone even when
/// the app is closed. Android and iOS only; everywhere else (web, tests)
/// every call quietly does nothing.
class NotificationService {
  NotificationService._();

  static bool get isSupported => impl.isSupported;

  /// Calls run one after another, in the order they were made, so a cancel
  /// that follows a schedule can't overtake it and leave an alert behind.
  static Future<void> _chain = Future.value();

  /// Call once at start-up.
  static Future<void> init() => _guard(impl.init);

  /// Asks for permission to show notifications (Android 13+ and iOS).
  /// Returns false if the user said no.
  static Future<bool> requestPermission() => _ask(impl.requestPermission);

  /// Whether the phone lets the app show notifications right now.
  static Future<bool> notificationsEnabled() => _ask(impl.notificationsEnabled);

  /// Opens the phone's notification settings for the app (Android).
  static Future<bool> openNotificationSettings() =>
      _ask(impl.openNotificationSettings);

  /// Whether alerts can go off at the exact second. Android 14 and newer
  /// deny that by default, and then an alert can arrive minutes late.
  static Future<bool> exactTimingAllowed() => _ask(impl.exactTimingAllowed);

  /// Opens the phone's "alarms and reminders" setting for the app (Android
  /// 14+). Returns true once exact timing is allowed.
  static Future<bool> requestExactTiming() => _ask(impl.requestExactTiming);

  /// Shows [title]/[body] at [at]. Pomodoro and break alerts use separate
  /// slots, so starting a break never cancels the Pomodoro alert that is
  /// just going off. [sound] (the phone's alarm sound) and [vibrate] follow
  /// Settings → When Time Is Up, and keep going until the student taps Stop
  /// (or the alert); with neither, nothing is scheduled.
  static Future<void> scheduleTimerEnd(
    DateTime at,
    String title,
    String body, {
    required bool isBreak,
    required bool sound,
    required bool vibrate,
  }) =>
      _guard(() => impl.scheduleTimerEnd(at, title, body,
          isBreak: isBreak, sound: sound, vibrate: vibrate));

  static Future<void> cancelTimerEnd() => _guard(impl.cancelTimerEnd);

  /// Rings the alarm now, the app's own (Android), when a phase ends with
  /// the app on screen. False when it couldn't (the scheduled one rings).
  static Future<bool> ringNow(String title, String body,
          {required bool isBreak, required bool sound, required bool vibrate}) =>
      _ask(() => impl.ringNow(title, body,
          isBreak: isBreak, sound: sound, vibrate: vibrate));

  /// Told when the alarm can't be rung the reliable way (main.dart sends a
  /// report).
  static set onProblem(void Function(String message)? hook) =>
      impl.problemHook = hook;

  /// Every day at [minuteOfDay] (e.g. 19:00 = 1140), or off when null.
  static Future<void> setDailyReminder(int? minuteOfDay) =>
      _guard(() => impl.setDailyReminder(minuteOfDay));

  /// Notifications are a bonus: a failure must never break the app.
  static Future<void> _guard(Future<void> Function() action) {
    if (!impl.isSupported) return Future.value();
    final run = _chain.then((_) => action()).catchError((Object _) {
      // e.g. permission missing or the plugin isn't set up; nothing to do.
    });
    _chain = run;
    return run;
  }

  /// A question to the phone, in turn with the other calls; a failure
  /// counts as "no".
  static Future<bool> _ask(Future<bool> Function() question) {
    if (!impl.isSupported) return question();
    final run = _chain.then((_) => question()).catchError((Object _) => false);
    _chain = run.then((_) {});
    return run;
  }
}
