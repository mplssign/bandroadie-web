import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'brand_colors.dart';
import 'design_tokens.dart';

/// BandRoadie App Theme
/// Dark mode only, Material 3, Zinc palette + Rose-500 accent.
/// All colors delegate to AppColors — no raw Color() literals here.
class AppTheme {
  AppTheme._();

  // ========================================
  // COLOR SCHEME
  // ========================================

  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
    surface: BrandColors.dark.surface,
  ).copyWith(
    // Override M3 tonal surfaces with our Zinc ramp
    surface: BrandColors.dark.surface,
    surfaceContainerLow: BrandColors.dark.surface,
    surfaceContainer: BrandColors.dark.surfaceElevated,
    surfaceContainerHigh: BrandColors.dark.surfaceElevated,
    surfaceContainerHighest: BrandColors.dark.surfaceElevated,
    // Borders
    outline: BrandColors.dark.border,
    outlineVariant: BrandColors.dark.border,
    // Semantic
    error: AppColors.error,
    // Text
    onSurface: BrandColors.dark.textPrimary,
    onSurfaceVariant: BrandColors.dark.textSecondary,
  );

  // ========================================
  // THEME DATA
  // ========================================

  static ThemeData get darkTheme {
    const bc = BrandColors.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _colorScheme,
      scaffoldBackgroundColor: bc.background,
      extensions: const [BrandColors.dark],

      // ----------------------------------------
      // APP BAR
      // ----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: bc.background,
        foregroundColor: bc.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: bc.textPrimary,
          fontSize: AppFontSizes.title2,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.primary),
      ),

      // ----------------------------------------
      // FILLED BUTTON (Primary action)
      // ----------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: bc.textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // ELEVATED BUTTON
      // ----------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: bc.textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // TEXT BUTTON (Secondary action)
      // ----------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
              fontSize: AppFontSizes.subhead, fontWeight: FontWeight.w500),
        ),
      ),

      // ----------------------------------------
      // OUTLINED BUTTON
      // ----------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // INPUT DECORATION (Text fields)
      // ----------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bc.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bc.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: TextStyle(color: bc.textMuted, fontSize: AppFontSizes.body),
        labelStyle: TextStyle(color: bc.textSecondary),
      ),

      // ----------------------------------------
      // BOTTOM NAVIGATION BAR
      // ----------------------------------------
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bc.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: bc.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ----------------------------------------
      // NAVIGATION BAR (Material 3 style)
      // ----------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bc.background,
        indicatorColor: bc.primarySubtle,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.primary);
          }
          return IconThemeData(color: bc.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: AppColors.primary,
              fontSize: AppFontSizes.caption,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: bc.textSecondary,
            fontSize: AppFontSizes.caption,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ----------------------------------------
      // CARD
      // ----------------------------------------
      cardTheme: CardThemeData(
        color: bc.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      // ----------------------------------------
      // ICON
      // ----------------------------------------
      iconTheme: IconThemeData(color: bc.textPrimary, size: 24),

      // ----------------------------------------
      // TEXT (DM Sans font)
      // ----------------------------------------
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.statLarge,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.modalTitle,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.sectionTitle,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.title2,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.body,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
            fontFamily: 'Geist',
            color: bc.textPrimary,
            fontSize: AppFontSizes.body),
        bodyMedium: TextStyle(
            fontFamily: 'Geist',
            color: bc.textSecondary,
            fontSize: AppFontSizes.subhead),
        bodySmall: TextStyle(
            fontFamily: 'Geist',
            color: bc.textMuted,
            fontSize: AppFontSizes.caption),
        labelLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ----------------------------------------
      // DEFAULT FONT FAMILY
      // ----------------------------------------
      fontFamily: 'Geist',

      // ----------------------------------------
      // DIVIDER
      // ----------------------------------------
      dividerTheme: DividerThemeData(
        color: bc.border,
        thickness: 1,
      ),

      // ----------------------------------------
      // SNACKBAR
      // ----------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bc.surfaceElevated,
        contentTextStyle:
            TextStyle(color: bc.textPrimary, fontSize: AppFontSizes.subhead),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  // ========================================
  // LIGHT COLOR SCHEME
  // ========================================

  static final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    surface: const Color(0xFFFAFAFA),
  ).copyWith(
    surface: const Color(0xFFFAFAFA),
    surfaceContainerLow: const Color(0xFFFAFAFA),
    surfaceContainer: const Color(0xFFF4F4F5),
    surfaceContainerHigh: const Color(0xFFF4F4F5),
    surfaceContainerHighest: const Color(0xFFF4F4F5),
    outline: const Color(0xFFE4E4E7),
    outlineVariant: const Color(0xFFE4E4E7),
    error: AppColors.error,
    onSurface: const Color(0xFF18181B),
    onSurfaceVariant: const Color(0xFF020617), // Slate 950
  );

  // ========================================
  // LIGHT THEME DATA
  // ========================================

  static ThemeData get lightTheme {
    const bc = BrandColors.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      scaffoldBackgroundColor: bc.background,
      extensions: const [BrandColors.light],

      // ----------------------------------------
      // APP BAR
      // ----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: bc.appBarBg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: AppFontSizes.title2,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: bc.primary),
      ),

      // ----------------------------------------
      // FILLED BUTTON (Primary action)
      // ----------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: bc.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // ELEVATED BUTTON
      // ----------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bc.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // TEXT BUTTON (Secondary action)
      // ----------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: bc.primary,
          textStyle: const TextStyle(
              fontSize: AppFontSizes.subhead, fontWeight: FontWeight.w500),
        ),
      ),

      // ----------------------------------------
      // OUTLINED BUTTON
      // ----------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: bc.primary,
          side: BorderSide(color: bc.primary.withValues(alpha: 0.5)),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: AppFontSizes.body, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // INPUT DECORATION (Text fields)
      // ----------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bc.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bc.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bc.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: TextStyle(color: bc.textMuted, fontSize: AppFontSizes.body),
        labelStyle: TextStyle(color: bc.textSecondary),
      ),

      // ----------------------------------------
      // BOTTOM NAVIGATION BAR
      // ----------------------------------------
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bc.background,
        selectedItemColor: bc.primary,
        unselectedItemColor: bc.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: AppFontSizes.caption,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ----------------------------------------
      // NAVIGATION BAR (Material 3 style)
      // ----------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bc.background,
        indicatorColor: bc.primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: bc.primary);
          }
          return IconThemeData(color: bc.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: bc.primary,
              fontSize: AppFontSizes.caption,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: bc.textSecondary,
            fontSize: AppFontSizes.caption,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ----------------------------------------
      // CARD
      // ----------------------------------------
      cardTheme: CardThemeData(
        color: bc.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      // ----------------------------------------
      // ICON
      // ----------------------------------------
      iconTheme: IconThemeData(color: bc.textPrimary, size: 24),

      // ----------------------------------------
      // TEXT (DM Sans font)
      // ----------------------------------------
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.statLarge,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.modalTitle,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.sectionTitle,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.title2,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.body,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
            fontFamily: 'Geist',
            color: bc.textPrimary,
            fontSize: AppFontSizes.body),
        bodyMedium: TextStyle(
            fontFamily: 'Geist',
            color: bc.textSecondary,
            fontSize: AppFontSizes.subhead),
        bodySmall: TextStyle(
            fontFamily: 'Geist',
            color: bc.textMuted,
            fontSize: AppFontSizes.caption),
        labelLarge: TextStyle(
          fontFamily: 'Geist',
          color: bc.textPrimary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ----------------------------------------
      // DEFAULT FONT FAMILY
      // ----------------------------------------
      fontFamily: 'Geist',

      // ----------------------------------------
      // DIVIDER
      // ----------------------------------------
      dividerTheme: DividerThemeData(
        color: bc.border,
        thickness: 1,
      ),

      // ----------------------------------------
      // SNACKBAR
      // ----------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bc.surfaceElevated,
        contentTextStyle:
            TextStyle(color: bc.textPrimary, fontSize: AppFontSizes.subhead),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  // ========================================
  // FORUI THEME
  // ========================================

  /// Builds Forui theme data from Forui's Neutral preset, overriding only
  /// the primary accent color to BandRoadie's brand color (Rose-700).
  /// Other colors (background, surface, text, etc.) intentionally remain
  /// Forui's stock Neutral palette — brand colors can be layered in
  /// incrementally in a future cycle if needed.
  static FThemeData foruiTheme(Brightness brightness) {
    final baseColors = brightness == Brightness.light
        ? FColors.neutralLight
        : FColors.neutralDark;

    final colors = baseColors.copyWith(
      primary: AppColors.primary, // shadcn/Forui Rose #FF2056
      // primaryForeground stays near-white in both modes — shadcn/Forui Rose is a
      // dark, saturated color, so text/icons on top of it need a light
      // foreground regardless of overall page brightness. Matches the
      // existing precedent in this file's Material filledButtonTheme
      // (light theme hardcodes Colors.white; dark theme's bc.textPrimary
      // is #FAFAFA — both effectively near-white).
      primaryForeground: Colors.white,
    );

    return FThemeData(colors: colors, touch: true).copyWith(
      switchStyle: FSwitchStyleDelta.delta(
        trackColor: FVariantsValueDelta.delta([
          FVariantValueDeltaOperation.base(AppColors.switchTrackOff),
          FVariantValueDeltaOperation.match(
            {FSwitchVariant.selected},
            AppColors.primarySoft,
          ),
        ]),
        thumbColor: FVariantsValueDelta.delta([
          FVariantValueDeltaOperation.all(Colors.white),
        ]),
      ),
    );
  }
}
