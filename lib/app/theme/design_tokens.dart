import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// BANDROADIE DESIGN TOKENS
// Matches Figma spec node 5:11 exactly.
// ============================================================================

/// Spacing tokens from Figma
class Spacing {
  Spacing._();

  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space13 = 13.0;
  static const double space14 = 14.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space37 = 37.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space53 = 53.0;
  static const double space56 = 56.0;
  static const double space64 = 64.0;

  /// Figma: 16px horizontal page padding
  static const double pagePadding = 16.0;

  /// Figma: rehearsal card radius 16px
  static const double cardRadius = 16.0;

  /// Figma: gig card / button radius 8px
  static const double buttonRadius = 8.0;

  /// Figma: chip radius 16px (pill shape)
  static const double chipRadius = 16.0;

  /// Figma: app bar height 41px
  static const double appBarHeight = 41.0;

  /// Figma: bottom nav height 68px
  static const double bottomNavHeight = 68.0;

  /// Rehearsal card height (increased for spacing)
  static const double rehearsalCardHeight = 130.0;

  /// Figma: gig card height 126px
  static const double gigCardHeight = 126.0;

  /// Figma: active nav item 80x53
  static const double navItemWidth = 80.0;
  static const double navItemHeight = 53.0;
}

// =============================================================================
// SONG CARD LAYOUT CONSTANTS
// Fixed column widths for deterministic alignment across cards.
// =============================================================================

/// Layout constants for SongCard metrics row
class SongCardLayout {
  SongCardLayout._();

  /// Total height of the metrics row
  static const double metricsRowHeight = 36.0;

  /// Gutter between BPM and Duration columns
  static const double metricsGutter = 12.0;

  /// Fixed width for BPM column (must fit '999 BPM' on one line)
  static const double bpmColWidth = 90.0;

  /// Fixed width for Duration column
  static const double durationColWidth = 80.0;

  /// Fixed width for trailing tuning badge column
  static const double trailingColWidth = 100.0;

  /// Card horizontal padding (left/right from content edge)
  static const double cardHorizontalPadding = 16.0;

  /// Card vertical padding
  static const double cardVerticalPadding = 14.0;

  /// Drag handle offset from left edge
  static const double dragHandleLeft = 6.0;

  /// Content left padding (after drag handle)
  static const double contentLeftPadding = 36.0;

  /// Trash icon size
  static const double trashIconSize = 22.0;

  /// Trash icon tappable hit target size
  static const double trashIconHitSize = 40.0;

  /// Border radius for editable input fields
  static const double inputBorderRadius = 10.0;

  /// Border width for editable input fields
  static const double inputBorderWidth = 1.0;

  /// Border color for editable input fields (white with opacity)
  static const Color inputBorderColor = Color(0x59FFFFFF); // white @ 35%
}

// =============================================================================
// BPM FORMATTING HELPERS
// Consistent BPM display across all widgets
// =============================================================================

/// Format BPM value for display.
///
/// Returns:
/// - `'- BPM'` if bpm is null, 0, or negative
/// - `'<bpm> BPM'` otherwise (e.g., `'132 BPM'`)
///
/// Use this everywhere BPM is displayed to ensure consistency.
String formatBpm(int? bpm) {
  if (bpm == null || bpm <= 0) {
    return '- BPM';
  }
  return '$bpm BPM';
}

/// Color palette from Figma
class AppColors {
  AppColors._();

  // Primary accent - Tailwind rose-700 #be123c
  static const Color accent = Color(0xFFBE123C);
  static const Color accentMuted = Color(0x33F43F5E);

  // Blue accent - Figma: #2563eb for borders
  static const Color blueAccent = Color(0xFF2563EB);

  // Backgrounds - Figma specs
  static const Color scaffoldBg = Color(0xFF1E1E1E); // Figma: brand-hover
  static const Color appBarBg = Color(0xFF1E293B); // Figma: gray-800
  static const Color surfaceDark = Color(0xFF1E293B); // gray-800
  static const Color cardBg = Color(0xFF1E1E1E);
  static const Color cardBgElevated = Color(0xFF252525);
  static const Color navBg = Color(0xFF020617); // Figma: gray-950

  // Borders - Figma specs
  static const Color borderSubtle = Color(0xFF94A3B8); // gray-400
  static const Color borderMuted = Color(0xFF334155); // gray-700
  static const Color borderBlue = Color(0xFF2563EB); // blue-600

  // Text hierarchy - Figma specs
  static const Color textPrimary = Color(0xFFFFFFFF); // white
  static const Color textSecondary = Color(0xFF94A3B8); // gray-400
  static const Color textMuted = Color(0xFF64748B); // gray-500
  static const Color textDisabled = Color(0xFF475569); // gray-600
  static const Color textNav = Color(0xFFF8FAFC); // gray-50

  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Gradients - Figma: rehearsal card gradient
  static const LinearGradient rehearsalGradient = LinearGradient(
    begin: Alignment(-0.8, -0.6),
    end: Alignment(0.8, 0.6),
    colors: [Color(0xFF2563EB), Color(0xFF9333EA)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E1E1E), Color(0xFF0A0A0A)],
  );

  /// Setlist card animated gradient border colors (Figma-style)
  /// Rose → Blue → Cyan → Purple → Orange → Rose (loops)
  static const List<Color> setlistGradientColors = [
    Color(0xFFF43F5E), // Rose-500 (primary accent)
    Color(0xFF2563EB), // Blue-600
    Color(0xFF06B6D4), // Cyan-500
    Color(0xFFC026D3), // Fuchsia-600
    Color(0xFFEA580C), // Orange-600
    Color(0xFFF43F5E), // Rose-500 (loop back)
  ];
}

