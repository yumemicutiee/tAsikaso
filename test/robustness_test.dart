import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/pomodoro_controller.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/capture/capture_screen.dart';
import 'package:study_app/screens/focus_screen.dart';
import 'package:study_app/services/haptics.dart';
import 'package:study_app/services/screen_awake.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/widgets/bottom_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScreenAwake.enabled = false;
    Haptics.enabled = false;
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    AppStore.instance.resetForTesting();
    PomodoroController.instance.resetForTesting();
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Like a person's double tap: the second one a few frames later.
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    final at = tester.getCenter(finder);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pump();
  }

  group('A quick second tap', () {
    testWidgets('on START opens Focus Mode once and keeps the timer going',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(const StudyApp());
      await tester.tap(find.byIcon(AppTab.study.icon));
      await tester.pumpAndSettle();

      await doubleTap(tester, find.text('START'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(FocusScreen), findsOneWidget);
      expect(PomodoroController.instance.running, isTrue);
      PomodoroController.instance.pause(); // no timer left running
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('on the camera button opens one camera screen',
        (tester) async {
      usePhoneSize(tester);
      final original = CaptureScreen.loadCameras;
      CaptureScreen.loadCameras = () async => [];
      addTearDown(() => CaptureScreen.loadCameras = original);
      await tester.pumpWidget(const StudyApp());

      await doubleTap(tester, find.byType(CameraButton));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CaptureScreen), findsOneWidget);
    });

    testWidgets("on Import From Gallery doesn't ask for the gallery twice",
        (tester) async {
      usePhoneSize(tester);
      final cameras = CaptureScreen.loadCameras;
      final pick = CaptureScreen.pickImages;
      addTearDown(() {
        CaptureScreen.loadCameras = cameras;
        CaptureScreen.pickImages = pick;
      });
      CaptureScreen.loadCameras = () async => [];
      var asked = 0;
      final gallery = Completer<List<XFile>>();
      CaptureScreen.pickImages = () {
        asked++;
        return gallery.future; // still opening
      };
      await tester.pumpWidget(const MaterialApp(home: CaptureScreen()));
      await tester.pump(const Duration(seconds: 1));

      await doubleTap(tester, find.byTooltip('Import From Gallery'));
      expect(asked, 1);
      expect(find.text("Couldn't open your gallery."), findsNothing);

      // Backing out of the gallery makes the button work again.
      gallery.complete([]);
      await tester.pump();
      await tester.tap(find.byTooltip('Import From Gallery'));
      expect(asked, 2);
    });

    testWidgets("on Restore from Backup doesn't start a second restore",
        (tester) async {
      usePhoneSize(tester);
      final original = BackupScreen.pickFile;
      addTearDown(() => BackupScreen.pickFile = original);
      final file = Completer<Uint8List?>();
      BackupScreen.pickFile = () => file.future; // the picker is opening
      await tester.pumpWidget(const MaterialApp(home: BackupScreen()));

      final restore = find.text('Restore from Backup');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose File'));
      // Busy (with a spinner) while the picker opens: pump, don't settle.
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(restore, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restore from Backup?'), findsNothing);

      // Nothing picked: the button works again.
      file.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.text('Restore from Backup?'), findsOneWidget);
    });
  });
}
