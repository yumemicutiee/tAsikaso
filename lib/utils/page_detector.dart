import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// Finds the page in a photo: the corners of the largest bright, roughly
/// four-sided area, as fractions of the image (top-left, top-right,
/// bottom-right, bottom-left), or null when no page stands out — it fills
/// the frame already, or it lies on a background as bright as itself.
///
/// Pure Dart, so it works on the web too; on phones call it in an isolate.
/// The photo is shrunk to about 320 pixels first, so it takes a few tens of
/// milliseconds.
List<Offset>? detectPageCorners(img.Image image) {
  const maxSide = 320;
  final longest = math.max(image.width, image.height);
  final scale = longest > maxSide ? maxSide / longest : 1.0;
  final w = math.max(8, (image.width * scale).round());
  final h = math.max(8, (image.height * scale).round());
  final small = img.copyResize(image,
      width: w, height: h, interpolation: img.Interpolation.average);

  // Brightness, smoothed so pen strokes and paper grain don't matter.
  // Normalised channels, so 16-bit and float photos (0–65535, 0–1) read
  // the same as ordinary 8-bit ones.
  var lum = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      lum[y * w + x] = (255 *
              (0.299 * p.rNormalized +
                  0.587 * p.gNormalized +
                  0.114 * p.bNormalized))
          .round()
          .clamp(0, 255);
    }
  }
  lum = _boxBlur(lum, w, h, 2);

  // Paper is the bright part. Otsu's threshold splits it from the desk.
  final threshold = _otsu(lum);
  final mask = Uint8List(w * h);
  var bright = 0;
  var brightSum = 0;
  var darkSum = 0;
  for (var i = 0; i < mask.length; i++) {
    if (lum[i] >= threshold) {
      mask[i] = 1;
      bright++;
      brightSum += lum[i];
    } else {
      darkSum += lum[i];
    }
  }
  final share = bright / mask.length;
  if (share < 0.1 || share > 0.97) return null;
  // Two shades of nearly the same brightness (paper on a white desk) are
  // not a page and its surroundings, whatever the threshold says.
  final contrast = brightSum / bright - darkSum / (mask.length - bright);
  if (contrast < 40) return null;

  // Close small holes (the writing) so the page is one solid shape.
  final closed = _erode(_dilate(mask, w, h, 2), w, h, 2);
  final page = _largestComponent(closed, w, h);
  if (page == null || page.area < 0.12 * w * h) return null;

  final hull = _convexHull(_boundary(page.pixels, w, h));
  if (hull.length < 4) return null;

  // A page seen at an angle is still a convex four-sided shape, so its
  // corners are the hull points farthest out along the two diagonals.
  _Pt best(num Function(_Pt) score) =>
      hull.reduce((a, b) => score(b) > score(a) ? b : a);
  final tl = best((p) => -(p.x + p.y));
  final tr = best((p) => p.x - p.y);
  final br = best((p) => p.x + p.y);
  final bl = best((p) => p.y - p.x);
  final quad = [tl, tr, br, bl];

  // Not page-shaped (a round object, a mess of bright patches)?
  if (_area(quad) < 0.8 * _area(hull)) return null;
  // One sheet fills its outline; bright clutter has big bites out of it.
  if (page.area < 0.85 * _area(hull)) return null;
  final sides = [
    for (var i = 0; i < 4; i++) _dist(quad[i], quad[(i + 1) % 4]),
  ];
  final minSide = 0.15 * math.min(w, h);
  if (sides.any((s) => s < minSide)) return null;
  // Perspective makes a page's far edge shorter than the near one, but not
  // under half of it: such a shape only happens to have four corners (the
  // emulator's test picture, a bright wall behind the desk).
  for (final (a, b) in [(sides[0], sides[2]), (sides[1], sides[3])]) {
    if (math.max(a, b) > 2 * math.min(a, b)) return null;
  }

  final corners = [
    for (final p in quad)
      Offset(
        (p.x / (w - 1)).clamp(0.0, 1.0),
        (p.y / (h - 1)).clamp(0.0, 1.0),
      ),
  ];

  // The whole frame: nothing worth cropping.
  const frame = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  var atEdges = true;
  for (var i = 0; i < 4; i++) {
    if ((corners[i] - frame[i]).distance > 0.02) atEdges = false;
  }
  return atEdges ? null : corners;
}

class _Pt {
  const _Pt(this.x, this.y);
  final int x;
  final int y;
}

class _Component {
  const _Component(this.pixels, this.area);

