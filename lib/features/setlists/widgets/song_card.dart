import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';
import 'animated_value_text.dart';

// ============================================================================
// SONG CARD
// Figma: Rose/500 border (#F43F5E) 1.5px, 8px radius
// Layout:
// - Drag handle icon (left, 6px from edge)
// - Song title (20px white semibold, 36px from left)
// - Artist name (16px gray, below title)
// - Delete icon (top right, rose/red)
// - Tags row: BPM, Duration, Tuning (with colored backgrounds)
// Card height: 121px
// ============================================================================

class SongCard extends StatefulWidget {
  final SetlistSong song;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showDragHandle;
  final bool showDeleteIcon;

  const SongCard({
    super.key,
    required this.song,
    this.onTap,
    this.onDelete,
    this.showDragHandle = true,
    this.showDeleteIcon = true,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: AppDurations.instant,
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
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Container(
          width: double.infinity,
          height: 121,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            border: Border.all(
              color: AppColors.accent, // Rose/500 #F43F5E
              width: StandardCardBorder.width, // 1.5px - matches Setlist cards
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius), // 8px
          ),
          child: Stack(
            children: [
              // Drag handle icon - positioned 6px from left, 13px from top
              if (widget.showDragHandle)
                Positioned(
                  left: SongCardLayout.dragHandleLeft,
                  top: 13,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 24,
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),

              // Content area with shared padding
              Padding(
                padding: EdgeInsets.only(
                  left: SongCardLayout.contentLeftPadding,
                  right: SongCardLayout.cardHorizontalPadding,
                  top: SongCardLayout.cardVerticalPadding,
                  bottom: SongCardLayout.cardVerticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: title/artist left + trash right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title/Artist block
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.song.title,
                                style: AppTextStyles.title3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.song.artist,
                                style: AppTextStyles.callout,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Trash icon
                        if (widget.showDeleteIcon)
                          SizedBox(
                            width: SongCardLayout.trashIconHitSize,
                            height: SongCardLayout.trashIconHitSize,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: SongCardLayout.trashIconSize,
                              onPressed: widget.onDelete,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const Spacer(),

                    // Metrics row with fixed columns
                    _buildMetricsRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Metrics row with fixed-width columns for deterministic alignment.
  /// Uses AnimatedValueText for placeholder support and animated transitions.
  Widget _buildMetricsRow() {
    return SizedBox(
      height: SongCardLayout.metricsRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // BPM column (fixed width, left-aligned)
          SizedBox(
            width: SongCardLayout.bpmColWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildBpmValue(),
            ),
          ),

          // Gutter
          const SizedBox(width: SongCardLayout.metricsGutter),

          // Duration column (fixed width, left-aligned)
          SizedBox(
            width: SongCardLayout.durationColWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildDurationValue(),
            ),
          ),

          // Flexible spacer + tuning (takes remaining space, right-aligned)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildTuningBadge(),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds BPM value with placeholder support and animation
  Widget _buildBpmValue() {
    return AnimatedValueText(
      displayText: widget.song.formattedBpm,
      isPlaceholder: widget.song.isBpmPlaceholder,
      onTap: null, // Read-only card
      backgroundColor: const Color(0xFF2C2C2C),
    );
  }

  /// Builds Duration value with animation
  Widget _buildDurationValue() {
    return AnimatedValueText(
      displayText: widget.song.formattedDuration,
      isPlaceholder: false,
      onTap: null, // Read-only card
      backgroundColor: const Color(0xFF2C2C2C),
    );
  }

  /// Build the tuning badge with short label and proper color
  /// NO border - filled background only, pill shape
  Widget _buildTuningBadge() {
    final tuning = widget.song.tuning;
    final shortLabel = tuningShortLabel(tuning);
    final bgColor = tuningBadgeColor(tuning);
    final textColor = tuningBadgeTextColor(bgColor);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        // NO border - filled background only
        borderRadius: BorderRadius.circular(100), // Pill shape
      ),
      child: Text(
        shortLabel,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1,
        ),
      ),
    );
  }
}
