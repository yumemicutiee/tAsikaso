import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/segmented_tabs.dart';
import '../widgets/streak_badge.dart';

Future<void> openAnalysis(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AnalysisScreen()),
    );

/// Pomodoro Analysis.
///
/// Overview: pick a week, month or year; everything below follows it —
/// the summary, History bars, Productive Hours, the focus / break split and
/// focus by task. The Heatmap and streak always show the last few months.
///
/// Timeline: every Pomodoro and break, newest first.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

enum _Period { week, month, year }

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _store = AppStore.instance;

  int _tab = 0; // 0 Overview, 1 Timeline
  _Period _period = _Period.week;
  late DateTime _start = _startOf(_Period.week, clock.now());

  /// Bar picked in History. Null shows the default (today, or the best).
  int? _picked;

  static DateTime _startOf(_Period p, DateTime d) => switch (p) {
        _Period.week => startOfWeek(d),
        _Period.month => DateTime(d.year, d.month),
        _Period.year => DateTime(d.year),
      };

  static DateTime _shift(_Period p, DateTime start, int by) => switch (p) {
        _Period.week => DateTime(start.year, start.month, start.day + 7 * by),
        _Period.month => DateTime(start.year, start.month + by),
        _Period.year => DateTime(start.year + by),
      };

  void _setPeriod(int i) => setState(() {
        _period = _Period.values[i];
        _start = _startOf(_period, clock.now());
        _picked = null;
      });

  void _move(int by) => setState(() {
        _start = _shift(_period, _start, by);
        _picked = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subPageAppBar('Pomodoro Analysis'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SegmentedTabs(
              labels: const ['Overview', 'Timeline'],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) =>
                  _tab == 0 ? _overview(context) : _Timeline(store: _store),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(BuildContext context) {
    final now = clock.now();
    final today = startOfDay(now);
    final end = _shift(_period, _start, 1);
    final isCurrent = !today.isBefore(_start) && today.isBefore(end);

    // History buckets: days (week, month) or months (year).
    final buckets = <DateTime>[
      if (_period == _Period.year)
        for (var m = 0; m < 12; m++) DateTime(_start.year, m + 1)
      else
        for (var d = _start;
            d.isBefore(end);
            d = DateTime(d.year, d.month, d.day + 1))
          d,
    ];
    DateTime bucketEnd(DateTime b) => _period == _Period.year
        ? DateTime(b.year, b.month + 1)
        : DateTime(b.year, b.month, b.day + 1);
    final minutes = [
      for (final b in buckets) _store.focusMinutesBetween(b, bucketEnd(b)),
    ];
    final sessions = _store.sessionsBetween(_start, end);
    final breaks = _store.breaksBetween(_start, end);
    final total = minutes.fold(0, (a, b) => a + b);

    // Averages count only the days that have happened.
    final lastDay = isCurrent ? today : DateTime(end.year, end.month, end.day - 1);
    // round(): a day can be 23 or 25 hours long.
    final elapsedDays = lastDay.isBefore(_start)
        ? 1
        : (lastDay.difference(_start).inHours / 24).round() + 1;
    final best = _indexOfMax(minutes);

    // Compare like with like: only as far into last week (month, year) as
    // this one has got.
    final prevStart = _shift(_period, _start, -1);
    var prevEnd = _start;
    if (isCurrent) {
      final same = DateTime(
          prevStart.year, prevStart.month, prevStart.day + elapsedDays);
      if (same.isBefore(_start)) prevEnd = same;
    }
    final prevTotal = _store.focusMinutesBetween(prevStart, prevEnd);

    int? todayIndex;
    if (isCurrent) {
      todayIndex = _period == _Period.year
          ? today.month - 1
          : buckets.indexWhere((b) => b == today);
      if (todayIndex < 0) todayIndex = null;
    }
    final shown = _picked ?? todayIndex ?? best ?? 0;

    String bucketName(int i, {bool long = false}) {
      final b = buckets[i];
      if (_period == _Period.year) {
        return long ? '${monthShort(b)} ${b.year}' : monthShort(b);
      }
      return long
          ? '${weekdayShort(b)}, ${b.day} ${monthShort(b)}'
          : weekdayShort(b);
    }

    // Labels under the bars; months show only every 7th day.
    String axisLabel(DateTime b) {
      switch (_period) {
        case _Period.week:
          return weekdayShort(b).substring(0, 1);
        case _Period.month:
          return const {1, 8, 15, 22, 29}.contains(b.day) ? '${b.day}' : '';
        case _Period.year:
          return monthShort(b).substring(0, 1);
      }
    }

    final String title;
    final String sub;
    switch (_period) {
      case _Period.week:
        title = isCurrent ? 'This Week' : formatWeekRange(_start);
        sub = formatWeekRange(_start);
      case _Period.month:
        title = isCurrent ? 'This Month' : '${monthLong(_start)} ${_start.year}';
        sub = '${monthLong(_start)} ${_start.year}';
      case _Period.year:
        title = isCurrent ? 'This Year' : '${_start.year}';
        sub = '${_start.year}';
    }
    final previousName = switch (_period) {
      _Period.week => 'last week',
      _Period.month => 'last month',
      _Period.year => 'last year',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        SegmentedTabs(
          labels: const ['Week', 'Month', 'Year'],
          selected: _period.index,
          dense: true,
          onChanged: _setPeriod,
        ),
        const SizedBox(height: 6),
        _PeriodSwitcher(
          title: title,
          sub: sub,
          period: _period.name,
          onPrev: () => _move(-1),
          onNext: isCurrent ? null : () => _move(1),
        ),
        const SizedBox(height: 10),
        _Summary(
          total: total,
          previous: prevTotal,
          previousName: previousName,
          pomodoros: sessions.length,
          dailyAverage: total ~/ elapsedDays,
          bestLabel: _period == _Period.year ? 'Best Month' : 'Best Day',
          best: best == null ? '–' : bucketName(best),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'History',
          trailing: Text(
            '${bucketName(shown, long: true)} · ${formatMinutes(minutes[shown])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          child: _Bars(
            minutes: minutes,
            labels: [for (final b in buckets) axisLabel(b)],
            names: [
              for (var i = 0; i < buckets.length; i++) bucketName(i, long: true),
            ],
            goal: _period == _Period.year ? null : _store.settings.dailyGoalMinutes,
            highlighted: shown,
            onPick: (i) => setState(() => _picked = i),
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Productive Hours',
          child: _ProductiveHours(sessions: sessions),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Focus / Break',
          child: _FocusBreak(
            focus: total,
            rest: breaks.fold(0, (a, b) => a + b.minutes),
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Focus by Task',
          child: _ByTask(sessions: sessions),
        ),
        const SizedBox(height: 16),
        _Card(
          title: 'Heatmap',
          child: _Heatmap(store: _store, today: today),
        ),
        const SizedBox(height: 12),
        Text(
          'Only finished Pomodoros count as focus. Skipped breaks count for '
          'the time you took.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// Index of the largest value, or null if all are zero.
  static int? _indexOfMax(List<int> values) {
    int? best;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > 0 && (best == null || values[i] > values[best])) best = i;
    }
    return best;
  }
}

class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({
    required this.title,
    required this.sub,
    required this.period,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final String sub;
  final String period; // "week", "month", "year"
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous ${period[0].toUpperCase()}${period.substring(1)}',
          onPressed: onPrev,
          icon: const Icon(AppIcons.chevronLeft, size: 20),
          color: AppColors.ink,
        ),
        Expanded(
          child: Column(
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sectionTitle),
              if (title != sub)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.statLabel),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Next ${period[0].toUpperCase()}${period.substring(1)}',
          onPressed: onNext,
          icon: const Icon(AppIcons.chevronRight, size: 20),
          color: AppColors.ink,
          disabledColor: AppColors.border,
        ),
      ],
    );
  }
}

/// Navy card: total focus, the change from the previous period, and three
/// small numbers.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.previous,
    required this.previousName,
    required this.pomodoros,
    required this.dailyAverage,
    required this.bestLabel,
    required this.best,
  });

  final int total;
  final int previous;
  final String previousName;
  final int pomodoros;
  final int dailyAverage;
  final String bestLabel;
  final String best;

  @override
  Widget build(BuildContext context) {
    String? change;
    var up = true;
    if (previous > 0) {
      final pct = ((total - previous) * 100 / previous).round();
      up = pct >= 0;
      change = '${up ? '+' : '−'}${pct.abs()}% vs $previousName';
    } else if (total > 0) {
      change = 'Up from 0 $previousName';
    }

    Widget mini(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  )),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.heroTop, AppColors.heroBottom],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Focus Time',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              )),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatMinutes(total),
                      style: const TextStyle(
                        fontFamily: kHeadingFont,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      )),
                ),
              ),
              if (change != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(change,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: up ? AppColors.primary : AppColors.gold,
                        )),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              mini('$pomodoros', 'Pomodoros'),
              mini(formatMinutes(dailyAverage), 'Daily Average'),
              mini(best, bestLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppText.sectionTitle),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: trailing),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Focus minutes per day (or month) as thin bars. Tap one to read it in the
