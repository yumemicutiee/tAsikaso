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
    final choice = await showModalBottomSheet<_NoAccountLogOut>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _KeepProgressSheet(),
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

/// Log Out without an account: "Save your progress first?". A picture of
/// what they would lose (a note, a flashcard, the streak), then Keep it
/// with Google, Not now, and the small Log out and delete everything.
class _KeepProgressSheet extends StatelessWidget {
  const _KeepProgressSheet();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final note = store.notes.isEmpty ? 'Your notes' : store.notes.first.title;
    final card = store.sets
        .expand((s) => s.cards)
        .map((c) => c.front.trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => 'Your flashcards');
    final streak = store.streakDays;
    final (big, small) = streak > 0
        ? ('$streak', 'day streak')
        : ('${store.notes.length}', store.notes.length == 1 ? 'note' : 'notes');
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What would be lost, drawn from their own things.
            ExcludeSemantics(
              child: Container(
                height: 190,
                color: AppColors.tint(AppColors.primary, 0.45),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 10,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDeep.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      height: 130,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 26,
                            child: Transform.rotate(
                              angle: -0.12,
                              child: _PeekCard(
                                width: 110,
                                color: AppColors.surface,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(note,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink)),
                                    for (final w in const [1.0, 0.7, 0.85])
                                      FractionallySizedBox(
                                        widthFactor: w,
                                        child: Container(
                                          margin: const EdgeInsets.only(top: 6),
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: AppColors.border,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 30,
                            child: Transform.rotate(
                              angle: 0.1,
                              child: _PeekCard(
                                width: 104,
                                color: const Color(0xFFF5B5C8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('FLASHCARD',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.6,
                                            color: Color(0xFF8A2B48))),
                                    const SizedBox(height: 6),
                                    Text(card,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF3C1020))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 75,
                            top: 0,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A6E),
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1E3A6E)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 22,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(big,
                                      style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white)),
                                  Text(small,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFCFE4FA))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Save your progress first?',
                      style: AppText.screenTitle.copyWith(fontSize: 23)),
                  const SizedBox(height: 10),
                  Text(
                    "Without an account you can't log back in, so logging "
                    'out deletes your notes, flashcards, tasks and streak '
                    'from this phone. Sign in with Google to keep them.',
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_NoAccountLogOut.google),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDeep,
                        foregroundColor: AppColors.onPrimaryDeep,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Image.asset('assets/brand/google_g.png',
                                width: 16, height: 16),
                          ),
                          const SizedBox(width: 10),
                          const Text('Keep it with Google',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        minimumSize: const Size.fromHeight(44)),
                    child: const Text('Not now',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_NoAccountLogOut.delete),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.streakRed),
                      child: const Text('Log out and delete everything',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.streakRed)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small tilted card in the sheet's picture.
class _PeekCard extends StatelessWidget {
  const _PeekCard(
      {required this.width, required this.color, required this.child});

  final double width;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3A6E).withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}
