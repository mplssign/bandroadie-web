import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

// ============================================================================
// EMPTY SECTION CARD
// Reusable card for empty states with animated CTA button and Figma polish.
// ============================================================================

class EmptySectionCard extends StatefulWidget {
  final IconData? icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onButtonPressed;

  const EmptySectionCard({
    super.key,
    this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.onButtonPressed,
  });

  @override
  State<EmptySectionCard> createState() => _EmptySectionCardState();
}

class _EmptySectionCardState extends State<EmptySectionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _buttonController;
  late Animation<double> _buttonScale;

  @override
  void initState() {
    super.initState();
    _buttonController = AnimationController(
      duration: AppDurations.medium,
      vsync: this,
    );
    _buttonScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _buttonController, curve: AppCurves.rubberband),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced motion accessibility setting
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _buttonController.value = 1.0; // Skip animation
    } else if (!_buttonController.isCompleted) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _buttonController.forward();
      });
    }
  }

  @override
  void dispose() {
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.space24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
        border: Border.all(color: AppColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon with subtle background (only if icon is provided)
          if (widget.icon != null) ...[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(widget.icon, color: AppColors.textMuted, size: 28),
            ),
            const SizedBox(height: Spacing.space16),
          ],

          // Title (matches SectionHeader style: 16px bold)
          Text(
            widget.title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
          ),

          const SizedBox(height: Spacing.space8),

          // Subtitle
          Text(
            widget.subtitle,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),

          const SizedBox(height: Spacing.space20),

          // CTA button with scale animation
          ScaleTransition(
            scale: _buttonScale,
            child: BrandActionButton(
              label: widget.buttonLabel,
              onPressed: widget.onButtonPressed,
              icon: Icons.add_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
