import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_button.dart';
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
          child: AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outlined,
            onPressed: (isSaving || isDeleting) ? null : onCancel,
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
    return AppButton(
      label: 'Close',
      variant: AppButtonVariant.outlined,
      fullWidth: true,
      onPressed: onClose,
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
      child: AppButton(
        label: 'Delete Event',
        variant: AppButtonVariant.destructive,
        onPressed: (isSaving || isDeleting) ? null : onDelete,
        isLoading: isDeleting,
      ),
    );
  }
}
