import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Grey pill with a white "thumb" on the selected option, e.g.
/// Overview | Timeline or Week | Month | Year.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.dense = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Smaller text and padding, for use inside a card.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.searchFill,
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(
                        horizontal: 4, vertical: dense ? 6 : 8),
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.segmentOn : Colors.transparent,
                      borderRadius: BorderRadius.circular(dense ? 8 : 10),
                      boxShadow: i == selected
                          ? [
                              BoxShadow(
                                color: AppColors.shadow(0.08),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 11.5 : 12.5,
                        fontWeight:
                            i == selected ? FontWeight.w700 : FontWeight.w600,
                        color: i == selected
                            ? AppColors.ink
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
