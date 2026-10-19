import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/scan_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/card_suggestions.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../flashcards/set_screen.dart';
import '../note_viewer_screen.dart';
import 'captured_page.dart';
import 'notes_pdf.dart';

/// Review captured pages: rotate and crop each one by dragging its four
/// corners, then save them as a PDF in a folder.
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
  });

  final List<CapturedPage> pages;

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

  Future<void> _openSaveSheet() async {
    final request = await showModalBottomSheet<_SaveRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SaveSheet(pageCount: _pages.length),
    );
    if (request == null || !mounted) return;
    await _save(request);
  }

  Future<void> _save(_SaveRequest request) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final store = AppStore.instance;
    final asCards = request.format == _SaveFormat.flashcards;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(
        text: asCards ? 'Preparing your photos…' : 'Creating your PDF…',
      ),
    );

    try {
      // Let the progress dialog appear before the image work starts
      // (on web the work runs on the UI thread).
      await WidgetsBinding.instance.endOfFrame;
      final jpegs = <Uint8List>[];
      for (final page in _pages) {
        jpegs.add(await page.render());
        await WidgetsBinding.instance.endOfFrame;
      }

      // Read the text on the pages (on the phone, no internet). Used for
      // search, "View Text" and suggested flashcards.
      final text = await ScanService.readText(jpegs);

      final folder = request.folder ??
          store.addFolder('My Notes', AppColors.folderPalette.first);

      if (asCards) {
        final suggestions = suggestCards(text);
        final deck = await store.addSet(
          title: request.title,
          folderId: folder.id,
          photos: jpegs,
          suggestions: suggestions,
        );
        // Close the progress dialog, review and camera, then open the set so
        // cards can be written while looking at the photos.
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute(builder: (_) => SetScreen(setId: deck.id)));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(suggestions.isEmpty
                ? 'Photos saved. Now add cards for them.'
                : 'Photos saved. We found ${plural(suggestions.length, 'card')} '
                    'to suggest.'),
            showCloseIcon: true,
          ));
        return;
      }

      final pdf = await buildNotesPdf(jpegs, title: request.title);
      final thumb = await CapturedPage.thumbnail(jpegs.first);
      final note = await store.addNote(
        title: request.title,
        folderId: folder.id,
        pdf: pdf,
        thumbnail: thumb,
        pageCount: jpegs.length,
        text: text,
      );

      navigator.popUntil((route) => route.isFirst);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Saved to ${folder.name}'),
            showCloseIcon: true,
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => navigator.push(
                MaterialPageRoute(builder: (_) => NoteViewerScreen(noteId: note.id)),
              ),
            ),
          ),
        );
    } catch (_) {
      navigator.pop(); // progress dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text(asCards
              ? "Couldn't save the photos. Please try again."
              : "Couldn't create the PDF. Please try again."),
        ),
      );
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
                        updated[i] = Offset(
                          math.min(1.0, math.max(0.0, moved.dx)),
                          math.min(1.0, math.max(0.0, moved.dy)),
                        );
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

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.primaryDeep),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(text, style: AppText.itemTitle)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SaveFormat { pdf, flashcards }

class _SaveRequest {
  const _SaveRequest({
    required this.title,
    required this.folder,
    required this.format,
  });

  final String title;

  /// Null when the user has no folders yet ("My Notes" is created).
  final StudyFolder? folder;
  final _SaveFormat format;
}

/// Bottom sheet: PDF or Flashcards, a title, and a folder.
class _SaveSheet extends StatefulWidget {
  const _SaveSheet({required this.pageCount});

  final int pageCount;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  final List<StudyFolder> _folders = [...AppStore.instance.recentFolders(1000)];
  late StudyFolder? _folder = _folders.isEmpty ? null : _folders.first;

  /// Creates a folder right here and selects it.
  Future<void> _newFolder() async {
    final draft = await showFolderEditor(context);
    if (draft == null || !mounted) return;
    final folder = AppStore.instance.addFolder(draft.name, draft.colorValue);
    setState(() {
      _folders.insert(0, folder);
      _folder = folder;
    });
  }
  _SaveFormat _format = _SaveFormat.pdf;
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _defaultTitle() {
    final name = _folder?.name ?? 'My';
    final kind = _format == _SaveFormat.pdf ? 'Notes' : 'Cards';
    return '$name $kind ${formatNoteDate(DateTime.now())}';
  }

  void _submit() {
    final typed = _title.text.trim();
    Navigator.of(context).pop(_SaveRequest(
      title: typed.isEmpty ? _defaultTitle() : typed,
      folder: _folder,
      format: _format,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pdf = _format == _SaveFormat.pdf;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle('Save Notes As', subtitle: plural(widget.pageCount, 'page')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _FormatOption(
                    icon: AppIcons.pdf,
                    title: 'PDF',
                    subtitle: 'All pages in one file',
                    selected: pdf,
                    onTap: () => setState(() => _format = _SaveFormat.pdf),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormatOption(
                    icon: AppIcons.flashcards,
                    title: 'Flashcards',
                    subtitle: 'Write cards from photos',
                    selected: !pdf,
                    onTap: () => setState(() => _format = _SaveFormat.flashcards),
                  ),
                ),
              ],
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _folders.isEmpty
                      ? Text('A folder called "My Notes" will be created.',
                          style: AppText.statLabel)
                      : DropdownButtonFormField<StudyFolder>(
                          // Rebuilt when a new folder is picked for us.
                          key: ValueKey(_folder?.id),
                          initialValue: _folder,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Folder',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final f in _folders)
                              DropdownMenuItem(
                                value: f,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: f.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(f.name,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (f) => setState(() => _folder = f ?? _folder),
                        ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'New Folder',
                  child: OutlinedButton(
                    onPressed: _newFolder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(color: AppColors.border),
                      minimumSize: const Size(48, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.newFolder, size: 18),
                        SizedBox(width: 6),
                        Text('New',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: pdf ? 'Save as PDF' : 'Make Flashcards',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(selected ? 13 : 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  color: selected ? AppColors.primaryDeep : AppColors.ink, size: 26),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: AppText.itemMeta),
            ],
          ),
        ),
      ),
    );
  }
}
