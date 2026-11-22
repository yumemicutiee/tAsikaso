import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/screens/capture/reading_screen.dart';
import 'package:study_app/screens/capture/review_screen.dart';

/// Taps Next on the crop screen and waits (in real time: the pages are
/// cropped in another isolate) while the reading screen reads them, until
/// the save sheet is up.
Future<void> tapNextAndRead(WidgetTester tester) async {
  ReadingScreen.pause = Duration.zero;
  await tester.tap(find.text('Next'));
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 300 && find.byType(SaveSheet).evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}
