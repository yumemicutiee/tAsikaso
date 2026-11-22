import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/brand.dart';

/// tAsikaso's logo (a plus and an "A") on a rounded tile, in the app's
/// current colors: the tile is the theme's pastel fill, the outline its deep
/// shade, the letters white. With the default Navy & Sky theme it matches the
/// launcher icon, which can't change color and so always uses Navy & Sky.
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
        child: Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.17),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(_fill,
                  color: Colors.white,
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
