import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb.dart';

import 'local_storage.dart';

/// IndexedDB (the browser's database): one object store of key → bytes,
/// with the JSON document under its own key. Takes the database factory so
/// tests can use an in-memory one.
class IdbStorage implements LocalStorage {
  IdbStorage(this._factory);

  final IdbFactory _factory;

  static const _dbName = 'tasikaso';
  static const _storeName = 'files';
  static const _jsonKey = 'data.json';

  Database? _db;

  Future<Database> _open() async {
    return _db ??= await _factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (e) => e.database.createObjectStore(_storeName),
    );
  }

  Future<T> _run<T>(String mode, Future<T> Function(ObjectStore) action) async {
    final db = await _open();
    final txn = db.transaction(_storeName, mode);
    final result = await action(txn.objectStore(_storeName));
    await txn.completed;
    return result;
  }

  @override
  bool get isPersistent => true;

  @override
  Future<String?> readJson() async {
    final bytes = await readBytes(_jsonKey);
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<void> writeJson(String json) =>
      writeBytes(_jsonKey, Uint8List.fromList(utf8.encode(json)));

  @override
  Future<Uint8List?> readBytes(String key) => _run(idbModeReadOnly, (s) async {
        final value = await s.getObject(key);
        if (value == null) return null;
        return value is Uint8List
            ? value
            : Uint8List.fromList((value as List).cast<int>());
      });

  @override
  Future<void> writeBytes(String key, Uint8List bytes) =>
      _run(idbModeReadWrite, (s) => s.put(bytes, key));

  @override
  Future<void> delete(String key) =>
      _run(idbModeReadWrite, (s) => s.delete(key));

  @override
  Future<void> deletePrefix(String prefix) =>
      _run(idbModeReadWrite, (s) async {
        for (final key in await s.getAllKeys()) {
          if (key is String && key.startsWith(prefix)) await s.delete(key);
        }
      });

  @override
  Future<List<String>> list(String prefix) => _run(idbModeReadOnly, (s) async {
        return [
          for (final key in await s.getAllKeys())
            if (key is String && key != _jsonKey && key.startsWith(prefix)) key,
        ];
      });
}
