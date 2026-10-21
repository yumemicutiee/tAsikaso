import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../data/plans.dart';
import '../data/pomodoro_controller.dart';
import '../models/models.dart';
import '../theme/brand.dart';
import '../services/scan_service.dart';
import '../services/study_ai.dart';
import '../utils/card_suggestions.dart';
import '../utils/format.dart';
import '../utils/quiz_builder.dart';
import '../widgets/dialogs.dart';
import '../widgets/list_items.dart';
import 'capture/notes_pdf.dart';
import 'flashcards/quiz_screen.dart';
import 'flashcards/set_screen.dart';
import 'flashcards/study_cards_screen.dart';
import 'folder_screen.dart';
import 'note_viewer_screen.dart';
import 'plans_screen.dart';
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
  try {
    await Printing.sharePdf(bytes: bytes, filename: pdfFileName(note.title));
  } catch (e) {
    debugPrint('Could not share the PDF: $e');
    if (context.mounted) _toast(context, "This PDF couldn't be shared.");
  }
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

/// Studies [deck]: with smart review (tAsikaso+), just the cards due today
/// when some (but not all) are due, otherwise every card. [dueOnly]
/// overrides that; the free plan always studies every card.
void studySet(BuildContext context, FlashcardSet deck, {bool? dueOnly}) {
  if (deck.cards.isEmpty) {
    _toast(context, 'Add some cards first.');
    openSet(context, deck);
    return;
  }
  final due = _store.dueCards(deck).length;
  final reviewDue = _store.isPlus &&
      (dueOnly ?? (due > 0 && due < deck.cards.length));
  Navigator.of(context).push(
    MaterialPageRoute(
        builder: (_) => StudyCardsScreen(setId: deck.id, dueOnly: reviewDue)),
  );
}

/// Opens a quiz on [deck]: the one it already has, or a new one. With
/// [fresh], a new one is written even if the set has a quiz.
Future<void> quizSet(BuildContext context, FlashcardSet deck,
    {bool fresh = false}) async {
  if (deck.cards.length < 2) {
    _toast(context, 'Add at least two cards first.');
    return;
  }
  // Questions about cards that were deleted since are left out.
  final ids = {for (final c in deck.cards) c.id};
  var questions = fresh
      ? const <QuizQuestion>[]
      : [
          for (final q in deck.quiz)
            if (q.cardId == null || ids.contains(q.cardId)) q,
        ];
  if (questions.isEmpty) {
    final made = await makeQuiz(context, deck);
    if (made == null) return;
    questions = made;
  }
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
        builder: (_) => QuizScreen(setId: deck.id, questions: questions)),
  );
}

/// Writes a new quiz for [deck] — by the study server when it's on, else
/// from the cards themselves — keeps it on the set, and returns it. Null if
/// none could be made.
Future<List<QuizQuestion>?> makeQuiz(
    BuildContext context, FlashcardSet deck) async {
  var questions = const <QuizQuestion>[];
  String? problem;
  if (StudyAi.isOn) {
    try {
      questions = await runWithProgress(
        context,
        'Writing your quiz…',
        () => StudyAi.makeQuiz(
            title: deck.title, cards: deck.cards, concepts: deck.concepts),
      );
    } on StudyAiException catch (e) {
      problem = e.message;
    } catch (e) {
      debugPrint('Quiz from the study server failed: $e');
      problem = "The study server's answer couldn't be read.";
    }
  }
  if (questions.isEmpty) questions = buildLocalQuiz(deck.cards);
  if (!context.mounted) return null;
  if (questions.isEmpty) {
    _toast(context, "A quiz couldn't be made from these cards.");
    return null;
  }
  final current = _store.setById(deck.id);
  if (current != null) _store.updateSet(current.copyWith(quiz: questions));
  if (problem != null) {
    _toast(context, '$problem The quiz was made from your cards instead.');
  }
  return questions;
}

/// Cards to ask the study server for: 30, or what's left of the free
/// plan's suggested cards this month.
int cardsToAskFor(int? left) => left == null ? 30 : math.min(30, left);

/// Said when the free plan's suggested cards for this month are used up.
String get suggestionLimitNote =>
    "Free plan: this month's $kFreeSuggestedCardsPerMonth suggested cards "
    'are used up. $kPlusName has no limit.';

