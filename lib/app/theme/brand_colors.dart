import 'package:flutter/material.dart';
import 'design_tokens.dart';

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceOverlay,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.primary,
    required this.primaryDim,
    required this.primaryContainer,
    required this.primaryLight,
    required this.primarySubtle,
    required this.success,
    required this.warning,
    required this.error,
    required this.appBarBg,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceOverlay;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color primary;
  final Color primaryDim;
  final Color primaryContainer;
  final Color primaryLight;
  final Color primarySubtle;
  final Color success;
  final Color warning;
  final Color error;
  final Color appBarBg;

  static const dark = BrandColors(
    background: Color(0xFF09090B),
    surface: Color(0xFF18181B),
    surfaceElevated: Color(0xFF27272A),
    surfaceOverlay: Color(0xFF3F3F46),
    border: Color(0xFF27272A),
    borderStrong: Color(0xFF52525B),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFA1A1AA),
    textMuted: Color(0xFF71717A),
    textDisabled: Color(0xFF52525B),
    primary: AppColors.primary,
    primaryDim: Color(0xFFBE123C),
    primaryContainer: Color(0xFF1C0A12),
    primaryLight: Color(0xFFFB7185),
    primarySubtle: Color(0x4DF43F5E),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    error: AppColors.error,
    appBarBg: Color(0xFF09090B),
  );

  static const light = BrandColors(
    background: Color(0xFFF8FAFC), // Slate 50 - oklch(98.4% 0.003 247.858)
    surface: Color(0xFFFAFAFA),
    surfaceElevated: Color(0xFFF4F4F5),
    surfaceOverlay: Color(0xFFE4E4E7),
    border: Color(0xFFE4E4E7),
    borderStrong: Color(0xFFA1A1AA),
    textPrimary: Color(0xFF020617), // Slate 950
    textSecondary: Color(0xFF020617), // Slate 950
    textMuted: Color(0xFF020617), // Slate 950
    textDisabled: Color(0xFFD4D4D8),
    primary: AppColors.primary,
    primaryDim: Color(0xFFBE123C),
    primaryContainer: Color(0xFFFFF1F2),
    primaryLight: Color(0xFFFB7185),
    primarySubtle: Color(0x1AF43F5E),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    error: AppColors.error,
    appBarBg: Color(0xFF18181B),
  );

  @override
  BrandColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? primary,
    Color? primaryDim,
    Color? primaryContainer,
    Color? primaryLight,
    Color? primarySubtle,
    Color? success,
    Color? warning,
    Color? error,
    Color? appBarBg,
  }) =>
      BrandColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textDisabled: textDisabled ?? this.textDisabled,
        primary: primary ?? this.primary,
        primaryDim: primaryDim ?? this.primaryDim,
        primaryContainer: primaryContainer ?? this.primaryContainer,
        primaryLight: primaryLight ?? this.primaryLight,
        primarySubtle: primarySubtle ?? this.primarySubtle,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        appBarBg: appBarBg ?? this.appBarBg,
      );

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDim: Color.lerp(primaryDim, other.primaryDim, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      appBarBg: Color.lerp(appBarBg, other.appBarBg, t)!,
    );
  }
}

extension BrandColorsX on BuildContext {
  BrandColors get colors {
    final ext = Theme.of(this).extension<BrandColors>();
    assert(ext != null, 'BrandColors not registered in ThemeData.extensions');
    return ext ?? BrandColors.dark;
  }
}
