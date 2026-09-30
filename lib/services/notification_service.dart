import 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_io.dart' as impl;

/// Timer alerts and the daily study reminder, shown by the phone even when
/// the app is closed. Android and iOS only; everywhere else (web, tests)
/// every call quietly does nothing.
class NotificationService {
  NotificationService._();

  static bool get isSupported => impl.isSupported;

  /// Call once at start-up.
  static Future<void> init() => _guard(impl.init);

  /// Asks for permission to show notifications (Android 13+ and iOS).
  /// Returns false if the user said no.
  static Future<bool> requestPermission() async {
    try {
      return await impl.requestPermission();
    } catch (_) {
      return false;
    }
  }

  /// Shows [title]/[body] at [at]. Pomodoro and break alerts use separate
  /// slots, so starting a break never cancels the Pomodoro alert that is
  /// just going off.
  static Future<void> scheduleTimerEnd(
    DateTime at,
    String title,
    String body, {
    required bool isBreak,
  }) =>
      _guard(() => impl.scheduleTimerEnd(at, title, body, isBreak: isBreak));

  static Future<void> cancelTimerEnd() => _guard(impl.cancelTimerEnd);

  /// Every day at [minuteOfDay] (e.g. 19:00 = 1140), or off when null.
  static Future<void> setDailyReminder(int? minuteOfDay) =>
      _guard(() => impl.setDailyReminder(minuteOfDay));

  /// Notifications are a bonus: a failure must never break the app.
  static Future<void> _guard(Future<void> Function() action) async {
    if (!impl.isSupported) return;
    try {
      await action();
    } catch (_) {
      // e.g. permission missing or the plugin isn't set up; nothing to do.
    }
  }
}
