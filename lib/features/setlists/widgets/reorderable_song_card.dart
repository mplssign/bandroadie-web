import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';
import 'tuning_picker_bottom_sheet.dart';

// ============================================================================
// REORDERABLE SONG CARD
// Variant of SongCard optimized for ReorderableListView with inline editing.
//
// RESPONSIVE LAYOUT:
// - Top row: Title/Artist (left) + Delete icon (right)
// - Bottom row (metrics): BPM | Duration | Edit | Tuning
//   - Uses MainAxisAlignment.spaceBetween for equidistant spacing
//   - BPM left-aligns with song title
//   - Tuning right-aligns with delete icon
//   - Spacing adjusts evenly as screen width changes
//
// Border: StandardCardBorder (#334155) 1.5px - matches non-Catalog setlist cards
// Card height: 121px
//
// EDITABLE FIELDS (tap-to-edit):
// - Tuning: bottom sheet selector
//
// MICRO-INTERACTIONS:
// - Tap: scale/opacity feedback
// - Drag: handled by parent ReorderableListView proxyDecorator
// ============================================================================

class ReorderableSongCard extends StatefulWidget {
  final SetlistSong song;
  final int index;
  final bool isDraggable;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Future<bool> Function(String tuning)? onTuningChanged;

  const ReorderableSongCard({
    super.key,
    required this.song,
    required this.index,
    this.isDraggable = true,
    this.onEdit,
    this.onDelete,
    this.onTuningChanged,
  });

  @override
  State<ReorderableSongCard> createState() => _ReorderableSongCardState();
}

class _ReorderableSongCardState extends State<ReorderableSongCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  // Saving/error states for tuning only
  bool _isSaving = false;
  String? _editError;

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

  // ============================================================
  // TUNING SELECTION
  // ============================================================

  Future<void> _selectTuning() async {
    if (_isSaving) return;

    final result = await showTuningPickerBottomSheet(
      context,
      selectedTuningIdOrName: widget.song.tuning,
    );

    if (result != null && result != widget.song.tuning) {
      setState(() {
        _isSaving = true;
      });

      final success = await widget.onTuningChanged?.call(result) ?? false;

      setState(() {
        _isSaving = false;
        if (!success) {
          _editError = 'Save failed';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Container(
          width: double.infinity,
          height: 121,
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            border: Border.all(
              color: StandardCardBorder.color,
              width: StandardCardBorder.width,
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Stack(
            children: [
              // Drag handle area - only shown when draggable
              // For Catalog, no drag handle is shown
              if (widget.isDraggable)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: SongCardLayout.contentLeftPadding,
                  child: ReorderableDragStartListener(
                    index: widget.index,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: SongCardLayout.dragHandleLeft,
                        ),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 24,
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),

              // Saving indicator
              if (_isSaving)
                Positioned(
                  right: 48,
                  top: 14,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.accent.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),

              // Content area - wrapped in Listener to prevent drag events from bubbling
              // This ensures only the drag handle can initiate reordering
              Positioned(
                left: SongCardLayout.contentLeftPadding,
                right: 0,
                top: 0,
                bottom: 0,
                child: Listener(
                  onPointerDown:
                      (_) {}, // Absorb pointer events to prevent drag
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: SongCardLayout.cardHorizontalPadding,
                      top: SongCardLayout.cardVerticalPadding,
                      bottom: SongCardLayout.cardVerticalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ============================================
                        // TOP ROW: Title/Artist (left) + Delete (right)
                        // Delete icon anchored to far right edge
                        // ============================================
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title/Artist block - left-aligned, takes available space
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
                            // Delete icon - anchored to far right
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

                        // Error message (if any)
                        if (_editError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _editError!,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                        // ============================================
                        // METRICS ROW: Responsive flexbox layout
                        // Left: BPM (fixed) | Right: Duration → Edit → Tuning (flex)
                        // ============================================
                        _buildMetricsRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Metrics row with equidistant spacing.
  ///
  /// LAYOUT STRUCTURE:
  /// [BPM] ←--equal space--→ [Duration] ←--equal space--→ [Edit] ←--equal space--→ [Tuning]
  ///
  /// Uses MainAxisAlignment.spaceBetween to distribute 4 elements evenly:
  /// - BPM anchors to left edge (aligns with song title above)
  /// - Tuning anchors to right edge (aligns with delete icon above)
  /// - Duration and Edit are distributed evenly in between
  /// - As screen width changes, spacing adjusts proportionally
  Widget _buildMetricsRow() {
    return SizedBox(
      height: SongCardLayout.metricsRowHeight,
      child: Row(
        // ================================================
        // EQUIDISTANT SPACING: spaceBetween distributes
        // elements evenly from left edge to right edge
        // ================================================
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ================================================
          // 1. BPM - anchors to left (aligns with title)
          // ================================================
          _buildBpmValue(),

          // ================================================
          // 2. DURATION - second element, evenly spaced
          // ================================================
          _buildDurationValue(),

          // ================================================
          // 3. EDIT ICON - third element, evenly spaced
          // ================================================
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              onPressed: widget.onEdit,
              icon: Icon(
                Icons.edit_outlined,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),

          // ================================================
          // 4. TUNING - anchors to right (aligns with delete)
          // ================================================
          _buildTuningBadge(),
        ],
      ),
    );
  }

  /// Builds BPM value display (read-only, no border)
  /// Shows "- BPM" placeholder if no BPM value set.
  /// Always returns a widget to maintain consistent spacing in spaceBetween layout.
  Widget _buildBpmValue() {
    return Text(
      widget.song.isBpmPlaceholder ? '- BPM' : widget.song.formattedBpm,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFFF5F5F5),
        height: 1,
      ),
    );
  }

  /// Builds Duration value display (read-only, no border)
  /// Shows "0:00" if no duration entered
  Widget _buildDurationValue() {
    return Text(
      widget.song.formattedDuration,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFFF5F5F5),
        height: 1,
      ),
    );
  }

  /// Builds the tuning badge with micro-interaction on tap
  /// NO border - filled background only, pill shape
  Widget _buildTuningBadge() {
    final tuning = widget.song.tuning;
    final shortLabel = tuningShortLabel(tuning);
    final bgColor = tuningBadgeColor(tuning);
    final textColor = tuningBadgeTextColor(bgColor);

    return GestureDetector(
      onTap: _isSaving ? null : _selectTuning,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: AppDurations.instant,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Container(
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
        ),
      ),
    );
  }
}
