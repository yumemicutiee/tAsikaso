import 'package:flutter/material.dart';

/// One of the app's colour themes. "Navy & Sky" is the default and free;
/// the others come with tAsikaso+. Each has a pastel [fill] for buttons and
/// rings and a [deep] shade for accents and the Focus Mode background.
enum Palette {
  navy('Navy & Sky', 0xFF9FCBF5, 0xFF1E3A6E, 0xFF132647, 0xFFA9D2F7),
  teal('Teal & Mint', 0xFF8FD9C8, 0xFF0F4C4A, 0xFF0A3332, 0xFF9FE3D3),
  plum('Plum & Lavender', 0xFFC4B5F5, 0xFF3B2A6E, 0xFF271C4B, 0xFFCFC3FA),
  forest('Forest & Sage', 0xFFA9D8A6, 0xFF1F4D2B, 0xFF14351D, 0xFFB9E3B6),
  wine('Wine & Rose', 0xFFF5B3C4, 0xFF6B1F3A, 0xFF4A1428, 0xFFF9C4D1),
  cocoa('Cocoa & Peach', 0xFFF8C49E, 0xFF5A3218, 0xFF3E2210, 0xFFFAD2B4),
  graphite('Graphite & Silver', 0xFFC9D1DD, 0xFF2B303B, 0xFF1C2028, 0xFFD4DBE5),

  /// The user's own colour, built from one hue (see [ThemeColors.fromHue]).
  /// Its numbers here are unused.
  custom('Custom', 0, 0, 0, 0);

  const Palette(this.label, this.fill, this.deep, this.deepest, this.pale);

  final String label;

  /// Pastel fill (buttons, rings), dark content on it.
  final int fill;

  /// Accent text in light mode, and the top of the hero gradient.
  final int deep;

  /// The bottom of the hero gradient.
  final int deepest;

  /// Accent text in dark mode.
  final int pale;

  /// Free for everyone.
  bool get isFree => this == navy;

  /// This theme's colours ([custom] needs [ThemeColors.fromHue] instead).
  ThemeColors get colors => ThemeColors(fill, deep, deepest, pale);
}

/// The four colours that make a theme (ARGB ints).
@immutable
class ThemeColors {
  const ThemeColors(this.fill, this.deep, this.deepest, this.pale);

  /// A full theme from one hue (0–360), with the same lightness and
  /// saturation as Navy & Sky, so any hue looks as calm and readable.
  factory ThemeColors.fromHue(double hue) {
    int hsl(double s, double l) =>
        HSLColor.fromAHSL(1, hue % 360, s, l).toColor().toARGB32();
    return ThemeColors(
      hsl(0.78, 0.79), // fill: soft pastel
      hsl(0.57, 0.27), // deep: text accent / hero top
      hsl(0.58, 0.18), // deepest: hero bottom
      hsl(0.82, 0.82), // pale: accent in dark mode
    );
  }

  final int fill;
  final int deep;
  final int deepest;
  final int pale;

  @override
  bool operator ==(Object other) =>
      other is ThemeColors &&
      other.fill == fill &&
      other.deep == deep &&
      other.deepest == deepest &&
      other.pale == pale;

  @override
  int get hashCode => Object.hash(fill, deep, deepest, pale);
}

/// The app's colours, for the current [Palette] in a light and a dark
/// version.
///
///   Deep   – text-coloured accents (links, numbers, selected tab) and the
///            Focus Mode / tAsikaso+ backgrounds ([heroTop] → [heroBottom])
///   Fill   – pastel fills: buttons, rings, the + and camera buttons
///   Butter – camera and crop screens
///   Gold   – the tAsikaso+ crown and "Plus" badges
///   Flame  – the streak only (orange → red)
///
/// Colours that differ between light and dark are getters, so they must not
/// be used inside `const` expressions. The app rebuilds every widget when
/// the appearance changes (see `StudyApp`), so a getter read in `build`
/// always gives the current colour.
///
/// Rules of thumb:
/// * Text on the page or on a card: [ink], [textPrimary], [textSecondary].
/// * Text or icons on a solid pastel fill ([primary], [accent], [gold], a
///   folder's colour): [onFill] – dark in both modes.
/// * A light wash of a colour behind text (folder tiles, badges): [tint].
/// * Charts: [chartStrong], [chartSoft] and [heat], chosen for each mode.
class AppColors {
  AppColors._();

