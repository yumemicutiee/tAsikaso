import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/number_field.dart';

/// Deletes [task] and offers "Undo" for a few seconds.
void deleteTaskWithUndo(ScaffoldMessengerState messenger, StudyTask task) {
  final store = AppStore.instance;
  final removed = store.deleteTask(task.id);
  if (removed == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Deleted "${task.title}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => store.restoreTask(removed),
      ),
    ));
}

/// Create a task, or edit / delete an existing one.
Future<void> showTaskEditor(BuildContext context, {StudyTask? task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskEditor(task: task),
  );
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.task});

  final StudyTask? task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late int _pomodoros = widget.task?.pomodorosTotal ?? 4;

  static const _min = 1;
  static const _max = 20;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final store = AppStore.instance;
    final task = widget.task;
    if (task == null) {
      final created = store.addTask(title, _pomodoros);
      store.selectTask(created.id);
    } else {
      store.updateTask(task.copyWith(title: title, pomodorosTotal: _pomodoros));
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final task = widget.task;
    if (task == null) return;
    final ok = await showConfirmDialog(context,
        title: 'Delete Task?', message: '"${task.title}" will be deleted.');
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    deleteTaskWithUndo(messenger, task);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;
    final focus = AppStore.instance.settings.focusMinutes;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle(editing ? 'Edit Task' : 'New Task'),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Task',
                hintText: 'e.g. Review Chapter 3',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated Pomodoros', style: AppText.itemTitle),
                      const SizedBox(height: 2),
                      Text('About ${_pomodoros * focus} minutes of focus',
                          style: AppText.itemMeta),
                    ],
                  ),
                ),
                NumberField(
                  value: _pomodoros,
                  min: _min,
                  max: _max,
                  label: 'Estimated Pomodoros',
                  onChanged: (v) => setState(() => _pomodoros = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: editing ? 'Save' : 'Add Task',
              onPressed: _title.text.trim().isEmpty ? null : _save,
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.streakRed),
                  child: const Text('Delete Task'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