/// card header. A dashed line marks the daily goal.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.minutes,
    required this.labels,
    required this.names,
    required this.highlighted,
    required this.onPick,
    this.goal,
  });

  final List<int> minutes;
  final List<String> labels;
  final List<String> names;
  final int highlighted;
  final ValueChanged<int> onPick;
  final int? goal;

  static const _height = 140.0;
  static const _axis = 34.0; // room for the scale on the right

  @override
  Widget build(BuildContext context) {
    final most = minutes.fold(goal ?? 0, (a, b) => a > b ? a : b);
    // A tidy top for the scale: whole hours, so the middle line is a whole
    // or half hour.
    final top = most <= 60 ? 60 : ((most + 59) ~/ 60) * 60;
    final n = minutes.length;
    final g = goal;

    return Column(
      children: [
        SizedBox(
          height: _height,
          child: LayoutBuilder(builder: (context, box) {
            final slot = (box.maxWidth - _axis) / n;
            final raw = slot * 0.62;
            final barWidth = raw < 3 ? 3.0 : (raw > 18 ? 18.0 : raw);
            return Stack(
              children: [
                // Recessive grid: top and middle lines with small labels.
                for (final f in const [0.0, 0.5])
                  Positioned(
                    top: _height * f,
                    left: 0,
                    right: 0,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(height: 1, color: AppColors.divider),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: _axis - 4,
                          child: Text(
                            _scaleLabel((top * (1 - f)).round()),
                            style: TextStyle(
                                fontSize: 9, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (g != null && g > 0)
                  Positioned(
                    top: _height * (1 - g / top) - 0.5,
                    left: 0,
                    right: _axis,
                    child: const _DashedLine(),
                  ),
                Positioned(
                  left: 0,
                  right: _axis,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: '${names[i]}: ${formatMinutes(minutes[i])}',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onPick(i),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: _Bar(
                                  width: barWidth,
                                  fraction: minutes[i] / top,
                                  highlighted: i == highlighted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: _axis),
          child: Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: SizedBox(
                    height: 14,
                    child: labels[i].isEmpty
                        ? null
                        : OverflowBox(
                            minWidth: 0,
                            maxWidth: 30,
                            child: Text(
                              labels[i],
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: i == highlighted
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: i == highlighted
                                    ? AppColors.ink
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
        if (g != null && g > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 16, child: _DashedLine()),
              const SizedBox(width: 6),
              Text('Daily goal · ${formatMinutes(g)}', style: AppText.itemMeta),
            ],
          ),
        ],
      ],
    );
  }
}

/// Short scale labels: "45m", "1h", "1.5h".
String _scaleLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.width,
    required this.fraction,
    required this.highlighted,
  });

  final double width;
  final double fraction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final f = fraction <= 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    // Empty days still get a small stub so the day is visibly "empty".
    final raw = _Bars._height * f;
    final h = f == 0 ? 3.0 : (raw < 6 ? 6.0 : raw);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: f == 0
            ? AppColors.chartEmpty
            : (highlighted ? AppColors.chartStrong : AppColors.chartSoft),
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(width < 8 ? 2 : 4)),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(builder: (context, box) {
        final count = (box.maxWidth / 7).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              Container(width: 4, height: 1, color: AppColors.textMuted),
              const SizedBox(width: 3),
            ],
          ],
        );
      }),
    );
  }
}

