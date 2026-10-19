import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_storage.dart';

LocalStorage createStorage() => FileStorage();

/// Stores data under `<app documents>/study_app/`.
class FileStorage implements LocalStorage {
  Directory? _root;

  Future<Directory> _dir() async {
    final existing = _root;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/study_app');
    await dir.create(recursive: true);
    return _root = dir;
  }

  Future<File> _file(String key) async {
    final dir = await _dir();
    return File('${dir.path}/$key');
  }

  @override
  bool get isPersistent => true;

  @override
  Future<String?> readJson() async {
    final file = await _file('data.json');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeJson(String json) async {
    // Write to a temp file first so a crash mid-write can't corrupt the data.
    final file = await _file('data.json');
    final tmp = await _file('data.json.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final file = await _file(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final target = await _file(prefix);
    final dir = Directory(target.path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    } else if (await target.exists()) {
      await target.delete();
    }
  }
}
