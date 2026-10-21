import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../data/app_store.dart';
import 'drive_store.dart';

/// Keeps the user's data in their own Google Drive and brings it back on
/// any device: sign in with Google once, then every change is uploaded
/// (a little after it happens, and when the app goes to the background),
/// and a new phone can restore everything.
///
/// What's on Drive is the same as a backup file, unpacked: `data.json`
/// plus every PDF, photo and thumbnail, in the app's private Drive folder
/// (`appDataFolder`), which the user can't see in Drive and other apps
/// can't read. Only files that are new are uploaded; files of deleted
/// notes and sets are removed.
///
/// Needs a Google OAuth client for the app (see README → Google Drive
/// sync); without one, signing in fails with a clear message.
class DriveSync extends ChangeNotifier {
  DriveSync._();

  static final DriveSync instance = DriveSync._();

  /// Drive's "app data" scope: this app's own hidden folder, nothing else.
  static const scopes = [drive.DriveApi.driveAppdataScope];

  /// The web OAuth client id, built in with `--dart-define=GOOGLE_CLIENT_ID=…`.
  /// Android needs none in the app (its client is registered by package
  /// name and signing key).
  static const _clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  /// The name of the small file on Drive; the others are named after
  /// their keys (`notes/x.pdf` → `notes__x.pdf`).
  static const dataName = 'data.json';

  /// Where this service keeps its own bookkeeping on the device. Not part
  /// of the user's data, so it isn't synced or backed up.
  static const _stateKey = 'drive/state.json';

  /// How long after the last change the upload starts.
  static Duration autoSyncDelay = const Duration(seconds: 90);

  /// Set in tests to stand in for Google Drive (and to count as supported).
  @visibleForTesting
  static DriveStore? debugStore;

  bool _initialized = false;
  GoogleSignInAccount? _account;
  String? _email;
  bool _busy = false;
  String? _error;
  RemoteFile? _remoteData;
  DateTime? _lastSyncAt;
  bool _autoSync = true;
  String? _uploadedJson;
  bool _dirty = false;
  bool _ignoreChanges = false;
  Timer? _timer;
  Future<String?>? _running;
  AppLifecycleListener? _lifecycle;

  /// Google sign-in works in the Android and iOS apps and on the web.
  bool get isSupported =>
      debugStore != null ||
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get isSignedIn => _email != null;
  String? get email => _email;
  bool get busy => _busy;

  /// What went wrong last time, in words, or null.
  String? get error => _error;

  /// `data.json` as it is on Drive, or null when nothing is there yet.
  RemoteFile? get remote => _remoteData;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get autoSync => _autoSync;

  /// Drive holds data saved after this device last synced (another device
  /// uploaded since), so a restore would bring something new.
  bool get remoteNewer {
    final r = _remoteData?.modifiedTime;
    final l = _lastSyncAt;
    if (r == null) return false;
    return l == null || r.isAfter(l.add(const Duration(seconds: 5)));
  }

  /// Changes made here that Drive doesn't have yet.
  bool get hasUnsyncedChanges => _dirty;

