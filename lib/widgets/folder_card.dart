import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../utils/format.dart';

/// Soft, rounded folder tile: a tint of the folder's colour, a coloured
/// icon badge, then the name and what's inside.
class FolderCard extends StatelessWidget {
  const FolderCard({
    super.key,
    required this.folder,
    required this.noteCount,
    required this.setCount,
    this.onTap,
    this.onLongPress,
  });

  final StudyFolder folder;
  final int noteCount;
  final int setCount;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Width / height of folder tiles (grids use it too).
  static const double aspectRatio = 0.95;

  static const radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.tint(folder.color, 0.3);
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Semantics(
        button: true,
        label: '${folder.name} folder',
        child: Material(
          color: tint,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: [
                // Large, faint folder shape in the corner for depth.
                Positioned(
                  right: -14,
                  bottom: -16,
                  child: Icon(
                    AppIcons.folder,
                    size: 72,
                    color: folder.color.withValues(alpha: 0.35),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: folder.color,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(AppIcons.folder,
                            size: 18, color: AppColors.onFill),
                      ),
                      const Spacer(),
                      Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${plural(noteCount, 'note')} · ${plural(setCount, 'set')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.ink.withValues(alpha: 0.65),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed "+ New Folder" tile shown after the folders.
class NewFolderCard extends StatelessWidget {
  const NewFolderCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: FolderCard.aspectRatio,
      child: Semantics(
        button: true,
        label: 'New Folder',
        child: GestureDetector(
          onTap: onTap,
          child: CustomPaint(
            painter: _DashedBorderPainter(color: AppColors.navInactive),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.newFolder, size: 22, color: AppColors.textSecondary),
                  const SizedBox(height: 4),
                  Text(
                    'New Folder',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
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

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(FolderCard.radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
