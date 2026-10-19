import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../models/models.dart';
import '../services/screen_awake.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Full-screen, distraction-free view of the running Pomodoro.
///
/// Opened from START with a circle that grows out of the button
/// ([openFocusScreen]); closing shrinks it back.
class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  static Color get _bg => AppColors.heroTop; // navy
  static Color get _bgDark => AppColors.heroBottom;

  static const _focusLines = [
    'Focus on the process,',
    'One step at a time,',
    'Keep going,',
    "You've got this,",
  ];

  @override
  Widget build(BuildContext context) {
    final timer = PomodoroController.instance;
    final store = AppStore.instance;

    final page = _KeepAwake(
      enabled: store.prefs.keepScreenOn,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _bg,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bg, _bgDark],
              ),
            ),
            child: Stack(
              children: [
                // Soft bubbles drifting up behind everything.
                if (store.prefs.focusBubbles)
                  const Positioned.fill(child: _Bubbles()),
                SafeArea(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([timer, store]),
                    builder: (context, _) {
                      final name = store.prefs.userName.trim();
                      final task = store.currentTask?.title;
                      final line = timer.isFocus
                          ? _focusLines[(timer.session - 1) % _focusLines.length]
                          : 'Time for a breather,';

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          children: [
                            // Task pill + close
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      timer.isFocus
                                          ? (task ?? 'Focus session')
                                          : timer.mode.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Close Focus Mode',
                                    child: Material(
                                      color: Colors.white,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => Navigator.of(context).pop(),
                                        child: const SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: Icon(AppIcons.close,
                                              size: 16, color: AppColors.onFill),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(flex: 2),
                            Text(
                              line,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              name.isEmpty ? 'you!' : '$name!',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                                height: 1.2,
                              ),
                            ),
                            const Spacer(),
                            FittedBox(
                              child: Text(
                                timer.timeText,
                                style: const TextStyle(
                                  fontFamily: kHeadingFont,
                                  fontSize: 88,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                  color: Colors.white,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 90,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _TickDialPainter(
                                  progress: timer.progress,
                                  accent: AppColors.primary,
                                ),
                              ),
                            ),
                            const Spacer(flex: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _RoundButton(
                                  icon: AppIcons.reset,
                                  label: 'Reset',
                                  onTap: timer.atStart ? null : timer.reset,
                                ),
                                const SizedBox(width: 20),
                                _RoundButton(
                                  icon: timer.running ? AppIcons.pause : AppIcons.start,
                                  label: timer.running
                                      ? 'Pause'
                                      : (timer.atStart ? 'Start' : 'Resume'),
                                  big: true,
                                  onTap: timer.toggle,
                                ),
                                const SizedBox(width: 20),
                                _RoundButton(
                                  icon: AppIcons.skip,
                                  label: timer.isFocus ? 'Skip to Break' : 'Skip Break',
                                  onTap: timer.skip,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Leaving Focus Mode (the ✕ or the phone's back gesture) pauses the
    // timer; RESUME on the Study screen carries on.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) timer.pause();
      },
      child: page,
    );
  }
}

/// Soft, see-through bubbles rising slowly behind the timer, each swaying a
/// little. Calm by design: few, faint and slow. Holds still when the phone
/// asks for less motion.
class _Bubbles extends StatefulWidget {
  const _Bubbles();

  @override
  State<_Bubbles> createState() => _BubblesState();
}

class _BubblesState extends State<_Bubbles>
    with SingleTickerProviderStateMixin {
  /// One loop. Every bubble's rise and sway period divides it, so the loop
  /// restarts without a jump.
  static const _loop = Duration(seconds: 60);

  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _loop);

  static final List<_Bubble> _bubbles = _Bubble.make(16);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _clock
        ..stop()
        ..value = 0.37;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BubblePainter(_clock, _bubbles),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Bubble {
  const _Bubble({
    required this.x,
    required this.radius,
    required this.rise,
    required this.phase,
    required this.sway,
    required this.swayPeriod,
    required this.alpha,
  });

  final double x; // 0–1 across the screen
  final double radius; // logical pixels
  final int rise; // seconds to cross the screen (divides 60)
  final double phase; // 0–1 head start
  final double sway; // side-to-side, logical pixels
  final int swayPeriod; // seconds (divides 60)
  final double alpha;

  /// The same gentle set every time (fixed seed).
  static List<_Bubble> make(int count) {
    final rnd = math.Random(7);
    const rises = [20, 30, 30, 60];
    const sways = [6, 10, 12, 15];
    return [
      for (var i = 0; i < count; i++)
        _Bubble(
          x: (i + rnd.nextDouble()) / count,
          radius: 5 + rnd.nextDouble() * rnd.nextDouble() * 34,
          rise: rises[rnd.nextInt(rises.length)],
          phase: rnd.nextDouble(),
          sway: 6 + rnd.nextDouble() * 18,
          swayPeriod: sways[rnd.nextInt(sways.length)],
          alpha: 0.05 + rnd.nextDouble() * 0.08,
        ),
    ];
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.clock, this.bubbles) : super(repaint: clock);

  final Animation<double> clock;
  final List<_Bubble> bubbles;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock.value * 60;
    final fill = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final b in bubbles) {
      // Bottom to top, then round again.
      final travel = size.height + b.radius * 2;
      final progress = (seconds / b.rise + b.phase) % 1.0;
      final y = size.height + b.radius - progress * travel;
      final x = b.x * size.width +
          math.sin((seconds / b.swayPeriod + b.phase) * 2 * math.pi) * b.sway;
      final c = Offset(x, y);

      fill.color = AppColors.primary.withValues(alpha: b.alpha);
      canvas.drawCircle(c, b.radius, fill);
      ring.color = Colors.white.withValues(alpha: b.alpha * 1.6);
      canvas.drawCircle(c, b.radius, ring);
      // A small shine near the top-left edge.
      fill.color = Colors.white.withValues(alpha: b.alpha * 2);
      canvas.drawCircle(
          c + Offset(-b.radius * 0.4, -b.radius * 0.4), b.radius * 0.18, fill);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.bubbles != bubbles;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.big = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 64.0 : 48.0;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Material(
            color: big ? Colors.white : Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  icon,
                  size: big ? 26 : 20,
                  color: big ? FocusScreen._bg : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tick marks along a shallow arc, like a dial. Ticks already passed are
/// bright; a longer yellow tick marks "now".
class _TickDialPainter extends CustomPainter {
  _TickDialPainter({required this.progress, required this.accent});

  final double progress;

  /// The "now" tick (the theme's fill colour).
  final Color accent;

  static const _ticks = 41;

  @override
  void paint(Canvas canvas, Size size) {
    // A big circle whose top edge forms the arc.
    final radius = size.width * 1.1;
    final center = Offset(size.width / 2, radius + 14);
    const sweep = 0.9; // radians across the width
    const start = -math.pi / 2 - sweep / 2;
    final now = (progress * (_ticks - 1)).round();

    for (var i = 0; i < _ticks; i++) {
      final a = start + sweep * i / (_ticks - 1);
      final isNow = i == now;
      final major = i % 5 == 0;
      final len = isNow ? 30.0 : (major ? 18.0 : 11.0);
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = center + dir * radius;
      final inner = center + dir * (radius - len);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isNow ? 3 : 2
        ..color = isNow
            ? accent
            : Colors.white.withValues(alpha: i < now ? 0.95 : 0.35);
      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(_TickDialPainter old) =>
      old.progress != progress || old.accent != accent;
}

/// Opens [FocusScreen] with a circle growing from [origin] (global position,
/// e.g. the centre of the START button).
Future<void> openFocusScreen(BuildContext context, Offset origin) {
  return Navigator.of(context).push(_CircularRevealRoute(origin: origin));
}

/// Starts a Pomodoro (unless the timer is already running) and opens Focus
/// Mode growing out of the widget that [from] belongs to (e.g. a button).
void startFocusFrom(BuildContext from) {
  final timer = PomodoroController.instance;
  if (!timer.running) {
    if (!timer.isFocus && timer.atStart) timer.selectMode(TimerMode.pomodoro);
    timer.start();
  }
  final box = from.findRenderObject() as RenderBox?;
  // Relative to the navigator, which is centred (not at 0,0) on wide screens.
  final nav = Navigator.of(from).context.findRenderObject() as RenderBox?;
  final size = MediaQuery.sizeOf(from);
  final origin = box != null && box.hasSize
      ? box.localToGlobal(box.size.center(Offset.zero), ancestor: nav)
      : Offset(size.width / 2, size.height / 2);
  openFocusScreen(from, origin);
}

/// Keeps the screen on while Focus Mode is open (if [enabled]).
class _KeepAwake extends StatefulWidget {
  const _KeepAwake({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_KeepAwake> createState() => _KeepAwakeState();
}

class _KeepAwakeState extends State<_KeepAwake> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) ScreenAwake.set(true);
  }

  @override
  void didUpdateWidget(_KeepAwake old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled) ScreenAwake.set(widget.enabled);
  }

  @override
  void dispose() {
    if (widget.enabled) ScreenAwake.set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CircularRevealRoute extends PageRouteBuilder<void> {
  _CircularRevealRoute({required Offset origin})
      : super(
          transitionDuration: const Duration(milliseconds: 600),
          reverseTransitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (context, animation, secondary) => const FocusScreen(),
          transitionsBuilder: (context, animation, secondary, child) {
            // drive() adds no listeners of its own, so nothing piles up
            // while this builder runs every frame.
            final curved =
                animation.drive(CurveTween(curve: Curves.easeInOutCubic));
            return AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (context, child) {
                final size = MediaQuery.sizeOf(context);
                // Far enough to cover the furthest corner.
                final maxRadius = [
                  Offset.zero,
                  Offset(size.width, 0),
                  Offset(0, size.height),
                  Offset(size.width, size.height),
                ].map((c) => (c - origin).distance).reduce(math.max);
                return ClipPath(
                  clipper: _CircleClipper(origin, maxRadius * curved.value),
                  child: child,
                );
              },
            );
          },
        );
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.radius != radius || old.center != center;
}
