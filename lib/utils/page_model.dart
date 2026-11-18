import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// The maths around the page-corner models (DocAligner, see
/// assets/models/DOCALIGNER_NOTICE.txt): what goes in and how their answer
/// becomes four corners. Pure Dart so it can be tested anywhere; running
/// the models is `services/page_model_service.dart`.

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

/// How much border [pageModelInputPadded] adds on each side, as a share of
/// the photo's width and height.
const double pageModelPadding = 0.2;

/// The model's input for [image] with a border of [pad] × its size on every
/// side, filled by repeating the photo's edge pixels (more "desk"). A page
/// that fills most of the photo then looks page-sized to the model, which
/// otherwise can take a box printed on the page for the page itself. Map the
/// corners back with [unpadCorners].
Float32List pageModelInputPadded(img.Image image, {double pad = pageModelPadding}) {
  const s = pageModelInputSize;
  final px = (image.width * pad).floor(), py = (image.height * pad).floor();
  final bigW = image.width + 2 * px, bigH = image.height + 2 * py;
  // The photo's part of the square, and where it starts.
  final iw = math.max(1, (s * image.width / bigW).round());
  final ih = math.max(1, (s * image.height / bigH).round());
  final ox = s * px / bigW, oy = s * py / bigH;
  final inner = img.copyResize(image,
      width: iw, height: ih, interpolation: img.Interpolation.average);
  final out = Float32List(3 * s * s);
  for (var y = 0; y < s; y++) {
    final sy = (y + 0.5 - oy).floor().clamp(0, ih - 1);
    for (var x = 0; x < s; x++) {
      final sx = (x + 0.5 - ox).floor().clamp(0, iw - 1);
      final p = inner.getPixel(sx, sy);
      final i = y * s + x;
      out[i] = p.rNormalized.toDouble().clamp(0.0, 1.0);
      out[s * s + i] = p.gNormalized.toDouble().clamp(0.0, 1.0);
      out[2 * s * s + i] = p.bNormalized.toDouble().clamp(0.0, 1.0);
    }
  }
  return out;
}

/// Corners found in the bordered photo of [pageModelInputPadded], back as
/// fractions of the photo itself (kept on it), or null when they no longer
/// make a plausible page.
List<Offset>? unpadCorners(List<Offset> corners, int width, int height,
    {double pad = pageModelPadding}) {
  final fx = (width * pad).floor() / width, fy = (height * pad).floor() / height;
  final back = [
    for (final c in corners)
      Offset((c.dx * (1 + 2 * fx) - fx).clamp(0.0, 1.0),
          (c.dy * (1 + 2 * fy) - fy).clamp(0.0, 1.0)),
  ];
  return plausiblePage(back) ? back : null;
}

/// The simpler detector's [sheet] when it holds the model's [found] shape
/// and is at least [ratio] times its size: the model then took something
/// printed on the page (a border, a table, a block of ruled lines) for the
/// page. Otherwise [found].
List<Offset> preferEnclosingSheet(List<Offset> found, List<Offset>? sheet,
    {double ratio = 1.3}) {
  if (sheet == null || sheet.length != 4) return found;
  // A little slack, so corners on the sheet's own edge count as inside.
  final centre = sheet.reduce((a, b) => a + b) / 4;
  final grown = [for (final p in sheet) centre + (p - centre) * 1.04];
  final inside = found.every((p) => _insideConvex(p, grown));
  return inside && quadArea(sheet) >= ratio * quadArea(found) ? sheet : found;
}

/// Area of a four-cornered shape (fractions of the photo, so 1 = all of it).
double quadArea(List<Offset> q) {
  var a = 0.0;
  for (var i = 0; i < q.length; i++) {
    final p = q[i], n = q[(i + 1) % q.length];
    a += p.dx * n.dy - n.dx * p.dy;
  }
  return a.abs() / 2;
}

bool _insideConvex(Offset p, List<Offset> poly) {
  var sign = 0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    if (cross == 0) continue;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
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
  return plausiblePage(corners) ? corners : null;
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
bool plausiblePage(List<Offset> c) {
  if (c.length != 4) return false;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
    if (cross <= 0) return false;
  }
  final (tl, tr, br, bl) = (c[0], c[1], c[2], c[3]);
  if (tl.dx >= tr.dx || bl.dx >= br.dx || tl.dy >= bl.dy || tr.dy >= br.dy) {
    return false;
  }
  if (quadArea(c) < 0.04) return false;
  for (var i = 0; i < 4; i++) {
    if ((c[i] - c[(i + 1) % 4]).distance < 0.05) return false;
  }
  return true;
}
