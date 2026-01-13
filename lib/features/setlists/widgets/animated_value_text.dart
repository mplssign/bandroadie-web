import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// ANIMATED VALUE TEXT
// Animates transitions between placeholder "—" and real values with
// fade + slide-up effect.
//
// Usage:
//   AnimatedValueText(
//     displayText: song.formattedBpm ?? '—',
//     isPlaceholder: song.formattedBpm == null,
//   )
// ============================================================================

/// Animated text widget for BPM/Duration values.
/// Transitions smoothly when value changes from null to set (or vice versa).
class AnimatedValueText extends StatelessWidget {
  /// The text to display ("—" for placeholder, or actual value)
  final String displayText;

  /// Whether this is a placeholder (affects styling only, not interactivity)
  final bool isPlaceholder;

  /// Optional tap handler (always enabled if provided, even for placeholders)
  final VoidCallback? onTap;

  /// Text style override (defaults to 14pt semibold)
  final TextStyle? textStyle;

  /// Background color for the tag container
  final Color backgroundColor;

  /// Border color override (e.g., rose/500 for override indicator)
  /// If null, uses white border by default
  final Color? borderColor;

  /// Whether the field is currently focused/being edited
  /// When true, shows rose/500 border
  final bool isFocused;

  const AnimatedValueText({
    super.key,
    required this.displayText,
    this.isPlaceholder = false,
    this.onTap,
    this.textStyle,
    this.backgroundColor = const Color(0xFF2C2C2C),
    this.borderColor,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    // Use ValueKey to trigger AnimatedSwitcher when text changes
    final content = _buildContent();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        // Fade + slide up transition
        final slideAnimation = Tween<Offset>(
          begin: const Offset(
            0,
            0.3,
          ), // Start 30% below (≈8px for typical height)
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slideAnimation, child: child),
        );
      },
      child: content,
    );
  }

  Widget _buildContent() {
    final effectiveStyle =
        textStyle ??
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isPlaceholder ? AppColors.textMuted : const Color(0xFFF5F5F5),
          height: 1,
        );

    // Determine border color:
    // 1. If focused -> rose/500 (AppColors.accent)
    // 2. If override exists (borderColor provided) -> use that color
    // 3. Default -> white
    final effectiveBorderColor = isFocused
        ? AppColors.accent
        : (borderColor ?? Colors.white);
    final effectiveBorderWidth = isFocused || borderColor != null ? 2.0 : 1.0;

    // Always show bordered container for consistent "input field" appearance
    // Tap is always enabled if onTap is provided (even for placeholders)
    return GestureDetector(
      key: ValueKey('${isPlaceholder ? "placeholder" : "value"}_$displayText'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: effectiveBorderColor,
            width: effectiveBorderWidth,
          ),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Text(
          displayText,
          style: effectiveStyle,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}
