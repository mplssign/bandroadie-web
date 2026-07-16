import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// ACTION BUTTONS ROW
// Figma: Horizontal row with outlined buttons
// - + Add to Setlist: Plus icon + text, rose border (opens unified overlay)
// - Share: Share icon only, rose border
// Buttons: 8px radius, 16px horizontal padding, 8px vertical padding
// ============================================================================

typedef ShareCallback = Function(BuildContext context);

class ActionButtonsRow extends StatelessWidget {
  final VoidCallback? onAddToSetlist;
  final ShareCallback? onShare;

  const ActionButtonsRow({
    super.key,
    this.onAddToSetlist,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // + Add to Setlist button
        _ActionButton(
          icon: AppIcons.add,
          label: 'Add to Setlist',
          onTap: onAddToSetlist,
        ),

        const SizedBox(width: 8),

        // Share button (icon only)
        // Wrap share callback to provide context
        _ActionButton(
          icon: AppIcons.share,
          onTap: onShare != null ? () => onShare!(context) : null,
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, this.label, this.onTap});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppDurations.instant,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _controller.forward();
  void _handleTapUp(TapUpDetails details) => _controller.reverse();
  void _handleTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space8,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.primary, // Rose #F43F5E
              width: 2,
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: AppColors.primary),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label!,
                  style: const TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
