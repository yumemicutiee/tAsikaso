import 'dart:convert';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'plans.dart';
import '../theme/app_colors.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/spaced_review.dart';
import 'backup.dart';
import 'seed_data.dart';
import 'storage/local_storage.dart';
import 'storage/local_storage_memory.dart';

/// A deleted task and where it was, so it can be put back.
typedef RemovedTask = ({StudyTask task, int index, bool wasCurrent});

/// Something the user needs to know about their data (it couldn't be read
/// or saved). The app shell shows it.
typedef StoreProblem = ({String title, String message});

/// Thrown when the saved data comes from a newer version of the app.
class _NewerDataException implements Exception {
  const _NewerDataException();
}

/// Single source of truth for the app's data. Screens listen to it with
/// `ListenableBuilder`; every change is saved to the device automatically.
class AppStore extends ChangeNotifier {
  AppStore._() {
    _seed();
  }

  static final AppStore instance = AppStore._();

  /// Called after [eraseEverything] (Google Drive sync forgets the
  /// account, so the copy on Drive isn't wiped too).
  static void Function()? onEraseEverything;

  /// Version of the save file this app writes. Files from a newer version are
  /// never overwritten.
  static const _dataVersion = 1;

  /// The last save file that loaded without problems (updated at start-up).
  static const _backupKey = 'backup/data.json';

  /// Copies of save files that couldn't be read completely.
  static const _recoveryPrefix = 'recovery/';

  LocalStorage _storage = MemoryStorage();

  /// The device's storage while saving is paused (see [_pauseSaving]): still
  /// read from, so saved PDFs and photos keep opening, but never written to.
  LocalStorage? _paused;

  /// Where PDFs, photos and thumbnails are read from.
  LocalStorage get _files => _paused ?? _storage;

  /// False on web (for now) and in tests: data lasts until the app closes.
  /// Also false on a phone when saving was paused because the saved data
  /// couldn't be read, so that it stays untouched.
  bool get isPersistent => _storage.isPersistent;

  /// The latest problem to tell the user about, or null. The app shell
  /// shows it and sets this back to null.
  final ValueNotifier<StoreProblem?> problem = ValueNotifier(null);

  /// True after a save failed, until one succeeds again.
  bool _saveFailed = false;

  final List<StudyFolder> _folders = [];
  final List<Note> _notes = []; // newest first
  final List<StudyTask> _tasks = [];
  final List<FlashcardSet> _sets = []; // newest first
  PomodoroSettings _settings = const PomodoroSettings();
  String? _currentTaskId;
  final Map<String, int> _focusLog = {}; // day key -> minutes
  final Map<String, int> _reviewLog = {}; // day key -> cards reviewed
  final Map<String, int> _suggestedLog = {}; // month key -> suggested cards
  final Map<String, Uint8List> _thumbs = {}; // note id -> small JPEG
  Uint8List? _profilePhoto;
  final List<FocusSession> _sessions = []; // oldest first
  final List<BreakSession> _breaks = []; // oldest first
  AppPrefs _prefs = const AppPrefs();
  TimerSnapshot? _timer;

  /// Oldest sessions are dropped beyond this to keep the save file small.
  static const _maxSessions = 5000;

  Future<void> _saveChain = Future.value();

  /// True while no save is in progress. A new chain then starts from a fresh
  /// future, so it never hangs off one created in another zone (tests run
  /// under fake time; a future made before that would complete outside it).
  bool _saveIdle = true;

  /// Completes when all pending saves are written.
  Future<void> get pendingSaves =>
      _saveIdle ? Future<void>.value() : _saveChain;

  /// Starter data for a first launch: sample folders and tasks.
  void _seed() {
    _clear();
    _folders.addAll(SeedData.folders);
    _tasks.addAll(SeedData.tasks());
  }

  /// No data at all.
  void _clear() {
    _folders.clear();
    _tasks.clear();
    _notes.clear();
    _sets.clear();
    _settings = const PomodoroSettings();
    _currentTaskId = null;
    _focusLog.clear();
    _reviewLog.clear();
    _suggestedLog.clear();
    _thumbs.clear();
    _profilePhoto = null;
    _sessions.clear();
    _breaks.clear();
    _prefs = const AppPrefs();
    _timer = null;
  }

