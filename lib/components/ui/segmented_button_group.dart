import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/theme/brand_colors.dart';

/// Data class for a single segment in a SegmentedButtonGroup
class SegmentData {
  final String label;
  final String value;
  final VoidCallback? onTap;

  SegmentData({
    required this.label,
    required this.value,
    this.onTap,
  });
}

/// A reusable grouped segmented button component
///
/// Renders a single rounded container with multiple segments separated by dividers.
/// Each segment displays a label on top and a value below, centered vertically.
class SegmentedButtonGroup extends StatelessWidget {
  final List<SegmentData> segments;

  const SegmentedButtonGroup({
    super.key,
    required this.segments,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: context.colors.textSecondary,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        child: IntrinsicHeight(
          child: Row(
            children: _buildSegments(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSegments(BuildContext context) {
    final List<Widget> children = [];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];

      // Add divider before all segments except the first
      if (i > 0) {
        children.add(
          Container(
            width: 1.0,
            color: context.colors.textSecondary,
          ),
        );
      }

      // Add the segment
      children.add(
        Expanded(
          child: _buildSegment(segment, context),
        ),
      );
    }

    return children;
  }

  Widget _buildSegment(SegmentData segment, BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: Spacing.space12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            segment.label,
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.space4),
          Text(
            segment.value,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    // If onTap is provided, wrap in GestureDetector
    if (segment.onTap != null) {
      return GestureDetector(
        onTap: segment.onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}
