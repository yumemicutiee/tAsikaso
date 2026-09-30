import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

// Phones (and the test VM, where both report unavailable).

/// ML Kit's document scanner exists on Android only.
bool get canScanDocuments => Platform.isAndroid;

bool get canReadText => Platform.isAndroid || Platform.isIOS;

Future<List<Uint8List>?> scanDocuments(int pageLimit) async {
  final scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      pageLimit: pageLimit,
      mode: ScannerMode.full, // auto-crop, filters, clean-up
      isGalleryImport: true,
    ),
  );
  try {
    final result = await scanner.scanDocument();
    final paths = result.images ?? const <String>[];
    if (paths.isEmpty) return null;
    final pages = <Uint8List>[];
    for (final path in paths) {
      final file = File(path);
      pages.add(await file.readAsBytes());
      try {
        await file.delete();
      } catch (_) {
        // It's in the cache folder; Android cleans it up eventually.
      }
    }
    return pages;
  } on PlatformException catch (e) {
    // Backing out of the scanner is reported as an error.
    if ((e.message ?? '').toLowerCase().contains('cancel')) return null;
    rethrow;
  } finally {
    await scanner.close();
  }
}

Future<String> readText(List<Uint8List> jpegs) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final out = StringBuffer();
  try {
    for (var i = 0; i < jpegs.length; i++) {
      // ML Kit reads JPEGs from a file (raw bytes must be camera frames).
      final file = File('${dir.path}/ocr_${stamp}_$i.jpg');
      await file.writeAsBytes(jpegs[i], flush: true);
      try {
        final result =
            await recognizer.processImage(InputImage.fromFilePath(file.path));
        final text = result.text.trim();
        if (text.isNotEmpty) {
          if (out.isNotEmpty) out.write('\n\n');
          out.write(text);
        }
      } finally {
        try {
          await file.delete();
        } catch (_) {
          // Temporary file; the OS clears it eventually.
        }
      }
    }
  } finally {
    await recognizer.close();
  }
  return out.toString();
}
