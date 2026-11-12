import 'package:flutter/material.dart';

/// ──────────────────────────────────────────────
/// منصة أونلاين — Design System: Navy + Royal Blue + Gold
/// ──────────────────────────────────────────────
/// The single source of the app's colors.
///
/// * [lightScheme] / [darkScheme] are the hand-tuned default brand schemes.
/// * [fromCenterColor] builds a center's (white-label) scheme from its
///   `primary_color`: the chromatic roles are generated from the seed, while
///   the gold tertiary (platform identity), the semantic colors and the
///   neutral surfaces stay fixed, so every center still reads as the same app.
///
/// Screens should read colors through `Theme.of(context).colorScheme` or
/// `context.palette` (theme-aware). The static constants further down are
/// either brand-fixed (gold, semantic, social) or legacy light/dark values
/// kept for existing call sites — prefer the scheme for anything new.
/// ──────────────────────────────────────────────
class AppColors {
  AppColors._();

  // ─── Brand (fixed — platform identity) ───
  static const Color defaultPrimary = Color(0xFF0B3D91);
  static const Color defaultSecondary = Color(0xFF1769E0);
  static const Color gold = Color(0xFFF4B942);
  static const Color goldDark = Color(0xFFFFD980);
  static const Color onGold = Color(0xFF1A1200);
  static const Color goldContainer = Color(0xFFFFF0CC);
  static const Color goldContainerDark = Color(0xFF4A3800);

  // ─── Semantic (fixed in every center theme) ───
  static const Color success = Color(0xFF198754);
  static const Color successDark = Color(0xFF75D9A3);
  static const Color warning = Color(0xFFFD7E14);
  static const Color warningDark = Color(0xFFFFB86C);
  static const Color error = Color(0xFFDC3545);
  static const Color errorDark = Color(0xFFFFB4AB);
  static const Color info = Color(0xFF1769E0);
  static const Color infoDark = Color(0xFFB4CFFF);

  /// Identity alias of [error] — some screens call this slot "danger".
  static const Color danger = error;

