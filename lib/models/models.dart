import 'package:flutter/material.dart';

// All models are immutable and serialise to JSON for on-device storage.
// Big binary data (PDFs, photos, thumbnails) is stored as separate files,
// keyed by the model's id, and never lives inside the JSON.

typedef Json = Map<String, Object?>;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
bool _bool(Object? v) => v == true;
int _minuteOfDay(int m) => m < 0 ? 0 : (m >= 24 * 60 ? 24 * 60 - 1 : m);

DateTime _date(Object? v) =>
    v is String ? (DateTime.tryParse(v) ?? DateTime(2026)) : DateTime(2026);

/// A subject folder (e.g. Biology) that holds notes and flashcard sets.
@immutable
class StudyFolder {
  const StudyFolder({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;

  /// ARGB colour chosen by the user.
  final int colorValue;

  Color get color => Color(colorValue);

  StudyFolder copyWith({String? name, int? colorValue}) => StudyFolder(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
      );

  Json toJson() => {'id': id, 'name': name, 'color': colorValue};

  factory StudyFolder.fromJson(Json j) => StudyFolder(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Folder',
        colorValue: _int(j['color'], 0xFFA9CFF5),
      );
}

/// Captured lecture notes saved as a PDF.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.folderId,
    required this.createdAt,
    this.pageCount = 0,
    this.text = '',
  });

  final String id;
  final String title;
  final String folderId;
  final DateTime createdAt;
  final int pageCount;

  /// Text read from the pages (OCR). Empty if none was found or OCR isn't
  /// available on this device. Used for search and "View Text".
  final String text;

  String get pdfKey => 'notes/$id.pdf';
  String get thumbKey => 'notes/$id.jpg';

  Note copyWith({String? title, String? folderId}) => Note(
        id: id,
        title: title ?? this.title,
        folderId: folderId ?? this.folderId,
        createdAt: createdAt,
        pageCount: pageCount,
        text: text,
      );

  Json toJson() => {
        'id': id,
        'title': title,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
        'pages': pageCount,
        'text': text,
      };

  factory Note.fromJson(Json j) => Note(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Notes',
        folderId: j['folderId'] as String? ?? '',
        createdAt: _date(j['createdAt']),
        pageCount: _int(j['pages']),
        text: j['text'] as String? ?? '',
      );
}

/// A task tracked by the Pomodoro timer.
@immutable
class StudyTask {
  const StudyTask({
    required this.id,
    required this.title,
    required this.pomodorosTotal,
    required this.createdAt,
    this.pomodorosDone = 0,
    this.focusMinutes = 0,
    this.done = false,
  });

  final String id;
  final String title;

  /// Estimated Pomodoros needed.
  final int pomodorosTotal;
  final int pomodorosDone;

  /// Minutes of completed focus sessions spent on this task.
  final int focusMinutes;
  final bool done;
  final DateTime createdAt;

  /// 0.0 – 1.0, by Pomodoros completed.
  double get progress {
    if (done) return 1.0;
    if (pomodorosTotal <= 0) return 0.0;
    final p = pomodorosDone / pomodorosTotal;
    return p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
  }

  /// "4 / 8 · 100 / 200 mins"
  String progressLabel(int focusLength) =>
      '$pomodorosDone / $pomodorosTotal · $focusMinutes / '
      '${pomodorosTotal * focusLength} mins';

