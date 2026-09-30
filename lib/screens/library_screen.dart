import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/folder_card.dart';
import 'actions.dart';
import 'search_results.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onCapture});

  final VoidCallback? onCapture;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return Column(
      children: [
        const AppHeader(title: 'Library'),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final query = _query.trim();
              final folders = store.folders;
              final sets = store.sets;
              final notes = store.notes;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                children: [
                  AppSearchField(
                    controller: _search,
                    hint: 'Search notes, cards and folders',
                    onChanged: (q) => setState(() => _query = q),
                  ),
                  if (query.isNotEmpty)
                    ...buildSearchResults(context, query)
                  else ...[
                    const SizedBox(height: 20),
                    Text('Folders (${folders.length})', style: AppText.sectionTitle),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: folders.length + 1,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: FolderCard.aspectRatio,
                      ),
                      itemBuilder: (context, i) {
                        if (i == folders.length) {
                          return NewFolderCard(onTap: () => createFolder(context));
                        }
                        final f = folders[i];
                        return FolderCard(
                          folder: f,
                          noteCount: store.noteCountIn(f.id),
                          setCount: store.setCountIn(f.id),
                          onTap: () => openFolder(context, f),
                          onLongPress: () => editFolder(context, f),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Flashcard Sets (${sets.length})',
                      actionLabel: 'New Set',
                      onViewAll: () => createSet(context),
                    ),
                    const SizedBox(height: 4),
                    if (sets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No flashcard sets yet.',
                          style: AppText.statLabel,
                        ),
                      )
                    else
                      for (final s in sets) setTile(context, s),
                    const SizedBox(height: 24),
                    Text('Notes (${notes.length})', style: AppText.sectionTitle),
                    const SizedBox(height: 8),
                    if (notes.isEmpty)
                      EmptyState(
                        icon: AppIcons.capture,
                        message: 'Notes you scan will appear here.',
                        actionLabel: 'Scan Notes',
                        onAction: widget.onCapture,
                      )
                    else
                      for (final n in notes) noteTile(context, n),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
