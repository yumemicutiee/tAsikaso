import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/list_items.dart';
import 'actions.dart';
import 'capture/notes_pdf.dart';

/// Shows a saved note's PDF with built-in Share and Print buttons, plus
/// Rename / Move / Delete in the menu.
class NoteViewerScreen extends StatefulWidget {
  const NoteViewerScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends State<NoteViewerScreen> {
  final _store = AppStore.instance;
  Future<Uint8List?>? _pdf;

  Note? _note() {
    for (final n in _store.notes) {
      if (n.id == widget.noteId) return n;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final note = _note();
    if (note != null) _pdf = _store.readPdf(note);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final note = _note();
        if (note == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: AppColors.background),
            body: const Center(child: Text('This note was deleted.')),
          );
        }
        final actions = noteActions(context, note, onDeleted: () {
          if (mounted) Navigator.of(this.context).pop();
        })
          ..remove('Open')
          ..remove('Share PDF');

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.ink,
            title: Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            actions: [
              if (note.text.isNotEmpty)
                IconButton(
                  tooltip: 'View Text',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoteTextScreen(note: note),
                    ),
                  ),
                  icon: const Icon(AppIcons.text, size: 22),
                ),
              ActionsMenu(actions: actions),
            ],
          ),
          body: FutureBuilder<Uint8List?>(
            future: _pdf,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      "This note's PDF couldn't be found.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return PdfPreview(
                build: (format) => bytes,
                pdfFileName: pdfFileName(note.title),
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                scrollViewDecoration:
                    BoxDecoration(color: AppColors.background),
              );
            },
          ),
        );
      },
    );
  }
}

/// The text read from a note's pages, selectable, with a Copy button.
class NoteTextScreen extends StatelessWidget {
  const NoteTextScreen({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subPageAppBar('Note Text', actions: [
        IconButton(
          tooltip: 'Copy All',
          icon: const Icon(AppIcons.copy, size: 22),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: note.text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Text copied')));
          },
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(note.title, style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text(
            'Read automatically from your photos, so check names and numbers.',
            style: AppText.itemMeta,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              note.text,
              style: TextStyle(
                  fontSize: 14, height: 1.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
