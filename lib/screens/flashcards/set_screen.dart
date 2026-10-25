import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
import '../../widgets/dialogs.dart';
import '../../widgets/list_items.dart';
import '../actions.dart';
import '../plans_screen.dart';

/// A flashcard set: its reference photos, its cards, and a Study button.
class SetScreen extends StatelessWidget {
  const SetScreen({super.key, required this.setId});

  final String setId;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final deck = store.setById(setId);
        if (deck == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: AppColors.background),
            body: const Center(child: Text('This flashcard set was deleted.')),
          );
        }
        final folder = store.folder(deck.folderId);
        // Smart review (what's due today) is tAsikaso+; answers are still
        // recorded on the free plan, so a plan starts with real history.
        final smart = store.isPlus;
        final due = smart ? store.dueCards(deck) : deck.cards;
        // Cards can be made from the photos' text: already read, or
        // readable on this device.
        final canMakeCards = deck.sourceText.trim().isNotEmpty ||
            (deck.photoCount > 0 && ScanService.canReadText);
        final menu = {
          if (deck.cards.length >= 2)
            'New Quiz': () => quizSet(context, deck, fresh: true),
          if (canMakeCards)
            (StudyAi.isOn ? 'Make Cards with AI' : 'Suggest Cards from Photos'):
                () => makeCardsForSet(context, deck),
          ...setActions(context, deck, onDeleted: () {
            if (context.mounted) Navigator.of(context).pop();
          })
            ..remove('Study')
            ..remove('Quiz'),
        };

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.ink,
            title: Text(
              deck.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            actions: [ActionsMenu(actions: menu)],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(
                children: [
                  if (folder != null) ...[
                    Flexible(
                      child: SubjectTag(label: folder.name, color: folder.color),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(plural(deck.cards.length, 'card'), style: AppText.statLabel),
                ],
              ),
              const SizedBox(height: 16),
              AccentButton(
                label: deck.cards.isEmpty
                    ? 'Add cards to start studying'
                    : due.isNotEmpty && due.length < deck.cards.length
                        ? 'Review ${plural(due.length, 'Card')} Due'
                        : 'Study ${plural(deck.cards.length, 'Card')}',
                onPressed: deck.cards.isEmpty ? null : () => studySet(context, deck),
              ),
              if (deck.cards.isNotEmpty && !smart)
                Center(
                  child: TextButton.icon(
                    onPressed: () =>
                        showPlusPrompt(context, PlusFeature.smartReview),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(AppIcons.locked, size: 13),
                    label: const Text('Smart review: just the cards due today'),
                  ),
                )
              else if (deck.cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Center(
                    child: due.isEmpty
                        ? Text('All caught up, nothing is due today.',
                            style: AppText.itemMeta)
                        : due.length < deck.cards.length
                            ? TextButton(
                                onPressed: () =>
                                    studySet(context, deck, dueOnly: false),
                                child: Text(
                                    'Study all ${plural(deck.cards.length, 'card')}'),
                              )
                            : Text('${plural(due.length, 'card')} due today',
                                style: AppText.itemMeta),
                  ),
                ),
              if (deck.cards.length >= 2) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => quizSet(context, deck),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(color: AppColors.border, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(AppIcons.target, size: 18),
                    label: Text(
                      deck.quiz.isEmpty
                          ? 'Take a Quiz'
                          : 'Take a Quiz (${plural(deck.quiz.length, 'question')})',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                // A quiz made from two or three cards repeats itself.
                if (deck.cards.length < 4 && !StudyAi.isOn)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Center(
                      child: Text('Add a few more cards for a better quiz.',
                          style: AppText.itemMeta),
                    ),
                  ),
              ],
              if (deck.summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(deck.summary, style: AppText.statLabel.copyWith(height: 1.45)),
              ],
              if (deck.concepts.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Key Concepts', style: AppText.sectionTitle),
                const SizedBox(height: 10),
                for (final c in deck.concepts)
                  ConceptTile(term: c.term, explanation: c.explanation),
              ],
              if (deck.photoCount > 0) ...[
                const SizedBox(height: 24),
                Text('Your Photos', style: AppText.sectionTitle),
                const SizedBox(height: 4),
                Text('Tap a photo to see it full size while you write cards.',
                    style: AppText.itemMeta),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: deck.photoCount,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, i) =>
                        _SetPhoto(key: ValueKey('${deck.id}-$i'), deck: deck, index: i),
                  ),
                ),
              ],
              if (deck.suggestions.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Suggested Cards (${deck.suggestions.length})',
                  actionLabel: 'Add All',
                  onViewAll: () => store.updateSet(deck.copyWith(
                    cards: [...deck.cards, ...deck.suggestions],
                    suggestions: const [],
                  )),
                ),
                const SizedBox(height: 4),
                Text(
                  'Found in the text of your photos. Add the ones you want.',
                  style: AppText.itemMeta,
                ),
                const SizedBox(height: 10),
                for (final s in deck.suggestions)
                  _SuggestionTile(
                    key: ValueKey('s-${s.id}'),
                    card: s,
                    onAdd: () => store.updateSet(deck.copyWith(
                      cards: [...deck.cards, s],
                      suggestions: [
                        for (final x in deck.suggestions)
                          if (x.id != s.id) x,
                      ],
                    )),
                    onSkip: () => store.updateSet(deck.copyWith(
                      suggestions: [
                        for (final x in deck.suggestions)
                          if (x.id != s.id) x,
                      ],
                    )),
                  ),
              ],
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Cards',
                actionLabel: 'Add Card',
                onViewAll: () => showCardEditor(context, deck),
              ),
              const SizedBox(height: 8),
              if (deck.cards.isEmpty)
                EmptyState(
                  icon: AppIcons.flashcards,
                  message: 'Write a question on the front and the answer on '
                      'the back.',
                  actionLabel: 'Add Card',
                  onAction: () => showCardEditor(context, deck),
                )
              else
                for (final card in deck.cards)
                  _CardTile(
                    key: ValueKey(card.id),
                    card: card,
                    onTap: () => showCardEditor(context, deck, card: card),
                    actions: {
                      'Edit': () => showCardEditor(context, deck, card: card),
                      'Delete': () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Delete Card?',
                          message: '"${card.front}" will be deleted.',
                        );
                        if (!ok) return;
                        store.updateSet(deck.copyWith(
                          cards: [
                            for (final c in deck.cards)
                              if (c.id != card.id) c,
                          ],
                          // Its questions would still be counted and listed.
                          quiz: [
                            for (final q in deck.quiz)
                              if (q.cardId != card.id) q,
                          ],
                        ));
                      },
                    },
                  ),
              if (deck.quiz.isNotEmpty) ...[
                const SizedBox(height: 24),
                _QuizList(key: ValueKey('quiz-${deck.id}'), deck: deck),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The set's saved quiz, folded away until opened: each question with its
/// type and answer, and Delete for a bad one.
class _QuizList extends StatefulWidget {
  const _QuizList({super.key, required this.deck});

  final FlashcardSet deck;

  @override
  State<_QuizList> createState() => _QuizListState();
}

class _QuizListState extends State<_QuizList> {
  bool _open = false;

  Future<void> _delete(QuizQuestion question) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Question?',
      message: '"${question.prompt.split('\n').first}" will be left out of '
          'the quiz.',
    );
    if (!ok) return;
    final store = AppStore.instance;
    final current = store.setById(widget.deck.id);
    if (current == null) return;
    store.updateSet(current.copyWith(quiz: [
      for (final q in current.quiz)
        if (!identical(q, question)) q,
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.deck.quiz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Quiz Questions (${quiz.length})',
          actionLabel: _open ? 'Hide' : 'Show',
          onViewAll: () => setState(() => _open = !_open),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          for (final q in quiz)
            _QuestionTile(question: q, onDelete: () => _delete(q)),
        ],
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question, required this.onDelete});

  final QuizQuestion question;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.type.label, style: AppText.itemMeta),
                const SizedBox(height: 3),
                Text(
                  question.prompt,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Answer: ${question.answer}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.statLabel,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete Question',
            onPressed: onDelete,
            icon: const Icon(AppIcons.delete, size: 18),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.card,
    required this.onTap,
    required this.actions,
  });

  final Flashcard card;
  final VoidCallback onTap;
  final MenuActions actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.front,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.back,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.statLabel,
                      ),
                    ],
                  ),
                ),
                ActionsMenu(actions: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A suggested card with Add / Skip buttons.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    super.key,
    required this.card,
    required this.onAdd,
    required this.onSkip,
  });

  final Flashcard card;
  final VoidCallback onAdd;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.suggest, size: 16, color: AppColors.primaryDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.front,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(card.back,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.statLabel),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Skip',
            onPressed: onSkip,
            icon: const Icon(AppIcons.close, size: 18),
            color: AppColors.textSecondary,
          ),
          IconButton(
            tooltip: 'Add Card',
            onPressed: onAdd,
            icon: const Icon(AppIcons.check, size: 20),
            color: AppColors.primaryDeep,
          ),
        ],
      ),
    );
  }
}

