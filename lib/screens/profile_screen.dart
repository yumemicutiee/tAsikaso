import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../services/drive_sync.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/profile_photo.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import 'actions.dart';
import 'settings_screen.dart' show SettingsSection;
import 'analysis_screen.dart';
import 'backup_screen.dart';
import 'help_screen.dart';
import 'plans_screen.dart';

/// Profile: photo and name (filled in from the Google account on sign-in,
/// changeable here), study stats and app settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Picks a photo from the gallery or the camera; null if the user backed
  /// out. Tests replace this.
  @visibleForTesting
  static Future<XFile?> Function(ImageSource source) pickPhoto =
      (source) => ImagePicker().pickImage(
            source: source,
            maxWidth: 1024,
            maxHeight: 1024,
          );

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return Column(
      children: [
        AppHeader(title: 'Profile', onSettings: () => openSettings(context)),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final name = store.prefs.userName.trim();
              final photo = store.profilePhoto;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Semantics(
                      button: true,
                      label: 'Change photo',
                      child: GestureDetector(
                        onTap: () => _editPhoto(context),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primarySoft,
                              backgroundImage:
                                  photo == null ? null : MemoryImage(photo),
                              child: photo != null
                                  ? null
                                  : name.isEmpty
                                      ? Icon(AppIcons.avatar,
                                          size: 40, color: AppColors.primaryDeep)
                                      : Text(
                                          name.characters.first.toUpperCase(),
                                          style: TextStyle(
                                            fontFamily: kHeadingFont,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryDeep,
                                          ),
                                        ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.background, width: 2),
                                ),
                                child: const Icon(AppIcons.capture,
                                    size: 14, color: AppColors.onFill),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _editName(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name.isEmpty ? 'Add Your Name' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(AppIcons.edit,
                              size: 16, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _StatBox(
                          value: '${store.streakDays}',
                          label: 'Day Streak',
                          color: AppColors.streakText),
                      const SizedBox(width: 12),
                      _StatBox(
                          value: '${store.notes.length}',
                          label: 'Notes',
                          color: AppColors.primaryDeep),
                      const SizedBox(width: 12),
                      _StatBox(
                          value: '${store.sets.length}',
                          label: 'Card Sets',
                          color: AppColors.primaryDeep),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PlusHero(
                    title: store.plan == null
                        ? kPlusName
                        : '$kPlusName ${store.plan!.title}',
                    subtitle: store.plan == null
                        ? 'Unlimited suggested cards, smart review, full '
                            'analysis history, colors and Google Drive sync.'
                        : store.subscription?.endsAt == null
                            ? 'All $kPlusName features are on.'
                            : 'All $kPlusName features are on, until '
                                '${formatNoteDate(store.subscription!.endsAt!)}.',
                    action: SizedBox(
                      height: 34,
                      child: FilledButton(
                        onPressed: () => openPlans(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.onFill,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                            store.plan == null ? 'See Plans' : 'Manage Plan',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Group(children: [
                    _row(AppIcons.chart, 'Pomodoro Analysis',
                        () => openAnalysis(context)),
                    _row(AppIcons.settings, 'Settings',
                        () => openSettings(context)),
                    _row(
                        AppIcons.notifications,
                        'Notifications & Reminders',
                        () => openSettings(context,
                            section: SettingsSection.notifications)),
                    _row(AppIcons.backup, 'Backup & Sync',
                        () => openBackup(context),
                        badge: store.isPlus ? null : 'Plus'),
                  ]),
                  const SizedBox(height: 16),
                  _Group(children: [
                    _row(AppIcons.help, 'Help & FAQ', () => openHelp(context)),
                  ]),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static Future<void> _editName(BuildContext context) async {
    final store = AppStore.instance;
    final name = await showTextInputDialog(
      context,
      title: 'Your Name',
      initial: store.prefs.userName,
      hint: 'Shown in greetings',
      allowEmpty: true, // clearing the name is allowed
    );
    if (name == null) return;
    store.updatePrefs(store.prefs.copyWith(userName: name.trim()));
  }

  /// Change or remove the profile photo.
  static Future<void> _editPhoto(BuildContext context) async {
    final store = AppStore.instance;
    final sync = DriveSync.instance;
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.gallery),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(context).pop(_PhotoChoice.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(AppIcons.capture),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.of(context).pop(_PhotoChoice.camera),
              ),
            if (sync.googlePhotoUrl != null)
              ListTile(
                leading: const Icon(AppIcons.backup),
                title: const Text('Use My Google Photo'),
                onTap: () => Navigator.of(context).pop(_PhotoChoice.google),
              ),
            if (store.profilePhoto != null)
              ListTile(
                leading: const Icon(AppIcons.delete, color: AppColors.streakRed),
                title: const Text('Remove Photo',
                    style: TextStyle(color: AppColors.streakRed)),
                onTap: () => Navigator.of(context).pop(_PhotoChoice.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void toast(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    switch (choice) {
      case _PhotoChoice.remove:
        await store.setProfilePhoto(null);
      case _PhotoChoice.google:
        if (!await sync.useGooglePhoto()) {
          toast("Couldn't get your Google photo. Check your connection and "
              'try again.');
        }
      case _PhotoChoice.gallery:
      case _PhotoChoice.camera:
        final source = choice == _PhotoChoice.gallery
            ? ImageSource.gallery
            : ImageSource.camera;
        final XFile? file;
        try {
          file = await pickPhoto(source);
        } catch (e) {
          debugPrint('Could not pick a photo: $e');
          toast(choice == _PhotoChoice.gallery
              ? "Couldn't open your gallery."
              : "Couldn't open the camera.");
          return;
        }
        if (file == null) return;
        final square = await compute(squarePhoto, await file.readAsBytes());
        if (square == null) {
          toast("That photo couldn't be read. Try another one.");
          return;
        }
        await store.setProfilePhoto(square);
    }
  }

  static Widget _row(IconData icon, String label, VoidCallback onTap,
          {String? badge}) =>
      ListTile(
        leading: Icon(icon, color: AppColors.ink, size: 22),
        title: Row(
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.itemTitle),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    )),
              ),
            ],
          ],
        ),
        trailing: Icon(AppIcons.chevronRight,
            color: AppColors.textMuted, size: 18),
        dense: true,
        onTap: onTap,
      );
}

enum _PhotoChoice { gallery, camera, google, remove }

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: AppText.statValue.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: AppText.itemMeta),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
