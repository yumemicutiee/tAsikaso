import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The background of the loading screen and the welcome screen, which
/// follows it without a seam: a pale sky in light mode, the app's own dark
/// background in dark mode.
Color get brandGround =>
    AppColors.isDark ? AppColors.background : const Color(0xFFF4F8FD);

/// The opening's wordmark: the logo's plus, "tAsikaso" with a blue "A",
/// and under it the loading bar, which on the welcome screen drops away and
/// leaves the tagline in its place.
///
/// The loading screen and the welcome screen both place it with [topIn], so
/// it doesn't move when one hands over to the other.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.plus = 1,
    this.letter,
    this.track = 1,
    this.progress = 1,
    this.barDrop = 0,
    this.barOpacity = 1,
    this.tagline = 0,
  });

  /// The tagline.
  static const words = 'Snap. Study. Recall.';

  static const double wordHeight = 50;

  /// From the top of the name to the top of the bar.
  static const double barOffset = wordHeight + 26;

  static const double barWidth = 206;

  /// Where the top of the name goes in a screen [height] tall: centred.
  static double topIn(double height) => height / 2 - wordHeight / 2;

  /// The plus, 0 (gone) to 1 (shown).
  final double plus;

  /// Each letter, 0 (gone) to 1 (shown); null: all shown.
  final double Function(int index)? letter;

  /// The bar's track, 0 to 1.
  final double track;

  /// How full the bar is, 0 to 1.
  final double progress;

  /// How far the bar has dropped, in pixels, and how much of it shows.
  final double barDrop;
  final double barOpacity;

  /// The tagline, 0 (gone) to 1 (shown).
  final double tagline;

  static const _letters = 'tAsikaso';

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final ink = dark ? const Color(0xFFEEF0F7) : const Color(0xFF1E3A6E);
    final capital = dark ? const Color(0xFF9FCBF5) : const Color(0xFF4F80BF);
    final style = TextStyle(
      fontFamily: kHeadingFont,
      fontSize: wordHeight,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      height: 1,
      color: ink,
    );
    // Everything on one centre line: the name (with its plus), the bar and
    // the tagline (and, on the welcome screen, "Welcome to" above).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // A logo: the same size whatever the phone's text size.
        MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: wordHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: plus.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: (1 - plus) * -1.57,
                    child: Transform.scale(
                      scale: 0.3 + 0.7 * plus,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: CustomPaint(size: Size(26, 26), painter: _Plus()),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < _letters.length; i++)
                  Builder(builder: (context) {
                    final v = letter?.call(i) ?? 1;
                    return Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - v) * 16),
                        child: Text(_letters[i],
                            style: i == 1 ? style.copyWith(color: capital) : style),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        SizedBox(
          width: barWidth,
          height: barOffset - wordHeight + 20,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: barOffset - wordHeight,
                width: barWidth,
                height: 4,
                child: Transform.translate(
                  offset: Offset(0, barDrop),
                  child: Opacity(
                    opacity: (track * barOpacity).clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (tagline > 0)
                Positioned(
                  left: -40,
                  right: -40,
                  top: barOffset - wordHeight - 10,
                  child: Opacity(
                    opacity: tagline.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - tagline) * 10),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        // Rising weight: light "Snap.", medium "Study.",
                        // bold sky "Recall.".
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 21,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                            children: [
                              TextSpan(
                                text: 'Snap. ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textSecondary),
                              ),
                              TextSpan(
                                text: 'Study. ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: dark
                                        ? const Color(0xFFD5DBE8)
                                        : const Color(0xFF3A3F55)),
                              ),
                              TextSpan(
                                text: 'Recall.',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: capital),
                              ),
                            ],
                          ),
                          semanticsLabel: words,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The logo's plus: two round-ended sky strokes.
class _Plus extends CustomPainter {
  const _Plus();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9FCBF5)
      ..strokeWidth = size.width * 0.23
      ..strokeCap = StrokeCap.round;
    final m = size.width * 0.12;
    canvas
      ..drawLine(Offset(size.width / 2, m), Offset(size.width / 2, size.height - m), paint)
      ..drawLine(Offset(m, size.height / 2), Offset(size.width - m, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(_Plus oldDelegate) => false;
}