  static bool _dark = false;

  /// True while the dark palette is in use.
  static bool get isDark => _dark;

  /// Switches light / dark. Call only from `StudyApp` (which then rebuilds
  /// everything) or from tests.
  static void useDark(bool dark) => _dark = dark;

  static Palette _palette = Palette.navy;
  static ThemeColors _c = Palette.navy.colors;

  /// The colour theme in use.
  static Palette get palette => _palette;

  /// Its colours (for [Palette.custom], built from the chosen hue).
  static ThemeColors get colors => _c;

  /// Switches the colour theme. Call only from `StudyApp` or from tests.
  static void usePalette(Palette p, [ThemeColors? colors]) {
    _palette = p;
    _c = colors ?? p.colors;
  }

  static const _darkCard = Color(0xFF181D2C);

  static Color _pick(int light, int dark) => Color(_dark ? dark : light);

  // ---- Same in both modes ----------------------------------------------------

  /// Pastel button and ring fill (sky by default). Always carries [onFill]
  /// content.
  static Color get primary => Color(_c.fill);

  /// Dark ink for text and icons on pastel fills, in both modes.
  static const onFill = Color(0xFF23263A);

  // Focus Mode and tAsikaso+ backgrounds (a deep gradient, white text)
  static Color get heroTop => Color(_c.deep);
  static Color get heroBottom => Color(_c.deepest);

  static const accent = Color(0xFFF7DC8C); // Butter (fills)

  // tAsikaso+
  static const gold = Color(0xFFFFD76A); // light yellow gold (the crown)

  // Streak
  static const streakOrange = Color(0xFFFF8A3D);
  static const streakRed = Color(0xFFE5484D);

  // Capture (camera) screens are dark in both modes.
  static const cameraBackground = Color(0xFF1A1C2B);
  static const cameraPanel = Color(0xFF272A3D);

  /// Colours users can pick for folders (ARGB). Soft pastels that all
  /// carry [onFill] content when used as a solid fill.
  static const folderPalette = <int>[
    0xFFA9CFF5, // sky
    0xFFA8DCC1, // mint
    0xFFF7DC8C, // butter
    0xFFF9C9A3, // peach
    0xFFF5B5C8, // pink
    0xFFC7B8F5, // lavender
    0xFFB9E3E8, // aqua
    0xFFD9E7A8, // lime
    0xFFE3C9B0, // sand
    0xFFD5D9E3, // grey
  ];

  // ---- Light / dark ----------------------------------------------------------

  /// Navy in light mode, pale sky in dark: links, numbers, the selected tab,
  /// icons that should stand out.
  static Color get primaryDeep => Color(_dark ? _c.pale : _c.deep);

  /// Content on a [primaryDeep] fill (e.g. the selected day).
  static Color get onPrimaryDeep => _pick(0xFFFFFFFF, 0xFF23263A);

  /// Soft sky wash: highlighted rows, icon circles, ring tracks.
  static Color get primarySoft => _palette == Palette.navy
      ? _pick(0xFFE7F2FD, 0xFF1C2A45)
      : Color.lerp(_dark ? _darkCard : Colors.white, primary, _dark ? 0.12 : 0.24)!;

  static Color get accentDeep => _pick(0xFF8A6A10, 0xFFE9CC7A);
  static Color get accentSoft => _pick(0xFFFDF7E2, 0xFF2E2A1C);

  static Color get goldSoft => _pick(0xFFFDEBB8, 0xFF3B3220);

  static Color get streakSoft => _pick(0xFFFFEEE8, 0xFF3A2320);
  static Color get streakText => _pick(0xFFD9462F, 0xFFFF8A6B);

  // Surfaces
  static Color get background => _pick(0xFFFFFFFF, 0xFF0F1320);
  static Color get surface => _pick(0xFFFFFFFF, 0xFF181D2C);

  /// Sheets and dialogs (a step above [surface] in dark mode).
  static Color get raised => _pick(0xFFFFFFFF, 0xFF1F2536);
  static Color get searchFill => _pick(0xFFF1F3F6, 0xFF222838);

