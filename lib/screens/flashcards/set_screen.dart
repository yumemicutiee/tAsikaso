import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/list_items.dart';
import '../actions.dart';

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
        final menu = setActions(context, deck, onDeleted: () {
          if (context.mounted) Navigator.of(context).pop();
        })
          ..remove('Study');

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
                    : 'Study ${plural(deck.cards.length, 'Card')}',
                onPressed: deck.cards.isEmpty ? null : () => studySet(context, deck),
              ),
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
                      'Delete': () => store.updateSet(deck.copyWith(
                            cards: [
                              for (final c in deck.cards)
                                if (c.id != card.id) c,
                            ],
                          )),
                    },
                  ),
            ],
          ),
        );
      },
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
