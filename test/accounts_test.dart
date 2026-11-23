import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/plans.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/settings_screen.dart';
import 'package:study_app/services/accounts.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/services/plan_sync.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';

/// Supabase Auth, as the app sees it.
class FakeAccounts implements AccountsBackend {
  @override
  String? userId;
  @override
  bool isAnonymous = true;
  String current = 'account-token-1';
  int anonymousSignIns = 0;
  int refreshes = 0;
  int signOuts = 0;
  bool offline = false;
  final googleTokens = <String>[];

  @override
  Future<String?> accessToken() async => userId == null ? null : current;

  @override
  Future<void> signInAnonymously() async {
    if (offline) throw Exception('no internet');
    anonymousSignIns++;
    userId = 'anon-user';
    isAnonymous = true;
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    current = 'account-token-${refreshes + 1}';
  }

  @override
  Future<void> signInWithGoogle({required String idToken, String? accessToken}) async {
    googleTokens.add(idToken);
    isAnonymous = false;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    userId = null;
  }
}

Map<String, Object?> me({
  String tier = 'anonymous',
  bool anonymous = true,
  Map<String, Object?>? plan,
  int read = 3,
}) =>
    {
      'user': {'id': 'anon-user', 'anonymous': anonymous},
      'tier': tier,
      'plan': plan ?? {'name': null, 'startedAt': null, 'endsAt': null, 'test': false},
      'day': '2026-11-24',
      'resetsInSeconds': 3600,
      'today': {
        'read': {'used': read, 'limit': 20},
        'study': {'used': 1, 'limit': 10},
        'check': {'used': 0, 'limit': null},
      },
    };

