import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// The maths around the page-corner model (DocAligner "lcnet100", see
/// assets/models/DOCALIGNER_NOTICE.txt): what goes in and how its answer
/// becomes four corners. Pure Dart so it can be tested anywhere; running
/// the model itself is `services/page_model_service.dart`.

/// The model looks at the whole photo squeezed to this square.
const int pageModelInputSize = 256;

/// Each corner comes back as a [pageModelHeatmapSize]² map of how likely
/// every spot is to be that corner.
const int pageModelHeatmapSize = 128;

/// A spot belongs to a corner when the map is at least this sure (the value
/// DocAligner itself uses).
const double pageModelThreshold = 0.3;

/// The model's input for [image]: RGB, 0–1, channels first, the photo
/// stretched to 256 × 256 (it was trained on stretched photos).
Float32List pageModelInput(img.Image image) {
  const s = pageModelInputSize;
  final small = img.copyResize(image,
      width: s, height: s, interpolation: img.Interpolation.average);
  final out = Float32List(3 * s * s);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      final p = small.getPixel(x, y);
      final i = y * s + x;
      out[i] = p.rNormalized.toDouble().clamp(0.0, 1.0);
      out[s * s + i] = p.gNormalized.toDouble().clamp(0.0, 1.0);
      out[2 * s * s + i] = p.bNormalized.toDouble().clamp(0.0, 1.0);
    }
  }
  return out;
}

/// The page's corners (top-left, top-right, bottom-right, bottom-left, as
/// fractions of the photo) from the model's four heatmaps, or null when the
/// model didn't see a page.
///
/// Each corner is the centre of its map's biggest confident patch, weighted
/// by how sure the model is. When one corner is outside the photo (the page
/// runs off the frame), it is placed where the other three say it must be
/// and kept on the photo's edge. A shape that isn't a plausible page (twisted,
/// tiny, inside out) gives null, so the caller can try something else.
List<Offset>? cornersFromHeatmap(
  List<double> heat, {
  int size = pageModelHeatmapSize,
  double threshold = pageModelThreshold,
}) {
  final plane = size * size;
  if (heat.length < 4 * plane) return null;
  final found = <Offset?>[
    for (var c = 0; c < 4; c++)
      _peakCentre(heat, c * plane, size, threshold),
  ];
  final missing = [for (var i = 0; i < 4; i++) if (found[i] == null) i];
  if (missing.length > 1) return null;
  if (missing.length == 1) {
    final i = missing.single;
    // A page is close to a parallelogram: the hidden corner is the
    // neighbours' sum minus the opposite corner.
    found[i] = found[(i + 1) % 4]! + found[(i + 3) % 4]! - found[(i + 2) % 4]!;
  }
  final corners = [
    for (final p in found)
      Offset(p!.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)),
  ];
  return _plausiblePage(corners) ? corners : null;
}

/// Weighted centre of the biggest connected patch at or above [threshold]
/// in one heatmap, as fractions; null when there's none.
Offset? _peakCentre(List<double> heat, int start, int size, double threshold) {
  final plane = size * size;
  final seen = Uint8List(plane);
  final stack = <int>[];
  var bestArea = 0;
  var bestX = 0.0, bestY = 0.0;
  for (var i = 0; i < plane; i++) {
    if (seen[i] == 1 || heat[start + i] < threshold) continue;
    var area = 0;
    var sw = 0.0, sx = 0.0, sy = 0.0;
    stack.add(i);
    seen[i] = 1;
    while (stack.isNotEmpty) {
      final j = stack.removeLast();
      final x = j % size, y = j ~/ size;
      final w = heat[start + j];
      area++;
      sw += w;
      sx += w * x;
      sy += w * y;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= size) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if ((dx == 0 && dy == 0) || nx < 0 || nx >= size) continue;
          final k = ny * size + nx;
          if (seen[k] == 0 && heat[start + k] >= threshold) {
            seen[k] = 1;
            stack.add(k);
          }
        }
      }
    }
    if (area > bestArea && sw > 0) {
      bestArea = area;
      bestX = (sx / sw + 0.5) / size;
      bestY = (sy / sw + 0.5) / size;
    }
  }
  return bestArea == 0 ? null : Offset(bestX, bestY);
}

/// Convex, turning the same way all round (top-left → top-right →
/// bottom-right → bottom-left is clockwise on screen), each corner on its
/// own side, and big enough to be a page rather than a stray patch.
bool _plausiblePage(List<Offset> c) {
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
    if (cross <= 0) return false;
  }
  final (tl, tr, br, bl) = (c[0], c[1], c[2], c[3]);
  if (tl.dx >= tr.dx || bl.dx >= br.dx || tl.dy >= bl.dy || tr.dy >= br.dy) {
    return false;
  }
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    area += c[i].dx * c[(i + 1) % 4].dy - c[(i + 1) % 4].dx * c[i].dy;
  }
  if (area.abs() / 2 < 0.04) return false;
  for (var i = 0; i < 4; i++) {
    if ((c[i] - c[(i + 1) % 4]).distance < 0.05) return false;
  }
  return true;
}
