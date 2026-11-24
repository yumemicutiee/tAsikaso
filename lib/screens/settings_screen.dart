import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../models/models.dart';
import '../services/accounts.dart';
import '../services/drive_sync.dart';
import '../services/notification_service.dart';
import '../services/plan_sync.dart';
import '../services/scan_service.dart';
import '../services/study_ai.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/common.dart' show SheetTitle;
import '../widgets/dialogs.dart';
import '../widgets/number_field.dart';
import '../widgets/segmented_tabs.dart';
import 'actions.dart' show openPrivacyPolicy;
import 'backup_screen.dart';
import 'help_screen.dart';
import 'plans_screen.dart';

/// A part of Settings that another screen can open directly.
enum SettingsSection { notifications }

/// Everything adjustable in one place: you, the timer, Focus Mode,
/// notifications, scanning and your data.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.section});

  /// Scrolls to this section when the screen opens.
  final SettingsSection? section;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return PopScope(
      // A length typed just before leaving still counts as settled.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _rememberCustom();
      },
      child: Scaffold(
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
            // Build the whole list up front when a section further down has
            // to be scrolled into view as soon as the screen opens.
            scrollCacheExtent:
                section == null ? null : const ScrollCacheExtent.pixels(4000),
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
                  onChanged: (v) => update(s.copyWith(focusMinutes: v)),
                  onCommitted: _rememberCustom,
                ),
                _StepRow(
                  label: 'Short Break',
                  value: s.shortBreakMinutes,
                  unit: 'minutes',
                  min: PomodoroSettings.breakRange.$1,
                  max: PomodoroSettings.breakRange.$2,
                  onChanged: (v) => update(s.copyWith(shortBreakMinutes: v)),
                  onCommitted: _rememberCustom,
                ),
                _StepRow(
                  label: 'Long Break',
                  value: s.longBreakMinutes,
                  unit: 'minutes',
                  min: PomodoroSettings.breakRange.$1,
                  max: PomodoroSettings.breakRange.$2,
                  onChanged: (v) => update(s.copyWith(longBreakMinutes: v)),
                  onCommitted: _rememberCustom,
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
                  label: 'Moving Bubbles',
                  value: p.focusBubbles,
                  onChanged: (v) => prefs(p.copyWith(focusBubbles: v)),
                ),
              ]),

              _RevealOnce(
                enabled: section == SettingsSection.notifications,
                child: const _Heading('Notifications'),
              ),
              _Group(children: [
                _TapRow(
                  label: 'When Time Is Up',
                  value: p.timeUpAlert.label,
                  onTap: () => _pickTimeUpAlert(context),
                ),
                if (p.timeUpAlert != TimeUpAlert.off &&
                    NotificationService.isSupported)
                  const _ExactTimingRow(),
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
                  ? (p.timeUpAlert.sound
                      ? 'The alarm rings even when your phone is on silent or the app is closed.'
                      : 'Alerts come even when the app is closed.')
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
                  ? "Google's scanner finds the page edges and crops "
                      'automatically. The app\'s own camera looks for the '
                      'edges too.'
                  : 'Needs an Android phone. The camera is used instead, '
                      'and looks for the page edges itself.'),

              const _Heading('Smart Study'),
              _Group(children: [
                _Switch(
                  label: 'Flashcards & Quizzes with AI',
                  value: p.useAi,
                  onChanged: (v) => prefs(p.copyWith(useAi: v)),
                ),
                // Only meaningful with Smart Study on.
                if (p.useAi)
                  _Switch(
                    label: 'Read Photos with AI',
                    value: p.aiReading,
                    onChanged: (v) => prefs(p.copyWith(aiReading: v)),
                  ),
                _TapRow(
                  label: 'Study Server',
                  value: StudyAi.serverUrl.isEmpty
                      ? 'Not set'
                      : _shortUrl(StudyAi.serverUrl),
                  onTap: () => _editServer(context),
                ),
                _TapRow(
                  label: 'App Token',
                  value: StudyAi.token.isEmpty ? 'None' : '••••••••',
                  onTap: () => _editToken(context),
                ),
              ]),
              _Note(StudyAi.hasServer
                  ? '${p.useAi && p.aiReading ? 'AI reads the text from '
                      'your scanned pages, handwriting too, then makes clean '
                      'notes, key concepts, flashcards and quizzes.' : 'When '
                      'you save a scan, your study server asks AI for '
                      'clean notes, key concepts, flashcards and a quiz.'} '
                      '$kSmartStudyPrivacy Needs internet.'
                  : 'Run the study server from the app\'s server folder '
                      '(see its README), then add its address here to get '
                      'clean notes, key concepts, flashcards and quizzes '
                      'made for you. $kSmartStudyPrivacy'),
              if (StudyAi.usesAccounts) const _AccountUsage(),

              const _Heading('Your Data'),
              _Note(store.isPersistent
                  ? kIsWeb
                      ? 'Your folders, notes, flashcards and tasks are saved '
                          'in this browser. Clearing its site data removes '
                          'them, so keep a backup.'
                      : 'Your folders, notes, flashcards and tasks are saved '
                          'on this device.'
                  : "Saving is paused because your saved data couldn't "
                      'be read; it was left untouched. Restart the app to '
                      'try again, or Delete All Data to start fresh.'),
              const SizedBox(height: 8),
              _Group(children: [
                _TapRow(
                  label: 'Backup & Restore',
                  icon: AppIcons.backup,
                  onTap: () => openBackup(context),
                ),
                _Switch(
                  label: 'Send Crash Reports',
                  value: p.crashReports,
                  onChanged: (v) =>
                      store.updatePrefs(store.prefs.copyWith(crashReports: v)),
                ),
                _TapRow(
                  label: 'Privacy Policy',
                  icon: AppIcons.help,
                  onTap: () => openPrivacyPolicy(context),
                ),
                if (StudyAi.usesAccounts)
                  _TapRow(
                    label: 'Delete Account',
                    danger: true,
                    onTap: () => _deleteAccount(context),
                  ),
                _TapRow(
                  label: 'Delete All Data',
                  danger: true,
                  onTap: () => _eraseAll(context),
                ),
              ]),
              const SizedBox(height: 6),
              const _Note('Crash reports hold the error and where in the app '
                  "it happened, never your notes, photos or name. They go to "
                  'the study server.'),

              const _Heading('About'),
              _Group(children: [
                _TapRow(
                  label: 'Help & FAQ',
                  icon: AppIcons.help,
                  onTap: () => openHelp(context),
                ),
                const _TapRow(label: 'Version', value: kAppVersion),
              ]),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
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

  /// Remembers the current lengths as the "Custom" rhythm once they're
  /// settled. Doing this on every keystroke would remember "2" on the way
  /// to "25", and then "25" is Classic, so the real custom rhythm was lost.
  static void _rememberCustom() {
    final store = AppStore.instance;
    final s = store.settings;
    if (s.preset != null) return;
    final c = s.custom;
    if (c != null &&
        c.focus == s.focusMinutes &&
        c.shortBreak == s.shortBreakMinutes &&
        c.longBreak == s.longBreakMinutes) {
      return;
    }
    store.updateSettings(_custom(s));
  }

  static void _resetPomodoro(BuildContext context) {
    final store = AppStore.instance;
    final before = store.settings;
    store.updateSettings(before.reset());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Pomodoro settings reset to 25 – 5 – 15.'),
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

  /// "https://notes.example.com/api/" → "notes.example.com/api"
  static String _shortUrl(String url) {
    var s = url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/+$'), '');
    if (s.length > 30) s = '${s.substring(0, 29)}…';
    return s;
  }

  static Future<void> _editServer(BuildContext context) async {
    final store = AppStore.instance;
    final url = await showTextInputDialog(
      context,
      title: 'Study Server',
      initial: store.prefs.aiServerUrl,
      hint: 'https://your-site.com',
      allowEmpty: true,
      plainText: true,
    );
    if (url == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (url.isNotEmpty && !StudyAi.isValidUrl(url)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Enter the full address, starting with http:// or https://.'),
        ));
      return;
    }
    store.updatePrefs(store.prefs.copyWith(aiServerUrl: url));
    if (url.isEmpty) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Checking the server… A server that was asleep can '
            'take up to a minute to wake up.'),
        duration: StudyAi.pingTimeout,
      ));
    final ok = await StudyAi.ping(url);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? 'Connected to the study server.'
            : "Saved, but no study server answered there. Check the "
                'address and that the server is running.'),
        showCloseIcon: true,
      ));
  }

  static Future<void> _editToken(BuildContext context) async {
    final store = AppStore.instance;
    final token = await showTextInputDialog(
      context,
      title: 'App Token',
      initial: store.prefs.aiToken,
      hint: "The APP_TOKEN from the server's .env",
      allowEmpty: true,
      plainText: true,
    );
    if (token == null) return;
    store.updatePrefs(store.prefs.copyWith(aiToken: token));
  }

  static Future<void> _editName(BuildContext context) async {
    final store = AppStore.instance;
    final name = await showTextInputDialog(
      context,
      title: 'Your Name',
      initial: store.prefs.userName,
      allowEmpty: true, // clearing the name is allowed
    );
    if (name == null) return;
    store.updatePrefs(store.prefs.copyWith(userName: name.trim()));
  }

  /// The four "When Time Is Up" choices in a sheet.
  static Future<void> _pickTimeUpAlert(BuildContext context) async {
    final current = AppStore.instance.prefs.timeUpAlert;
    final picked = await showModalBottomSheet<TimeUpAlert>(
      context: context,
      // As tall as its four choices (the default half-height cut off "Off"
      // on a phone), scrolling only when the text is very large.
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle('When Time Is Up',
                subtitle: 'When a Pomodoro or a break ends'),
            const SizedBox(height: 8),
            for (final a in TimeUpAlert.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.label, style: AppText.itemTitle),
                subtitle: Text(_timeUpAlertNote(a)),
                trailing: a == current
                    ? Icon(AppIcons.check, color: AppColors.primaryDeep, size: 20)
                    : null,
                onTap: () => Navigator.of(sheet).pop(a),
              ),
          ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _setTimeUpAlert(context, picked);
  }

  static String _timeUpAlertNote(TimeUpAlert a) => switch (a) {
        TimeUpAlert.alarmAndVibration =>
          "Your phone's alarm sound and vibration, until you tap it (up to a minute)",
        TimeUpAlert.alarm =>
          "Your phone's alarm sound, until you tap it (up to a minute)",
        TimeUpAlert.vibration => 'Vibration, no sound',
        TimeUpAlert.off => 'No sound, no vibration, no notification',
      };

  static Future<void> _setTimeUpAlert(BuildContext context, TimeUpAlert alert) async {
    final store = AppStore.instance;
    final on = alert != TimeUpAlert.off;
    if (on && !await _askPermission(context)) return;
    store.updatePrefs(store.prefs.withTimeUpAlert(alert));
    if (on) {
      // Covers the phase that's already running, with the new choice.
      PomodoroController.instance.refreshAlert();
    } else {
      await NotificationService.cancelTimerEnd();
    }
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
          content: Text('Notifications are turned off for this app. You '
              "can allow them in your phone's settings."),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: NotificationService.openNotificationSettings,
          ),
          duration: Duration(seconds: 8),
        ));
    }
    return ok;
  }

  /// Deletes the account on the study server (plan and usage) and signs
  /// out; notes on this device and the Drive copy stay.
  static Future<void> _deleteAccount(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
    final sure = await showConfirmDialog(
      context,
      title: 'Delete Your Account?',
      message: 'Your $kAppName account is deleted: its plan, its Smart '
          'Study usage, and the settings, tasks and statistics saved in it. '
          'You are signed out here. What is on this device stays (notes, '
          'flashcards, tasks, statistics), and so does your copy on Google '
          'Drive; Delete All Data removes the ones on this device. This '
          'cannot be undone.',
      confirmLabel: 'Delete Account',
    );
    if (!sure) return;
    try {
      await StudyAi.deleteAccount();
    } on StudyAiException catch (e) {
      say(e.message);
      return;
    }
    final sync = DriveSync.instance;
    if (sync.isSignedIn) {
      await sync.signOut(); // signs out of the account too
    } else {
      await Accounts.instance.signOut();
    }
    AppStore.instance.applyServerPlan(null);
    say('Your account was deleted.');
  }

  static Future<void> _eraseAll(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showConfirmDialog(
      context,
      title: 'Delete All Data?',
      message: 'Every folder, note, flashcard set, task and statistic will be '
          'deleted from this device, and your settings (name, study server, '
          'reminder) go back to the start. Your tAsikaso+ plan and colors '
          'stay. This cannot be undone.'
          '${DriveSync.instance.isSignedIn ? ' Your copy on Google Drive is '
              'kept; sign in again to bring it back.' : ''}',
      confirmLabel: 'Delete Everything',
    );
    if (!sure) return;
    PomodoroController.instance.restart();
    await NotificationService.cancelTimerEnd();
    await NotificationService.setDailyReminder(null);
    final clean = await AppStore.instance.eraseEverything();
    navigator.popUntil((route) => route.isFirst);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(clean
            ? 'All data deleted.'
            : "Some files couldn't be deleted. Restart the app and try again."),
      ));
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
            ? '${settings.focusMinutes} – ${settings.shortBreakMinutes} – '
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
              // The name under the swatch would be read a second time.
              excludeSemantics: true,
              onTap: () => onPick(p),
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

  /// Fixed (not the theme colour), so every locked swatch looks the same.
  static const _lockBadge = Color(0xFF23263A);

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
          // The same dark badge on every locked colour, in the middle.
          if (locked)
            Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _lockBadge,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                ),
                child: const Icon(AppIcons.plus, size: 11, color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }
}

