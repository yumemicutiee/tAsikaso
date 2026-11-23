import 'dart:async';

import 'package:study_app/data/app_store.dart';
import 'package:study_app/screens/welcome/welcome_screen.dart';

/// Runs before every test file: the tests start with the sample folders and
/// tasks (a real install starts empty).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppStore.samplesOnFirstLaunch = true;
  // The welcome's cards float forever; tests wait for the screen to settle.
  WelcomeScreen.floating = false;
  await testMain();
}