/// Focus minutes by hour of the day (24 cells, darker = more), so you can
/// see when you work best. Tap a cell for its number.
class _ProductiveHours extends StatefulWidget {
  const _ProductiveHours({required this.sessions});

  final List<FocusSession> sessions;

  @override
  State<_ProductiveHours> createState() => _ProductiveHoursState();
}

class _ProductiveHoursState extends State<_ProductiveHours> {
  int? _picked;

  /// Splits each session over the clock hours it covered.
  static List<int> _byHour(List<FocusSession> sessions) {
    final out = List.filled(24, 0);
    for (final s in sessions) {
      var t = s.startedAt;
      final end = s.endedAt;
      while (t.isBefore(end)) {
        final nextHour = DateTime(t.year, t.month, t.day, t.hour + 1);
        final stop = nextHour.isBefore(end) ? nextHour : end;
        out[t.hour] += stop.difference(t).inMinutes;
        t = stop;
      }
    }
    return out;
  }

  static String _hour(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final byHour = _byHour(widget.sessions);
    final most = byHour.fold(0, (a, b) => a > b ? a : b);
    var best = -1;
    for (var h = 0; h < 24; h++) {
      if (byHour[h] > 0 && (best < 0 || byHour[h] > byHour[best])) best = h;
    }
    final picked = _picked;

    final String caption;
    if (most == 0) {
      caption = 'Finish a Pomodoro to see your best hours.';
    } else if (picked != null) {
      caption = '${_hour(picked)} – ${_hour((picked + 1) % 24)}: '
          '${formatMinutes(byHour[picked])} of focus';
    } else {
      caption = 'You focus best around ${_hour(best)}.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var h = 0; h < 24; h++)
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${_hour(h)}: ${formatMinutes(byHour[h])}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _picked = _picked == h ? null : h),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 30,
                        decoration: BoxDecoration(
                          color: _level(byHour[h], most),
                          borderRadius: BorderRadius.circular(3),
                          border: h == picked
                              ? Border.all(color: AppColors.ink, width: 1.5)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final label in const ['12 AM', '6 AM', '12 PM', '6 PM'])
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(caption, style: AppText.statLabel),
      ],
    );
  }
}

