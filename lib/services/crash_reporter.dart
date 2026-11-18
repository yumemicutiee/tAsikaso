import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/app_store.dart';
import '../theme/brand.dart';
import 'study_ai.dart';

/// Sends a short report to the study server's log (`POST /v1/crash`) when
/// the app hits an error nobody caught, so problems on phones nobody can
/// test by hand still come to light.
///
/// A report holds the error, where in the app's code it happened, the app
/// version and the system — never notes, photos, cards, the name or email
/// (see web/privacy.html). It is skipped when Settings → Your Data → Send
/// Crash Reports is off or no study server is set, and is best-effort: a
/// failure to send is ignored.
class CrashReporter {
  CrashReporter._();

  /// At most this many reports per run of the app, so an error repeating
  /// every frame can't flood the server.
  static const maxPerRun = 5;
  static const maxMessage = 300;
  static const maxStack = 3500;

  static final Set<String> _sent = {};
  static int _count = 0;

  /// Set in tests to stand in for the network.
  @visibleForTesting
  static http.Client Function()? debugClient;

  /// Catches what Flutter and the platform report as uncaught, keeping
  /// whatever handled them before (the red error screen while debugging,
  /// the console).
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(report(details.exception, details.stack, source: 'flutter'));
    };
    final platformPrevious = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack, source: 'platform'));
      return platformPrevious?.call(error, stack) ?? false;
    };
  }

  /// Sends one report, if allowed. Returns whether one was sent.
  static Future<bool> report(Object error, StackTrace? stack,
      {String source = 'flutter'}) async {
    try {
      if (!AppStore.instance.prefs.crashReports) return false;
      final url = StudyAi.serverUrl;
      if (!StudyAi.isValidUrl(url)) return false;
      final message = _clip('${error.runtimeType}: $error', maxMessage);
      final where = _clip(stack?.toString() ?? '', maxStack);
      // The same error over and over is reported once.
      if (_count >= maxPerRun || !_sent.add('$message\n${where.split('\n').first}')) {
        return false;
      }
      _count++;
      final client = (debugClient ?? http.Client.new)();
      try {
        final token = StudyAi.token;
        final res = await client
            .post(
              Uri.parse('${url.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/crash'),
              headers: {
                'content-type': 'application/json',
                if (token.isNotEmpty) 'authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'message': message,
                if (where.isNotEmpty) 'stack': where,
                'source': source,
                'version': kAppVersion,
                'platform': platformName(),
              }),
            )
            .timeout(const Duration(seconds: 15));
        return res.statusCode < 300;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Crash report not sent: $e');
      return false;
    }
  }

  /// "android 14 (…)", "web", …
  static String platformName() {
    if (kIsWeb) return 'web';
    return _clip('${Platform.operatingSystem} ${Platform.operatingSystemVersion}', 120);
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  /// Test hook: forget what was sent this run.
  @visibleForTesting
  static void reset() {
    _sent.clear();
    _count = 0;
  }
}
