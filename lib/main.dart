import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/app_store.dart';
import 'data/pomodoro_controller.dart';
import 'data/storage/local_storage.dart';
import 'services/drive_sync.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = AppStore.instance;
  await store.init(createDeviceStorage());
  // A Pomodoro that was running when the app was closed carries on.
  PomodoroController.instance.restore();
  runApp(const StudyApp());

  // After the first frame so start-up isn't slowed down.
  // Google Drive sync signs the user back in quietly and watches for changes.
  DriveSync.instance.init();
  await NotificationService.init();
  final prefs = store.prefs;
  await NotificationService.setDailyReminder(
      prefs.dailyReminder ? prefs.reminderMinutes : null);
}
