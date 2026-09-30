import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import 'seed_data.dart';
import 'storage/local_storage.dart';
import 'storage/local_storage_memory.dart';

/// A deleted task and where it was, so it can be put back.
typedef RemovedTask = ({StudyTask task, int index, bool wasCurrent});

/// Single source of truth for the app's data. Screens listen to it with
/// `ListenableBuilder`; every change is saved to the device automatically.
class AppStore extends ChangeNotifier {
  AppStore._() {
    _seed();
  }

  static final AppStore instance = AppStore._();

  LocalStorage _storage = MemoryStorage();

  /// False on web (for now) and in tests: data lasts until the app closes.
  bool get isPersistent => _storage.isPersistent;

  final List<StudyFolder> _folders = [];
  final List<Note> _notes = []; // newest first
  final List<StudyTask> _tasks = [];
  final List<FlashcardSet> _sets = []; // newest first
  PomodoroSettings _settings = const PomodoroSettings();
  String? _currentTaskId;
  final Map<String, int> _focusLog = {}; // day key -> minutes
  final Map<String, int> _reviewLog = {}; // day key -> cards reviewed
  final Map<String, Uint8List> _thumbs = {}; // note id -> small JPEG
  final List<FocusSession> _sessions = []; // oldest first
  final List<BreakSession> _breaks = []; // oldest first
  AppPrefs _prefs = const AppPrefs();

  /// Oldest sessions are dropped beyond this to keep the save file small.
  static const _maxSessions = 5000;

  Future<void> _saveChain = Future.value();

  /// Completes when all pending saves are written. For tests.
  @visibleForTesting
  Future<void> get pendingSaves => _saveChain;

  void _seed() {
    _folders
      ..clear()
      ..addAll(SeedData.folders);
    _tasks
      ..clear()
      ..addAll(SeedData.tasks());
    _notes.clear();
    _sets.clear();
    _settings = const PomodoroSettings();
    _currentTaskId = null;
    _focusLog.clear();
    _reviewLog.clear();
    _thumbs.clear();
    _sessions.clear();
    _breaks.clear();
    _prefs = const AppPrefs();
  }

  /// Loads saved data (or saves the starter data on first launch).
  Future<void> init(LocalStorage storage) async {
    _storage = storage;
    String? raw;
    var loaded = false;
    try {
      raw = await storage.readJson();
      if (raw == null) {
        _persist(); // first launch: save the starter data
      } else {
        _load(jsonDecode(raw) as Map<String, Object?>);
      }
      loaded = true;
    } catch (e, st) {
      debugPrint('Could not load saved data: $e\n$st');
    }

    if (!loaded) {
      // Never overwrite a file we couldn't read unless a copy was kept.
      var backedUp = false;
      if (raw != null) {
        try {
          await storage.writeBytes('data.corrupt.json', utf8.encode(raw));
          backedUp = true;
        } catch (_) {
          // Couldn't keep a copy; handled below.
        }
      }
      _seed();
      if (backedUp) {
        _persist();
      } else {
        // Work in memory this session so the original file stays untouched.
        _storage = MemoryStorage();
      }
    } else {
      for (final n in _notes) {
        try {
          final t = await storage.readBytes(n.thumbKey);
          if (t != null) _thumbs[n.id] = t;
        } catch (_) {
          // A missing thumbnail just shows the grey placeholder.
        }
      }
    }
    notifyListeners();
  }

  /// Deletes every folder, note, flashcard set, task, statistic and setting,
  /// including saved PDFs and photos. Nothing is re-added.
  Future<void> eraseEverything() async {
    try {
      await _storage.deletePrefix('notes/');
      await _storage.deletePrefix('sets/');
    } catch (e) {
      debugPrint('Could not delete some files: $e');
    }
    // Keep the look and tAsikaso+ as they were.
    final keep = _prefs;
    _seed();
    _prefs = _prefs.copyWith(
      appearance: keep.appearance,
      palette: keep.palette,
      customHue: keep.customHue,
      plus: keep.plus,
    );
    _folders.clear();
    _tasks.clear();
    _persist();
    notifyListeners();
  }

  /// Back to starter data with in-memory storage. For tests.
  @visibleForTesting
  void resetForTesting() {
    _storage = MemoryStorage();
    _saveChain = Future<void>.value();
    _seed();
    notifyListeners();
  }

