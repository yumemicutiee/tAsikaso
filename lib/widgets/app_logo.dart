import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/brand.dart';

/// tAsikaso's logo (a plus and an "A") in the app's current colors: the
/// letters filled with the theme's pastel fill and outlined in its deep
/// shade, on a transparent background. With the default Navy & Sky theme it
/// matches the launcher icon, which can't change color and so always uses
/// Navy & Sky (tool/make_icons.py).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  static const _outline = 'assets/brand/logo_outline.png';
  static const _fill = 'assets/brand/logo_fill.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$kAppName logo',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(_fill,
                  color: AppColors.primary,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.medium),
              Image.asset(_outline,
                  color: AppColors.heroTop,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.medium),
            ],
          ),
        ),
      ),
    );
  }
}
