import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist.dart';
import 'animated_gradient_border.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// SETLIST CARD
// Figma: Animated gradient border, 20px radius, 16px padding
// Title: 20px white semibold
// Metadata: 16px gray "X songs • Xh XXm"
// ============================================================================

class SetlistCard extends StatefulWidget {
  final Setlist setlist;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int index;
  final bool isDraggable;

  const SetlistCard({
    super.key,
    required this.setlist,
    this.onTap,
    this.onLongPress,
    this.index = 0,
    this.isDraggable = false,
  });

  @override
  State<SetlistCard> createState() => _SetlistCardState();
}

class _SetlistCardState extends State<SetlistCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late GradientAnimationConfig _gradientConfig;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: AppDurations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));

    // Deterministic animation config based on setlist ID
    _gradientConfig = GradientAnimationConfig.fromId(widget.setlist.id);
  }

  @override
  void didUpdateWidget(SetlistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate config if setlist ID changes
    if (oldWidget.setlist.id != widget.setlist.id) {
      _gradientConfig = GradientAnimationConfig.fromId(widget.setlist.id);
    }
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _tapController.reverse();
  }

  void _handleTapCancel() {
    _tapController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final innerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Setlist name - Figma: Title3/Emphasized
        // Show star icon for Catalog setlist
        Row(
          children: [
            if (widget.setlist.isCatalog) ...[
              const Icon(AppIcons.star, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                widget.setlist.name,
                style: AppTextStyles.title3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.space8),
        // Metadata - Figma: Callout/Regular gray
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${widget.setlist.formattedMetadata} ',
                style: AppTextStyles.callout,
              ),
              TextSpan(
                text: '• ',
                style: AppTextStyles.callout.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: widget.setlist.formattedDuration,
                style: AppTextStyles.callout,
              ),
            ],
          ),
        ),
      ],
    );

    // ── Draggable variant ──
    // Matches ReorderableSongCard pattern exactly.
    if (widget.isDraggable) {
      return GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: AnimatedBuilder(
          animation: _tapController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(opacity: _opacityAnimation.value, child: child),
            );
          },
          child: IntrinsicHeight(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                border: Border.all(
                  color: StandardCardBorder.color,
                  width: StandardCardBorder.width,
                ),
                borderRadius: BorderRadius.circular(SetlistCardBorder.radius),
              ),
              child: Row(
                children: [
                  // Drag handle area
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: SizedBox(
                      width: SongCardLayout.contentLeftPadding,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: SongCardLayout.dragHandleLeft,
                          ),
                          child: Icon(
                            AppIcons.drag,
                            size: 24,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Content area
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: Spacing.space16,
                          top: Spacing.space16,
                          bottom: Spacing.space16,
                        ),
                        child: innerContent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Non-draggable variant (Catalog) — original layout ──
    final cardContent = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: widget.setlist.isCatalog
          ? null // Catalog uses AnimatedGradientBorder
          : BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(SetlistCardBorder.radius),
              border: Border.all(
                color: StandardCardBorder.color,
                width: StandardCardBorder.width,
              ),
            ),
      child: innerContent,
    );

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: widget.setlist.isCatalog
            ? AnimatedGradientBorder(
                config: _gradientConfig,
                child: cardContent,
              )
            : cardContent,
      ),
    );
  }
}
