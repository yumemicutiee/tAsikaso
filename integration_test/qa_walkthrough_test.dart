// QA walkthrough (not part of the regular emulator run): opens every main
// screen on an Android emulator in light and dark mode, on the free plan and
// on tAsikaso+, and on a small phone with large text, saving a screenshot of
// each. Layout errors (overflows) and exceptions are logged with the screen
// they happened on ("QA_PROBLEM") instead of stopping the run, so one run
// shows every problem. Run by .github/workflows/qa-walkthrough.yml.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:study_app/app.dart';
import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/plans.dart';
import 'package:study_app/data/storage/local_storage.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/screens/capture/notes_pdf.dart';
import 'package:study_app/utils/format.dart';

late final IntegrationTestWidgetsFlutterBinding binding;
final store = AppStore.instance;
final problems = <String>[];
var stage = 'start';
var shotCount = 0;

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA walkthrough', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final first = details.exceptionAsString().split('\n').first;
      problems.add('[$stage] $first');
      debugPrint('QA_PROBLEM [$stage] ${details.exceptionAsString()}');
    };
    try {
      await store.init(createDeviceStorage());
      await seed();
      await walk(tester);
    } finally {
      FlutterError.onError = original;
    }
    debugPrint('QA_SUMMARY ${problems.length} problem(s), $shotCount screenshots');
    for (final p in problems) {
      debugPrint('QA_SUMMARY $p');
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}

// ---------------------------------------------------------------- data

Future<void> seed() async {
  store.updatePrefs(store.prefs.copyWith(userName: 'Budi'));
  final photo = notesPhoto(['PHOTOSYNTHESIS', 'Light makes sugar']);
  final pdf = await buildNotesPdf([photo], title: 'Photosynthesis Notes');
  await store.addNote(
    title: 'Photosynthesis Notes',
    folderId: 'f-biology',
    pdf: pdf,
    thumbnail: photo,
    pageCount: 1,
    text: 'Photosynthesis - Lecture 7\nCalvin cycle in the stroma uses ATP and NADPH.',
    cleanText: '# Photosynthesis\n\n## Calvin Cycle\n- Takes place in the stroma.\n'
        '- Uses ATP and NADPH to fix carbon dioxide.\n\n1. First numbered line\n2. Second',
    summary: 'How plants turn light into sugar, from the thylakoids to the Calvin cycle.',
    concepts: const [
      Concept(term: 'Thylakoid', explanation: 'Membrane discs where the light reactions happen.'),
      Concept(term: 'RuBisCO', explanation: 'The enzyme that fixes carbon dioxide.'),
    ],
  );
  Flashcard card(String f, String b) => Flashcard(id: newId(), front: f, back: b);
  final cards = [
    card('Where does the Calvin cycle take place?', 'In the stroma.'),
    card('What is photolysis?', 'Splitting water with light energy.'),
    card('Which enzyme fixes CO2?', 'RuBisCO.'),
    card('What do the light reactions make?', 'ATP and NADPH.'),
    card('Main pigment in chloroplasts?', 'Chlorophyll.'),
    card('A very long question to see how a card with a lot of text wraps on a '
        'small phone with large text turned on in the accessibility settings?',
        'An equally long answer that keeps going so the back of the card also '
        'needs several lines on a narrow screen, which is where things break.'),
  ];
  await store.addSet(
    title: 'Photosynthesis Lecture',
    folderId: 'f-biology',
    cards: cards,
    sourceText: 'Calvin cycle in the stroma uses ATP and NADPH.',
    summary: 'How plants turn light into sugar.',
    concepts: const [Concept(term: 'Stroma', explanation: 'Fluid around the thylakoids.')],
    quiz: [
      const QuizQuestion(
          type: QuestionType.multipleChoice,
          prompt: 'Where does the Calvin cycle take place?',
          answer: 'Stroma',
          options: ['Thylakoid membrane', 'Stroma', 'Mitochondria', 'Cytoplasm'],
          answerIndex: 1,
          explanation: 'It runs in the stroma.'),
      const QuizQuestion(
          type: QuestionType.trueFalse,
          prompt: 'Oxygen released in photosynthesis comes from CO2.',
          answer: 'False',
          options: ['True', 'False'],
          answerIndex: 1),
      const QuizQuestion(
          type: QuestionType.fillBlank,
          prompt: 'The enzyme ____ fixes carbon dioxide.',
          answer: 'RuBisCO'),
      const QuizQuestion(
          type: QuestionType.typed,
          prompt: 'What do the light reactions make for the Calvin cycle?',
          answer: 'ATP and NADPH'),
    ],
  );
  await store.addSet(
    title: 'A set with a really long name that should be cut off nicely',
    folderId: 'f-physics',
    cards: [card('F = ?', 'ma'), card('Speed?', 'distance / time')],
  );
  await store.pendingSaves;
}