  // ---- Persistence -----------------------------------------------------------

  List<Map<String, Object?>> _maps(Object? list) => [
        for (final item in (list as List<Object?>? ?? const []))
          if (item is Map<String, Object?>) item,
      ];

  /// Parses everything first and only then replaces the current data, so a
  /// bad file can't leave the store half-loaded.
  void _load(Map<String, Object?> j) {
    final folders = _maps(j['folders']).map(StudyFolder.fromJson).toList();
    final notes = _maps(j['notes']).map(Note.fromJson).toList();
    final tasks = _maps(j['tasks']).map(StudyTask.fromJson).toList();
    final sets = _maps(j['sets']).map(FlashcardSet.fromJson).toList();
    final s = j['settings'];
    final settings = s is Map<String, Object?>
        ? PomodoroSettings.fromJson(s)
        : const PomodoroSettings();
    final current = j['currentTask'] as String?;
    final focusLog = _intMap(j['focusLog']);
    final reviewLog = _intMap(j['reviewLog']);
    final sessions = _maps(j['sessions']).map(FocusSession.fromJson).toList();
    final breaks = _maps(j['breaks']).map(BreakSession.fromJson).toList();
    final p = j['prefs'];
    final prefs = p is Map<String, Object?> ? AppPrefs.fromJson(p) : const AppPrefs();

    _folders
      ..clear()
      ..addAll(folders);
    _notes
      ..clear()
      ..addAll(notes);
    _tasks
      ..clear()
      ..addAll(tasks);
    _sets
      ..clear()
      ..addAll(sets);
    _settings = settings;
    _currentTaskId = current;
    _focusLog
      ..clear()
      ..addAll(focusLog);
    _reviewLog
      ..clear()
      ..addAll(reviewLog);
    _sessions
      ..clear()
      ..addAll(sessions);
    _breaks
      ..clear()
      ..addAll(breaks);
    _prefs = prefs;
    _thumbs.clear();
  }

  Map<String, int> _intMap(Object? v) => {
        if (v is Map<String, Object?>)
          for (final e in v.entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
      };

  Map<String, Object?> _toJson() => {
        'version': 1,
        'folders': [for (final f in _folders) f.toJson()],
        'notes': [for (final n in _notes) n.toJson()],
        'tasks': [for (final t in _tasks) t.toJson()],
        'sets': [for (final s in _sets) s.toJson()],
        'settings': _settings.toJson(),
        'currentTask': _currentTaskId,
        'focusLog': _focusLog,
        'reviewLog': _reviewLog,
        'sessions': [for (final s in _sessions) s.toJson()],
        'breaks': [for (final b in _breaks) b.toJson()],
        'prefs': _prefs.toJson(),
      };

  /// Saves in the background, one write at a time, in order.
  void _persist() {
    final data = jsonEncode(_toJson());
    final storage = _storage;
    _saveChain = _saveChain
        .then((_) => storage.writeJson(data))
        .catchError((Object e) => debugPrint('Save failed: $e'));
  }

  void _changed() {
    _persist();
    notifyListeners();
  }

  // ---- Folders ---------------------------------------------------------------

  List<StudyFolder> get folders => List.unmodifiable(_folders);

  StudyFolder? folder(String id) {
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  int noteCountIn(String folderId) =>
      _notes.where((n) => n.folderId == folderId).length;

  int setCountIn(String folderId) =>
      _sets.where((s) => s.folderId == folderId).length;

  /// Folders with the most recent notes or sets first.
  List<StudyFolder> recentFolders([int count = 3]) {
    final last = <String, DateTime>{};
    void bump(String id, DateTime t) {
      final prev = last[id];
      if (prev == null || t.isAfter(prev)) last[id] = t;
    }

    for (final n in _notes) {
      bump(n.folderId, n.createdAt);
    }
    for (final s in _sets) {
      bump(s.folderId, s.createdAt);
    }
    final sorted = List.of(_folders);
    final order = {for (var i = 0; i < _folders.length; i++) _folders[i].id: i};
    sorted.sort((a, b) {
      final ta = last[a.id];
      final tb = last[b.id];
      if (ta != null && tb != null) return tb.compareTo(ta);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return order[a.id]!.compareTo(order[b.id]!);
    });
    return sorted.take(count).toList();
  }

  StudyFolder addFolder(String name, int colorValue) {
    final f = StudyFolder(id: newId(), name: name, colorValue: colorValue);
    _folders.add(f);
    _changed();
    return f;
  }

  void updateFolder(StudyFolder folder) {
    final i = _folders.indexWhere((f) => f.id == folder.id);
    if (i < 0) return;
    _folders[i] = folder;
    _changed();
  }

  /// Deletes the folder together with its notes and flashcard sets.
  Future<void> deleteFolder(String id) async {
    final notes = _notes.where((n) => n.folderId == id).toList();
    final sets = _sets.where((s) => s.folderId == id).toList();
    _folders.removeWhere((f) => f.id == id);
    _notes.removeWhere((n) => n.folderId == id);
    _sets.removeWhere((s) => s.folderId == id);
    for (final n in notes) {
      _thumbs.remove(n.id);
    }
    _changed();
    for (final n in notes) {
      await _storage.delete(n.pdfKey);
      await _storage.delete(n.thumbKey);
    }
    for (final s in sets) {
      await _storage.deletePrefix('sets/${s.id}/');
    }
  }

  // ---- Notes -----------------------------------------------------------------

  /// Newest first.
  List<Note> get notes => List.unmodifiable(_notes);

  List<Note> notesIn(String folderId) =>
      _notes.where((n) => n.folderId == folderId).toList();

  Uint8List? thumbnail(String noteId) => _thumbs[noteId];

  Future<Uint8List?> readPdf(Note note) => _storage.readBytes(note.pdfKey);

  Future<Note> addNote({
    required String title,
    required String folderId,
    required Uint8List pdf,
    required Uint8List thumbnail,
    required int pageCount,
    String text = '',
  }) async {
    final note = Note(
      id: newId(),
      title: title,
      folderId: folderId,
      createdAt: clock.now(),
      pageCount: pageCount,
      text: text,
    );
    await _storage.writeBytes(note.pdfKey, pdf);
    await _storage.writeBytes(note.thumbKey, thumbnail);
    _thumbs[note.id] = thumbnail;
    _notes.insert(0, note);
    _changed();
    return note;
  }

  void updateNote(Note note) {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) return;
    _notes[i] = note;
    _changed();
  }

  Future<void> deleteNote(String id) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final note = _notes.removeAt(i);
    _thumbs.remove(id);
    _changed();
    await _storage.delete(note.pdfKey);
    await _storage.delete(note.thumbKey);
  }

