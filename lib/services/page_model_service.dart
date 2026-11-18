import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../utils/page_model.dart';

/// Runs the page-corner model (assets/models/docaligner_lcnet100.onnx) with
/// ONNX Runtime: on the phone's CPU on Android and iOS (a background thread),
/// and with onnxruntime-web in the browser (see web/index.html). It works
/// the same with or without Google Play services.
///
/// Every failure returns null so the caller falls back to the older
/// detector (utils/page_detector.dart); the user can always drag the corners.
class PageModel {
  PageModel._();

  static const asset = 'assets/models/docaligner_lcnet100.onnx';

  /// The first run on the web downloads ONNX Runtime's WebAssembly (a few
  /// MB), so it's given longer than later runs.
  static const firstRunTimeout = Duration(seconds: 45);
  static const runTimeout = Duration(seconds: 15);

  static Future<OrtSession>? _session;
  static bool _unavailable = false;
  static int _failures = 0;
  static bool _ranOnce = false;

  /// False once the model has been found not to work here (no plugin, or it
  /// failed twice), so later photos don't wait for it.
  static bool get available => !_unavailable;

  /// Corners for the photo whose [pageModelInput] is [input], or null.
  static Future<List<Offset>?> findCorners(Float32List input) async {
    if (_unavailable) return null;
    try {
      final run = _run(input);
      final corners =
          await run.timeout(_ranOnce ? runTimeout : firstRunTimeout);
      _ranOnce = true;
      _failures = 0;
      return corners;
    } on MissingPluginException {
      _unavailable = true; // widget tests, or a platform without the plugin
      return null;
    } on TimeoutException {
      debugPrint('Page model took too long; using the simple detector.');
      return null;
    } catch (e) {
      debugPrint('Page model failed: $e');
      _session = null;
      if (++_failures >= 2) _unavailable = true;
      return null;
    }
  }

  static Future<List<Offset>?> _run(Float32List input) async {
    final session =
        await (_session ??= OnnxRuntime().createSessionFromAsset(asset));
    const s = pageModelInputSize;
    final tensor = await OrtValue.fromList(input, [1, 3, s, s]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({'img': tensor});
      final heat = outputs['heatmap'] ?? outputs.values.first;
      final flat = await heat.asFlattenedList();
      return cornersFromHeatmap(
          [for (final v in flat) (v as num).toDouble()]);
    } finally {
      await tensor.dispose();
      for (final t in outputs?.values ?? const <OrtValue>[]) {
        await t.dispose();
      }
    }
  }

  /// Test hook: forget the session and any earlier failure.
  @visibleForTesting
  static void reset() {
    _session = null;
    _unavailable = false;
    _failures = 0;
    _ranOnce = false;
  }
}
