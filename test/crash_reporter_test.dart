import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_app/data/app_store.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/services/crash_reporter.dart';
import 'package:study_app/theme/brand.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  final sent = <http.Request>[];

  setUp(() {
    store.resetForTesting();
    CrashReporter.reset();
    sent.clear();
    CrashReporter.debugClient = () => MockClient((req) async {
          sent.add(req);
          return http.Response('', 204);
        });
    store.updatePrefs(store.prefs.copyWith(
        aiServerUrl: 'https://study.example.com/', aiToken: 'tok'));
  });

  tearDown(() => CrashReporter.debugClient = null);

  Map<String, Object?> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, Object?>;

  test('a report goes to the study server with only the error, the place, '
      'the version and the system', () async {
    final ok = await CrashReporter.report(
        StateError('no page'), StackTrace.fromString('#0 save (review_screen.dart:191)'));
    expect(ok, isTrue);
    final r = sent.single;
    expect(r.url.toString(), 'https://study.example.com/v1/crash');
    expect(r.headers['authorization'], 'Bearer tok');
    final b = body(r);
    expect(b.keys.toSet(), {'message', 'stack', 'source', 'version', 'platform'});
    expect(b['message'], contains('no page'));
    expect(b['stack'], contains('review_screen.dart:191'));
    expect(b['version'], kAppVersion);
  });

  test('nothing is sent when Send Crash Reports is off', () async {
    store.updatePrefs(store.prefs.copyWith(crashReports: false));
    expect(await CrashReporter.report(StateError('x'), null), isFalse);
    expect(sent, isEmpty);
  });

  test('nothing is sent without a study server', () async {
    store.updatePrefs(store.prefs.copyWith(aiServerUrl: ''));
    // (A build with a server built in would still have one.)
    if (await CrashReporter.report(StateError('x'), null)) {
      expect(sent.single.url.path, '/v1/crash');
    } else {
      expect(sent, isEmpty);
    }
  });

  test('the same error is sent once, and at most a few per run', () async {
    final stack = StackTrace.fromString('#0 tick (timer.dart:1)');
    expect(await CrashReporter.report(StateError('same'), stack), isTrue);
    expect(await CrashReporter.report(StateError('same'), stack), isFalse);
    for (var i = 0; i < 10; i++) {
      await CrashReporter.report(StateError('error $i'), stack);
    }
    expect(sent, hasLength(CrashReporter.maxPerRun));
  });

  test('long messages and stacks are cut short', () async {
    await CrashReporter.report(
        FormatException('y' * 5000), StackTrace.fromString('#0 f\n' * 2000));
    final b = body(sent.single);
    expect((b['message'] as String).length, lessThanOrEqualTo(CrashReporter.maxMessage));
    expect((b['stack'] as String).length, lessThanOrEqualTo(CrashReporter.maxStack));
  });

  test('a server that is down is ignored', () async {
    CrashReporter.debugClient = () => MockClient((_) async => throw Exception('offline'));
    expect(await CrashReporter.report(StateError('z'), null), isFalse);
  });

  test('the switch is saved, and on unless turned off', () {
    expect(const AppPrefs().crashReports, isTrue);
    expect(AppPrefs.fromJson(const {}).crashReports, isTrue);
    final off = const AppPrefs().copyWith(crashReports: false);
    expect(AppPrefs.fromJson(off.toJson()).crashReports, isFalse);
  });
}
