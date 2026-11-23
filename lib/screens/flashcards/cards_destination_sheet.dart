import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/choices.dart';
import '../../widgets/common.dart';
import '../../widgets/meta_row.dart';

/// Where a note's flashcards go: a new set in [folder], or added to [set].
class CardsDestination {
  const CardsDestination.newSet(StudyFolder this.folder) : set = null;
  const CardsDestination.addTo(FlashcardSet this.set) : folder = null;

  final StudyFolder? folder;
  final FlashcardSet? set;
}

/// Asks where [note]'s flashcards go, before any are made: a new set (in
/// the note's folder, or another one) or a set the user already has.
Future<CardsDestination?> askCardsDestination(BuildContext context, Note note) =>
    showModalBottomSheet<CardsDestination>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CardsDestinationSheet(note: note),
    );

class CardsDestinationSheet extends StatefulWidget {
  const CardsDestinationSheet({super.key, required this.note});

  final Note note;

  @override
  State<CardsDestinationSheet> createState() => _CardsDestinationSheetState();
}

class _CardsDestinationSheetState extends State<CardsDestinationSheet> {
  final _store = AppStore.instance;

  /// The note's folder first, then the others by use.
  late final List<StudyFolder> _folders = [
    ?_store.folder(widget.note.folderId),
    for (final f in _store.recentFolders(1000))
      if (f.id != widget.note.folderId) f,
  ];
  late StudyFolder? _folder = _folders.isEmpty ? null : _folders.first;

  /// The note's folder's sets first, then the rest.
  late final List<FlashcardSet> _sets = [
    ..._store.setsIn(widget.note.folderId),
    for (final s in _store.sets)
      if (s.folderId != widget.note.folderId) s,
  ];
  late FlashcardSet? _set = _sets.isEmpty ? null : _sets.first;
  bool _addToSet = false;

  Future<void> _newFolder() async {
    final folder = await createFolderHere(context);
    if (folder == null || !mounted) return;
    setState(() {
      _folders.insert(0, folder);
      _folder = folder;
    });
  }

  void _submit() {
    final CardsDestination? to = switch ((_addToSet, _set, _folder)) {
      (true, final set?, _) => CardsDestination.addTo(set),
      (false, _, final folder?) => CardsDestination.newSet(folder),
      _ => null,
    };
    if (to != null) Navigator.of(context).pop(to);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle('Make Flashcards', subtitle: 'From "${widget.note.title}"'),
            const SizedBox(height: 14),
            FormatOption(
              icon: AppIcons.newCards,
              title: 'New Set',
              subtitle: 'A new flashcard set called "${widget.note.title}"',
              selected: !_addToSet,
              onTap: () => setState(() => _addToSet = false),
            ),
            const SizedBox(height: 8),
            FormatOption(
              icon: AppIcons.add,
              title: 'Add to a Set',
              subtitle: _sets.isEmpty
                  ? 'You have no flashcard sets yet'
                  : 'Add the cards to a set you already have',
              selected: _addToSet,
              enabled: _sets.isNotEmpty,
              onTap: () => setState(() => _addToSet = true),
            ),
            const SizedBox(height: 16),
            if (_addToSet)
              DropdownButtonFormField<FlashcardSet>(
                initialValue: _set,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Set',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final s in _sets)
                    DropdownMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(s.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: MetaRow([
                              MetaItem(AppIcons.folderOpen,
                                  _store.folder(s.folderId)?.name ?? 'No folder'),
                              MetaItem(AppIcons.flashcards,
                                  plural(s.cards.length, 'card')),
                            ], gap: 8),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (s) => setState(() => _set = s ?? _set),
              )
            else
              FolderField(
                folders: _folders,
                folder: _folder,
                onChanged: (f) => setState(() => _folder = f),
                onNewFolder: _newFolder,
              ),
            const SizedBox(height: 20),
            AccentButton(
              label: _addToSet ? 'Add Cards' : 'Make Flashcards',
              onPressed: _submit,
            ),
            if (!_addToSet && _folder?.id != widget.note.folderId) ...[
              const SizedBox(height: 8),
              Text('The note stays in its own Notebook.',
                  style: AppText.itemMeta),
            ],
          ],
        ),
      ),
    );
  }
}
