import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// A real buzz when a Pomodoro or break ends, as opposed to the faint tap
/// of a haptic click (which also obeys the phone's touch-feedback setting).
class Haptics {
  Haptics._();

  /// Off in tests, where there is no phone to buzz.
  @visibleForTesting
  static bool enabled = true;

  static Future<void> timeIsUp() async {
    if (!enabled) return;
    try {
      if (!await Vibration.hasVibrator()) return;
      await Vibration.vibrate(pattern: [0, 400, 200, 400]);
    } catch (e) {
      // Not available here (web, desktop): nothing to do.
      debugPrint('Could not vibrate: $e');
    }
  }
}
