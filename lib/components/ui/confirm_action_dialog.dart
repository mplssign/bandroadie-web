import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// CONFIRM ACTION DIALOG
// A reusable confirmation dialog with consistent layout:
// - Title at top
// - Description content
// - Primary action button (full width)
// - Cancel text button centered below
// ============================================================================

/// Shows a confirmation dialog with consistent layout.
///
/// Returns `true` if the user confirms, `false` if they cancel.
Future<bool> showConfirmActionDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  Color? confirmColor,
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ConfirmActionDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      confirmColor:
          confirmColor ?? (isDestructive ? AppColors.error : AppColors.accent),
      cancelLabel: cancelLabel,
    ),
  );
  return result ?? false;
}

class ConfirmActionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final String cancelLabel;

  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    this.cancelLabel = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        Spacing.space24,
        Spacing.space20,
        Spacing.space24,
        Spacing.space24,
      ),
      title: Text(
        title,
        style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.space24),
          // Primary action button (full width)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: confirmColor,
                padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: Text(
                confirmLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.space12),
          // Cancel text button centered below
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                cancelLabel,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      // No actions array - we put buttons in content
      actions: const [],
    );
  }
}