  // ---- Flashcard sets --------------------------------------------------------

  List<FlashcardSet> get sets => List.unmodifiable(_sets);

  List<FlashcardSet> setsIn(String folderId) =>
      _sets.where((s) => s.folderId == folderId).toList();

  FlashcardSet? setById(String id) {
    for (final s in _sets) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<FlashcardSet> addSet({
    required String title,
    required String folderId,
    List<Uint8List> photos = const [],
    List<Flashcard> cards = const [],
    List<Flashcard> suggestions = const [],
  }) async {
    final deck = FlashcardSet(
      id: newId(),
      title: title,
      folderId: folderId,
      createdAt: clock.now(),
      cards: cards,
      suggestions: suggestions,
      photoCount: photos.length,
    );
    for (var i = 0; i < photos.length; i++) {
      await _storage.writeBytes(deck.photoKey(i), photos[i]);
    }
    _sets.insert(0, deck);
    _changed();
    return deck;
  }

  void updateSet(FlashcardSet deck) {
    final i = _sets.indexWhere((s) => s.id == deck.id);
    if (i < 0) return;
    _sets[i] = deck;
    _changed();
  }

  /// Remembers a study session: when, and how many cards were known on the
  /// first try out of those seen. Called as cards are answered.
  void markSetStudied(String id, {required int known, required int seen}) {
    final i = _sets.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _sets[i] = _sets[i].copyWith(
      lastStudiedAt: clock.now(),
      lastKnown: known,
      lastSeen: seen,
    );
    _changed();
  }

  /// Sets with cards, most recently studied first; sets never studied follow,
  /// newest first.
  List<FlashcardSet> recentSets(int count) {
    final withCards = _sets.where((s) => s.cards.isNotEmpty).toList();
    final studied = withCards.where((s) => s.lastStudiedAt != null).toList()
      ..sort((a, b) => b.lastStudiedAt!.compareTo(a.lastStudiedAt!));
    final fresh = withCards.where((s) => s.lastStudiedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...studied, ...fresh].take(count).toList();
  }

  Future<void> deleteSet(String id) async {
    _sets.removeWhere((s) => s.id == id);
    _changed();
    await _storage.deletePrefix('sets/$id/');
  }

  Future<Uint8List?> readSetPhoto(FlashcardSet deck, int index) =>
      _storage.readBytes(deck.photoKey(index));

  // ---- Tasks -----------------------------------------------------------------

  /// Unfinished tasks, with the current one always first.
  List<StudyTask> get activeTasks {
    final list = _tasks.where((t) => !t.done).toList();
    final current = currentTask;
    if (current != null && list.first.id != current.id) {
      list
        ..removeWhere((t) => t.id == current.id)
        ..insert(0, current);
    }
    return list;
  }

  List<StudyTask> get completedTasks => _tasks.where((t) => t.done).toList();

  /// The task the timer works on: the one the user picked, otherwise the
  /// first unfinished task.
  StudyTask? get currentTask {
    for (final t in _tasks) {
      if (t.id == _currentTaskId && !t.done) return t;
    }
    for (final t in _tasks) {
      if (!t.done) return t;
    }
    return null;
  }

  /// Makes [id] the task the timer works on and moves it to the top.
  void selectTask(String id) {
    _currentTaskId = id;
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i > 0) _tasks.insert(0, _tasks.removeAt(i));
    _changed();
  }

