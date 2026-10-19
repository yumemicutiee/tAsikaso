import 'package:flutter/foundation.dart';

import 'scan_service_stub.dart'
    if (dart.library.io) 'scan_service_mlkit.dart' as impl;

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

  static bool get canScanDocuments =>
      debugScannerAvailable ?? impl.canScanDocuments;

  static bool get canReadText => impl.canReadText;

  /// Opens the scanner. Returns the cropped pages as JPEGs, or null if the
  /// user backed out. Throws if the scanner couldn't start (e.g. Google Play
  /// services missing), so the caller can fall back to the camera.
  static Future<List<Uint8List>?> scanDocuments({int pageLimit = 20}) =>
      impl.scanDocuments(pageLimit);

  /// All text found on [jpegs], pages separated by a blank line. Returns an
  /// empty string if nothing was found, it's unavailable, or it failed —
  /// reading text is a bonus and must never block saving.
  static Future<String> readText(List<Uint8List> jpegs) async {
    if (!canReadText || jpegs.isEmpty) return '';
    try {
      return await impl.readText(jpegs);
    } catch (e) {
      debugPrint('Text recognition failed: $e');
      return '';
    }
  }
}
