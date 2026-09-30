import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Plus Jakarta Sans for titles, big numbers and buttons; Inter for all
/// other text. Both are bundled in assets/fonts.
const String kHeadingFont = 'PlusJakartaSans';
const String kBodyFont = 'Inter';

/// Text styles. Getters (not constants) because their colours follow the
/// light / dark palette; don't use them inside `const` expressions.
class AppText {
  AppText._();

  static TextStyle get screenTitle => TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: AppColors.ink,
    height: 1.2,
  );

  static TextStyle get sectionTitle => TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get viewAll => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static TextStyle get itemTitle => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get itemMeta => TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static TextStyle get statValue => TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static TextStyle get statLabel => TextStyle(
    fontSize: 11.5,
    color: AppColors.textSecondary,
  );

  static TextStyle get timer => TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 56,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
    letterSpacing: -1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// On sky / butter button fills, so always dark.
  static TextStyle get button => const TextStyle(
    fontFamily: kHeadingFont,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onFill,
    letterSpacing: 0.3,
  );
}

/// The Material theme for the current palette ([AppColors.isDark]).
ThemeData buildAppTheme() {
  final dark = AppColors.isDark;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kBodyFont,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: dark ? AppColors.primaryDeep : AppColors.primary,
      onPrimary: AppColors.onFill,
      secondary: AppColors.accent,
      onSecondary: AppColors.onFill,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    ),
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    iconTheme: IconThemeData(color: AppColors.ink),
    dividerTheme: DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle:
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.ink,
      textColor: AppColors.textPrimary,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontSize: 13, color: AppColors.textPrimary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primaryDeep),
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: AppColors.textMuted),
      labelStyle: TextStyle(color: AppColors.textSecondary),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primaryDeep,
      selectionHandleColor: AppColors.primaryDeep,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
