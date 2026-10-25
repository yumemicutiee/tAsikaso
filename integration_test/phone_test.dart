// Runs on an Android phone or emulator, not in `flutter test`: the parts the
// unit tests can't reach (the phone's own storage and backups, text
// recognition, timer alerts, the camera, big gallery photos, Focus Mode
// keeping the screen on). On GitHub every push runs it on an emulator
// (.github/workflows/android-emulator.yml); on a phone plugged into this PC:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/phone_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/data/storage/local_storage.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/capture/capture_screen.dart';
import 'package:study_app/screens/capture/notes_pdf.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/services/notification_service.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/widgets/bottom_nav.dart';

late final IntegrationTestWidgetsFlutterBinding binding;
final store = AppStore.instance;

void main() {
  // First: it is what reports the results to `flutter drive` (a binding
  // started by testWidgets instead never does, and the run waits forever).
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves to the phone and still has it after a restart',
      (tester) async {
    await store.init(createDeviceStorage());
    expect(store.isPersistent, isTrue);

    final page = notesPhoto(['CELLS']);
    final folder = store.addFolder('Emulator Check', 0xFFA9CFF5);
    final pdf = await buildNotesPdf([page], title: 'Cells');
    final note = await store.addNote(
      title: 'Cells',
      folderId: folder.id,
      pdf: pdf,
      thumbnail: page,
      pageCount: 1,
    );
    await store.pendingSaves;

    // As if the app was closed and opened again: read back from the phone.
    await store.init(createDeviceStorage());
    expect(store.folders.map((f) => f.name), contains('Emulator Check'));
    final again = store.notes.singleWhere((n) => n.id == note.id);
    expect(await store.readPdf(again), pdf);

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    expect(find.text("Today's Focus"), findsOneWidget);
    await shot(tester, '1-dashboard');
    for (final (i, tab) in [AppTab.library, AppTab.study, AppTab.profile].indexed) {
      await tester.tap(find.byIcon(tab.icon));
      await tester.pumpAndSettle();
      await shot(tester, '${i + 2}-${tab.name}');
    }
  });

  testWidgets('reads the text on a photo and hides it in the Scan PDF',
      (tester) async {
    expect(ScanService.canReadText, isTrue);
    final photo = notesPhoto(['PHOTOSYNTHESIS', 'Plants make sugar from light']);
    final pages = await ScanService.readPages([photo]);
    final text = RecognizedPage.join(pages);
    debugPrint('Text recognition read: $text');
    expect(text.toLowerCase(), contains('photosynthesis'));
    expect(pages.single.lines, isNotEmpty);

    final pdf = await buildNotesPdf([photo], title: 'Photosynthesis', text: pages);
    expect(pdfPageCount(pdf), 1);
    // Text rendering mode 3 = invisible: selectable and searchable.
    expect(RegExp(r'\b3 Tr\b').hasMatch(inflated(pdf)), isTrue);
  });

  testWidgets('a timer alert shows when the time is up', (tester) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await NotificationService.init();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!;
    expect(await android.areNotificationsEnabled(), isTrue);
    debugPrint('Exact timing allowed: '
        '${await NotificationService.exactTimingAllowed()}');

    await NotificationService.scheduleTimerEnd(
      clock.now().add(const Duration(seconds: 5)),
      'Pomodoro done',
      'Time for a short break.',
      isBreak: false,
      vibrate: true,
    );
    expect((await plugin.pendingNotificationRequests()).map((r) => r.id),
        contains(1));

    var shown = <ActiveNotification>[];
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 90) &&
        !shown.any((n) => n.id == 1)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      shown = await android.getActiveNotifications();
    }
    debugPrint('Timer alert after ${waited.elapsed.inSeconds} s');
    expect(shown.where((n) => n.id == 1).map((n) => n.title),
        contains('Pomodoro done'));

    await NotificationService.setDailyReminder(19 * 60);
    expect((await plugin.pendingNotificationRequests()).map((r) => r.id),
        contains(2));
    await NotificationService.setDailyReminder(null);
    await NotificationService.cancelTimerEnd();
    await plugin.cancelAll();
  });

  testWidgets('a backup file brings everything back on the phone',
      (tester) async {
    final folder = store.addFolder('Backup Check', 0xFFF5C2C7);
    final pdf = await buildNotesPdf([notesPhoto(['BACKUP'])], title: 'Backup');
    final note = await store.addNote(
      title: 'Backup',
      folderId: folder.id,
      pdf: pdf,
      thumbnail: notesPhoto(['B']),
      pageCount: 1,
    );
    await store.pendingSaves;
    final zip = await store.createBackup();

    expect(await store.eraseEverything(), isTrue);
    expect(store.notes.any((n) => n.id == note.id), isFalse);
    await store.restoreBackup(zip);
    expect(await store.readPdf(store.notes.singleWhere((n) => n.id == note.id)),
        pdf);

    // Still there when the app opens again.
    await store.pendingSaves;
    await store.init(createDeviceStorage());
    expect(store.folders.map((f) => f.name), contains('Backup Check'));
    expect(await store.readPdf(store.notes.singleWhere((n) => n.id == note.id)),
        pdf);
  });

  testWidgets('the camera takes a photo that is saved as a Scan PDF',
      (tester) async {
    final known = {for (final n in store.notes) n.id};
    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CameraButton));
    // The capture screen's own messages for a camera that won't start.
    await waitFor(tester, find.byType(CameraPreview),
        failsOn: find.textContaining(RegExp("couldn't start|access is turned "
            "off|No camera was found|isn't available here")));
    await Future<void>.delayed(const Duration(seconds: 2)); // a few frames
    await shot(tester, '5-camera');

    await tester.tap(find.bySemanticsLabel('Take Photo'));
    await waitFor(tester, find.byType(ReviewScreen),
        timeout: const Duration(seconds: 60),
        failsOn: find.textContaining("Couldn't take the photo"));
    await tester.pumpAndSettle();
    await shot(tester, '6-review');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as PDF'));
    final waited = Stopwatch()..start();
    bool isNew(Note n) => !known.contains(n.id);
    while (waited.elapsed < const Duration(seconds: 90) &&
        !store.notes.any(isNew)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    final saved = store.notes.singleWhere(isNew);
    expect(saved.pageCount, 1);
    expect((await store.readPdf(saved))!.length, greaterThan(1000));
    await tester.pumpAndSettle();
    await shot(tester, '7-saved');
  });

  testWidgets('a big gallery photo is cropped to its page and saved',
      (tester) async {
    // Android's photo picker can't be driven from a test, so the photo is
    // handed over as the picker would: a 7.7-megapixel page on a desk.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gallery_page.jpg');
    await file.writeAsBytes(pageOnDesk());
    final pick = CaptureScreen.pickImages;
    CaptureScreen.pickImages = () async => [XFile(file.path)];
    addTearDown(() => CaptureScreen.pickImages = pick);
    final known = {for (final n in store.notes) n.id};

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CameraButton));
    await waitFor(tester, find.byTooltip('Import From Gallery'));
    await tester.tap(find.byTooltip('Import From Gallery'));
    await waitFor(tester, find.textContaining('Page edges found'),
        timeout: const Duration(seconds: 90));
    await tester.pumpAndSettle();
    await shot(tester, '8-gallery-crop');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as PDF'));
    bool isNew(Note n) => !known.contains(n.id);
    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 90) &&
        !store.notes.any(isNew)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    final saved = store.notes.singleWhere(isNew);
    expect(saved.pageCount, 1);
    expect((await store.readPdf(saved))!.length, greaterThan(10000));
    await tester.pumpAndSettle();
  });

  testWidgets('a one-minute Pomodoro in Focus Mode ends with an alert',
      (tester) async {
    final timer = PomodoroController.instance;
    final settings = store.settings;
    store.updateSettings(settings.copyWith(focusMinutes: 1));
    addTearDown(() => store.updateSettings(settings));
    timer.restart();
    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    int sessionsToday() => store
        .sessionsBetween(today, DateTime(now.year, now.month, now.day + 1))
        .length;
    final before = sessionsToday();

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppTab.study.icon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START'));
    await waitFor(tester, find.byType(FocusScreen));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await WakelockPlus.enabled, isTrue); // the screen stays on
    await shot(tester, '9-focus');

    final waited = Stopwatch()..start();
    while (waited.elapsed < const Duration(seconds: 90) &&
        sessionsToday() == before) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(sessionsToday(), before + 1);
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()!;
    var shown = <ActiveNotification>[];
    for (var i = 0; i < 15 && !shown.any((n) => n.id == 1); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      shown = await android.getActiveNotifications();
    }
    expect(shown.where((n) => n.id == 1).map((n) => n.title),
        contains('Pomodoro done!'));

    await tester.tap(find.byTooltip('Close Focus Mode'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await WakelockPlus.enabled, isFalse);
    await FlutterLocalNotificationsPlugin().cancelAll();
  });
}

