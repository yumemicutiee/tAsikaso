import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Centred title, with a settings gear on the right when [onSettings] is set.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.onSettings});

  final String title;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(title, style: AppText.screenTitle),
            if (onSettings != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  icon: Icon(AppIcons.settings,
                      color: AppColors.ink, size: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// App bar for pages opened on top of the tabs (Settings, Analysis, Plans…).
AppBar subPageAppBar(String title, {List<Widget>? actions}) => AppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: kHeadingFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      actions: actions,
    );
