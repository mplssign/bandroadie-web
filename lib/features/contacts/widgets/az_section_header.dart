import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// AZ SECTION HEADER
// Shared section-letter header used by the A-Z list segments.
// ============================================================================

class AzSectionHeader extends StatelessWidget {
  final String letter;
  final double rightPadding;

  const AzSectionHeader({
    super.key,
    required this.letter,
    required this.rightPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space8,
        rightPadding,
        Spacing.space8,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: AppFontSizes.pageTitle,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
