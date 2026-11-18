import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/app_store.dart';
import 'data/pomodoro_controller.dart';
import 'data/storage/local_storage.dart';
import 'services/crash_reporter.dart';
import 'services/drive_sync.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Help → Open-Source Licenses: the auto-crop model's notice, next to the
  // packages' own licenses that Flutter lists by itself.
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString('assets/models/DOCALIGNER_NOTICE.txt');
    yield LicenseEntryWithLineBreaks(['DocAligner (page-corner model)'], notice);
  });
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = AppStore.instance;
  await store.init(createDeviceStorage());
  // After the saved settings are loaded: they say whether reports may go.
  CrashReporter.install();
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
