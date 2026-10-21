import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
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
        final hasText = note.text.isNotEmpty ||
            note.cleanText.isNotEmpty ||
            note.concepts.isNotEmpty;

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
              if (hasText)
                IconButton(
                  tooltip: 'View Text',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoteTextScreen(noteId: note.id),
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

/// A note's text: typed up by the study server when it was (with the
/// summary and key concepts), or as read from the pages. Selectable, with
/// Copy, and a button to make flashcards from it. Reads the note from the
/// store, so a rename shows here too.
class NoteTextScreen extends StatefulWidget {
  const NoteTextScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteTextScreen> createState() => _NoteTextScreenState();
}

class _NoteTextScreenState extends State<NoteTextScreen> {
  /// Show the text as read from the photos instead of the typed-up notes.
  bool _asRead = false;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final note = store.note(widget.noteId);
        if (note == null) {
          return Scaffold(
            appBar: subPageAppBar('Note Text'),
            body: const Center(child: Text('This note was deleted.')),
          );
        }
        final typedUp = note.cleanText.isNotEmpty;
        final showTyped = typedUp && !_asRead;
        final text = showTyped ? note.cleanText : note.text;

        return Scaffold(
          appBar: subPageAppBar('Note Text', actions: [
            IconButton(
              tooltip: 'Make Flashcards',
              icon: const Icon(AppIcons.flashcards, size: 22),
              onPressed: () => makeFlashcardsFromNote(context, note),
            ),
            IconButton(
              tooltip: 'Copy All',
              icon: const Icon(AppIcons.copy, size: 22),
              onPressed: text.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                            const SnackBar(content: Text('Text copied')));
                    },
            ),
          ]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(note.title, style: AppText.sectionTitle),
              const SizedBox(height: 4),
              Text(
                showTyped
                    ? 'Typed up by your study server from the text read '
                        'from your photos, so check names and numbers.'
                    : 'Read automatically from your photos, so check names '
                        'and numbers.',
                style: AppText.itemMeta,
              ),
              if (typedUp)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => setState(() => _asRead = !_asRead),
                    child: Text(_asRead
                        ? 'Show the typed-up notes'
                        : 'Show the text as read'),
                  ),
                ),
              if (showTyped && note.summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(note.summary,
                    style: AppText.statLabel.copyWith(height: 1.45)),
              ],
              if (showTyped && note.concepts.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Key Concepts', style: AppText.sectionTitle),
                const SizedBox(height: 10),
                for (final c in note.concepts)
                  ConceptTile(term: c.term, explanation: c.explanation),
              ],
              const SizedBox(height: 16),
              if (showTyped && note.concepts.isNotEmpty) ...[
                Text('Notes', style: AppText.sectionTitle),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: text.isEmpty
                    ? Text("No text was read from this note's pages.",
                        style: AppText.statLabel)
                    : SelectableText.rich(
                        notesTextSpan(text),
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.textPrimary),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lays out notes in the study server's line format (`# ` heading, `## `
/// section, `- ` bullet) with bold headings and bullet dots; plain text
/// comes through unchanged.
TextSpan notesTextSpan(String text) {
  final heading = TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  final section = TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  final lines = text.split('\n');
  final spans = <TextSpan>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    final end = i == lines.length - 1 ? '' : '\n';
    if (line.startsWith('# ')) {
      spans.add(TextSpan(text: '${line.substring(2).trim()}$end', style: heading));
    } else if (line.startsWith('## ')) {
      spans.add(TextSpan(text: '${line.substring(3).trim()}$end', style: section));
    } else if (line.startsWith('- ')) {
      spans.add(TextSpan(text: '•  ${line.substring(2).trim()}$end'));
    } else {
      spans.add(TextSpan(text: '$line$end'));
    }
  }
  return TextSpan(children: spans);
}
