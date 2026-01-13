import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services/supabase_client.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';
import '../../../shared/utils/event_permission_helper.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../block_out_repository.dart';
import '../models/calendar_event.dart';

// ============================================================================
// BLOCK OUT DRAWER
// Bottom drawer for creating and editing block out periods.
// Completely separate from the Add/Edit Event drawer.
//
// MODES:
//   - create: New block out (default)
//   - edit: Editing existing block out (can delete)
//   - viewOnly: Read-only view (non-creator viewing someone else's block out)
//
// USAGE:
//   BlockOutDrawer.show(
//     context,
//     ref: ref,
//     bandId: activeBandId,
//     initialDate: tappedDate,
//     onSaved: () => refreshCalendar(),
//   );
//
//   // Edit mode:
//   BlockOutDrawer.show(
//     context,
//     ref: ref,
//     bandId: activeBandId,
//     mode: BlockOutDrawerMode.edit,
//     existingBlockOut: blockOutSpan,
//     onSaved: () => refreshCalendar(),
//   );
// ============================================================================

/// Mode for the block out drawer
enum BlockOutDrawerMode { create, edit, viewOnly }

class BlockOutDrawer extends ConsumerStatefulWidget {
  /// The band ID (required)
  final String bandId;

  /// Mode: create, edit, or viewOnly
  final BlockOutDrawerMode mode;

  /// Initial start date (from calendar day tap, or today) - for create mode
  final DateTime? initialDate;

  /// Existing block out span data - for edit/viewOnly mode
  final BlockOutSpan? existingBlockOut;

  /// Callback when block out is saved/deleted successfully
  final VoidCallback? onSaved;

  const BlockOutDrawer({
    super.key,
    required this.bandId,
    this.mode = BlockOutDrawerMode.create,
    this.initialDate,
    this.existingBlockOut,
    this.onSaved,
  });

  /// Show the Block Out drawer
  static Future<bool?> show(
    BuildContext context, {
    required WidgetRef ref,
    required String bandId,
    BlockOutDrawerMode mode = BlockOutDrawerMode.create,
    DateTime? initialDate,
    BlockOutSpan? existingBlockOut,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return BlockOutDrawer(
          bandId: bandId,
          mode: mode,
          initialDate: initialDate,
          existingBlockOut: existingBlockOut,
          onSaved: onSaved,
        );
      },
    );
  }

  @override
  ConsumerState<BlockOutDrawer> createState() => _BlockOutDrawerState();
}

class _BlockOutDrawerState extends ConsumerState<BlockOutDrawer> {
  // Form state
  late DateTime _startDate;
  DateTime? _untilDate;
  final _reasonController = TextEditingController();

  // Loading / error state
  bool _isSaving = false;
  bool _isDeleting = false;
  String? _errorMessage;

  /// Whether this drawer is in read-only mode (non-creator viewing)
  bool get _isReadOnly => widget.mode == BlockOutDrawerMode.viewOnly;

  /// Whether this is edit mode (creator editing their own block out)
  bool get _isEditMode => widget.mode == BlockOutDrawerMode.edit;

