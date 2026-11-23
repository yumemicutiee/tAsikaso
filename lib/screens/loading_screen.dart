import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/app_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/brand_mark.dart';

/// Opening the app: the loading screen while [load] reads the saved data,
/// shown for at least [minimum]; once both are done its bar fills to the
/// end and the app takes over. A new install goes on to the welcome screen,
/// which starts exactly where the loading screen ends (the full bar then
/// drops away), so there is no fade; otherwise the app fades in.
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
  bool _loaded = false;
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
    if (mounted) setState(() => _loaded = true);
  }

  void _show() {
    if (!mounted || _ready) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady?.call());
  }

  @override
  Widget build(BuildContext context) {
    final toWelcome = !AppStore.instance.prefs.welcomed;
    return AnimatedSwitcher(
      duration: toWelcome ? Duration.zero : const Duration(milliseconds: 380),
      child: _ready
          ? const StudyApp(key: ValueKey('app'))
          : MaterialApp(
              key: const ValueKey('loading'),
              title: kAppName,
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              // As StudyApp lays out wide screens, so nothing shifts.
              builder: (context, child) => ColoredBox(
                color: AppColors.frame,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              home: LoadingScreen(finish: _loaded, onFinished: _show),
            ),
    );
  }
}

/// The loading screen: the logo's plus pops in, the letters of the name
/// rise one by one, and the bar under it fills while the app loads. When
/// [finish] turns true the bar fills to the end, then [onFinished] runs.
/// With animations turned off on the phone, it simply shows.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.finish = false, this.onFinished});

  /// The tagline, shown on the welcome screen in place of the bar.
  static const tagline = BrandMark.words;

  final bool finish;
  final VoidCallback? onFinished;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  /// The plus, the letters and the bar's track appearing (once).
  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));

  /// How full the bar is.
  late final AnimationController _fill = AnimationController(vsync: this);

  Timer? _startFill;
  bool _started = false;
  bool _finishing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _reveal.value = 1;
      _fill.value = 1;
    } else {
      // On the web the page's own loader already spelled out the name.
      if (kIsWeb) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
      _startFill = Timer(Duration(milliseconds: kIsWeb ? 0 : 700), () {
        if (!_finishing) {
          _fill.animateTo(0.9,
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic);
        }
      });
    }
    if (widget.finish) _complete();
  }

  @override
  void didUpdateWidget(LoadingScreen old) {
    super.didUpdateWidget(old);
    if (widget.finish && !old.finish) _complete();
  }

  Future<void> _complete() async {
    if (_finishing) return;
    _finishing = true;
    _startFill?.cancel();
    // The name is spelled out before the bar ends.
    if (_reveal.value < 1) {
      await Future<void>.delayed(
          Duration(milliseconds: ((1 - _reveal.value) * 1000).round()));
      if (!mounted) return;
    }
    final left = 1 - _fill.value;
    if (left > 0) {
      await _fill.animateTo(1,
          duration: Duration(milliseconds: (150 + left * 650).round()),
          curve: Curves.easeInOutCubic);
    }
    if (mounted) widget.onFinished?.call();
  }

  @override
  void dispose() {
    _startFill?.cancel();
    _reveal.dispose();
    _fill.dispose();
    super.dispose();
  }

  /// 0 → 1 between [from] and [to] ms of the reveal, eased.
  double _in(double from, double to) {
    final ms = _reveal.value * 1000;
    return Curves.easeOutCubic.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGround,
      body: Semantics(
        label: 'Loading $kAppName',
        child: ExcludeSemantics(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Positioned(
                    top: BrandMark.topIn(box.maxHeight),
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_reveal, _fill]),
                        builder: (context, _) => BrandMark(
                          plus: _in(0, 280),
                          letter: (i) => _in(120.0 + i * 70, 470.0 + i * 70),
                          track: _in(550, 800),
                          progress: _fill.value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
