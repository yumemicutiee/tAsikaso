import 'dart:async';

import 'package:study_app/data/app_store.dart';

/// Runs before every test file: the tests start with the sample folders and
/// tasks (a real install starts empty).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppStore.samplesOnFirstLaunch = true;
  await testMain();
}
