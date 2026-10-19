import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/list_items.dart';
import 'actions.dart';

/// One folder's notes and flashcard sets.
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
                'Edit Folder': () => editFolder(context, folder),
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
              Text(
                '${plural(notes.length, 'note')} · ${plural(sets.length, 'flashcard set')}',
                style: AppText.statLabel,
              ),
              if (notes.isEmpty && sets.isEmpty) ...[
                const SizedBox(height: 16),
                const EmptyState(
                  icon: AppIcons.newFolder,
                  message: 'This folder is empty. Scan notes or make a '
                      'flashcard set and save it here.',
                ),
              ],
              if (sets.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Flashcard Sets', style: AppText.sectionTitle),
                const SizedBox(height: 4),
                for (final s in sets) setTile(context, s),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Notes', style: AppText.sectionTitle),
                const SizedBox(height: 4),
                for (final n in notes) noteTile(context, n),
              ],
            ],
          ),
        );
      },
    );
  }
}