  StudyTask copyWith({
    String? title,
    int? pomodorosTotal,
    int? pomodorosDone,
    int? focusMinutes,
    bool? done,
  }) =>
      StudyTask(
        id: id,
        title: title ?? this.title,
        pomodorosTotal: pomodorosTotal ?? this.pomodorosTotal,
        pomodorosDone: pomodorosDone ?? this.pomodorosDone,
        focusMinutes: focusMinutes ?? this.focusMinutes,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Json toJson() => {
        'id': id,
        'title': title,
        'total': pomodorosTotal,
        'doneCount': pomodorosDone,
        'minutes': focusMinutes,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StudyTask.fromJson(Json j) => StudyTask(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Task',
        pomodorosTotal: _int(j['total'], 1),
        pomodorosDone: _int(j['doneCount']),
        focusMinutes: _int(j['minutes']),
        done: _bool(j['done']),
        createdAt: _date(j['createdAt']),
      );
}

@immutable
class Flashcard {
  const Flashcard({required this.id, required this.front, required this.back});

  final String id;
  final String front;
  final String back;

  Flashcard copyWith({String? front, String? back}) =>
      Flashcard(id: id, front: front ?? this.front, back: back ?? this.back);

  Json toJson() => {'id': id, 'front': front, 'back': back};

  factory Flashcard.fromJson(Json j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
      );
}

/// A deck of flashcards, optionally with the page photos it was made from.
@immutable
class FlashcardSet {
  const FlashcardSet({
    required this.id,
    required this.title,
    required this.folderId,
    required this.createdAt,
    this.cards = const [],
    this.suggestions = const [],
    this.photoCount = 0,
    this.lastStudiedAt,
    this.lastKnown = 0,
    this.lastSeen = 0,
  });

  final String id;
  final String title;
  final String folderId;
  final DateTime createdAt;
  final List<Flashcard> cards;

  /// Cards suggested from the photos' text, waiting to be added or skipped.
  final List<Flashcard> suggestions;

  /// Number of reference photos stored for this set.
  final int photoCount;

  /// When the set was last studied (null = never), and how that session
  /// went: cards known on the first try out of cards seen.
  final DateTime? lastStudiedAt;
  final int lastKnown;
  final int lastSeen;

  String photoKey(int index) => 'sets/$id/$index.jpg';

  FlashcardSet copyWith({
    String? title,
    String? folderId,
    List<Flashcard>? cards,
    List<Flashcard>? suggestions,
    DateTime? lastStudiedAt,
    int? lastKnown,
    int? lastSeen,
  }) =>
      FlashcardSet(
        id: id,
        title: title ?? this.title,
        folderId: folderId ?? this.folderId,
        createdAt: createdAt,
        cards: cards ?? this.cards,
        suggestions: suggestions ?? this.suggestions,
        photoCount: photoCount,
        lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
        lastKnown: lastKnown ?? this.lastKnown,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Json toJson() => {
        'id': id,
        'title': title,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
        'photos': photoCount,
        'cards': [for (final c in cards) c.toJson()],
        'suggestions': [for (final c in suggestions) c.toJson()],
        'studied': lastStudiedAt?.toIso8601String(),
        'known': lastKnown,
        'seen': lastSeen,
      };

  factory FlashcardSet.fromJson(Json j) => FlashcardSet(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Flashcards',
        folderId: j['folderId'] as String? ?? '',
        createdAt: _date(j['createdAt']),
        photoCount: _int(j['photos']),
        cards: _cards(j['cards']),
        suggestions: _cards(j['suggestions']),
        lastStudiedAt: j['studied'] is String
            ? DateTime.tryParse(j['studied'] as String)
            : null,
        lastKnown: _int(j['known']),
        lastSeen: _int(j['seen']),
      );

  static List<Flashcard> _cards(Object? list) => [
        for (final c in (list as List<Object?>? ?? const []))
          if (c is Map<String, Object?>) Flashcard.fromJson(c),
      ];
}

enum TimerMode {
  pomodoro('Pomodoro'),
  shortBreak('Short Break'),
  longBreak('Long Break');

  const TimerMode(this.label);

  final String label;
}

/// User-adjustable Pomodoro durations (minutes) and behaviour.
@immutable
class PomodoroSettings {
  const PomodoroSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.longBreakEvery = 4,
    this.autoStartBreaks = false,
    this.autoStartFocus = false,
    this.dailyGoalMinutes = 150,
    this.custom,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// A long break follows every Nth completed Pomodoro.
  final int longBreakEvery;
  final bool autoStartBreaks;
  final bool autoStartFocus;

  /// Focus minutes aimed for each day (the Dashboard ring).
  final int dailyGoalMinutes;

  /// The user's own focus / short / long minutes, remembered so the
  /// "Custom" preset can bring them back after trying another preset.
  final PomodoroPreset? custom;

  /// The preset these lengths match, or null for custom lengths.
  PomodoroPreset? get preset {
    for (final p in PomodoroPreset.all) {
      if (p.focus == focusMinutes &&
          p.shortBreak == shortBreakMinutes &&
          p.longBreak == longBreakMinutes) {
        return p;
      }
    }
    return null;
  }

  /// These settings with [p]'s lengths.
  PomodoroSettings withPreset(PomodoroPreset p) => copyWith(
        focusMinutes: p.focus,
        shortBreakMinutes: p.shortBreak,
        longBreakMinutes: p.longBreak,
      );

  /// Back to the defaults, keeping the daily goal and the saved custom
  /// lengths.
  PomodoroSettings reset() =>
      PomodoroSettings(dailyGoalMinutes: dailyGoalMinutes, custom: custom);

  int minutesFor(TimerMode mode) => switch (mode) {
        TimerMode.pomodoro => focusMinutes,
        TimerMode.shortBreak => shortBreakMinutes,
        TimerMode.longBreak => longBreakMinutes,
      };

  PomodoroSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? longBreakEvery,
    bool? autoStartBreaks,
    bool? autoStartFocus,
    int? dailyGoalMinutes,
    PomodoroPreset? custom,
  }) =>
      PomodoroSettings(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        longBreakEvery: longBreakEvery ?? this.longBreakEvery,
        autoStartBreaks: autoStartBreaks ?? this.autoStartBreaks,
        autoStartFocus: autoStartFocus ?? this.autoStartFocus,
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        custom: custom ?? this.custom,
      );

  Json toJson() => {
        'focus': focusMinutes,
        'short': shortBreakMinutes,
        'long': longBreakMinutes,
        'every': longBreakEvery,
        'autoBreaks': autoStartBreaks,
        'autoFocus': autoStartFocus,
        'goal': dailyGoalMinutes,
        if (custom case final c?)
          'custom': [c.focus, c.shortBreak, c.longBreak],
      };

  /// Allowed values (min, max), used by Settings and when loading.
  static const focusRange = (1, 180);
  static const breakRange = (1, 60);
  static const everyRange = (1, 12);
  static const goalRange = (15, 720);

  factory PomodoroSettings.fromJson(Json j) => PomodoroSettings(
        focusMinutes: _inRange(_int(j['focus'], 25), focusRange),
        shortBreakMinutes: _inRange(_int(j['short'], 5), breakRange),
        longBreakMinutes: _inRange(_int(j['long'], 15), breakRange),
        longBreakEvery: _inRange(_int(j['every'], 4), everyRange),
        autoStartBreaks: _bool(j['autoBreaks']),
        autoStartFocus: _bool(j['autoFocus']),
        dailyGoalMinutes: _inRange(_int(j['goal'], 150), goalRange),
        custom: switch (j['custom']) {
          [final num f, final num s, final num l] => PomodoroPreset(
              'Custom',
              _inRange(f.toInt(), focusRange),
              _inRange(s.toInt(), breakRange),
              _inRange(l.toInt(), breakRange),
            ),
          _ => null,
        },
      );
}

/// A named set of Pomodoro lengths (minutes).
@immutable
class PomodoroPreset {
  const PomodoroPreset(this.name, this.focus, this.shortBreak, this.longBreak);

