import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// A file in the app's private folder on Google Drive.
@immutable
class RemoteFile {
  const RemoteFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.size = 0,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int size;
}

/// Who is signed in, as Drive reports it.
@immutable
class AccountInfo {
  const AccountInfo({required this.email, this.name, this.photoUrl});

  final String email;
  final String? name;

  /// Link to the account's photo, if it has one.
  final String? photoUrl;
}

/// The app's private folder on Google Drive (`appDataFolder`: the user
/// never sees it in Drive, and other apps can't read it), or a stand-in
/// for tests.
abstract class DriveStore {
  Future<List<RemoteFile>> list();
  Future<Uint8List> download(String id);

  /// Uploads [bytes] as a new file called [name], or replaces the file
  /// [replaceId] when given.
  Future<RemoteFile> upload(String name, Uint8List bytes, {String? replaceId});

  Future<void> delete(String id);

  /// The signed-in account, if Drive will say.
  Future<AccountInfo?> accountInfo();

  void close() {}
}

/// Google Drive through the Drive API, with a client that carries the
/// user's access token (see `drive_sync.dart`).
class GoogleDriveStore implements DriveStore {
  GoogleDriveStore(this._client) : _api = drive.DriveApi(_client);

  final http.Client _client;
  final drive.DriveApi _api;

  static const _folder = 'appDataFolder';
  static const _fields = 'id,name,modifiedTime,size';

  /// Google documents one-request (multipart) uploads for files of up to
  /// 5 MB. Bigger ones, such as a long Scan PDF, go up in 1 MB pieces, and
  /// a piece the connection drops is sent again on its own.
  static const resumableFrom = 5 * 1024 * 1024;

  @override
  Future<List<RemoteFile>> list() async {
    final out = <RemoteFile>[];
    String? page;
    do {
      final result = await _api.files.list(
        spaces: _folder,
        pageSize: 1000,
        pageToken: page,
        $fields: 'nextPageToken,files($_fields)',
      );
      for (final f in result.files ?? const <drive.File>[]) {
        final file = _remote(f);
        if (file != null) out.add(file);
      }
      page = result.nextPageToken;
    } while (page != null);
    return out;
  }

  @override
  Future<Uint8List> download(String id) async {
    final media = await _api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes,
      {String? replaceId}) async {
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final options = bytes.length > resumableFrom
        ? drive.ResumableUploadOptions()
        : drive.UploadOptions.defaultOptions;
    final drive.File saved;
    if (replaceId != null) {
      saved = await _api.files.update(
        drive.File(),
        replaceId,
        uploadMedia: media,
        uploadOptions: options,
        $fields: _fields,
      );
    } else {
      saved = await _api.files.create(
        drive.File(name: name, parents: const [_folder]),
        uploadMedia: media,
        uploadOptions: options,
        $fields: _fields,
      );
    }
    return _remote(saved) ?? RemoteFile(id: saved.id ?? '', name: name);
  }

  @override
  Future<void> delete(String id) => _api.files.delete(id);

  @override
  Future<AccountInfo?> accountInfo() async {
    final about = await _api.about.get($fields: 'user');
    final user = about.user;
    if (user == null) return null;
    return AccountInfo(
      email: user.emailAddress ?? '',
      name: user.displayName,
      photoUrl: user.photoLink,
    );
  }

  @override
  void close() => _client.close();

  static RemoteFile? _remote(drive.File f) {
    final id = f.id;
    final name = f.name;
    if (id == null || name == null) return null;
    return RemoteFile(
      id: id,
      name: name,
      modifiedTime: f.modifiedTime,
      size: int.tryParse(f.size ?? '') ?? 0,
    );
  }
}

/// Google Drive in memory, for tests.
class MemoryDriveStore implements DriveStore {
  final Map<String, (String, Uint8List, DateTime)> _files = {};
  int _next = 1;
  int uploads = 0;
  int deletes = 0;
  String? email = 'student@example.com';
  String? name;
  String? photoUrl;

  /// The current time, so tests can control `modifiedTime`.
  DateTime Function() now = DateTime.now;

  Map<String, Uint8List> get byName =>
      {for (final f in _files.values) f.$1: f.$2};

  @override
  Future<List<RemoteFile>> list() async => [
        for (final e in _files.entries)
          RemoteFile(
            id: e.key,
            name: e.value.$1,
            modifiedTime: e.value.$3,
            size: e.value.$2.length,
          ),
      ];

  @override
  Future<Uint8List> download(String id) async {
    final f = _files[id];
    if (f == null) throw StateError('No file $id');
    return f.$2;
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes,
      {String? replaceId}) async {
    uploads++;
    final id = replaceId ?? 'f${_next++}';
    final at = now();
    _files[id] = (name, bytes, at);
    return RemoteFile(id: id, name: name, modifiedTime: at, size: bytes.length);
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    _files.remove(id);
  }

  @override
  Future<AccountInfo?> accountInfo() async {
    final e = email;
    if (e == null) return null;
    return AccountInfo(email: e, name: name, photoUrl: photoUrl);
  }

  @override
  void close() {}
}
