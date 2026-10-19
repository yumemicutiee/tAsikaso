import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/notification_service.dart';
import '../theme/brand.dart';
import 'app_store.dart';

/// The one Pomodoro timer in the app. The Study screen and the full-screen
/// Focus view both show it, so it lives outside any single widget.
///
/// Its state is saved with the app's data, so a running or paused phase
/// carries on after the app was closed (see [restore]).
class PomodoroController extends ChangeNotifier with WidgetsBindingObserver {
  PomodoroController._() {
    _setMode(TimerMode.pomodoro);
    _lastCurrentTaskId = _store.currentTask?.id;
    _store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  static final PomodoroController instance = PomodoroController._();

  final AppStore _store = AppStore.instance;

  /// Shows a short message (e.g. "Pomodoro done!"). Set by the app shell.
  /// A message from before it was set waits in [takePendingMessage].
  void Function(String message)? onMessage;
  String? _pendingMessage;

  TimerMode _mode = TimerMode.pomodoro;
  int _phaseTotal = 25 * 60; // seconds
  int _remaining = 25 * 60;
  Timer? _ticker;

  /// When the running phase ends. The countdown is worked out from this, so
  /// it stays right even after the app was in the background.
  DateTime? _endsAt;

  /// Pomodoros finished in this sitting (for the long-break rhythm).
  int _completed = 0;

  /// The task this Pomodoro counts for, picked when it started, so adding
  /// or picking another task halfway through doesn't move it.
  String? _taskId;
  String? _taskTitle;

  /// Changes whenever a phase starts over (new mode, reset, finished), so a
  /// question asked about one phase is never applied to the next.
  int _phase = 0;

  /// For noticing when another task becomes current mid-Pomodoro.
  String? _lastCurrentTaskId;

  TimerMode get mode => _mode;
  int get remaining => _remaining;
  int get phaseTotal => _phaseTotal;
  bool get running => _ticker != null;
  bool get atStart => !running && _remaining == _phaseTotal;
  bool get isFocus => _mode == TimerMode.pomodoro;
  int get session => _completed + 1;
  int get phase => _phase;

  /// The task this Pomodoro counts for: the one it was started for, or the
  /// current task until it starts.
  String? get taskTitle {
    if (_taskId != null || _taskTitle != null) {
      return _store.task(_taskId)?.title ?? _taskTitle;
    }
    return _store.currentTask?.title;
  }

  /// 0.0 at the start of the phase, 1.0 when it ends.
  double get progress {
    if (_phaseTotal == 0) return 0.0;
    final p = 1 - _remaining / _phaseTotal;
    return p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
  }

  /// "24:59"
  String get timeText =>
      '${(_remaining ~/ 60).toString().padLeft(2, '0')}:'
      '${(_remaining % 60).toString().padLeft(2, '0')}';

  PomodoroSettings get _settings => _store.settings;

  // ---- Controls --------------------------------------------------------------

  void start() {
    if (running) return;
    if (isFocus && _remaining == _phaseTotal) {
      // A new Pomodoro counts for the task that's current now.
      final task = _store.currentTask;
      _taskId = task?.id;
      _taskTitle = task?.title;
    }
    _run(clock.now().add(Duration(seconds: _remaining)));
    _save();
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _stopTicker();
    _save();
    notifyListeners();
  }

  void toggle() => running ? pause() : start();

  /// Back to the start of this phase, using the latest durations.
  void reset() {
    _stopTicker();
    _setMode(_mode);
    _save();
    notifyListeners();
  }

  /// Switches to [mode]. Choosing the mode that's already on does nothing,
  /// so a stray tap can't wipe a running Pomodoro.
  void selectMode(TimerMode mode) {
    if (mode == _mode) return;
    _stopTicker();
    _setMode(mode);
    _save();
    notifyListeners();
  }

  void skip() => _finish(completed: false);

  /// Picks the timer up where it was left when the app was last closed. A
  /// phase that ran out in the meantime is counted at the time it ended.
  void restore() {
    final saved = _store.timerSnapshot;
    if (saved == null || running) return;
    _completed = saved.completed;
    _lastCurrentTaskId = _store.currentTask?.id;
    final end = saved.endsAt;
    if (end == null && saved.remainingSeconds >= saved.phaseSeconds) {
      _setMode(saved.mode); // not started yet: use the current lengths
      notifyListeners();
      return;
    }

    _mode = saved.mode;
    _phase++;
    _phaseTotal = saved.phaseSeconds;
    _taskId = saved.taskId;
    _taskTitle = saved.taskTitle;
    final now = clock.now();
    if (end == null) {
      _remaining = saved.remainingSeconds; // paused
    } else if (end.isAfter(now)) {
      _remaining = (end.difference(now).inMilliseconds / 1000).ceil();
      _run(end);
    } else {
      _remaining = 0;
      _finish(completed: true, endedAt: end, whileClosed: true);
      return;
    }
    notifyListeners();
  }

  /// A message from before [onMessage] was set (e.g. from [restore]), once.
  String? takePendingMessage() {
    final m = _pendingMessage;
    _pendingMessage = null;
    return m;
  }

  /// Stops everything and returns to a fresh Pomodoro. For tests.
  @visibleForTesting
  void resetForTesting() {
    _stopTicker();
    _completed = 0;
    _setMode(TimerMode.pomodoro);
    onMessage = null;
    _pendingMessage = null;
    _lastCurrentTaskId = _store.currentTask?.id;
    notifyListeners();
  }

  // ---- Internals -------------------------------------------------------------

  void _setMode(TimerMode mode) {
    _mode = mode;
    _phaseTotal = _settings.minutesFor(mode) * 60;
    _remaining = _phaseTotal;
    _taskId = null;
    _taskTitle = null;
    _phase++;
  }

  /// Runs the countdown until [end].
  void _run(DateTime end) {
    _endsAt = end;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _scheduleAlert();
  }

  /// Keeps the timer's state with the app's data (see [restore]).
  void _save() => _store.saveTimer(TimerSnapshot(
        mode: _mode,
        phaseSeconds: _phaseTotal,
        remainingSeconds: _remaining,
        endsAt: _endsAt,
        completed: _completed,
        taskId: _taskId,
        taskTitle: _taskTitle,
      ));

  void _say(String message) {
    final show = onMessage;
    if (show != null) {
      show(message);
    } else {
      _pendingMessage = message;
    }
  }

  /// [cancelAlert] is false when the phase ran out: its notification is
  /// due right now and must still sound if the app is in the background.
  void _stopTicker({bool cancelAlert = true}) {
    final wasRunning = _ticker != null;
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    if (wasRunning && cancelAlert) NotificationService.cancelTimerEnd();
  }

  /// Lets the phone announce the end of this phase even if the app is
  /// closed by then.
  void _scheduleAlert() {
    final end = _endsAt;
    if (end == null || !_store.prefs.timerAlerts) return;
    final next = isFocus ? 'break' : 'Pomodoro';
    NotificationService.scheduleTimerEnd(
      end,
      isFocus ? 'Pomodoro done!' : 'Break over',
      isFocus ? 'Nice work. Time for a $next.' : 'Ready for the next $next?',
      isBreak: !isFocus,
    );
    // Timer Alerts are on by default, so ask for permission the first time
    // they would be used (Android 13+ and iOS need it).
    final prefs = _store.prefs;
    if (!prefs.askedNotifications && NotificationService.isSupported) {
      _store.updatePrefs(prefs.copyWith(askedNotifications: true));
      NotificationService.requestPermission();
    }
  }

  void _tick() {
    final end = _endsAt;
    if (end == null) return;
    final ms = end.difference(clock.now()).inMilliseconds;
    final left = ms <= 0 ? 0 : (ms / 1000).ceil();
    if (left != _remaining) {
      _remaining = left;
      notifyListeners();
    }
    if (left == 0) _finish(completed: true, endedAt: end);
  }

  /// Moves to the next phase. [completed] is false when the user skips.
  /// [endedAt] is when a completed phase ran out (default: now), and
  /// [whileClosed] is true if that happened while the app was closed.
  void _finish({
    required bool completed,
    DateTime? endedAt,
    bool whileClosed = false,
  }) {
    _stopTicker(cancelAlert: !completed);
    final wasFocus = isFocus;
    if (wasFocus && completed) {
      _completed++;
      _store.recordFocusSession(
        _phaseTotal ~/ 60,
        endedAt: endedAt,
        taskId: _taskId,
        taskTitle: _taskTitle,
      );
    } else if (!wasFocus) {
      // A skipped break still counts for the time actually taken.
      final taken = completed ? _phaseTotal : _phaseTotal - _remaining;
      _store.recordBreak(taken ~/ 60,
          long: _mode == TimerMode.longBreak, endedAt: endedAt);
    }

    final every = _settings.longBreakEvery < 1 ? 1 : _settings.longBreakEvery;
    final TimerMode next;
    if (wasFocus) {
      next = completed && _completed % every == 0
          ? TimerMode.longBreak
          : TimerMode.shortBreak;
    } else {
      next = TimerMode.pomodoro;
    }
    _setMode(next);
    _save();
    notifyListeners();

    if (!completed) return;
    if (whileClosed) {
      // The phone already sounded the alert; the next phase waits for START.
      _say(wasFocus
          ? 'Your Pomodoro finished while $kAppName was closed. '
              'Time for a ${next.label}.'
          : 'Your break ended while $kAppName was closed. '
              'Ready for the next Pomodoro?');
      return;
    }
    if (_store.prefs.vibrateOnFinish) HapticFeedback.heavyImpact();
    _say(wasFocus
        ? 'Pomodoro done! Time for a ${next.label}.'
        : 'Break over. Ready for the next Pomodoro?');
    final autoStart = next == TimerMode.pomodoro
        ? _settings.autoStartFocus
        : _settings.autoStartBreaks;
    if (autoStart) start();
  }

  void _onStoreChanged() {
    // New durations in Settings apply straight away if the timer hasn't
    // started.
    final total = _settings.minutesFor(_mode) * 60;
    if (atStart && total != _phaseTotal) {
      _phaseTotal = total;
      _remaining = total;
      notifyListeners();
    }
    _noticeTaskSwitch();
  }

  /// When another task becomes current mid-Pomodoro (picked, or just
  /// added), says that this Pomodoro still counts for the one it started on.
  void _noticeTaskSwitch() {
    final current = _store.currentTask;
    if (current?.id == _lastCurrentTaskId) return;
    _lastCurrentTaskId = current?.id;
    final counting = _store.task(_taskId);
    if (!isFocus || atStart || current == null || counting == null) return;
    if (counting.id == current.id) return;
    _say('This Pomodoro still counts for "${counting.title}". '
        '"${current.title}" is next.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catch up immediately when coming back to the app.
    if (state == AppLifecycleState.resumed && running) _tick();
  }
}
