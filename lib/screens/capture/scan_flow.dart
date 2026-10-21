import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../services/scan_service.dart';
import '../../utils/format.dart';
import 'capture_screen.dart';
import 'captured_page.dart';
import 'review_screen.dart';

/// True while the scanner is opening and its pages are being prepared, so a
/// second tap can't start another scan on top. Once a screen is open the
/// button is covered anyway, so the flag is released before that.
bool _scanning = false;

/// Starts scanning notes.
///
/// With Smart Scanner on (and on Android), the phone's document scanner opens:
/// it finds the page edges, crops and straightens each page automatically.
/// The pages then go to the review screen to double-check and save.
/// Otherwise — or if the scanner can't start — the app's own camera opens.
Future<void> startScan(BuildContext context) async {
  if (_scanning) return;
  if (!AppStore.instance.prefs.smartScanner || !ScanService.canScanDocuments) {
    await _openCamera(context);
    return;
  }

  final _Scan result;
  _scanning = true;
  try {
    result = await _scan(context);
  } finally {
    _scanning = false;
  }
  if (!context.mounted) return;

  // What to say is shown on the screen that opens, not as a toast, which
  // would cover its buttons at the bottom.
  switch (result) {
    case _ScanUnavailable():
      // Google Play services missing or too old: the camera does the job.
      await _openCamera(context,
          notice: "Smart Scanner isn't available on this phone, "
              'so the camera opened instead.');
    case _ScanCancelled():
      return;
    case _ScanPages(pages: final pages) when pages.isEmpty:
      _toast(context, "The scanned pages couldn't be read. Please try again.");
    case _ScanPages(:final pages, :final failed):
      await Navigator.of(context).push(
        MaterialPageRoute<List<CapturedPage>>(
          builder: (_) => ReviewScreen(
            pages: pages,
            autoCropped: true,
            addMore: (firstId) => _scanMore(context, firstId),
            notice: failed > 0 ? _leftOut(failed) : null,
          ),
        ),
      );
  }
}

/// "2 pages couldn't be read and were left out."
String _leftOut(int failed) => "${plural(failed, 'page')} couldn't be read "
    "and ${failed == 1 ? 'was' : 'were'} left out.";

sealed class _Scan {
  const _Scan();
}

/// The scanner couldn't start.
class _ScanUnavailable extends _Scan {
  const _ScanUnavailable();
}

/// The user backed out of the scanner.
class _ScanCancelled extends _Scan {
  const _ScanCancelled();
}

/// The scanned pages (empty if none of them could be read), and how many
/// couldn't be read.
class _ScanPages extends _Scan {
  const _ScanPages(this.pages, this.failed);
  final List<CapturedPage> pages;
  final int failed;
}

/// Opens the scanner and prepares what it returns.
Future<_Scan> _scan(BuildContext context) async {
  final List<Uint8List>? jpegs;
  try {
    jpegs = await ScanService.scanDocuments();
  } catch (e) {
    debugPrint('Document scanner unavailable: $e');
    return const _ScanUnavailable();
  }
  if (jpegs == null || jpegs.isEmpty || !context.mounted) {
    return const _ScanCancelled();
  }
  final (pages, failed) = await _preparePages(context, jpegs, 0);
  return _ScanPages(pages, failed);
}

/// "Add More" on the review screen. Throws if the scanner couldn't open.
Future<List<CapturedPage>?> _scanMore(BuildContext context, int firstId) async {
  final jpegs = await ScanService.scanDocuments();
  if (jpegs == null || jpegs.isEmpty || !context.mounted) return null;
  final (pages, failed) = await _preparePages(context, jpegs, firstId);
  if (context.mounted) {
    if (pages.isEmpty) {
      _toast(context, "The scanned pages couldn't be read. Please try again.");
    } else if (failed > 0) {
      _toast(context, _leftOut(failed));
    }
  }
  return pages;
}

/// Decodes and shrinks scanned [jpegs] into pages numbered from [firstId].
/// A page that can't be read is left out rather than losing the whole scan;
/// how many were left out is returned too.
@visibleForTesting
Future<(List<CapturedPage>, int)> preparePages(
    List<Uint8List> jpegs, int firstId) async {
  final pages = <CapturedPage>[];
  var failed = 0;
  for (final jpeg in jpegs) {
    try {
      pages.add(await CapturedPage.fromPhoto(firstId + pages.length, jpeg));
    } catch (e) {
      failed++;
      debugPrint('A scanned page could not be read: $e');
    }
  }
  return (pages, failed);
}

/// [preparePages] behind a "Preparing your pages…" dialog: decoding a stack
/// of high-resolution pages can take a while, and the screen was blank.
Future<(List<CapturedPage>, int)> _preparePages(
    BuildContext context, List<Uint8List> jpegs, int firstId) async {
  final navigator = Navigator.of(context);
  var open = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: _PreparingDialog()),
  ).whenComplete(() => open = false));

  final prepared = await preparePages(jpegs, firstId);
  if (open && navigator.mounted) navigator.pop();
  return prepared;
}

Future<void> _openCamera(BuildContext context, {String? notice}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CaptureScreen(notice: notice),
      ),
    );

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
}

class _PreparingDialog extends StatelessWidget {
  const _PreparingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Preparing your pages…')),
        ],
      ),
    );
  }
}
