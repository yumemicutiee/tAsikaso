import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_store.dart';
import '../../data/plans.dart';
import '../../models/models.dart';
import '../../services/scan_service.dart';
import '../../services/study_ai.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/choices.dart';
import '../../widgets/dialogs.dart';
import '../note_viewer_screen.dart';
import 'captured_page.dart';
import 'notes_pdf.dart';
import 'reading_screen.dart';

/// Review captured pages: rotate and crop each one by dragging its four
/// corners. Next reads their text ([ReadingScreen]), then they're saved as
/// Text Notes in the folder picked.
///
/// Pops with the remaining pages when the user goes back to take more.
///
/// When the pages came from the phone's document scanner, [addMore] scans
/// more pages instead (there is no camera screen underneath to go back to).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.pages,
    this.autoCropped = false,
    this.addMore,
    this.notice,
  });

  final List<CapturedPage> pages;

  /// Something to know about the pages (e.g. some couldn't be read), shown
  /// above the tools; a toast would cover them.
  final String? notice;

  /// The scanner already found the page edges; crop stays optional.
  final bool autoCropped;

  /// Scans more pages; called with the first free page id.
  final Future<List<CapturedPage>?> Function(int firstId)? addMore;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<CapturedPage> _pages = List.of(widget.pages);
  int _current = 0;

  CapturedPage get _page => _pages[_current];

  bool get _fromScanner => widget.addMore != null;

  Future<void> _addMore() async {
    final nextId =
        _pages.fold<int>(0, (m, p) => p.id > m ? p.id : m) + 1;
    try {
      final more = await widget.addMore!(nextId);
      if (!mounted || more == null || more.isEmpty) return;
      setState(() {
        _current = _pages.length;
        _pages.addAll(more);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Couldn't open the scanner.")));
    }
  }

  /// Leaving the scanner flow throws the pages away, so ask first.
  Future<void> _leave() async {
    if (!_fromScanner) {
      Navigator.of(context).pop(_pages);
      return;
    }
    final discard = await showConfirmDialog(
      context,
      title: 'Discard Pages?',
      message: 'The ${plural(_pages.length, 'page')} you scanned will not be saved.',
      confirmLabel: 'Discard',
    );
    if (!discard || !mounted) return;
    Navigator.of(context).pop(_pages);
  }

  void _deletePage() {
    if (_pages.length == 1) {
      if (_fromScanner) {
        _leave(); // asks before throwing the scan away
      } else {
        Navigator.of(context).pop(<CapturedPage>[]);
      }
      return;
    }
    setState(() {
      _pages.removeAt(_current);
      _current = math.min(_current, _pages.length - 1);
    });
  }

  /// The pages as last read; read again if they were changed since.
  ReadPages? _read;

  /// Next: the pages are cropped and their text read (on the reading
  /// screen), then the save sheet shows what was read.
  Future<void> _openSaveSheet() async {
    var read = _read;
    if (read == null || read.key != readKey(_pages)) {
      read = await ReadingScreen.read(context, _pages);
      if (read == null || !mounted) return;
      _read = read;
    }
    final request = await showModalBottomSheet<SaveRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaveSheet(pageCount: _pages.length, read: read),
    );
    if (request == null || !mounted) return;
    await _save(request, read);
  }

  /// Saves the pages as Text Notes in the folder picked, then opens them
  /// on their text. With Smart Study on, the text is typed up first.
  Future<void> _save(SaveRequest request, ReadPages read) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final store = AppStore.instance;
    final progress = ValueNotifier<String>('Saving your notes…');
    // Cancel is offered while the study server works (the one long wait).
    // It skips the AI step; the notes are still saved.
    final onCancel = ValueNotifier<VoidCallback?>(null);

    Route<Object?>? dialog; // to close this one, not one opened on top
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialog ??= ModalRoute.of(dialogContext);
        return ProgressDialog(text: progress, onCancel: onCancel);
      },
    );

    void toast(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        showCloseIcon: true,
        duration: Duration(seconds: text.length > 60 ? 8 : 4),
      ));

    StudyFolder? created; // "My Notes", made for this save alone
    try {
      // Let the progress dialog appear before the work starts.
      await WidgetsBinding.instance.endOfFrame;
      // Cropped and read on the reading screen (on the phone, no
      // internet).
      final jpegs = read.jpegs;
      final pages = read.pages;
      final text = read.text;

      // The study server (Claude) types the notes up and picks out key
      // concepts. Cards are made later, from the note.
      StudyKit? kit;
      String? aiProblem;
      if (StudyAi.isOn && text.trim().length >= 20) {
        progress.value = 'Typing up your notes…';
        final cancel = CancelToken();
        onCancel.value = cancel.cancel;
        try {
          kit = await StudyAi.makeStudyKit(
            text: text,
            title: request.title,
            maxCards: 0,
            quizCount: 0,
            cancel: cancel,
          );
        } on StudyAiException catch (e) {
          // Cancelled: saved as if the server couldn't be reached.
          aiProblem = e.isCancelled ? 'The AI step was skipped.' : e.message;
        } finally {
          onCancel.value = null;
        }
      }

      final folder = request.folder ??
          (created = store.addFolder('My Notes', AppColors.folderPalette.first));
      final title = switch (kit?.title.trim()) {
        final t? when t.isNotEmpty && t.length <= 60 => t,
        _ => titleFromText(text) ?? request.title,
      };

      // The photos are kept with the text (selectable in them), so the
      // original pages are one tap away.
      progress.value = 'Saving your notes…';
      final pdf = await buildNotesPdf(jpegs, title: title, text: pages);
      final thumb = await CapturedPage.thumbnail(jpegs.first);
      final note = await store.addNote(
        title: title,
        folderId: folder.id,
        pdf: pdf,
        thumbnail: thumb,
        pageCount: jpegs.length,
        text: text,
        cleanText: kit?.notes ?? '',
        summary: kit?.summary ?? '',
        concepts: kit?.concepts ?? const [],
        textNote: true,
      );

      // Straight to the text, to check it and make flashcards from it.
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
          MaterialPageRoute(builder: (_) => NoteTextScreen(noteId: note.id)));
      toast(aiProblem == null
          ? 'Saved to ${folder.name}'
          : 'Saved to ${folder.name}. $aiProblem');
    } catch (e, st) {
      debugPrint('Saving the notes failed: $e\n$st');
      // Don't leave an empty folder behind for a save that didn't happen.
      if (created != null &&
          store.noteCountIn(created.id) == 0 &&
          store.setCountIn(created.id) == 0) {
        store.deleteFolder(created.id).ignore();
      }
      closeDialog(navigator, dialog); // progress dialog
      toast("Couldn't save your notes. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final multi = _pages.length > 1;

    return PopScope<List<CapturedPage>>(
      // System back should also hand the remaining pages back to the camera.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.cameraBackground,
          body: SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _leave,
                        icon: const Icon(AppIcons.back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          multi
                              ? 'Page ${_current + 1} of ${_pages.length}'
                              : (widget.autoCropped ? 'Check Page' : 'Crop Page'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: _openSaveSheet,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onFill,
                        ),
                        child: const Text('Next',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

                // Crop editor
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: CropEditor(
                      key: ValueKey(_page.id),
                      page: _page,
                      onChanged: (c) => setState(() => _page.corners = c),
                    ),
                  ),
                ),
                if (widget.notice case final notice?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      notice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.accent, fontSize: 11),
                    ),
                  ),
                if (_page.autoDetected && !widget.autoCropped)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      "Page edges found. Drag the corners if they're off.",
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),

                // Page strip
                if (multi)
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: _pages.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => setState(() => _current = i),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: i == _current ? AppColors.accent : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: RotatedBox(
                              quarterTurns: _pages[i].quarterTurns,
                              child: Image.memory(
                                _pages[i].bytes,
                                fit: BoxFit.cover,
                                cacheWidth: 120,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Tools
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolButton(
                        icon: AppIcons.rotate,
                        label: 'Rotate',
                        onPressed: () => setState(_page.rotateClockwise),
                      ),
                      _ToolButton(
                        icon: AppIcons.resetCrop,
                        label: 'Reset',
                        onPressed: () => setState(_page.resetCrop),
                      ),
                      _ToolButton(
                        icon: AppIcons.addPhoto,
                        label: multi || _fromScanner ? 'Add More' : 'Retake',
                        onPressed: _fromScanner
                            ? _addMore
                            : () => Navigator.of(context)
                                .pop(multi ? _pages : <CapturedPage>[]),
                      ),
                      _ToolButton(
                        icon: AppIcons.delete,
                        label: 'Delete',
                        onPressed: _deletePage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a page photo with a draggable four-corner crop frame. Four free
/// corners (not a rectangle) so a board photographed at an angle can be
/// straightened when it's saved.
class CropEditor extends StatelessWidget {
  const CropEditor({super.key, required this.page, required this.onChanged});

  final CapturedPage page;

  /// Called with new corners (fractions of the displayed image).
  final ValueChanged<List<Offset>> onChanged;

  static const double _handle = 28;

  @override
  Widget build(BuildContext context) {
    final corners = page.corners;
    final aspect = page.displayAspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit the (rotated) photo inside the available space, leaving room
        // for the handles that sit on its edges.
        final maxW = math.max(1.0, constraints.maxWidth - _handle);
        final maxH = math.max(1.0, constraints.maxHeight - _handle);
        var w = maxW;
        var h = w / aspect;
        if (h > maxH) {
          h = maxH;
          w = h * aspect;
        }

        // The box is one handle larger than the photo so the handles, which
        // sit on the photo's edges, are fully inside it and fully tappable.
        const inset = _handle / 2;
        return Center(
          child: SizedBox(
            width: w + _handle,
            height: h + _handle,
            child: Stack(
              children: [
                Positioned(
                  left: inset,
                  top: inset,
                  width: w,
                  height: h,
                  child: RotatedBox(
                    quarterTurns: page.quarterTurns,
                    child: Image.memory(
                      page.bytes,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  left: inset,
                  top: inset,
                  width: w,
                  height: h,
                  child: CustomPaint(painter: _CropOverlayPainter(corners)),
                ),
                for (var i = 0; i < corners.length; i++)
                  Positioned(
                    left: corners[i].dx * w,
                    top: corners[i].dy * h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        final moved = page.corners[i] +
                            Offset(d.delta.dx / w, d.delta.dy / h);
                        final updated = List<Offset>.of(page.corners);
                        updated[i] = CapturedPage.constrainCorner(
                            page.corners, i, moved);
                        onChanged(updated);
                      },
                      child: Container(
                        width: _handle,
                        height: _handle,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.accent, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter(this.corners);

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final c in corners) Offset(c.dx * size.width, c.dy * size.height),
    ];
    final quad = Path()..addPolygon(pts, true);

    // Dim everything outside the crop area.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      quad,
    );
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      quad,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.corners != corners;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Expanded so the four tools share the row evenly on narrow screens.
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text Notes: the text read from the pages (typed up with Smart Study),
/// to edit and make flashcards from, with the pages kept. Flashcards: a set
/// with the photos (or the PDF's pages) to write cards from. For an
/// imported PDF only, [scanPdf] keeps the PDF as it is.
enum SaveFormat { textNotes, scanPdf, flashcards }

class SaveRequest {
  const SaveRequest({
    required this.title,
    required this.folder,
    required this.format,
  });

  final String title;

  /// Null when the user has no folders yet ("My Notes" is created).
  final StudyFolder? folder;
  final SaveFormat format;
}

/// Bottom sheet. For scanned pages, after their text was [read]: only the
/// folder (they're saved as Text Notes). For an imported PDF ([pdfName]):
/// Text Notes, the PDF as it is or Flashcards, a title and a folder.
class SaveSheet extends StatefulWidget {
  const SaveSheet({
    super.key,
    required this.pageCount,
    this.read,
    this.pdfName,
    this.pdfHasText = false,
    this.defaultTitle,
    this.notice,
  });

  final int pageCount;

  /// Scanned pages: what was read from them.
  final ReadPages? read;

  /// The imported PDF's file name; null for scanned pages.
  final String? pdfName;

  /// Text was found in the imported PDF.
  final bool pdfHasText;

  /// The title used when none is typed; null: "{Folder} Notes {date}".
  final String? defaultTitle;

  /// Something to know, shown under the title (e.g. not every page was read).
  final String? notice;

  @override
  State<SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<SaveSheet> {
  final List<StudyFolder> _folders = [...AppStore.instance.recentFolders(1000)];
  late StudyFolder? _folder = _folders.isEmpty ? null : _folders.first;

  /// Creates a folder right here and selects it.
  Future<void> _newFolder() async {
    final folder = await createFolderHere(context);
    if (folder == null || !mounted) return;
    setState(() {
      _folders.insert(0, folder);
      _folder = folder;
    });
  }
  // Scanned pages are always Text Notes. A PDF: Text Notes first when it
  // has text, otherwise the PDF as it is.
  late SaveFormat _format = _canReadText || widget.read != null
      ? SaveFormat.textNotes
      : widget.pdfName != null
          ? SaveFormat.scanPdf
          : SaveFormat.flashcards;
  final _title = TextEditingController();

  /// Whether there is text: read from the scanned pages, or in the PDF.
  bool get _canReadText => widget.pdfName != null
      ? widget.pdfHasText
      : widget.read != null
          ? widget.read!.text.trim().isNotEmpty
          : ScanService.canReadText;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _defaultTitle() {
    if (widget.defaultTitle case final title?) return title;
    final name = _folder?.name ?? 'My';
    final kind = _format == SaveFormat.flashcards ? 'Cards' : 'Notes';
    return '$name $kind ${formatNoteDate(DateTime.now())}';
  }

  void _submit() {
    final typed = _title.text.trim();
    Navigator.of(context).pop(SaveRequest(
      title: typed.isEmpty ? _defaultTitle() : typed,
      folder: _folder,
      format: _format,
    ));
  }

  /// Scanned pages: only where they go. They're saved as Text Notes,
  /// titled from their text (renamed from the note's menu).
  Widget _buildForPages(BuildContext context, ReadPages read) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle(
              'Save Notes',
              subtitle: [
                plural(widget.pageCount, 'page'),
                if (read.text.trim().isEmpty)
                  ScanService.canReadText
                      ? 'no text found'
                      : 'text is read in the phone app',
              ].join(' · '),
            ),
            const SizedBox(height: 18),
            FolderField(
              folders: _folders,
              folder: _folder,
              onChanged: (f) => setState(() => _folder = f),
              onNewFolder: _newFolder,
              helper: "Saved in the folder's Notebook",
            ),
            const SizedBox(height: 20),
            AccentButton(label: 'Save Notes', onPressed: _submit),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.read case final read?) return _buildForPages(context, read);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final fromPdf = widget.pdfName != null;
    final canReadText = _canReadText;
    final ai = StudyAi.isOn;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle(
              fromPdf ? 'Import PDF' : 'Save Notes As',
              subtitle: [
                plural(widget.pageCount, 'page'),
                if (fromPdf && !canReadText) 'no text found',
              ].join(' · '),
            ),
            if (widget.notice case final notice?) ...[
              const SizedBox(height: 6),
              Text(notice, style: AppText.itemMeta),
            ],
            const SizedBox(height: 14),
            FormatOption(
              icon: AppIcons.text,
              title: 'Text Notes',
              subtitle: !canReadText
                  ? (fromPdf
                      ? 'No text was found in this PDF'
                      : ScanService.canReadText
                          ? 'No text was found on these pages'
                          : 'Needs text recognition (Android or iOS)')
                  : ai
                      ? 'Typed up cleanly with key concepts, to edit and '
                          'turn into flashcards'
                      : (fromPdf
                          ? 'The text of your PDF, to edit and turn into '
                              'flashcards'
                          : 'Your notes as text, to edit and turn into '
                              'flashcards'),
              selected: _format == SaveFormat.textNotes,
              enabled: canReadText,
              onTap: () => setState(() => _format = SaveFormat.textNotes),
            ),
            if (fromPdf) ...[
              const SizedBox(height: 8),
              FormatOption(
                icon: AppIcons.pdf,
                title: 'PDF',
                subtitle: canReadText
                    ? 'Your PDF as it is; its text can be searched'
                    : 'Your PDF as it is',
                selected: _format == SaveFormat.scanPdf,
                onTap: () => setState(() => _format = SaveFormat.scanPdf),
              ),
            ],
            const SizedBox(height: 8),
            FormatOption(
              icon: AppIcons.flashcards,
              title: 'Flashcards',
              subtitle: (ai && canReadText
                      ? (fromPdf
                          ? 'Cards and a quiz made from your PDF'
                          : 'Cards and a quiz made from your notes')
                      : fromPdf
                          ? (canReadText
                              ? 'Cards suggested from its text'
                              : 'Write cards while looking at its pages')
                          : 'Write cards while looking at your photos') +
                  // Where no text is read (the web), no cards are
                  // suggested, so the monthly allowance doesn't apply.
                  switch (canReadText ? AppStore.instance.suggestedCardsLeft : null) {
                    null => '',
                    0 => " · this month's suggested cards are used up",
                    final left =>
                      ' · $left of $kFreeSuggestedCardsPerMonth suggested cards left this month',
                  },
              selected: _format == SaveFormat.flashcards,
              onTap: () => setState(() => _format = SaveFormat.flashcards),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: _defaultTitle(),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            FolderField(
              folders: _folders,
              folder: _folder,
              onChanged: (f) => setState(() => _folder = f),
              onNewFolder: _newFolder,
              helper: _format == SaveFormat.flashcards
                  ? null
                  : "Saved in the folder's Notebook",
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: switch (_format) {
                SaveFormat.textNotes => 'Save as Notes',
                SaveFormat.scanPdf => 'Save PDF',
                SaveFormat.flashcards => 'Make Flashcards',
              },
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// A title from the first line of [text] when it reads like one (a heading
/// such as "Photosynthesis - Lecture 7"), else null.
String? titleFromText(String text) {
  for (final raw in text.split('\n')) {
    final line = raw
        .replaceFirst(RegExp(r'^[#\-•*\s]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(line).length;
    return line.length <= 60 && letters >= 3 ? line : null;
  }
  return null;
}
