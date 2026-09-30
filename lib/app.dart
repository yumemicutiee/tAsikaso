import 'package:flutter/material.dart';

import 'data/app_store.dart';
import 'models/models.dart';
import 'screens/home_shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/brand.dart';

/// The app. Follows the Appearance setting (System / Light / Dark) and, for
/// System, the phone's own dark mode, plus the chosen colour theme.
class StudyApp extends StatefulWidget {
  const StudyApp({super.key});

  @override
  State<StudyApp> createState() => _StudyAppState();
}

class _StudyAppState extends State<StudyApp> with WidgetsBindingObserver {
  final _store = AppStore.instance;

  @override
  void initState() {
    super.initState();
    AppColors.useDark(_wantsDark());
    AppColors.usePalette(_store.palette, _store.themeColors);
    _store.addListener(_update);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_update);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _update();

  bool _wantsDark() => switch (_store.prefs.appearance) {
        Appearance.light => false,
        Appearance.dark => true,
        Appearance.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  /// Switches the palette and rebuilds every screen, including ones further
  /// back in the navigation stack, so nothing keeps the old colours.
  void _update() {
    final dark = _wantsDark();
    final palette = _store.palette;
    final colors = _store.themeColors;
    if (dark == AppColors.isDark &&
        palette == AppColors.palette &&
        colors == AppColors.colors) {
      return;
    }
    AppColors.useDark(dark);
    AppColors.usePalette(palette, colors);
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // On wide screens (web / tablet) keep the phone layout centred for now.
      // A dedicated desktop-web layout comes later.
      builder: (context, child) => ColoredBox(
        color: AppColors.frame,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
