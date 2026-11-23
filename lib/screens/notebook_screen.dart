import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/meta_row.dart';
import 'actions.dart';
import 'capture/scan_flow.dart';

/// Opens a folder's Notebook: every note saved to the folder.
void openNotebook(BuildContext context, StudyFolder folder) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => NotebookScreen(folderId: folder.id)),
  );
}

/// A folder's Notebook: its notes, newest first. Each folder has one; notes
/// saved to the folder go in it.
class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key, required this.folderId});

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
            appBar: subPageAppBar('Notebook'),
            body: const Center(child: Text('This folder was deleted.')),
          );
        }
        final notes = store.notesIn(folder.id);
        return Scaffold(
          appBar: subPageAppBar('${folder.name} Notebook'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(plural(notes.length, 'note'), style: AppText.statLabel),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                EmptyState(
                  icon: AppIcons.notebook,
                  message: 'This notebook is empty. Scan your notes and save '
                      'them to ${folder.name}.',
                  actionLabel: 'Scan Notes',
                  onAction: () => startScan(context),
                )
              else
                for (final n in notes) noteTile(context, n),
            ],
          ),
        );
      },
    );
  }
}

/// The Notebook on a folder's page: how many notes, and the latest.
class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.folder, required this.notes});

  final StudyFolder folder;

  /// The folder's notes, newest first.
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final latest = notes.isEmpty ? null : notes.first;
    final detail = latest == null
        ? 'No notes yet'
        : '${plural(notes.length, 'note')}, latest: ${latest.title}';
    return Semantics(
      button: true,
      label: '${folder.name} Notebook, $detail',
      excludeSemantics: true,
      onTap: () => openNotebook(context, folder),
      child: Material(
        color: AppColors.tint(folder.color, 0.25),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openNotebook(context, folder),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 52,
                  decoration: BoxDecoration(
                    color: folder.color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(4),
                      right: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(AppIcons.notebook,
                      size: 24, color: AppColors.onFill),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notebook',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 3),
                      if (latest == null)
                        Text(detail, style: AppText.itemMeta)
                      else
                        MetaRow([
                          MetaItem(AppIcons.notebook, plural(notes.length, 'note')),
                          MetaItem(AppIcons.newNote, latest.title),
                        ]),
                    ],
                  ),
                ),
                Icon(AppIcons.chevronRight, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
