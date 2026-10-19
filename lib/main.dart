import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/app_store.dart';
import 'data/storage/local_storage.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = AppStore.instance;
  await store.init(createDeviceStorage());
  runApp(const StudyApp());

  // After the first frame so start-up isn't slowed down.
  await NotificationService.init();
  final prefs = store.prefs;
  await NotificationService.setDailyReminder(
      prefs.dailyReminder ? prefs.reminderMinutes : null);
}
