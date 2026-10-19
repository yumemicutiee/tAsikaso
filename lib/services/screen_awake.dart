import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on (Focus Mode). Failures are ignored: it's a comfort,
/// not a requirement.
class ScreenAwake {
  ScreenAwake._();

  /// Switched off in tests, where there's no screen to keep awake.
  @visibleForTesting
  static bool enabled = true;

  static Future<void> set(bool on) async {
    if (!enabled) return;
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      debugPrint('Keep-awake unavailable: $e');
    }
  }
}
