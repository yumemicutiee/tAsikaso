import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../services/drive_sync.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../../widgets/app_logo.dart';
import '../actions.dart';
import '../loading_screen.dart';
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
      setState(() => _busy = false);
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
        if (mounted) setState(() => _busy = true);
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
    final background =
        AppColors.isDark ? AppColors.background : const Color(0xFFF4F8FD);
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // The picture of the app shrinks on short screens.
            final scale = ((box.maxHeight - 470) / _AppPeek.height)
                .clamp(0.55, 1.0)
                .clamp(0.0, (box.maxWidth - 48) / _AppPeek.width);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 38),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header(),
                      // Out of the way while the name is typed.
                      if (_step == _Step.choose) ...[
                        const SizedBox(height: 10),
                        Center(child: _AppPeek(scale: scale)),
                      ],
                      const SizedBox(height: 10),
                      Text(LoadingScreen.tagline,
                          style: TextStyle(
                            fontFamily: kHeadingFont,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            height: 1.2,
                            color: AppColors.ink,
                          )),
                      const SizedBox(height: 8),
                      Text(
                        'Your timer, your class notes and your flashcards '
                        'in one place.',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _step == _Step.choose ? _choose() : _askName(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _choose() {
    return Column(
      key: const ValueKey('choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GoogleButton(busy: _busy, onPressed: _busy ? null : _google),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: AppColors.streakText)),
        ],
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
        const SizedBox(height: 4),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('New here? Google signs you up. Your notes stay on your phone. ',
                  textAlign: TextAlign.center,
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

/// The small logo and the name, top left.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppLogo(size: 34),
        const SizedBox(width: 8),
        Text(kAppName,
            style: TextStyle(
              fontFamily: kHeadingFont,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.ink,
            )),
      ],
    );
  }
}

/// A peek at the app: Today's Focus, a note whose text was found and a
/// flashcard, tilted on top of each other.
class _AppPeek extends StatelessWidget {
  const _AppPeek({required this.scale});

  static const double width = 342;
  static const double height = 370;

  final double scale;

  static const _deg = 3.14159265 / 180;

  List<BoxShadow> get _shadow => [
        BoxShadow(
          color: const Color(0xFF1E3A6E).withValues(alpha: AppColors.isDark ? 0.4 : 0.13),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final card = dark ? AppColors.raised : Colors.white;
    final lineBlue = dark ? const Color(0xFF2A4470) : const Color(0xFFCFE4FA);
    final lineGrey = AppColors.thumbnail;
    Widget line(double w, Color c, {double top = 8}) => Padding(
          padding: EdgeInsets.only(top: top),
          child: FractionallySizedBox(
            widthFactor: w,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        width: width * scale,
        height: height * scale,
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Today's Focus.
                Positioned(
                  left: 8,
                  top: 24,
                  child: Transform.rotate(
                    angle: -6 * _deg,
                    child: Container(
                      width: 210,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _shadow,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: 0.8,
                                  strokeWidth: 7,
                                  strokeCap: StrokeCap.round,
                                  color: AppColors.primary,
                                  backgroundColor: AppColors.primarySoft,
                                ),
                                Center(
                                  child: Text('80%',
                                      style: TextStyle(
                                        fontFamily: kHeadingFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryDeep,
                                      )),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Today's Focus",
                                    style: TextStyle(
                                      fontFamily: kHeadingFont,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    )),
                                const SizedBox(height: 3),
                                Text('120 of 150 min',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // A note, its text found.
                Positioned(
                  right: 4,
                  top: 64,
                  child: Transform.rotate(
                    angle: 5 * _deg,
                    child: Container(
                      width: 170,
                      height: 216,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _shadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Photosynthesis',
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              )),
                          line(0.92, lineBlue, top: 12),
                          line(0.78, lineBlue),
                          line(0.86, lineBlue),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: dark
                                  ? const Color(0xFF1F3B2E)
                                  : const Color(0xFFD4EEE0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('Text found',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: dark
                                      ? const Color(0xFFA8DCC1)
                                      : const Color(0xFF2C6B4C),
                                )),
                          ),
                          line(0.70, lineGrey, top: 14),
                          line(0.90, lineGrey),
                          line(0.60, lineGrey),
                        ],
                      ),
                    ),
                  ),
                ),
                // A flashcard.
                Positioned(
                  left: 34,
                  top: 188,
                  child: Transform.rotate(
                    angle: -2 * _deg,
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      decoration: BoxDecoration(
                        color: AppColors.heroTop,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _shadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('FLASHCARD',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                color: Color(0xFFA9D2F7),
                              )),
                          const SizedBox(height: 8),
                          const Text('Where does photosynthesis happen?',
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                color: Colors.white,
                              )),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('Show Answer',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onFill,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.isDark ? AppColors.raised : Colors.white,
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
