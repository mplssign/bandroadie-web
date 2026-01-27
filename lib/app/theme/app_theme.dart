import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// BandRoadie App Theme
/// Dark mode only, Material 3, rose accent (#BE123C)
/// Font: Ubuntu (Google Fonts) - App name uses Rock Salt
class AppTheme {
  AppTheme._();

  // ========================================
  // COLORS
  // ========================================

  /// Primary brand color — rose
  static const Color primaryColor = Color(0xFFBE123C);

  /// Dark background — almost black
  static const Color scaffoldBackground = Color(0xFF1E1E1E);

  /// Surface color — slightly lighter than background
  static const Color surfaceColor = Color(0xFF252525);

  /// Card/elevated surface
  static const Color cardColor = Color(0xFF2A2A2A);

  // ========================================
  // COLOR SCHEME
  // ========================================

  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: Brightness.dark,
    surface: surfaceColor,
  );

  // ========================================
  // THEME DATA
  // ========================================

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _colorScheme,

      // Custom dark background
      scaffoldBackgroundColor: scaffoldBackground,

      // ----------------------------------------
      // APP BAR
      // ----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: _colorScheme.primary),
      ),

      // ----------------------------------------
      // FILLED BUTTON (Primary action)
      // ----------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _colorScheme.primary,
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
          backgroundColor: _colorScheme.primary,
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
          foregroundColor: _colorScheme.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ----------------------------------------
      // OUTLINED BUTTON
      // ----------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _colorScheme.primary,
          side: BorderSide(color: _colorScheme.primary.withValues(alpha: 0.5)),
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
        fillColor: cardColor,
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
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorScheme.error, width: 2),
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 16,
        ),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      ),

      // ----------------------------------------
      // BOTTOM NAVIGATION BAR
      // ----------------------------------------
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        selectedItemColor: _colorScheme.primary,
        unselectedItemColor: Colors.white.withValues(alpha: 0.5),
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
        backgroundColor: scaffoldBackground,
        indicatorColor: _colorScheme.primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: _colorScheme.primary);
          }
          return IconThemeData(color: Colors.white.withValues(alpha: 0.5));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: _colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ----------------------------------------
      // CARD
      // ----------------------------------------
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      // ----------------------------------------
      // ICON
      // ----------------------------------------
      iconTheme: const IconThemeData(color: Colors.white, size: 24),

      // ----------------------------------------
      // TEXT (DM Sans font)
      // ----------------------------------------
      textTheme: GoogleFonts.dmSansTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
          bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
          bodySmall: TextStyle(color: Colors.white70, fontSize: 12),
          labelLarge: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ----------------------------------------
      // DEFAULT FONT FAMILY
      // ----------------------------------------
      fontFamily: GoogleFonts.interTight().fontFamily,

      // ----------------------------------------
      // DIVIDER
      // ----------------------------------------
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.1),
        thickness: 1,
      ),

      // ----------------------------------------
      // SNACKBAR
      // ----------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        // Softer, slower animation for enter/exit
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
