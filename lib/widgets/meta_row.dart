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
/// shrink (with …) when there isn't room, or, with [wrap], go on to a
/// second line. Read out as one label ([label] when the text is short).
class MetaRow extends StatelessWidget {
  const MetaRow(this.items,
      {super.key,
      this.style,
      this.gap = 12,
      this.wrap = false,
      this.label,
      this.lead});

  final List<MetaItem> items;

  /// The text style; [AppText.itemMeta] by default.
  final TextStyle? style;

  /// Space between details.
  final double gap;

  /// Details that don't fit go on to the next line, whole.
  final bool wrap;

  /// What's read out; the details' text, by default.
  final String? label;

  /// Shown first, without an icon ("Today"), and read out first.
  final String? lead;

  @override
  Widget build(BuildContext context) {
    final text = style ?? AppText.itemMeta;
    final size = (text.fontSize ?? 12) + 1.5;
    Widget detail(MetaItem item) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: size, color: AppColors.primaryDeep),
            SizedBox(width: size * 0.3),
            Flexible(
              child: Text(item.text,
                  style: text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
    return Semantics(
      label: label ??
          [if (lead != null) lead!, for (final i in items) i.text].join(', '),
      excludeSemantics: true,
      child: wrap
          ? Wrap(
              spacing: gap,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (lead case final lead?)
                  Text(lead, style: text.copyWith(fontWeight: FontWeight.w700)),
                for (final item in items) detail(item),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (n, item) in items.indexed) ...[
                  if (n > 0) SizedBox(width: gap),
                  Flexible(child: detail(item)),
                ],
              ],
            ),
    );
  }
}
