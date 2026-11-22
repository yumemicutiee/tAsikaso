import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'dialogs.dart';

/// Makes a folder right where one is being picked (a save sheet, the Make
/// Flashcards sheet), with the folder editor. Null when cancelled.
Future<StudyFolder?> createFolderHere(BuildContext context) async {
  final draft = await showFolderEditor(context);
  if (draft == null) return null;
  return AppStore.instance.addFolder(draft.name, draft.colorValue);
}

/// The Folder picker of a sheet, with a New button to make one there.
class FolderField extends StatelessWidget {
  const FolderField({
    super.key,
    required this.folders,
    required this.folder,
    required this.onChanged,
    required this.onNewFolder,
    this.helper,
  });

  final List<StudyFolder> folders;
  final StudyFolder? folder;
  final ValueChanged<StudyFolder> onChanged;
  final VoidCallback onNewFolder;

  /// A line under the picker, e.g. where in the folder things go.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: folders.isEmpty
              ? Text('A folder called "My Notes" will be created.',
                  style: AppText.statLabel)
              : DropdownButtonFormField<StudyFolder>(
                  // Rebuilt when a new folder is picked for us.
                  key: ValueKey(folder?.id),
                  initialValue: folder,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Folder',
                    helperText: helper,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final f in folders)
                      DropdownMenuItem(
                        value: f,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: f.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(f.name,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (f) {
                    if (f != null) onChanged(f);
                  },
                ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'New Folder',
          child: OutlinedButton(
            onPressed: onNewFolder,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: BorderSide(color: AppColors.border),
              minimumSize: const Size(48, 46),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            // The tooltip is the label; "New" would be read too.
            child: const ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.newFolder, size: 18),
                  SizedBox(width: 6),
                  Text('New',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One choice on a sheet (Text Notes, Scan PDF, New Set…): an icon, a title
/// and a line about it, outlined when picked.
class FormatOption extends StatelessWidget {
  const FormatOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? AppColors.ink : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: selected ? 13 : 14, vertical: selected ? 11 : 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppColors.primaryDeep : ink, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.itemMeta),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(AppIcons.check, size: 18, color: AppColors.primaryDeep),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
