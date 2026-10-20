import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Asks for a single line of text. Returns null if cancelled, and also if
/// the text is empty unless [allowEmpty] (then '' means "cleared").
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = 'Save',
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.confirmLabel,
    required this.allowEmpty,
  });

  final String title;
  final String initial;
  final String hint;
  final String confirmLabel;
  final bool allowEmpty;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty && !widget.allowEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppText.sectionTitle),
      content: Semantics(
        // The field has no label of its own; the title says what it's for.
        label: widget.title,
        child: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onFill,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Yes/no question. Returns true only if confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppText.sectionTitle),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.streakRed,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Tells the user something they need to know, with a single OK.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppText.sectionTitle),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onFill,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Result of the folder editor.
typedef FolderDraft = ({String name, int colorValue});

/// Create or edit a folder: name + colour. When editing, [onDelete] adds a
/// "Delete Folder" button; it runs after the sheet has closed.
Future<FolderDraft?> showFolderEditor(
  BuildContext context, {
  StudyFolder? folder,
  Future<void> Function()? onDelete,
}) {
  return showModalBottomSheet<FolderDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FolderEditor(folder: folder, onDelete: onDelete),
  );
}

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({this.folder, this.onDelete});

  final StudyFolder? folder;
  final Future<void> Function()? onDelete;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.folder?.name ?? '');
  late int _color = widget.folder?.colorValue ?? AppColors.folderPalette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, colorValue: _color));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.folder != null;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle(editing ? 'Edit Folder' : 'New Folder'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Folder Name',
                hintText: 'e.g. Chemistry',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('Color', style: AppText.itemMeta),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < AppColors.folderPalette.length; i++)
                  _ColorDot(
                    color: Color(AppColors.folderPalette[i]),
                    name: AppColors.folderPaletteNames[i],
                    selected: AppColors.folderPalette[i] == _color,
                    onTap: () =>
                        setState(() => _color = AppColors.folderPalette[i]),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: editing ? 'Save' : 'Create Folder',
              onPressed: _name.text.trim().isEmpty ? null : _submit,
            ),
            if (editing && widget.onDelete != null) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () {
                    final onDelete = widget.onDelete!;
                    Navigator.of(context).pop();
                    onDelete();
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.streakRed),
                  child: const Text('Delete Folder'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$name color',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.ink : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(AppIcons.check, size: 18, color: AppColors.onFill)
              : null,
        ),
      ),
    );
  }
}

/// Lets the user pick one of their folders.
Future<StudyFolder?> showFolderPicker(
  BuildContext context, {
  String title = 'Move to Folder',
  String? currentId,
}) {
  final folders = AppStore.instance.folders;
  return showModalBottomSheet<StudyFolder>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          SheetTitle(title),
          const SizedBox(height: 8),
          for (final f in folders)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 10, backgroundColor: f.color),
              title: Text(f.name, style: AppText.itemTitle),
              trailing: f.id == currentId
                  ? Icon(AppIcons.check, color: AppColors.primaryDeep, size: 20)
                  : null,
              onTap: () => Navigator.of(context).pop(f),
            ),
        ],
      ),
    ),
  );
}
