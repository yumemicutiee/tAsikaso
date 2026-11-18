import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../../services/page_model_service.dart';
import '../../utils/page_detector.dart';
import '../../utils/page_model.dart';

/// A photographed or imported page, plus how the user wants it cropped and
/// rotated. The original photo is never changed; crop and rotation are
/// applied when the notes are saved (see [render]).
class CapturedPage {
  CapturedPage({
    required this.id,
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Longest side kept after import. Plenty for reading notes in a PDF and
  /// keeps processing fast on phones.
  static const int maxSide = 2000;

  /// Corners as fractions of the displayed image:
  /// top-left, top-right, bottom-right, bottom-left.
  static const List<Offset> fullFrame = [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ];

  final int id;

  /// Upright JPEG (EXIF orientation already applied).
  final Uint8List bytes;
  final int width;
  final int height;

  /// Clockwise quarter turns chosen by the user.
  int quarterTurns = 0;

  /// Crop corners in the rotated view.
  List<Offset> corners = List.of(fullFrame);

  /// The corners were found by the app (see [fromPhoto]); the user can
  /// still drag them.
  bool autoDetected = false;

  /// Width / height as shown on screen (after rotation).
  double get displayAspectRatio =>
      quarterTurns.isOdd ? height / width : width / height;

  void resetCrop() {
    corners = List.of(fullFrame);
    autoDetected = false;
  }

  /// Corners can't come closer than this (as a fraction of the page).
  static const double minCropGap = 0.05;

  /// Where corner [i] may go when dragged to [wanted]: inside the page, and
  /// never past the corner beside it or the one below/above it, so the crop
  /// can't twist into a bow tie or collapse to nothing.
  static Offset constrainCorner(List<Offset> corners, int i, Offset wanted) {
    const gap = minCropGap;
    var x = math.min(1.0, math.max(0.0, wanted.dx));
    var y = math.min(1.0, math.max(0.0, wanted.dy));
    final (tl, tr, br, bl) = (corners[0], corners[1], corners[2], corners[3]);
    switch (i) {
      case 0: // top-left
        x = math.min(x, tr.dx - gap);
        y = math.min(y, bl.dy - gap);
      case 1: // top-right
        x = math.max(x, tl.dx + gap);
        y = math.min(y, br.dy - gap);
      case 2: // bottom-right
        x = math.max(x, bl.dx + gap);
        y = math.max(y, tr.dy + gap);
      case 3: // bottom-left
        x = math.min(x, br.dx - gap);
        y = math.max(y, tl.dy + gap);
    }
    return Offset(x, y);
  }

  /// Rotates 90° clockwise, carrying the crop corners along.
  void rotateClockwise() {
    Offset turn(Offset p) => Offset(1 - p.dy, p.dx);
    final c = corners;
    // After turning, the old bottom-left becomes the new top-left, etc.
    corners = [turn(c[3]), turn(c[0]), turn(c[1]), turn(c[2])];
    quarterTurns = (quarterTurns + 1) % 4;
  }

  /// Decodes a camera/gallery photo, straightens it using its EXIF
  /// orientation and scales it down. Runs off the UI thread on phones.
  ///
  /// With [findEdges], the page is looked for in the photo (like a document
  /// scanner does) and the crop corners start on its edges when it's found.
  /// [quarterTurns] turns the photo clockwise first, for cameras that hand
  /// over sideways frames (the web camera on phones).
  ///
  /// The page-corner models ([PageModel]) are asked first. When they can't
  /// run or see no page, the simpler detector's answer is used; and when
  /// the simpler detector finds a clearly bigger sheet holding what the
  /// models found, the models took a box on the page for the page, so the
  /// sheet wins ([preferEnclosingSheet]).
  static Future<CapturedPage> fromPhoto(
    int id,
    Uint8List original, {
    bool findEdges = false,
    int quarterTurns = 0,
  }) async {
    final (bytes, width, height, simpleXY, modelInputs) = await compute(
        _normalizePhoto, (original, findEdges && PageModel.available, findEdges, quarterTurns));
    final page = CapturedPage(id: id, bytes: bytes, width: width, height: height);
    final simple = simpleXY == null
        ? null
        : [for (var i = 0; i < 4; i++) Offset(simpleXY[i * 2], simpleXY[i * 2 + 1])];
    var found = modelInputs == null ? null : await PageModel.findCorners(modelInputs);
    found = found == null ? simple : preferEnclosingSheet(found, simple);
    if (found != null) {
      page.corners = found;
      page.autoDetected = true;
    }
    return page;
  }

  /// Applies rotation and the four-corner crop. Returns a JPEG.
  Future<Uint8List> render() => compute(_renderPage, (
        bytes,
        quarterTurns,
        [for (final c in corners) ...[c.dx, c.dy]],
      ));

  /// Small JPEG for list thumbnails.
  static Future<Uint8List> thumbnail(Uint8List jpg) =>
      compute(_makeThumbnail, jpg);
}

// ---------------------------------------------------------------------------
// Image work. Top-level functions so `compute` can run them in an isolate.

/// Returns the upright, scaled JPEG, its size, the corners the simple
/// detector found (as x, y fractions, 8 numbers) or null, and the page
/// models' inputs when [forModel] (the models themselves run on the main
/// side, through their plugin).
(Uint8List, int, int, List<double>?, PageModelInputs?) _normalizePhoto(
    (Uint8List, bool, bool, int) job) {
  final (data, forModel, findEdges, quarterTurns) = job;
  final decoded = img.decodeImage(data);
  if (decoded == null) {
    throw const FormatException('This photo format is not supported.');
  }
  var image = img.bakeOrientation(decoded);
  if (quarterTurns % 4 != 0) {
    image = img.copyRotate(image, angle: 90 * (quarterTurns % 4));
  }
  const maxSide = CapturedPage.maxSide;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: maxSide, interpolation: img.Interpolation.average);
  }
  List<double>? corners;
  if (findEdges) {
    try {
      final found = detectPageCorners(image);
      if (found != null) corners = [for (final c in found) ...[c.dx, c.dy]];
    } catch (e) {
      // Finding the edges is a convenience; the full frame still works.
      debugPrint('Page detection failed: $e');
    }
  }
  PageModelInputs? modelInput;
  if (forModel) {
    try {
      modelInput = PageModelInputs(pageModelInput(image),
          pageModelInputPadded(image), image.width, image.height);
    } catch (e) {
      debugPrint('Preparing the page model input failed: $e');
    }
  }
  return (
    img.encodeJpg(image, quality: 88),
    image.width,
    image.height,
    corners,
    modelInput,
  );
}

