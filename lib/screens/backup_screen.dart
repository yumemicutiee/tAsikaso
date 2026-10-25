import 'package:clock/clock.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_store.dart';
import '../data/backup.dart';
import '../data/plans.dart';
import '../data/pomodoro_controller.dart';
import '../services/drive_sync.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'plans_screen.dart';

Future<void> openBackup(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
    );

/// Keep everything in the user's Google Drive (sign in once, then it syncs
/// by itself), or back everything up to one file and restore it here or on
/// another phone.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  /// Hands the backup file to the phone's share sheet (or downloads it on
  /// the web). Returns false if the user backed out. Tests replace this.
  @visibleForTesting
  static Future<bool> Function(Uint8List bytes, String name) share = _share;

  /// Lets the user pick a backup file; null if they backed out. Tests
  /// replace this.
  @visibleForTesting
  static Future<Uint8List?> Function() pickFile = _pickFile;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

Future<bool> _share(Uint8List bytes, String name) async {
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'application/zip', name: name)],
    fileNameOverrides: [name],
    subject: '$kAppName backup',
    downloadFallbackEnabled: true,
  ));
  return result.status != ShareResultStatus.dismissed;
}

Future<Uint8List?> _pickFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (files.isEmpty) return null;
  return files.first.xFile.readAsBytes();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  final _sync = DriveSync.instance;

  /// [messenger] when it was looked up before a wait this screen may not
  /// outlive.
  void _toast(String text, [ScaffoldMessengerState? messenger]) {
    (messenger ?? ScaffoldMessenger.of(context))
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        showCloseIcon: true,
        duration: Duration(seconds: text.length > 60 ? 8 : 4),
      ));
  }

  // ---- Google Drive ------------------------------------------------------------

  Future<void> _signIn() async {
    final problem = await _sync.signIn();
    if (!mounted) return;
    if (problem != null) {
      if (problem.isNotEmpty) _toast(problem);
      return;
    }
    if (!_sync.isSignedIn) return;
    if (_sync.error case final problem? when _sync.lastSyncAt == null) {
      // Drive couldn't be checked, so it may hold another phone's data:
      // nothing goes up over it until the user can choose.
      _toast(problem);
      return;
    }
    final plus = AppStore.instance.isPlus;
    if (_sync.remote != null && _sync.lastSyncAt == null) {
      // This device hasn't synced before and Drive already holds data
      // (from another phone, or from before a reinstall). Getting it back
      // is free; uploading is tAsikaso+.
      await _offerRestore(canUpload: plus);
    } else if (plus) {
      await _syncNow();
    } else {
      _toast('Signed in as ${_sync.email}. ${DriveSync.needsPlusMessage}');
    }
  }

  Future<void> _offerRestore({required bool canUpload}) async {
    final saved = _sync.remote?.modifiedTime;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Your Data Is on Google Drive', style: AppText.sectionTitle),
        content: Text(
          'Google Drive has your folders, notes, flashcards and tasks'
          '${saved == null ? '' : ', saved ${formatAgo(saved, clock.now())}'}. '
          'Restore them to this device (replacing what is here now)'
          '${canUpload ? ", or keep this device's data and upload it to Drive instead?" : '?'}',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(canUpload ? 'Keep Mine' : 'Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onFill,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted || restore == null) return;
    if (restore) {
      await _restoreFromDrive(confirm: false);
    } else if (canUpload) {
      await _syncNow();
    }
  }

  Future<void> _syncNow() async {
    final problem = await _sync.syncNow(interactive: true);
    if (!mounted) return;
    _toast(problem ?? 'Synced with Google Drive.');
  }

  Future<void> _restoreFromDrive({bool confirm = true}) async {
    final navigator = Navigator.of(context);
    if (confirm) {
      final sure = await showConfirmDialog(
        context,
        title: 'Restore from Google Drive?',
        message: 'Everything on this device will be replaced by what is on '
            'Google Drive: folders, notes, flashcards, tasks, statistics and '
            'settings. This cannot be undone.',
        confirmLabel: 'Restore',
      );
      if (!sure || !mounted) return;
    }
    final problem = await _sync.restoreFromDrive();
    if (!mounted) return;
    if (problem != null) {
      _toast(problem);
      return;
    }
    PomodoroController.instance.restart();
    navigator.popUntil((route) => route.isFirst);
    _toast('Restored from Google Drive.');
  }

  Future<void> _signOut() async {
    await _sync.signOut();
    if (mounted) _toast('Signed out. Your data stays on Google Drive.');
  }

  // ---- Backup file -------------------------------------------------------------

  Future<void> _backUp() async {
    final store = AppStore.instance;
    if (!store.isPlus) {
      await showPlusPrompt(context, PlusFeature.backup);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await store.createBackup();
      final shared =
          await BackupScreen.share(bytes, backupFileName(clock.now()));
      if (shared) store.markBackedUp();
    } catch (e) {
      debugPrint('Backup failed: $e');
      if (mounted) _toast("The backup couldn't be made. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final store = AppStore.instance;
    final navigator = Navigator.of(context);
    // The restore can take a while, and this screen may be closed by the
    // time it's done; the app's messenger still says how it went.
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showConfirmDialog(
      context,
      title: 'Restore from Backup?',
      message: 'Everything on this device will be replaced by what is in the '
          'backup: folders, notes, flashcards, tasks, statistics and '
          'settings. This cannot be undone.',
      confirmLabel: 'Choose File',
    );
    if (!sure) return;
    final Uint8List? bytes;
    try {
      bytes = await BackupScreen.pickFile();
    } catch (e) {
      debugPrint('Could not pick a file: $e');
      if (mounted) _toast("Couldn't open that file.");
      return;
    }
    if (bytes == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await store.restoreBackup(bytes);
      PomodoroController.instance.restart();
      navigator.popUntil((route) => route.isFirst);
      _toast('Backup restored.', messenger);
    } on FormatException catch (e) {
      _toast(e.message, messenger);
    } catch (e) {
      debugPrint('Restore failed: $e');
      _toast("The backup couldn't be restored. Nothing was changed.",
          messenger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: subPageAppBar('Backup & Sync'),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, _sync]),
        builder: (context, _) {
          final last = store.prefs.lastBackupAt;
          final plus = store.isPlus;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Sign in with Google and everything, folders, notes, '
                'flashcards, tasks and statistics, is kept in your own Google '
                'Drive and comes back on any phone. You can also keep a backup '
                'file yourself.',
                style: AppText.itemMeta.copyWith(height: 1.4),
              ),
              if (!plus) ...[
                const SizedBox(height: 14),
                _PlusNote(
                  onTap: () => showPlusPrompt(context, PlusFeature.backup),
                ),
              ],
              const SizedBox(height: 20),
              _DriveCard(
                sync: _sync,
                plus: plus,
                onSignIn: _signIn,
                onSignOut: _signOut,
                onSyncNow: _syncNow,
                onRestore: () => _restoreFromDrive(),
                onPlans: () => openPlans(context),
              ),
              const SizedBox(height: 28),
              Text('Backup file', style: AppText.sectionTitle),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last backup', style: AppText.itemMeta),
                          const SizedBox(height: 2),
                          Text(
                            last == null
                                ? 'Never'
                                : formatAgo(last, clock.now()),
                            style: AppText.itemTitle,
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AccentButton(
                label: plus ? 'Back Up Now' : 'Back Up Now  ·  $kPlusName',
                onPressed: _busy ? null : _backUp,
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore from Backup'),
                ),
              ),
              const SizedBox(height: 16),
              Text('How the file works', style: AppText.sectionTitle),
              const SizedBox(height: 8),
              const _Step(
                1,
                kIsWeb
                    ? 'Back Up Now downloads one file with everything in it.'
                    : 'Back Up Now makes one file with everything in it and '
                        'opens the share sheet.',
              ),
              const _Step(
                2,
                kIsWeb
                    ? 'Keep the file somewhere safe, such as Google Drive.'
                    : 'Choose Google Drive to keep it in the cloud (or any '
                        'other place you like).',
              ),
              const _Step(
                3,
                'On a new phone, open this screen, tap Restore from Backup '
                'and pick the file.',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What's free and what's tAsikaso+ on this screen, for free accounts.
class _PlusNote extends StatelessWidget {
  const _PlusNote({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(AppIcons.locked, size: 18, color: AppColors.primaryDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Syncing to Google Drive and making backup files are part '
                  'of $kPlusName. Signing in and restoring what you already '
                  'saved are free.',
                  style: AppText.statLabel
                      .copyWith(height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google Drive sync: sign in, status, Sync Now, Restore, auto-sync.
/// Without tAsikaso+ ([plus] false) syncing is replaced by a way to the
/// plans; signing in and restoring still work.
class _DriveCard extends StatelessWidget {
  const _DriveCard({
    required this.sync,
    required this.plus,
    required this.onSignIn,
    required this.onSignOut,
    required this.onSyncNow,
    required this.onRestore,
    required this.onPlans,
  });

  final DriveSync sync;
  final bool plus;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onSyncNow;
  final VoidCallback onRestore;
  final VoidCallback onPlans;

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    final busy = sync.busy;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.backup, size: 20, color: AppColors.primaryDeep),
              const SizedBox(width: 8),
              Expanded(child: Text('Google Drive', style: AppText.sectionTitle)),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!sync.isSignedIn) ...[
            Text(
              'Sign in with your Google account. Your data is kept in a '
              'private folder of your Google Drive that only this app can '
              'see, and every change is uploaded by itself.',
              style: AppText.statLabel.copyWith(height: 1.4),
            ),
            const SizedBox(height: 14),
            AccentButton(
              label: 'Sign in with Google',
              onPressed: busy || !sync.isSupported ? null : onSignIn,
            ),
            if (!sync.isSupported) ...[
              const SizedBox(height: 6),
              Text('Works in the Android app and on the web.',
                  style: AppText.itemMeta),
            ],
          ] else ...[
            Text('Signed in as ${sync.email}', style: AppText.itemTitle),
            const SizedBox(height: 4),
            Text(
              !plus
                  ? 'Sync is paused: it comes with $kPlusName'
                  : sync.lastSyncAt == null
                      ? 'Not synced yet'
                      : 'Last synced ${formatAgo(sync.lastSyncAt!, now)}'
                          '${sync.hasUnsyncedChanges ? ' · changes waiting' : ''}',
              style: AppText.statLabel,
            ),
            if (sync.error case final error?) ...[
              const SizedBox(height: 6),
              Text(error,
                  style: AppText.statLabel.copyWith(color: AppColors.streakRed)),
            ],
            if (sync.remoteNewer) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Drive has newer data'
                      '${sync.remote?.modifiedTime == null ? '' : ' (saved ${formatAgo(sync.remote!.modifiedTime!, now)})'}, '
                      'from another device. Restore it here to catch up; '
                      "this device's data will be replaced.",
                      style: AppText.statLabel.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: busy ? null : onRestore,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onFill,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Restore It Here',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (plus) ...[
              AccentButton(
                  label: 'Sync Now', onPressed: busy ? null : onSyncNow),
              // The card already paints a background, so the tile mustn't.
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text('Sync automatically', style: AppText.itemTitle),
                  subtitle: Text(
                      'A little after each change, and when you leave the app.',
                      style: AppText.itemMeta),
                  value: sync.autoSync,
                  activeThumbColor: AppColors.primaryDeep,
                  onChanged: sync.setAutoSync,
                ),
              ),
            ] else
              AccentButton(label: 'See Plans to Sync', onPressed: onPlans),
            if (sync.remote != null && !sync.remoteNewer)
              Center(
                child: TextButton(
                  onPressed: busy ? null : onRestore,
                  child: const Text('Restore from Drive'),
                ),
              ),
            Center(
              child: TextButton(
                onPressed: busy ? null : onSignOut,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
                child: const Text('Sign Out'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDeep)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppText.itemMeta.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
