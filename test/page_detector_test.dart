import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/utils/page_detector.dart';

/// A 400×300 photo of a pale page on a desk, with some writing on it.
/// [corners] are fractions: top-left, top-right, bottom-right, bottom-left.
img.Image photoOfPage(List<Offset> corners, {img.Color? desk}) {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: desk ?? img.ColorRgb8(70, 58, 48));
  img.fillPolygon(
    image,
    vertices: [
      for (final c in corners) img.Point(c.dx * 399, c.dy * 299),
    ],
    color: img.ColorRgb8(236, 232, 222),
  );
  // Lines of "writing" inside the page.
  for (var y = 70; y < 230; y += 18) {
    img.fillRect(image,
        x1: 90, y1: y, x2: 300, y2: y + 4, color: img.ColorRgb8(40, 40, 60));
  }
  return image;
}

const pageCorners = [
  Offset(0.15, 0.12),
  Offset(0.86, 0.16),
  Offset(0.84, 0.90),
  Offset(0.12, 0.86),
];

void expectNear(List<Offset> found, List<Offset> wanted) {
  for (var i = 0; i < 4; i++) {
    expect((found[i] - wanted[i]).distance, lessThan(0.035),
        reason: 'corner $i: found ${found[i]}, wanted ${wanted[i]}');
  }
}

void main() {
  test('finds the corners of a page on a darker desk', () {
    final found = detectPageCorners(photoOfPage(pageCorners));
    expect(found, isNotNull);
    expectNear(found!, pageCorners);
  });

  test('a page seen at a steeper angle is still found', () {
    const skewed = [
      Offset(0.25, 0.08),
      Offset(0.80, 0.20),
      Offset(0.90, 0.95),
      Offset(0.10, 0.80),
    ];
    final found = detectPageCorners(photoOfPage(skewed));
    expect(found, isNotNull);
    expectNear(found!, skewed);
  });

  test('a 16-bit photo is read like an 8-bit one', () {
    // Its channels run to 65535: read as 0–255 everything looked white.
    final deep = photoOfPage(pageCorners).convert(format: img.Format.uint16);
    final found = detectPageCorners(deep);
    expect(found, isNotNull);
    expectNear(found!, pageCorners);
  });

  test('a page that fills the frame is left as it is', () {
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(236, 232, 222));
    expect(detectPageCorners(image), isNull);
  });

  test('a page on a background as pale as itself is left as it is', () {
    const corners = [
      Offset(0.2, 0.2),
      Offset(0.8, 0.2),
      Offset(0.8, 0.8),
      Offset(0.2, 0.8),
    ];
    // A desk almost as pale as the paper.
    final image = photoOfPage(corners, desk: img.ColorRgb8(226, 222, 212));
    expect(detectPageCorners(image), isNull);
  });

  test('a round bright thing is not taken for a page', () {
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(70, 58, 48));
    img.fillCircle(image,
        x: 200, y: 150, radius: 120, color: img.ColorRgb8(236, 232, 222));
    expect(detectPageCorners(image), isNull);
  });

  test('a bright shape that only happens to have four corners is not a page',
      () {
    // Like the emulator's test picture: a pale area running off the top
    // and left of the frame in steps, with no sheet of paper in it.
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(70, 58, 48));
    img.fillPolygon(
      image,
      vertices: [
        img.Point(0, 0),
        img.Point(399, 0),
        img.Point(399, 120),
        img.Point(250, 120),
        img.Point(250, 200),
        img.Point(130, 200),
        img.Point(130, 299),
        img.Point(0, 299),
      ],
      color: img.ColorRgb8(240, 240, 236),
    );
    expect(detectPageCorners(image), isNull);
  });

  test('a page photographed at a slant, half off the frame, is still found',
      () {
    // Far edge (top) shorter than the near one; the bottom runs off.
    const slanted = [
      Offset(0.25, 0.10),
      Offset(0.75, 0.10),
      Offset(0.95, 1.0),
      Offset(0.05, 1.0),
    ];
    final found = detectPageCorners(photoOfPage(slanted));
    expect(found, isNotNull);
    expectNear(found!, slanted);
  });

  test('fromPhoto pre-sets the crop corners when asked to find the edges',
      () async {
    final png = img.encodePng(photoOfPage(pageCorners));
    final found = await CapturedPage.fromPhoto(1, png, findEdges: true);
    expect(found.autoDetected, isTrue);
    expectNear(found.corners, pageCorners);

    final plain = await CapturedPage.fromPhoto(2, png);
    expect(plain.autoDetected, isFalse);
    expect(plain.corners, CapturedPage.fullFrame);

    found.resetCrop();
    expect(found.autoDetected, isFalse);
    expect(found.corners, CapturedPage.fullFrame);
  });

  test('fromPhoto can turn a sideways frame upright first', () async {
    final wide = img.Image(width: 40, height: 30);
    img.fill(wide, color: img.ColorRgb8(200, 200, 200));
    // A dark strip along the top edge: after a clockwise turn it's on the right.
    img.fillRect(wide, x1: 0, y1: 0, x2: 39, y2: 4, color: img.ColorRgb8(0, 0, 0));
    final page = await CapturedPage.fromPhoto(1, img.encodePng(wide), quarterTurns: 1);
    expect((page.width, page.height), (30, 40));
    final turned = img.decodeImage(page.bytes)!;
    expect(turned.getPixel(29, 20).r, lessThan(60)); // right edge is dark
    expect(turned.getPixel(0, 20).r, greaterThan(150)); // left edge is light
  });
}
