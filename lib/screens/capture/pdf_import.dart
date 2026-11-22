import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/scan_service.dart';
import '../../services/study_ai.dart';
import '../../theme/app_colors.dart';
import '../../utils/card_suggestions.dart';
import '../../utils/format.dart';
import '../../widgets/dialogs.dart';
import '../actions.dart' show cardsToAskFor, suggestionLimitNote;
import '../flashcards/set_screen.dart';
import '../note_viewer_screen.dart';
import 'captured_page.dart';
import 'notes_pdf.dart';
import 'pdf_text_stub.dart' if (dart.library.js_interop) 'pdf_text_web.dart'
    as pdf_text;
import 'review_screen.dart' show SaveFormat, SaveRequest, SaveSheet;

/// How many pages of an imported PDF are read (the rest of the file is still
/// kept when it's saved as a PDF).
const kPdfImportPageLimit = 30;

/// Imported PDFs larger than this are refused (they'd fill the phone's
/// storage and take minutes to read).
const kPdfImportMaxBytes = 60 * 1024 * 1024;

/// "Only the first 30 pages were read."
const kPdfPagesLeftOut =
    'Only the first $kPdfImportPageLimit pages were read.';

/// A PDF picked to import, with what was read from it.
class ImportedPdf {
  const ImportedPdf({
    required this.name,
    required this.bytes,
    required this.pages,
    required this.text,
    this.more = false,
  });

  /// The file name, e.g. "Lecture 7 - Photosynthesis.pdf".
  final String name;

  /// The PDF file itself.
  final Uint8List bytes;

  /// The pages read, as JPEGs (at most [kPdfImportPageLimit]).
  final List<Uint8List> pages;

  /// The text on those pages: the PDF's own text (web) or read from the
  /// pages on the phone, which works for scanned PDFs too.
  final String text;

  /// The PDF has more pages than were read.
  final bool more;

  /// The file name as a title: no ".pdf", underscores as spaces.
  String get title => pdfTitle(name);
}

/// "Lecture_7 - Photosynthesis.pdf" → "Lecture 7 - Photosynthesis".
String pdfTitle(String fileName) {
  var t = fileName.trim();
  if (t.toLowerCase().endsWith('.pdf')) t = t.substring(0, t.length - 4);
  t = t.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? 'Imported PDF' : t;
}

/// Picking, reading and rendering PDFs; each can be stood in for in tests.
class PdfImport {
  PdfImport._();

  /// Opens the file picker for one PDF. Null if none was picked.
  static Future<({String name, Uint8List bytes})?> Function() pick = _pick;

  /// Renders page [index] (from 0) of [pdf] as a JPEG; null past the last
  /// page. Throws if the PDF can't be opened.
  static Future<Uint8List?> Function(Uint8List pdf, int index) renderPage =
      _renderPage;

  /// True if [pdf] has a page [index] (from 0).
  static Future<bool> Function(Uint8List pdf, int index) hasPage = _hasPage;

  /// The PDF's own text (its text layer), pages separated by a blank line.
  /// Used where the phone can't read text from images (the web); empty
  /// for a scanned PDF.
  static Future<String> Function(Uint8List pdf, int maxPages) textLayer =
      pdf_text.pdfTextLayer;

