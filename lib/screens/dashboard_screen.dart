import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/folder_card.dart';
import '../widgets/progress_ring.dart';
import '../widgets/streak_badge.dart';
import 'actions.dart';
import 'analysis_screen.dart';
import 'focus_screen.dart';
import 'plans_screen.dart';
import 'search_results.dart';

/// Home: greeting, this week's days, today's focus goal, the week at a
/// glance, the task to continue, folders and recent notes.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onOpenLibrary,
    this.onOpenStudy,
    this.onCapture,
    this.onOpenProfile,
  });

  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenStudy;
  final VoidCallback? onCapture;
  final VoidCallback? onOpenProfile;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _query = '';
  final _search = TextEditingController();

  /// The search field shows after tapping the search button.
  bool _searching = false;

  /// Day picked in the week strip; null means today.
  DateTime? _day;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final query = _query.trim();
        final today = startOfDay(clock.now());
        // A day picked last week (app left open overnight) falls back to today.
        final picked = _day;
        final day = picked != null && startOfWeek(picked) == startOfWeek(today)
            ? picked
            : today;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            _Greeting(
              name: store.prefs.userName,
              streak: store.streakDays,
              searching: _searching,
              onSearch: _toggleSearch,
              onAvatar: widget.onOpenProfile,
              onAddName: () => _askName(context),
            ),
            if (_searching) ...[
              const SizedBox(height: 16),
              AppSearchField(
                controller: _search,
                autofocus: true,
                hint: 'Search notes, cards and folders',
                onChanged: (q) => setState(() => _query = q),
              ),
            ],
            if (query.isNotEmpty)
              ...buildSearchResults(context, query)
            else
              ..._home(context, store, today, day),
          ],
        );
      },
    );
  }

  Future<void> _askName(BuildContext context) async {
    final store = AppStore.instance;
    final name = await showTextInputDialog(
      context,
      title: 'What Should We Call You?',
      initial: store.prefs.userName,
      hint: 'Your name',
    );
    if (name == null) return;
    store.updatePrefs(store.prefs.copyWith(userName: name.trim()));
  }

  List<Widget> _home(
      BuildContext context, AppStore store, DateTime today, DateTime day) {
    final folders = store.recentFolders(12);
    final task = store.currentTask;
    final notes = store.notes.take(4).toList();
    final decks = store.recentSets(3);
    final monday = startOfWeek(today);
    final week = [
      for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i),
    ];

    return [
      const SizedBox(height: 20),
      _WeekStrip(
        today: today,
        selected: day,
        isActive: store.activeOn,
        onSelect: (d) => setState(() => _day = d == today ? null : d),
      ),
      const SizedBox(height: 18),
      _GoalCard(
        title: day == today
            ? "Today's Focus"
            : '${weekdayShort(day)}, ${day.day} ${monthShort(day)}',
        minutes: store.focusMinutesOn(day),
        goal: store.settings.dailyGoalMinutes,
        cards: store.cardsReviewedOn(day),
        onStart: startFocusFrom,
      ),
      const SizedBox(height: 14),
      _WeekCard(
        days: week,
        today: today,
        minutes: [for (final d in week) store.focusMinutesOn(d)],
        onTap: () => openAnalysis(context),
      ),
      const SizedBox(height: 24),

      // Continue
      SectionHeader(
        title: 'Continue',
        actionLabel: 'All Tasks',
        onViewAll: widget.onOpenStudy,
      ),
      const SizedBox(height: 12),
      if (task != null)
        _ContinueCard(
          task: task,
          focusLength: store.settings.focusMinutes,
          onTap: widget.onOpenStudy,
          onPlay: startFocusFrom,
        )
      else
        EmptyState(
          icon: AppIcons.newTask,
          message: 'No tasks yet. Add one to start a Pomodoro.',
          actionLabel: 'Go to Study',
          onAction: widget.onOpenStudy,
        ),

      // Flashcard sets studied lately
      if (decks.isNotEmpty) ...[
        const SizedBox(height: 24),
        SectionHeader(title: 'Recent Flashcards', onViewAll: widget.onOpenLibrary),
        const SizedBox(height: 12),
        Container(
          decoration: _cardBox(18),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < decks.length; i++) ...[
                  if (i > 0) const Divider(),
                  _DeckRow(
                    deck: decks[i],
                    color: store.folder(decks[i].folderId)?.color ??
                        AppColors.primary,
                    now: clock.now(),
                    onStudy: () => studySet(context, decks[i]),
                    onOpen: () => openSet(context, decks[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),

      // Folders: three tiles that fit the width (no half-hidden tile);
      // View All opens the rest in the Library.
      SectionHeader(title: 'Folders', onViewAll: widget.onOpenLibrary),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _folderSlots; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: i < folders.length
                  ? FolderCard(
                      folder: folders[i],
                      noteCount: store.noteCountIn(folders[i].id),
                      setCount: store.setCountIn(folders[i].id),
                      onTap: () => openFolder(context, folders[i]),
                      onLongPress: () => editFolder(context, folders[i]),
                    )
                  : i == folders.length
                      ? NewFolderCard(onTap: () => createFolder(context))
                      : const SizedBox.shrink(),
            ),
          ],
        ],
      ),

      if (!store.prefs.hidePlusBanner) ...[
        const SizedBox(height: 20),
        _PlusStrip(onTap: () => openPlans(context)),
      ],
      const SizedBox(height: 24),

      // Recent notes
      SectionHeader(title: 'Recent Notes', onViewAll: widget.onOpenLibrary),
      const SizedBox(height: 8),
      if (notes.isEmpty)
        EmptyState(
          icon: AppIcons.capture,
          message: 'Scan the board or your notebook and save it as a PDF.',
          actionLabel: 'Scan Notes',
          onAction: widget.onCapture,
        )
      else
        for (final note in notes) noteTile(context, note),
    ];
  }
}

