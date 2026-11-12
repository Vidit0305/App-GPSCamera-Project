import 'package:flutter/material.dart';

/// App typography built on the bundled Inter font.
abstract final class AppTypography {
  static const fontFamily = 'Inter';

  static TextTheme textTheme(Color primary, Color secondary) {
    // fontFamily is applied explicitly because component themes (buttons,
    // inputs) take these styles directly, before ThemeData merges its font.
    return const TextTheme().merge(TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.4),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.3),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primary, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primary, height: 1.4),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: secondary, height: 1.35),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary, letterSpacing: 0.1),
      labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: secondary, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondary, letterSpacing: 0.4),
    )).apply(fontFamily: fontFamily);
  }
}
