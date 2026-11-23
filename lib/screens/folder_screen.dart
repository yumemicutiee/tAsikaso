import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/list_items.dart';
import '../widgets/meta_row.dart';
import 'actions.dart';
import 'notebook_screen.dart';

/// One folder: its Notebook (the notes) and its flashcard sets.
class FolderScreen extends StatelessWidget {
  const FolderScreen({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final folder = store.folder(folderId);
        if (folder == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: AppColors.background),
            body: const Center(child: Text('This folder was deleted.')),
          );
        }
        final notes = store.notesIn(folder.id);
        final sets = store.setsIn(folder.id);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.ink,
            titleSpacing: 0,
            title: Row(
              children: [
                CircleAvatar(radius: 9, backgroundColor: folder.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kHeadingFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              ActionsMenu(actions: {
                'Edit Folder': () => editFolder(context, folder,
                    onDeleted: () => Navigator.of(context).pop()),
                'New Flashcard Set': () => createSet(context, folderId: folder.id),
                'Delete Folder': () async {
                  final deleted = await deleteFolder(context, folder);
                  if (deleted && context.mounted) Navigator.of(context).pop();
                },
              }),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              MetaRow([
                MetaItem(AppIcons.notebook, plural(notes.length, 'note')),
                MetaItem(AppIcons.flashcards, plural(sets.length, 'flashcard set')),
              ], style: AppText.statLabel),
              // Each folder has one Notebook, where its notes are.
              const SizedBox(height: 16),
              NotebookCard(folder: folder, notes: notes),
              const SizedBox(height: 24),
              Text('Flashcard Sets', style: AppText.sectionTitle),
              const SizedBox(height: 4),
              if (sets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No flashcard sets yet. Open a note in the Notebook and '
                    'tap Make Flashcards, or make a set from the menu.',
                    style: AppText.statLabel,
                  ),
                )
              else
                for (final s in sets) setTile(context, s),
            ],
          ),
        );
      },
    );
  }
}
