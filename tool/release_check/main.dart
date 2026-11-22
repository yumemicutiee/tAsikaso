// A release build of this file checks text recognition the way the
// published APK runs it (shrunk by R8, release mode), on an emulator. See
// .github/workflows/release-check.yml. Every result goes to the log as a
// line starting with RELEASECHECK.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:study_app/screens/capture/pdf_import.dart';
import 'package:study_app/services/scan_service_mlkit.dart' as mlkit;
import 'package:study_app/services/study_ai.dart';

void say(String line) => debugPrint('RELEASECHECK $line');

/// A photo of a page of notes: dark lines on white.
Uint8List notesPhoto(List<String> lines) {
  final page = img.Image(width: 1400, height: 900);
  img.fill(page, color: img.ColorRgb8(250, 250, 248));
  for (final (i, line) in lines.indexed) {
    img.drawString(page, line,
        font: img.arial48, x: 80, y: 120 + i * 110, color: img.ColorRgb8(20, 20, 30));
  }
  return Uint8List.fromList(img.encodeJpg(page, quality: 90));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Release check running…')))));
  await Future<void>.delayed(const Duration(seconds: 2));
  say('start');
  say('study server built in: ${StudyAi.hasServer}');

  // 1. Text recognition on a photo, called directly so errors show.
  try {
    final pages = await mlkit.readPages([
      notesPhoto(['OSMOSIS: water across a membrane', 'DIFFUSION: particles spread']),
    ]);
    final text = pages.map((p) => p.lines.map((l) => l.text).join(' / ')).join(' | ');
    say('photo ok: "$text"');
  } catch (e, st) {
    say('photo FAILED: $e');
    say('photo stack: $st');
  }

  // 2. An imported PDF: its pages drawn as images, then read.
  try {
    final doc = pw.Document()
      ..addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(children: [
          pw.Text('MITOSIS: cell division', style: const pw.TextStyle(fontSize: 28)),
          pw.Text('RIBOSOMES make proteins', style: const pw.TextStyle(fontSize: 28)),
        ]),
      ));
    final bytes = await doc.save();
    final pdf = await readPdf('check.pdf', bytes);
    say('pdf pages: ${pdf.pages.length}, text: "${pdf.text.replaceAll('\n', ' / ')}"');
  } catch (e, st) {
    say('pdf FAILED: $e');
    say('pdf stack: $st');
  }
  say('done');
}
