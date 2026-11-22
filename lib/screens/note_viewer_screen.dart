import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../services/study_ai.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/list_items.dart';
import 'actions.dart';
import 'capture/notes_pdf.dart';

/// Shows a saved note's PDF with built-in Share and Print buttons, plus
/// Rename / Move / Delete in the menu. For Text Notes this shows the
/// original pages, opened from the text ([fromText]), so it has no menu of
/// its own and no button back to the text.
class NoteViewerScreen extends StatefulWidget {
  const NoteViewerScreen({super.key, required this.noteId, this.fromText = false});

  final String noteId;
  final bool fromText;

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
        final hasText = !widget.fromText &&
            (note.text.isNotEmpty ||
                note.cleanText.isNotEmpty ||
                note.concepts.isNotEmpty);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.ink,
            title: Text(
              widget.fromText ? 'Original Pages' : note.title,
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
              if (!widget.fromText) ActionsMenu(actions: actions),
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
/// Edit (to fix misread words), Copy, and a big Make Flashcards button. With
/// Smart Study on, the text as read can be typed up (again). Text Notes open
/// here, with the original pages one tap away, Rename / Move / Delete in the
/// menu, and Share as a text PDF. Reads the note from the store, so a rename
/// or an edit shows here too.
class NoteTextScreen extends StatefulWidget {
  const NoteTextScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteTextScreen> createState() => _NoteTextScreenState();
}

class _NoteTextScreenState extends State<NoteTextScreen> {
  /// Show the text as read from the photos instead of the typed-up notes.
  bool _asRead = false;

  void _viewPages(Note note) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteViewerScreen(noteId: note.id, fromText: true),
        ),
      );

  Future<void> _edit(Note note, {required bool typedUp}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditScreen(noteId: note.id, typedUp: typedUp),
      ),
    );
  }

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
        final canTypeUp = StudyAi.isOn && note.text.trim().isNotEmpty;
        final linkStyle = TextButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        );
        final menu = noteActions(context, note, onDeleted: () {
          if (mounted) Navigator.of(this.context).pop();
        })
          ..remove('Open')
          ..remove('View Pages');

        return Scaffold(
          appBar: subPageAppBar(note.textNote ? 'Text Notes' : 'Note Text',
              actions: [
                if (note.textNote)
                  IconButton(
                    tooltip: 'View Pages',
                    icon: const Icon(AppIcons.photo, size: 22),
                    onPressed: () => _viewPages(note),
                  ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(AppIcons.edit, size: 22),
                  onPressed: () => _edit(note, typedUp: showTyped),
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
                if (note.textNote) ActionsMenu(actions: menu),
              ]),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: note.displayText.trim().isEmpty
                      ? null
                      : () => makeFlashcardsFromNote(context, note),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onFill,
                    disabledBackgroundColor: AppColors.primarySoft,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(AppIcons.flashcards, size: 20),
                  label: const Text('Make Flashcards',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(note.title, style: AppText.sectionTitle),
              const SizedBox(height: 4),
              Text(
                note.edited
                    ? 'Edited by you.'
                    : showTyped
                        ? 'Typed up by your study server from the text read '
                            'from your pages, so check names and numbers.'
                        : 'Read automatically from your pages, so check names '
                            'and numbers. Tap Edit to fix a word.',
                style: AppText.itemMeta,
              ),
              if (note.textNote || typedUp || canTypeUp)
                Wrap(
                  spacing: 16,
                  children: [
                    if (note.textNote)
                      TextButton.icon(
                        style: linkStyle,
                        onPressed: () => _viewPages(note),
                        icon: const Icon(AppIcons.photo, size: 15),
                        label: Text(note.pageCount == 1
                            ? 'View the original page'
                            : 'View the original pages'),
                      ),
                    if (typedUp)
                      TextButton(
                        style: linkStyle,
                        onPressed: () => setState(() => _asRead = !_asRead),
                        child: Text(_asRead
                            ? 'Show the typed-up notes'
                            : 'Show the text as read'),
                      ),
                    if (canTypeUp)
                      TextButton.icon(
                        style: linkStyle,
                        onPressed: () async {
                          final done = await typeUpNote(context, note);
                          if (done && mounted) setState(() => _asRead = false);
                        },
                        icon: const Icon(AppIcons.suggest, size: 15),
                        label: Text(
                            typedUp ? 'Type Up Again' : 'Type Up with AI'),
                      ),
                  ],
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

/// Edits a note's text, to fix words that were misread: the typed-up notes
/// when [typedUp], else the text as read. Asks before throwing changes away.
class NoteEditScreen extends StatefulWidget {
  const NoteEditScreen({super.key, required this.noteId, this.typedUp = false});

  final String noteId;
  final bool typedUp;

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  final _store = AppStore.instance;
  late final TextEditingController _text;
  late final String _original;

  @override
  void initState() {
    super.initState();
    final note = _store.note(widget.noteId);
    _original = note == null
        ? ''
        : widget.typedUp
            ? note.cleanText
            : note.text;
    _text = TextEditingController(text: _original);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _changed => _text.text != _original;

  void _save() {
    final note = _store.note(widget.noteId);
    final messenger = ScaffoldMessenger.of(context);
    final saved = note != null && _changed;
    if (saved) {
      final text = _text.text.trimRight();
      _store.updateNote(widget.typedUp
          ? note.copyWith(cleanText: text, edited: true)
          : note.copyWith(text: text, edited: true));
    }
    Navigator.of(context).pop();
    if (saved) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Notes saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showConfirmDialog(context,
            title: 'Discard Changes?',
            message: 'Your changes to these notes will be lost.',
            confirmLabel: 'Discard',
            cancelLabel: 'Keep Editing');
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: subPageAppBar('Edit Notes', actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ]),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.typedUp
                    ? 'Fix anything the study server got wrong. Lines starting '
                        'with # are headings and - are bullets.'
                    : 'Fix any words that were read wrong.',
                style: AppText.itemMeta,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Your notes',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
