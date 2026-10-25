import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/models/models.dart';

// The store's own safety: restores that can't half-happen, and dates that
// stay on their day.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;

  setUp(store.resetForTesting);

  /// A backup holding one note ("From Backup") and a set with a photo,
  /// made on another (in-memory) device.
  Future<Uint8List> otherBackup() async {
    await store.init(MemoryStorage());
    final folder = store.addFolder('Restored', 0xFFA9CFF5);
    await store.addNote(
      title: 'From Backup',
      folderId: folder.id,
      pdf: Uint8List.fromList([9, 9]),
      thumbnail: Uint8List.fromList([9]),
      pageCount: 1,
    );
    await store.addSet(
        title: 'Deck', folderId: folder.id, photos: [Uint8List.fromList([8])]);
    final zip = await store.createBackup();
    store.resetForTesting();
    return zip;
  }

  group('Smart review dates', () {
    test('a card is due at midnight a whole number of days later, also '
        'across a daylight-saving change', () async {
      final deck = await store.addSet(
        title: 'Bonds',
        folderId: store.folders.first.id,
        cards: const [Flashcard(id: 'c', front: 'Ionic', back: 'Transfer')],
      );
      // Evenings just before the clocks change in Europe and the Americas.
      for (final now in [
        DateTime(2026, 3, 7, 21),
        DateTime(2026, 3, 28, 21),
        DateTime(2026, 10, 24, 21),
        DateTime(2026, 10, 31, 21),
      ]) {
        withClock(Clock.fixed(now), () {
          store.scheduleCard(deck.id, 'c', knewIt: false); // back to 1 day
          store.scheduleCard(deck.id, 'c', knewIt: true); // 3 days
        });
        final due = store.setById(deck.id)!.cards.single.due!;
        expect(due, DateTime(now.year, now.month, now.day + 3), reason: '$now');
        expect((due.hour, due.minute), (0, 0), reason: '$now');
      }
    });
  });

  test('while saving is paused, a note made this session still opens',
      () async {
    final storage = MemoryStorage();
    await storage.writeJson('{"version": 99}'); // from a newer app version
    await store.init(storage);
    expect(store.isPersistent, isFalse);

    final note = await store.addNote(
      title: 'New',
      folderId: store.addFolder('Bio', 0xFFA9CFF5).id,
      pdf: Uint8List.fromList([1, 2]),
      thumbnail: Uint8List.fromList([1]),
      pageCount: 1,
    );
    final deck = await store.addSet(
        title: 'Deck', folderId: note.folderId, photos: [Uint8List.fromList([3])]);
    expect(await store.readPdf(note), [1, 2]);
    expect(await store.readSetPhoto(deck, 0), [3]);
    expect(await storage.readBytes(note.pdfKey), isNull); // the device is untouched
  });

  group('Restoring a backup', () {
    test("an old backup's ended plan doesn't say this device's plan ended",
        () async {
      // A backup made in September, during a monthly plan...
      final zip = await withClock(Clock.fixed(DateTime(2026, 9, 1)), () {
        store.startPlan(PlusPlan.monthly);
        return store.createBackup();
      });
      // ...restored in October, on a yearly plan.
      await withClock(Clock.fixed(DateTime(2026, 10, 20)), () async {
        store.startPlan(PlusPlan.yearly);
        store.problem.value = null;
        await store.restoreBackup(zip);
        expect(store.problem.value, isNull);
        expect(store.plan, PlusPlan.yearly);
      });
    });

    test('a restore that runs out of space keeps what was here, files too',
        () async {
      final zip = await otherBackup();
      final storage = _FullStorage();
      await store.init(storage);
      final mine = await store.addNote(
        title: 'Mine',
        folderId: store.folders.first.id,
        pdf: Uint8List.fromList([1, 2, 3]),
        thumbnail: Uint8List.fromList([1]),
        pageCount: 1,
      );
      await store.pendingSaves;

      storage.writesLeft = 1; // the backup has three files
      await expectLater(store.restoreBackup(zip), throwsException);
      storage.writesLeft = null;

      expect(store.notes.single.title, 'Mine');
      expect(await store.readPdf(mine), [1, 2, 3]);
      expect(store.thumbnail(mine.id), [1]);
      // The backup's file that did get written is gone again.
      expect(await store.dataFileKeys(),
          unorderedEquals(['notes/${mine.id}.pdf', 'notes/${mine.id}.jpg']));
      // Saving carries on as before.
      store.addFolder('After', 0xFFA9CFF5);
      await store.pendingSaves;
      final saved = (await storage.readJson())!;
      expect(saved, contains('After'));
      expect(saved, contains('Mine'));
      expect(saved, isNot(contains('From Backup')));
    });

    test("a change made during a restore isn't saved over it", () async {
      final zip = await otherBackup();
      final storage = _SlowStorage();
      await store.init(storage);
      store.addFolder('Before', 0xFFA9CFF5);
      await store.pendingSaves;

      storage.gate = Completer<void>();
      final restoring = store.restoreBackup(zip);
      await pumpEventQueue(); // copying the backup's files
      final from = storage.jsonWrites.length;
      store.addFolder('During', 0xFFA9CFF5); // e.g. a Pomodoro ends
      await pumpEventQueue();
      storage.gate!.complete();
      await restoring;
      await store.pendingSaves;

      expect(
        storage.jsonWrites.skip(from).where((j) => j.contains('During')),
        isEmpty,
        reason: 'the data being replaced was written during the restore',
      );
      final names = store.folders.map((f) => f.name);
      expect(names, contains('Restored'));
      expect(names, isNot(contains('Before')));
      final saved = (await storage.readJson())!;
      expect(saved, contains('From Backup'));
      expect(saved, isNot(contains('Before')));
    });

    test("files of this device's data that the backup doesn't have are "
        'removed', () async {
      final zip = await otherBackup();
      await store.init(MemoryStorage());
      await store.addNote(
        title: 'Mine',
        folderId: store.folders.first.id,
        pdf: Uint8List.fromList([1]),
        thumbnail: Uint8List.fromList([1]),
        pageCount: 1,
      );
      await store.setProfilePhoto(Uint8List.fromList([5]));

      await store.restoreBackup(zip);
      final note = store.notes.single;
      final deck = store.sets.single;
      expect(note.title, 'From Backup');
      expect(await store.dataFileKeys(), unorderedEquals([
        note.pdfKey,
        note.thumbKey,
        deck.photoKey(0),
      ]));
      expect(store.profilePhoto, isNull); // the backup has none
    });
  });
}

/// Device storage that runs out of space after [writesLeft] more files
/// (no limit while null).
class _FullStorage extends MemoryStorage {
  int? writesLeft;

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final left = writesLeft;
    if (left != null) {
      if (left <= 0) throw Exception('No space left on device');
      writesLeft = left - 1;
    }
    await super.writeBytes(key, bytes);
  }
}

/// Device storage whose file writes wait for [gate] while it is set, and
/// that keeps every save file written.
class _SlowStorage extends MemoryStorage {
  Completer<void>? gate;
  final jsonWrites = <String>[];

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    await gate?.future;
    await super.writeBytes(key, bytes);
  }

  @override
  Future<void> writeJson(String json) async {
    jsonWrites.add(json);
    await super.writeJson(json);
  }
}
