import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

abstract final class AppTheme {
  static const radius = 16.0;
  static const radiusSmall = 10.0;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.navy,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE4F5),
      onPrimaryContainer: AppColors.navy,
      secondary: AppColors.royal,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE2E9FF),
      onSecondaryContainer: Color(0xFF14317F),
      tertiary: AppColors.royal,
      onTertiary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFDE6E6),
      onErrorContainer: Color(0xFF7A1212),
      surface: AppColors.card,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF9FAFC),
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: Color(0xFFEDF0F5),
      surfaceContainerHighest: Color(0xFFE6EAF0),
      outline: Color(0xFFCBD2DC),
      outlineVariant: AppColors.divider,
      shadow: Color(0xFF0B1F3A),
      inverseSurface: AppColors.navy,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.royalLight,
    );
    return _build(scheme, AppColors.background, StatusColors.light,
        AppTypography.textTheme(AppColors.textPrimary, AppColors.textSecondary));
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.royalLight,
      onPrimary: Color(0xFF071534),
      primaryContainer: AppColors.navyLight,
      onPrimaryContainer: Color(0xFFDCE4F5),
      secondary: AppColors.royalLight,
      onSecondary: Color(0xFF071534),
      secondaryContainer: Color(0xFF1E3170),
      onSecondaryContainer: Color(0xFFDCE4FF),
      tertiary: AppColors.royalLight,
      onTertiary: Color(0xFF071534),
      error: Color(0xFFFF6B6B),
      onError: Color(0xFF3A0000),
      errorContainer: Color(0xFF3A1414),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkCard,
      onSurface: AppColors.darkTextPrimary,
      onSurfaceVariant: AppColors.darkTextSecondary,
      surfaceContainerLowest: Color(0xFF070B13),
      surfaceContainerLow: Color(0xFF0F1523),
      surfaceContainer: AppColors.darkBackground,
      surfaceContainerHigh: AppColors.darkCardHigh,
      surfaceContainerHighest: Color(0xFF243049),
      outline: Color(0xFF3A4766),
      outlineVariant: AppColors.darkDivider,
      shadow: Colors.black,
      inverseSurface: AppColors.darkTextPrimary,
      onInverseSurface: AppColors.darkBackground,
      inversePrimary: AppColors.royal,
    );
    return _build(scheme, AppColors.darkBackground, StatusColors.dark,
        AppTypography.textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary));
  }

  static ThemeData _build(ColorScheme scheme, Color background, StatusColors status, TextTheme text) {
    final isDark = scheme.brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final smallShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: background,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: smallShape,
          textStyle: text.labelLarge,
          backgroundColor: isDark ? AppColors.royal : AppColors.navy,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: smallShape,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: smallShape, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCardHigh : const Color(0xFFF3F5F9),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        side: BorderSide(color: scheme.outlineVariant),
        showCheckmark: false,
        selectedColor: scheme.secondaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(color: scheme.onSurface)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(shape: shape, backgroundColor: scheme.surface),
      listTileTheme: ListTileThemeData(
        shape: smallShape,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: smallShape,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.secondary,
        thumbColor: scheme.secondary,
        inactiveTrackColor: scheme.outlineVariant,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.secondary : null),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
