import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Chip style variants
enum AppChipVariant {
  /// Default chip with no selection state
  defaultChip,

  /// Filter chip with selection state (selectable badge)
  filter,

  /// Action chip with tap callback
  action,
}

/// Wrapper for Forui badge widgets that respects app theme configuration.
///
/// Use this widget instead of Material [Chip], [FilterChip], or [ActionChip]
/// to ensure consistent chip styling across the app using Forui design system.
///
/// Implementation uses [FBadge] for presentation and [FTappable.static] for
/// interactive behavior (selection, tap callbacks). This is the recommended
/// pattern for selectable badges in Forui.
///
/// **Migration note:** Moved from Material-only to Forui in Cycle 4
/// (feature/domain-chip-forui-consolidation).
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.onTap,
    this.isSelected,
    this.variant = AppChipVariant.defaultChip,
    this.enabled = true,
  });

  /// Chip label text
  final String label;

  /// Optional tap callback
  final VoidCallback? onTap;

  /// Optional selection state (used for filter variant)
  final bool? isSelected;

  /// Chip style variant
  final AppChipVariant variant;

  /// Whether the chip is enabled (tappable)
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Determine if this chip should be selectable (filter variant with isSelected provided)
    final bool isFilterVariant =
        variant == AppChipVariant.filter && isSelected != null;

    // Build the badge content
    final badge = FBadge(
      variant: isFilterVariant && (isSelected ?? false)
          ? FBadgeVariant.primary
          : FBadgeVariant.secondary,
      child: Text(label),
    );

    // For filter variant or when onTap is provided, wrap in FTappable.static
    if (isFilterVariant || onTap != null) {
      return FTappable.static(
        selected: isFilterVariant ? (isSelected ?? false) : false,
        onPress: enabled ? onTap : null,
        child: badge,
      );
    }

    // For default variant with no interaction, return badge directly
    return badge;
  }
}