  /// Drawer title based on mode
  String get _drawerTitle {
    switch (widget.mode) {
      case BlockOutDrawerMode.create:
        return 'Add Block Out';
      case BlockOutDrawerMode.edit:
        return 'Edit Block Out';
      case BlockOutDrawerMode.viewOnly:
        return 'Block Out Details';
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize from existing data in edit/viewOnly mode
    if (widget.existingBlockOut != null) {
      _startDate = widget.existingBlockOut!.startDate;
      // Only set end date if it's a multi-day span
      if (widget.existingBlockOut!.isMultiDay) {
        _untilDate = widget.existingBlockOut!.endDate;
      }
      _reasonController.text = widget.existingBlockOut!.reason;
    } else {
      _startDate = widget.initialDate ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    // Validate
    if (_untilDate != null && _untilDate!.isBefore(_startDate)) {
      setState(() {
        _errorMessage = 'End date cannot be before start date';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not logged in');
      }

      final repository = ref.read(blockOutRepositoryProvider);

      if (_isEditMode && widget.existingBlockOut != null) {
        // Update existing block out
        // First delete all dates in the span, then create new ones
        await repository.deleteBlockOutSpan(
          userId: widget.existingBlockOut!.userId,
          bandId: widget.bandId,
          startDate: widget.existingBlockOut!.startDate,
          endDate: widget.existingBlockOut!.endDate,
        );
        // Create new block out with updated dates
        await repository.createBlockOut(
          bandId: widget.bandId,
          userId: userId,
          startDate: _startDate,
          untilDate: _untilDate,
          reason: _reasonController.text.trim(),
        );
      } else {
        // Create new block out
        await repository.createBlockOut(
          bandId: widget.bandId,
          userId: userId,
          startDate: _startDate,
          untilDate: _untilDate,
          reason: _reasonController.text.trim(),
        );
      }

      // Success feedback
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call();

        showSuccessSnackBar(
          context,
          message: _isEditMode ? 'Block out updated' : 'Block out added',
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = _mapErrorToMessage(e);
      });
    }
  }

  Future<void> _handleDelete() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text('Delete Block Out?', style: AppTextStyles.title3),
        content: Text(
          'This will remove the block out dates. This action cannot be undone.',
          style: AppTextStyles.callout.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.callout.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppTextStyles.callout.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(blockOutRepositoryProvider);

      // Delete all dates in the span
      await repository.deleteBlockOutSpan(
        userId: widget.existingBlockOut!.userId,
        bandId: widget.bandId,
        startDate: widget.existingBlockOut!.startDate,
        endDate: widget.existingBlockOut!.endDate,
      );

      // Success feedback
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call();

        showSuccessSnackBar(context, message: 'Block out deleted');
      }
    } catch (e) {
      setState(() {
        _isDeleting = false;
        _errorMessage = _mapDeleteErrorToMessage(e);
      });
    }
  }

  /// Maps errors to user-friendly messages for block out delete operations.
  /// Uses centralized helper for consistent messaging.
  String _mapDeleteErrorToMessage(Object error) {
    // Use centralized helper for block out-specific messaging
    return mapBlockOutErrorToMessage(error, context: 'delete');
  }

