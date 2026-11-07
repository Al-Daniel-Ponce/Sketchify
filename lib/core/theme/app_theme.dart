import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = isDark
        ? ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.dark,
          ).copyWith(
            primary: AppColors.primary,
            onPrimary: const Color(0xFF2A1206),
            primaryContainer: const Color(0xFF4A2312),
            onPrimaryContainer: AppColors.primarySoft,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFF2C2650),
            onSecondaryContainer: const Color(0xFFD6D0FF),
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            surfaceContainerLowest: AppColors.ink,
            surfaceContainerLow: const Color(0xFF141A24),
            surfaceContainer: AppColors.surfaceHigh,
            surfaceContainerHigh: const Color(0xFF202836),
            surfaceContainerHighest: AppColors.surfaceHighest,
            onSurfaceVariant: AppColors.textSecondary,
            outline: AppColors.outline,
            outlineVariant: const Color(0xFF263143),
            error: AppColors.danger,
            onError: const Color(0xFF2B0909),
          )
        : ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFFDD541B),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFFFE2D4),
            onPrimaryContainer: const Color(0xFF4A1A05),
            secondary: const Color(0xFF6757D8),
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFE8E3FF),
            onSecondaryContainer: const Color(0xFF211A52),
            surface: const Color(0xFFF8F5F1),
            onSurface: const Color(0xFF171A1F),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF2EEE8),
            surfaceContainer: const Color(0xFFECE7E0),
            surfaceContainerHigh: const Color(0xFFE5DFD7),
            surfaceContainerHighest: const Color(0xFFDED7CE),
            onSurfaceVariant: const Color(0xFF5B6472),
            outline: const Color(0xFF8B8F97),
            outlineVariant: const Color(0xFFD6D0C8),
            error: const Color(0xFFC0392B),
            onError: Colors.white,
          );

    final typography = Typography.material2021();
    final baseText = (isDark ? typography.white : typography.black).copyWith(
      displaySmall: (isDark ? typography.white : typography.black).displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      headlineMedium: (isDark ? typography.white : typography.black)
          .headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: (isDark ? typography.white : typography.black)
          .headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: (isDark ? typography.white : typography.black).titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: (isDark ? typography.white : typography.black).titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: (isDark ? typography.white : typography.black).bodyLarge
          ?.copyWith(height: 1.45),
      bodyMedium: (isDark ? typography.white : typography.black).bodyMedium
          ?.copyWith(height: 1.45),
      labelLarge: (isDark ? typography.white : typography.black).labelLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
      labelSmall: (isDark ? typography.white : typography.black).labelSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
    );

    final textTheme = baseText.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.9)),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 44),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.7),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.65),
        thickness: 1,
        space: 24,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        modalBackgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
