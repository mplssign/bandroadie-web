import 'package:flutter/material.dart';

/// Chip style variants
enum AppChipVariant {
  /// Default chip with no selection state (Chip)
  defaultChip,

  /// Filter chip with selection state (FilterChip)
  filter,

  /// Action chip with tap callback (ActionChip)
  action,
}

/// Wrapper for Material chip widgets that respects app theme configuration.
///
/// Use this widget instead of [Chip], [FilterChip], or [ActionChip]
/// to ensure consistent chip styling across the app. Delegates to
/// the appropriate Material chip based on [variant] while respecting
/// theme configuration.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.onTap,
    this.isSelected,
    this.variant = AppChipVariant.defaultChip,
  });

  /// Chip label text
  final String label;

  /// Optional tap callback (used for action variant)
  final VoidCallback? onTap;

  /// Optional selection state (used for filter variant)
  final bool? isSelected;

  /// Chip style variant
  final AppChipVariant variant;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case AppChipVariant.defaultChip:
        return Chip(label: Text(label));

      case AppChipVariant.filter:
        return FilterChip(
          label: Text(label),
          selected: isSelected ?? false,
          onSelected: onTap != null ? (_) => onTap!() : null,
        );

      case AppChipVariant.action:
        return ActionChip(label: Text(label), onPressed: onTap);
    }
  }
}