  final String name;
  final int focus;
  final int shortBreak;
  final int longBreak;

  static const classic = PomodoroPreset('Classic', 25, 5, 15);
  static const short = PomodoroPreset('Short', 15, 3, 10);
  static const deepWork = PomodoroPreset('Deep Work', 50, 10, 30);

  /// The ready-made rhythms (not "Custom").
  static const all = [classic, short, deepWork];

  /// "25 · 5 · 15"
  String get summary => '$focus · $shortBreak · $longBreak';
}

int _inRange(int v, (int, int) range) {
  final (lo, hi) = range;
  return v < lo ? lo : (v > hi ? hi : v);
}

/// One finished Pomodoro, for the Analysis screen.
@immutable
class FocusSession {
  const FocusSession({
    required this.endedAt,
    required this.minutes,
    this.taskId,
    this.taskTitle,
  });

  final DateTime endedAt;
  final int minutes;
  final String? taskId;

  /// Kept so the analysis still makes sense after a task is deleted.
  final String? taskTitle;

  DateTime get startedAt => endedAt.subtract(Duration(minutes: minutes));

  Json toJson() => {
        'end': endedAt.toIso8601String(),
        'min': minutes,
        'task': taskId,
        'title': taskTitle,
      };

  factory FocusSession.fromJson(Json j) => FocusSession(
        endedAt: _date(j['end']),
        minutes: _int(j['min']),
        taskId: j['task'] as String?,
        taskTitle: j['title'] as String?,
      );
}

/// A break that was taken (finished, or skipped after at least a minute),
/// for the focus / break ratio and the Timeline.
@immutable
class BreakSession {
  const BreakSession({
    required this.endedAt,
    required this.minutes,
    this.long = false,
  });

  final DateTime endedAt;
  final int minutes;
  final bool long;

  DateTime get startedAt => endedAt.subtract(Duration(minutes: minutes));

  Json toJson() => {
        'end': endedAt.toIso8601String(),
        'min': minutes,
        if (long) 'long': true,
      };

  factory BreakSession.fromJson(Json j) => BreakSession(
        endedAt: _date(j['end']),
        minutes: _int(j['min']),
        long: _bool(j['long']),
      );
}

/// Light or dark colours, or follow the phone.
enum Appearance {
  system('System'),
  light('Light'),
  dark('Dark');