  // ─── Default schemes ───
  static const Color lightBackground = Color(0xFFFAFBFE);
  static const Color darkBackgroundColor = Color(0xFF0F1118);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0B3D91),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD4E3FF),
    onPrimaryContainer: Color(0xFF001B3F),
    secondary: Color(0xFF1769E0),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDBE8FF),
    onSecondaryContainer: Color(0xFF001A44),
    tertiary: gold,
    onTertiary: onGold,
    tertiaryContainer: goldContainer,
    onTertiaryContainer: Color(0xFF261A00),
    error: error,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1C2E),
    onSurfaceVariant: Color(0xFF44475E),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF5F7FB),
    surfaceContainer: Color(0xFFEEF1F8),
    surfaceContainerHigh: Color(0xFFE8ECF5),
    surfaceContainerHighest: Color(0xFFF0F3F9),
    outline: Color(0xFF757889),
    outlineVariant: Color(0xFFC5C6D9),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2F3142),
    onInverseSurface: Color(0xFFF1F0F7),
    inversePrimary: Color(0xFFA8C8FF),
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA8C8FF),
    onPrimary: Color(0xFF002F6B),
    primaryContainer: Color(0xFF0A2E6E),
    onPrimaryContainer: Color(0xFFD4E3FF),
    secondary: Color(0xFFB4CFFF),
    onSecondary: Color(0xFF003580),
    secondaryContainer: Color(0xFF0E4FAA),
    onSecondaryContainer: Color(0xFFDBE8FF),
    tertiary: goldDark,
    onTertiary: Color(0xFF3D2E00),
    tertiaryContainer: goldContainerDark,
    onTertiaryContainer: goldContainer,
    error: errorDark,
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF15171F),
    onSurface: Color(0xFFE3E4F0),
    onSurfaceVariant: Color(0xFFC5C6D9),
    surfaceContainerLowest: Color(0xFF0F1118),
    surfaceContainerLow: Color(0xFF1A1C26),
    surfaceContainer: Color(0xFF1F2232),
    surfaceContainerHigh: Color(0xFF292C3E),
    surfaceContainerHighest: Color(0xFF1D2030),
    outline: Color(0xFF8F90A3),
    outlineVariant: Color(0xFF44475E),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE3E4F0),
    onInverseSurface: Color(0xFF2F3142),
    inversePrimary: Color(0xFF0B3D91),
    surfaceTint: Colors.transparent,
  );

  /// Scheme for a center's [seedColor]. [DynamicSchemeVariant.fidelity] keeps
  /// the generated primary close to the center's exact brand color (a plain
  /// tonal-spot seed would wash it out). Gold tertiary, semantic colors and
  /// the neutral surfaces come from the default scheme.
  static ColorScheme fromCenterColor(Color seedColor, Brightness brightness) {
    final base = brightness == Brightness.light ? lightScheme : darkScheme;
    if (seedColor.toARGB32() == defaultPrimary.toARGB32()) return base;
    final seeded = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return base.copyWith(
      primary: seeded.primary,
      onPrimary: seeded.onPrimary,
      primaryContainer: seeded.primaryContainer,
      onPrimaryContainer: seeded.onPrimaryContainer,
      secondary: seeded.secondary,
      onSecondary: seeded.onSecondary,
      secondaryContainer: seeded.secondaryContainer,
      onSecondaryContainer: seeded.onSecondaryContainer,
      inversePrimary: seeded.inversePrimary,
    );
  }

  /// Background behind the scheme's surfaces (scaffold color).
  static Color backgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightBackground : darkBackgroundColor;

  // ─── Skeleton loading ───
  static const Color shimmerBase = Color(0xFFF0F0F0);
  static const Color shimmerHighlight = Color(0xFFE0E0E0);
  static const Color shimmerBaseDark = Color(0xFF2A2A2A);
  static const Color shimmerHighlightDark = Color(0xFF3A3A3A);

  // ─── Social / third-party brand colors (fixed by those brands) ───
  static const Color whatsapp = Color(0xFF25D366);
  static const Color facebook = Color(0xFF1877F2);
  static const Color youtube = Color(0xFFFF0000);
  static const Color telegram = Color(0xFF29B6F6);
  static const Color instagram = Color(0xFFC13584);
  static const List<Color> instagramGradient = [
    Color(0xFFF58529),
    Color(0xFFDD2A7B),
    Color(0xFF8134AF),
  ];
  static const Color tiktok = Color(0xFF000000);
  static const Color twitter = Color(0xFF1DA1F2);

  /// Categorical colors for subject icons (one per subject, by index).
  static const List<Color> subjectPalette = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFF44336),
    Color(0xFF3F51B5),
  ];

  // ─────────────────────────────────────────────────────────────────────
  // Legacy constants — kept so existing call sites compile. They do NOT
  // follow the center color or dark mode; use the scheme / palette instead.
  // ─────────────────────────────────────────────────────────────────────

  // Primary (Royal Navy)
  static const Color primary = defaultPrimary;
  static const Color primaryLight = defaultSecondary;
  static const Color primaryDark = Color(0xFF072B6B);
  static const Color primarySurface = Color(0xFFD4E3FF);
  static const Color primaryBorder = Color(0xFFC5C6D9);
  static const Color primaryMuted = Color(0xFFEEF1F8);
  static const Color brand = primary;
  static const Color brandDark = primaryDark;

  // Accent (Gold)
  static const Color accent = gold;
  static const Color accentLight = Color(0xFFF8CC6F);
  static const Color accentSurface = goldContainer;

  // Semantic tints
  static const Color successLight = Color(0xFFD1E7DD);
  static const Color warningLight = Color(0xFFFFE5D0);
  static const Color errorLight = Color(0xFFFFDAD6);
  static const Color infoLight = Color(0xFFDBE8FF);

  // Neutral (light)
  static const Color background = lightBackground;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F3F9);
  static const Color border = Color(0xFFC5C6D9);
  static const Color borderLight = Color(0xFFE8ECF5);
  static const Color divider = Color(0xFFE8ECF5);

  // Text (light)
  static const Color textPrimary = Color(0xFF1A1C2E);
  static const Color textSecondary = Color(0xFF44475E);
  static const Color textTertiary = Color(0xFF757889);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // Dark mode
  static const Color darkPrimary = Color(0xFFA8C8FF);
  static const Color darkBackground = darkBackgroundColor;
  static const Color darkSurface = Color(0xFF15171F);
  static const Color darkSurfaceVariant = Color(0xFF1D2030);
  static const Color darkBorder = Color(0xFF44475E);
  static const Color darkTextPrimary = Color(0xFFE3E4F0);
  static const Color darkTextSecondary = Color(0xFFC5C6D9);
  static const Color darkTextTertiary = Color(0xFF8F90A3);

  // Gradients (static navy — prefer `AppDecorations.gradientHeader`)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  static const LinearGradient bannerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight, Color(0xFF2E5FAE)],
    stops: [0.0, 0.7, 1.0],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [brand, brandDark],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primarySurface, accentSurface],
  );

  // --- Smart UI identity (entry screens: AppTheme.smartBrand) ---
  static const smartBlue = Color(0xFF2440E6);
  static const smartGold = Color(0xFFFFC23D);
  static const smartNavy = Color(0xFF10183A);
  static const smartMist = Color(0xFFF2F4FA);

  static final ColorScheme smartLightScheme =
      ColorScheme.fromSeed(
        seedColor: smartBlue,
        brightness: Brightness.light,
      ).copyWith(
        primary: smartBlue,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE3E8FF),
        onPrimaryContainer: smartNavy,
        secondary: const Color(0xFF1B2FB0),
        onSecondary: Colors.white,
        tertiary: smartGold,
        onTertiary: smartNavy,
        tertiaryContainer: const Color(0xFFFFF1CC),
        onTertiaryContainer: smartNavy,
        surface: Colors.white,
        onSurface: smartNavy,
        onSurfaceVariant: const Color(0xFF5A6385),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF7F8FC),
        surfaceContainer: smartMist,
        surfaceContainerHigh: const Color(0xFFE9ECF6),
        surfaceContainerHighest: const Color(0xFFE1E5F2),
        outline: const Color(0xFF8A92B2),
        outlineVariant: const Color(0xFFD9DEEC),
      );

  static final ColorScheme smartDarkScheme =
      ColorScheme.fromSeed(
        seedColor: smartBlue,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF7086FF),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFF22306E),
        onPrimaryContainer: const Color(0xFFE3E8FF),
        secondary: smartBlue,
        onSecondary: Colors.white,
        tertiary: smartGold,
        onTertiary: smartNavy,
        tertiaryContainer: const Color(0xFF4A3B12),
        onTertiaryContainer: const Color(0xFFFFE7A8),
        surface: const Color(0xFF18224A),
        onSurface: smartMist,
        onSurfaceVariant: const Color(0xFFAAB2D0),
        surfaceContainerLowest: const Color(0xFF0C1330),
        surfaceContainerLow: const Color(0xFF151E42),
        surfaceContainer: const Color(0xFF1B2550),
        surfaceContainerHigh: const Color(0xFF212C5A),
        surfaceContainerHighest: const Color(0xFF283466),
        outline: const Color(0xFF7A84AA),
        outlineVariant: const Color(0xFF2E3A6B),
      );
}
