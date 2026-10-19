import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/list_items.dart';
import 'capture/notes_pdf.dart';
import 'flashcards/set_screen.dart';
import 'flashcards/study_cards_screen.dart';
import 'folder_screen.dart';
import 'note_viewer_screen.dart';
import 'settings_screen.dart';

// Shared actions for notes, flashcard sets and folders, used by several
// screens so behaviour is the same everywhere.

AppStore get _store => AppStore.instance;

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

// ---- Notes -------------------------------------------------------------------

void openNote(BuildContext context, Note note) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => NoteViewerScreen(noteId: note.id)),
  );
}

Future<void> shareNote(BuildContext context, Note note) async {
  final bytes = await _store.readPdf(note);
  if (!context.mounted) return;
  if (bytes == null) {
    _toast(context, "This note's PDF couldn't be found.");
    return;
  }
  await Printing.sharePdf(bytes: bytes, filename: pdfFileName(note.title));
}

/// [onDeleted] runs after the note is deleted (e.g. to close its screen).
MenuActions noteActions(BuildContext context, Note note, {VoidCallback? onDeleted}) => {
      'Open': () => openNote(context, note),
      'Share PDF': () => shareNote(context, note),
      'Rename': () async {
        final name = await showTextInputDialog(context,
            title: 'Rename Note', initial: note.title);
        if (name != null) _store.updateNote(note.copyWith(title: name));
      },
      'Move to Folder': () async {
        final f = await showFolderPicker(context, currentId: note.folderId);
        if (f != null) _store.updateNote(note.copyWith(folderId: f.id));
      },
      'Delete': () async {
        final ok = await showConfirmDialog(context,
            title: 'Delete Note?',
            message: '"${note.title}" and its PDF will be deleted.');
        if (!ok) return;
        await _store.deleteNote(note.id);
        onDeleted?.call();
      },
    };

// ---- Flashcard sets ----------------------------------------------------------

void openSet(BuildContext context, FlashcardSet deck) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SetScreen(setId: deck.id)),
  );
}

void studySet(BuildContext context, FlashcardSet deck) {
  if (deck.cards.isEmpty) {
    _toast(context, 'Add some cards first.');
    openSet(context, deck);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StudyCardsScreen(setId: deck.id)),
  );
}

/// [onDeleted] runs after the set is deleted (e.g. to close its screen).
MenuActions setActions(BuildContext context, FlashcardSet deck, {VoidCallback? onDeleted}) => {
      'Study': () => studySet(context, deck),
      'Rename': () async {
        final name = await showTextInputDialog(context,
            title: 'Rename Set', initial: deck.title);
        if (name != null) _store.updateSet(deck.copyWith(title: name));
      },
      'Move to Folder': () async {
        final f = await showFolderPicker(context, currentId: deck.folderId);
        if (f != null) _store.updateSet(deck.copyWith(folderId: f.id));
      },
      'Delete': () async {
        final ok = await showConfirmDialog(context,
            title: 'Delete Flashcard Set?',
            message:
                '"${deck.title}" and its ${plural(deck.cards.length, 'card')} will be deleted.');
        if (!ok) return;
        await _store.deleteSet(deck.id);
        onDeleted?.call();
      },
    };

/// Asks for a title and folder, creates an empty set and opens it.
Future<void> createSet(BuildContext context, {String? folderId}) async {
  final folders = _store.folders;
  if (folders.isEmpty) {
    _toast(context, 'Create a folder first.');
    return;
  }
  final title = await showTextInputDialog(context,
      title: 'New Flashcard Set', hint: 'e.g. Cell Biology', confirmLabel: 'Next');
  if (title == null || !context.mounted) return;

  StudyFolder? folder = folderId == null ? null : _store.folder(folderId);
  folder ??= await showFolderPicker(context, title: 'Save in Folder');
  if (folder == null || !context.mounted) return;

  final deck = await _store.addSet(title: title, folderId: folder.id);
  if (context.mounted) openSet(context, deck);
}

// ---- Folders -----------------------------------------------------------------

void openFolder(BuildContext context, StudyFolder folder) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FolderScreen(folderId: folder.id)),
  );
}

Future<void> createFolder(BuildContext context) async {
  final draft = await showFolderEditor(context);
  if (draft != null) _store.addFolder(draft.name, draft.colorValue);
}

Future<void> editFolder(BuildContext context, StudyFolder folder) async {
  final draft = await showFolderEditor(context, folder: folder);
  if (draft != null) {
    _store.updateFolder(
        folder.copyWith(name: draft.name, colorValue: draft.colorValue));
  }
}

/// Returns true if the folder was deleted.
Future<bool> deleteFolder(BuildContext context, StudyFolder folder) async {
  final notes = _store.noteCountIn(folder.id);
  final sets = _store.setCountIn(folder.id);
  final contents = (notes + sets) == 0
      ? 'It is empty.'
      : 'Its ${plural(notes, 'note')} and ${plural(sets, 'flashcard set')} will also be deleted.';
  final ok = await showConfirmDialog(context,
      title: 'Delete "${folder.name}"?', message: contents);
  if (ok) await _store.deleteFolder(folder.id);
  return ok;
}

// ---- Ready-made list rows ----------------------------------------------------

Widget noteTile(BuildContext context, Note note) => NoteTile(
      key: ValueKey(note.id),
      note: note,
      folder: _store.folder(note.folderId),
      thumbnail: _store.thumbnail(note.id),
      onTap: () => openNote(context, note),
      actions: noteActions(context, note),
    );

Widget setTile(BuildContext context, FlashcardSet deck) => SetTile(
      key: ValueKey(deck.id),
      deck: deck,
      folder: _store.folder(deck.folderId),
      onTap: () => openSet(context, deck),
      actions: setActions(context, deck),
    );

// ---- Settings ----------------------------------------------------------------

void openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SettingsScreen()),
  );
}
