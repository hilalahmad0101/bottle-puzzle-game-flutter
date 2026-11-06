import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Light and dark Material 3 themes.
abstract final class AppTheme {
  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: AppColors.prism,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.ink,
      surfaceContainerHighest: AppColors.inkRaised,
      secondary: AppColors.aqua,
      tertiary: AppColors.ember,
    ),
    scaffold: AppColors.inkDeep,
  );

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: AppColors.prism,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.parchmentRaised,
      secondary: AppColors.aqua,
      tertiary: AppColors.ember,
    ),
    scaffold: AppColors.parchment,
  );

  static ThemeData _build(ColorScheme scheme, {required Color scaffold}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          letterSpacing: 4,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(220, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),
    );
  }
}
