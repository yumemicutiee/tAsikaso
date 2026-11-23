import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../services/drive_sync.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../../widgets/app_logo.dart';
import '../actions.dart';
import 'intro_slides.dart';

/// The first screen of a new install: sign up or log in with Google, or
/// carry on without an account (then the name to greet the user by). After
/// it come the slides about the app ([IntroSlides]), once.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Step { choose, name }

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _store = AppStore.instance;
  final _sync = DriveSync.instance;
  final _name = TextEditingController();
  _Step _step = _Step.choose;
  bool _busy = false;
  String? _error;

  /// Signed in with Google: the name step only asks when Google gave none.
  bool _withGoogle = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await _sync.signIn();
    if (!mounted) return;
    if (!_sync.isSignedIn) {
      setState(() {
        _busy = false;
        _error = (error == null || error.isEmpty)
            ? "Google sign-in didn't finish. Try again, or continue without "
                'an account.'
            : error;
      });
      return;
    }
    // A copy of this account's data on Google Drive: offer to bring it back.
    if (_sync.remote != null) {
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Welcome Back'),
          content: const Text('Your $kAppName data is on your Google Drive. '
              'Bring it back to this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Start Fresh'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bring It Back'),
            ),
          ],
        ),
      );
      if (restore == true) {
        final failed = await _sync.restoreFromDrive();
        if (!mounted) return;
        if (failed != null && failed.isNotEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failed)));
        }
      }
      if (!mounted) return;
    }
    setState(() {
      _busy = false;
      _withGoogle = true;
    });
    if (_store.prefs.userName.trim().isEmpty) {
      setState(() => _step = _Step.name);
    } else {
      _finish();
    }
  }

  void _withoutAccount() => setState(() {
        _error = null;
        _withGoogle = false;
        _name.text = _store.prefs.userName;
        _step = _Step.name;
      });

  void _saveName() {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      _store.updatePrefs(_store.prefs.copyWith(userName: name));
    }
    FocusScope.of(context).unfocus();
    _finish();
  }

  void _finish() {
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const IntroSlides(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 36),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const _Brand(),
                    const Spacer(),
                    const SizedBox(height: 28),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _step == _Step.choose ? _choose() : _askName(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choose() {
    return Column(
      key: const ValueKey('choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sign up or log in',
            textAlign: TextAlign.center, style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text('New to $kAppName? Your Google account signs you up.',
            textAlign: TextAlign.center, style: AppText.statLabel),
        const SizedBox(height: 16),
        _GoogleButton(busy: _busy, onPressed: _busy ? null : _google),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: AppColors.streakText)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: AppText.statLabel),
            ),
            Expanded(child: Divider(color: AppColors.divider)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 46,
          child: TextButton(
            onPressed: _busy ? null : _withoutAccount,
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryDeep),
            child: const Text('Continue without an account',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Your notes stay on your phone. ',
                  style: AppText.itemMeta.copyWith(fontSize: 11)),
              GestureDetector(
                onTap: () => openPrivacyPolicy(context),
                child: Text('Privacy Policy',
                    style: AppText.itemMeta.copyWith(
                        fontSize: 11,
                        color: AppColors.primaryDeep,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primaryDeep)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _askName() {
    final signedIn = _withGoogle ? _sync.email : null;
    return Column(
      key: const ValueKey('name'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What should we call you?',
            textAlign: TextAlign.center, style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text(
          signedIn != null
              ? 'Signed in as $signedIn'
              : 'For your greeting. You can change it later in Settings.',
          textAlign: TextAlign.center,
          style: AppText.statLabel,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 40,
          onSubmitted: (_) => _saveName(),
          decoration: const InputDecoration(
            hintText: 'Your name',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _saveName,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onFill,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        if (!_withGoogle) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => setState(() => _step = _Step.choose),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
              child: const Text('Back'),
            ),
          ),
        ],
      ],
    );
  }
}

/// The logo, the name and what the app is for.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppLogo(size: 104),
        const SizedBox(height: 14),
        Text(kAppName,
            style: TextStyle(
              fontFamily: kHeadingFont,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.ink,
            )),
        const SizedBox(height: 8),
        Text(
          'Focus with Pomodoro, snap your notes into text, '
          'and turn them into flashcards.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14, height: 1.45, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// "Continue with Google": the Google "G" on a white button, as Google's
/// sign-in branding asks.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.primaryDeep),
              )
            else
              Image.asset('assets/brand/google_g.png', width: 20, height: 20),
            const SizedBox(width: 12),
            Text(busy ? 'Signing in…' : 'Continue with Google',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
