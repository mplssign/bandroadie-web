import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

// Extra colour tokens scoped to the event editor drawer.
const Color kEdSurface = Color(0xFF0C0C0E);
const Color kEdCardBg = Color(0xFF101013);
const Color kEdCardBorder = Color(0xFF1F1F23);
const Color kEdInputFill = Color(0xFF131316);
const Color kEdPlaceholder = Color(0xFF52525B);
const Color kEdSegmentedBorder = Color(0xFF26262B);
const Color kEdSuccessBg = Color(0xFF052E16);
const Color kEdSuccessBorder = Color(0xFF166534);
const Color kEdSuccessIcon = Color(0xFF4ADE80);
const Color kEdDangerBg = Color(0xFF450A0A);
const Color kEdDangerBorder = Color(0xFF991B1B);
const Color kEdMutedForegroundFaint = Color(0xFF71717A);

/// Creates the Forui theme scoped to the event editor drawer.
FThemeData buildEventEditorTheme() {
  final colors = FColors.neutralDark.copyWith(
    background: kEdSurface,
    foreground: const Color(0xFFFAFAFA),
    primary: const Color(0xFFfb2c5a),
    primaryForeground: Colors.white,
    secondary: const Color(0xFF141417),
    secondaryForeground: const Color(0xFFa1a1aa),
    muted: kEdCardBg,
    mutedForeground: const Color(0xFF8b8b93),
    destructive: const Color(0xFFf87171),
    destructiveForeground: Colors.white,
    error: const Color(0xFFf87171),
    errorForeground: Colors.white,
    card: kEdSurface,
    border: const Color(0xFF27272a),
    systemOverlayStyle: SystemUiOverlayStyle.light,
  );

  return FThemeData(colors: colors, touch: true);
}