  /// Maps errors to user-friendly messages for block out save operations.
  /// Uses centralized helper for consistent messaging.
  String _mapErrorToMessage(Object error) {
    final errorStr = error.toString().toLowerCase();

    // Special case: not logged in
    if (errorStr.contains('not logged in')) {
      return 'Please log in to add a block out.';
    }

    // Use centralized helper for all other errors
    return mapBlockOutErrorToMessage(error, context: 'save');
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) => _datePickerTheme(child),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Clear until date if it's now before start date
        if (_untilDate != null && _untilDate!.isBefore(_startDate)) {
          _untilDate = null;
        }
      });
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _selectUntilDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _untilDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) => _datePickerTheme(child),
    );

    if (picked != null) {
      setState(() {
        _untilDate = picked;
      });
      HapticFeedback.selectionClick();
    }
  }

  Widget _datePickerTheme(Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.cardBg,
          onSurface: AppColors.textPrimary,
        ),
        dialogTheme: DialogThemeData(backgroundColor: AppColors.cardBg),
      ),
      child: child!,
    );
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: Spacing.space16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_drawerTitle, style: AppTextStyles.title3),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: AppColors.scaffoldBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // View-only banner (non-creator viewing someone else's block out)
            if (_isReadOnly) ...[
              const SizedBox(height: Spacing.space16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only the creator can edit or delete this block out.',
                          style: AppTextStyles.footnote.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: Spacing.space16),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: Spacing.pagePadding,
                  right: Spacing.pagePadding,
                  bottom: bottomPadding + safeBottom + 100,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error banner
                    if (_errorMessage != null) ...[
                      _buildErrorBanner(),
                      const SizedBox(height: Spacing.space16),
                    ],

                    // 1. Start Date (required)
                    _buildDateField(
                      label: 'Start Date',
                      value: _startDate,
                      onTap: _selectStartDate,
                      isRequired: true,
                    ),

                    const SizedBox(height: Spacing.space16),

                    // 2. End Date (optional)
                    _buildDateField(
                      label: 'End Date (Optional)',
                      value: _untilDate,
                      onTap: _selectUntilDate,
                      isRequired: false,
                      placeholder: 'Last day',
                    ),

                    const SizedBox(height: Spacing.space16),

                    // 3. Reason (optional)
                    _buildTextField(
                      label: 'Reason (optional)',
                      controller: _reasonController,
                      hint: 'Out of town, vacation, etc.',
                      maxLines: 2,
                    ),

                    // Delete button (edit mode only - creator can delete)
                    if (_isEditMode) ...[
                      const SizedBox(height: Spacing.space24),
                      _buildDeleteButton(),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Buttons (sticky)
            _buildBottomButtons(safeBottom),
          ],
        ),
      ),
    );
  }

  /// Delete button (destructive text style) - only shown in edit mode for creator
  Widget _buildDeleteButton() {
    return Center(
      child: TextButton(
        onPressed: (_isSaving || _isDeleting) ? null : _handleDelete,
        child: _isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.error,
                ),
              )
            : Text(
                'Delete Block Out',
                style: AppTextStyles.calloutEmphasized.copyWith(
                  color: AppColors.error,
                ),
              ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.footnote.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required bool isRequired,
    String? placeholder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.footnote.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: AppTextStyles.footnote.copyWith(color: AppColors.error),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: (_isSaving || _isDeleting || _isReadOnly) ? null : onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _isReadOnly
                  ? AppColors.scaffoldBg.withValues(alpha: 0.5)
                  : AppColors.scaffoldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value != null
                        ? _formatDate(value)
                        : (placeholder ?? 'Select date'),
                    style: AppTextStyles.callout.copyWith(
                      color: value != null
                          ? (_isReadOnly
                                ? AppColors.textSecondary
                                : AppColors.textPrimary)
                          : AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                if (!_isReadOnly)
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_isSaving && !_isDeleting && !_isReadOnly,
          maxLines: maxLines,
          style: AppTextStyles.callout.copyWith(
            color: _isReadOnly
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.callout.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: _isReadOnly
                ? AppColors.scaffoldBg.withValues(alpha: 0.5)
                : AppColors.scaffoldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons(double safeBottom) {
    // Read-only mode: just show a Close button
    if (_isReadOnly) {
      return Container(
        padding: EdgeInsets.only(
          left: Spacing.pagePadding,
          right: Spacing.pagePadding,
          top: Spacing.space16,
          bottom: safeBottom + Spacing.space16,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          border: Border(
            top: BorderSide(
              color: AppColors.borderMuted.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
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
        ),
      );
    }

    // Edit mode: Cancel + Update buttons (matching EventEditorDrawer)
    if (_isEditMode) {
      return Container(
        padding: EdgeInsets.only(
          left: Spacing.pagePadding,
          right: Spacing.pagePadding,
          top: Spacing.space12,
          bottom: safeBottom + Spacing.space12,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          border: Border(
            top: BorderSide(
              color: AppColors.borderMuted.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Cancel button - equal width
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: (_isSaving || _isDeleting)
                      ? null
                      : () => Navigator.pop(context),
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
            // Update button - equal width
            Expanded(
              child: BrandActionButton(
                label: 'Update',
                isLoading: _isSaving,
                onPressed: (_isSaving || _isDeleting) ? null : _handleSave,
              ),
            ),
          ],
        ),
      );
    }

    // Create mode: Cancel + Add Block Out buttons
    return Container(
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: Spacing.space16,
        bottom: safeBottom + Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(
          top: BorderSide(color: AppColors.borderMuted.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Cancel button - equal width
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
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
              label: 'Add Block Out',
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _handleSave,
            ),
          ),
        ],
      ),
    );
  }
}
