import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/plans.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/analysis_screen.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/plans_screen.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/theme/app_colors.dart';

List<Flashcard> cards(int n, [String prefix = 'c']) => [
      for (var i = 0; i < n; i++)
        Flashcard(id: '$prefix$i', front: 'Front $prefix$i', back: 'Back $i'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;

  setUp(() {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    ScanService.debugRead = null;
    StudyAi.debugClient = null;
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('Plans', () {
    test('test purchases are on while payments are not connected', () {
      expect(kTestPurchases, isTrue);
    });

    test('each plan runs for its own length, and switching starts afresh', () {
      final start = DateTime(2026, 10, 21, 9);
      withClock(Clock.fixed(start), () {
        expect(store.isPlus, isFalse);
        expect(store.plan, isNull);

        store.startPlan(PlusPlan.semester);
        expect(store.isPlus, isTrue);
        expect(store.plan, PlusPlan.semester);
        expect(store.subscription!.endsAt, DateTime(2027, 4, 21, 9));
        expect(store.subscription!.test, isTrue);

        store.startPlan(PlusPlan.yearly);
        expect(store.plan, PlusPlan.yearly);
        expect(store.subscription!.endsAt, DateTime(2027, 10, 21, 9));

        store.startPlan(PlusPlan.monthly);
        expect(store.subscription!.endsAt, DateTime(2026, 11, 21, 9));

        store.endPlan();
        expect(store.isPlus, isFalse);
        expect(store.subscription, isNull);
      });
    });

    test('a plan ends by itself, and the user is told once', () {
      withClock(Clock.fixed(DateTime(2026, 10, 21)), () {
        store.startPlan(PlusPlan.monthly);
      });
      withClock(Clock.fixed(DateTime(2026, 11, 20, 23)), () {
        expect(store.isPlus, isTrue); // the last day still counts
      });
      withClock(Clock.fixed(DateTime(2026, 11, 22)), () {
        expect(store.isPlus, isFalse);
        expect(store.checkPlanEnded(), isTrue);
        expect(store.problem.value!.title, 'Your tAsikaso+ Plan Ended');
        expect(store.subscription, isNull);
        expect(store.checkPlanEnded(), isFalse);
      });
    });

    test('the plan is saved, and older "plus" switches still load', () {
      store.startPlan(PlusPlan.semester);
      final back = AppPrefs.fromJson(store.prefs.toJson());
      expect(back.subscription!.plan, PlusPlan.semester);
      expect(back.subscription!.endsAt, store.subscription!.endsAt);
      expect(back.subscription!.test, isTrue);

      final legacy = AppPrefs.fromJson(const {'plus': true});
      expect(legacy.subscription!.plan, PlusPlan.yearly);
      expect(legacy.subscription!.endsAt, isNull); // no end: stays on
      expect(AppPrefs.fromJson(const {}).subscription, isNull);
      expect(AppPrefs.fromJson(const {
        'plan': {'name': 'nope', 'since': '2026-01-01'},
      }).subscription, isNull);
    });

    test('Delete All Data and restoring a backup keep the plan', () async {
      store.startPlan(PlusPlan.yearly);
      final zip = await store.createBackup();
      await store.eraseEverything();
      expect(store.plan, PlusPlan.yearly);

      // A backup made on the free plan doesn't end the plan...
      store.endPlan();
      final freeZip = await store.createBackup();
      store.startPlan(PlusPlan.semester);
      await store.restoreBackup(freeZip);
      expect(store.plan, PlusPlan.semester);

      // ...and one made with a plan doesn't start one.
      store.endPlan();
      await store.restoreBackup(zip);
      expect(store.isPlus, isFalse);
    });
  });

  group('Suggested cards: 20 a month on the free plan', () {
    test('cards past the allowance are left out; next month starts over', () {
      withClock(Clock.fixed(DateTime(2026, 10, 21)), () {
        expect(store.suggestedCardsLeft, kFreeSuggestedCardsPerMonth);
        final first = store.takeSuggestedCards(cards(15));
        expect(first.kept.length, 15);
        expect(first.dropped, 0);
        expect(store.suggestedCardsLeft, 5);

        final second = store.takeSuggestedCards(cards(8, 'd'));
        expect(second.kept.length, 5);
        expect(second.dropped, 3);
        expect(store.suggestedCardsLeft, 0);
        expect(store.takeSuggestedCards(cards(1, 'e')).kept, isEmpty);
      });
      withClock(Clock.fixed(DateTime(2026, 11, 1)), () {
        expect(store.suggestedCardsLeft, kFreeSuggestedCardsPerMonth);
      });
    });

    test('tAsikaso+ has no limit', () {
      store.takeSuggestedCards(cards(20));
      expect(store.suggestedCardsLeft, 0);
      store.startPlan(PlusPlan.monthly);
      expect(store.suggestedCardsLeft, isNull);
      expect(store.takeSuggestedCards(cards(40, 'p')).kept.length, 40);
    });

    test('the count survives Delete All Data and old backups', () async {
      final zip = await store.createBackup();
      store.takeSuggestedCards(cards(20));
      await store.eraseEverything();
      expect(store.suggestedCardsLeft, 0);
      await store.restoreBackup(zip);
      expect(store.suggestedCardsLeft, 0);
    });

    Future<void> saveScanAsFlashcards(WidgetTester tester) async {
      usePhoneSize(tester);
      ScanService.debugRead = (jpegs) async => [
            for (final _ in jpegs)
              const RecognizedPage(lines: [
                RecognizedLine(
                    text: 'Osmosis: water across a membrane',
                    left: 0, top: 0, right: 10, bottom: 10),
                RecognizedLine(
                    text: 'Diffusion - particles spread out',
                    left: 0, top: 20, right: 10, bottom: 30),
              ]),
          ];
      final image = img.Image(width: 40, height: 30);
      final page = CapturedPage(
          id: 1, bytes: img.encodePng(image), width: 40, height: 30);
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(pages: [page])));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flashcards'));
      await tester.pump();
      await tester.tap(find.text('Make Flashcards'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 150 && store.sets.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('used up: the study server is not asked for cards at all',
        (tester) async {
      final requests = <http.Request>[];
      store.updatePrefs(store.prefs.copyWith(aiServerUrl: 'https://s.test'));
      StudyAi.debugClient = () => MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 500);
          });
      store.takeSuggestedCards(cards(20));

      await saveScanAsFlashcards(tester);
      expect(requests, isEmpty);
      final deck = store.sets.single;
      expect(deck.cards, isEmpty);
      expect(deck.suggestions, isEmpty);
      expect(find.textContaining('suggested cards are used up'), findsOneWidget);
    });

    testWidgets('some left: only that many are asked for and kept',
        (tester) async {
      final asked = <int>[];
      store.updatePrefs(store.prefs.copyWith(aiServerUrl: 'https://s.test'));
      StudyAi.debugClient = () => MockClient((req) async {
            asked.add((jsonDecode(req.body) as Map)['maxCards'] as int);
            return http.Response(
                jsonEncode({
                  'kit': {
                    'title': 'T',
                    'summary': '',
                    'notes': '',
                    'concepts': <Object>[],
                    'cards': [
                      for (var i = 0; i < 5; i++)
                        {'front': 'Q$i', 'back': 'A$i'},
                    ],
                    'quiz': <Object>[],
                  },
                }),
                200,
                headers: {'content-type': 'application/json'});
          });
      store.takeSuggestedCards(cards(17));

      await saveScanAsFlashcards(tester);
      expect(asked, [3]);
      expect(store.sets.single.cards.length, 3); // the server sent 5
      expect(store.suggestedCardsLeft, 0);
    });
  });

  group('Free plan vs tAsikaso+ on screen', () {
    testWidgets('a tester starts, switches and ends a plan', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(const MaterialApp(home: PlansScreen()));
      final list = find.byType(Scrollable).first;
      Future<void> show(String text) async {
        await tester.scrollUntilVisible(find.text(text), 200, scrollable: list);
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('Test mode'), findsWidgets);
      await show('Start Yearly Plan');

      await show('Semester');
      await tester.tap(find.text('Semester'));
      await tester.pump();
      await show('Start Semester Plan');
      await tester.tap(find.text('Start Semester Plan'));
      await tester.pumpAndSettle();
      expect(store.plan, PlusPlan.semester);
      expect(find.text('This Is Your Plan'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);

      await show('Yearly');
      await tester.tap(find.text('Yearly'));
      await tester.pump();
      await show('Switch to Yearly');
      await tester.tap(find.text('Switch to Yearly'));
      await tester.pumpAndSettle();
      expect(store.plan, PlusPlan.yearly);
      expect(find.textContaining('Switched to tAsikaso+ Yearly'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // the toast goes away
      await tester.pumpAndSettle();

      await show('Go Back to Free Plan');
      await tester.tap(find.text('Go Back to Free Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Go Back to Free?'), findsOneWidget);
      await tester.tap(find.text('Go to Free'));
      await tester.pumpAndSettle();
      expect(store.isPlus, isFalse);
      expect(find.text('Go Back to Free Plan'), findsNothing);

      // The header says which plan is on.
      store.startPlan(PlusPlan.semester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text("You're on tAsikaso+ Semester"), -300, scrollable: list);
      expect(find.text("You're on tAsikaso+ Semester"), findsOneWidget);
      expect(find.textContaining('test plan, no charge'), findsOneWidget);
    });

    testWidgets('Analysis: heatmap and earlier weeks lock on the free plan',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(const MaterialApp(home: AnalysisScreen()));
      await tester.tap(find.byTooltip('Previous Week (tAsikaso+)'));
      await tester.pumpAndSettle();
      expect(find.text('Full Pomodoro Analysis'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(find.text('This Week'), findsOneWidget); // didn't move

      store.startPlan(PlusPlan.yearly);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous Week'), findsOneWidget);
      store.endPlan();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Heatmap'), 300,
          scrollable: find.byType(Scrollable).last);
      expect(find.textContaining('Part of tAsikaso+'), findsOneWidget);
      store.startPlan(PlusPlan.yearly);
      await tester.pumpAndSettle();
      expect(find.textContaining('Part of tAsikaso+'), findsNothing);
    });

    testWidgets('Timeline: free shows this week, Plus shows everything',
        (tester) async {
      usePhoneSize(tester);
      store.recordFocusSession(25,
          endedAt: DateTime.now().subtract(const Duration(days: 30)));
      store.recordFocusSession(25);
      await tester.pumpWidget(const MaterialApp(home: AnalysisScreen()));
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Earlier days are part of your full timeline.'),
          findsOneWidget);

      store.startPlan(PlusPlan.monthly);
      await tester.pumpAndSettle();
      expect(find.text('Earlier days are part of your full timeline.'),
          findsNothing);
      expect(find.textContaining('Pomodoro · 25m'), findsNWidgets(2));
    });

    testWidgets('Smart review: free studies all cards, Plus sees what is due',
        (tester) async {
      usePhoneSize(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final deck = await store.addSet(
        title: 'Bonds',
        folderId: store.folders.first.id,
        cards: [
          const Flashcard(id: 'c1', front: 'Ionic', back: 'Transfer'),
          const Flashcard(id: 'c2', front: 'Covalent', back: 'Share')
              .scheduled(interval: 3, due: tomorrow),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: SetScreen(setId: deck.id)));
      await tester.pump();
      expect(find.text('Study 2 Cards'), findsOneWidget);
      expect(find.text('Review 1 Card Due'), findsNothing);
      await tester.tap(find.text('Smart review: just the cards due today'));
      await tester.pumpAndSettle();
      expect(find.text('Smart Review'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      store.startPlan(PlusPlan.semester);
      await tester.pump();
      expect(find.text('Review 1 Card Due'), findsOneWidget);
    });

    testWidgets('Backup: making a file is Plus, restoring stays free',
        (tester) async {
      usePhoneSize(tester);
      final originalShare = BackupScreen.share;
      var shared = false;
      BackupScreen.share = (bytes, name) async => shared = true;
      addTearDown(() => BackupScreen.share = originalShare);

      await tester.pumpWidget(const MaterialApp(home: BackupScreen()));
      expect(find.textContaining('part of tAsikaso+'), findsWidgets);
      await tester.tap(find.text('Back Up Now  ·  tAsikaso+'));
      await tester.pumpAndSettle();
      expect(find.text('Backup & Sync'), findsWidgets); // the prompt's title
      expect(find.text('See Plans'), findsOneWidget);
      expect(shared, isFalse);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(find.text('Restore from Backup'), findsOneWidget);

      store.startPlan(PlusPlan.yearly);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back Up Now'));
      await tester.pumpAndSettle();
      expect(shared, isTrue);
    });
  });

  group('Google Drive sync and the plan', () {
    late MemoryDriveStore drive;
    final sync = DriveSync.instance;

    setUp(() async {
      drive = MemoryDriveStore();
      DriveSync.debugStore = drive;
      await sync.resetForTesting();
    });

    tearDown(() async {
      await sync.resetForTesting();
      DriveSync.debugStore = null;
    });

    test('free accounts can sign in and restore, but not upload', () async {
      // Data from a time with a plan is on Drive.
      store.startPlan(PlusPlan.yearly);
      store.addFolder('From Before', 0xFFA9CFF5);
      await sync.debugSignIn();
      expect(await sync.syncNow(), isNull);
      final uploads = drive.uploads;

      store.endPlan();
      store.addFolder('New', 0xFFA9CFF5);
      expect(await sync.syncNow(), DriveSync.needsPlusMessage);
      expect(drive.uploads, uploads);

      await store.eraseEverything();
      await sync.debugSignIn();
      expect(await sync.restoreFromDrive(), isNull);
      expect(store.folders.any((f) => f.name == 'From Before'), isTrue);
    });

    testWidgets('signed in on the free plan: sync is paused, plans offered',
        (tester) async {
      usePhoneSize(tester);
      await sync.debugSignIn();
      await tester.pumpWidget(const MaterialApp(home: BackupScreen()));
      await tester.pump();
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('Sync is paused: it comes with tAsikaso+'), findsOneWidget);
      expect(find.text('See Plans to Sync'), findsOneWidget);
      expect(find.text('Sync Now'), findsNothing);

      store.startPlan(PlusPlan.monthly);
      await tester.pump();
      expect(find.text('Sync Now'), findsOneWidget);
      expect(find.text('See Plans to Sync'), findsNothing);
      // Starting the plan queued an automatic sync of the change.
      expect(sync.hasUnsyncedChanges, isTrue);
      await sync.resetForTesting(); // cancels that timer
    });

    test('the photo-less upload list carries the profile photo too', () async {
      store.startPlan(PlusPlan.yearly);
      await store.setProfilePhoto(Uint8List.fromList([1, 2, 3]));
      await sync.debugSignIn();
      await sync.syncNow();
      expect(drive.byName.keys, contains('profile__photo.jpg'));
    });
  });
}
