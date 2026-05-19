import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CATEGORY BUTTON
// Reusable full-width button with icon, label, subtitle, and press animation.
// Used in Add to Setlist modal and empty setlist states.
// ============================================================================

class CategoryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? accentColor;
  final VoidCallback onTap;

  const CategoryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.accentColor,
    required this.onTap,
  });

  @override
  State<CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<CategoryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _pressController.forward();
  void _handleTapUp(TapUpDetails details) => _pressController.reverse();
  void _handleTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space20,
            vertical: Spacing.space16,
          ),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: context.colors.border, width: 1.5),
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (widget.accentColor ?? AppColors.primary).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 22,
                  color: widget.accentColor ?? AppColors.primary,
                ),
              ),

              const SizedBox(width: Spacing.space16),

              // Label + Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTextStyles.headline.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: AppTextStyles.body.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                AppIcons.forward,
                size: 24,
                color: context.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
