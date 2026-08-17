import 'package:flutter/material.dart';
import 'calendar_markers.dart';

/// Color constants for event indicators (from Figma design)
class CalendarColors {
  CalendarColors._();

  /// Blue indicator for confirmed rehearsals (#2563EB)
  static const Color rehearsalIndicator = Color(MarkerColors.rehearsalColor);

  /// Green indicator for confirmed gigs (#65A30D)
  static const Color gigIndicator = Color(MarkerColors.gigColor);

  /// Rose indicator for block outs (#F43F5E)
  static const Color blockOutIndicator = Color(MarkerColors.blockOutColor);

  /// Orange indicator for potential gigs and rehearsals (#EA580C)
  /// Matches the lighter gradient color on potential event cards.
  static const Color potentialIndicator = Color(MarkerColors.potentialColor);
}