/// Colour for [value] on the [AppColors.heat] scale, relative to [most].
Color _level(int value, int most) {
  if (value <= 0 || most <= 0) return AppColors.heat[0];
  final f = value / most;
  if (f <= 0.25) return AppColors.heat[1];
  if (f <= 0.5) return AppColors.heat[2];
  if (f <= 0.8) return AppColors.heat[3];
  return AppColors.heat[4];
}

/// How the time splits between focus and breaks.
class _FocusBreak extends StatelessWidget {
  const _FocusBreak({required this.focus, required this.rest});

  final int focus;
  final int rest;

  @override
  Widget build(BuildContext context) {
    final total = focus + rest;
    if (total == 0) {
      return Text('No Pomodoros or breaks in this period yet.',
          style: AppText.statLabel);
    }
    final focusPct = (focus * 100 / total).round();
    final restPct = 100 - focusPct;

    final String advice;
    if (rest == 0) {
      advice = 'No breaks yet. A short rest keeps you sharp.';
    } else if (focusPct > 90) {
      advice = 'Mostly focus. Remember to take your breaks.';
    } else if (focusPct < 70) {
      advice = 'Breaks are running long. Try Auto-start Pomodoros.';
    } else {
      advice = 'A healthy rhythm of focus and rest.';
    }

    Widget side(String label, int minutes, int pct, Color dot,
            {bool end = false}) =>
        Column(
          crossAxisAlignment:
              end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(label, style: AppText.itemMeta),
              ],
            ),
            const SizedBox(height: 2),
            Text(formatMinutes(minutes), style: AppText.statValue),
            Text('$pct%', style: AppText.itemMeta),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: side('Focus', focus, focusPct, AppColors.chartStrong)),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: side('Break', rest, restPct, AppColors.chartSoft,
                    end: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Focus $focusPct percent, break $restPct percent',
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (focus > 0)
                  Expanded(
                    flex: focus,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.chartStrong,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                if (focus > 0 && rest > 0) const SizedBox(width: 3),
                if (rest > 0)
                  Expanded(
                    flex: rest,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.chartSoft,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(advice, style: AppText.statLabel),
      ],
    );
  }
}