/// A pale page with writing, slightly turned, on a brown desk: a
/// 2400 × 3200 JPEG, bigger than the app keeps (it shrinks it to 2000).
Uint8List pageOnDesk() {
  final photo = img.Image(width: 2400, height: 3200);
  img.fill(photo, color: img.ColorRgb8(92, 70, 52));
  img.fillPolygon(photo,
      vertices: [
        img.Point(380, 300),
        img.Point(2050, 420),
        img.Point(1960, 2900),
        img.Point(300, 2780),
      ],
      color: img.ColorRgb8(238, 234, 224));
  for (var y = 600; y < 2500; y += 90) {
    img.fillRect(photo,
        x1: 520, y1: y, x2: 1750, y2: y + 14, color: img.ColorRgb8(40, 44, 70));
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 85));
}

/// A white page with [lines] in large black letters, as a JPEG.
Uint8List notesPhoto(List<String> lines) {
  final page = img.Image(width: 1400, height: 900);
  img.fill(page, color: img.ColorRgb8(255, 255, 255));
  for (final (i, line) in lines.indexed) {
    img.drawString(page, line,
        font: img.arial48, x: 80, y: 120 + i * 120, color: img.ColorRgb8(0, 0, 0));
  }
  return Uint8List.fromList(img.encodeJpg(page, quality: 90));
}

