import 'package:flutter/foundation.dart';

import 'recognized_text.dart';
import 'scan_service_stub.dart'
    if (dart.library.io) 'scan_service_mlkit.dart' as impl;

export 'recognized_text.dart';

/// The phone's own document scanner and text recognition (Google ML Kit).
///
/// - Document scanner (Android): finds the page edges, crops and straightens
///   automatically, offers filters, and scans many pages in one go.
/// - Text recognition (Android & iOS): reads the text on the pages, on the
///   device, without internet.
///
/// On web (and anywhere else they aren't available) both report
/// unavailable and the app falls back to its own camera and crop screens.
class ScanService {
  ScanService._();

  /// Set in tests to pretend the scanner is (un)available.
  @visibleForTesting
  static bool? debugScannerAvailable;

  /// Set in tests to stand in for the scanner itself.
  @visibleForTesting
  static Future<List<Uint8List>?> Function()? debugScan;

  /// Set in tests to stand in for text recognition.
  @visibleForTesting
  static Future<List<RecognizedPage>> Function(List<Uint8List>)? debugRead;

  static bool get canScanDocuments =>
      debugScannerAvailable ?? impl.canScanDocuments;

  static bool get canReadText => debugRead != null || impl.canReadText;

  /// Opens the scanner. Returns the cropped pages as JPEGs, or null if the
  /// user backed out. Throws if the scanner couldn't start (e.g. Google Play
  /// services missing), so the caller can fall back to the camera.
  static Future<List<Uint8List>?> scanDocuments({int pageLimit = 20}) {
    final fake = debugScan;
    if (fake != null) return fake();
    return impl.scanDocuments(pageLimit);
  }

  /// The text on each of [jpegs], line by line with positions. One result
  /// per page, empty where nothing was found, text recognition isn't
  /// available, or it failed: reading text is a bonus and must never block
  /// saving.
  static Future<List<RecognizedPage>> readPages(List<Uint8List> jpegs) async {
    final none = [for (final _ in jpegs) const RecognizedPage()];
    if (!canReadText || jpegs.isEmpty) return none;
    try {
      final pages = await (debugRead ?? impl.readPages)(jpegs);
      return pages.length == jpegs.length ? pages : none;
    } catch (e) {
      debugPrint('Text recognition failed: $e');
      return none;
    }
  }

  /// All text found on [jpegs], pages separated by a blank line. Empty if
  /// nothing was found or reading text isn't available.
  static Future<String> readText(List<Uint8List> jpegs) async =>
      RecognizedPage.join(await readPages(jpegs));
}