/// Top tasks by focus time, as horizontal bars.
class _ByTask extends StatelessWidget {
  const _ByTask({required this.sessions});

  final List<FocusSession> sessions;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final s in sessions) {
      final name = s.taskTitle ?? 'No task';
      totals[name] = (totals[name] ?? 0) + s.minutes;
    }
    if (totals.isEmpty) {
      return Text('Finish a Pomodoro to see where your time goes.',
          style: AppText.statLabel);
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = rows.take(5).toList();
    final most = shown.first.value;

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(shown[i].key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.itemTitle),
                    ),
                    const SizedBox(width: 8),
                    Text(formatMinutes(shown[i].value),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        )),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: shown[i].value / most,
                    minHeight: 6,
                    color: i == 0 ? AppColors.chartStrong : AppColors.chartSoft,
                    backgroundColor: AppColors.primarySoft,
                  ),
                ),
              ],
            ),
          ),
        if (rows.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('+ ${plural(rows.length - shown.length, 'more task')}',
                style: AppText.itemMeta),
          ),
      ],
    );
  }
}

/// Every day of the last few months as a small square (a column per week,
/// Monday on top). Darker = more focus; the darkest means the daily goal was
/// met. The streak sits underneath.
class _Heatmap extends StatefulWidget {
  const _Heatmap({required this.store, required this.today});

  final AppStore store;
  final DateTime today;