  StudyTask addTask(String title, int pomodoros) {
    final t = StudyTask(
      id: newId(),
      title: title,
      pomodorosTotal: pomodoros,
      createdAt: clock.now(),
    );
    _tasks.add(t);
    _changed();
    return t;
  }

  void updateTask(StudyTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return;
    _tasks[i] = task;
    _changed();
  }

  /// Deletes a task. Returns what [restoreTask] needs to undo it.
  RemovedTask? deleteTask(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    final removed = (
      task: _tasks.removeAt(i),
      index: i,
      wasCurrent: _currentTaskId == id,
    );
    if (removed.wasCurrent) _currentTaskId = null;
    _changed();
    return removed;
  }

  /// Puts back a task removed by [deleteTask] ("Undo").
  void restoreTask(RemovedTask removed) {
    if (_tasks.any((t) => t.id == removed.task.id)) return;
    final i = removed.index > _tasks.length ? _tasks.length : removed.index;
    _tasks.insert(i, removed.task);
    if (removed.wasCurrent) _currentTaskId = removed.task.id;
    _changed();
  }

  /// Removes every finished task.
  void clearCompletedTasks() {
    _tasks.removeWhere((t) => t.done);
    _changed();
  }

  // ---- Settings --------------------------------------------------------------

  PomodoroSettings get settings => _settings;

  void updateSettings(PomodoroSettings s) {
    _settings = s;
    _changed();
  }

  // ---- Stats -----------------------------------------------------------------

  /// Called when a focus session finishes. Credits the current task.
  void recordFocusSession(int minutes) {
    final now = clock.now();
    final key = dayKey(now);
    _focusLog[key] = (_focusLog[key] ?? 0) + minutes;
    final task = currentTask;
    _sessions.add(FocusSession(
      endedAt: now,
      minutes: minutes,
      taskId: task?.id,
      taskTitle: task?.title,
    ));
    if (_sessions.length > _maxSessions) {
      _sessions.removeRange(0, _sessions.length - _maxSessions);
    }
    if (task != null) {
      final i = _tasks.indexWhere((t) => t.id == task.id);
      _tasks[i] = task.copyWith(
        pomodorosDone: task.pomodorosDone + 1,
        focusMinutes: task.focusMinutes + minutes,
      );
    }
    _changed();
  }

  /// Called when a break ends (or is skipped after at least a minute).
  void recordBreak(int minutes, {required bool long}) {
    if (minutes <= 0) return;
    _breaks.add(BreakSession(endedAt: clock.now(), minutes: minutes, long: long));
    if (_breaks.length > _maxSessions) {
      _breaks.removeRange(0, _breaks.length - _maxSessions);
    }
    _changed();
  }

  void recordCardsReviewed(int count) {
    if (count <= 0) return;
    final key = dayKey(clock.now());
    _reviewLog[key] = (_reviewLog[key] ?? 0) + count;
    _changed();
  }

