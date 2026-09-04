import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/components/ui/app_button.dart';

/// Standard sticky footer for modal sheets and drawers.
///
/// Renders a surface container (top border + shadow) containing:
/// - An optional full-width destructive action above the primary/cancel row.
/// - A row with the cancel (text, left) and primary (filled rose, right) buttons.
///
/// Pass `onCancel: null` to hide the cancel slot; the primary spans full width.
/// Pass both `destructiveLabel` and `onDestructive` to show the destructive row.
class SheetFooter extends StatelessWidget {
  const SheetFooter({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIsLoading = false,
    this.primaryIcon,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.destructiveLabel,
    this.onDestructive,
    this.destructiveIsLoading = false,
  });

  /// Label for the primary (rose filled) button.
  final String primaryLabel;

  /// Callback for the primary button. Null disables it.
  final VoidCallback? onPrimary;

  /// Shows a spinner on the primary button and disables cancel when true.
  final bool primaryIsLoading;

  /// Optional leading icon on the primary button.
  final IconData? primaryIcon;

  /// Label for the cancel (text) button. Defaults to 'Cancel'.
  final String cancelLabel;

  /// Callback for the cancel button. Null hides the cancel slot entirely.
  final VoidCallback? onCancel;

  /// Label for the optional full-width destructive button rendered above the row.
  /// Both [destructiveLabel] and [onDestructive] must be non-null to show it.
  final String? destructiveLabel;

  /// Callback for the destructive button.
  final VoidCallback? onDestructive;

  /// Shows a spinner on the destructive button when true.
  final bool destructiveIsLoading;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final primary = AppButton(
      label: primaryLabel,
      onPressed: primaryIsLoading ? null : onPrimary,
      icon: primaryIcon,
      isLoading: primaryIsLoading,
      fullWidth: true,
    );

    final Widget row = onCancel != null
        ? Row(
            children: [
              Expanded(
                child: AppButton(
                  label: cancelLabel,
                  onPressed: primaryIsLoading ? null : onCancel,
                  variant: AppButtonVariant.text,
                  fullWidth: true,
                ),
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(child: primary),
            ],
          )
        : primary;

    final hasDestructive = destructiveLabel != null && onDestructive != null;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: 12,
        bottom: safeBottom + 12,
      ),
      child: hasDestructive
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: destructiveLabel!,
                  onPressed: destructiveIsLoading ? null : onDestructive,
                  variant: AppButtonVariant.destructive,
                  isLoading: destructiveIsLoading,
                  fullWidth: true,
                ),
                const SizedBox(height: Spacing.space12),
                row,
              ],
            )
          : row,
    );
  }
}
