import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../services/scan_service.dart';
import 'capture_screen.dart';
import 'captured_page.dart';
import 'review_screen.dart';

/// Starts scanning notes.
///
/// With Smart Scanner on (and on Android), the phone's document scanner opens:
/// it finds the page edges, crops and straightens each page automatically.
/// The pages then go to the review screen to double-check and save.
/// Otherwise — or if the scanner can't start — the app's own camera opens.
Future<void> startScan(BuildContext context) async {
  if (AppStore.instance.prefs.smartScanner && ScanService.canScanDocuments) {
    try {
      final pages = await _scanPages(0);
      if (pages == null || !context.mounted) return; // backed out
      await Navigator.of(context).push(
        MaterialPageRoute<List<CapturedPage>>(
          builder: (_) => ReviewScreen(
            pages: pages,
            autoCropped: true,
            addMore: (count) => _scanPages(count),
          ),
        ),
      );
      return;
    } catch (e) {
      debugPrint('Document scanner unavailable: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Smart Scanner isn't available on this phone, "
              'so the camera opened instead.'),
          showCloseIcon: true,
        ));
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const CaptureScreen(),
    ),
  );
}

/// Runs the scanner and prepares its pages. [firstId] keeps ids unique when
/// pages are added to an existing batch.
Future<List<CapturedPage>?> _scanPages(int firstId) async {
  final jpegs = await ScanService.scanDocuments();
  if (jpegs == null || jpegs.isEmpty) return null;
  return [
    for (var i = 0; i < jpegs.length; i++)
      await CapturedPage.fromPhoto(firstId + i, jpegs[i]),
  ];
}