  /// Loads saved data (or saves the starter data on first launch).
  ///
  /// Saved data is never replaced with sample data. If it can't be read, a
  /// copy is kept, the last copy that worked is tried, and [problem] tells
  /// the user what happened.
  Future<void> init(LocalStorage storage) async {
    _storage = storage;
    _paused = null;
    _saveFailed = false;

    String? raw;
    try {
      raw = await storage.readJson();
    } catch (e, st) {
      // The file is there but can't be opened: leave it alone.
      debugPrint('Could not read saved data: $e\n$st');
      _clear();
      _pauseSaving();
      _report(_unreadable(kept: false));
      notifyListeners();
      return;
    }

    if (raw == null) {
      _seed();
      _persist(); // first launch: save the starter data
      notifyListeners();
      return;
    }

    try {
      final skipped = _load(raw);
      if (skipped == 0) {
        await _tryWrite(_backupKey, raw); // the last copy that worked
      } else {
        // Keep the whole file before the unreadable parts are left out.
        final kept = await _keepCopy(raw);
        if (!kept) _pauseSaving();
        _report((
          title: "Some Data Couldn't Be Loaded",
          message: "${plural(skipped, 'item')} in your saved data couldn't "
              "be read, so ${skipped == 1 ? 'it was' : 'they were'} left out. "
              'Everything else is here.'
              '${kept ? '' : ' Changes you make now won\'t be saved, so the '
                  'saved data stays untouched.'}',
        ));
      }
    } on _NewerDataException {
      _clear();
      _pauseSaving();
      _report((
        title: 'Update $kAppName',
        message: 'Your data was saved by a newer version of $kAppName. '
            'Update the app to see it. Until then nothing you do here is '
            'saved, so your data stays safe.',
      ));
    } catch (e, st) {
      debugPrint('Could not load saved data: $e\n$st');
      final kept = await _keepCopy(raw);
      final restored = await _loadBackup(storage);
      if (!restored) _clear();
      if (kept) {
        _persist();
      } else {
        _pauseSaving();
      }
      _report(restored
          ? (
              title: 'Data Restored',
              message: "Your latest saved data couldn't be read, so $kAppName "
                  'brought back the copy from the last time the app opened. '
                  'Changes made after that may be missing.'
                  '${kept ? '' : ' Changes you make now won\'t be saved, so '
                      'the saved data stays untouched.'}',
            )
          : _unreadable(kept: kept));
    }
    await _loadThumbnails(storage);
    await _loadProfilePhoto(storage);
    checkPlanEnded();
    notifyListeners();
  }

  StoreProblem _unreadable({required bool kept}) => (
        title: "Saved Data Couldn't Be Read",
        message: kept
            ? "$kAppName couldn't read your saved data, so it started empty. "
                'A copy of the old data was kept on this device.'
            : "$kAppName couldn't read your saved data. It was left "
                "untouched, and changes you make now won't be saved. Restart "
                'the app to try again.',
      );

  void _report(StoreProblem p) => problem.value = p;

  /// Works in memory for the rest of this session, so the saved file stays
  /// exactly as it is.
  void _pauseSaving() {
    _paused ??= _storage;
    _storage = MemoryStorage();
  }

  /// Loads the last save file that worked. Returns false if there is none
  /// or it can't be read either.
  Future<bool> _loadBackup(LocalStorage storage) async {
    try {
      final bytes = await storage.readBytes(_backupKey);
      if (bytes == null) return false;
      _load(utf8.decode(bytes));
      return true;
    } catch (e) {
      debugPrint('Could not load the backup: $e');
      return false;
    }
  }

  /// Keeps [raw] as a recovery copy. Returns false if that failed.
  Future<bool> _keepCopy(String raw) => _tryWrite(
      '$_recoveryPrefix${clock.now().millisecondsSinceEpoch}.json', raw);

  Future<bool> _tryWrite(String key, String text) async {
    try {
      await _storage.writeBytes(key, utf8.encode(text));
      return true;
    } catch (e) {
      debugPrint('Could not write $key: $e');
      return false;
    }
  }

  Future<void> _loadThumbnails(LocalStorage storage) async {
    for (final n in _notes) {
      try {
        final t = await storage.readBytes(n.thumbKey);
        if (t != null) _thumbs[n.id] = t;
      } catch (_) {
        // A missing thumbnail just shows the grey placeholder.
      }
    }
  }

  Future<void> _loadProfilePhoto(LocalStorage storage) async {
    try {
      _profilePhoto = await storage.readBytes(profilePhotoKey);
    } catch (_) {
      _profilePhoto = null; // the avatar shows the initial instead
    }
  }

  // ---- Profile photo -----------------------------------------------------------

  static const profilePhotoKey = 'profile/photo.jpg';

  /// The user's photo (a square JPEG), or null for the initial / icon.
  Uint8List? get profilePhoto => _profilePhoto;

  /// Sets (or with null, removes) the profile photo. [fromUrl] is the
  /// Google photo link it was taken from, or empty for the user's own.
  Future<void> setProfilePhoto(Uint8List? bytes, {String fromUrl = ''}) async {
    if (bytes == null) {
      await _tryDelete(profilePhotoKey);
    } else {
      await _storage.writeBytes(profilePhotoKey, bytes);
    }
    _profilePhoto = bytes;
    _prefs = _prefs.copyWith(profilePhotoUrl: bytes == null ? '' : fromUrl);
    _changed();
  }

  /// Deletes every folder, note, flashcard set, task, statistic and setting,
  /// including saved PDFs, photos and backup copies. Nothing is re-added.
  ///
  /// Also wipes the device when saving was paused: the user asked for a
  /// clean slate, and that removes the file that couldn't be read, so
  /// saving starts again. Returns false if some files couldn't be deleted.
  Future<bool> eraseEverything() async {
    final device = _paused ?? _storage;
    var clean = true;
    for (final prefix in [
      'notes/',
      'sets/',
      'profile/',
      'backup/',
      'drive/',
      _recoveryPrefix,
    ]) {
      if (!await _tryDeletePrefix(prefix, from: device)) clean = false;
    }
    // The save file itself, and copies kept by older versions.
    for (final key in ['data.json', 'data.json.tmp', 'data.corrupt.json']) {
      if (!await _tryDelete(key, from: device)) clean = false;
    }
    if (_paused != null) {
      _storage = device;
      _paused = null;
      _saveFailed = false;
    }
    // Keep the look, the tAsikaso+ plan and this month's suggested-card
    // count (a plan and its limits aren't study data).
    final keep = _prefs;
    final suggested = Map.of(_suggestedLog);
    _clear();
    _prefs = _prefs.copyWith(
      appearance: keep.appearance,
      palette: keep.palette,
      customHue: keep.customHue,
      subscription: keep.subscription,
    );
    _suggestedLog.addAll(suggested);
    _persist();
    notifyListeners();
    onEraseEverything?.call();
    return clean;
  }

  /// Deletes one file, reporting instead of throwing: a stale file is
  /// better than a crash, and Delete All Data clears it later.
  Future<bool> _tryDelete(String key, {LocalStorage? from}) async {
    try {
      await (from ?? _storage).delete(key);
      return true;
    } catch (e) {
      debugPrint('Could not delete $key: $e');
      return false;
    }
  }

  Future<bool> _tryDeletePrefix(String prefix, {LocalStorage? from}) async {
    try {
      await (from ?? _storage).deletePrefix(prefix);
      return true;
    } catch (e) {
      debugPrint('Could not delete $prefix: $e');
      return false;
    }
  }

  /// Back to starter data with in-memory storage. For tests.
  @visibleForTesting
  void resetForTesting() {
    _storage = MemoryStorage();
    _paused = null;
    _saveChain = Future<void>.value();
    _saveIdle = true;
    _saveFailed = false;
    problem.value = null;
    _seed();
    notifyListeners();
  }

  // ---- Persistence -----------------------------------------------------------

  /// Reads [raw] into the store and returns how many records had to be left
  /// out because they couldn't be read. Everything is parsed first and only
  /// then replaces the current data, so a bad file can't leave the store
  /// half-loaded. Throws if [raw] can't be used at all.
  int _load(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The save file is not a JSON object.');
    }
    final j = decoded;
    final version = j['version'];
    if (version is num && version > _dataVersion) {
      throw const _NewerDataException();
    }

    // One unreadable record is left out instead of losing everything.
    var skipped = 0;
    List<T> all<T>(Object? list, T Function(Json) parse) {
      final out = <T>[];
      if (list == null) return out;
      if (list is! List) {
        skipped++;
        return out;
      }
      for (final item in list) {
        try {
          out.add(parse(item as Json));
        } catch (_) {
          skipped++;
        }
      }
      return out;
    }

    T? one<T>(Object? value, T Function(Json) parse) {
      if (value == null) return null;
      try {
        return parse(value as Json);
      } catch (_) {
        skipped++;
        return null;
      }
    }

    final folders = all(j['folders'], StudyFolder.fromJson);
    final notes = all(j['notes'], Note.fromJson);
    final tasks = all(j['tasks'], StudyTask.fromJson);
    final sets = all(j['sets'], FlashcardSet.fromJson);
    final settings =
        one(j['settings'], PomodoroSettings.fromJson) ?? const PomodoroSettings();
    final current = j['currentTask'];
    final focusLog = _intMap(j['focusLog']);
    final reviewLog = _intMap(j['reviewLog']);
    final suggestedLog = _intMap(j['suggestedLog']);
    final sessions = all(j['sessions'], FocusSession.fromJson);
    final breaks = all(j['breaks'], BreakSession.fromJson);
    final prefs = one(j['prefs'], AppPrefs.fromJson) ?? const AppPrefs();
    final timer = one(j['timer'], TimerSnapshot.fromJson);

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
    _currentTaskId = current is String ? current : null;
    _focusLog
      ..clear()
      ..addAll(focusLog);
    _reviewLog
      ..clear()
      ..addAll(reviewLog);
    _suggestedLog
      ..clear()
      ..addAll(suggestedLog);
    _sessions
      ..clear()
      ..addAll(sessions);
    _breaks
      ..clear()
      ..addAll(breaks);
    _prefs = prefs;
    _timer = timer;
    _thumbs.clear();
    return skipped;
  }

  Map<String, int> _intMap(Object? v) => {
        if (v is Map<String, Object?>)
          for (final e in v.entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
      };

  /// Everything small, as saved on the device. [forExport] (backup files and
  /// the copy on Google Drive, which can be shared) leaves out the study
  /// server's app token: it stays on this device.
  Map<String, Object?> _toJson({bool forExport = false}) => {
        'version': _dataVersion,
        'folders': [for (final f in _folders) f.toJson()],
        'notes': [for (final n in _notes) n.toJson()],
        'tasks': [for (final t in _tasks) t.toJson()],
        'sets': [for (final s in _sets) s.toJson()],
        'settings': _settings.toJson(),
        'currentTask': _currentTaskId,
        'focusLog': _focusLog,
        'reviewLog': _reviewLog,
        if (_suggestedLog.isNotEmpty) 'suggestedLog': _suggestedLog,
        'sessions': [for (final s in _sessions) s.toJson()],
        'breaks': [for (final b in _breaks) b.toJson()],
        'prefs': (forExport ? _prefs.copyWith(aiToken: '') : _prefs).toJson(),
        if (_timer case final t?) 'timer': t.toJson(),
      };

  /// Saves in the background, one write at a time, in order. Every save
  /// writes everything, so after a failed save the next one catches up.
  void _persist() {
    final data = jsonEncode(_toJson());
    final storage = _storage;
    final previous = _saveIdle ? Future<void>.value() : _saveChain;
    _saveIdle = false;
    late final Future<void> run;
    run = previous.then((_) => storage.writeJson(data)).then(
      (_) {
        _saveFailed = false;
      },
      onError: (Object e) {
        debugPrint('Save failed: $e');
        if (_saveFailed) return; // already told the user
        _saveFailed = true;
        _report((
          title: "Couldn't Save",
          message: "$kAppName couldn't save your latest changes. Your "
              'device may be out of storage space. Free up some space: '
              'everything is saved again with your next change.',
        ));
      },
    ).whenComplete(() {
      if (identical(_saveChain, run)) _saveIdle = true;
    });
    _saveChain = run;
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
      await _tryDelete(n.pdfKey);
      await _tryDelete(n.thumbKey);
    }
    for (final s in sets) {
      await _tryDeletePrefix('sets/${s.id}/');
    }
  }

  // ---- Notes -----------------------------------------------------------------

  /// Newest first.
  List<Note> get notes => List.unmodifiable(_notes);

  List<Note> notesIn(String folderId) =>
      _notes.where((n) => n.folderId == folderId).toList();

  Note? note(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Uint8List? thumbnail(String noteId) => _thumbs[noteId];

  Future<Uint8List?> readPdf(Note note) => _files.readBytes(note.pdfKey);

  Future<Note> addNote({
    required String title,
    required String folderId,
    required Uint8List pdf,
    required Uint8List thumbnail,
    required int pageCount,
    String text = '',
    String cleanText = '',
    String summary = '',
    List<Concept> concepts = const [],
  }) async {
    final note = Note(
      id: newId(),
      title: title,
      folderId: folderId,
      createdAt: clock.now(),
      pageCount: pageCount,
      text: text,
      cleanText: cleanText,
      summary: summary,
      concepts: concepts,
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
    await _tryDelete(note.pdfKey);
    await _tryDelete(note.thumbKey);
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
    String sourceText = '',
    String summary = '',
    List<Concept> concepts = const [],
    List<QuizQuestion> quiz = const [],
  }) async {
    final deck = FlashcardSet(
      id: newId(),
      title: title,
      folderId: folderId,
      createdAt: clock.now(),
      cards: cards,
      suggestions: suggestions,
      photoCount: photos.length,
      sourceText: sourceText,
      summary: summary,
      concepts: concepts,
      quiz: quiz,
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

  /// Cards in [deck] due for review today (new cards included).
  List<Flashcard> dueCards(FlashcardSet deck) =>
      deck.dueCards(startOfDay(clock.now()));

  /// Smart review: after the first answer for a card in a round, decides
  /// when it comes back (tomorrow if missed, later and later if known).
  void scheduleCard(String setId, String cardId, {required bool knewIt}) {
    final i = _sets.indexWhere((s) => s.id == setId);
    if (i < 0) return;
    final deck = _sets[i];
    final today = startOfDay(clock.now());
    _sets[i] = deck.copyWith(cards: [
      for (final c in deck.cards)
        if (c.id == cardId)
          c.scheduled(
            interval: nextInterval(c.interval, knewIt: knewIt),
            due: today.add(
                Duration(days: nextInterval(c.interval, knewIt: knewIt))),
          )
        else
          c,
    ]);
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
    await _tryDeletePrefix('sets/$id/');
  }

  Future<Uint8List?> readSetPhoto(FlashcardSet deck, int index) =>
      _files.readBytes(deck.photoKey(index));

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

  StudyTask? task(String? id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

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

  // ---- Timer -----------------------------------------------------------------

  /// The timer as it was last left (see `PomodoroController.restore`).
  TimerSnapshot? get timerSnapshot => _timer;

  /// Saves the timer's state. Screens don't show it from here, so nothing
  /// is rebuilt.
  void saveTimer(TimerSnapshot snapshot) {
    _timer = snapshot;
    _persist();
  }

  // ---- Stats -----------------------------------------------------------------

  /// Called when a focus session finishes, at [endedAt] (default: now).
  ///
  /// Credits the task the Pomodoro was started for ([taskId], with
  /// [taskTitle] kept in case that task was deleted since), or the current
  /// task when neither is given.
  void recordFocusSession(
    int minutes, {
    DateTime? endedAt,
    String? taskId,
    String? taskTitle,
  }) {
    final end = endedAt ?? clock.now();
    final key = dayKey(end);
    _focusLog[key] = (_focusLog[key] ?? 0) + minutes;
    final given = taskId != null || taskTitle != null;
    final task = given ? this.task(taskId) : currentTask;
    _sessions.add(FocusSession(
      endedAt: end,
      minutes: minutes,
      taskId: task?.id ?? taskId,
      taskTitle: task?.title ?? taskTitle,
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

  /// Called when a break ends (or is skipped after at least a minute), at
  /// [endedAt] (default: now).
  void recordBreak(int minutes, {required bool long, DateTime? endedAt}) {
    if (minutes <= 0) return;
    _breaks.add(BreakSession(
        endedAt: endedAt ?? clock.now(), minutes: minutes, long: long));
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

  bool _inConcepts(List<Concept> concepts, String q) => concepts
      .any((c) => _matches(c.term, q) || _matches(c.explanation, q));

  /// Notes whose title, text (as read or typed up), summary, key concepts
  /// or folder name contain [q].
  List<Note> searchNotes(String q) => _notes
      .where((n) =>
          _matches(n.title, q) ||
          _matches(n.text, q) ||
          _matches(n.cleanText, q) ||
          _matches(n.summary, q) ||
          _inConcepts(n.concepts, q) ||
          _matches(folder(n.folderId)?.name ?? '', q))
      .toList();

  /// Sets whose title, cards, summary or key concepts contain [q].
  List<FlashcardSet> searchSets(String q) => _sets
      .where((s) =>
          _matches(s.title, q) ||
          s.cards.any((c) => _matches(c.front, q) || _matches(c.back, q)) ||
          _matches(s.summary, q) ||
          _inConcepts(s.concepts, q))
      .toList();

  // ---- Backup ----------------------------------------------------------------

  /// Everything, as one backup file (see `backup.dart`).
  Future<Uint8List> createBackup() async {
    await pendingSaves; // include the latest change
    final files = <String, Uint8List>{};
    for (final prefix in ['notes/', 'sets/', 'profile/']) {
      for (final key in await _files.list(prefix)) {
        final bytes = await _files.readBytes(key);
        if (bytes != null) files[key] = bytes;
      }
    }
    return packBackup(
      json: exportJson(),
      files: files,
      createdAt: clock.now(),
      appVersion: kAppVersion,
    );
  }

  /// Replaces everything on this device with the backup in [zip]. Throws a
  /// [FormatException] if it isn't a backup this version can read; nothing
  /// is changed in that case.
  Future<void> restoreBackup(Uint8List zip) async {
    final contents = unpackBackup(zip);
    await restoreFrom(json: contents.json, files: contents.files);
  }

  /// Everything small, as the JSON that is backed up and synced: what is
  /// saved, without the study server's app token.
  String exportJson() => jsonEncode(_toJson(forExport: true));

  /// Keys of every PDF, photo and thumbnail on this device, and the
  /// profile photo.
  Future<List<String>> dataFileKeys() async => [
        ...await _files.list('notes/'),
        ...await _files.list('sets/'),
        ...await _files.list('profile/'),
      ];

  Future<Uint8List?> readFile(String key) => _files.readBytes(key);

  /// Files the app keeps for itself (sync state), apart from the user's data.
  Future<Uint8List?> readAppFile(String key) => _storage.readBytes(key);

  Future<void> writeAppFile(String key, Uint8List bytes) =>
      _storage.writeBytes(key, bytes);

  /// Replaces everything on this device with [json] and [files] (from a
  /// backup file or Google Drive). Throws a [FormatException] if the data
  /// can't be used; nothing is changed in that case.
  Future<void> restoreFrom({
    required String json,
    required Map<String, Uint8List> files,
  }) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException("This backup's data can't be read.");
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException("This backup's data can't be read.");
    }
    final version = decoded['version'];
    if (version is num && version > _dataVersion) {
      throw const FormatException(
          'This backup was made by a newer version of $kAppName. '
          'Update the app to restore it.');
    }

    // The plan and this month's suggested-card count belong to this device
    // and account, not to the data being restored: an old backup mustn't
    // end (or start) a plan, or hand back used-up suggestions. So does the
    // study server set up here (backups carry no app token).
    final keepPlan = _prefs.subscription;
    final keepSuggested = Map.of(_suggestedLog);
    final keepServerUrl = _prefs.aiServerUrl;
    final keepToken = _prefs.aiToken;

    // A restore is a clean slate, so it also ends a paused state (the
    // unreadable file is replaced).
    final device = _paused ?? _storage;
    await pendingSaves; // no older save may land on top of the restore
    for (final prefix in ['notes/', 'sets/', 'profile/']) {
      await _tryDeletePrefix(prefix, from: device);
    }
    for (final entry in files.entries) {
      final key = entry.key;
      if (key.startsWith('notes/') ||
          key.startsWith('sets/') ||
          key.startsWith('profile/')) {
        await device.writeBytes(key, entry.value);
      }
    }
    await device.writeJson(json);
    _paused = null;
    await init(device);

    // A server set up on this device wins; a new phone with none takes the
    // backup's address (not a secret) so Smart Study keeps working, plus
    // the token only if the backup is old enough to still carry one.
    _prefs = _prefs.copyWith(
      subscription: keepPlan,
      clearSubscription: keepPlan == null,
      aiServerUrl: keepServerUrl.isNotEmpty ? keepServerUrl : null,
      aiToken: keepServerUrl.isNotEmpty || keepToken.isNotEmpty ? keepToken : null,
    );
    for (final e in keepSuggested.entries) {
      final restored = _suggestedLog[e.key] ?? 0;
      if (e.value > restored) _suggestedLog[e.key] = e.value;
    }
    _changed();
  }

  /// Remembers that a backup file was just made.
  void markBackedUp() =>
      updatePrefs(_prefs.copyWith(lastBackupAt: clock.now()));

  // ---- Preferences -----------------------------------------------------------

  AppPrefs get prefs => _prefs;

  // ---- tAsikaso+ ---------------------------------------------------------------

  /// The plan on record, even if it has ended (see [isPlus]).
  Subscription? get subscription => _prefs.subscription;

  /// tAsikaso+ is active right now.
  bool get isPlus => _prefs.subscription?.activeAt(clock.now()) ?? false;

  /// The active plan, or null on the free plan.
  PlusPlan? get plan => isPlus ? _prefs.subscription!.plan : null;

  /// Starts [plan] now, for one period. Switching from another plan starts
  /// the new one from today. [test] marks a plan switched on without
  /// payment (see [kTestPurchases]).
  void startPlan(PlusPlan plan, {bool test = kTestPurchases}) {
    final now = clock.now();
    _prefs = _prefs.copyWith(
      subscription: Subscription(
        plan: plan,
        startedAt: now,
        endsAt: plan.endFrom(now),
        test: test,
      ),
      hidePlusBanner: false, // shows again if the plan ends
    );
    _changed();
  }

  /// Back to the free plan straight away. Nothing is deleted: colours fall
  /// back to the default and Plus features lock until a plan starts again.
  void endPlan() {
    if (_prefs.subscription == null) return;
    _prefs = _prefs.copyWith(clearSubscription: true);
    _changed();
  }

  /// When a plan on record has run out: back to Free, and the user is told.
  /// Called at start-up; returns true if a plan just ended.
  bool checkPlanEnded() {
    final s = _prefs.subscription;
    if (s == null || s.activeAt(clock.now())) return false;
    _prefs = _prefs.copyWith(clearSubscription: true);
    _persist();
    _report((
      title: 'Your $kPlusName Plan Ended',
      message: 'Your ${s.plan.title} plan ended on '
          '${formatNoteDate(s.endsAt!)}, so you are on the free plan now. '
          'Nothing was deleted: your colors, analysis history, smart review '
          'and backups come back when you start a plan again.',
    ));
    return true;
  }

  // ---- Suggested cards (free: a few a month) ---------------------------------

  int get suggestedCardsThisMonth =>
      _suggestedLog[monthKey(clock.now())] ?? 0;

  /// How many more suggested cards this month's plan allows; null = no
  /// limit (tAsikaso+).
  int? get suggestedCardsLeft => isPlus
      ? null
      : math.max(0, kFreeSuggestedCardsPerMonth - suggestedCardsThisMonth);

  /// Keeps as many of [cards] (made by the app from notes) as the plan
  /// allows this month, counts those, and says how many were left out.
  ({List<Flashcard> kept, int dropped}) takeSuggestedCards(
      List<Flashcard> cards) {
    final left = suggestedCardsLeft;
    final kept =
        left == null || cards.length <= left ? cards : cards.sublist(0, left);
    if (kept.isNotEmpty) {
      final key = monthKey(clock.now());
      _suggestedLog[key] = (_suggestedLog[key] ?? 0) + kept.length;
      _changed();
    }
    return (kept: kept, dropped: cards.length - kept.length);
  }

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
