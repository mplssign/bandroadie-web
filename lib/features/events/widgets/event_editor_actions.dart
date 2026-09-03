import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/event_editor_theme.dart';
import '../../../components/ui/app_button.dart';

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
    this.summary,
  });

  final bool canSave;
  final bool isSaving;
  final bool isDeleting;
  final String primaryButtonLabel;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final colors = FTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null && summary!.isNotEmpty) ...[
          Text(
            summary!,
            style: TextStyle(fontSize: 14, color: kEdMutedForegroundFaint),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: (isSaving || isDeleting) ? null : onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(width: Spacing.space12),
            Expanded(
              child: SizedBox(
                height: 40,
                child: isSaving
                    ? ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.primaryForeground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: null,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.primaryForeground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: canSave ? onSave : null,
                        child: Text(primaryButtonLabel),
                      ),
              ),
            ),
          ],
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
