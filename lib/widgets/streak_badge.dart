import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// "🔥 3 Day Streak" pill. The flame is painted with an orange → red
/// gradient; it's the only place those colours appear in the app.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: AppColors.streakSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StreakFlame(size: 15),
          const SizedBox(width: 3),
          Text(
            '$days Day Streak',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.streakText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flame icon filled with the streak gradient.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.streakOrange, AppColors.streakRed],
      ).createShader(bounds),
      child: Icon(AppIcons.streak, size: size, color: Colors.white),
    );
  }
}
