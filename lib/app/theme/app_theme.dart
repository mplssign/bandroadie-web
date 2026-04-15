import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    surface: AppColors.surface,
  ).copyWith(
    // Override M3 tonal surfaces with our Zinc ramp
    surface: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surfaceElevated,
    surfaceContainerHigh: AppColors.surfaceElevated,
    surfaceContainerHighest: AppColors.surfaceElevated,
    // Borders
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    // Semantic
    error: AppColors.error,
    // Text
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
  );

  // ========================================
  // THEME DATA
  // ========================================

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _colorScheme,
      scaffoldBackgroundColor: AppColors.background,

      // ----------------------------------------
      // APP BAR
      // ----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
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
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // ELEVATED BUTTON
      // ----------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // TEXT BUTTON (Secondary action)
      // ----------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // INPUT DECORATION (Text fields)
      // ----------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
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
          borderSide: BorderSide(color: AppColors.border, width: 1),
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
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
        labelStyle: TextStyle(color: AppColors.textSecondary),
      ),

      // ----------------------------------------
      // BOTTOM NAVIGATION BAR
      // ----------------------------------------
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ----------------------------------------
      // NAVIGATION BAR (Material 3 style)
      // ----------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primarySubtle,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.primary);
          }
          return IconThemeData(color: AppColors.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ----------------------------------------
      // CARD
      // ----------------------------------------
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      // ----------------------------------------
      // ICON
      // ----------------------------------------
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),

      // ----------------------------------------
      // TEXT (DM Sans font)
      // ----------------------------------------
      textTheme: GoogleFonts.dmSansTextTheme(
        TextTheme(
          headlineLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 12),
          labelLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ----------------------------------------
      // DEFAULT FONT FAMILY
      // ----------------------------------------
      fontFamily: GoogleFonts.dmSans().fontFamily,

      // ----------------------------------------
      // DIVIDER
      // ----------------------------------------
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),

      // ----------------------------------------
      // SNACKBAR
      // ----------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
    onSurfaceVariant: const Color(0xFF71717A),
  );

  // ========================================
  // LIGHT THEME DATA
  // ========================================

  static ThemeData get lightTheme {
    // Light-mode inline colors (do NOT modify design_tokens.dart)
    const background = Color(0xFFFFFFFF);
    const surface = Color(0xFFFAFAFA);
    const surfaceElevated = Color(0xFFF4F4F5);
    const textPrimary = Color(0xFF18181B);
    const textSecondary = Color(0xFF71717A);
    const textMuted = Color(0xFFA1A1AA);
    const border = Color(0xFFE4E4E7);
    const primary = Color(0xFFF43F5E);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      scaffoldBackgroundColor: background,

      // ----------------------------------------
      // APP BAR
      // ----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: primary),
      ),

      // ----------------------------------------
      // FILLED BUTTON (Primary action)
      // ----------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // ELEVATED BUTTON
      // ----------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // TEXT BUTTON (Secondary action)
      // ----------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ----------------------------------------
      // OUTLINED BUTTON
      // ----------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.5)),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ----------------------------------------
      // INPUT DECORATION (Text fields)
      // ----------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
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
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: const TextStyle(color: textMuted, fontSize: 16),
        labelStyle: const TextStyle(color: textSecondary),
      ),

      // ----------------------------------------
      // BOTTOM NAVIGATION BAR
      // ----------------------------------------
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ----------------------------------------
      // NAVIGATION BAR (Material 3 style)
      // ----------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ----------------------------------------
      // CARD
      // ----------------------------------------
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      // ----------------------------------------
      // ICON
      // ----------------------------------------
      iconTheme: const IconThemeData(color: textPrimary, size: 24),

      // ----------------------------------------
      // TEXT (DM Sans font)
      // ----------------------------------------
      textTheme: GoogleFonts.dmSansTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(
            color: textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: TextStyle(
            color: textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: TextStyle(
            color: textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
          bodySmall: TextStyle(color: textMuted, fontSize: 12),
          labelLarge: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ----------------------------------------
      // DEFAULT FONT FAMILY
      // ----------------------------------------
      fontFamily: GoogleFonts.dmSans().fontFamily,

      // ----------------------------------------
      // DIVIDER
      // ----------------------------------------
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),

      // ----------------------------------------
      // SNACKBAR
      // ----------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
