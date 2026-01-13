import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

/// A standardized rose-outlined action button with gradient background.
///
/// Use this widget for all primary CTA buttons that should have the brand
/// rose-accent styling (gradient background + rose border).
///
/// Features:
/// - Gradient background matching "Let's get this show started" hero card
/// - Rose-accent border at 20% opacity
/// - Optional leading icon
/// - Loading state with spinner
/// - Press micro-interaction (scale down to 98%)
/// - Full-width option for form contexts
class BrandActionButton extends StatefulWidget {
  const BrandActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
    this.height = 48.0,
  });

  /// Button label text
  final String label;

  /// Callback when button is pressed (null disables button)
  final VoidCallback? onPressed;

  /// Optional leading icon
  final IconData? icon;

  /// Shows loading spinner instead of content when true
  final bool isLoading;

  /// If true, button expands to fill available width
  final bool fullWidth;

  /// Button height (default 48.0)
  final double height;

  @override
  State<BrandActionButton> createState() => _BrandActionButtonState();
}

class _BrandActionButtonState extends State<BrandActionButton> {
  bool _isPressed = false;

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading;

  void _handleTapDown(TapDownDetails details) {
    if (_isEnabled) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: Spacing.space8),
              ],
              Text(
                widget.label,
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          );

    final button = GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _isEnabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _isPressed ? BrandButton.pressScale : 1.0,
        duration: BrandButton.pressDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _isEnabled ? 1.0 : 0.5,
          duration: BrandButton.pressDuration,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
            decoration: BrandButton.decoration,
            child: Center(child: content),
          ),
        ),
      ),
    );

    if (widget.fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}
