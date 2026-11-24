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
import 'package:study_app/screens/capture/captured_page.dart';
import 'package:study_app/services/page_model_service.dart';
import 'package:study_app/utils/page_model.dart';
import 'package:study_app/screens/capture/notes_pdf.dart';
import 'package:study_app/screens/capture/reading_screen.dart';
import 'package:study_app/screens/capture/review_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/screens/flashcards/set_screen.dart';
import 'package:study_app/screens/note_viewer_screen.dart';
import 'package:study_app/screens/folder_screen.dart';
import 'package:study_app/screens/welcome/welcome_screen.dart';
import 'package:study_app/services/notification_service.dart';
import 'package:study_app/services/scan_service.dart';
import 'package:study_app/services/study_ai.dart';
import 'package:study_app/widgets/bottom_nav.dart';

import 'model_photos.dart';

late final IntegrationTestWidgetsFlutterBinding binding;
final store = AppStore.instance;

void main() {
  // First: it is what reports the results to `flutter drive` (a binding
  // started by testWidgets instead never does, and the run waits forever).
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The welcome's cards float forever; the tests wait for screens to settle.
  WelcomeScreen.floating = false;

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

    // A fresh install: no sample data, and the welcome comes first.
    expect(store.activeTasks, isEmpty);
    expect(store.prefs.welcomed, isFalse);
    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
    await shot(tester, '0a-welcome');
    await tester.tap(find.bySemanticsLabel('Continue without an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Emulator');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Emulator!'), findsOneWidget);
    await shot(tester, '0b-slide-1');
    for (var i = 2; find.text('Next').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await shot(tester, '0b-slide-$i');
    }
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(store.prefs.welcomed, isTrue);

    expect(find.text("Today's Focus"), findsOneWidget);
    await shot(tester, '1-dashboard');
    for (final (i, tab) in [AppTab.library, AppTab.study, AppTab.profile].indexed) {
      await tester.tap(find.byIcon(tab.icon));
      await tester.pumpAndSettle();
      await shot(tester, '${i + 2}-${tab.name}');
    }
  });

  testWidgets("reads the text on a photo and hides it in the note's PDF",
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
      sound: true,
      vibrate: true,
    );
    expect((await plugin.pendingNotificationRequests()).map((r) => r.id),
        contains(1));

    // The other "When Time Is Up" choices make their own channels.
    for (final (sound, vibrate) in [(true, false), (false, true)]) {
      await NotificationService.scheduleTimerEnd(
          clock.now().add(const Duration(hours: 1)), 'Check', 'Channel check.',
          isBreak: true, sound: sound, vibrate: vibrate);
    }
    await NotificationService.scheduleTimerEnd(
        clock.now().add(const Duration(hours: 1)), 'Off', 'Nothing.',
        isBreak: true, sound: false, vibrate: false);
    expect((await plugin.pendingNotificationRequests()).map((r) => r.id),
        isNot(contains(3)), reason: 'Off schedules nothing');

    // What Android made of them: the phone's alarm sound, on the alarm
    // volume (rings even on silent), loud enough to wake; vibration as chosen.
    final channels = {
      for (final c in await android.getNotificationChannels() ?? const []) c.id: c,
    };
    debugPrint('Timer channels: ${[
      for (final c in channels.values)
        '${c.id}: sound=${(c.sound as dynamic)?.sound} usage=${c.audioAttributesUsage} '
            'vibrate=${c.enableVibration} importance=${c.importance}',
    ]}');
    for (final id in ['timer_alarm_vibrate', 'timer_alarm']) {
      final c = channels[id];
      expect(c, isNotNull, reason: id);
      expect(c!.playSound, isTrue, reason: id);
      expect((c.sound as dynamic).sound.toString(), contains('alarm_alert'), reason: id);
      expect(c.audioAttributesUsage, AudioAttributesUsage.alarm, reason: id);
      // Max is asked for; Android may keep it as high (heads-up with sound).
      expect(c.importance.value, greaterThanOrEqualTo(Importance.high.value), reason: id);
    }
    expect(channels['timer_alarm_vibrate']!.enableVibration, isTrue);
    expect(channels['timer_alarm']!.enableVibration, isFalse);
    expect(channels['timer_vibrate']!.playSound, isFalse);
    expect(channels['timer_vibrate']!.enableVibration, isTrue);

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

  testWidgets('the camera takes a photo that is read and saved as notes',
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

    await nextAndRead(tester, shotName: '6b-reading');
    await shot(tester, '7-save-sheet');
    // The camera's test pattern has no text: the photo is still kept, for
    // the notes to be typed in with Edit.
    await tester.tap(find.text('Save Notes').last);
    await waitFor(tester, find.byType(NoteTextScreen),
        timeout: const Duration(seconds: 90));
    final saved = store.notes.singleWhere((n) => !known.contains(n.id));
    expect(saved.pageCount, 1);
    expect((await store.readPdf(saved))!.length, greaterThan(1000));
    await tester.pumpAndSettle();
    await shot(tester, '7b-saved');
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

    await nextAndRead(tester);
    await tester.tap(find.text('Save Notes').last);
    await waitFor(tester, find.byType(NoteTextScreen),
        timeout: const Duration(seconds: 90));
    final saved = store.notes.singleWhere((n) => !known.contains(n.id));
    expect(saved.pageCount, 1);
    expect((await store.readPdf(saved))!.length, greaterThan(10000));
    await tester.pumpAndSettle();
  });

  testWidgets("a photo of notes → text notes in a folder's Notebook → flashcards "
      'where the user picks',
      (tester) async {
    // The whole study flow on the phone: a photo of notes is read (ML Kit),
    // saved as Text Notes in the folder picked on the save sheet, found in
    // that folder, then turned into flashcards.
    final before = store.prefs;
    store.updatePrefs(before.copyWith(useAi: false));
    addTearDown(() => store.updatePrefs(before));
    final chemistry = store.addFolder('Chemistry Check', 0xFFF5C2A9);
    final biology = store.addFolder('Biology Check', 0xFFA9CFF5); // newest: picked first
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/notes_page.jpg');
    await file.writeAsBytes(notesPhoto([
      'OSMOSIS: water across a membrane',
      'DIFFUSION: particles spreading out',
    ]));
    final pick = CaptureScreen.pickImages;
    CaptureScreen.pickImages = () async => [XFile(file.path)];
    addTearDown(() => CaptureScreen.pickImages = pick);
    final known = {for (final n in store.notes) n.id};
    final knownSets = {for (final s in store.sets) s.id};

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CameraButton));
    await waitFor(tester, find.byTooltip('Import From Gallery'));
    await tester.tap(find.byTooltip('Import From Gallery'));
    await waitFor(tester, find.byType(ReviewScreen),
        timeout: const Duration(seconds: 90));
    await tester.pumpAndSettle();
    await nextAndRead(tester, shotName: '10b-reading');

    // After reading, only the folder is asked.
    expect(find.text('Text Notes'), findsNothing);
    expect(find.text('Flashcards'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<StudyFolder>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemistry Check').last);
    await tester.pumpAndSettle();
    await shot(tester, '11-save-notes');
    await tester.tap(find.text('Save Notes').last);
    await waitFor(tester, find.byType(NoteTextScreen),
        timeout: const Duration(seconds: 90));
    await tester.pumpAndSettle();
    await shot(tester, '12-text-notes');

    final note = store.notes.singleWhere((n) => !known.contains(n.id));
    debugPrint('Text Notes read: ${note.text}');
    expect(note.textNote, isTrue);
    expect(note.folderId, chemistry.id);
    expect(note.text.toLowerCase(), contains('osmosis'));
    expect(note.text.toLowerCase(), contains('diffusion'));
    expect(find.textContaining(RegExp('osmosis', caseSensitive: false)),
        findsWidgets);
    expect((await store.readPdf(note))!.length, greaterThan(1000),
        reason: 'the photo is kept as the original page');

    // The note is in that folder's Notebook.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppTab.library.icon));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Chemistry Check'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Chemistry Check'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderScreen), findsOneWidget);
    // The Notebook card shows the latest note's title.
    expect(find.text(note.title), findsOneWidget);
    await shot(tester, '13-folder');
    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();
    expect(find.text('Chemistry Check Notebook'), findsOneWidget);
    expect(find.text(note.title), findsOneWidget);
    await shot(tester, '14-notebook');

    // Opened from the Notebook, it's on its text. Make Flashcards asks where
    // the cards go: here, a new set in another folder.
    await tester.tap(find.text(note.title));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTextScreen), findsOneWidget);
    await tester.tap(find.text('Make Flashcards'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<StudyFolder>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biology Check').last);
    await tester.pumpAndSettle();
    await shot(tester, '15-cards-go-to');
    await tester.tap(find.text('Make Flashcards').last);
    await waitFor(tester, find.byType(SetScreen));
    await tester.pumpAndSettle();
    final deck = store.sets.singleWhere((s) => !knownSets.contains(s.id));
    debugPrint('Cards suggested: '
        '${deck.suggestions.map((c) => '${c.front} = ${c.back}').join('; ')}');
    expect(deck.folderId, biology.id);
    expect(store.note(note.id)!.folderId, chemistry.id);
    expect(deck.suggestions.map((c) => c.front.toLowerCase()),
        containsAll(['osmosis', 'diffusion']));
    await shot(tester, '16-flashcards');
  });

  testWidgets('the page models find the page on a white desk, among clutter '
      'and around ruled lines', (tester) async {
    // The simple detector finds nothing on a white desk; the models must, on
    // this phone, with no help from Google Play services.
    PageModel.reset();
    double worst(List<Offset> c, List<Offset> truth) => [
          for (var i = 0; i < 4; i++) (c[i] - truth[i]).distance,
        ].reduce((a, b) => a > b ? a : b);
    PageModelInputs inputsFor(Uint8List jpg) {
      final image = img.decodeJpg(jpg)!;
      return PageModelInputs(pageModelInput(image), pageModelInputPadded(image),
          image.width, image.height);
    }

    for (final photo in modelPhotos) {
      final truth = [for (final p in photo.truth) Offset(p[0], p[1])];
      final jpg = base64Decode(photo.jpgBase64);
      final took = Stopwatch()..start();
      final corners = await PageModel.findCorners(inputsFor(jpg));
      debugPrint('Page models on ${photo.name}: ${took.elapsedMilliseconds} ms');
      expect(corners, isNotNull, reason: 'the models ran and saw ${photo.name}');
      expect(worst(corners!, truth), lessThan(0.02), reason: photo.name);
      // And through the app's own import path.
      final page = await CapturedPage.fromPhoto(1, jpg, findEdges: true);
      expect(page.autoDetected, isTrue, reason: photo.name);
      expect(worst(page.corners, truth), lessThan(0.02), reason: photo.name);
    }
    expect(PageModel.available, isTrue);

    // The gallery test's page: ruled lines with wide margins, which the
    // models take for the page. The crop must still be the whole sheet.
    final sheet = await CapturedPage.fromPhoto(2, pageOnDesk(), findEdges: true);
    const sheetTruth = [
      Offset(380 / 2400, 300 / 3200),
      Offset(2050 / 2400, 420 / 3200),
      Offset(1960 / 2400, 2900 / 3200),
      Offset(300 / 2400, 2780 / 3200),
    ];
    expect(sheet.autoDetected, isTrue);
    expect(worst(sheet.corners, sheetTruth), lessThan(0.02),
        reason: 'cropped to the sheet, not the lines on it: ${sheet.corners}');

    // A second run is the normal case: timed for the log.
    final warm = inputsFor(base64Decode(modelPhotos.first.jpgBase64));
    final again = Stopwatch()..start();
    await PageModel.findCorners(warm);
    debugPrint('Page models, warm: ${again.elapsedMilliseconds} ms');
  });

  testWidgets('Smart Study end to end: the app, the study server and Claude',
      (tester) async {
    // tool/emulator_tests.sh runs the real study server on the machine that
    // hosts the emulator (10.0.2.2), with a stand-in for Claude, and passes
    // its address in; elsewhere this test has nothing to talk to.
    const url = String.fromEnvironment('E2E_STUDY_SERVER');
    if (url.isEmpty) {
      markTestSkipped('No study server for this run.');
      return;
    }
    final before = store.prefs;
    addTearDown(() => store.updatePrefs(before));
    void useServer(String address, String token) => store.updatePrefs(store.prefs
        .copyWith(useAi: true, aiServerUrl: address, aiToken: token));
    const notes = 'Mitochondria make ATP for the cell. Ribosomes make '
        'proteins. The nucleus holds the DNA.';

    useServer(url, 'emulator-token');
    expect(await StudyAi.ping(url), isTrue, reason: 'Settings → Connected');

    final kit = await StudyAi.makeStudyKit(text: notes, title: 'Cells');
    expect(kit.cards, hasLength(3));
    expect(kit.summary, contains('E2E summary'));
    expect(kit.notes, contains('Mitochondria make ATP'));
    expect(kit.concepts.single.term, contains('ATP'));
    expect(kit.quiz.single.prompt, contains('E2E question'));
    expect(kit.quiz.single.cardId, kit.cards[1].id,
        reason: 'the question points at the card it tests');

    final quiz = await StudyAi.makeQuiz(title: 'Cells', cards: kit.cards);
    expect(quiz, isNotEmpty);
    expect(quiz.first.prompt, startsWith('E2E'));

    final check = await StudyAi.checkAnswer(
        question: 'Which organelle makes ATP?',
        answer: 'Mitochondria',
        userAnswer: 'the mitochondrion');
    expect(check.partly, isTrue);
    expect(check.feedback, contains('E2E feedback'));

    // A wrong token: the server refuses, and the app says why.
    useServer(url, 'not-the-token');
    await expectLater(
        StudyAi.makeStudyKit(text: notes),
        throwsA(isA<StudyAiException>()
            .having((e) => e.code, 'code', 'unauthorized')));

    // Nothing at that address (the phone offline, a wrong address).
    const nobody = 'http://10.0.2.2:9';
    expect(await StudyAi.ping(nobody), isFalse,
        reason: 'Settings → no study server answered there');
    useServer(nobody, 'emulator-token');
    await expectLater(
        StudyAi.makeStudyKit(text: notes),
        throwsA(isA<StudyAiException>().having((e) => e.code, 'code', 'offline')));

    // Back to the real server.
    useServer(url, 'emulator-token');
    store.updatePrefs(store.prefs.copyWith(aiReading: true));

    // A page photo read by Claude (the stand-in answers only if it came as
    // an image).
    final printed = notesPhoto(['Mitochondria make ATP']);
    final pageText = await StudyAi.readPage(printed);
    expect(pageText, startsWith('E2E read by Claude'),
        reason: 'the photo reached Claude as an image');

    // The whole way through the screens: a photo of notes from the gallery
    // → lines found on the phone (ML Kit) → the photo read by Claude →
    // typed up by the server → saved as notes → Make Flashcards → cards
    // from the server.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/notes_for_ai.jpg');
    await file.writeAsBytes(notesPhoto([
      'Mitochondria make ATP',
      'Ribosomes make proteins',
      'The nucleus holds the DNA',
    ]));
    final pick = CaptureScreen.pickImages;
    CaptureScreen.pickImages = () async => [XFile(file.path)];
    addTearDown(() => CaptureScreen.pickImages = pick);
    final knownSets = {for (final s in store.sets) s.id};

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CameraButton));
    await waitFor(tester, find.byTooltip('Import From Gallery'));
    await tester.tap(find.byTooltip('Import From Gallery'));
    await waitFor(tester, find.byType(ReviewScreen),
        timeout: const Duration(seconds: 90));
    await tester.pumpAndSettle();
    await nextAndRead(tester);
    final knownNotes = {for (final n in store.notes) n.id};
    final waited = Stopwatch()..start();
    await tester.tap(find.text('Save Notes').last);
    await waitFor(tester, find.byType(NoteTextScreen),
        timeout: const Duration(seconds: 120));
    await tester.pumpAndSettle();
    final note = store.notes.singleWhere((n) => !knownNotes.contains(n.id));
    expect(note.text, startsWith('E2E read by Claude'),
        reason: "the note's text is Claude's reading of the photo, not ML Kit's");
    expect(note.cleanText, contains('Mitochondria'),
        reason: 'typed up by Claude via the server');
    expect(note.summary, contains('E2E summary'));
    await tester.tap(find.text('Make Flashcards'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Flashcards').last); // a new set

    bool isNew(FlashcardSet s) => !knownSets.contains(s.id);
    while (waited.elapsed < const Duration(seconds: 120) && !store.sets.any(isNew)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    final made = store.sets.singleWhere(isNew);
    debugPrint('Smart Study save flow: ${waited.elapsedMilliseconds} ms');
    expect(made.cards.map((c) => c.front), contains('E2E front'),
        reason: 'the cards came from Claude via the server, not the offline guesser');
    expect(made.summary, contains('E2E summary'));
    expect(made.sourceText, contains('Mitochondria'),
        reason: "the cards were made from the note's text");
    expect(made.folderId, note.folderId);
    await tester.pumpAndSettle();
    await shot(tester, '10-smart-study-set');
  });

  testWidgets('a 12-page scan from the gallery becomes one set of Text Notes',
      (tester) async {
    // Each page is a large photo (1500 × 2000), so the phone crops, reads
    // (OCR) and lays out twelve of them one after another, as with a long
    // lecture. Time and memory go to the log.
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (var i = 1; i <= 12; i++) {
      final page = img.Image(width: 1500, height: 2000);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      for (var line = 0; line < 8; line++) {
        img.drawString(page, line == 0 ? 'Lecture page $i' : 'Line $line of page $i',
            font: img.arial48, x: 100, y: 150 + line * 200, color: img.ColorRgb8(0, 0, 0));
      }
      final f = File('${dir.path}/long_scan_$i.jpg');
      await f.writeAsBytes(img.encodeJpg(page, quality: 90));
      files.add(XFile(f.path));
    }
    final pick = CaptureScreen.pickImages;
    CaptureScreen.pickImages = () async => files;
    addTearDown(() => CaptureScreen.pickImages = pick);
    final known = {for (final n in store.notes) n.id};
    final rssBefore = ProcessInfo.currentRss;

    await tester.pumpWidget(const StudyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CameraButton));
    await waitFor(tester, find.byTooltip('Import From Gallery'));
    final took = Stopwatch()..start();
    await tester.tap(find.byTooltip('Import From Gallery'));
    await waitFor(tester, find.byType(ReviewScreen),
        timeout: const Duration(minutes: 3));
    await tester.pumpAndSettle();
    final imported = took.elapsedMilliseconds;
    await nextAndRead(tester, timeout: const Duration(minutes: 4));
    final read = took.elapsedMilliseconds - imported;
    // Text Notes: the text of all 12 pages, with the photos kept.
    await tester.tap(find.text('Save Notes').last);
    bool isNew(Note n) => !known.contains(n.id);
    while (took.elapsed < const Duration(minutes: 6) && !store.notes.any(isNew)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    }
    final saved = store.notes.singleWhere(isNew);
    expect(saved.textNote, isTrue);
    debugPrint('12-page scan: imported in $imported ms, read in $read ms, saved in '
        '${took.elapsedMilliseconds} ms; memory ${rssBefore >> 20} MB → '
        '${ProcessInfo.currentRss >> 20} MB, peak ${ProcessInfo.maxRss >> 20} MB');
    expect(saved.pageCount, 12);
    // Read on the phone, page by page: the last page's text is in the
    // note (search) and hidden in the PDF (select and copy).
    expect(saved.text.toLowerCase(), contains('lecture page 12'));
    final pdf = (await store.readPdf(saved))!;
    expect(pdfPageCount(pdf), 12);
    // Invisible text (rendering mode 3) on every page: selectable, searchable.
    expect(RegExp(r'\b3 Tr\b').allMatches(inflated(pdf)).length,
        greaterThanOrEqualTo(12));
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

    // The alarm keeps going until the student stops it: still there after
    // more than the minute it used to be limited to.
    await Future<void>.delayed(const Duration(seconds: 75));
    expect((await android.getActiveNotifications()).map((n) => n.id),
        contains(1),
        reason: 'the alarm must keep going until Stop is tapped');

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

/// Taps Next on the crop screen: the reading screen crops and reads the
/// pages (a screenshot of it as [shotName]), then the save sheet opens.
Future<void> nextAndRead(WidgetTester tester,
    {String? shotName, Duration timeout = const Duration(seconds: 90)}) async {
  await tester.tap(find.text('Next'));
  if (shotName != null) {
    await waitFor(tester, find.byType(ReadingScreen));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await shot(tester, shotName);
  }
  await waitFor(tester, find.byType(SaveSheet),
      timeout: timeout, failsOn: find.text("Couldn't read the pages"));
  await tester.pumpAndSettle();
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
