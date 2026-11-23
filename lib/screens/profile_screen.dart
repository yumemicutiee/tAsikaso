import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../services/account_data.dart';
import '../services/accounts.dart';
import '../services/drive_sync.dart';
import '../services/notification_service.dart';
import '../services/study_ai.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/profile_photo.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import 'actions.dart';
import 'analysis_screen.dart';
import 'backup_screen.dart';
import 'help_screen.dart';
import 'plans_screen.dart';
import 'welcome/welcome_screen.dart';

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
                    _row(AppIcons.backup, 'Backup & Sync',
                        () => openBackup(context),
                        badge: store.isPlus ? null : 'Plus'),
                    _row(AppIcons.help, 'Help & FAQ', () => openHelp(context)),
                    _row(AppIcons.signOut, 'Log Out', () => _logOut(context)),
                  ]),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Logs out and goes back to the welcome screen.
  ///
  /// With a Google account: the account's data (name, photo, preferences,
  /// Pomodoro settings, tasks and statistics) is saved to the account,
  /// then cleared from this phone along with the plan copy; Continue with
  /// Google brings it all back, here or on another phone. Notes, flashcards
  /// and their pages stay on this phone (Google Drive keeps them with
  /// Backup & Sync).
  ///
  /// Without one there's nothing to log back in to: [_logOutWithoutAccount]
  /// warns, offers Google sign-in, and otherwise deletes everything.
  static Future<void> _logOut(BuildContext context) async {
    final sync = DriveSync.instance;
    if (!sync.isSignedIn) return _logOutWithoutAccount(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final store = AppStore.instance;
    final account = Accounts.instance;
    final withAccount =
        sync.isSignedIn && account.enabled && account.hasSession && !account.isAnonymous;
    final sure = await showConfirmDialog(
      context,
      title: 'Log Out?',
      message: withAccount
          ? 'Your name, photo, settings, tasks and Pomodoro statistics are '
              'saved to your account (${sync.email}), then cleared from this '
              'phone. Continue with Google to get them back, here or on '
              'another phone. Your notes and flashcards stay on this phone.'
          : "You'll be signed out of Google (${sync.email}) and go back "
              'to the welcome screen. Your notes, flashcards and tasks '
              'stay on this phone.',
      confirmLabel: 'Log Out',
      danger: false,
    );
    if (!sure || !context.mounted) return;
    if (withAccount && !await AccountData.instance.save()) {
      if (!context.mounted) return;
      final anyway = await showConfirmDialog(
        context,
        title: "Couldn't Save to Your Account",
        message: 'Check your internet connection. If you log out now, '
            'changes since your last save stay only on this phone and are '
            'cleared from it.',
        confirmLabel: 'Log Out Anyway',
      );
      if (!anyway) return;
    }
    if (sync.isSignedIn) await sync.signOut();
    if (withAccount) {
      PomodoroController.instance.restart();
      await NotificationService.cancelTimerEnd();
      await NotificationService.setDailyReminder(null);
      await store.resetAccountData();
      messenger.hideCurrentSnackBar();
    } else if (store.prefs.profilePhotoUrl.isNotEmpty) {
      await store.setProfilePhoto(null);
    }
    store.updatePrefs(store.prefs.copyWith(userName: '', welcomed: false));
    navigator.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const WelcomeScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (_) => false,
    );
  }

  /// Log Out without an account: there is no account to log back in to,
  /// so logging out deletes everything on this phone. Warns first, and
  /// offers Google sign-in to keep it all instead.
  static Future<void> _logOutWithoutAccount(BuildContext context) async {
    final sync = DriveSync.instance;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<_NoAccountLogOut>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AppIcons.warning, size: 32, color: AppColors.streakRed),
        title: Text("You Can't Log Back In", style: AppText.sectionTitle),
        content: const Text(
          "You're using $kAppName without an account, so there's nothing to "
          'log back in to. Logging out deletes everything on this phone: '
          'your notes, flashcards, tasks, Pomodoro statistics and settings.'
          '\n\nSign in with Google to keep them in an account.',
          style: TextStyle(height: 1.4),
        ),
        actionsOverflowDirection: VerticalDirection.up,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_NoAccountLogOut.delete),
            style: TextButton.styleFrom(foregroundColor: AppColors.streakRed),
            child: const Text('Log Out and Delete'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_NoAccountLogOut.google),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onFill,
            ),
            child: const Text('Sign In with Google'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == _NoAccountLogOut.google) {
      final error = await sync.signIn();
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(sync.isSignedIn
              ? 'Signed in as ${sync.email}. Your notes and progress are kept.'
              : (error == null || error.isEmpty)
                  ? "Google sign-in didn't finish. Nothing was deleted."
                  : error),
          showCloseIcon: true,
        ));
      return;
    }

    // Log Out and Delete: the timer and reminders stop, the account kept
    // for this phone (plan, Smart Study use) goes, then everything here.
    final store = AppStore.instance;
    final account = Accounts.instance;
    PomodoroController.instance.restart();
    await NotificationService.cancelTimerEnd();
    await NotificationService.setDailyReminder(null);
    if (account.enabled && account.hasSession) {
      try {
        await StudyAi.deleteAccount();
      } catch (e) {
        debugPrint('Account not deleted at Log Out: $e');
      }
      await account.signOut();
    }
    await store.eraseEverything();
    store.applyServerPlan(null);
    store.updatePrefs(store.prefs.copyWith(userName: '', welcomed: false));
    messenger.hideCurrentSnackBar();
    navigator.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const WelcomeScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (_) => false,
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

/// What the user chose when logging out without an account.
enum _NoAccountLogOut { google, delete }
