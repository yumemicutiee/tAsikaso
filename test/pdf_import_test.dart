import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/screens/capture/pdf_import.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';

/// Lines like the ones on lecture slides, "Term: definition".
const slideText = 'Osmosis: movement of water across a membrane\n'
    'Diffusion: particles spreading out';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  final pdfBytes = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));

  late Uint8List pageJpeg;
  setUpAll(() {
    final page = img.Image(width: 60, height: 80);
    img.fill(page, color: img.ColorRgb8(250, 250, 250));
    pageJpeg = Uint8List.fromList(img.encodeJpg(page));
  });

  /// A PDF of [pages] pages, whose text layer is [text].
  void pdfWith(int pages, {String text = '', String name = 'Lecture_7 - Cells.pdf'}) {
    PdfImport.pick = () async => (name: name, bytes: pdfBytes);
    PdfImport.renderPage = (_, i) async => i < pages ? pageJpeg : null;
    PdfImport.hasPage = (_, i) async => i < pages;
    PdfImport.textLayer = (_, _) async => text;
  }

  /// Text recognition (the phone) reads [text] off every page.
  void phoneReads(String text) {
    ScanService.debugRead = (jpegs) async => [
          for (final _ in jpegs)
            RecognizedPage(lines: [
              for (final (i, line) in text.split('\n').indexed)
                RecognizedLine(
                    text: line, left: 0, top: i * 20.0, right: 200, bottom: i * 20.0 + 16),
            ]),
        ];
  }

  setUp(() {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    ScanService.debugRead = null;
    StudyAi.debugClient = null;
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Saving makes a thumbnail in another isolate, so wait in real time.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 150 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  /// A screen with an "Import PDF" button, as in the + menu.
  Future<void> openImport(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => importPdf(context),
              child: const Text('Import PDF'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Import PDF'));
    await tester.pump();
    await waitFor(tester, () => find.text('Make Flashcards').evaluate().isNotEmpty ||
        find.text('Save PDF').evaluate().isNotEmpty);
  }

  group('A PDF file name as a title', () {
    test('drops .pdf and underscores', () {
      expect(pdfTitle('Lecture_7 - Cells.pdf'), 'Lecture 7 - Cells');
      expect(pdfTitle('notes.PDF'), 'notes');
      expect(pdfTitle('  .pdf'), 'Imported PDF');
    });
  });

  group('Reading a PDF', () {
    test('reads at most the page limit and says there were more', () async {
      pdfWith(kPdfImportPageLimit + 5, text: slideText);
      final pdf = await readPdf('big.pdf', pdfBytes);
      expect(pdf.pages, hasLength(kPdfImportPageLimit));
      expect(pdf.more, isTrue);
    });

    test('a short PDF is read whole', () async {
      pdfWith(3, text: slideText);
      final pdf = await readPdf('short.pdf', pdfBytes);
      expect(pdf.pages, hasLength(3));
      expect(pdf.more, isFalse);
      // No text recognition here (as on the web): the PDF's own text.
      expect(pdf.text, slideText);
    });

    test('on a phone every page is read as an image, so scanned PDFs work',
        () async {
      pdfWith(2); // a scanned PDF: no text layer
      phoneReads('Mitosis: cell division');
      final pdf = await readPdf('scan.pdf', pdfBytes);
      expect(pdf.text, 'Mitosis: cell division\n\nMitosis: cell division');
    });

    test('a PDF that cannot be opened throws', () async {
      pdfWith(0);
      expect(readPdf('empty.pdf', pdfBytes), throwsFormatException);
    });
  });

  group('Import PDF', () {
    testWidgets('saves the PDF as it is, titled after the file', (tester) async {
      pdfWith(2, text: slideText);
      await openImport(tester);
      expect(find.text('Import PDF'), findsWidgets);
      expect(find.text('2 pages'), findsOneWidget);
      await tester.tap(find.text('Save PDF'));
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);

      final note = store.notes.single;
      expect(note.title, 'Lecture 7 - Cells');
      expect(note.text, slideText);
      expect(note.pageCount, 2);
      expect(await store.readPdf(note), pdfBytes);
      expect(find.textContaining('Saved to'), findsOneWidget);
    });

    testWidgets('as flashcards without the study server, cards are suggested '
        'from the text and the pages kept', (tester) async {
      pdfWith(3, text: slideText);
      await openImport(tester);
      await tester.tap(find.text('Flashcards'));
      await tester.pump();
      expect(find.textContaining('Cards suggested from its text'), findsOneWidget);
      await tester.tap(find.text('Make Flashcards'));
      await tester.pump();
      await waitFor(tester, () => store.sets.isNotEmpty);

      final deck = store.sets.single;
      expect(deck.title, 'Lecture 7 - Cells');
      expect(deck.photoCount, 3);
      expect(deck.sourceText, slideText);
      expect(deck.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(find.byType(SetScreen), findsOneWidget);
      expect(find.textContaining('We found 2 cards to suggest'), findsOneWidget);
    });

    testWidgets('a PDF without text can still be kept, but not typed up',
        (tester) async {
      pdfWith(1); // scanned, read where there's no text recognition
      await openImport(tester);
      expect(find.text('1 page · no text found'), findsOneWidget);
      expect(find.text('No text was found in this PDF'), findsOneWidget);
      expect(find.textContaining('scanned PDFs are read in the Android'), findsOneWidget);
      await tester.tap(find.text('Save PDF'));
      await tester.pump();
      await waitFor(tester, () => store.notes.isNotEmpty);
      expect(store.notes.single.text, '');
    });

    testWidgets('says when only the first pages were read', (tester) async {
      pdfWith(kPdfImportPageLimit + 1, text: slideText);
      await openImport(tester);
      expect(find.textContaining(kPdfPagesLeftOut), findsOneWidget);
    });
  });

  group('Make Cards from a PDF', () {
    testWidgets("adds cards suggested from the PDF's text to a set",
        (tester) async {
      usePhoneSize(tester);
      pdfWith(2, text: slideText);
      final deck = await store.addSet(
          title: 'Cells', folderId: store.folders.first.id, sourceText: 'Old: text');
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.byTooltip('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Cards from a PDF'));
      await tester.pump();
      await waitFor(tester,
          () => store.setById(deck.id)!.suggestions.isNotEmpty);

      final saved = store.setById(deck.id)!;
      expect(saved.suggestions.map((c) => c.front), ['Osmosis', 'Diffusion']);
      expect(saved.sourceText, 'Old: text\n\n$slideText');
      expect(find.text('2 cards suggested from the text.'), findsOneWidget);
    });
  });
}
