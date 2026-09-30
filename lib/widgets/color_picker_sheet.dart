import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Lets the user pick their own app colour by hue. Returns the hue (0–360),
/// or null if the sheet was closed.
Future<double?> showCustomColorSheet(BuildContext context, double initialHue) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomColorSheet(initialHue: initialHue),
  );
}

class _CustomColorSheet extends StatefulWidget {
  const _CustomColorSheet({required this.initialHue});

  final double initialHue;

  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  late double _hue = widget.initialHue.clamp(0, 359);

  /// The slider's rainbow, in the same soft pastels the app uses.
  static final _rainbow = LinearGradient(colors: [
    for (var h = 0; h <= 360; h += 30) Color(ThemeColors.fromHue(h.toDouble()).fill),
  ]);

  @override
  Widget build(BuildContext context) {
    final c = ThemeColors.fromHue(_hue);
    final fill = Color(c.fill);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetTitle('Your Color',
                subtitle: 'Slide to pick any color. Light and dark shades '
                    'are made to match.'),
            const SizedBox(height: 16),

            // Preview: a Focus Mode card and a button in the new colour.
            Container(
              constraints: const BoxConstraints(minHeight: 118),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(c.deep), Color(c.deepest)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Keep going,',
                            style: TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.9),
                            )),
                        Text('you!',
                            style: TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: fill,
                            )),
                        const SizedBox(height: 4),
                        const Text('25:00',
                            style: TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.start, size: 14, color: AppColors.onFill),
                        SizedBox(width: 6),
                        Text('START',
                            style: TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onFill,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Hue slider over a rainbow track.
            SizedBox(
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: _rainbow,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 14,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.white,
                      overlayColor: fill.withValues(alpha: 0.3),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 11),
                      // Keeps the slider's ends 12px in, matching the
                      // rainbow track, so the thumb sits on its own hue.
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _hue,
                      max: 359,
                      semanticFormatterCallback: (v) => '${v.round()} degrees',
                      onChanged: (v) => setState(() => _hue = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_hue),
                style: FilledButton.styleFrom(
                  backgroundColor: fill,
                  foregroundColor: AppColors.onFill,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Use This Color',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