  /// The selected option in a segmented switch (sits on [searchFill]).
  static Color get segmentOn => _pick(0xFFFFFFFF, 0xFF323A50);
  static Color get thumbnail => _pick(0xFFEEF1F6, 0xFF262C3D);

  // Text
  static Color get ink => _pick(0xFF23263A, 0xFFEEF0F7);
  static Color get textPrimary => _pick(0xFF2A2D3E, 0xFFE4E7F0);
  static Color get textSecondary => _pick(0xFF6B7085, 0xFFA3A9BD);
  static Color get textMuted => _pick(0xFFA0A5B8, 0xFF6B7288);

  // Lines
  static Color get border => _pick(0xFFE6EAF1, 0xFF2A3143);
  static Color get divider => _pick(0xFFEAECF2, 0xFF262C3D);

  // Navigation
  static Color get navInactive => _pick(0xFFB0B5C6, 0xFF5F667C);

  /// Outside the phone-width layout on wide screens (web / tablet).
  static Color get frame => _pick(0xFFE9ECF1, 0xFF090C15);

  // Charts
  /// The emphasised mark: the picked bar, "Focus", the top task.
  static Color get chartStrong => primaryDeep;

  /// Ordinary marks: other bars, "Break".
  static Color get chartSoft => !_dark
      ? primary
      : _palette == Palette.navy
          ? const Color(0xFF3F6BA3)
          : Color.lerp(heroTop, primary, 0.35)!;

  /// Empty bar stubs and bar tracks.
  static Color get chartEmpty => _pick(0xFFEAECF2, 0xFF262C3D);

  /// Sequential scale for Productive Hours and the Heatmap:
  /// none → a little → … → a lot. One hue; darker = more in light mode,
  /// brighter = more in dark mode.
  static List<Color> get heat {
    if (_palette == Palette.navy) return _dark ? _heatDark : _heatLight;
    final none = _dark ? _heatDark[0] : _heatLight[0];
    final top = primaryDeep;
    return _dark
        ? [
            none,
            Color.lerp(none, primary, 0.25)!,
            Color.lerp(none, primary, 0.5)!,
            Color.lerp(none, primary, 0.8)!,
            top,
          ]
        : [
            none,
            Color.lerp(Colors.white, primary, 0.45)!,
            primary,
            Color.lerp(primary, top, 0.5)!,
            top,
          ];
  }

  static const _heatLight = <Color>[
    Color(0xFFEEF1F6), // none (neutral grey)
    Color(0xFFCFE4FA),
    Color(0xFF9FCBF5),
    Color(0xFF5E8FCB),
    Color(0xFF1E3A6E),
  ];

  static const _heatDark = <Color>[
    Color(0xFF232838), // none (neutral)
    Color(0xFF243A5E),
    Color(0xFF2F5A92),
    Color(0xFF5F97D6),
    Color(0xFFA9D2F7),
  ];

  /// Drop-shadow colour at [alpha] (light mode). In dark mode a light
  /// shadow would glow, so it's black and a little stronger instead.
  static Color shadow(double alpha) => _dark
      ? Colors.black.withValues(alpha: alpha * 4 > 0.5 ? 0.5 : alpha * 4)
      : const Color(0xFF23263A).withValues(alpha: alpha);

  /// The soft sky halo under sky buttons (camera, +, the current task).
  /// Light mode only: on a dark page it looks like a glow, so dark mode gets
  /// a plain dark shadow.
  static Color halo(double alpha) => _dark
      ? Colors.black.withValues(alpha: 0.35)
      : primary.withValues(alpha: alpha);

  /// A light wash of [c] over the card colour: folder tiles, tags, badges.
  /// In dark mode the wash is over the dark card, so text on it stays [ink].
  static Color tint(Color c, [double amount = 0.3]) =>
      Color.lerp(surface, c, _dark ? amount * 0.75 : amount)!;

  /// Darker (light mode) or lighter (dark mode) shade of [c] for text on a
  /// [tint] of the same colour.
  static Color deepen(Color c, [double amount = 0.38]) {
    final hsl = HSLColor.fromColor(c);
    final l = _dark ? hsl.lightness + amount * 0.3 : hsl.lightness - amount;
    return hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
  }
}
