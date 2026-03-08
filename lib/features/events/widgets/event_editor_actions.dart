import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

/// Bottom action buttons for the event editor: Cancel + Save.
class EventEditorBottomActions extends StatelessWidget {
  const EventEditorBottomActions({
    super.key,
    required this.canSave,
    required this.isSaving,
    required this.isDeleting,
    required this.primaryButtonLabel,
    required this.onSave,
    required this.onCancel,
  });

  final bool canSave;
  final bool isSaving;
  final bool isDeleting;
  final String primaryButtonLabel;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Cancel button - equal width
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: (isSaving || isDeleting) ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderMuted),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: Text(
                'Cancel',
                style: AppTextStyles.calloutEmphasized.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.space12),
        // Primary button - equal width
        Expanded(
          child: BrandActionButton(
            label: primaryButtonLabel,
            isLoading: isSaving,
            onPressed: canSave ? onSave : null,
          ),
        ),
      ],
    );
  }
}

/// Single Close button for viewOnly mode.
class EventEditorViewOnlyClose extends StatelessWidget {
  const EventEditorViewOnlyClose({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onClose,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.borderMuted),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
        ),
        child: Text(
          'Close',
          style: AppTextStyles.calloutEmphasized.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Delete event button (destructive text style). Shown in edit mode only.
class EventDeleteButton extends StatelessWidget {
  const EventDeleteButton({
    super.key,
    required this.isSaving,
    required this.isDeleting,
    required this.onDelete,
  });

  final bool isSaving;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: (isSaving || isDeleting) ? null : onDelete,
        child: isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.error,
                ),
              )
            : Text(
                'Delete Event',
                style: AppTextStyles.calloutEmphasized.copyWith(
                  color: AppColors.error,
                ),
              ),
      ),
    );
  }
}
