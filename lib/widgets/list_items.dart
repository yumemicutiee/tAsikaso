import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';

/// Menu entries for a "⋮" button: label → action.
typedef MenuActions = Map<String, VoidCallback>;

/// "⋮" button built from [MenuActions]. Hidden when there are none.
class ActionsMenu extends StatelessWidget {
  const ActionsMenu({super.key, required this.actions});

  final MenuActions actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox(width: 12);
    return MoreMenu(
      actions: actions.keys.toList(),
      onSelected: (label) => actions[label]?.call(),
    );
  }
}

/// Row for a saved note.
class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.note,
    this.folder,
    this.thumbnail,
    this.onTap,
    this.actions = const {},
  });

  final Note note;
  final StudyFolder? folder;
  final Uint8List? thumbnail;
  final VoidCallback? onTap;
  final MenuActions actions;

  @override
  Widget build(BuildContext context) {
    final f = folder;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            NoteThumbnail(image: thumbnail),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: AppText.itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${formatNoteDate(note.createdAt)} · ${plural(note.pageCount, 'page')}',
                          style: AppText.itemMeta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (f != null) ...[
                        const SizedBox(width: 6),
                        Flexible(child: SubjectTag(label: f.name, color: f.color)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ActionsMenu(actions: actions),
          ],
        ),
      ),
    );
  }
}

/// Row for a flashcard set.
class SetTile extends StatelessWidget {
  const SetTile({
    super.key,
    required this.deck,
    this.folder,
    this.onTap,
    this.actions = const {},
  });

  final FlashcardSet deck;
  final StudyFolder? folder;
  final VoidCallback? onTap;
  final MenuActions actions;

  @override
  Widget build(BuildContext context) {
    final f = folder;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(AppIcons.flashcards,
                  size: 22, color: AppColors.primaryDeep),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.title,
                    style: AppText.itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plural(deck.cards.length, 'card'),
                          style: AppText.itemMeta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (f != null) ...[
                        const SizedBox(width: 6),
                        Flexible(child: SubjectTag(label: f.name, color: f.color)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ActionsMenu(actions: actions),
          ],
        ),
      ),
    );
  }
}

/// Outlined task card. The bar on the left fills up with Pomodoro progress.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.focusLength,
    this.trailing,
    this.onTap,
    this.actions = const {},
    this.current = false,
  });

  final StudyTask task;

  /// Minutes per Pomodoro, for the "100 / 200 mins" label.
  final int focusLength;

  /// Replaces the "⋮" menu when set.
  final Widget? trailing;
  final VoidCallback? onTap;
  final MenuActions actions;

  /// The task the timer is working on: sky outline and a "Current" tag.
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: current ? AppColors.primary : AppColors.border,
          width: current ? 1.5 : 1,
        ),
        boxShadow: current
            ? [
                BoxShadow(
                  color: AppColors.halo(0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                  child: _ProgressBar(progress: task.progress),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.itemTitle.copyWith(
                                  color: task.done ? AppColors.textMuted : null,
                                  decoration:
                                      task.done ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            if (current) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Current',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDeep,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(task.done ? AppIcons.check : AppIcons.play,
                                size: 11, color: AppColors.textSecondary),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                task.progressLabel(focusLength),
                                style: AppText.itemMeta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Center(child: trailing ?? ActionsMenu(actions: actions)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical 4px bar that fills from the bottom.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // CustomPaint (not FractionallySizedBox) so it works inside IntrinsicHeight.
    return SizedBox(
      width: 4,
      child: CustomPaint(
        painter: _ProgressBarPainter(
          progress,
          track: AppColors.primarySoft,
          fill: progress >= 1 ? AppColors.primaryDeep : AppColors.primary,
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.progress, {required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (progress <= 0) return;
    final h = size.height * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        radius,
      ),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.progress != progress || old.track != track || old.fill != fill;
}
