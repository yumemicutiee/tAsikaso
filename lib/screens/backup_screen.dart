import 'package:clock/clock.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_store.dart';
import '../data/backup.dart';
import '../data/pomodoro_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

Future<void> openBackup(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
    );

/// Back everything up to one file (to Google Drive, say) and restore it
/// here or on another phone.
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

  Future<void> _backUp() async {
    final store = AppStore.instance;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await store.createBackup();
      final shared =
          await BackupScreen.share(bytes, backupFileName(clock.now()));
      if (shared) store.markBackedUp();
    } catch (e) {
      debugPrint('Backup failed: $e');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("The backup couldn't be made. Please try again.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final store = AppStore.instance;
    final navigator = Navigator.of(context);
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
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that file.")));
      return;
    }
    if (bytes == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await store.restoreBackup(bytes);
      PomodoroController.instance.restart();
      navigator.popUntil((route) => route.isFirst);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } on FormatException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('Restore failed: $e');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("The backup couldn't be restored. Nothing was "
                'changed.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: subPageAppBar('Backup & Restore'),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final last = store.prefs.lastBackupAt;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Keep a copy of everything, folders, notes, flashcards, tasks '
                'and statistics, in one file. Save it to Google Drive to keep '
                'it safe, and restore it here or on another phone.',
                style: AppText.itemMeta.copyWith(height: 1.4),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 16),
              AccentButton(
                label: 'Back Up Now',
                onPressed: _busy ? null : _backUp,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore from Backup'),
                ),
              ),
              const SizedBox(height: 24),
              Text('How it works', style: AppText.sectionTitle),
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
                    ? 'Upload the file to Google Drive to keep it safe.'
                    : 'Choose Google Drive to keep it in the cloud (or any '
                        'other place you like).',
              ),
              const _Step(
                3,
                'On a new phone, open this screen, tap Restore from Backup '
                'and pick the file.',
              ),
              const SizedBox(height: 16),
              Text(
                'Automatic sync between devices is coming later; for now, '
                'back up after big changes.',
                style: AppText.itemMeta,
              ),
            ],
          );
        },
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
