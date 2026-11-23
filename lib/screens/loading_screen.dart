import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';

/// Opening the app: the loading screen while [load] reads the saved data,
/// shown for at least [minimum] (long enough for the name to be spelled out
/// and underlined), then the app.
/// [onReady] runs once the app is up.
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    required this.load,
    this.onReady,
    this.minimum = const Duration(milliseconds: 1400),
  });

  final Future<void> Function() load;
  final VoidCallback? onReady;
  final Duration minimum;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Before the saved settings are read: the phone's light or dark mode.
    AppColors.useDark(
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark);
    _start();
  }

  Future<void> _start() async {
    try {
      await Future.wait([
        widget.load(),
        Future<void>.delayed(widget.minimum),
      ]);
    } catch (e, st) {
      // The store reports its own problems; the app opens regardless.
      debugPrint('Starting up: $e\n$st');
    }
    if (!mounted) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady?.call());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      child: _ready
          ? const StudyApp(key: ValueKey('app'))
          : MaterialApp(
              key: const ValueKey('loading'),
              title: kAppName,
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: const LoadingScreen(),
            ),
    );
  }
}

/// The loading screen ("Wordmark Reveal"): the logo's plus pops in, the
/// letters of the name rise one by one, a sky line draws under them, then
/// it all fades and starts again while the app is still loading. With
/// animations turned off on the phone, it simply shows.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  static const tagline = 'Snap. Study. Recall.';

  /// One round of the animation.
  static const cycle = Duration(milliseconds: 2400);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LoadingScreen.cycle);

  static const _letters = 'tAsikaso';
  static const double _size = 50;

  /// Seconds into a round, as a fraction of it.
  static double _t(double ms) => ms / 2400;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = _t(1500); // all shown
      _c.stop();
    } else if (!_c.isAnimating) {
      // On the web the page's own loader already played the reveal: carry
      // on from the shown name instead of starting over.
      _c.value = kIsWeb ? _t(1500) : 0;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 → 1 between [from] and [to] ms, eased; and 1 → 0 at the end of the round.
  double _in(double from, double to) {
    final ms = _c.value * 2400;
    final fadeOut = ms < 2100 ? 1.0 : 1 - ((ms - 2100) / 300).clamp(0.0, 1.0);
    final t = ((ms - from) / (to - from)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t) * fadeOut;
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.isDark ? const Color(0xFFEEF0F7) : const Color(0xFF1E3A6E);
    final capital = AppColors.isDark ? const Color(0xFF9FCBF5) : const Color(0xFF4F80BF);
    final style = TextStyle(
      fontFamily: kHeadingFont,
      fontSize: _size,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      height: 1,
      color: ink,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Semantics(
        label: 'Loading $kAppName',
        child: ExcludeSemantics(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  // Large text on a small phone: the name shrinks to fit.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final plus = _in(0, 280);
                    final line = _in(620, 1200);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Opacity(
                              opacity: plus,
                              child: Transform.rotate(
                                angle: (1 - plus) * -1.57,
                                child: Transform.scale(
                                  scale: 0.3 + 0.7 * plus,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: CustomPaint(
                                        size: Size(26, 26), painter: _Plus()),
                                  ),
                                ),
                              ),
                            ),
                            for (var i = 0; i < _letters.length; i++)
                              Builder(builder: (context) {
                                final v = _in(120.0 + i * 70, 470.0 + i * 70);
                                return Opacity(
                                  opacity: v,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - v) * 16),
                                    child: Text(_letters[i],
                                        style: i == 1
                                            ? style.copyWith(color: capital)
                                            : style),
                                  ),
                                );
                              }),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.only(left: 30),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1,
                            child: Container(
                              width: 206 * line,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 72,
                child: SafeArea(
                  top: false,
                  child: Text(
                    LoadingScreen.tagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo's plus: two round-ended sky strokes.
class _Plus extends CustomPainter {
  const _Plus();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9FCBF5)
      ..strokeWidth = size.width * 0.23
      ..strokeCap = StrokeCap.round;
    final m = size.width * 0.12;
    canvas
      ..drawLine(Offset(size.width / 2, m), Offset(size.width / 2, size.height - m), paint)
      ..drawLine(Offset(m, size.height / 2), Offset(size.width - m, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(_Plus oldDelegate) => false;
}
