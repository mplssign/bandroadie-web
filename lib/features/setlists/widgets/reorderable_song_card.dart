import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_progress_indicator.dart';
import '../../lyrics/models/lyrics_data.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';
import 'tuning_picker_bottom_sheet.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../components/ui/app_card.dart';

// ============================================================================
// REORDERABLE SONG CARD
// Variant of SongCard optimized for ReorderableListView with inline editing.
//
// METRICS LAYOUT:
// - Top row: Title/Artist (left) + Delete icon (right)
// - Bottom row (metrics): BPM | Duration | Key | Tuning
//   - Uses shared list-level widths for stable alignment
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

class SongMetricsSharedWidths {
  final double bpmWidth;
  final double durationWidth;
  final double keyWidth;
  final double tuningWidth;

  const SongMetricsSharedWidths({
    required this.bpmWidth,
    required this.durationWidth,
    required this.keyWidth,
    required this.tuningWidth,
  });

  double get totalWidth => bpmWidth + durationWidth + keyWidth + tuningWidth;
}

class ReorderableSongCard extends StatefulWidget {
  final SetlistSong song;
  final int index;
  final SongMetricsSharedWidths sharedWidths;
  final bool isDraggable;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLyricsView;
  final Future<bool> Function(String tuning)? onTuningChanged;

  const ReorderableSongCard({
    super.key,
    required this.song,
    required this.index,
    required this.sharedWidths,
    this.isDraggable = true,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onLyricsView,
    this.onTuningChanged,
  });

  /// Whether the song has non-empty lyrics content.
  bool get hasLyrics {
    final lyrics = LyricsData.fromJsonString(song.lyrics);
    return lyrics.isNotEmpty;
  }

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
    widget.onTap?.call();
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

    if (result != null) {
      final String? newTuning;
      if (result.tuningId.isEmpty) {
        newTuning = null;
      } else {
        // Compose the compound tuning string (e.g. "standard_e|capo:3")
        newTuning = composeCapoTuning(result.tuningId, result.capoFret) ??
            result.tuningId;
      }

      if (newTuning != widget.song.tuning) {
        setState(() {
          _isSaving = true;
        });

        final success =
            await widget.onTuningChanged?.call(newTuning ?? '') ?? false;

        setState(() {
          _isSaving = false;
          if (!success) {
            _editError = 'Save failed';
          }
        });
      }
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
        child: AppCard(
          padding: EdgeInsets.zero,
          height: 121,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          child: Container(
            width: double.infinity,
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
                            AppIcons.drag,
                            size: 24,
                            color: context.colors.textSecondary
                                .withValues(alpha: 0.6),
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
                      child: AppProgressIndicator(),
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
                                      style: AppTextStyles.title3.copyWith(
                                        color: context.colors.textPrimary,
                                      ),
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
                              // Lyrics icon - shown only when song has lyrics
                              // Top-aligns with title, right-aligns with tuning badge
                              if (widget.hasLyrics)
                                GestureDetector(
                                  onTap: widget.onLyricsView,
                                  behavior: HitTestBehavior.opaque,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      AppIcons.lyrics,
                                      color: AppColors.primary,
                                      size: 28,
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
                                  color: AppColors.primary,
                                  fontSize: AppFontSizes.caption,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          // ============================================
                          // METRICS ROW: Fixed columns for stable alignment
                          // BPM | Duration | Key | Tuning
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
      ),
    );
  }

  /// Metrics row with shared list-level column positions.
  ///
  /// LAYOUT STRUCTURE:
  /// [BPM] [Duration] [Key] [Tuning]
  ///
  /// BPM, Duration, and Key use shared-width left-aligned slots.
  /// Tuning uses a shared-width right-aligned slot.
  /// Tuning uses shared width and is the only
  /// column allowed to truncate when space is tight.
  /// The Key slot remains reserved even when the song has no key so all
  /// metric values stay in the same horizontal positions.
  Widget _buildMetricsRow() {
    final hasKey = widget.song.musicalKey != null &&
        widget.song.musicalKey!.trim().isNotEmpty;

    return SizedBox(
      height: SongCardLayout.metricsRowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shared = widget.sharedWidths;
          final availableWidth = constraints.maxWidth;
          final fixedColsWidth =
              shared.bpmWidth + shared.durationWidth + shared.keyWidth;
          final colSum = shared.totalWidth;
          final leftover = availableWidth - colSum;

          final gap = leftover >= 0 ? leftover / 3 : 0.0;
          final tuningWidth = leftover >= 0
              ? shared.tuningWidth
              : (availableWidth - fixedColsWidth)
                  .clamp(0.0, shared.tuningWidth);

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: shared.bpmWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildBpmValue(),
                ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: shared.durationWidth,
                child: Align(
                  alignment: Alignment.center,
                  child: _buildDurationValue(),
                ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: shared.keyWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: hasKey ? _buildKeyBadge() : const SizedBox.shrink(),
                ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: tuningWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildTuningBadge(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds BPM value display (read-only, no border)
  /// Shows "- BPM" placeholder if no BPM value set.
  /// Always returns a widget to maintain consistent spacing in spaceBetween layout.
  Widget _buildBpmValue() {
    return Text(
      widget.song.isBpmPlaceholder ? '- BPM' : widget.song.formattedBpm,
      style: TextStyle(
        fontSize: AppFontSizes.subhead,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
        height: 1,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }

  /// Builds Duration value display (read-only, no border)
  /// Shows "0:00" if no duration entered
  Widget _buildDurationValue() {
    return Text(
      widget.song.formattedDuration,
      style: TextStyle(
        fontSize: AppFontSizes.subhead,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
        height: 1,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }

  /// Builds the key badge (read-only display)
  /// Only shown when musicalKey is not null and not empty
  Widget _buildKeyBadge() {
    const keyColor = Color(0xFFF59E0B); // Amber-500

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: keyColor, width: 1.5),
        borderRadius: BorderRadius.circular(100), // Pill shape
      ),
      child: Text(
        widget.song.musicalKey!,
        style: const TextStyle(
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w700,
          color: keyColor,
          height: 1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  /// Builds the tuning badge with micro-interaction on tap
  /// NO border - filled background only, pill shape
  /// When onTuningChanged is null, renders as non-interactive label
  Widget _buildTuningBadge() {
    final tuning = widget.song.tuning;
    final shortLabel = tuningShortLabel(tuning);
    final bgColor = tuningBadgeColor(tuning);
    final textColor = tuningBadgeTextColor(bgColor, tuningKey: tuning);

    final badge = Container(
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
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );

    // Non-interactive label when onTuningChanged is null (read-only)
    if (widget.onTuningChanged == null) {
      return badge;
    }

    return GestureDetector(
      onTap: _isSaving ? null : _selectTuning,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: AppDurations.instant,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: badge,
      ),
    );
  }
}
