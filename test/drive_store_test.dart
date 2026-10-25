import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_app/services/drive_store.dart';

/// Google Drive's upload endpoints, as far as GoogleDriveStore uses them:
/// one-request multipart uploads, and resumable sessions that take 1 MB
/// pieces (308 until the last, which returns the file).
class FakeDriveUploads {
  final requests = <http.Request>[];
  final received = BytesBuilder();
  var name = '';

  late final client = MockClient((req) async {
    requests.add(req);
    final type = req.url.queryParameters['uploadType'];
    if (type == 'multipart') {
      return _file(req.url.pathSegments.last == 'files' ? 'new' : 'old', 3);
    }
    if (type == 'resumable') {
      // Starts a session; the pieces go to its own address.
      if (req.body.isNotEmpty) {
        name = (jsonDecode(req.body) as Map)['name'] as String? ?? name;
      }
      return http.Response('', 200,
          headers: {'location': 'https://upload.test/session'});
    }
    if (req.url.host == 'upload.test') {
      received.add(req.bodyBytes);
      final range = RegExp(r'bytes (\d+)-(\d+)/(\S+)')
          .firstMatch(req.headers['content-range']!)!;
      final end = int.parse(range[2]!);
      final total = int.tryParse(range[3]!);
      if (total == null || end + 1 < total) {
        return http.Response('', 308, headers: {'range': 'bytes=0-$end'});
      }
      return _file('big', total);
    }
    return http.Response('unexpected ${req.method} ${req.url}', 400);
  });

  http.Response _file(String id, int size) => http.Response(
        jsonEncode({'id': id, 'name': name.isEmpty ? id : name, 'size': '$size'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

void main() {
  test('a small file goes up in one request', () async {
    final fake = FakeDriveUploads();
    final store = GoogleDriveStore(fake.client);
    final saved = await store.upload('data.json', Uint8List.fromList([1, 2, 3]));
    expect(saved.id, 'new');
    expect(fake.requests, hasLength(1));
    expect(fake.requests.single.url.queryParameters['uploadType'], 'multipart');
  });

  test('a file over 5 MB goes up in resumable 1 MB pieces, new or replaced',
      () async {
    final big = Uint8List.fromList(List.generate(
        GoogleDriveStore.resumableFrom + 300 * 1024, (i) => i % 251));
    for (final replaceId in [null, 'old']) {
      final fake = FakeDriveUploads();
      final store = GoogleDriveStore(fake.client);
      final saved =
          await store.upload('notes__abc.pdf', big, replaceId: replaceId);

      final start = fake.requests.first;
      expect(start.url.queryParameters['uploadType'], 'resumable');
      expect(start.method, replaceId == null ? 'POST' : 'PATCH');
      expect(start.headers['x-upload-content-length'], '${big.length}');
      final pieces = fake.requests.skip(1).toList();
      expect(pieces, hasLength(6)); // five whole megabytes and the rest
      expect(pieces.every((r) => r.method == 'PUT'), isTrue);
      expect(fake.received.takeBytes(), big);
      expect(saved.id, 'big');
      expect(saved.size, big.length);
      if (replaceId == null) expect(saved.name, 'notes__abc.pdf');
    }
  });
}
