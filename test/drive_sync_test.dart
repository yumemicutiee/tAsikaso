import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:study_app/data/app_store.dart';
import 'package:study_app/data/plans.dart';
import 'package:study_app/data/storage/local_storage_memory.dart';
import 'package:study_app/screens/backup_screen.dart';
import 'package:study_app/screens/profile_screen.dart';
import 'package:study_app/services/drive_store.dart';
import 'package:study_app/services/drive_sync.dart';
import 'package:study_app/theme/app_colors.dart';
import 'package:study_app/utils/profile_photo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = AppStore.instance;
  final sync = DriveSync.instance;
  late MemoryDriveStore drive;
  final bytes = Uint8List.fromList(List.generate(64, (i) => i));

  setUp(() async {
    AppColors.useDark(false);
    AppColors.usePalette(Palette.navy);
    store.resetForTesting();
    store.startPlan(PlusPlan.yearly); // syncing to Drive is tAsikaso+
    drive = MemoryDriveStore();
    DriveSync.debugStore = drive;
    await sync.resetForTesting();
  });

  tearDown(() async {
    await sync.resetForTesting();
    DriveSync.debugStore = null;
    DriveSync.debugFetchPhoto = null;
  });

  group('Profile from the Google account', () {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));

    test('fills in an empty name and the photo, never the user\'s own', () async {
      drive.name = 'Eugene Custodio';
      drive.photoUrl = 'https://lh3.googleusercontent.com/a/abc=s96-c';
      final fetched = <String>[];
      DriveSync.debugFetchPhoto = (url) async {
        fetched.add(url);
        return jpeg;
      };

      await sync.debugSignIn();
      expect(store.prefs.userName, 'Eugene Custodio');
      expect(store.profilePhoto, jpeg);
      expect(store.prefs.profilePhotoUrl, drive.photoUrl);
      expect(sync.googlePhotoUrl, drive.photoUrl);
      expect(fetched, [drive.photoUrl]);

      // The same photo again: no new download.
      await sync.debugSignIn();
      expect(fetched.length, 1);

      // The user's own name and photo are left alone, even if Google's change.
      store.updatePrefs(store.prefs.copyWith(userName: 'Gene'));
      final own = Uint8List.fromList([1, 2, 3]);
      await store.setProfilePhoto(own);
      expect(store.prefs.profilePhotoUrl, '');
      drive.photoUrl = 'https://lh3.googleusercontent.com/a/new=s96-c';
      await sync.debugSignIn();
      expect(store.prefs.userName, 'Gene');
      expect(store.profilePhoto, own);
      expect(fetched.length, 1);

      // "Use my Google photo" brings it back on purpose.
      expect(await sync.useGooglePhoto(), isTrue);
      expect(store.profilePhoto, jpeg);
      expect(fetched.length, 2);

      // With no photo, a (new) Google photo is taken again.
      await store.setProfilePhoto(null);
      await sync.debugSignIn();
      expect(store.profilePhoto, jpeg);
      expect(fetched.length, 3);
    });

    test('a Google photo link is asked for at the profile size', () {
      expect(googlePhotoAtSize('https://x/a/abc=s96-c', 256), 'https://x/a/abc=s256-c');
      expect(googlePhotoAtSize('https://x/a/abc=s96', 256), 'https://x/a/abc=s256');
      expect(googlePhotoAtSize('https://x/-/s64-c/photo.jpg', 256), 'https://x/-/s256-c/photo.jpg');
      expect(googlePhotoAtSize('https://x/photo.png', 256), 'https://x/photo.png');
    });

    test('squarePhoto makes a square JPEG and refuses junk', () {
      final wide = img.encodePng(img.Image(width: 40, height: 20));
      final out = squarePhoto(Uint8List.fromList(wide))!;
      final decoded = img.decodeImage(out)!;
      expect((decoded.width, decoded.height), (profilePhotoSize, profilePhotoSize));
      expect(squarePhoto(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('the photo travels in backups and in Drive sync', () async {
      await store.setProfilePhoto(jpeg);
      final zip = await store.createBackup();
      store.resetForTesting();
      expect(store.profilePhoto, isNull);
      await store.restoreBackup(zip);
      expect(store.profilePhoto, jpeg);

      // resetForTesting above was a fresh device: no plan, so start one.
      store.startPlan(PlusPlan.yearly);
      await sync.debugSignIn();
      await sync.syncNow();
      expect(drive.byName.keys, contains('profile__photo.jpg'));

      await store.setProfilePhoto(null);
      await sync.syncNow();
      expect(drive.byName.keys, isNot(contains('profile__photo.jpg')));
    });

    testWidgets('Profile shows the photo and can remove it', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await store.setProfilePhoto(jpeg);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProfileScreen())));
      await tester.pump();
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
      expect(avatar.backgroundImage, isNotNull);

      await tester.tap(find.bySemanticsLabel('Change photo'));
      await tester.pumpAndSettle();
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Use My Google Photo'), findsNothing); // not signed in
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      expect(store.profilePhoto, isNull);
      expect(store.prefs.profilePhotoUrl, '');
    });
  });

  test('file names on Drive carry the key without slashes', () {
    expect(DriveSync.remoteName('notes/ab.pdf'), 'notes__ab.pdf');
    expect(DriveSync.localKey('notes__ab.pdf'), 'notes/ab.pdf');
    expect(DriveSync.localKey('sets__s1__0.jpg'), 'sets/s1/0.jpg');
    expect(DriveSync.localKey('data.json'), isNull);
    expect(DriveSync.localKey('something-else.txt'), isNull);
  });

  test('syncing uploads everything once, then only what changed', () async {
    final folder = store.folders.first;
    final note = await store.addNote(
      title: 'Cells',
      folderId: folder.id,
      pdf: bytes,
      thumbnail: bytes,
      pageCount: 1,
    );
    await store.addSet(title: 'Set', folderId: folder.id, photos: [bytes]);

    await sync.debugSignIn();
    expect(sync.isSignedIn, isTrue);
    expect(sync.remote, isNull); // nothing on Drive yet

    expect(await sync.syncNow(), isNull);
    final names = drive.byName.keys.toSet();
    expect(names, contains('data.json'));
    expect(names, contains('notes__${note.id}.pdf'));
    expect(names, contains('notes__${note.id}.jpg'));
    expect(names.where((n) => n.startsWith('sets__')).length, 1);
    expect(drive.uploads, 4);
    expect(sync.lastSyncAt, isNotNull);
    expect(sync.remote, isNotNull);
    expect(sync.remoteNewer, isFalse);

    // Nothing changed: nothing is uploaded again.
    await sync.syncNow();
    expect(drive.uploads, 4);

    // A change marks the device dirty; the next sync sends data.json only.
    store.updatePrefs(store.prefs.copyWith(userName: 'Ana'));
    expect(sync.hasUnsyncedChanges, isTrue);
    await sync.syncNow();
    expect(drive.uploads, 5);
    expect(utf8.decode(drive.byName['data.json']!), contains('Ana'));
    expect(sync.hasUnsyncedChanges, isFalse);

    // Deleting the note removes its files from Drive.
    await store.deleteNote(note.id);
    await sync.syncNow();
    expect(drive.deletes, 2);
    expect(drive.byName.keys.where((n) => n.startsWith('notes__')), isEmpty);
  });

  test('a new device sees the data on Drive and can restore it', () async {
    final folder = store.folders.first;
    await store.addSet(title: 'From phone A', folderId: folder.id, photos: [bytes]);
    store.updatePrefs(store.prefs.copyWith(userName: 'Ana'));
    await sync.debugSignIn();
    await sync.syncNow();

    // Phone B: fresh store, same Drive.
    store.resetForTesting();
    await sync.resetForTesting();
    expect(store.sets, isEmpty);
    await sync.debugSignIn();
    expect(sync.remote, isNotNull);
    expect(sync.lastSyncAt, isNull);
    expect(sync.remoteNewer, isTrue);

    expect(await sync.restoreFromDrive(), isNull);
    expect(store.sets.single.title, 'From phone A');
    expect(store.prefs.userName, 'Ana');
    expect(await store.readSetPhoto(store.sets.single, 0), bytes);
    expect(sync.remoteNewer, isFalse);
    expect(sync.hasUnsyncedChanges, isFalse);
  });

  test('signing out and Delete All Data keep the copy on Drive', () async {
    await sync.debugSignIn();
    await sync.syncNow();
    expect(drive.byName.containsKey('data.json'), isTrue);

    await sync.signOut();
    expect(sync.isSignedIn, isFalse);
    expect(drive.byName.containsKey('data.json'), isTrue);

    await sync.debugSignIn();
    await store.eraseEverything();
    expect(sync.isSignedIn, isFalse, reason: 'erasing forgets the account');
    expect(drive.byName.containsKey('data.json'), isTrue);
    expect(drive.deletes, 0);
  });

  test('without Drive, a sync says to sign in', () async {
    expect(await sync.syncNow(), 'Sign in with Google first.');
  });

  test('a change made during an upload is still to be synced', () async {
    final gated = _GatedDriveStore();
    DriveSync.debugStore = gated;
    await sync.debugSignIn();
    expect(await sync.syncNow(), isNull);

    store.updatePrefs(store.prefs.copyWith(userName: 'Ana'));
    gated.gate = Completer<void>();
    final uploading = sync.syncNow();
    await pumpEventQueue(); // waiting on Drive
    store.updatePrefs(store.prefs.copyWith(userName: 'Ben'));
    gated.gate!.complete();
    expect(await uploading, isNull);
    expect(utf8.decode(gated.byName['data.json']!), contains('Ana'));
    expect(sync.hasUnsyncedChanges, isTrue, reason: 'Ben is not on Drive yet');

    gated.gate = null;
    expect(await sync.syncNow(), isNull);
    expect(utf8.decode(gated.byName['data.json']!), contains('Ben'));
    expect(sync.hasUnsyncedChanges, isFalse);
  });

  test('a restore asked for during an upload waits for it, then restores',
      () async {
    final gated = _GatedDriveStore();
    DriveSync.debugStore = gated;
    store.addFolder('On Drive', 0xFFA9CFF5);
    await sync.debugSignIn();
    expect(await sync.syncNow(), isNull);

    // An automatic upload of a later change fails...
    store.addFolder('Only Here', 0xFFA9CFF5);
    gated
      ..gate = Completer<void>()
      ..failNext = true;
    final uploading = sync.syncNow();
    await pumpEventQueue();
    // ...while the user taps Restore from Google Drive.
    final restoring = sync.restoreFromDrive();
    gated.gate!.complete();
    expect(await uploading, isNotNull);
    expect(await restoring, isNull);
    expect(store.folders.any((f) => f.name == 'On Drive'), isTrue);
    expect(store.folders.any((f) => f.name == 'Only Here'), isFalse);
  });

  test("an automatic sync on a device that never synced leaves Drive's data "
      'alone until the user chooses', () async {
    final folder = store.folders.first;
    await store.addSet(title: 'From phone A', folderId: folder.id, photos: [bytes]);
    await sync.debugSignIn();
    expect(await sync.syncNow(), isNull);
    final onDrive = Map.of(drive.byName);
    final uploads = drive.uploads;

    // Phone B signs in. A change there syncs by itself later (or when the
    // app is hidden), before the user answers "Restore or Keep Mine?".
    store.resetForTesting();
    await sync.resetForTesting();
    store.startPlan(PlusPlan.yearly);
    await sync.debugSignIn();
    store.updatePrefs(store.prefs.copyWith(userName: 'Ben'));
    expect(await sync.syncNow(), isNotNull);
    expect(drive.uploads, uploads);
    expect(drive.deletes, 0);
    expect(drive.byName.keys, onDrive.keys);

    // Keep Mine replaces it, as asked.
    expect(await sync.syncNow(interactive: true), isNull);
    expect(utf8.decode(drive.byName['data.json']!), contains('Ben'));
    // From then on syncing is automatic again.
    store.updatePrefs(store.prefs.copyWith(userName: 'Ben B'));
    expect(await sync.syncNow(), isNull);
    expect(utf8.decode(drive.byName['data.json']!), contains('Ben B'));
  });

  test('a sync running during Delete All Data leaves the copy on Drive',
      () async {
    final storage = _GatedStorage();
    await store.init(storage);
    store.startPlan(PlusPlan.yearly);
    await store.addNote(
      title: 'Cells',
      folderId: store.folders.first.id,
      pdf: bytes,
      thumbnail: bytes,
      pageCount: 1,
    );
    await sync.debugSignIn();
    expect(await sync.syncNow(), isNull);
    final onDrive = drive.byName.keys.toSet();
    expect(onDrive.where((n) => n.startsWith('notes__')).length, 2);

    // A change starts an upload, which is about to list this device's
    // files...
    store.updatePrefs(store.prefs.copyWith(userName: 'Ana'));
    storage.listGate = Completer<void>();
    final uploading = sync.syncNow();
    await pumpEventQueue();
    // ...when Delete All Data has removed the notes but not the rest yet.
    storage.deleteGate = Completer<void>();
    final erasing = store.eraseEverything();
    await pumpEventQueue();
    storage.listGate!.complete();
    await uploading;
    storage.deleteGate!.complete();
    await erasing;

    expect(drive.deletes, 0);
    expect(drive.byName.keys.toSet(), containsAll(onDrive));
    expect(sync.isSignedIn, isFalse);
  });

  test("an upload that stops halfway doesn't leave data.json naming files "
      'that are not on Drive', () async {
    final gated = _GatedDriveStore();
    DriveSync.debugStore = gated;
    await sync.debugSignIn();
    expect(await sync.syncNow(), isNull);
    final before = utf8.decode(gated.byName['data.json']!);

    final note = await store.addNote(
      title: 'Cells',
      folderId: store.folders.first.id,
      pdf: bytes,
      thumbnail: bytes,
      pageCount: 1,
    );
    gated.fileUploadsLeft = 1; // the connection drops after the PDF
    expect(await sync.syncNow(), isNotNull);
    expect(utf8.decode(gated.byName['data.json']!), before);

    gated.fileUploadsLeft = null;
    expect(await sync.syncNow(), isNull);
    expect(utf8.decode(gated.byName['data.json']!), contains(note.id));
    expect(gated.byName.keys,
        containsAll(['notes__${note.id}.pdf', 'notes__${note.id}.jpg']));
  });

  testWidgets('Backup & Sync: sign in, first sync, status', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: BackupScreen()));
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Back Up Now'), findsOneWidget);

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as student@example.com'), findsOneWidget);
    expect(find.text('Synced with Google Drive.'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
    expect(find.text('Sync automatically'), findsOneWidget);
    expect(drive.byName.containsKey('data.json'), isTrue);

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}

/// Drive whose `data.json` uploads wait for [gate] while it is set, and
/// fail once after [failNext]; other files fail once [fileUploadsLeft]
/// (no limit while null) is used up.
class _GatedDriveStore extends MemoryDriveStore {
  Completer<void>? gate;
  bool failNext = false;
  int? fileUploadsLeft;

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes,
      {String? replaceId}) async {
    if (name == DriveSync.dataName) {
      await gate?.future;
      if (failNext) {
        failNext = false;
        throw Exception('Connection reset');
      }
    } else if (fileUploadsLeft case final left?) {
      if (left <= 0) throw Exception('Connection reset');
      fileUploadsLeft = left - 1;
    }
    return super.upload(name, bytes, replaceId: replaceId);
  }
}

/// Device storage on which listing `notes/` waits for [listGate] and
/// removing `sets/` for [deleteGate] while they are set, so a sync and
/// Delete All Data can be caught halfway.
class _GatedStorage extends MemoryStorage {
  Completer<void>? listGate;
  Completer<void>? deleteGate;

  @override
  Future<List<String>> list(String prefix) async {
    if (prefix == 'notes/') await listGate?.future;
    return super.list(prefix);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    if (prefix == 'sets/') await deleteGate?.future;
    await super.deletePrefix(prefix);
  }
}