/// [questions] without those about cards that weren't kept.
List<QuizQuestion> _quizFor(List<QuizQuestion> questions, List<Flashcard> kept) {
  final ids = {for (final c in kept) c.id};
  return [
    for (final q in questions)
      if (q.cardId == null || ids.contains(q.cardId)) q,
  ];
}

/// Cards for an existing set from the text of its photos: the study server
/// writes them (with key concepts and a quiz) when it's on; otherwise
/// they're suggested from the text for the user to add or skip. The free
/// plan gets [kFreeSuggestedCardsPerMonth] a month.
Future<void> makeCardsForSet(BuildContext context, FlashcardSet deck) async {
  final left = _store.suggestedCardsLeft;
  if (left == 0) {
    await showPlusPrompt(context, PlusFeature.unlimitedSuggestions);
    return;
  }
  final ai = StudyAi.isOn;
  String text = deck.sourceText;
  StudyKit? kit;
  String? problem;
  try {
    await runWithProgress(
      context,
      ai ? 'Making your flashcards…' : 'Reading your photos…',
      () async {
        if (text.trim().isEmpty && deck.photoCount > 0) {
          final photos = <Uint8List>[];
          for (var i = 0; i < deck.photoCount; i++) {
            final bytes = await _store.readSetPhoto(deck, i);
            if (bytes != null) photos.add(bytes);
          }
          text = await ScanService.readText(photos);
        }
        if (ai && text.trim().isNotEmpty) {
          kit = await StudyAi.makeStudyKit(
              text: text, title: deck.title, maxCards: cardsToAskFor(left));
        }
      },
    );
  } on StudyAiException catch (e) {
    problem = e.message;
  } catch (e) {
    debugPrint('Making cards failed: $e');
    problem = "Couldn't make cards. Please try again.";
  }
  if (!context.mounted) return;
  if (text.trim().isEmpty) {
    _toast(context, 'No text could be read from the photos.');
    return;
  }
  final current = _store.setById(deck.id);
  if (current == null) return;
  final fronts = {
    for (final c in current.cards) c.front.trim().toLowerCase(),
    for (final c in current.suggestions) c.front.trim().toLowerCase(),
  };

  if (kit case final kit?) {
    final (:kept, :dropped) = _store.takeSuggestedCards([
      for (final c in kit.cards)
        if (fronts.add(c.front.trim().toLowerCase())) c,
    ]);
    _store.updateSet(current.copyWith(
      cards: [...current.cards, ...kept],
      sourceText: text,
      summary: kit.summary,
      concepts: kit.concepts,
      quiz: _quizFor(kit.quiz, [...current.cards, ...kept]),
    ));
    final made = kept.isEmpty
        ? 'No new cards to add.'
        : '${plural(kept.length, 'card')} added.';
    _toast(context, dropped > 0 ? '$made $suggestionLimitNote' : made);
    return;
  }

  final (:kept, :dropped) = _store.takeSuggestedCards([
    for (final c in suggestCards(text))
      if (fronts.add(c.front.trim().toLowerCase())) c,
  ]);
  _store.updateSet(current.copyWith(
    suggestions: [...current.suggestions, ...kept],
    sourceText: text,
  ));
  var made = kept.isEmpty
      ? 'No cards were found in the text.'
      : '${plural(kept.length, 'card')} suggested from the text.';
  if (dropped > 0) made = '$made $suggestionLimitNote';
  _toast(context, problem == null ? made : '$problem $made');
}