/// Folder tiles shown on the Dashboard.
const int _folderSlots = 3;

/// Card outline used by the Dashboard cards.
BoxDecoration _cardBox(double radius) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border),
    );

/// Ring toward the daily focus goal, the numbers, and a Start Focus button.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.title,
    required this.minutes,
    required this.goal,
    required this.cards,
    required this.onStart,
  });

  final String title;
  final int minutes;
  final int goal;
  final int cards;

  /// Called with the button's context, so Focus Mode can grow out of it.
  final void Function(BuildContext button) onStart;

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : minutes / goal;
    final pct = (progress * 100).round();
    final muted = TextStyle(
        fontSize: 12, height: 1.4, color: AppColors.textSecondary);
    final strong = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBox(20),
      child: Row(
        children: [
          ProgressRing(
            progress: progress,
            size: 104,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$pct%',
                      style: TextStyle(
                        fontFamily: kHeadingFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      )),
                ),
                Text('of goal',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sectionTitle),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$minutes', style: strong),
                    TextSpan(text: ' of $goal min · '),
                    TextSpan(text: '$cards', style: strong),
                    TextSpan(text: cards == 1 ? ' card reviewed' : ' cards reviewed'),
                  ]),
                  style: muted,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: Builder(
                    builder: (button) => FilledButton(
                      onPressed: () => onStart(button),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onFill,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.start, size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Start Focus',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "This Week": total, daily average and a tiny bar per day. Tap for the
/// full Analysis.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.days,
    required this.today,
    required this.minutes,
    required this.onTap,
  });

  final List<DateTime> days;
  final DateTime today;
  final List<int> minutes;
  final VoidCallback onTap;

  static const _barsHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    var total = 0;
    var past = 0;
    var most = 60;
    for (var i = 0; i < 7; i++) {
      if (!days[i].isAfter(today)) {
        total += minutes[i];
        past++;
      }
      if (minutes[i] > most) most = minutes[i];
    }
    final avg = past == 0 ? 0 : total ~/ past;

    return Semantics(
      button: true,
      label: 'This week: ${formatMinutes(total)} focused. Open Analysis',
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              children: [
                Flexible(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.chart,
                              size: 16, color: AppColors.primaryDeep),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('This Week',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: kHeadingFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(formatMinutes(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kHeadingFont,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          )),
                      Text('Daily avg ${formatMinutes(avg)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: SizedBox(
                    height: _barsHeight + 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: _MiniBar(
                              label: weekdayShort(days[i]).substring(0, 1),
                              fraction: minutes[i] / most,
                              highlighted: days[i] == today,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Icon(AppIcons.chevronRight,
                    size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({
    required this.label,
    required this.fraction,
    required this.highlighted,
  });

  final String label;
  final double fraction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final f = fraction <= 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    final raw = _WeekCard._barsHeight * f;
    final h = f == 0 ? 3.0 : (raw < 6 ? 6.0 : raw);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 10,
          height: h,
          decoration: BoxDecoration(
            color: f == 0
                ? AppColors.chartEmpty
                : (highlighted ? AppColors.chartStrong : AppColors.chartSoft),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(4),
              bottom: Radius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 9.5,
            height: 1,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
            color: highlighted ? AppColors.ink : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// The current task with its progress and a play button.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.task,
    required this.focusLength,
    required this.onTap,
    required this.onPlay,
  });

  final StudyTask task;
  final int focusLength;
  final VoidCallback? onTap;

  /// Starts a Pomodoro on this task (Focus Mode grows out of the button).
  final void Function(BuildContext button) onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.itemTitle.copyWith(fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${task.pomodorosDone} of ${plural(task.pomodorosTotal, 'Pomodoro')} · '
                      '${task.focusMinutes} / ${task.pomodorosTotal * focusLength} min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 6,
                        color: AppColors.primary,
                        backgroundColor: AppColors.primarySoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Builder(
                builder: (button) => Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Start Focus',
                    onPressed: () => onPlay(button),
                    icon: const Icon(AppIcons.start,
                        size: 18, color: AppColors.onFill),
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flashcard set in the "Recent Flashcards" list. The whole row starts
/// studying (long-press opens the set); a small ring on the right shows how
/// many cards were known last time. No buttons, so the list stays calm.
class _DeckRow extends StatelessWidget {
  const _DeckRow({
    required this.deck,
    required this.color,
    required this.now,
    required this.onStudy,
    required this.onOpen,
  });

  final FlashcardSet deck;
  final Color color;
  final DateTime now;
  final VoidCallback onStudy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final studied = deck.lastStudiedAt;
    final seen = deck.lastSeen;
    final scored = studied != null && seen > 0;
    final score = scored ? deck.lastKnown / seen : 0.0;
    final deep = Color.lerp(color, AppColors.ink, 0.35)!;

    return Semantics(
      button: true,
      label: 'Study ${deck.title}',
      child: InkWell(
        onTap: onStudy,
        onLongPress: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tint(color, 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(AppIcons.flashcards,
                    size: 18, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.itemTitle.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plural(deck.cards.length, 'card')} · '
                      '${studied == null ? 'Not studied yet' : formatAgo(studied, now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (scored)
                Semantics(
                  label: '${deck.lastKnown} of $seen known last time',
                  child: ProgressRing(
                    progress: score,
                    size: 38,
                    strokeWidth: 3.5,
                    color: deep,
                    trackColor: AppColors.tint(color, 0.35),
                    child: Text(
                      '${(score * 100).round()}%',
                      style: TextStyle(
                        fontFamily: kHeadingFont,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  'New',
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDeep,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(AppIcons.chevronRight,
                  size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-line tAsikaso+ invitation.
class _PlusStrip extends StatelessWidget {
  const _PlusStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: PlusHero.gradient),
        child: InkWell(
          onTap: onTap,
          child: const Stack(
            children: [
              // Soft circles, like the big tAsikaso+ card.
              Positioned(
                right: -24,
                top: -44,
                child: PlusBlob(size: 110, alpha: 0.08),
              ),
              Positioned(
                right: 64,
                bottom: -52,
                child: PlusBlob(size: 84, alpha: 0.06),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(AppIcons.plus, size: 20, color: AppColors.gold),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Try $kPlusName free',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              )),
                          Text('Suggested cards, full history, backup',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    Icon(AppIcons.chevronRight, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top row: avatar (opens Profile), the streak and search. Below it, on its own
/// full-width line, "Hello, Budi!". Only the first name is used; a long one
/// wraps to a second line rather than being cut off.
class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.streak,
    required this.searching,
    required this.onSearch,
    required this.onAvatar,
    required this.onAddName,
  });

  final String name;
  final int streak;
  final bool searching;
  final VoidCallback onSearch;
  final VoidCallback? onAvatar;
  final VoidCallback onAddName;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final first = trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
    final initial = first.isEmpty ? null : first.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Profile',
              child: GestureDetector(
                onTap: onAvatar,
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.primarySoft,
                  child: initial == null
                      ? Icon(AppIcons.avatar,
                          size: 20, color: AppColors.primaryDeep)
                      : Text(
                          initial,
                          style: TextStyle(
                            fontFamily: kHeadingFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                ),
              ),
            ),
            const Spacer(),
            _StreakChip(days: streak),
            const SizedBox(width: 8),
            Material(
              color: AppColors.searchFill,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: searching ? 'Close Search' : 'Search',
                onPressed: onSearch,
                icon: Icon(searching ? AppIcons.close : AppIcons.search,
                    size: 20, color: AppColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        GestureDetector(
          onTap: first.isEmpty ? onAddName : null,
          child: Text(
            first.isEmpty ? 'Hello there!' : 'Hello, $first!',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kHeadingFont,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// Flame + number of days in a row.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$days day streak',
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
        decoration: BoxDecoration(
          color: AppColors.streakSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StreakFlame(size: 18),
            const SizedBox(width: 3),
            Text(
              '$days',
              style: TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.streakText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mon–Sun of this week: day names on top, dates in circles below. The
/// picked day (today by default) is a dark filled circle; a small dot marks
/// days you studied.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.today,
    required this.selected,
    required this.isActive,
    required this.onSelect,
  });

  final DateTime today;
  final DateTime selected;
  final bool Function(DateTime day) isActive;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = startOfWeek(today);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayChip(
              day: DateTime(monday.year, monday.month, monday.day + i),
              today: today,
              selected: selected,
              active: isActive(DateTime(monday.year, monday.month, monday.day + i)),
              onTap: onSelect,
            ),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.today,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final DateTime selected;
  final bool active;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final isSelected = day == selected;
    final future = day.isAfter(today);

    final Color fill;
    final Color border;
    final Color number;
    if (isSelected) {
      fill = AppColors.ink;
      border = AppColors.ink;
      number = AppColors.onPrimaryDeep;
    } else if (isToday) {
      fill = AppColors.surface;
      border = AppColors.primary;
      number = AppColors.primaryDeep;
    } else {
      fill = AppColors.surface;
      border = AppColors.border;
      number = future ? AppColors.textMuted : AppColors.ink;
    }

    return Semantics(
      button: !future,
      selected: isSelected,
      label: formatLongDate(day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: future ? null : () => onTap(day),
        child: Column(
          children: [
            Text(
              weekdayShort(day),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.ink : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: isToday ? 1.5 : 1),
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: kHeadingFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: number,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.primaryDeep : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
