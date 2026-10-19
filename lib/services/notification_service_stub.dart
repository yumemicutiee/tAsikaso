// Web and other platforms: no notifications.

bool get isSupported => false;

Future<void> init() async {}

Future<bool> requestPermission() async => false;

Future<void> scheduleTimerEnd(DateTime at, String title, String body,
    {required bool isBreak}) async {}

Future<void> cancelTimerEnd() async {}

Future<void> setDailyReminder(int? minuteOfDay) async {}
