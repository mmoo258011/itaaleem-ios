import 'package:flutter/material.dart';

/// Material 3 type scale in Cairo.
///
/// Letter spacing is deliberately 0 on every style: Cairo is set almost
/// entirely in Arabic here, and any tracking breaks the joins between
/// connected Arabic letters (the M3 values are tuned for Latin text).
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Cairo';

  /// Bundled (assets/fonts): the smart UI's font, for the entry screens.
  static const String smartFontFamily = 'ReadexPro';

  /// Monospace for codes / long numbers (system fallback chain).
  static const String monoFamily = 'monospace';
  static const List<String> monoFallback = ['JetBrains Mono', 'Courier'];

  static TextTheme textTheme(
    Color onSurface,
    Color onSurfaceVariant, {
    String family = fontFamily,
  }) {
    TextStyle style(
      double size,
      FontWeight weight,
      double height, [
      Color? color,
    ]) => TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
      color: color ?? onSurface,
    );

    // Hierarchy: headlines bold 24-32, titles semibold 15-22, body regular
    // 12-16, labels medium 11-14. Body line heights are taller than M3's
    // Latin defaults — Arabic diacritics and Cairo's tall ascenders need
    // the room to stay readable in multi-line text.
    return TextTheme(
      displayLarge: style(57, FontWeight.w700, 1.12),
      displayMedium: style(45, FontWeight.w700, 1.16),
      displaySmall: style(36, FontWeight.w700, 1.22),
      headlineLarge: style(32, FontWeight.w700, 1.25),
      headlineMedium: style(28, FontWeight.w700, 1.29),
      headlineSmall: style(24, FontWeight.w700, 1.33),
      titleLarge: style(22, FontWeight.w700, 1.36),
      titleMedium: style(18, FontWeight.w600, 1.44),
      titleSmall: style(15, FontWeight.w600, 1.47),
      bodyLarge: style(16, FontWeight.w400, 1.6),
      bodyMedium: style(14, FontWeight.w400, 1.57),
      bodySmall: style(12, FontWeight.w400, 1.5, onSurfaceVariant),
      labelLarge: style(14, FontWeight.w600, 1.43),
      labelMedium: style(12, FontWeight.w500, 1.33),
      labelSmall: style(11, FontWeight.w500, 1.45, onSurfaceVariant),
    );
  }

  /// For codes, OTPs and tabular numbers.
  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