  /// Loads the saved state, signs the user back in quietly, and starts
  /// watching for changes. Safe to call more than once.
  Future<void> init() async {
    if (_initialized || !isSupported) return;
    _initialized = true;
    final store = AppStore.instance;
    await _loadState();
    store.addListener(_onStoreChanged);
    AppStore.onEraseEverything = forget;
    _lifecycle = AppLifecycleListener(onHide: _onHide);
    if (debugStore != null) return;

    try {
      await GoogleSignIn.instance
          .initialize(clientId: _clientId.isEmpty ? null : _clientId);
      GoogleSignIn.instance.authenticationEvents.listen(
        _onAuthEvent,
        onError: (Object e) => debugPrint('Google sign-in: $e'),
      );
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = attempt == null ? null : await attempt;
      if (account != null) {
        await _signedIn(account.email, account);
      } else if (_email != null && kIsWeb) {
        // On the web the session is restored through the event stream, if
        // at all; until then the saved account name is shown.
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Google sign-in could not start: $e');
    }
  }

  void _onAuthEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _signedIn(event.user.email, event.user);
      case GoogleSignInAuthenticationEventSignOut():
        _account = null;
    }
  }

  /// Signs in with Google and asks for Drive access. Returns null when it
  /// worked (or the user backed out), else what went wrong, in words.
  Future<String?> signIn() async {
    if (!isSupported) return 'Google sign-in works in the Android app and on the web.';
    if (!_initialized) await init();
    _setBusy(true);
    try {
      if (debugStore != null) {
        await _signedIn(await debugStore!.accountEmail() ?? 'test', null);
        return null;
      }
      if (GoogleSignIn.instance.supportsAuthenticate()) {
        final account =
            await GoogleSignIn.instance.authenticate(scopeHint: scopes);
        final client = account.authorizationClient;
        if (await client.authorizationForScopes(scopes) == null) {
          await client.authorizeScopes(scopes);
        }
        await _signedIn(account.email, account);
      } else {
        // Web: asking for the Drive scope signs the user in as well; Drive
        // then tells us who they are.
        final authz = await GoogleSignIn.instance.authorizationClient
            .authorizeScopes(scopes);
        final store = GoogleDriveStore(authz.authClient(scopes: scopes));
        String? email;
        try {
          email = await store.accountEmail();
        } finally {
          store.close();
        }
        await _signedIn(email ?? 'Google account', null);
      }
      return null;
    } on GoogleSignInException catch (e) {
      return _describe(e);
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return "Couldn't sign in to Google. Check your internet connection and "
          'try again.';
    } finally {
      _setBusy(false);
    }
  }

  /// Signs out. The data on Drive stays; this device keeps its own copy.
  Future<void> signOut() async {
    _timer?.cancel();
    _email = null;
    _account = null;
    _remoteData = null;
    _lastSyncAt = null;
    _uploadedJson = null;
    _dirty = false;
    _error = null;
    await _saveState();
    if (debugStore == null && _initialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Google sign-out: $e');
      }
    }
    notifyListeners();
  }

  /// After Delete All Data: forget the account here, so the next sync
  /// can't wipe the copy on Drive. The user can sign in and restore it.
  void forget() => signOut();

  void setAutoSync(bool on) {
    _autoSync = on;
    _saveState();
    notifyListeners();
    if (on && _dirty) _schedule();
  }

  /// Signs in for tests, with [debugStore] standing in for Drive.
  @visibleForTesting
  Future<void> debugSignIn({String email = 'student@example.com'}) async {
    if (!_initialized) {
      _initialized = true;
      await _loadState();
      AppStore.instance.addListener(_onStoreChanged);
      AppStore.onEraseEverything = forget;
    }
    await _signedIn(email, null);
  }

  /// Back to nothing, for tests.
  @visibleForTesting
  Future<void> resetForTesting() async {
    _timer?.cancel();
    if (_initialized) {
      AppStore.instance.removeListener(_onStoreChanged);
      AppStore.onEraseEverything = null;
    }
    _lifecycle?.dispose();
    _lifecycle = null;
    _initialized = false;
    _account = null;
    _email = null;
    _busy = false;
    _error = null;
    _remoteData = null;
    _lastSyncAt = null;
    _autoSync = true;
    _uploadedJson = null;
    _dirty = false;
    _running = null;
  }

  Future<void> _signedIn(String email, GoogleSignInAccount? account) async {
    _account = account;
    final changed = email != _email;
    _email = email;
    _error = null;
    if (changed) {
      // A different account: what we knew about Drive no longer applies.
      _remoteData = null;
      _lastSyncAt = null;
      _uploadedJson = null;
    }
    await _saveState();
    notifyListeners();
    await checkRemote();
  }

  /// Looks at what is on Drive (so [remote] and [remoteNewer] are right).
  /// Returns what went wrong, or null.
  Future<String?> checkRemote() async {
    if (!isSignedIn) return null;
    try {
      final store = await _driveStore();
      try {
        final files = await store.list();
        _remoteData = _dataFile(files);
      } finally {
        store.close();
      }
      _error = null;
      notifyListeners();
      return null;
    } catch (e) {
      return _fail(e);
    }
  }

  /// Uploads what Drive doesn't have yet: `data.json` when it changed,
  /// new PDFs and photos; removes the files of deleted notes and sets.
  /// Returns what went wrong, or null.
  Future<String?> syncNow({bool interactive = false}) =>
      _runOne(() => _upload(interactive: interactive));

  /// Replaces everything on this device with what is on Drive. Returns
  /// what went wrong, or null.
  Future<String?> restoreFromDrive() => _runOne(_restore);

  Future<String?> _runOne(Future<String?> Function() work) {
    final running = _running;
    if (running != null) return running;
    _setBusy(true);
    final future = work().whenComplete(() {
      _running = null;
      _setBusy(false);
    });
    _running = future;
    return future;
  }

  Future<String?> _upload({required bool interactive}) async {
    if (!isSignedIn) return 'Sign in with Google first.';
    final app = AppStore.instance;
    try {
      final store = await _driveStore(interactive: interactive);
      try {
        await app.pendingSaves;
        final remote = {for (final f in await store.list()) f.name: f};
        final json = app.exportJson();
        final data = remote[dataName];
        if (data == null || json != _uploadedJson) {
          _remoteData = await store.upload(
            dataName,
            Uint8List.fromList(utf8.encode(json)),
            replaceId: data?.id,
          );
          _uploadedJson = json;
        } else {
          _remoteData = data;
        }

        final local = (await app.dataFileKeys()).toSet();
        for (final key in local) {
          final name = remoteName(key);
          if (remote.containsKey(name)) continue;
          final bytes = await app.readFile(key);
          if (bytes != null) await store.upload(name, bytes);
        }
        for (final f in remote.values) {
          final key = localKey(f.name);
          if (key != null && !local.contains(key)) await store.delete(f.id);
        }
      } finally {
        store.close();
      }
      _dirty = false;
      _lastSyncAt = clock.now();
      _error = null;
      await _saveState();
      notifyListeners();
      return null;
    } catch (e) {
      return _fail(e);
    }
  }

  Future<String?> _restore() async {
    if (!isSignedIn) return 'Sign in with Google first.';
    final app = AppStore.instance;
    try {
      final store = await _driveStore(interactive: true);
      final String json;
      final files = <String, Uint8List>{};
      final RemoteFile data;
      try {
        final all = await store.list();
        final found = _dataFile(all);
        if (found == null) return 'There is nothing on Google Drive yet.';
        data = found;
        json = utf8.decode(await store.download(data.id));
        for (final f in all) {
          final key = localKey(f.name);
          if (key != null) files[key] = await store.download(f.id);
        }
      } finally {
        store.close();
      }
      _ignoreChanges = true;
      try {
        await app.restoreFrom(json: json, files: files);
      } finally {
        _ignoreChanges = false;
      }
      _remoteData = data;
      _uploadedJson = app.exportJson();
      _dirty = false;
      _lastSyncAt = clock.now();
      _error = null;
      await _saveState();
      notifyListeners();
      return null;
    } on FormatException catch (e) {
      return _fail(e, e.message);
    } catch (e) {
      return _fail(e);
    }
  }

  // ---- When to sync --------------------------------------------------------

  void _onStoreChanged() {
    if (_ignoreChanges || !isSignedIn) return;
    _dirty = true;
    if (_autoSync) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(autoSyncDelay, () {
      _timer = null;
      if (_dirty && isSignedIn && _autoSync) syncNow();
    });
  }

  /// The app went to the background: a good moment to upload.
  void _onHide() {
    if (_dirty && isSignedIn && _autoSync && _running == null) {
      _timer?.cancel();
      _timer = null;
      syncNow();
    }
  }

  // ---- Drive access ------------------------------------------------------------

  Future<DriveStore> _driveStore({bool interactive = false}) async {
    if (debugStore case final s?) return s;
    final client = _account?.authorizationClient ??
        GoogleSignIn.instance.authorizationClient;
    var authz = await client.authorizationForScopes(scopes);
    if (authz == null) {
      if (!interactive) throw const _NeedsSignIn();
      authz = await client.authorizeScopes(scopes);
    }
    return GoogleDriveStore(authz.authClient(scopes: scopes));
  }

  static RemoteFile? _dataFile(List<RemoteFile> files) {
    for (final f in files) {
      if (f.name == dataName) return f;
    }
    return null;
  }

  /// `notes/x.pdf` → `notes__x.pdf` (Drive names shouldn't carry paths).
  static String remoteName(String key) => key.replaceAll('/', '__');

  /// `notes__x.pdf` → `notes/x.pdf`; null for files that aren't data.
  static String? localKey(String name) {
    if (name == dataName) return null;
    final key = name.replaceAll('__', '/');
    if (key.startsWith('notes/') || key.startsWith('sets/')) return key;
    return null;
  }

  String _fail(Object e, [String? message]) {
    debugPrint('Google Drive sync: $e');
    _error = message ?? _describe(e);
    notifyListeners();
    return _error!;
  }

  static String _describe(Object e) => switch (e) {
        _NeedsSignIn() => 'Google asked to sign in again. Open Backup & Sync '
            'and tap Sync Now.',
        GoogleSignInException(code: GoogleSignInExceptionCode.canceled) => '',
        GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError ||
              GoogleSignInExceptionCode.providerConfigurationError
        ) =>
          "Google sign-in isn't set up for this build yet: the app's OAuth "
              'client is missing (see README → Google Drive sync).',
        GoogleSignInException(code: GoogleSignInExceptionCode.uiUnavailable) =>
          "Google sign-in isn't available on this device.",
        GoogleSignInException(description: final d) =>
          'Google sign-in failed${d == null ? '' : ': $d'}.',
        drive.DetailedApiRequestError(status: 401 || 403) =>
          'Google Drive refused the request. Sign out and sign in again.',
        drive.DetailedApiRequestError(status: 507) =>
          'Your Google Drive is full.',
        _ => "Couldn't reach Google Drive. Check your internet connection and "
            'try again.',
      };

  void _setBusy(bool v) {
    if (_busy == v) return;
    _busy = v;
    notifyListeners();
  }

  // ---- Saved state -----------------------------------------------------------

  Future<void> _loadState() async {
    try {
      final bytes = await AppStore.instance.readAppFile(_stateKey);
      if (bytes == null) return;
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map) return;
      _email = j['email'] is String ? j['email'] as String : null;
      _lastSyncAt =
          j['lastSync'] is String ? DateTime.tryParse(j['lastSync'] as String) : null;
      _autoSync = j['auto'] != false;
    } catch (e) {
      debugPrint('Drive sync state could not be read: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      await AppStore.instance.writeAppFile(
        _stateKey,
        Uint8List.fromList(utf8.encode(jsonEncode({
          'email': ?_email,
          'lastSync': ?_lastSyncAt?.toUtc().toIso8601String(),
          'auto': _autoSync,
        }))),
      );
    } catch (e) {
      debugPrint('Drive sync state could not be saved: $e');
    }
  }
}

/// Drive access needs the user to sign in again (the token has expired).
class _NeedsSignIn implements Exception {
  const _NeedsSignIn();
}
