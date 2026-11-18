import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/services/page_model_service.dart';
import 'package:study_app/utils/page_detector.dart';
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

  group('the bordered input', () {
    for (final name in ['white_desk_00', 'clutter_02']) {
      test('matches what the models were checked with ($name)', () {
        final photo = img.decodeJpg(File('$_dir/page_$name.jpg').readAsBytesSync())!;
        final ref = img.decodePng(
            File('$_dir/page_${name}_input_padded.png').readAsBytesSync())!;
        final input = pageModelInputPadded(photo);
        const s = pageModelInputSize;
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
        expect(diff / (3 * s * s), lessThan(5));
      });
    }

    test('corners found in it map back onto the photo', () {
      // A 1000 × 1500 photo with a 20% border is 1400 × 2100; a corner at
      // the photo's own (100, 150) sits at (300, 450) in the bordered one.
      const inBordered = [
        Offset(300 / 1400, 450 / 2100),
        Offset(1100 / 1400, 450 / 2100),
        Offset(1100 / 1400, 1650 / 2100),
        Offset(300 / 1400, 1650 / 2100),
      ];
      final back = unpadCorners(inBordered, 1000, 1500)!;
      expect(back[0].dx, closeTo(0.1, 1e-9));
      expect(back[0].dy, closeTo(0.1, 1e-9));
      expect(back[2].dx, closeTo(0.9, 1e-9));
      expect(back[2].dy, closeTo(0.9, 1e-9));
    });

    test('a shape that ends up off the photo is dropped', () {
      // All four corners in the border: nothing of the photo is left.
      const inBorder = [
        Offset(0.01, 0.01), Offset(0.1, 0.01), Offset(0.1, 0.1), Offset(0.01, 0.1),
      ];
      expect(unpadCorners(inBorder, 1000, 1500), isNull);
    });
  });

  group('preferEnclosingSheet', () {
    const sheet = [Offset(0.1, 0.1), Offset(0.9, 0.12), Offset(0.88, 0.9), Offset(0.12, 0.88)];
    const linesOnIt = [Offset(0.25, 0.2), Offset(0.75, 0.2), Offset(0.75, 0.75), Offset(0.25, 0.75)];

    test('the sheet wins when the models found a box printed on it', () {
      expect(preferEnclosingSheet(linesOnIt, sheet), sheet);
    });

    test('the models win when they and the sheet agree', () {
      const nearly = [Offset(0.11, 0.11), Offset(0.89, 0.13), Offset(0.87, 0.89), Offset(0.13, 0.87)];
      expect(preferEnclosingSheet(nearly, sheet), nearly);
    });

    test('the models win when the sheet is somewhere else (clutter)', () {
      const elsewhere = [Offset(0.5, 0.5), Offset(0.95, 0.5), Offset(0.95, 0.95), Offset(0.5, 0.95)];
      expect(preferEnclosingSheet(linesOnIt, elsewhere), linesOnIt);
    });

    test('the models win when there is no sheet', () {
      expect(preferEnclosingSheet(linesOnIt, null), linesOnIt);
    });

    test('the emulator\'s photo: ruled lines with wide margins crop to the sheet', () {
      // integration_test's pageOnDesk(): a cream sheet with dark ruled
      // lines well inside it, on a brown desk.
      final photo = img.Image(width: 2400, height: 3200);
      img.fill(photo, color: img.ColorRgb8(92, 70, 52));
      img.fillPolygon(photo,
          vertices: [
            img.Point(380, 300), img.Point(2050, 420),
            img.Point(1960, 2900), img.Point(300, 2780),
          ],
          color: img.ColorRgb8(238, 234, 224));
      for (var y = 600; y < 2500; y += 90) {
        img.fillRect(photo,
            x1: 520, y1: y, x2: 1750, y2: y + 14, color: img.ColorRgb8(40, 44, 70));
      }
      // What all three model runs answered on the PC: the block of lines.
      const modelSaw = [Offset(0.214, 0.185), Offset(0.727, 0.188), Offset(0.729, 0.784), Offset(0.216, 0.783)];
      const truth = [
        Offset(380 / 2400, 300 / 3200), Offset(2050 / 2400, 420 / 3200),
        Offset(1960 / 2400, 2900 / 3200), Offset(300 / 2400, 2780 / 3200),
      ];
      final simple = detectPageCorners(photo);
      expect(simple, isNotNull);
      expect(_worst(preferEnclosingSheet(modelSaw, simple), truth), lessThan(0.02));
    });

    test('quadArea', () {
      expect(quadArea(const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]), 1);
      expect(quadArea(linesOnIt), closeTo(0.275, 1e-9));
    });
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
