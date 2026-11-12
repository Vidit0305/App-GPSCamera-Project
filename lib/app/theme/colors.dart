import 'package:flutter/material.dart';

/// Brand palette for GPS Camera ("Modern Professional").
abstract final class AppColors {
  // Brand (matches the app icon)
  static const navy = Color(0xFF0B1B3F); // Primary - deep navy blue
  static const navyLight = Color(0xFF14307A);
  static const royal = Color(0xFF2B63F0); // Secondary - royal blue
  static const royalLight = Color(0xFF7FA2FF);
  static const cyan = Color(0xFF5EEAD4); // small highlights only

  // Light surfaces
  static const background = Color(0xFFF4F6FB); // very light grey
  static const card = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827); // dark charcoal
  static const textSecondary = Color(0xFF6B7280); // grey
  static const divider = Color(0xFFE8ECF3);

  // Dark surfaces
  static const darkBackground = Color(0xFF070D1C);
  static const darkCard = Color(0xFF0F172A);
  static const darkCardHigh = Color(0xFF16213A);
  static const darkTextPrimary = Color(0xFFE6EBF5);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkDivider = Color(0xFF1E293B);

  // Status
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFE8890C);
  static const error = Color(0xFFE5484D);
}

/// Semantic status colours that adapt to brightness, exposed as a ThemeExtension.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.successContainer,
    required this.warningContainer,
    required this.errorContainer,
    required this.textSecondary,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color successContainer;
  final Color warningContainer;
  final Color errorContainer;
  final Color textSecondary;

  static const light = StatusColors(
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
    successContainer: Color(0xFFE3F5EB),
    warningContainer: Color(0xFFFFF1DE),
    errorContainer: Color(0xFFFDE6E6),
    textSecondary: AppColors.textSecondary,
  );

  static const dark = StatusColors(
    success: Color(0xFF4CC788),
    warning: Color(0xFFFFB04D),
    error: Color(0xFFFF6B6B),
    successContainer: Color(0xFF12301F),
    warningContainer: Color(0xFF3A2808),
    errorContainer: Color(0xFF3A1414),
    textSecondary: AppColors.darkTextSecondary,
  );

  @override
  StatusColors copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? successContainer,
    Color? warningContainer,
    Color? errorContainer,
    Color? textSecondary,
  }) {
    return StatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      successContainer: successContainer ?? this.successContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      errorContainer: errorContainer ?? this.errorContainer,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

extension StatusColorsX on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}
