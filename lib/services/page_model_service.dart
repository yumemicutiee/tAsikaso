import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../utils/page_model.dart';

/// What the page models look at for one photo: the photo, the photo with a
/// border ([pageModelInputPadded]), and its size (to map corners back).
class PageModelInputs {
  const PageModelInputs(this.plain, this.padded, this.width, this.height);
  final Float32List plain;
  final Float32List padded;
  final int width;
  final int height;
}

/// Runs DocAligner's page-corner models (assets/models/, see
/// DOCALIGNER_NOTICE.txt) with ONNX Runtime: on the phone's CPU on Android
/// and iOS (a background thread), and with onnxruntime-web in the browser
/// (see web/index.html). The same on every phone, with or without Google
/// Play services.
///
/// The models are asked in turn until one is sure:
///  1. the big model (fastvit_sa24) on the photo,
///  2. the big model on the photo with a border, which stops a box printed
///     on the page passing for the page,
///  3. the small model (lcnet100), which answers more often.
/// Measured on 96 test photos, this chain found 90 pages right and 5 wrong,
/// where the small model alone got 80 right and 13 wrong.
///
/// Every failure returns null so the caller falls back to the simpler
/// detector (utils/page_detector.dart); the user can always drag the corners.
class PageModel {
  PageModel._();

  static const bigAsset = 'assets/models/docaligner_fastvit_sa24.onnx';
  static const smallAsset = 'assets/models/docaligner_lcnet100.onnx';

  /// The first run loads the models (and on the web downloads them and ONNX
  /// Runtime's WebAssembly), so it's given longer than later runs.
  static const firstRunTimeout = Duration(seconds: 60);
  static const runTimeout = Duration(seconds: 20);

  static final _models = {
    bigAsset: _Model(bigAsset),
    smallAsset: _Model(smallAsset),
  };
  static bool _ranOnce = false;

  /// False once neither model works here (no plugin, or both failed), so
  /// later photos don't wait for them.
  static bool get available => _models.values.any((m) => m.usable);

  /// Corners for one photo, or null.
  static Future<List<Offset>?> findCorners(PageModelInputs inputs) async {
    if (!available) return null;
    try {
      final corners =
          await _chain(inputs).timeout(_ranOnce ? runTimeout : firstRunTimeout);
      _ranOnce = true;
      return corners;
    } on TimeoutException {
      debugPrint('Page models took too long; using the simple detector.');
      return null;
    }
  }

  static Future<List<Offset>?> _chain(PageModelInputs inputs) async {
    final big = _models[bigAsset]!, small = _models[smallAsset]!;
    final first = await big.corners(inputs.plain);
    if (first != null) return first;
    final bordered = await big.corners(inputs.padded);
    if (bordered != null) {
      final back = unpadCorners(bordered, inputs.width, inputs.height);
      if (back != null) return back;
    }
    return small.corners(inputs.plain);
  }

  /// Test hook: forget the sessions and any earlier failure.
  @visibleForTesting
  static void reset() {
    for (final m in _models.values) {
      m.reset();
    }
    _ranOnce = false;
  }
}

/// One model file: its session, made on first use, and whether it works.
class _Model {
  _Model(this.asset);
  final String asset;

  Future<OrtSession>? _session;
  bool _broken = false;
  int _failures = 0;

  bool get usable => !_broken;

  /// Corners the model is sure of for [input], or null (also when it fails).
  Future<List<Offset>?> corners(Float32List input) async {
    if (_broken) return null;
    try {
      final session =
          await (_session ??= OnnxRuntime().createSessionFromAsset(asset));
      const s = pageModelInputSize;
      final tensor = await OrtValue.fromList(input, [1, 3, s, s]);
      Map<String, OrtValue>? outputs;
      try {
        outputs = await session.run({'img': tensor});
        final heat = outputs['heatmap'] ?? outputs.values.first;
        final flat = await heat.asFlattenedList();
        _failures = 0;
        return cornersFromHeatmap([for (final v in flat) (v as num).toDouble()]);
      } finally {
        await tensor.dispose();
        for (final t in outputs?.values ?? const <OrtValue>[]) {
          await t.dispose();
        }
      }
    } on MissingPluginException {
      _broken = true; // widget tests, or a platform without the plugin
      return null;
    } catch (e) {
      // E.g. not enough memory for the big model on a small phone: the
      // other model carries on.
      debugPrint('Page model $asset failed: $e');
      _session = null;
      if (++_failures >= 2) _broken = true;
      return null;
    }
  }

  void reset() {
    _session = null;
    _broken = false;
    _failures = 0;
  }
}