  const Appearance(this.label);
  final String label;
}

/// Personal preferences and app behaviour (Settings).
@immutable
class AppPrefs {
  const AppPrefs({
    this.userName = '',
    this.smartScanner = true,
    this.hidePlusBanner = false,
    this.keepScreenOn = true,
    this.vibrateOnFinish = true,
    this.focusBubbles = true,
    this.timerAlerts = true,
    this.dailyReminder = false,
    this.reminderMinutes = 19 * 60,
    this.askedNotifications = false,
    this.appearance = Appearance.system,
    this.palette = 'navy',
    this.customHue = 200,
    this.plus = false,
  });

  /// Shown in greetings ("Hello, Budi!").
  final String userName;

  /// Use the phone's document scanner (auto edge detection) when available.
  final bool smartScanner;
  final bool hidePlusBanner;

  /// Focus Mode keeps the screen awake while it's open.
  final bool keepScreenOn;

  /// Vibrate when a Pomodoro or break ends.
  final bool vibrateOnFinish;

  /// Soft bubbles drift up behind the timer in Focus Mode.
  final bool focusBubbles;

  /// A notification (with sound) when a Pomodoro or break ends, even if the
  /// app is closed.
  final bool timerAlerts;

  /// A daily "time to study" notification at [reminderMinutes] after
  /// midnight (e.g. 19:00 = 1140).
  final bool dailyReminder;
  final int reminderMinutes;

  /// The phone's "allow notifications?" question has been asked once, on
  /// the first START (Timer Alerts are on from the start).
  final bool askedNotifications;

  /// Light, dark, or the same as the phone.
  final Appearance appearance;

  /// The chosen colour theme, by name (see `Palette` in app_colors.dart).
  /// Themes other than the default need tAsikaso+.
  final String palette;

  /// The hue (0–360) of the user's own colour ("Custom").
  final double customHue;

  /// tAsikaso+ is active. (Payments aren't connected yet; debug builds can
  /// switch it on from the plans page for testing.)
  final bool plus;

  AppPrefs copyWith({
    String? userName,
    bool? smartScanner,
    bool? hidePlusBanner,
    bool? keepScreenOn,
    bool? vibrateOnFinish,
    bool? focusBubbles,
    bool? timerAlerts,
    bool? dailyReminder,
    int? reminderMinutes,
    bool? askedNotifications,
    Appearance? appearance,
    String? palette,
    double? customHue,
    bool? plus,
  }) =>
      AppPrefs(
        userName: userName ?? this.userName,
        smartScanner: smartScanner ?? this.smartScanner,
        hidePlusBanner: hidePlusBanner ?? this.hidePlusBanner,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        vibrateOnFinish: vibrateOnFinish ?? this.vibrateOnFinish,
        focusBubbles: focusBubbles ?? this.focusBubbles,
        timerAlerts: timerAlerts ?? this.timerAlerts,
        dailyReminder: dailyReminder ?? this.dailyReminder,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        askedNotifications: askedNotifications ?? this.askedNotifications,
        appearance: appearance ?? this.appearance,
        palette: palette ?? this.palette,
        customHue: customHue ?? this.customHue,
        plus: plus ?? this.plus,
      );

  Json toJson() => {
        'name': userName,
        'smartScanner': smartScanner,
        'hidePlus': hidePlusBanner,
        'awake': keepScreenOn,
        'vibrate': vibrateOnFinish,
        'bubbles': focusBubbles,
        'alerts': timerAlerts,
        'reminder': dailyReminder,
        'reminderAt': reminderMinutes,
        'asked': askedNotifications,
        'theme': appearance.name,
        'palette': palette,
        'hue': customHue,
        'plus': plus,
      };

  factory AppPrefs.fromJson(Json j) => AppPrefs(
        userName: j['name'] as String? ?? '',
        smartScanner: j['smartScanner'] != false,
        hidePlusBanner: _bool(j['hidePlus']),
        keepScreenOn: j['awake'] != false,
        vibrateOnFinish: j['vibrate'] != false,
        focusBubbles: j['bubbles'] != false,
        timerAlerts: j['alerts'] != false,
        dailyReminder: _bool(j['reminder']),
        reminderMinutes: _minuteOfDay(_int(j['reminderAt'], 19 * 60)),
        askedNotifications: _bool(j['asked']),
        appearance: Appearance.values.firstWhere(
          (a) => a.name == j['theme'],
          orElse: () => Appearance.system,
        ),
        palette: j['palette'] as String? ?? 'navy',
        customHue: (j['hue'] is num ? (j['hue'] as num).toDouble() : 200.0) % 360,
        plus: _bool(j['plus']),
      );
}