  int get focusMinutesToday => _focusLog[dayKey(clock.now())] ?? 0;
  int get cardsReviewedToday => _reviewLog[dayKey(clock.now())] ?? 0;

  /// Days in a row with a finished Pomodoro or reviewed cards. Today counts
  /// once you've studied; until then the streak from yesterday still shows.
  int get streakDays {
    bool active(DateTime d) {
      final k = dayKey(d);
      return (_focusLog[k] ?? 0) > 0 || (_reviewLog[k] ?? 0) > 0;
    }

    final now = clock.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!active(day)) day = DateTime(day.year, day.month, day.day - 1);
    var count = 0;
    while (active(day)) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  // ---- Search ----------------------------------------------------------------

  bool _matches(String text, String query) =>
      text.toLowerCase().contains(query.toLowerCase());

  List<StudyFolder> searchFolders(String q) =>
      _folders.where((f) => _matches(f.name, q)).toList();

  List<Note> searchNotes(String q) => _notes
      .where((n) =>
          _matches(n.title, q) ||
          _matches(n.text, q) ||
          _matches(folder(n.folderId)?.name ?? '', q))
      .toList();

  List<FlashcardSet> searchSets(String q) => _sets
      .where((s) =>
          _matches(s.title, q) ||
          s.cards.any((c) => _matches(c.front, q) || _matches(c.back, q)))
      .toList();

  // ---- Preferences -----------------------------------------------------------

  AppPrefs get prefs => _prefs;

  /// tAsikaso+ is active.
  bool get isPlus => _prefs.plus;

  /// The colour theme to show: the chosen one if it's free or tAsikaso+ is
  /// active, otherwise the default.
  Palette get palette {
    final chosen = Palette.values.firstWhere(
      (p) => p.name == _prefs.palette,
      orElse: () => Palette.navy,
    );
    return chosen.isFree || isPlus ? chosen : Palette.navy;
  }

  /// The user's own colour (used when [palette] is [Palette.custom]).
  ThemeColors get customColors => ThemeColors.fromHue(_prefs.customHue);

  /// The colours of [palette].
  ThemeColors get themeColors =>
      palette == Palette.custom ? customColors : palette.colors;

  void updatePrefs(AppPrefs p) {
    _prefs = p;
    _changed();
  }

  // ---- Analysis --------------------------------------------------------------

  /// Finished Pomodoros, oldest first.
  List<FocusSession> get sessions => List.unmodifiable(_sessions);

  /// Sessions that ended on or after [from] and before [to].
  List<FocusSession> sessionsBetween(DateTime from, DateTime to) => _sessions
      .where((s) => !s.endedAt.isBefore(from) && s.endedAt.isBefore(to))
      .toList();

  /// Breaks that ended on or after [from] and before [to], oldest first.
  List<BreakSession> breaksBetween(DateTime from, DateTime to) => _breaks
      .where((b) => !b.endedAt.isBefore(from) && b.endedAt.isBefore(to))
      .toList();

  /// All breaks, oldest first.
  List<BreakSession> get breaks => List.unmodifiable(_breaks);

  /// Focus minutes per day from [from] (inclusive) to [to] (exclusive).
  int focusMinutesBetween(DateTime from, DateTime to) {
    var total = 0;
    for (var d = startOfDay(from);
        d.isBefore(to);
        d = DateTime(d.year, d.month, d.day + 1)) {
      total += focusMinutesOn(d);
    }
    return total;
  }

  int focusMinutesOn(DateTime day) => _focusLog[dayKey(day)] ?? 0;
  int cardsReviewedOn(DateTime day) => _reviewLog[dayKey(day)] ?? 0;

  /// True if the user finished a Pomodoro or reviewed cards that day.
  bool activeOn(DateTime day) => focusMinutesOn(day) > 0 || cardsReviewedOn(day) > 0;

  /// Longest run of active days ever.
  int get longestStreak {
    final days = <DateTime>{
      for (final k in {..._focusLog.keys, ..._reviewLog.keys})
        if ((_focusLog[k] ?? 0) > 0 || (_reviewLog[k] ?? 0) > 0)
          if (DateTime.tryParse(k) case final d?) DateTime(d.year, d.month, d.day),
    }.toList()
      ..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      final next = prev == null ? null : DateTime(prev.year, prev.month, prev.day + 1);
      run = (next != null && next == d) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }
}