  static Future<({String name, Uint8List bytes})?> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (files.isEmpty) return null;
    final file = files.first;
    return (name: file.name, bytes: await file.xFile.readAsBytes());
  }

  static Future<Uint8List?> _renderPage(Uint8List pdf, int index) async {
    final List<PdfRaster> rasters;
    try {
      rasters = await Printing.raster(pdf, pages: [index], dpi: 150).toList();
    } catch (e) {
      // Past the last page Android reports an error; the first page failing
      // means the PDF itself can't be opened.
      if (index == 0) rethrow;
      return null;
    }
    if (rasters.isEmpty) return null; // past the last page (iOS, web)
    final r = rasters.first;
    return compute(_toJpeg, (r.width, r.height, r.pixels));
  }

  static Future<bool> _hasPage(Uint8List pdf, int index) async {
    try {
      final rasters =
          await Printing.raster(pdf, pages: [index], dpi: 6).toList();
      return rasters.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// A rendered page (RGBA, transparent where the PDF draws nothing) as a
/// JPEG on white.
Uint8List _toJpeg((int, int, Uint8List) raster) {
  final (width, height, rgba) = raster;
  final page = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: Uint8List.fromList(rgba).buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final white = img.Image(width: width, height: height);
  img.fill(white, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(white, page);
  return Uint8List.fromList(img.encodeJpg(white, quality: 85));
}

/// Reads up to [kPdfImportPageLimit] pages of [pdf] as JPEGs and their text,
/// calling [onProgress] as it goes. Stops early when [cancel] is cancelled.
@visibleForTesting
Future<ImportedPdf> readPdf(
  String name,
  Uint8List pdf, {
  void Function(String status)? onProgress,
  CancelToken? cancel,
}) async {
  final pages = <Uint8List>[];
  for (var i = 0; i < kPdfImportPageLimit; i++) {
    if (cancel?.isCancelled ?? false) throw StudyAiException.cancelled;
    onProgress?.call('Opening page ${i + 1}…');
    final page = await PdfImport.renderPage(pdf, i);
    if (page == null) break;
    pages.add(page);
  }
  if (pages.isEmpty) throw const FormatException('The PDF has no pages.');
  final more = pages.length == kPdfImportPageLimit &&
      await PdfImport.hasPage(pdf, kPdfImportPageLimit);

  if (cancel?.isCancelled ?? false) throw StudyAiException.cancelled;
  final String text;
  if (ScanService.canReadText) {
    // On the phone every page is read as an image: slides and handouts
    // and scanned PDFs alike, without internet.
    onProgress?.call('Reading the text…');
    text = await ScanService.readText(pages);
  } else {
    onProgress?.call('Reading the text…');
    text = await PdfImport.textLayer(pdf, pages.length);
  }
  return ImportedPdf(name: name, bytes: pdf, pages: pages, text: text, more: more);
}

/// Picks a PDF and reads it, behind a progress dialog with Cancel. Null if
/// nothing was picked, it was cancelled, or it couldn't be read (a toast
/// says why).
Future<ImportedPdf?> pickAndReadPdf(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));

  final ({String name, Uint8List bytes})? picked;
  try {
    picked = await PdfImport.pick();
  } catch (e) {
    debugPrint('Could not open the file picker: $e');
    toast("Couldn't open your files.");
    return null;
  }
  if (picked == null || !context.mounted) return null;
  if (picked.bytes.length > kPdfImportMaxBytes) {
    toast('This PDF is too big to import (the limit is '
        '${kPdfImportMaxBytes ~/ (1024 * 1024)} MB).');
    return null;
  }

  final navigator = Navigator.of(context);
  final status = ValueNotifier('Opening your PDF…');
  final cancel = CancelToken();
  final onCancel = ValueNotifier<VoidCallback?>(cancel.cancel);
  var open = true;
  Route<Object?>? dialog;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      dialog ??= ModalRoute.of(dialogContext);
      return ProgressDialog(text: status, onCancel: onCancel);
    },
  ).whenComplete(() => open = false));
  try {
    await WidgetsBinding.instance.endOfFrame;
    final job = readPdf(picked.name, picked.bytes,
        onProgress: (s) => status.value = s, cancel: cancel);
    final done = await Future.any<ImportedPdf?>([
      job,
      cancel.whenCancelled.then((_) => null),
    ]);
    if (done == null) job.ignore();
    return done;
  } on StudyAiException {
    return null; // cancelled
  } catch (e, st) {
    debugPrint('Could not read the PDF: $e\n$st');
    toast("This PDF couldn't be opened. It may be damaged or "
        'protected with a password.');
    return null;
  } finally {
    if (open && navigator.mounted) closeDialog(navigator, dialog);
  }
}

/// Import PDF: pick a PDF (lecture slides, a handout, a scanned PDF) and
/// save it as Text Notes (to edit and make flashcards from), as the PDF
/// it is, or as flashcards.
Future<void> importPdf(BuildContext context) async {
  final pdf = await pickAndReadPdf(context);
  if (pdf == null || !context.mounted) return;
  final hasText = pdf.text.trim().isNotEmpty;
  final request = await showModalBottomSheet<SaveRequest>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SaveSheet(
      pageCount: pdf.pages.length,
      pdfName: pdf.name,
      pdfHasText: hasText,
      defaultTitle: pdf.title,
      notice: [
        if (pdf.more) kPdfPagesLeftOut,
        if (!hasText)
          ScanService.canReadText
              ? 'No text could be read from its pages.'
              : 'It may be scanned: scanned PDFs are read in the Android and '
                  'iOS apps.',
      ].join(' ').nullIfEmpty,
    ),
  );
  if (request == null || !context.mounted) return;
  await saveImportedPdf(context, pdf, request);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Saves [pdf] as [request] asks: Text Notes, the PDF itself or a
