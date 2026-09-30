import 'package:flutter/foundation.dart';

import 'local_storage_memory.dart'
    if (dart.library.io) 'local_storage_io.dart' as platform;

/// Where the app keeps its data: one JSON document for everything small
/// (folders, notes, tasks, settings, stats) plus binary files (PDFs, photos,
/// thumbnails) addressed by a key such as `notes/abc.pdf`.
abstract class LocalStorage {
  Future<String?> readJson();
  Future<void> writeJson(String json);

  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List bytes);
  Future<void> delete(String key);

  /// Deletes every file whose key starts with [prefix] (e.g. `sets/abc/`).
  Future<void> deletePrefix(String prefix);

  /// True when data survives an app restart.
  bool get isPersistent;
}

/// Files in the app's documents folder on Android/iOS/desktop. On web, data
/// is kept in memory for now.
LocalStorage createDeviceStorage() => platform.createStorage();
