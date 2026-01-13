import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// SECTION HEADER
// Figma: Title3/Emphasized - 20px, weight 590, line-height 25px
// Title case (not uppercase) per Figma mock
//
// SPACING: Use `topSpacing` to maintain consistent vertical rhythm between
// sections. Default is Spacing.sectionGap for uniform section cadence.
// ============================================================================

/// Standard spacing above section headers for consistent vertical rhythm
const double kSectionTopSpacing = Spacing.space40;

class SectionHeader extends StatelessWidget {
  final String title;

  /// Spacing above the section header. Use null to disable top spacing.
  /// Defaults to kSectionTopSpacing for consistent vertical rhythm.
  final double? topSpacing;

  const SectionHeader({
    super.key,
    required this.title,
    this.topSpacing = kSectionTopSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final header = Text(
      title,
      style: GoogleFonts.dmSans(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
      ),
    );

    if (topSpacing == null || topSpacing == 0) {
      return header;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topSpacing),
        header,
      ],
    );
  }
}
