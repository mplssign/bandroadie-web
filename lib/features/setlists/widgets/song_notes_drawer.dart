import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_button.dart';

// ============================================================================
// SONG NOTES DRAWER
// Bottom drawer for viewing and editing song notes.
//
// Features:
// - View mode: read-only notes display with Edit button
// - Edit mode: editable text field with Save/Cancel
// - Save button disabled when text unchanged (prevents spurious saves)
// - PopScope dismiss handling (treats as Cancel)
// - Dark-mode safe (uses context.colors.surface)
// ============================================================================

/// Shows a bottom drawer for viewing/editing song notes.
///
/// Returns the edited notes text if saved, or null if cancelled.
Future<String?> showSongNotesDrawer(
  BuildContext context, {
  required String notes,
}) async {
  return showAppBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Spacing.cardRadius)),
    ),
    builder: (context) => SongNotesDrawer(notes: notes),
  );
}

class SongNotesDrawer extends StatefulWidget {
  final String notes;

  const SongNotesDrawer({super.key, required this.notes});

  @override
  State<SongNotesDrawer> createState() => _SongNotesDrawerState();
}

class _SongNotesDrawerState extends State<SongNotesDrawer> {
  bool _isEditing = false;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.notes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _hasChanges => _notesController.text.trim() != widget.notes.trim();

  void _handleCancel() {
    if (_isEditing) {
      // Edit mode cancel: reset and return to view mode
      setState(() {
        _notesController.text = widget.notes;
        _isEditing = false;
      });
    } else {
      // View mode cancel: close drawer
      Navigator.of(context).pop(null);
    }
  }

  void _handleSave() {
    Navigator.of(context).pop(_notesController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCancel();
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.85,
            ),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Spacing.cardRadius),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDragHandle(),
                _buildHeader(),
                Divider(color: context.colors.border, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Spacing.space16),
                    child: _isEditing ? _buildEditView() : _buildViewMode(),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.only(top: Spacing.space12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      child: Text(
        'Notes',
        style: AppTextStyles.pageTitle,
      ),
    );
  }

  Widget _buildViewMode() {
    return Text(
      widget.notes,
      style: AppTextStyles.callout.copyWith(
        color: context.colors.textPrimary,
        height: 1.5,
      ),
    );
  }

  Widget _buildEditView() {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.border),
      ),
      child: AppTextField(
        controller: _notesController,
        maxLines: null,
        minLines: 8,
        hintText: 'Add notes for this song...',
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(Spacing.space16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEditing) ...[
            // Edit mode: Save button
            AppButton(
              label: 'Save',
              variant: AppButtonVariant.primary,
              fullWidth: true,
              onPressed: _hasChanges ? _handleSave : null,
            ),
          ] else ...[
            // View mode: Edit button
            AppButton(
              label: 'Edit',
              variant: AppButtonVariant.primary,
              fullWidth: true,
              onPressed: () => setState(() => _isEditing = true),
            ),
          ],
          const SizedBox(height: 8),
          // Cancel button (both modes)
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.text,
            onPressed: _handleCancel,
          ),
        ],
      ),
    );
  }
}
