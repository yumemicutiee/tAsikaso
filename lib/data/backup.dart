import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// A backup is one ZIP file: `data.json` (everything small) plus every PDF,
/// photo and thumbnail under its usual key, and a `manifest.json` saying
/// what made it.
typedef BackupContents = ({String json, Map<String, Uint8List> files});

const backupFormat = 1;

/// e.g. `tAsikaso-backup-2026-10-20.zip`
String backupFileName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'tAsikaso-backup-${at.year}-${two(at.month)}-${two(at.day)}.zip';
}

/// Only these are backed up and restored; anything else in the ZIP is
/// ignored, so a tampered file can't write outside the app's data.
bool _isDataKey(String name) =>
    name.startsWith('notes/') ||
    name.startsWith('sets/') ||
    name.startsWith('profile/');

Uint8List packBackup({
  required String json,
  required Map<String, Uint8List> files,
  required DateTime createdAt,
  required String appVersion,
}) {
  final archive = Archive()
    ..add(ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(jsonEncode({
        'app': 'tAsikaso',
        'format': backupFormat,
        'appVersion': appVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
      })),
    ))
    ..add(ArchiveFile.bytes('data.json', utf8.encode(json)));
  for (final entry in files.entries) {
    if (_isDataKey(entry.key)) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Reads a backup made by [packBackup]. Throws a [FormatException] if the
/// file isn't one.
BackupContents unpackBackup(Uint8List zip) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip, verify: true);
  } catch (e) {
    throw const FormatException('This is not a backup file.');
  }
  String? json;
  final files = <String, Uint8List>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    final bytes = file.readBytes();
    if (bytes == null) continue;
    if (file.name == 'data.json') {
      json = utf8.decode(bytes);
    } else if (_isDataKey(file.name) && !file.name.contains('..')) {
      files[file.name] = bytes;
    }
  }
  if (json == null) {
    throw const FormatException('This backup has no data in it.');
  }
  return (json: json, files: files);
}
