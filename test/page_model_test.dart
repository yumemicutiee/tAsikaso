import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/services/page_model_service.dart';
import 'package:study_app/utils/page_model.dart';

/// Fixtures from the PC check of the model (the same ONNX file, run with
/// ONNX Runtime in Python): a photo, the 256×256 input it was given, the
/// heatmaps it answered with, and the true corners.
const _dir = 'test/fixtures';
final _meta = jsonDecode(File('$_dir/page_model_fixtures.json').readAsStringSync())
    as Map<String, dynamic>;

List<Offset> _truth(String name) => [
      for (final p in (_meta[name]['truth'] as List))
        Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];

/// Reads the model's saved heatmaps (gzipped float16).
List<double> _heatmap(String name) {
  final bytes = gzip.decode(File('$_dir/page_${name}_heatmap.f16.gz').readAsBytesSync());
  final halves = Uint8List.fromList(bytes).buffer.asUint16List();
  return [for (final h in halves) _half(h)];
}

double _half(int h) {
  final sign = (h >> 15) == 1 ? -1.0 : 1.0;
  final exp = (h >> 10) & 0x1f;
  final frac = h & 0x3ff;
  if (exp == 0) return sign * math.pow(2, -14) * (frac / 1024);
  if (exp == 31) return frac == 0 ? sign * double.infinity : double.nan;
  return sign * math.pow(2, exp - 15) * (1 + frac / 1024);
}

double _worst(List<Offset> a, List<Offset> b) =>
    [for (var i = 0; i < 4; i++) (a[i] - b[i]).distance].reduce(math.max);

/// Four heatmaps with one round blob at each of [corners] (null = none).
List<double> _blobs(List<Offset?> corners, {double peak = 0.9}) {
  const s = pageModelHeatmapSize;
  final heat = List<double>.filled(4 * s * s, 0);
  for (var c = 0; c < 4; c++) {
    final p = corners[c];
    if (p == null) continue;
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final dx = (x + 0.5) / s - p.dx, dy = (y + 0.5) / s - p.dy;
        heat[c * s * s + y * s + x] =
            peak * math.exp(-(dx * dx + dy * dy) / (2 * 0.01 * 0.01));
      }
    }
  }
  return heat;
}

void main() {
  group('the model\'s input', () {
    for (final name in ['white_desk_00', 'clutter_02']) {
      test('matches what the model was checked with ($name)', () {
        final photo = img.decodeJpg(File('$_dir/page_$name.jpg').readAsBytesSync())!;
        final ref = img.decodePng(File('$_dir/page_${name}_input.png').readAsBytesSync())!;
        final input = pageModelInput(photo);
        const s = pageModelInputSize;
        expect(input.length, 3 * s * s);
        var diff = 0.0;
        for (var y = 0; y < s; y++) {
          for (var x = 0; x < s; x++) {
            final p = ref.getPixel(x, y);
            final i = y * s + x;
            diff += (input[i] * 255 - p.r).abs() +
                (input[s * s + i] * 255 - p.g).abs() +
                (input[2 * s * s + i] * 255 - p.b).abs();
          }
        }
        // Same picture, resized by a different library: a few levels apart.
        expect(diff / (3 * s * s), lessThan(4));
        expect(input.reduce(math.max), lessThanOrEqualTo(1));
        expect(input.reduce(math.min), greaterThanOrEqualTo(0));
      });
    }
  });

  group('corners from the model\'s real answers', () {
    for (final name in ['white_desk_00', 'clutter_02']) {
      test('land on the page ($name)', () {
        final corners = cornersFromHeatmap(_heatmap(name));
        expect(corners, isNotNull);
        // Within 1% of the photo: no need to drag.
        expect(_worst(corners!, _truth(name)), lessThan(0.01));
      });
    }
  });

  group('cornersFromHeatmap', () {
    const page = [Offset(0.2, 0.15), Offset(0.8, 0.2), Offset(0.85, 0.85), Offset(0.15, 0.8)];

    test('finds each corner at its blob', () {
      final c = cornersFromHeatmap(_blobs(page))!;
      expect(_worst(c, page), lessThan(0.005));
    });

    test('a corner off the photo is placed from the other three, on the edge', () {
      // Bottom-right is past the frame, so the model has nothing for it.
      const truth = [Offset(0.3, 0.2), Offset(0.9, 0.25), Offset(1.05, 0.95), Offset(0.45, 0.9)];
      final c = cornersFromHeatmap(_blobs([truth[0], truth[1], null, truth[3]]))!;
      expect(c[2].dx, 1.0); // kept on the photo's right edge
      expect(c[2].dy, closeTo(0.95, 0.01));
    });

    test('two corners missing: not a page', () {
      expect(cornersFromHeatmap(_blobs([page[0], null, page[2], null])), isNull);
    });

    test('nothing confident: not a page', () {
      expect(cornersFromHeatmap(_blobs(page, peak: 0.2)), isNull);
      expect(cornersFromHeatmap(List.filled(4 * 128 * 128, 0)), isNull);
    });

    test('a twisted or swapped shape is rejected', () {
      expect(cornersFromHeatmap(_blobs([page[1], page[0], page[2], page[3]])), isNull);
      expect(cornersFromHeatmap(_blobs([page[0], page[1], page[3], page[2]])), isNull);
    });

    test('a tiny patch is not a page', () {
      const tiny = [Offset(0.5, 0.5), Offset(0.56, 0.5), Offset(0.56, 0.57), Offset(0.5, 0.57)];
      expect(cornersFromHeatmap(_blobs(tiny)), isNull);
    });

    test('a stray patch elsewhere does not move a corner', () {
      final heat = _blobs(page);
      // A small confident speck in the top-left map, far from the corner.
      const s = pageModelHeatmapSize;
      for (final (x, y) in [(100, 100), (101, 100), (100, 101)]) {
        heat[y * s + x] = 0.95;
      }
      expect(_worst(cornersFromHeatmap(heat)!, page), lessThan(0.005));
    });

    test('too short an answer is not a page', () {
      expect(cornersFromHeatmap([0.5, 0.5]), isNull);
    });
  });

  test('without the model (tests, no plugin) photos still get the simple detector', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PageModel.reset();
    final photo = img.decodeJpg(File('$_dir/page_clutter_02.jpg').readAsBytesSync())!;
    final page = await CapturedPage.fromPhoto(1, img.encodeJpg(photo), findEdges: true);
    expect(page.width, photo.width);
    // Whatever the simple detector decides, the import works and the crop
    // is either found or the whole photo.
    expect(page.corners, hasLength(4));
    // No plugin here: the model is switched off for later photos instead
    // of being retried each time.
    expect(PageModel.available, isFalse);
  });
}
