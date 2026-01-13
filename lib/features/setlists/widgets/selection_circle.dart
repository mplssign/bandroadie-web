import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// SELECTION CIRCLE
// Animated circular selection control for multi-select mode in Catalog.
//
// STATES:
// - Unselected: Empty outlined circle with subtle border
// - Selected: Rose-700 filled circle with white checkmark, scale animation
//
// INTERACTIONS:
// - Tap toggles selection state
// - Haptic feedback on selection change
// - Scale animation (1.0 → 1.15 → 1.0) on selection
//
// DESIGN:
// - Size: 24x24px (matches drag handle icon)
// - Border: 2px slate-500 when unselected
// - Fill: Rose-700 when selected
// - Checkmark: White, 14px icon
// ============================================================================

class SelectionCircle extends StatefulWidget {
  /// Whether this item is currently selected
  final bool isSelected;

  /// Called when the selection state should toggle
  final VoidCallback? onToggle;

  /// Size of the circle (default 24px)
  final double size;

  const SelectionCircle({
    super.key,
    required this.isSelected,
    this.onToggle,
    this.size = 24.0,
  });

  @override
  State<SelectionCircle> createState() => _SelectionCircleState();
}

class _SelectionCircleState extends State<SelectionCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Scale: 1.0 → 1.15 → 1.0 (bounce effect)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);

    // Fade in the checkmark
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // If already selected on build, set to end state
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SelectionCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate when selection state changes
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward(from: 0);
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onToggle == null) return;

    // Haptic feedback on selection change
    HapticFeedback.lightImpact();
    widget.onToggle!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size + 12, // Extra hit target area
        height: widget.size + 12,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isSelected
                        ? AppColors.accent
                        : Colors.transparent,
                    border: Border.all(
                      color: widget.isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: widget.isSelected
                      ? Opacity(
                          opacity: _fadeAnimation.value,
                          child: Icon(
                            Icons.check_rounded,
                            size: widget.size * 0.65,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
