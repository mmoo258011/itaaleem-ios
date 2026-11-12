import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:itaaleem/core/theme/app_colors.dart';
import 'package:itaaleem/core/theme/app_page_transitions.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_shadows.dart';
import 'package:itaaleem/core/theme/app_typography.dart';

/// Builds the app's Material 3 [ThemeData] (light + dark).
///
/// Without a [centerColor] the hand-tuned default brand schemes are used
/// ([AppColors.lightScheme] / [AppColors.darkScheme]); with one, the scheme is
/// generated from it ([AppColors.fromCenterColor]). Every component theme is
/// derived from the scheme, so a center's color re-tints the whole app.
/// Screens read colors/text styles through `Theme.of(context)` — never a hex.
class AppTheme {
  AppTheme._();

  static ThemeData light({Color? centerColor}) => _build(
    AppColors.fromCenterColor(
      centerColor ?? AppColors.defaultPrimary,
      Brightness.light,
    ),
  );

  /// The smart UI's identity for the screens every student sees before
  /// the app knows their center (login, sign-up, join, complete profile):
  /// #2440E6 / #FFC23D / #10183A / #F2F4FA and Readex Pro.
  static ThemeData smartBrand(Brightness brightness) =>
      brightness == Brightness.dark
      ? _build(
          AppColors.smartDarkScheme,
          family: AppTypography.smartFontFamily,
          background: AppColors.smartNavy,
        )
      : _build(
          AppColors.smartLightScheme,
          family: AppTypography.smartFontFamily,
          background: AppColors.smartMist,
        );

  static ThemeData dark({Color? centerColor}) => _build(
    AppColors.fromCenterColor(
      centerColor ?? AppColors.defaultPrimary,
      Brightness.dark,
    ),
  );

  /// Legacy neutral shadows — prefer [AppShadows] with the scheme's shadow.
  static List<BoxShadow> get shadowSm => AppShadows.sm(Colors.black);
  static List<BoxShadow> get shadowMd => AppShadows.md(Colors.black);
  static List<BoxShadow> get shadowLg => AppShadows.lg(Colors.black);

  static ThemeData _build(
    ColorScheme s, {
    String family = AppTypography.fontFamily,
    Color? background,
  }) {
    GoogleFonts.cairo();
    final isDark = s.brightness == Brightness.dark;
    final pageBackground = background ?? AppColors.backgroundFor(s.brightness);
    final text = AppTypography.textTheme(
      s.onSurface,
      s.onSurfaceVariant,
      family: family,
    );
    final hairline = s.outlineVariant.withValues(alpha: 0.5);
    final faintLine = s.outlineVariant.withValues(alpha: 0.3);
    final disabledFg = s.onSurface.withValues(alpha: 0.38);
    final disabledBg = s.onSurface.withValues(alpha: 0.12);

    RoundedRectangleBorder rounded(double radius, [BorderSide? side]) =>
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: side ?? BorderSide.none,
        );

