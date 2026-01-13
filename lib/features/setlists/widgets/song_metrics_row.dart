import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../tuning/tuning_helpers.dart';
import 'animated_value_text.dart';

// ============================================================================
// SONG METRICS ROW
// Fixed 3-column layout for BPM | Duration | Tuning with placeholder support.
//
// Layout:
//   [BPM: 72px] [12px gutter] [Duration: 84px] [Spacer] [Tuning: 100px right-aligned]
//
// Features:
// - Placeholder "—" for null values (non-interactive)
// - Animated fade+slide when values appear
// - Fixed column widths prevent layout shift
// ============================================================================

/// Metrics row showing BPM, Duration, and Tuning in fixed-width columns.
class SongMetricsRow extends StatelessWidget {
  /// BPM value (null shows placeholder)
  final int? bpm;

  /// Duration in seconds (null shows placeholder)
  final int? durationSeconds;

  /// Tuning identifier (e.g., "drop_d", "standard_e")
  final String tuning;

  /// Whether BPM has an override (affects styling)
  final bool hasBpmOverride;

  /// Whether duration has an override (affects styling)
  final bool hasDurationOverride;

  /// Callback when BPM is tapped (only fires for non-null values)
  final VoidCallback? onBpmTap;

  /// Callback when Duration is tapped (only fires for non-null values)
  final VoidCallback? onDurationTap;

  /// Callback when Tuning badge is tapped
  final VoidCallback? onTuningTap;

  /// Whether to show edit indicators (for editable cards)
  final bool isEditable;

  const SongMetricsRow({
    super.key,
    required this.bpm,
    required this.durationSeconds,
    required this.tuning,
    this.hasBpmOverride = false,
    this.hasDurationOverride = false,
    this.onBpmTap,
    this.onDurationTap,
    this.onTuningTap,
    this.isEditable = false,
  });

  /// Format BPM for display using shared helper
  /// Always returns a value (either "X BPM" or "- BPM")
  String get formattedBpm => formatBpm(bpm);

  /// Whether BPM is a placeholder (null/0/invalid)
  bool get isBpmPlaceholder => bpm == null || bpm! <= 0;

  /// Format duration for display (M:SS)
  String? get formattedDuration {
    if (durationSeconds == null) return null;
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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

          // Spacer pushes tuning to right
          const Spacer(),

          // Tuning column (fixed width, right-aligned)
          SizedBox(
            width: SongCardLayout.trailingColWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildTuningBadge(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBpmValue() {
    return AnimatedValueText(
      displayText: formattedBpm,
      isPlaceholder: isBpmPlaceholder,
      onTap: isBpmPlaceholder ? null : onBpmTap,
      backgroundColor: const Color(0xFF2C2C2C),
      borderColor: hasBpmOverride ? AppColors.accent : null,
    );
  }

  Widget _buildDurationValue() {
    final isPlaceholder = formattedDuration == null;
    final displayText = formattedDuration ?? '—';

    return AnimatedValueText(
      displayText: displayText,
      isPlaceholder: isPlaceholder,
      onTap: isPlaceholder ? null : onDurationTap,
      backgroundColor: const Color(0xFF2C2C2C),
      borderColor: hasDurationOverride ? AppColors.accent : null,
    );
  }

  Widget _buildTuningBadge() {
    final shortLabel = tuningShortLabel(tuning);
    final bgColor = tuningBadgeColor(tuning);
    final textColor = tuningBadgeTextColor(bgColor);

    return GestureDetector(
      onTap: onTuningTap,
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
    );
  }
}