/// Pumps in real time until [finder] finds something. Stops early, saying
/// what is on screen, when [failsOn] shows up or [timeout] passes.
Future<void> waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 30), Finder? failsOn}) async {
  final waited = Stopwatch()..start();
  while (waited.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    if (failsOn != null && failsOn.evaluate().isNotEmpty) break;
  }
  final shown = [
    for (final e in find.byType(Text).evaluate())
      if ((e.widget as Text).data case final text? when text.trim().isNotEmpty)
        text,
  ];
  fail('Waited ${waited.elapsed.inSeconds} s for $finder. '
      'On screen: ${shown.join(' | ')}');
}

var _surfaceReady = false;

/// Saves a screenshot (through test_driver/integration_test.dart). Never
/// fails the test: the screenshots are for people to look at.
Future<void> shot(WidgetTester tester, String name) async {
  const limit = Duration(seconds: 20);
  try {
    if (!_surfaceReady) {
      await binding.convertFlutterSurfaceToImage().timeout(limit);
      _surfaceReady = true;
      addTearDown(() => _surfaceReady = false); // the binding reverts it
    }
    await tester.pump();
    await binding.takeScreenshot(name).timeout(limit);
  } catch (e) {
    debugPrint('Screenshot $name failed: $e');
  }
}

/// The PDF as text, with its compressed streams inflated (as in
/// test/notes_pdf_test.dart).
String inflated(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final out = StringBuffer(text);
  for (final m in RegExp(r'stream\r?\n').allMatches(text)) {
    var end = text.indexOf('endstream', m.end);
    if (end < 0) continue;
    while (end > m.end && (text[end - 1] == '\n' || text[end - 1] == '\r')) {
      end--;
    }
    try {
      out.write(latin1.decode(
          const ZLibDecoder().decodeBytes(pdf.sublist(m.end, end)),
          allowInvalid: true));
    } catch (_) {
      // Not a deflated stream (an image, say).
    }
  }
  return out.toString();
}