  /// 1 where the pixel belongs to the component.
  final Uint8List pixels;
  final int area;
}

/// Averages each pixel with its neighbours within [r] (two passes).
Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(w * h);
  final out = Uint8List(w * h);
  final size = 2 * r + 1;
  for (var y = 0; y < h; y++) {
    var sum = 0;
    for (var x = -r; x <= r; x++) {
      sum += src[y * w + x.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[y * w + x] = sum ~/ size;
      sum += src[y * w + (x + r + 1).clamp(0, w - 1)] -
          src[y * w + (x - r).clamp(0, w - 1)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var y = -r; y <= r; y++) {
      sum += tmp[y.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum ~/ size;
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] -
          tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  return out;
}

/// Otsu's method: the brightness that best separates dark from light.
int _otsu(Uint8List lum) {
  final hist = List<int>.filled(256, 0);
  for (final v in lum) {
    hist[v]++;
  }
  final total = lum.length;
  var sumAll = 0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumBack = 0;
  var weightBack = 0;
  var best = 0.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    weightBack += hist[t];
    if (weightBack == 0) continue;
    final weightFore = total - weightBack;
    if (weightFore == 0) break;
    sumBack += t * hist[t];
    final meanBack = sumBack / weightBack;
    final meanFore = (sumAll - sumBack) / weightFore;
    final between =
        weightBack * weightFore * (meanBack - meanFore) * (meanBack - meanFore);
    if (between > best) {
      best = between;
      threshold = t + 1;
    }
  }
  return threshold;
}

Uint8List _dilate(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, 1);

Uint8List _erode(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, 0);

/// Sets each pixel to [hit] if any pixel within [r] equals [hit]
/// (dilation for 1, erosion for 0). Pixels outside the image count as
/// their nearest edge pixel, so a page touching the frame keeps its edge.
Uint8List _morph(Uint8List m, int w, int h, int r, int hit) {
  final tmp = Uint8List(w * h);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 1 - hit;
      for (var dx = -r; dx <= r && v != hit; dx++) {
        if (m[y * w + (x + dx).clamp(0, w - 1)] == hit) v = hit;
      }
      tmp[y * w + x] = v;
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var v = 1 - hit;
      for (var dy = -r; dy <= r && v != hit; dy++) {
        if (tmp[(y + dy).clamp(0, h - 1) * w + x] == hit) v = hit;
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

/// The biggest connected patch of 1s in [mask] (4-connected).
_Component? _largestComponent(Uint8List mask, int w, int h) {
  final label = Int32List(w * h); // 0 = unvisited
  final queue = Int32List(w * h);
  var next = 1;
  var bestLabel = 0;
  var bestArea = 0;
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || label[start] != 0) continue;
    final id = next++;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    label[start] = id;
    var area = 0;
    while (head < tail) {
      final i = queue[head++];
      area++;
      final x = i % w;
      final y = i ~/ w;
      void visit(int j) {
        if (mask[j] != 0 && label[j] == 0) {
          label[j] = id;
          queue[tail++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < w - 1) visit(i + 1);
      if (y > 0) visit(i - w);
      if (y < h - 1) visit(i + w);
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = id;
    }
  }
  if (bestLabel == 0) return null;
  final pixels = Uint8List(w * h);
  for (var i = 0; i < pixels.length; i++) {
    if (label[i] == bestLabel) pixels[i] = 1;
  }
  return _Component(pixels, bestArea);
}

/// Pixels of the shape that touch something outside it (or the frame).
List<_Pt> _boundary(Uint8List pixels, int w, int h) {
  final out = <_Pt>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (pixels[i] == 0) continue;
      if (x == 0 ||
          y == 0 ||
          x == w - 1 ||
          y == h - 1 ||
          pixels[i - 1] == 0 ||
          pixels[i + 1] == 0 ||
          pixels[i - w] == 0 ||
          pixels[i + w] == 0) {
        out.add(_Pt(x, y));
      }
    }
  }
  return out;
}

/// Andrew's monotone chain; returns the hull counter-clockwise.
List<_Pt> _convexHull(List<_Pt> points) {
  if (points.length < 3) return List.of(points);
  final pts = List.of(points)
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  int cross(_Pt o, _Pt a, _Pt b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <_Pt>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <_Pt>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

/// Shoelace area of a polygon.
double _area(List<_Pt> poly) {
  var sum = 0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

double _dist(_Pt a, _Pt b) {
  final dx = (a.x - b.x).toDouble();
  final dy = (a.y - b.y).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}