const semester = {
  'name': 'semester',
  'startedAt': '2026-11-24T04:00:00.000Z',
  'endsAt': '2027-05-24T04:00:00.000Z',
  'test': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  late FakeAccounts accounts;
  final requests = <http.Request>[];

  setUp(() async {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    await DriveSync.instance.resetForTesting();
    DriveSync.debugStore = null;
    requests.clear();
    accounts = FakeAccounts();
    Accounts.useForTesting(accounts);
    StudyAi.debugBuiltInUrl = 'https://study.example';
  });

  tearDown(() {
    Accounts.useForTesting(null);
    StudyAi.debugBuiltInUrl = null;
    StudyAi.debugClient = null;
    DriveSync.debugStore = null;
  });

  /// The study server answers with [reply] (status and body) per request.
  void server((int, Object?) Function(http.Request req) reply) {
    StudyAi.debugClient = () => MockClient((req) async {
          requests.add(req);
          final (status, body) = reply(req);
          return http.Response(body == null ? '' : jsonEncode(body), status,
              headers: {'content-type': 'application/json'});
        });
  }

  String? bearer(http.Request r) => r.headers['authorization'];

  group('Which token goes to the study server', () {
    test("the built-in server gets the account's token, made anonymously the "
        'first time', () async {
      server((_) => (200, me()));
      expect(StudyAi.usesAccounts, isTrue);
      final account = await StudyAi.fetchAccount();
      expect(accounts.anonymousSignIns, 1);
      expect(bearer(requests.single), 'Bearer account-token-1');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(), 'https://study.example/v1/me');
      expect(account!.tier, 'anonymous');
      expect(account.pagesRead.used, 3);
      expect(account.pagesRead.limit, 20);
      expect(account.answerChecks.limit, isNull, reason: 'null = no limit');

      await StudyAi.fetchAccount();
      expect(accounts.anonymousSignIns, 1, reason: 'the account is kept');
    });

    test('a page read sends the account token too', () async {
      server((_) => (200, {'page': {'text': 'Read'}}));
      expect(await StudyAi.readPage(Uint8List.fromList([0xFF, 0xD8, 1])), 'Read');
      expect(bearer(requests.single), 'Bearer account-token-1');
    });

    test('a server typed into Settings keeps its own token', () async {
      store.updatePrefs(store.prefs
          .copyWith(aiServerUrl: 'https://mine.test', aiToken: 'typed-token'));
      server((_) => (200, {'page': {'text': 'Read'}}));
      expect(StudyAi.usesAccounts, isFalse);
      await StudyAi.readPage(Uint8List.fromList([1]));
      expect(bearer(requests.single), 'Bearer typed-token');
      expect(accounts.anonymousSignIns, 0, reason: 'no account is made for it');
      expect(await StudyAi.fetchAccount(), isNull);
    });

    test("when Supabase can't be reached, the built-in token is used instead",
        () async {
      accounts.offline = true;
      server((_) => (200, {'page': {'text': 'Read'}}));
      await StudyAi.readPage(Uint8List.fromList([1]));
      expect(requests, hasLength(1), reason: 'the request still goes');
      expect(bearer(requests.single), isNot(contains('account-token')));
    });

    test('an expired sign-in is refreshed and the request sent once more',
        () async {
      var first = true;
      server((req) {
        if (first) {
          first = false;
          return (401, {'error': {'code': 'session_expired', 'message': 'Expired.'}});
        }
        return (200, {'page': {'text': 'Read'}});
      });
      expect(await StudyAi.readPage(Uint8List.fromList([1])), 'Read');
      expect(accounts.refreshes, 1);
      expect(requests.map(bearer),
          ['Bearer account-token-1', 'Bearer account-token-2']);
    });

    test("the server's daily-limit words reach the user", () async {
      server((_) => (429, {
            'error': {
              'code': 'daily_limit',
              'tier': 'anonymous',
              'message': "You've reached today's limit of 20 pages read by "
                  'Claude. Continue with Google in tAsikaso for more, or try '
                  'again tomorrow.',
            },
          }));
      await expectLater(
          StudyAi.readPage(Uint8List.fromList([1])),
          throwsA(isA<StudyAiException>()
              .having((e) => e.code, 'code', 'daily_limit')
              .having((e) => e.message, 'message', contains('Continue with Google'))));
    });

    test('with accounts off (no Supabase), nothing changes', () async {
      Accounts.useForTesting(null);
      expect(StudyAi.usesAccounts, isFalse);
      expect(await StudyAi.fetchAccount(), isNull);
    });
  });

  group('Plans on the account', () {
    test('switching a plan on goes through the server, which this phone then '
        'follows', () async {
      server((req) => (200, me(tier: 'plus', plan: semester)));
      expect(await PlanSync.change(PlusPlan.semester), isNull);
      final sent = requests.single;
      expect(sent.url.path, '/v1/plan/test');
      expect(jsonDecode(sent.body), {'plan': 'semester'});
      expect(store.isPlus, isTrue);
      expect(store.subscription!.plan, PlusPlan.semester);
      expect(store.subscription!.endsAt!.toUtc(), DateTime.utc(2027, 5, 24, 4));
    });

    test('back to Free through the server', () async {
      store.startPlan(PlusPlan.monthly);
      server((_) => (200, me(tier: 'anonymous')));
      expect(await PlanSync.change(null), isNull);
      expect(jsonDecode(requests.single.body), {'plan': null});
      expect(store.isPlus, isFalse);
    });

    test("when the server can't be reached, the plan doesn't change", () async {
      server((_) => (503, {
            'error': {
              'code': 'accounts_unavailable',
              'message': "The study server can't check your account right now. "
                  'Please try again in a minute.',
            },
          }));
      final problem = await PlanSync.change(PlusPlan.yearly);
      expect(problem, contains('try again in a minute'));
      expect(store.isPlus, isFalse);
    });

    test("the server's plan replaces this phone's at start-up", () async {
      server((_) => (200, me(tier: 'plus', anonymous: false, plan: semester)));
      final account = await PlanSync.refresh();
      expect(account!.isPlus, isTrue);
      expect(store.subscription!.plan, PlusPlan.semester);
      expect(store.subscription!.test, isTrue);
    });

    test('a test plan this phone had from before accounts is carried over',
        () async {
      store.startPlan(PlusPlan.yearly);
      var calls = 0;
      server((req) {
        calls++;
        return req.url.path == '/v1/me'
            ? (200, me())
            : (200, me(tier: 'plus', plan: {...semester, 'name': 'yearly'}));
      });
      await PlanSync.refresh();
      expect(calls, 2);
      expect(requests.last.url.path, '/v1/plan/test');
      expect(jsonDecode(requests.last.body), {'plan': 'yearly'});
      expect(store.subscription!.plan, PlusPlan.yearly);
    });

    test('without accounts, plans stay on this phone as before', () async {
      Accounts.useForTesting(null);
      server((_) => (500, null));
      expect(await PlanSync.change(PlusPlan.monthly), isNull);
      expect(requests, isEmpty);
      expect(store.subscription!.plan, PlusPlan.monthly);
    });
  });

  group('Google sign-in and the account', () {
    test("signing in with Google turns the anonymous account into Google's",
        () async {
      await Accounts.instance.token(); // the anonymous account
      expect(await Accounts.instance.signInWithGoogle(idToken: 'google-id-token'),
          isTrue);
      expect(accounts.googleTokens, ['google-id-token']);
      expect(Accounts.instance.isAnonymous, isFalse);
      // Signed in again on the next start: nothing to do.
      expect(await Accounts.instance.signInWithGoogle(idToken: 'again'), isTrue);
      expect(accounts.googleTokens, hasLength(1));
    });

    test('no ID token (e.g. the web) leaves the account as it is', () async {
      expect(await Accounts.instance.signInWithGoogle(idToken: null), isFalse);
      expect(accounts.googleTokens, isEmpty);
    });

    test('Log Out signs out of the account too', () async {
      DriveSync.debugStore = MemoryDriveStore();
      await DriveSync.instance.debugSignIn();
      await DriveSync.instance.signOut();
      expect(accounts.signOuts, 1);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets("Smart Study shows the account and today's use of Claude",
        (tester) async {
      server((_) => (200, me()));
      await openSettings(tester);
      await tester.scrollUntilVisible(
          find.textContaining('Today with Claude'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(
          find.textContaining('no account yet. Continue with Google'), findsOneWidget);
      expect(
          find.textContaining('3 of 20 pages read, 1 of 10 Smart Study requests, '
              '0 answer checks'),
          findsOneWidget);
    });

    testWidgets('Delete Account deletes it on the server and signs out',
        (tester) async {
      store.startPlan(PlusPlan.monthly);
      server((req) => req.method == 'DELETE' ? (204, null) : (200, me()));
      await Accounts.instance.token();
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete All Data'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Your Account?'), findsOneWidget);
      await tester.tap(find.text('Delete Account').last);
      await tester.pumpAndSettle();

      final delete = requests.where((r) => r.method == 'DELETE').single;
      expect(delete.url.path, '/v1/me');
      expect(accounts.signOuts, 1);
      expect(store.isPlus, isFalse);
      expect(find.text('Your account was deleted.'), findsOneWidget);
    });

    testWidgets('without accounts there is no Delete Account and no usage line',
        (tester) async {
      Accounts.useForTesting(null);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete All Data'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Delete Account'), findsNothing);
      expect(find.textContaining('Today with Claude'), findsNothing);
    });
  });
}