/// A new flashcard set from a note's text, in the note's folder. The free
/// plan gets [kFreeSuggestedCardsPerMonth] suggested cards a month.
Future<void> makeFlashcardsFromNote(BuildContext context, Note note) async {
  final text = note.displayText;
  if (text.trim().isEmpty) {
    _toast(context, 'This note has no text to make cards from.');
    return;
  }
  final left = _store.suggestedCardsLeft;
  if (left == 0) {
    await showPlusPrompt(context, PlusFeature.unlimitedSuggestions);
    return;
  }
  StudyKit? kit;
  String? problem;
  if (StudyAi.isOn) {
    try {
      kit = await runWithProgress(
        context,
        'Making your flashcards…',
        () => StudyAi.makeStudyKit(
            text: text, title: note.title, maxCards: cardsToAskFor(left)),
      );
    } on StudyAiException catch (e) {
      problem = e.message;
    } catch (e) {
      debugPrint('Cards from the study server failed: $e');
      problem = "The study server's answer couldn't be read.";
    }
  }
  if (!context.mounted) return;
  final (kept: cards, dropped: droppedCards) =
      _store.takeSuggestedCards(kit?.cards ?? const []);
  final (kept: suggestions, dropped: droppedSuggestions) = kit == null
      ? _store.takeSuggestedCards(suggestCards(text))
      : (kept: const <Flashcard>[], dropped: 0);
  final deck = await _store.addSet(
    title: note.title,
    folderId: note.folderId,
    cards: cards,
    suggestions: suggestions,
    sourceText: note.text.isNotEmpty ? note.text : text,
    summary: kit?.summary ?? note.summary,
    concepts: kit?.concepts ?? note.concepts,
    quiz: kit == null ? const [] : _quizFor(kit.quiz, cards),
  );
  if (!context.mounted) return;
  openSet(context, deck);
  var made = kit != null
      ? '${plural(cards.length, 'card')} made from "${note.title}".'
      : suggestions.isEmpty
          ? 'No cards were found in the text; write your own.'
          : '${plural(suggestions.length, 'card')} suggested from the text.';
  if (droppedCards + droppedSuggestions > 0) {
    made = '$made $suggestionLimitNote';
  }
  _toast(context, problem == null ? made : '$problem $made');
}

/// [onDeleted] runs after the set is deleted (e.g. to close its screen).
MenuActions setActions(BuildContext context, FlashcardSet deck, {VoidCallback? onDeleted}) => {
      'Study': () => studySet(context, deck),
      'Quiz': () => quizSet(context, deck),
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

/// Edits a folder; the sheet also offers to delete it. [onDeleted] runs
/// after a deletion (e.g. to close the folder's screen).
Future<void> editFolder(BuildContext context, StudyFolder folder,
    {VoidCallback? onDeleted}) async {
  final draft = await showFolderEditor(
    context,
    folder: folder,
    onDelete: () async {
      if (await deleteFolder(context, folder)) onDeleted?.call();
    },
  );
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

/// Opens Settings, scrolled to [section] if given.
void openSettings(BuildContext context, {SettingsSection? section}) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SettingsScreen(section: section)),
  );
}

// ---- Timer -------------------------------------------------------------------

/// Skips the current phase, asking first when that would throw away a
/// Pomodoro in progress.
Future<void> skipPhase(BuildContext context) async {
  final timer = PomodoroController.instance;
  if (timer.isFocus && !timer.atStart) {
    final phase = timer.phase;
    final ok = await showConfirmDialog(
      context,
      title: 'Skip This Pomodoro?',
      message: 'It has ${timer.timeText} left. A skipped Pomodoro '
          "doesn't count toward your focus time or your task.",
      confirmLabel: 'Skip',
    );
    // It may have finished while the question was open.
    if (!ok || timer.phase != phase) return;
  }
  timer.skip();
}

/// Starts the phase over, asking first when that would throw away a
/// Pomodoro in progress.
Future<void> resetTimer(BuildContext context) async {
  final timer = PomodoroController.instance;
  if (timer.isFocus && !timer.atStart) {
    final phase = timer.phase;
    final ok = await showConfirmDialog(
      context,
      title: 'Reset This Pomodoro?',
      message: 'It has ${timer.timeText} left and will start over. The time '
          "so far won't count toward your focus time or your task.",
      confirmLabel: 'Reset',
    );
    if (!ok || timer.phase != phase) return;
  }
  timer.reset();
}

/// Switches the timer to [mode], asking first when that would throw away a
/// Pomodoro in progress.
Future<void> switchTimerMode(BuildContext context, TimerMode mode) async {
  final timer = PomodoroController.instance;
  if (mode == timer.mode) return;
  if (timer.isFocus && !timer.atStart) {
    final phase = timer.phase;
    final ok = await showConfirmDialog(
      context,
      title: 'Switch to ${mode.label}?',
      message: 'This Pomodoro has ${timer.timeText} left. If you switch now, '
          "it won't count toward your focus time or your task.",
      confirmLabel: 'Switch',
    );
    if (!ok || timer.phase != phase) return;
  }
  timer.selectMode(mode);
}