Uint8List _renderPage((Uint8List, int, List<double>) job) {
  final (data, turns, c) = job;
  var image = img.decodeImage(data);
  if (image == null) {
    throw const FormatException('Could not read the photo.');
  }
  if (turns % 4 != 0) {
    image = img.copyRotate(image, angle: 90 * (turns % 4));
  }

  final maxX = image.width - 1;
  final maxY = image.height - 1;
  img.Point at(int i) => img.Point(c[i * 2] * maxX, c[i * 2 + 1] * maxY);
  final tl = at(0);
  final tr = at(1);
  final br = at(2);
  final bl = at(3);

  double dist(img.Point a, img.Point b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  // Output size follows the average edge lengths of the chosen area.
  final outW = math.max(2, ((dist(tl, tr) + dist(bl, br)) / 2).round());
  final outH = math.max(2, ((dist(tl, bl) + dist(tr, br)) / 2).round());

  final out = img.copyRectify(
    image,
    topLeft: tl,
    topRight: tr,
    bottomLeft: bl,
    bottomRight: br,
    interpolation: img.Interpolation.linear,
    toImage: img.Image.fromResized(image,
        width: outW, height: outH, noAnimation: true),
  );
  return img.encodeJpg(out, quality: 85);
}

Uint8List _makeThumbnail(Uint8List jpg) {
  final image = img.decodeImage(jpg);
  if (image == null) return jpg;
  final small = image.width >= image.height
      ? img.copyResize(image, width: 160, interpolation: img.Interpolation.average)
      : img.copyResize(image, height: 160, interpolation: img.Interpolation.average);
  return img.encodeJpg(small, quality: 80);
}