/// Setlist card border constants
class SetlistCardBorder {
  SetlistCardBorder._();

  /// Border thickness for animated gradient
  static const double width = 2.0;

  /// Border radius (matches card radius)
  static const double radius = 20.0;

  /// Minimum animation duration in milliseconds
  static const int minDurationMs = 2500;

  /// Maximum animation duration in milliseconds
  static const int maxDurationMs = 7500;
}

/// Standard card border constants (shared across Calendar events, non-Catalog setlists)
class StandardCardBorder {
  StandardCardBorder._();

  /// Border color - matches Calendar event cards (#334155)
  static const Color color = Color(0xFF334155);

  /// Border width - matches Calendar event cards
  static const double width = 1.5;

  /// Get a BorderSide with standard styling
  static BorderSide get side => const BorderSide(color: color, width: width);
}

/// Brand action button styling (rose-outlined buttons)
/// Matches the "Let's get this show started" hero card styling
class BrandButton {
  BrandButton._();

  /// Background gradient: rose accent with prominent visibility
  static LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.accent.withValues(alpha: 0.30),
      AppColors.accent.withValues(alpha: 0.15),
    ],
  );

  /// Border color: accent @ 60% opacity for prominence
  static Color get borderColor => AppColors.accent.withValues(alpha: 0.6);

  /// Border width
  static const double borderWidth = 1.5;

  /// Border radius
  static const double radius = 8.0;

  /// Get a BoxDecoration for brand buttons
  static BoxDecoration get decoration => BoxDecoration(
    gradient: gradient,
    border: Border.all(color: borderColor, width: borderWidth),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.accent.withValues(alpha: 0.25),
        blurRadius: 12,
        spreadRadius: 0,
        offset: const Offset(0, 2),
      ),
    ],
  );

  /// Get a BorderSide for OutlinedButton styling
  static BorderSide get side =>
      BorderSide(color: borderColor, width: borderWidth);

  /// Press scale factor for micro-interaction
  static const double pressScale = 0.98;

  /// Animation duration for press feedback
  static const Duration pressDuration = Duration(milliseconds: 100);
}

/// Animation durations
class AppDurations {
  AppDurations._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration entrance = Duration(milliseconds: 400);
}

/// Custom curves for "rubberband" and fluid feel
class AppCurves {
  AppCurves._();

  /// Standard ease out for most transitions
  static const Curve ease = Curves.easeOutCubic;

  /// Snappy entrance with slight overshoot
  static const Curve overshoot = Curves.elasticOut;

  /// Smooth decelerate for slide-ins
  static const Curve slideIn = Curves.easeOutQuart;

  /// Bounce-like for playful elements
  static const Curve bounce = Curves.bounceOut;

  /// Custom rubberband curve (controlled overshoot)
  static Curve get rubberband => const _RubberbandCurve();
}

/// Custom curve with controlled overshoot
class _RubberbandCurve extends Curve {
  const _RubberbandCurve();

  @override
  double transformInternal(double t) {
    // Slight overshoot around 0.8, then settle
    if (t == 0) return 0;
    if (t == 1) return 1;
    final oneMinusT = 1 - t;
    return -0.5 * oneMinusT * oneMinusT * oneMinusT +
        1.5 * oneMinusT * oneMinusT +
        t;
  }
}

/// Typography styles - Using DM Sans font
class AppTextStyles {
  AppTextStyles._();

  // Title3/Emphasized - 20px, weight 600, line-height 25px
  static TextStyle get title3 => GoogleFonts.dmSans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25, // 25/20
  );

  // Headline/Regular - 17px, weight 600, line-height 22px
  static TextStyle get headline => GoogleFonts.dmSans(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.29, // 22/17
  );

  // Callout/Regular - 16px, weight 400, line-height 21px
  static TextStyle get callout => GoogleFonts.dmSans(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.31, // 21/16
  );

  // Callout/Emphasized - 16px, weight 600, line-height 21px
  static TextStyle get calloutEmphasized => GoogleFonts.dmSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.31,
  );

  // Footnote/Emphasized - 13px, weight 600, line-height 18px
  static TextStyle get footnote => GoogleFonts.dmSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.38, // 18/13
  );

  // Nav label - 11px, weight 600, line-height 12px
  static TextStyle get navLabel => GoogleFonts.dmSans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textNav,
    height: 1.09, // 12/11
  );

  // Legacy aliases for compatibility
  static TextStyle get displayLarge => title3.copyWith(fontSize: 28);
  static TextStyle get displayMedium => title3;
  static TextStyle get sectionHeader => title3;
  static TextStyle get cardTitle => title3;
  static TextStyle get cardSubtitle => callout;
  static TextStyle get body => callout;
  static TextStyle get label => footnote;

  // Button and badge styles
  static TextStyle get button => GoogleFonts.dmSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.31,
  );

  static TextStyle get badge => GoogleFonts.dmSans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.09,
  );
}
