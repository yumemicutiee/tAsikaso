import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../services/account_data.dart';
import '../../services/accounts.dart';
import '../../services/drive_sync.dart';
import '../../services/study_ai.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../../widgets/brand_mark.dart';
import '../actions.dart';
import 'intro_slides.dart';

/// The first screen of a new install: sign up or log in with Google, or
/// carry on without an account (then the name to greet the user by). After
/// it come the slides about the app ([IntroSlides]), once.
///
/// It takes over from the loading screen where that ends, the name and the
/// full bar in the same place, then: the bar drops down the screen and the
/// buttons appear as it passes them, the tagline takes the bar's place,
/// "Welcome to" appears above the name, and a peek at the app (Today's
/// Focus, a note, a flashcard) pops out above and keeps floating.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  /// The cards keep floating after the intro (off in tests, which wait for
  /// the screen to stop moving).
  static bool floating = true;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Step { choose, name }

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  /// The intro, once: the bar dropping, then everything else appearing.
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  /// The cards floating, after the intro: periods of 4, 3 and 6 s.
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(seconds: 12));

  bool _started = false;
  final _store = AppStore.instance;
  final _sync = DriveSync.instance;
  final _name = TextEditingController();
  _Step _step = _Step.choose;
  bool _busy = false;
  String? _error;

  /// Signed in with Google: the name step only asks when Google gave none.
  bool _withGoogle = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _intro.value = 1;
      return;
    }
    _intro.forward().whenComplete(() {
      if (mounted && WelcomeScreen.floating) _float.repeat();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
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
        final reason = _sync.lastSignInProblem;
        _error = (error == null || error.isEmpty)
            ? "Google sign-in didn't finish. Try again, or continue without "
                'an account.${reason == null ? '' : '\n($reason)'}'
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
    // Without an account the student still gets a tAsikaso account (an
    // anonymous one, usually made on the first run already), so the admin
    // page has them, with this name; saved now in case it was only made here.
    if (!_withGoogle) unawaited(_recordAccount());
    FocusScope.of(context).unfocus();
    _finish();
  }

  static Future<void> _recordAccount() async {
    final accounts = Accounts.instance;
    if (!accounts.enabled || !StudyAi.usesAccounts) return;
    if (!accounts.hasSession && await accounts.token() == null) return;
    await AccountData.instance.save();
  }

  void _finish() {
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const IntroSlides(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  /// Milliseconds into the intro.
  double get _ms => _intro.value * 1600;

  /// 0 → 1 from [start] over [length] ms of the intro, eased.
  double _at(double start, double length, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_ms - start) / length).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGround,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: Listenable.merge([_intro, _float]),
            builder: (context, _) => _layout(context, box),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints box) {
    final h = box.maxHeight;
    final w = box.maxWidth;
    final naming = _step == _Step.name;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final centreTop = BrandMark.topIn(h);
    final barTop = centreTop + BrandMark.barOffset;

    // The bar drops from its place to below the screen in 600 ms, speeding
    // up; each button appears as the bar passes it.
    final drop = h - barTop + 24;
    final fall = (_ms / 600).clamp(0.0, 1.0);
    final barDrop = drop * fall * fall;
    final barOpacity = fall < 0.8 ? 1.0 : 1 - (fall - 0.8) / 0.2;
    double passed(double y) {
      final t = 600 * math.sqrt(((y - barTop) / drop).clamp(0.0, 1.0));
      return _at(t, 280);
    }

    final blockTop = h - 20 - 160; // about where "Continue with" starts
    final reveals = [passed(blockTop), passed(blockTop + 30), passed(blockTop + 128)];

    // The peek at the app: as big as the room above "Welcome to" allows.
    final room = centreTop - 12 - 46;
    final scale = math
        .min(1.0, math.min(room / _AppPeek.height, (w - 32) / _AppPeek.width))
        .clamp(0.35, 1.0);
    final seconds = _float.value * 12;
    double bob(double period) =>
        -3.5 * (1 - math.cos(2 * math.pi * seconds / period));

    // While the name is typed the name stays in the middle: of the screen,
    // or, with the keyboard up, of the room left above the name box.
    final formTop = h - 20 - keyboard - 230;
    final fitsInMiddle = centreTop + 110 + 16 <= formTop;
    final markTop = !naming || fitsInMiddle
        ? centreTop
        : ((formTop - 110) / 2).clamp(8.0, centreTop).toDouble();

    return Stack(
      children: [
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: naming ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: _AppPeek(
                scale: scale,
                pops: [_at(650, 450, Curves.linear), _at(800, 450, Curves.linear), _at(950, 450, Curves.linear)],
                floats: [bob(4), bob(3), bob(6)],
              ),
            ),
          ),
        ),
        Positioned(
          top: centreTop - 36,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: naming ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Opacity(
              opacity: _at(350, 300),
              child: Transform.translate(
                offset: Offset(0, (1 - _at(350, 300)) * -8),
                child: Text('Welcome to',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          top: markTop,
          left: 0,
          right: 0,
          child: Center(
            child: Semantics(
              label: kAppName,
              child: ExcludeSemantics(
                child: BrandMark(
                  barDrop: barDrop,
                  barOpacity: barOpacity,
                  tagline: _at(250, 300),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 20 + (naming ? keyboard : 0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: naming ? _askName() : _choose(reveals),
          ),
        ),
      ],
    );
  }

  Widget _choose(List<double> reveals) {
    // Each part appears (and can be tapped) once the dropping bar passes it.
    Widget appear(int i, Widget child) => IgnorePointer(
          ignoring: reveals[i] < 0.5,
          child: Opacity(
            opacity: reveals[i],
            child: Transform.translate(
                offset: Offset(0, (1 - reveals[i]) * 10), child: child),
          ),
        );
    return Column(
      key: const ValueKey('choose'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        appear(
          0,
          Text('Continue with',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 12),
        appear(
          1,
          Row(
            children: [
              Expanded(
                child: _ChoiceButton.google(
                  busy: _busy,
                  onPressed: _busy ? null : _google,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ChoiceButton.noAccount(
                  onPressed: _busy ? null : _withoutAccount,
                ),
              ),
            ],
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: AppColors.streakText)),
        ],
        const SizedBox(height: 14),
        appear(
          2,
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Google signs you up or logs you in. Your notes stay on your phone. ',
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
        ),
      ],
    );
  }

  Widget _askName() {
    final signedIn = _withGoogle ? _sync.email : null;
    return Column(
      key: const ValueKey('name'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What should we call you?',
            textAlign: TextAlign.center, style: AppText.sectionTitle),
        if (signedIn != null) ...[
          const SizedBox(height: 4),
          Text('Signed in as $signedIn',
              textAlign: TextAlign.center, style: AppText.statLabel),
        ],
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

/// A peek at the app: Today's Focus, a note whose text was found and a
/// flashcard, tilted on top of each other.
class _AppPeek extends StatelessWidget {
  const _AppPeek({
    required this.scale,
    this.pops = const [1, 1, 1],
    this.floats = const [0, 0, 0],
  });

  /// Each card popping out, 0 to 1, and how far up it has floated.
  final List<double> pops;
  final List<double> floats;

  /// Card [i] as it pops out (overshooting a little) and floats.
  Widget _animated(int i, Widget card) {
    final t = pops[i].clamp(0.0, 1.0);
    return Opacity(
      opacity: (t * 1.8).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, floats[i]),
        child: Transform.scale(
          scale: 0.4 + 0.6 * Curves.easeOutBack.transform(t),
          child: card,
        ),
      ),
    );
  }

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
                  child: _animated(0, Transform.rotate(
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
                  )),
                ),
                // A note, its text found.
                Positioned(
                  right: 4,
                  top: 64,
                  child: _animated(1, Transform.rotate(
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
                  )),
                ),
                // A flashcard.
                Positioned(
                  left: 34,
                  top: 188,
                  child: _animated(2, Transform.rotate(
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
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two big square choices under "Continue with": Google (the
/// "G" on white, as Google's sign-in branding asks), or no account.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton.google({required this.busy, required this.onPressed})
      : google = true;
  const _ChoiceButton.noAccount({required this.onPressed})
      : google = false,
        busy = false;

  final bool google;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final Color background;
    final Color foreground;
    final BorderSide side;
    if (google) {
      background = Colors.white;
      foreground = const Color(0xFF1F1F1F);
      side = dark ? BorderSide.none : BorderSide(color: AppColors.border, width: 1.2);
    } else if (dark) {
      background = const Color(0xFF181D2C);
      foreground = AppColors.ink;
      side = const BorderSide(color: Color(0xFF2F3850), width: 1.2);
    } else {
      background = AppColors.primarySoft;
      foreground = AppColors.heroTop;
      side = BorderSide.none;
    }
    final icon = google
        ? (busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Color(0xFF1E3A6E)),
              )
            : Image.asset('assets/brand/google_g.png', width: 24, height: 24))
        : Icon(AppIcons.profile, size: 26, color: dark ? const Color(0xFFA9D2F7) : AppColors.heroTop);
    return Semantics(
      button: true,
      label: google ? 'Continue with Google' : 'Continue without an account',
      excludeSemantics: true,
      child: SizedBox(
        height: 84,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background,
            disabledForegroundColor: foreground,
            side: side,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 8),
              Text(
                google ? (busy ? 'Signing in…' : 'Google') : 'No account',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
