import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/list_items.dart';
import '../widgets/progress_ring.dart';
import 'actions.dart';
import 'analysis_screen.dart';
import 'focus_screen.dart';
import 'task_editor.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final _store = AppStore.instance;
  final _timer = PomodoroController.instance;

  /// On the START button, so Focus Mode can grow out of it.
  final _startKey = GlobalKey();

  bool _showCompleted = false;

  /// Starts (or resumes) the timer and opens Focus Mode.
  void _startAndFocus() {
    _timer.start();
    _openFocus();
  }

  void _openFocus() {
    final box = _startKey.currentContext?.findRenderObject() as RenderBox?;
    // Relative to the navigator, which is centred (not at 0,0) on wide screens.
    final nav = Navigator.of(context).context.findRenderObject() as RenderBox?;
    final size = MediaQuery.sizeOf(context);
    final origin = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero), ancestor: nav)
        : Offset(size.width / 2, size.height / 2);
    openFocusScreen(context, origin);
  }

  MenuActions _taskActions(StudyTask t) => {
        if (!t.done && t.id != _store.currentTask?.id)
          'Work on This': () => _store.selectTask(t.id),
        if (!t.done) 'Edit Task': () => showTaskEditor(context, task: t),
        (t.done ? 'Mark as Not Done' : 'Mark as Done'): () =>
            _store.updateTask(t.copyWith(done: !t.done)),
        'Delete': () =>
            deleteTaskWithUndo(ScaffoldMessenger.of(context), t),
      };

  Future<void> _clearCompleted() async {
    final n = _store.completedTasks.length;
    final ok = await showConfirmDialog(
      context,
      title: 'Clear Completed?',
      message: '${plural(n, 'finished task')} will be removed. Your focus '
          'history stays in Pomodoro Analysis.',
      confirmLabel: 'Clear',
    );
    if (ok) _store.clearCompletedTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeader(title: 'Study', onSettings: () => openSettings(context)),
        Expanded(
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final current = _store.currentTask;
              final active = _store.activeTasks;
              final completed = _store.completedTasks;
              final focus = _store.settings.focusMinutes;

              final now = clock.now();
              final today = DateTime(now.year, now.month, now.day);
              final todayCount = _store
                  .sessionsBetween(
                      today, DateTime(today.year, today.month, today.day + 1))
                  .length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                children: [
                  ListenableBuilder(
                    listenable: _timer,
                    builder: (context, _) => _PomodoroCard(
                      timer: _timer,
                      startKey: _startKey,
                      sessionsPerCycle: _store.settings.longBreakEvery,
                      onStart: _startAndFocus,
                      onOpenFocus: _openFocus,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _TodayStrip(
                    pomodoros: todayCount,
                    minutes: _store.focusMinutesToday,
                    onAnalysis: () => openAnalysis(context),
                  ),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: 'Tasks',
                    actionLabel: 'New Task',
                    onViewAll: () => showTaskEditor(context),
                  ),
                  const SizedBox(height: 12),
                  if (active.isEmpty && completed.isEmpty)
                    EmptyState(
                      icon: AppIcons.newTask,
                      message: 'Add a task so your Pomodoros count toward it.',
                      actionLabel: 'New Task',
                      onAction: () => showTaskEditor(context),
                    )
                  else if (active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('All tasks are done. Nice work!',
                          style: AppText.statLabel),
                    ),
                  for (final task in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TaskCard(
                        key: ValueKey(task.id),
                        task: task,
                        focusLength: focus,
                        current: task.id == current?.id,
                        onTap: () => _store.selectTask(task.id),
                        actions: _taskActions(task),
                      ),
                    ),
                  if (completed.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => setState(() => _showCompleted = !_showCompleted),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text('Completed (${completed.length})',
                                style: AppText.sectionTitle),
                            const SizedBox(width: 6),
                            Icon(
                              _showCompleted
                                  ? AppIcons.chevronUp
                                  : AppIcons.chevronDown,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showCompleted) ...[
                      for (final task in completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TaskCard(
                            key: ValueKey(task.id),
                            task: task,
                            focusLength: focus,
                            actions: _taskActions(task),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _clearCompleted,
                          icon: const Icon(AppIcons.delete, size: 16),
                          label: const Text('Clear Completed'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
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

/// Mode switch, ring timer and the Reset / START / Skip buttons.
class _PomodoroCard extends StatelessWidget {
  const _PomodoroCard({
    required this.timer,
    required this.startKey,
    required this.sessionsPerCycle,
    required this.onStart,
    required this.onOpenFocus,
  });

  final PomodoroController timer;
  final GlobalKey startKey;

  /// Pomodoros before a long break ("Session 2 of 4").
  final int sessionsPerCycle;
  final VoidCallback onStart;
  final VoidCallback onOpenFocus;

  @override
  Widget build(BuildContext context) {
    final running = timer.running;
    final atStart = timer.atStart;
    final mode = timer.mode;
    final String buttonLabel = running ? 'PAUSE' : (atStart ? 'START' : 'RESUME');
    final cycle = sessionsPerCycle < 1 ? 1 : sessionsPerCycle;
    final session = ((timer.session - 1) % cycle) + 1;

    return Column(
      children: [
        // Pomodoro / Short Break / Long Break
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.searchFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              for (final m in TimerMode.values)
                Expanded(
                  child: _ModeTab(
                    label: m.label,
                    selected: m == mode,
                    onTap: () => timer.selectMode(m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _MaybeTooltip(
          message: running ? 'Open Focus Mode' : null,
          child: GestureDetector(
            onTap: running ? onOpenFocus : null,
            child: ProgressRing(
              progress: timer.progress,
              size: 236,
              strokeWidth: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(timer.timeText,
                          style: AppText.timer.copyWith(fontSize: 52)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timer.isFocus ? 'Session $session of $cycle' : mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundIconButton(
              icon: AppIcons.reset,
              tooltip: 'Reset Timer',
              onPressed: atStart ? null : timer.reset,
            ),
            const SizedBox(width: 20),
            Flexible(
              child: Material(
                key: startKey,
                color: AppColors.primary,
                shape: const StadiumBorder(),
                elevation: 0,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: running ? timer.pause : onStart,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(running ? AppIcons.pause : AppIcons.start,
                            size: 18, color: AppColors.onFill),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            buttonLabel,
                            style: AppText.button,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            _RoundIconButton(
              icon: AppIcons.skip,
              tooltip: timer.isFocus ? 'Skip to Break' : 'Skip Break',
              onPressed: timer.skip,
            ),
          ],
        ),
      ],
    );
  }
}

/// Adds a tooltip only when [message] is set.
class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return m == null ? child : Tooltip(message: m, child: child);
  }
}

/// Grey circle icon button (Reset, Skip).
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: AppColors.searchFill,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20, color: AppColors.ink),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
      ),
    );
  }
}

/// "Today · 2 Pomodoros · 50 min        Analysis >"
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({
    required this.pomodoros,
    required this.minutes,
    required this.onAnalysis,
  });

  final int pomodoros;
  final int minutes;
  final VoidCallback onAnalysis;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onAnalysis,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(AppIcons.chart, size: 18, color: AppColors.primaryDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Today · ${plural(pomodoros, 'Pomodoro')} · ${formatMinutes(minutes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                'Analysis',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDeep,
                ),
              ),
              Icon(AppIcons.chevronRight,
                  size: 16, color: AppColors.primaryDeep),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.segmentOn : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.shadow(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppColors.ink : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