/// flashcard set (cards and a quiz from the study server when it's on,
/// otherwise cards suggested from the text).
@visibleForTesting
Future<void> saveImportedPdf(
    BuildContext context, ImportedPdf pdf, SaveRequest request) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final store = AppStore.instance;
  final asCards = request.format == SaveFormat.flashcards;
  final text = pdf.text;
  final progress = ValueNotifier<String>(
      asCards ? 'Preparing the pages…' : 'Saving your PDF…');
  final onCancel = ValueNotifier<VoidCallback?>(null);

  Route<Object?>? dialog;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      dialog ??= ModalRoute.of(dialogContext);
      return ProgressDialog(text: progress, onCancel: onCancel);
    },
  );

  void toast(String text, {SnackBarAction? action}) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      showCloseIcon: true,
      action: action,
      duration: Duration(seconds: text.length > 60 ? 8 : 4),
    ));
  String withPagesNote(String message) =>
      pdf.more ? '$message $kPdfPagesLeftOut' : message;

  StudyFolder? created;
  try {
    await WidgetsBinding.instance.endOfFrame;
    final left = store.suggestedCardsLeft;
    final cardsUsedUp = asCards && left == 0;
    StudyKit? kit;
    String? aiProblem;
    // The study server types the text up or writes cards and a quiz; a
    // plain "PDF" save keeps the file as it is and only needs the text.
    final wantsKit = request.format != SaveFormat.scanPdf;
    if (wantsKit && StudyAi.isOn && text.trim().length >= 20 && !cardsUsedUp) {
      progress.value =
          asCards ? 'Making your flashcards…' : 'Typing up your notes…';
      final cancel = CancelToken();
      onCancel.value = cancel.cancel;
      try {
        kit = await StudyAi.makeStudyKit(
          text: text,
          title: request.title,
          maxCards: asCards ? cardsToAskFor(left) : 0,
          quizCount: asCards ? 12 : 0,
          cancel: cancel,
        );
      } on StudyAiException catch (e) {
        aiProblem = e.isCancelled ? 'The AI step was skipped.' : e.message;
      } finally {
        onCancel.value = null;
      }
    }
    if (request.format == SaveFormat.textNotes &&
        text.trim().isEmpty &&
        (kit == null || kit.notes.trim().isEmpty)) {
      closeDialog(navigator, dialog);
      toast("No text was found in this PDF, so it can't be saved as Text "
          'Notes. Save it as a PDF instead.');
      return;
    }

    final folder = request.folder ??
        (created = store.addFolder('My Notes', AppColors.folderPalette.first));

    if (asCards) {
      final (kept: cards, dropped: droppedCards) =
          store.takeSuggestedCards(kit?.cards ?? const <Flashcard>[]);
      final (kept: suggestions, dropped: droppedSuggestions) =
          kit == null && !cardsUsedUp
              ? store.takeSuggestedCards(suggestCards(text))
              : (kept: const <Flashcard>[], dropped: 0);
      final ids = {for (final c in cards) c.id};
      final deck = await store.addSet(
        title: request.title,
        folderId: folder.id,
        photos: pdf.pages,
        cards: cards,
        suggestions: suggestions,
        sourceText: text,
        summary: kit?.summary ?? '',
        concepts: kit?.concepts ?? const [],
        quiz: [
          for (final q in kit?.quiz ?? const <QuizQuestion>[])
            if (q.cardId == null || ids.contains(q.cardId)) q,
        ],
      );
      navigator.popUntil((route) => route.isFirst);
      navigator.push(MaterialPageRoute(builder: (_) => SetScreen(setId: deck.id)));
      var message = cardsUsedUp
          ? 'PDF imported. Write cards for its pages yourself.'
          : kit != null
              ? 'PDF imported with ${plural(cards.length, 'flashcard')} made '
                  'for you.'
              : aiProblem != null
                  ? '$aiProblem Cards were suggested from the text instead.'
                  : text.trim().isEmpty
                      ? 'PDF imported. Now add cards for its pages.'
                      : suggestions.isEmpty
                          ? 'PDF imported. No cards were found in the text; '
                              'add them yourself.'
                          : 'PDF imported. We found '
                              '${plural(suggestions.length, 'card')} to suggest.';
      if (cardsUsedUp || droppedCards + droppedSuggestions > 0) {
        message = '$message $suggestionLimitNote';
      }
      toast(withPagesNote(message));
      return;
    }

    // The PDF as it is, every page of it; Text Notes keep it as their
    // original pages.
    final textNotes = request.format == SaveFormat.textNotes;
    progress.value = textNotes ? 'Saving your notes…' : 'Saving your PDF…';
    final file = pdf.bytes;
    final counted = pdfPageCount(file);
    final pageCount = pdf.more
        ? (counted > pdf.pages.length ? counted : pdf.pages.length + 1)
        : pdf.pages.length;
    final thumb = await CapturedPage.thumbnail(pdf.pages.first);
    final note = await store.addNote(
      title: request.title,
      folderId: folder.id,
      pdf: file,
      thumbnail: thumb,
      pageCount: pageCount,
      text: text,
      cleanText: kit?.notes ?? '',
      summary: kit?.summary ?? '',
      concepts: kit?.concepts ?? const [],
      textNote: textNotes,
    );

    navigator.popUntil((route) => route.isFirst);
    if (textNotes) {
      // Straight to the text, to check it and make flashcards from it.
      navigator.push(
          MaterialPageRoute(builder: (_) => NoteTextScreen(noteId: note.id)));
      toast(withPagesNote(aiProblem == null
          ? 'Saved to ${folder.name}'
          : 'Saved to ${folder.name}. $aiProblem'));
      return;
    }
    toast(
      withPagesNote(aiProblem == null
          ? 'Saved to ${folder.name}'
          : 'Saved to ${folder.name}. $aiProblem'),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => navigator.push(
          MaterialPageRoute(builder: (_) => NoteViewerScreen(noteId: note.id)),
        ),
      ),
    );
  } catch (e, st) {
    debugPrint('Importing the PDF failed: $e\n$st');
    if (created != null &&
        store.noteCountIn(created.id) == 0 &&
        store.setCountIn(created.id) == 0) {
      store.deleteFolder(created.id).ignore();
    }
    closeDialog(navigator, dialog);
    toast("Couldn't import the PDF. Please try again.");
  }
}
