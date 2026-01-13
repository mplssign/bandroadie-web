import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// ACTION BUTTONS ROW
// Figma: Horizontal row with outlined buttons
// - Song Lookup: Search icon + text, rose border
// - Bulk Paste: List icon + text, rose border
// - Share: Share icon only, rose border
// Buttons: 8px radius, 16px horizontal padding, 8px vertical padding
// ============================================================================

class ActionButtonsRow extends StatelessWidget {
  final VoidCallback? onSongLookup;
  final VoidCallback? onBulkPaste;
  final VoidCallback? onShare;

  const ActionButtonsRow({
    super.key,
    this.onSongLookup,
    this.onBulkPaste,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Song Lookup button
        _ActionButton(
          icon: Icons.search_rounded,
          label: 'Song Lookup',
          onTap: onSongLookup,
        ),

        const SizedBox(width: 8),

        // Bulk Paste button
        _ActionButton(
          icon: Icons.list_rounded,
          label: 'Bulk Paste',
          onTap: onBulkPaste,
        ),

        const SizedBox(width: 8),

        // Share button (icon only)
        _ActionButton(icon: Icons.ios_share_rounded, onTap: onShare),
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
              color: AppColors.accent, // Rose #F43F5E
              width: 2,
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: AppColors.accent),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
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