  @override
  State<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<_Heatmap> {
  DateTime? _picked;

  static const _labelWidth = 28.0;
  static const _gap = 3.0;

  Color _goalLevel(int minutes, int goal) {
    if (minutes <= 0) return AppColors.heat[0];
    final f = goal <= 0 ? 1.0 : minutes / goal;
    if (f < 0.34) return AppColors.heat[1];
    if (f < 0.67) return AppColors.heat[2];
    if (f < 1) return AppColors.heat[3];
    return AppColors.heat[4];
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final today = widget.today;
    final goal = store.settings.dailyGoalMinutes;
    final thisMonday = startOfWeek(today);
    final picked = _picked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, box) {
          final fit = ((box.maxWidth - _labelWidth + _gap) / (13 + _gap)).floor();
          final weeks = fit < 4 ? 4 : (fit > 53 ? 53 : fit);
          final cell = (box.maxWidth - _labelWidth + _gap) / weeks - _gap;
          final firstMonday = DateTime(
              thisMonday.year, thisMonday.month, thisMonday.day - 7 * (weeks - 1));
          final mondays = [
            for (var w = 0; w < weeks; w++)
              DateTime(firstMonday.year, firstMonday.month, firstMonday.day + 7 * w),
          ];
          // Columns where a new month starts get its name above them; the
          // first column too, unless the next name would crowd it.
          final starts = [
            for (var w = 1; w < weeks - 1; w++)
              if (mondays[w].month != mondays[w - 1].month) w,
          ];
          if (starts.isEmpty || starts.first >= 3) starts.insert(0, 0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month names above the week where each month starts.
              SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final w in starts)
                      Positioned(
                        left: _labelWidth + w * (cell + _gap),
                        child: Text(
                          monthShort(mondays[w]),
                          style: TextStyle(
                              fontSize: 9.5, color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              for (var d = 0; d < 7; d++)
                Padding(
                  padding: EdgeInsets.only(bottom: d == 6 ? 0 : _gap),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _labelWidth,
                        child: Text(
                          const ['Mon', '', 'Wed', '', 'Fri', '', ''][d],
                          style: TextStyle(
                              fontSize: 9.5, color: AppColors.textSecondary),
                        ),
                      ),
                      for (var w = 0; w < weeks; w++) ...[
                        if (w > 0) const SizedBox(width: _gap),
                        _cell(
                          DateTime(mondays[w].year, mondays[w].month,
                              mondays[w].day + d),
                          cell,
                          goal,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                picked == null
                    ? (AppColors.isDark
                        ? 'Brightest = daily goal met'
                        : 'Darkest = daily goal met')
                    : '${weekdayShort(picked)}, ${picked.day} '
                        '${monthShort(picked)} · '
                        '${formatMinutes(store.focusMinutesOn(picked))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.itemMeta,
              ),
            ),
            Text('Less ', style: AppText.itemMeta),
            for (final c in AppColors.heat)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(' More', style: AppText.itemMeta),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            const StreakFlame(size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${plural(store.streakDays, 'day')} streak',
                    style: TextStyle(
                      fontFamily: kHeadingFont,
                      fontWeight: FontWeight.w800,
                      color: AppColors.streakText,
                    ),
                  ),
                  TextSpan(
                      text: ' · Best ${plural(store.longestStreak, 'day')}'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(DateTime day, double size, int goal) {
    if (day.isAfter(widget.today)) return SizedBox(width: size, height: size);
    final minutes = widget.store.focusMinutesOn(day);
    final selected = _picked == day;
    return Semantics(
      button: true,
      label: '${formatLongDate(day)}: ${formatMinutes(minutes)}',
      child: GestureDetector(
        onTap: () => setState(() => _picked = selected ? null : day),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _goalLevel(minutes, goal),
            borderRadius: BorderRadius.circular(size < 10 ? 2 : 3),
            border: selected
                ? Border.all(color: AppColors.ink, width: 1.5)
                : (day == widget.today
                    ? Border.all(color: AppColors.primaryDeep, width: 1)
                    : null),
          ),
        ),
      ),
    );
  }
}

/// Every Pomodoro and break, newest first, grouped by day.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final items = <_Entry>[
      for (final s in store.sessions)
        _Entry(
          start: s.startedAt,
          end: s.endedAt,
          minutes: s.minutes,
          title: s.taskTitle ?? 'Pomodoro',
          isBreak: false,
        ),
      for (final b in store.breaks)
        _Entry(
          start: b.startedAt,
          end: b.endedAt,
          minutes: b.minutes,
          title: b.long ? 'Long Break' : 'Short Break',
          isBreak: true,
        ),
    ]..sort((a, b) => b.end.compareTo(a.end));

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            Icon(AppIcons.clock, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              'Finished Pomodoros and breaks show up here.',
              textAlign: TextAlign.center,
              style: AppText.statLabel,
            ),
          ],
        ),
      );
    }

    // Group into days (items are already newest first).
    final days = <({DateTime day, List<_Entry> entries})>[];
    for (final e in items) {
      final d = startOfDay(e.end);
      if (days.isEmpty || days.last.day != d) {
        days.add((day: d, entries: [e]));
      } else {
        days.last.entries.add(e);
      }
    }

    final now = clock.now();
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(t));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final group = days[i];
        final focus = group.entries
            .where((e) => !e.isBreak)
            .fold(0, (a, e) => a + e.minutes);
        final pomodoros = group.entries.where((e) => !e.isBreak).length;
        final ago = formatAgo(group.day, now);
        final label = ago == 'Today' || ago == 'Yesterday'
            ? ago
            : '${weekdayShort(group.day)}, ${group.day.day} ${monthShort(group.day)}';

        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.sectionTitle),
                  ),
                  Text(
                    '${plural(pomodoros, 'Pomodoro')} · ${formatMinutes(focus)}',
                    style: AppText.itemMeta,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var j = 0; j < group.entries.length; j++)
                _TimelineRow(
                  entry: group.entries[j],
                  range: '${time(group.entries[j].start)} – '
                      '${time(group.entries[j].end)}',
                  last: j == group.entries.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Entry {
  const _Entry({
    required this.start,
    required this.end,
    required this.minutes,
    required this.title,
    required this.isBreak,
  });

  final DateTime start;
  final DateTime end;
  final int minutes;
  final String title;
  final bool isBreak;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.range,
    required this.last,
  });

  final _Entry entry;
  final String range;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dot and connecting line.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.isBreak ? AppColors.surface : AppColors.chartStrong,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: e.isBreak ? AppColors.chartSoft : AppColors.chartStrong,
                      width: 2,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: AppColors.divider),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.itemTitle.copyWith(
                            color: e.isBreak
                                ? AppColors.textSecondary
                                : AppColors.ink,
                          ),
                        ),
                        Text(range,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.itemMeta),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: e.isBreak
                          ? AppColors.searchFill
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      formatMinutes(e.minutes),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: e.isBreak
                            ? AppColors.textSecondary
                            : AppColors.primaryDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