/// Which account this is and today's use of Claude against its limits,
/// read from the study server when Settings opens.
class _AccountUsage extends StatefulWidget {
  const _AccountUsage();

  @override
  State<_AccountUsage> createState() => _AccountUsageState();
}

class _AccountUsageState extends State<_AccountUsage> {
  late final Future<AccountInfo?> _account = PlanSync.refresh();

  static String _use(DailyUse u, String one, String many) {
    final limit = u.limit;
    final word = (limit ?? u.used) == 1 ? one : many;
    return limit == null ? '${u.used} $word' : '${u.used} of $limit $word';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountInfo?>(
      future: _account,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Note("Loading today's use of AI…");
        }
        final a = snap.data;
        if (a == null) {
          return const _Note("Today's use of AI couldn't be loaded. "
              'Check your internet connection.');
        }
        final who = a.isPlus
            ? 'Your account: $kPlusName.'
            : a.anonymous
                ? 'Your account: no account yet. Continue with Google '
                    '(Profile → Backup & Sync) for more each day.'
                : 'Your account: signed in with Google.';
        return _Note('$who Today with AI: '
            '${_use(a.pagesRead, 'page read', 'pages read')}, '
            '${_use(a.studyRequests, 'Smart Study request', 'Smart Study requests')}, '
            '${_use(a.answerChecks, 'answer check', 'answer checks')}.');
      },
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
/// "Allow Exact Timing": shown only while the phone (Android 14+) would
/// deliver alerts late. Tapping it opens the phone's own setting.
class _ExactTimingRow extends StatefulWidget {
  const _ExactTimingRow();

  @override
  State<_ExactTimingRow> createState() => _ExactTimingRowState();
}

class _ExactTimingRowState extends State<_ExactTimingRow>
    with WidgetsBindingObserver {
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's settings page: see what was chosen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final allowed = await NotificationService.exactTimingAllowed();
    if (mounted && allowed != _allowed) setState(() => _allowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return const SizedBox.shrink();
    return _TapRow(
      label: 'Allow Exact Timing',
      value: 'Alerts may be late',
      onTap: () async {
        await NotificationService.requestExactTiming();
        await _check();
      },
    );
  }
}

/// Scrolls itself into view once, right after it is first built, so another
/// screen can open Settings at a particular section.
class _RevealOnce extends StatefulWidget {
  const _RevealOnce({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_RevealOnce> createState() => _RevealOnceState();
}

class _RevealOnceState extends State<_RevealOnce> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          alignment: 0, duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onCommitted,
    this.step = 1,
  });

  final String label;
  final int value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final VoidCallback? onCommitted;

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
            onCommitted: onCommitted,
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
