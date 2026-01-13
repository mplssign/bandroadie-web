import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// BUTTON GROUP GRID
// A reusable grid of toggle buttons with uniform sizing.
//
// USAGE:
//   ButtonGroupGrid<Duration>(
//     items: Duration.values,
//     labelBuilder: (d) => d.label,
//     isSelected: (d) => selectedDuration == d,
//     onTap: (d) => setState(() => selectedDuration = d),
//     columns: 4,
//   );
//
// AVAILABILITY MODE:
// For Potential Gigs, use availabilityMode with availabilityState to show
// member availability (green=yes, rose=no, outlined=not responded).
// In availability mode, buttons are not interactive for other users.
// ============================================================================

/// Availability state for a member in a Potential Gig
enum AvailabilityState {
  notResponded, // Outlined (default)
  available, // Green filled
  notAvailable, // Rose filled
}

/// A reusable grid component for rendering fixed-size toggle buttons/chips.
class ButtonGroupGrid<T> extends StatelessWidget {
  /// The list of items to render as buttons.
  final List<T> items;

  /// Function to generate the label text for each item.
  final String Function(T) labelBuilder;

  /// Function to determine if an item is currently selected.
  final bool Function(T) isSelected;

  /// Callback when an item is tapped.
  final void Function(T)? onTap;

  /// Number of columns in the grid.
  final int columns;

  /// Height of each button (default: 42).
  final double buttonHeight;

  /// Horizontal spacing between buttons (default: 8).
  final double horizontalSpacing;

  /// Vertical spacing between rows (default: 8).
  final double verticalSpacing;

  /// Whether buttons should have equal width (default: true).
  final bool equalWidth;

  /// Whether the grid is enabled (default: true).
  final bool enabled;

  /// Whether to use availability mode (Potential Gig member display).
  /// When true, buttons show availability state instead of selection state.
  final bool availabilityMode;

  /// Function to get the availability state for each item.
  /// Required when availabilityMode is true.
  final AvailabilityState Function(T)? availabilityState;

  /// Optional widget builder for multi-line labels (name disambiguation).
  /// Returns null to use the default labelBuilder text instead.
  final Widget? Function(T)? labelWidgetBuilder;

  const ButtonGroupGrid({
    super.key,
    required this.items,
    required this.labelBuilder,
    required this.isSelected,
    this.onTap,
    this.columns = 4,
    this.buttonHeight = 42,
    this.horizontalSpacing = 8,
    this.verticalSpacing = 8,
    this.equalWidth = true,
    this.enabled = true,
    this.availabilityMode = false,
    this.availabilityState,
    this.labelWidgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate rows needed
    final rowCount = (items.length / columns).ceil();

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        final startIndex = rowIndex * columns;
        final endIndex = (startIndex + columns).clamp(0, items.length);
        final rowItems = items.sublist(startIndex, endIndex);

        // Pad the last row with empty spaces if needed for equal width
        final paddedRowItems = List<T?>.from(rowItems);
        while (paddedRowItems.length < columns) {
          paddedRowItems.add(null);
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: rowIndex < rowCount - 1 ? verticalSpacing : 0,
          ),
          child: Row(
            children: List.generate(columns, (colIndex) {
              final item = paddedRowItems[colIndex];

              // Add spacing between buttons
              final margin = EdgeInsets.only(
                right: colIndex < columns - 1 ? horizontalSpacing : 0,
              );

              if (item == null) {
                // Empty spacer for incomplete last row
                return Expanded(child: Container(margin: margin));
              }

              if (availabilityMode) {
                // Availability mode: show availability state colors
                final state =
                    availabilityState?.call(item) ??
                    AvailabilityState.notResponded;

                return Expanded(
                  child: Container(
                    margin: margin,
                    child: _AvailabilityGridItem(
                      label: labelBuilder(item),
                      labelWidget: labelWidgetBuilder?.call(item),
                      state: state,
                      height: buttonHeight,
                    ),
                  ),
                );
              }

              // Normal selection mode
              final selected = isSelected(item);

              return Expanded(
                child: Container(
                  margin: margin,
                  child: _ButtonGridItem(
                    label: labelBuilder(item),
                    labelWidget: labelWidgetBuilder?.call(item),
                    isSelected: selected,
                    height: buttonHeight,
                    enabled: enabled,
                    onTap: onTap == null
                        ? null
                        : () {
                            onTap!(item);
                            HapticFeedback.selectionClick();
                          },
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

/// Internal button item widget with animation and styling.
class _ButtonGridItem extends StatelessWidget {
  final String label;
  final Widget? labelWidget;
  final bool isSelected;
  final double height;
  final bool enabled;
  final VoidCallback? onTap;

  const _ButtonGridItem({
    required this.label,
    this.labelWidget,
    required this.isSelected,
    required this.height,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: height,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.scaffoldBg,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.borderMuted,
          ),
        ),
        alignment: Alignment.center,
        child:
            labelWidget ??
            Text(
              label,
              style: AppTextStyles.footnote.copyWith(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
      ),
    );
  }
}

/// Internal availability item widget for Potential Gig member display.
/// Shows green for available, rose for not available, outlined for not responded.
class _AvailabilityGridItem extends StatelessWidget {
  final String label;
  final Widget? labelWidget;
  final AvailabilityState state;
  final double height;

  const _AvailabilityGridItem({
    required this.label,
    this.labelWidget,
    required this.state,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors based on availability state
    Color backgroundColor;
    Color borderColor;
    Color textColor;

    switch (state) {
      case AvailabilityState.available:
        // Green for available
        backgroundColor = const Color(0xFF22C55E); // Green-500
        borderColor = const Color(0xFF22C55E);
        textColor = Colors.white;
        break;
      case AvailabilityState.notAvailable:
        // Rose for not available
        backgroundColor = AppColors.accent; // Rose
        borderColor = AppColors.accent;
        textColor = Colors.white;
        break;
      case AvailabilityState.notResponded:
        // Outlined for not responded
        backgroundColor = AppColors.scaffoldBg;
        borderColor = AppColors.borderMuted;
        textColor = AppColors.textSecondary;
        break;
    }

    return AnimatedContainer(
      duration: AppDurations.fast,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.center,
      child:
          labelWidget ??
          Text(
            label,
            style: AppTextStyles.footnote.copyWith(
              color: textColor,
              fontWeight: state != AvailabilityState.notResponded
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
    );
  }
}
