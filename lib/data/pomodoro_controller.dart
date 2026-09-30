import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/notification_service.dart';
import 'app_store.dart';

/// The one Pomodoro timer in the app. The Study screen and the full-screen
/// Focus view both show it, so it lives outside any single widget.
class PomodoroController extends ChangeNotifier with WidgetsBindingObserver {
  PomodoroController._() {
    _setMode(TimerMode.pomodoro);
    _store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  static final PomodoroController instance = PomodoroController._();

  final AppStore _store = AppStore.instance;

  /// Shows a short message (e.g. "Pomodoro done!"). Set by the app shell.
  void Function(String message)? onMessage;

  TimerMode _mode = TimerMode.pomodoro;
  int _phaseTotal = 25 * 60; // seconds
  int _remaining = 25 * 60;
  Timer? _ticker;

  /// When the running phase ends. The countdown is worked out from this, so
  /// it stays right even after the app was in the background.
  DateTime? _endsAt;

  /// Pomodoros finished in this sitting (for the long-break rhythm).
  int _completed = 0;

  TimerMode get mode => _mode;
  int get remaining => _remaining;
  int get phaseTotal => _phaseTotal;
  bool get running => _ticker != null;
  bool get atStart => !running && _remaining == _phaseTotal;
  bool get isFocus => _mode == TimerMode.pomodoro;
  int get session => _completed + 1;

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
    _endsAt = clock.now().add(Duration(seconds: _remaining));
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _scheduleAlert();
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _stopTicker();
    notifyListeners();
  }

  void toggle() => running ? pause() : start();

  /// Back to the start of this phase, using the latest durations.
  void reset() {
    _stopTicker();
    _setMode(_mode);
    notifyListeners();
  }

  void selectMode(TimerMode mode) {
    _stopTicker();
    _setMode(mode);
    notifyListeners();
  }

  void skip() => _finish(completed: false);

  /// Stops everything and returns to a fresh Pomodoro. For tests.
  @visibleForTesting
  void resetForTesting() {
    _stopTicker();
    _completed = 0;
    _setMode(TimerMode.pomodoro);
    onMessage = null;
    notifyListeners();
  }

  // ---- Internals -------------------------------------------------------------

  void _setMode(TimerMode mode) {
    _mode = mode;
    _phaseTotal = _settings.minutesFor(mode) * 60;
    _remaining = _phaseTotal;
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
    if (left == 0) _finish(completed: true);
  }

  /// Moves to the next phase. [completed] is false when the user skips.
  void _finish({required bool completed}) {
    _stopTicker(cancelAlert: !completed);
    final wasFocus = isFocus;
    if (wasFocus && completed) {
      _completed++;
      _store.recordFocusSession(_phaseTotal ~/ 60);
    } else if (!wasFocus) {
      // A skipped break still counts for the time actually taken.
      final taken = completed ? _phaseTotal : _phaseTotal - _remaining;
      _store.recordBreak(taken ~/ 60, long: _mode == TimerMode.longBreak);
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
    notifyListeners();

    if (!completed) return;
    if (_store.prefs.vibrateOnFinish) HapticFeedback.heavyImpact();
    onMessage?.call(wasFocus
        ? 'Pomodoro done! Time for a ${next.label}.'
        : 'Break over. Ready for the next Pomodoro?');
    final autoStart = next == TimerMode.pomodoro
        ? _settings.autoStartFocus
        : _settings.autoStartBreaks;
    if (autoStart) start();
  }

  /// New durations in Settings apply straight away if the timer hasn't started.
  void _onStoreChanged() {
    final total = _settings.minutesFor(_mode) * 60;
    if (atStart && total != _phaseTotal) {
      _phaseTotal = total;
      _remaining = total;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catch up immediately when coming back to the app.
    if (state == AppLifecycleState.resumed && running) _tick();
  }
}
