import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../data/app_store.dart';
import 'accounts.dart';
import 'notification_service.dart';

/// Keeps the user's account data (see `AppStore.accountDataToJson`: the
/// profile and preferences, Pomodoro settings, tasks and statistics, and
/// the profile photo) saved in their tAsikaso account (Supabase table
/// `user_data`, readable and writable only by that user), and brings it
/// back after signing in: after Log Out, or on a new phone.
///
/// Saved a few seconds after a change, when the app goes to the
/// background, and before Log Out. Study materials aren't part of it: they
/// stay on the phone and go to Google Drive with Backup & Sync.
class AccountData {
  AccountData._();

  static final instance = AccountData._();

  /// How long after the last change the data is saved.
  @visibleForTesting
  static Duration delay = const Duration(seconds: 8);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _bringingIn = false;
  String? _savedJson;
  int? _savedPhotoHash;
  Future<bool>? _saving;

  /// Starts watching for changes (once, at start-up).
  void init() {
    if (_started) return;
    _started = true;
    AppStore.instance.addListener(_onChange);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(save()));
  }

  void _onChange() {
    if (_bringingIn || !Accounts.instance.hasSession) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(save()));
  }

  /// Saves the account data now if it changed since the last save. True
  /// when the account has the latest data (also when nothing changed).
  Future<bool> save() async {
    _timer?.cancel();
    // One save at a time; a second caller waits for it, then checks again.
    while (_saving != null) {
      await _saving;
    }
    final run = _save();
    _saving = run;
    try {
      return await run;
    } finally {
      _saving = null;
    }
  }

  Future<bool> _save() async {
    if (!Accounts.instance.hasSession) return false;
    final store = AppStore.instance;
    final data = store.accountDataToJson();
    final json = jsonEncode(data);
    final photo = store.profilePhoto;
    final photoHash = photo == null ? 0 : Object.hashAll(photo);
    final photoChanged = photoHash != _savedPhotoHash;
    if (json == _savedJson && !photoChanged) return true;
    String? photo64;
    if (photoChanged && photo != null) {
      photo64 = base64Encode(await compute(_smallPhoto, photo));
    }
    final ok = await Accounts.instance.saveUserData(data,
        photo: photo64 ?? '', includePhoto: photoChanged);
    if (ok) {
      _savedJson = json;
      _savedPhotoHash = photoHash;
    }
    return ok;
  }

  /// After signing in to a different account: its saved data is merged in
  /// (see `AppStore.mergeAccountData`) and the result saved back. False
  /// when it couldn't be read: then nothing is changed or overwritten.
  Future<bool> bringIn() async {
    _timer?.cancel();
    _bringingIn = true;
    try {
      final Map<String, Object?>? row;
      try {
        row = await Accounts.instance.loadUserData();
      } catch (e) {
        debugPrint("The account's data couldn't be read: $e");
        return false;
      }
      final store = AppStore.instance;
      final data = row?['data'];
      if (data is Map<String, Object?>) store.mergeAccountData(data);
      final photo = row?['photo'];
      if (photo is String && photo.isNotEmpty) {
        try {
          await store.setProfilePhoto(base64Decode(photo),
              fromUrl: store.prefs.profilePhotoUrl);
        } catch (e) {
          debugPrint("The account's photo couldn't be used: $e");
        }
      }
      // The reminder may have come back with the preferences.
      final prefs = store.prefs;
      unawaited(NotificationService.setDailyReminder(
          prefs.dailyReminder ? prefs.reminderMinutes : null));
    } finally {
      _bringingIn = false;
    }
    _savedJson = null;
    _savedPhotoHash = null;
    return save();
  }

  /// After Log Out or Delete Account: the next account starts fresh.
  void forget() {
    _timer?.cancel();
    _savedJson = null;
    _savedPhotoHash = null;
  }

  @visibleForTesting
  void resetForTesting() {
    forget();
    if (_started) AppStore.instance.removeListener(_onChange);
    _lifecycle?.dispose();
    _lifecycle = null;
    _started = false;
    _bringingIn = false;
    _saving = null;
  }
}

/// The profile photo at most 512 px a side, as JPEG, for the account.
Uint8List _smallPhoto(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;
  final small = image.width > 512 || image.height > 512
      ? (image.width >= image.height
          ? img.copyResize(image, width: 512, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: 512, interpolation: img.Interpolation.average))
      : image;
  return Uint8List.fromList(img.encodeJpg(small, quality: 82));
}
