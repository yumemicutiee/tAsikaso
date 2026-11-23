import 'package:flutter/material.dart';

import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_logo.dart';

/// Opening the app: the loading screen while [load] reads the saved data,
/// shown for at least [minimum] so it doesn't just flash, then the app.
/// [onReady] runs once the app is up.
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    required this.load,
    this.onReady,
    this.minimum = const Duration(milliseconds: 1100),
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

/// The loading screen: the logo, the name and a moving bar.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Semantics(
        label: 'Loading $kAppName',
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: appear,
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(appear),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogo(size: 112),
                      const SizedBox(height: 14),
                      Text(kAppName,
                          style: TextStyle(
                            fontFamily: kHeadingFont,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.ink,
                          )),
                      const SizedBox(height: 4),
                      Text('Focus. Snap. Remember.',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.78),
              child: SizedBox(
                width: 132,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primarySoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
