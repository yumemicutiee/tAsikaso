import 'package:flutter/foundation.dart';

import 'local_storage.dart';

LocalStorage createStorage() => MemoryStorage();

/// Keeps everything in memory. Used on web and in tests.
class MemoryStorage implements LocalStorage {
  String? _json;
  final Map<String, Uint8List> _files = {};

  @override
  bool get isPersistent => false;

  @override
  Future<String?> readJson() async => _json;

  @override
  Future<void> writeJson(String json) async {
    _json = json;
  }

  @override
  Future<Uint8List?> readBytes(String key) async => _files[key];

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    _files[key] = bytes;
  }

  @override
  Future<void> delete(String key) async {
    _files.remove(key);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    _files.removeWhere((key, _) => key.startsWith(prefix));
  }
}
