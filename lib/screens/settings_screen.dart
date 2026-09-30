import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/scan_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/dialogs.dart';
import '../widgets/number_field.dart';
import '../widgets/segmented_tabs.dart';
import 'help_screen.dart';
import 'plans_screen.dart';

/// Everything adjustable in one place: you, the timer, Focus Mode,
/// notifications, scanning and your data.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return Scaffold(
      appBar: subPageAppBar('Settings'),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.settings;
          final p = store.prefs;
          void update(PomodoroSettings next) => store.updateSettings(next);
          void prefs(AppPrefs next) => store.updatePrefs(next);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const _Heading('You'),
              _Group(children: [
                _TapRow(
                  label: 'Your Name',
                  value: p.userName.trim().isEmpty ? 'Add' : p.userName.trim(),
                  onTap: () => _editName(context),
                ),
                _StepRow(
                  label: 'Daily Focus Goal',
                  value: s.dailyGoalMinutes,
                  unit: 'minutes a day',
                  min: PomodoroSettings.goalRange.$1,
                  max: PomodoroSettings.goalRange.$2,
                  step: 15,
                  onChanged: (v) => update(s.copyWith(dailyGoalMinutes: v)),
                ),
              ]),

              const _Heading('Appearance'),
              SegmentedTabs(
                labels: [for (final a in Appearance.values) a.label],
                selected: p.appearance.index,
                onChanged: (i) =>
                    prefs(p.copyWith(appearance: Appearance.values[i])),
              ),
              const _Note("System follows your phone's dark mode setting."),

              const _Heading('App Color', plus: true),
              _PaletteGrid(
                selected: store.palette,
                unlocked: store.isPlus,
                customColors: store.customColors,
                onPick: (palette) {
                  if (!palette.isFree && !store.isPlus) {
                    openPlans(context);
                  } else if (palette == Palette.custom) {
                    _pickCustomColor(context);
                  } else {
                    prefs(p.copyWith(palette: palette.name));
                  }
                },
              ),
              _Note(store.isPlus
                  ? 'Buttons, charts and Focus Mode follow the color you pick.'
                  : 'Navy is free. The other colors come with $kPlusName.'),

              _Heading(
                'Pomodoro',
                action: TextButton.icon(
                  onPressed: s.preset == PomodoroPreset.classic &&
                          s.longBreakEvery == 4 &&
                          !s.autoStartBreaks &&
                          !s.autoStartFocus
                      ? null
                      : () => _resetPomodoro(context),
                  icon: const Icon(AppIcons.reset, size: 15),
                  label: const Text(
                    'Reset to Default',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              _Presets(
                settings: s,
                onPick: (preset) => update(s.withPreset(preset)),
                onCustom: () {
                  final c = s.custom;
                  if (c != null) {
                    if (s.preset != null) update(s.withPreset(c));
                  } else {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        content: Text(
                            'Change any number below to make your own rhythm.'),
                      ));
                  }
                },
              ),
              const SizedBox(height: 10),
              _Group(children: [
                _StepRow(
                  label: 'Focus',
                  value: s.focusMinutes,
                  unit: 'minutes',
                  min: PomodoroSettings.focusRange.$1,
                  max: PomodoroSettings.focusRange.$2,
                  onChanged: (v) => update(_custom(s.copyWith(focusMinutes: v))),
                ),
                _StepRow(
                  label: 'Short Break',
                  value: s.shortBreakMinutes,
                  unit: 'minutes',
                  min: PomodoroSettings.breakRange.$1,
                  max: PomodoroSettings.breakRange.$2,
                  onChanged: (v) =>
                      update(_custom(s.copyWith(shortBreakMinutes: v))),
                ),
                _StepRow(
                  label: 'Long Break',
                  value: s.longBreakMinutes,
                  unit: 'minutes',
                  min: PomodoroSettings.breakRange.$1,
                  max: PomodoroSettings.breakRange.$2,
                  onChanged: (v) =>
                      update(_custom(s.copyWith(longBreakMinutes: v))),
                ),
                _StepRow(
                  label: 'Long Break After',
                  value: s.longBreakEvery,
                  unit: 'Pomodoros',
                  min: PomodoroSettings.everyRange.$1,
                  max: PomodoroSettings.everyRange.$2,
                  onChanged: (v) => update(s.copyWith(longBreakEvery: v)),
                ),
                _Switch(
                  label: 'Auto-start Breaks',
                  value: s.autoStartBreaks,
                  onChanged: (v) => update(s.copyWith(autoStartBreaks: v)),
                ),
                _Switch(
                  label: 'Auto-start Pomodoros',
                  value: s.autoStartFocus,
                  onChanged: (v) => update(s.copyWith(autoStartFocus: v)),
                ),
              ]),

              const _Heading('Focus Mode'),
              _Group(children: [
                _Switch(
                  label: 'Keep Screen On',
                  value: p.keepScreenOn,
                  onChanged: (v) => prefs(p.copyWith(keepScreenOn: v)),
                ),
                _Switch(
                  label: 'Vibrate When Time Is Up',
                  value: p.vibrateOnFinish,
                  onChanged: (v) => prefs(p.copyWith(vibrateOnFinish: v)),
                ),
                _Switch(
                  label: 'Moving Bubbles',
                  value: p.focusBubbles,
                  onChanged: (v) => prefs(p.copyWith(focusBubbles: v)),
                ),
              ]),

              const _Heading('Notifications'),
              _Group(children: [
                _Switch(
                  label: 'Timer Alerts',
                  value: p.timerAlerts,
                  onChanged: (v) => _setTimerAlerts(context, v),
                ),
                _Switch(
                  label: 'Daily Study Reminder',
                  value: p.dailyReminder,
                  onChanged: (v) => _setReminder(context, on: v),
                ),
                if (p.dailyReminder)
                  _TapRow(
                    label: 'Remind Me At',
                    value: TimeOfDay(
                      hour: p.reminderMinutes ~/ 60,
                      minute: p.reminderMinutes % 60,
                    ).format(context),
                    onTap: () => _pickReminderTime(context),
                  ),
              ]),
              _Note(NotificationService.isSupported
                  ? 'Alerts sound even when the app is closed.'
                  : 'Notifications work in the Android and iOS apps.'),

              const _Heading('Scanning'),
              _Group(children: [
                _Switch(
                  label: 'Smart Scanner',
                  value: p.smartScanner,
                  onChanged: (v) => prefs(p.copyWith(smartScanner: v)),
                ),
              ]),
              _Note(ScanService.canScanDocuments
                  ? 'Finds the page edges and crops automatically.'
                  : 'Needs an Android phone. The camera is used instead.'),

              const _Heading('Your Data'),
              _Note(store.isPersistent
                  ? 'Your folders, notes, flashcards and tasks are saved on '
                      'this device.'
                  : 'Data is kept only while the app is open (saving on the '
                      'web version comes later).'),
              const SizedBox(height: 8),
              _Group(children: [
                _TapRow(
                  label: 'Delete All Data',
                  danger: true,
                  onTap: () => _eraseAll(context),
                ),
              ]),

              const _Heading('About'),
              _Group(children: [
                _TapRow(
                  label: 'Help & FAQ',
                  icon: AppIcons.help,
                  onTap: () => openHelp(context),
                ),
                const _TapRow(label: 'Version', value: '0.1.0'),
              ]),
            ],
          );
        },
      ),
    );
  }

  /// Custom lengths are remembered so the "Custom" card can bring them back.
  static PomodoroSettings _custom(PomodoroSettings next) {
    if (next.preset != null) return next;
    return next.copyWith(
      custom: PomodoroPreset('Custom', next.focusMinutes,
          next.shortBreakMinutes, next.longBreakMinutes),
    );
  }

  static void _resetPomodoro(BuildContext context) {
    final store = AppStore.instance;
    final before = store.settings;
    store.updateSettings(before.reset());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Pomodoro settings reset to 25 · 5 · 15.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.updateSettings(before),
        ),
      ));
  }

  static Future<void> _pickCustomColor(BuildContext context) async {
    final store = AppStore.instance;
    final hue = await showCustomColorSheet(context, store.prefs.customHue);
    if (hue == null) return;
    store.updatePrefs(
        store.prefs.copyWith(palette: Palette.custom.name, customHue: hue));
  }

  static Future<void> _editName(BuildContext context) async {
    final store = AppStore.instance;
    final name = await showTextInputDialog(
      context,
      title: 'Your Name',
      initial: store.prefs.userName,
    );
    if (name == null) return;
    store.updatePrefs(store.prefs.copyWith(userName: name.trim()));
  }

  static Future<void> _setTimerAlerts(BuildContext context, bool on) async {
    final store = AppStore.instance;
    if (on && !await _askPermission(context)) return;
    store.updatePrefs(store.prefs.copyWith(timerAlerts: on));
    if (!on) await NotificationService.cancelTimerEnd();
  }

  static Future<void> _setReminder(BuildContext context, {required bool on}) async {
    final store = AppStore.instance;
    if (on && !await _askPermission(context)) return;
    store.updatePrefs(store.prefs.copyWith(dailyReminder: on));
    await NotificationService.setDailyReminder(
        on ? store.prefs.reminderMinutes : null);
  }

  static Future<void> _pickReminderTime(BuildContext context) async {
    final store = AppStore.instance;
    final m = store.prefs.reminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: 'Remind me at',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    store.updatePrefs(store.prefs.copyWith(reminderMinutes: minutes));
    await NotificationService.setDailyReminder(minutes);
  }

  /// Asks the phone for notification permission; explains if refused.
  static Future<bool> _askPermission(BuildContext context) async {
    if (!NotificationService.isSupported) return true;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await NotificationService.requestPermission();
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Notifications are turned off for this app. You can '
              "allow them in your phone's settings."),
          showCloseIcon: true,
        ));
    }
    return ok;
  }

  static Future<void> _eraseAll(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showConfirmDialog(
      context,
      title: 'Delete All Data?',
      message: 'Every folder, note, flashcard set, task and statistic will be '
          'deleted from this device. This cannot be undone.',
      confirmLabel: 'Delete Everything',
    );
    if (!sure) return;
    PomodoroController.instance.reset();
    await NotificationService.cancelTimerEnd();
    await NotificationService.setDailyReminder(null);
    await AppStore.instance.eraseEverything();
    navigator.popUntil((route) => route.isFirst);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('All data deleted.')));
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.plus = false, this.action});

  final String text;

  /// Shows a small gold "Plus" badge after the title.
  final bool plus;

  /// A small button on the right (e.g. "Reset to Default").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 22, action == null ? 4 : 0,
          action == null ? 10 : 4),
      child: Row(
        children: [
          Text(text, style: AppText.sectionTitle),
          if (plus) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Plus',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
          // Takes only the room left, so a long label shrinks instead of
          // overflowing (large text, narrow phones).
          if (action != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: action,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Classic / Short / Deep Work / Custom cards. The one matching the current
/// lengths is highlighted; "Custom" brings back your own lengths.
class _Presets extends StatelessWidget {
  const _Presets({
    required this.settings,
    required this.onPick,
    required this.onCustom,
  });

  final PomodoroSettings settings;
  final ValueChanged<PomodoroPreset> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final current = settings.preset;
    final custom = settings.custom;
    final cards = <Widget>[
      for (final p in PomodoroPreset.all)
        _PresetCard(
          title: p.name,
          detail: p.summary,
          selected: current == p,
          onTap: () => onPick(p),
        ),
      _PresetCard(
        title: 'Custom',
        detail: current == null
            ? '${settings.focusMinutes} · ${settings.shortBreakMinutes} · '
                '${settings.longBreakMinutes}'
            : (custom?.summary ?? 'Your own'),
        selected: current == null,
        onTap: onCustom,
      ),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: cards[row * 2]),
              const SizedBox(width: 8),
              Expanded(child: cards[row * 2 + 1]),
            ],
          ),
        ],
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.primaryDeep : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Colour themes as round swatches (fill + deep shade). Locked ones show a
/// small crown and open the tAsikaso+ plans instead.
class _PaletteGrid extends StatelessWidget {
  const _PaletteGrid({
    required this.selected,
    required this.unlocked,
    required this.customColors,
    required this.onPick,
  });

  final Palette selected;
  final bool unlocked;

  /// The user's own colour, shown on the "Custom" swatch once it's in use.
  final ThemeColors customColors;
  final ValueChanged<Palette> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 10,
      children: [
        for (final p in Palette.values)
          SizedBox(
            width: 74,
            child: Semantics(
              button: true,
              selected: p == selected,
              label: p.isFree || unlocked ? p.label : '${p.label}, $kPlusName',
              child: InkWell(
                onTap: () => onPick(p),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      _Swatch(
                        colors: p == Palette.custom ? customColors : p.colors,
                        rainbow: p == Palette.custom && selected != p,
                        selected: p == selected,
                        locked: !p.isFree && !unlocked,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.label.split(' & ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              p == selected ? FontWeight.w700 : FontWeight.w500,
                          color: p == selected
                              ? AppColors.ink
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colors,
    required this.selected,
    required this.locked,
    this.rainbow = false,
  });

  final ThemeColors colors;
  final bool selected;
  final bool locked;

  /// A colour wheel instead of the two halves ("Custom", before it's used).
  final bool rainbow;

  static const _wheel = SweepGradient(colors: [
    Color(0xFFF5A3A3),
    Color(0xFFF5D7A3),
    Color(0xFFD9F5A3),
    Color(0xFFA3F5C4),
    Color(0xFFA3E4F5),
    Color(0xFFA3B4F5),
    Color(0xFFD2A3F5),
    Color(0xFFF5A3DC),
    Color(0xFFF5A3A3),
  ]);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.ink : Colors.transparent,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: rainbow
                    ? _wheel
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0.5, 0.5],
                        colors: [Color(colors.fill), Color(colors.deep)],
                      ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (locked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.heroTop,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: const Icon(AppIcons.plus, size: 9, color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(text, style: AppText.statLabel.copyWith(height: 1.4)),
    );
  }
}

/// Row text: one line, no subtitle.
TextStyle get _rowText => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
    );

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: _rowText),
      value: value,
      activeThumbColor: AppColors.primaryDeep,
      onChanged: onChanged,
    );
  }
}

/// A row with an optional value on the right; tappable when [onTap] is set.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    this.value,
    this.icon,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: icon == null ? null : Icon(icon, color: AppColors.ink, size: 20),
      title: Text(
        label,
        style: _rowText.copyWith(
          color: danger ? AppColors.streakRed : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          if (onTap != null && !danger) ...[
            const SizedBox(width: 4),
            Icon(AppIcons.chevronRight,
                size: 16, color: AppColors.textMuted),
          ],
        ],
      ),
    );
  }
}

/// A label with a [NumberField] you can type into or nudge with − / +.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _rowText),
          ),
          NumberField(
            value: value,
            min: min,
            max: max,
            step: step,
            compact: true,
            label: '$label, $unit ($min to $max)',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