    TextStyle cairo(double size, FontWeight weight, [Color? color]) =>
        TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: 0,
          color: color,
        );

    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: color, width: width),
        );

    // Shared by every button: 52px tall, 14px corners, bold 16px label.
    final buttonShape = rounded(AppRadius.button);
    final buttonText = cairo(16, FontWeight.w700);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);

    return ThemeData(
      useMaterial3: true,
      brightness: s.brightness,
      colorScheme: s,
      fontFamily: family,
      textTheme: text,
      primaryColor: s.primary,
      scaffoldBackgroundColor: pageBackground,
      canvasColor: pageBackground,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: s.onSurface, size: 24),
      disabledColor: disabledFg,

      // Blends into the page instead of sitting on it as a separate strip;
      // a soft shadow only appears once content scrolls underneath.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        toolbarHeight: 60,
        backgroundColor: pageBackground,
        foregroundColor: s.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: s.shadow.withValues(alpha: isDark ? 0.4 : 0.12),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: cairo(18, FontWeight.w700, s.onSurface),
        iconTheme: IconThemeData(color: s.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: s.onSurface, size: 24),
        actionsPadding: const EdgeInsetsDirectional.only(end: 4),
      ),

      // Flat cards: a hairline border instead of a shadow.
      cardTheme: CardThemeData(
        elevation: 0,
        color: s.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: s.shadow.withValues(alpha: 0.05),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: rounded(
          AppRadius.card,
          BorderSide(
            color: isDark ? s.onSurface.withValues(alpha: 0.08) : hairline,
          ),
        ),
      ),

      // Primary CTA. Minimum width stays finite (not double.infinity) so a
      // button inside a Row never throws; full-width buttons stretch via their
      // parent (see `AppButton(expand: true)`).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: s.primary,
              disabledForegroundColor: disabledFg,
              minimumSize: const Size.fromHeight(52),
              padding: buttonPadding,
              shape: buttonShape,
              textStyle: buttonText,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? disabledBg
                      : s.primary,
                  width: 1.5,
                ),
              ),
            ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.primary,
          disabledForegroundColor: disabledFg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: buttonShape,
          textStyle: cairo(14, FontWeight.w700),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          disabledForegroundColor: disabledFg,
          shape: rounded(AppRadius.md),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: rounded(AppRadius.lg),
        extendedTextStyle: cairo(15, FontWeight.w700),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputBorder(hairline, 1),
        enabledBorder: inputBorder(hairline, 1),
        disabledBorder: inputBorder(faintLine, 1),
        focusedBorder: inputBorder(s.primary, 1.5),
        errorBorder: inputBorder(s.error, 1),
        focusedErrorBorder: inputBorder(s.error, 1.5),
        hintStyle: cairo(14, FontWeight.w400, s.onSurfaceVariant),
        labelStyle: cairo(14, FontWeight.w500, s.onSurfaceVariant),
        floatingLabelStyle: cairo(14, FontWeight.w600, s.primary),
        helperStyle: cairo(12, FontWeight.w400, s.onSurfaceVariant),
        errorStyle: cairo(12, FontWeight.w500, s.error),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? s.primary
              : s.onSurfaceVariant,
        ),
        suffixIconColor: s.onSurfaceVariant,
      ),

      // The shell uses its own bar (`AppBottomNav`); this keeps any stock
      // NavigationBar in the same style.
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? cairo(12, FontWeight.w700, s.primary)
              : cairo(12, FontWeight.w500, s.onSurfaceVariant),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? s.onPrimaryContainer
                : s.onSurfaceVariant,
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: s.surface,
        selectedItemColor: s.primary,
        unselectedItemColor: s.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: cairo(12, FontWeight.w700),
        unselectedLabelStyle: cairo(12, FontWeight.w500),
      ),

      // Rounded 3px indicator under the label, the width of the label.
      tabBarTheme: TabBarThemeData(
        labelColor: s.onPrimaryContainer,
        unselectedLabelColor: s.onSurfaceVariant,
        // Pill indicator, matching the web's segmented tabs.
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: s.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        dividerColor: faintLine,
        labelStyle: cairo(14, FontWeight.w700),
        unselectedLabelStyle: cairo(14, FontWeight.w500),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        splashBorderRadius: BorderRadius.circular(AppRadius.md),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: s.surfaceContainerLow,
        selectedColor: s.primaryContainer,
        disabledColor: disabledBg,
        checkmarkColor: s.onPrimaryContainer,
        showCheckmark: false,
        labelStyle: cairo(13, FontWeight.w600, s.onSurface),
        secondaryLabelStyle: cairo(13, FontWeight.w700, s.onPrimaryContainer),
        shape: const StadiumBorder(),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide(color: s.primary.withValues(alpha: 0.4))
              : BorderSide(color: hairline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        iconTheme: IconThemeData(color: s.onSurfaceVariant, size: 18),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: s.primaryContainer,
          selectedForegroundColor: s.onPrimaryContainer,
          foregroundColor: s.onSurfaceVariant,
          side: BorderSide(color: hairline),
          shape: rounded(AppRadius.md),
          textStyle: cairo(13, FontWeight.w600),
        ),
      ),

      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : s.outline,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: rounded(6),
        side: BorderSide(color: s.outline, width: 1.5),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: s.shadow.withValues(alpha: 0.2),
        shape: rounded(AppRadius.dialog),
        titleTextStyle: cairo(20, FontWeight.w700, s.onSurface),
        contentTextStyle: cairo(15, FontWeight.w400, s.onSurfaceVariant),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        modalBackgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.bottomSheet),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: s.outlineVariant,
        dragHandleSize: const Size(40, 4),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: s.shadow.withValues(alpha: 0.18),
        shape: rounded(AppRadius.md, BorderSide(color: faintLine)),
        textStyle: cairo(14, FontWeight.w500, s.onSurface),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(s.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(rounded(AppRadius.md)),
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded(AppRadius.dialog),
        headerHeadlineStyle: cairo(24, FontWeight.w700),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: s.surface,
        shape: rounded(AppRadius.dialog),
        hourMinuteShape: rounded(AppRadius.md),
        dayPeriodShape: rounded(AppRadius.md),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        elevation: 2,
        contentTextStyle: cairo(14, FontWeight.w500, s.onInverseSurface),
        actionTextColor: s.inversePrimary,
        shape: rounded(AppRadius.md),
        insetPadding: const EdgeInsets.all(16),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: s.error,
        textColor: s.onError,
        textStyle: cairo(10, FontWeight.w700),
      ),

      dividerTheme: DividerThemeData(color: faintLine, thickness: 1, space: 1),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
        horizontalTitleGap: 12,
        iconColor: s.onSurfaceVariant,
        shape: rounded(AppRadius.md),
        titleTextStyle: cairo(15, FontWeight.w600, s.onSurface),
        subtitleTextStyle: cairo(13, FontWeight.w400, s.onSurfaceVariant),
        leadingAndTrailingTextStyle: cairo(
          13,
          FontWeight.w500,
          s.onSurfaceVariant,
        ),
      ),

      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: s.primary,
        collapsedIconColor: s.onSurfaceVariant,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.primary,
        linearTrackColor: s.surfaceContainerHigh,
        linearMinHeight: 4,
        circularTrackColor: Colors.transparent,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: s.primary,
        inactiveTrackColor: s.surfaceContainerHigh,
        thumbColor: s.primary,
        trackHeight: 4,
      ),

      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(AppRadius.full),
        thickness: const WidgetStatePropertyAll(4),
        thumbColor: WidgetStatePropertyAll(
          s.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: s.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: cairo(12, FontWeight.w500, s.onInverseSurface),
      ),

      // Android: the app's own fade + direction-aware slide (the same one
      // GoRouter pages use). iOS keeps Cupertino for its swipe-back gesture.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Button styles that aren't the theme default.
class AppButtonStyles {
  AppButtonStyles._();

  /// Gold "premium" CTA (buy a book, upgrade a subscription).
  static ButtonStyle gold(ColorScheme s) => FilledButton.styleFrom(
    backgroundColor: s.tertiary,
    foregroundColor: s.onTertiary,
    elevation: 0,
    minimumSize: const Size(64, 52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
    textStyle: const TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Tonal square icon button (toolbars on light surfaces). Not the global
  /// `iconButtonTheme` on purpose: that would put a grey square behind every
  /// icon button, including the video player's overlay controls.
  static ButtonStyle tonalIcon(ColorScheme s) => IconButton.styleFrom(
    backgroundColor: s.surfaceContainerHigh,
    foregroundColor: s.onSurface,
    fixedSize: const Size(44, 44),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
  );
}
