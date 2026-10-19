import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Tabs shown in the bottom bar. The camera button sits between Library and
/// Study but is an action, not a tab.
enum AppTab {
  dashboard('Dashboard', AppIcons.dashboard, AppIcons.dashboardActive),
  library('Library', AppIcons.library, AppIcons.libraryActive),
  study('Study', AppIcons.study, AppIcons.studyActive),
  profile('Profile', AppIcons.profile, AppIcons.profileActive);

  const AppTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.current,
    required this.onTabSelected,
    required this.onCameraPressed,
  });

  final AppTab current;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onCameraPressed;

  @override
  Widget build(BuildContext context) {
    Widget item(AppTab tab) => Expanded(
          child: _NavItem(
            tab: tab,
            selected: tab == current,
            onTap: () => onTabSelected(tab),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              item(AppTab.dashboard),
              item(AppTab.library),
              Expanded(child: Center(child: CameraButton(onPressed: onCameraPressed))),
              item(AppTab.study),
              item(AppTab.profile),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryDeep : AppColors.navInactive;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 25, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big sky-blue camera button (same colour as the + button) in the middle of the bottom bar.
class CameraButton extends StatelessWidget {
  const CameraButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture Notes',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.halo(0.45),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(AppIcons.capture, size: 28, color: AppColors.onFill),
            ),
          ),
        ),
      ),
    );
  }
}
