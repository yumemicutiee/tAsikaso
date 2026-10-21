import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The size profile photos are kept at (square, pixels).
const profilePhotoSize = 256;

/// A square JPEG of [bytes] (any image format, upright), or null if it
/// can't be read. Top-level so it can run in an isolate with `compute`.
Uint8List? squarePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: profilePhotoSize,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(square, quality: 85);
}

/// Google account photo links name their size (`…=s96-c`, or `/s96-c/` in
/// the path); this asks for [size] pixels instead. Other links come back
/// unchanged.
String googlePhotoAtSize(String url, int size) {
  final suffix = url.replaceFirstMapped(
    RegExp(r'=s\d+(-c)?$'),
    (m) => '=s$size${m.group(1) ?? ''}',
  );
  if (suffix != url) return suffix;
  return url.replaceFirst(RegExp(r'/s\d+-c/'), '/s$size-c/');
}
