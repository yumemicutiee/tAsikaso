import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One detail in a [MetaRow]: a small icon and its text ("4 notes").
class MetaItem {
  const MetaItem(this.icon, this.text);

  final IconData icon;
  final String text;
}

/// Details under a title ("4 notes  2 sets"), each with a small icon in
/// place of a separating dot, spaced apart on one line. The last details
/// shrink (with …) when there isn't room. Read out as one label.
class MetaRow extends StatelessWidget {
  const MetaRow(this.items, {super.key, this.style, this.gap = 12});

  final List<MetaItem> items;

  /// The text style; [AppText.itemMeta] by default.
  final TextStyle? style;

  /// Space between details.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final text = style ?? AppText.itemMeta;
    final size = (text.fontSize ?? 12) + 1.5;
    return Semantics(
      label: items.map((i) => i.text).join(', '),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (n, item) in items.indexed) ...[
            if (n > 0) SizedBox(width: gap),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: size, color: AppColors.primaryDeep),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(item.text,
                        style: text, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
