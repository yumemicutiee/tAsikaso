import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'actions.dart';

/// Matching folders, flashcard sets and notes for a search [query].
/// Returns a list of widgets to drop into a ListView.
List<Widget> buildSearchResults(BuildContext context, String query) {
  final store = AppStore.instance;
  final folders = store.searchFolders(query);
  final sets = store.searchSets(query);
  final notes = store.searchNotes(query);

  if (folders.isEmpty && sets.isEmpty && notes.isEmpty) {
    return [
      const SizedBox(height: 20),
      EmptyState(
        icon: AppIcons.search,
        message: 'Nothing matches "$query".',
      ),
    ];
  }

  return [
    if (folders.isNotEmpty) ...[
      const SizedBox(height: 20),
      Text('Folders', style: AppText.sectionTitle),
      const SizedBox(height: 4),
      for (final f in folders)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 12, backgroundColor: f.color),
          title: Text(f.name, style: AppText.itemTitle),
          subtitle: Text(
            '${store.noteCountIn(f.id)} notes · ${store.setCountIn(f.id)} sets',
            style: AppText.itemMeta,
          ),
          onTap: () => openFolder(context, f),
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
  ];
}