/// A reference photo, loaded once from storage.
class _SetPhoto extends StatefulWidget {
  const _SetPhoto({super.key, required this.deck, required this.index});

  final FlashcardSet deck;
  final int index;

  @override
  State<_SetPhoto> createState() => _SetPhotoState();
}

class _SetPhotoState extends State<_SetPhoto> {
  late final Future<Uint8List?> _bytes =
      AppStore.instance.readSetPhoto(widget.deck, widget.index);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return GestureDetector(
          onTap: bytes == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _PhotoViewer(bytes: bytes),
                  )),
          child: Container(
            width: 82,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.thumbnail,
              borderRadius: BorderRadius.circular(8),
            ),
            child: bytes == null
                ? Icon(AppIcons.photo, color: AppColors.textMuted)
                : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 240),
          ),
        );
      },
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cameraBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cameraBackground,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.memory(bytes)),
      ),
    );
  }
}

// ---- Card editor --------------------------------------------------------------

/// Add a card to [deck], or edit [card].
Future<void> showCardEditor(BuildContext context, FlashcardSet deck, {Flashcard? card}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CardEditor(setId: deck.id, card: card),
  );
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({required this.setId, this.card});

  final String setId;
  final Flashcard? card;

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _front = TextEditingController(text: widget.card?.front ?? '');
  late final _back = TextEditingController(text: widget.card?.back ?? '');
  final _frontFocus = FocusNode();
  int _added = 0;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    super.dispose();
  }

  bool get _valid => _front.text.trim().isNotEmpty && _back.text.trim().isNotEmpty;

  /// Saves the card. Returns false if the set no longer exists.
  bool _save() {
    final store = AppStore.instance;
    final deck = store.setById(widget.setId);
    if (deck == null) return false;
    final front = _front.text.trim();
    final back = _back.text.trim();
    final existing = widget.card;
    final cards = existing == null
        ? [...deck.cards, Flashcard(id: newId(), front: front, back: back)]
        : [
            for (final c in deck.cards)
              c.id == existing.id ? c.copyWith(front: front, back: back) : c,
          ];
    store.updateSet(deck.copyWith(cards: cards));
    return true;
  }

  void _saveAndClose() {
    if (!_valid) return;
    _save();
    Navigator.of(context).pop();
  }

  void _saveAndNext() {
    if (!_valid || !_save()) return;
    setState(() {
      _added++;
      _front.clear();
      _back.clear();
    });
    _frontFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.card != null;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle(
              editing ? 'Edit Card' : 'New Card',
              subtitle: _added > 0 ? '${plural(_added, 'card')} added' : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _front,
              focusNode: _frontFocus,
              autofocus: !editing,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Front (question or term)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _back,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Back (answer)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: editing ? 'Save' : 'Save Card',
              onPressed: _valid ? _saveAndClose : null,
            ),
            if (!editing) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _valid ? _saveAndNext : null,
                  child: const Text('Save & Add Another'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.streakRed),
                  onPressed: () async {
                    final ok = await showConfirmDialog(context,
                        title: 'Delete Card?', message: 'This card will be deleted.');
                    if (!ok || !context.mounted) return;
                    final store = AppStore.instance;
                    final deck = store.setById(widget.setId);
                    final card = widget.card;
                    if (deck != null && card != null) {
                      store.updateSet(deck.copyWith(cards: [
                        for (final c in deck.cards)
                          if (c.id != card.id) c,
                      ], quiz: [
                        for (final q in deck.quiz)
                          if (q.cardId != card.id) q,
                      ]));
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Delete Card'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