Uint8List notesPhoto(List<String> lines) {
  final page = img.Image(width: 1400, height: 900);
  img.fill(page, color: img.ColorRgb8(255, 255, 255));
  for (final (i, line) in lines.indexed) {
    img.drawString(page, line,
        font: img.arial48, x: 80, y: 120 + i * 120, color: img.ColorRgb8(0, 0, 0));
  }
  return Uint8List.fromList(img.encodeJpg(page, quality: 90));
}

// ---------------------------------------------------------------- helpers

late WidgetTester t;

Future<void> settle([int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> restart() async {
  await t.pumpWidget(StudyApp(key: UniqueKey()));
  await settle(1500);
}

var _surfaceReady = false;
Future<void> shot(String name) async {
  shotCount++;
  final n = '${shotCount.toString().padLeft(3, '0')}-$name';
  try {
    if (!_surfaceReady) {
      await binding.convertFlutterSurfaceToImage().timeout(const Duration(seconds: 20));
      _surfaceReady = true;
    }
    await t.pump();
    await binding.takeScreenshot(n).timeout(const Duration(seconds: 20));
  } catch (e) {
    debugPrint('Screenshot $n failed: $e');
  }
}

/// Taps the first widget showing [label] (text, then tooltip, then a text
/// containing it). Logs QA_MISSING and returns false when there is none.
Future<bool> tap(String label, {bool contains = false, int wait = 700}) async {
  for (final f in [
    find.text(label),
    find.byTooltip(label),
    if (contains) find.textContaining(label),
  ]) {
    final hits = f.hitTestable();
    if (hits.evaluate().isNotEmpty) {
      await t.tap(hits.first, warnIfMissed: false);
      await settle(wait);
      return true;
    }
    if (f.evaluate().isNotEmpty) {
      try {
        await t.ensureVisible(f.first);
        await settle(300);
        await t.tap(f.first, warnIfMissed: false);
        await settle(wait);
        return true;
      } catch (_) {}
    }
  }
  debugPrint('QA_MISSING [$stage] "$label"');
  return false;
}

/// Brings [label] into view by scrolling the screen's list down.
Future<bool> scrollTo(String label) async {
  for (var i = 0; i < 14; i++) {
    final f = find.text(label).hitTestable();
    if (f.evaluate().isNotEmpty) {
      await t.ensureVisible(f.first);
      await settle(300);
      return true;
    }
    await swipeUp();
  }
  debugPrint('QA_MISSING [$stage] scroll to "$label"');
  return false;
}

Future<void> swipeUp([double by = 450]) async {
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  await t.dragFrom(Offset(size.width / 2, size.height * 0.62), Offset(0, -by));
  await settle(500);
}

/// Screenshots a long screen in [n] parts.
Future<void> shots(String name, int n) async {
  await shot(name);
  for (var i = 2; i <= n; i++) {
    await swipeUp(520);
    await shot('$name-$i');
  }
}

Future<void> back() async {
  await t.binding.handlePopRoute();
  await settle(700);
}

Future<void> step(String name, Future<void> Function() body) async {
  stage = name;
  debugPrint('QA_STEP $name');
  try {
    await body();
  } catch (e, st) {
    problems.add('[$name] test step failed: $e');
    debugPrint('QA_PROBLEM [$name] step failed: $e\n$st');
  }
}

Future<void> openTab(String label) async {
  final f = find.text(label).hitTestable();
  if (f.evaluate().isNotEmpty) {
    await t.tap(f.last, warnIfMissed: false);
  } else {
    debugPrint('QA_MISSING [$stage] tab "$label"');
  }
  await settle(900);
}

// ---------------------------------------------------------------- walk

Future<void> walk(WidgetTester tester) async {
  t = tester;
  await step('alarm notice after updating', () async {
    store.updatePrefs(store.prefs.copyWith(alarmNotice: true));
    await restart();
    await shot('0-alarm-notice');
    await tap('Keep Alarm');
  });
  await restart();
  await step('about logo', () async {
    await openTab('Profile');
    await tap('Settings');
    await scrollTo('tAsikaso');
    await shot('0-settings-logo-navy');
    await back();
  });

  Future<void> tour(String m) async {
    await step('$m dashboard', () async {
      await openTab('Dashboard');
      await shots('$m-dashboard', 3);
    });
    await step('$m library', () async {
      await openTab('Library');
      await shots('$m-library', 2);
    });
    await step('$m note', () async {
      await openTab('Library');
      if (await scrollTo('Photosynthesis Notes')) {
        await tap('Photosynthesis Notes', wait: 2500);
        await shot('$m-note-viewer');
        if (await tap('View Text', wait: 1200)) {
          await shots('$m-note-text', 3);
          await tap('Show the text as read');
          await shot('$m-note-text-raw');
          await back();
        }
        await back();
      }
    });
    await step('$m set', () async {
      await openTab('Library');
      await scrollTo('Photosynthesis Lecture');
      await tap('Photosynthesis Lecture', wait: 1200);
      await shots('$m-set', 3);
      await back();
    });
    await step('$m study', () async {
      await openTab('Study');
      await shots('$m-study', 2);
    });
    await step('$m profile', () async {
      await openTab('Profile');
      await shots('$m-profile', 2);
    });
    await step('$m settings', () async {
      await openTab('Profile');
      await tap('Settings');
      await shots('$m-settings', 8);
      await back();
    });
    await step('$m plans', () async {
      await openTab('Profile');
      await tap('See Plans', contains: false) || await tap('Manage Plan');
      await shots('$m-plans', 4);
      await back();
    });
    await step('$m backup', () async {
      await openTab('Profile');
      await scrollTo('Backup & Sync');
      await tap('Backup & Sync');
      await shots('$m-backup', 3);
      await back();
    });
    await step('$m analysis', () async {
      await openTab('Profile');
      await tap('Pomodoro Analysis', wait: 1200);
      await shots('$m-analysis', 6);
      await tap('Timeline', wait: 1000);
      await shots('$m-timeline', 2);
      await back();
    });
    await step('$m help', () async {
      await openTab('Profile');
      await scrollTo('Help & FAQ');
      await tap('Help & FAQ');
      await tap('How do quizzes work?');
      await shots('$m-help', 3);
      await back();
    });
  }

  // 1. Light, free plan, normal phone.
  await tour('a-free');

  await step('a-free gated', () async {
    await openTab('Library');
    await scrollTo('Photosynthesis Lecture');
    await tap('Photosynthesis Lecture', wait: 1200);
    await tap('Smart review: just the cards due today', contains: true);
    await shot('a-free-plus-prompt');
    await tap('Not Now');
    await tap('More');
    await shot('a-free-set-menu');
    await tap('New Quiz');
    await shot('a-free-new-quiz');
    await back();
    await back();
  });

  await step('a-free quiz', () async {
    await openTab('Library');
    await scrollTo('Photosynthesis Lecture');
    await tap('Photosynthesis Lecture', wait: 1200);
    await tap('Take a Quiz', contains: true, wait: 1500);
    await shot('a-quiz-1');
    await tap('Stroma');
    await tap('Check');
    await shot('a-quiz-1-checked');
    await tap('Next');
    await tap('True');
    await tap('Check');
    await shot('a-quiz-2-wrong');
    await tap('Next');
    await t.enterText(find.byType(TextField).first, 'Rubisko');
    await settle();
    await tap('Check', wait: 1500);
    await shot('a-quiz-3-typo');
    await tap('Next');
    await t.enterText(find.byType(TextField).first, 'energy molecules ATP');
    await settle();
    await tap('Check', wait: 3000);
    await shot('a-quiz-4-partly');
    await tap('See Results', wait: 1200);
    await shots('a-quiz-results', 2);
    await back();
    await shot('a-quiz-after-back');
    await back();
  });

  await step('a-free study cards', () async {
    await openTab('Library');
    await scrollTo('Photosynthesis Lecture');
    await tap('Photosynthesis Lecture', wait: 1200);
    await tap('Study', contains: true, wait: 1200);
    await shot('a-cards-1');
    await tap('Show Answer');
    await shot('a-cards-1-back');
    await tap('Got It');
    await back();
    await shot('a-cards-left-midway');
    await back();
  });

  await step('a-free timer', () async {
    await openTab('Study');
    await tap('START', wait: 2500);
    await shot('a-focus');
    await back();
    await shot('a-focus-closed');
    await tap('Reset Timer');
    await shot('a-reset-confirm');
    await tap('Cancel');
    await tap('Short Break');
    await shot('a-switch-confirm');
    await tap('Cancel');
  });

  await step('a-free settings sheets', () async {
    await openTab('Profile');
    await tap('Settings');
    await scrollTo('When Time Is Up');
    await tap('When Time Is Up');
    await shot('a-time-up-sheet');
    await back();
    await scrollTo('Study Server');
    await tap('Study Server');
    await shot('a-study-server-dialog');
    await tap('Cancel');
    await scrollTo('Delete All Data');
    await tap('Delete All Data');
    await shot('a-delete-dialog');
    await tap('Cancel');
    await back();
  });

  // 2. tAsikaso+ (test plan) and dark mode.
  await step('b-plus', () async {
    store.startPlan(PlusPlan.yearly);
    store.updatePrefs(store.prefs.copyWith(appearance: Appearance.dark));
    await restart();
  });
  await tour('b-plus-dark');
  await step('b-plus-dark set review', () async {
    await openTab('Library');
    await scrollTo('Photosynthesis Lecture');
    await tap('Photosynthesis Lecture', wait: 1200);
    await shot('b-set-plus');
    await tap('Review', contains: true, wait: 1200);
    await shot('b-review-due');
    await back();
    await back();
  });

  // 3. Small phone (320 x 568) with large text (1.5x), light, Plus.
  await step('c-small', () async {
    store.updatePrefs(store.prefs.copyWith(appearance: Appearance.light));
    t.view.physicalSize = const Size(320 * 2.75, 568 * 2.75);
    t.view.devicePixelRatio = 2.75;
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    await restart();
  });
  await tour('c-small-big-text');
  await step('c-small quiz', () async {
    await openTab('Library');
    await scrollTo('Photosynthesis Lecture');
    await tap('Photosynthesis Lecture', wait: 1200);
    await tap('Take a Quiz', contains: true, wait: 1500);
    await shot('c-quiz');
    await tap('Stroma');
    await tap('Check');
    await shot('c-quiz-checked');
    await back();
    await back();
  });
  await step('c-small focus', () async {
    await openTab('Study');
    await tap('START', wait: 2500);
    await shot('c-focus');
    await back();
  });
  t.platformDispatcher.clearTextScaleFactorTestValue();
  t.view.reset();
}
