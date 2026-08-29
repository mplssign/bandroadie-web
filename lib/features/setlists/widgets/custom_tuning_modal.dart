import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../services/custom_tuning_service.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_button.dart';

// ============================================================================
// CUSTOM TUNING MODAL
// Modal for creating a new custom guitar tuning.
//
// Features:
// - Input for any number of guitar strings (low to high)
// - Input for tuning name
// - Validation: at least 1 valid note token, A-G with optional #/b
// - Real-time uppercase normalization
// - Save button disabled until valid
// - Returns the created CustomTuning on success
// ============================================================================

/// Show modal to create a custom tuning
/// Returns the created CustomTuning if saved, null if cancelled
Future<CustomTuning?> showCustomTuningModal(BuildContext context) async {
  HapticFeedback.lightImpact();

  return showAppBottomSheet<CustomTuning>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => const _CustomTuningModal(),
  );
}

class _CustomTuningModal extends StatefulWidget {
  const _CustomTuningModal();

  @override
  State<_CustomTuningModal> createState() => _CustomTuningModalState();
}

class _CustomTuningModalState extends State<_CustomTuningModal>
    with SingleTickerProviderStateMixin {
  final _stringsController = TextEditingController();
  final _nameController = TextEditingController();
  final _stringsFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();

  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isSaving = false;
  String? _stringsError;
  String? _nameError;

  @override
  void initState() {
    super.initState();

    // Setup entrance animation
    _animController = AnimationController(
      duration: AppDurations.medium,
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: AppCurves.rubberband),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _animController.forward();

    // Listen for input changes to clear errors and validate
    _stringsController.addListener(_onInputChanged);
    _nameController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _stringsController.dispose();
    _nameController.dispose();
    _stringsFocusNode.dispose();
    _nameFocusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {
      _stringsError = null;
      _nameError = null;
    });
  }

  /// Validate the strings input.
  /// Returns error message if invalid, null if valid.
  /// Accepts any number of space-separated note tokens (A-G with optional # or b).
  String? _validateStrings(String input) {
    if (input.trim().isEmpty) {
      return 'Please enter guitar strings';
    }

    // Split by whitespace, commas, or hyphens
    final notes = input
        .trim()
        .toUpperCase()
        .split(RegExp(r'[\s,\-]+'))
        .where((s) => s.isNotEmpty)
        .toList();

    if (notes.isEmpty) {
      return 'Please enter at least one string';
    }

    // Validate each note: must be A-G with optional # or B (for flats like Bb, Db)
    final validNotePattern = RegExp(r'^[A-G][#B]?$');
    for (int i = 0; i < notes.length; i++) {
      if (!validNotePattern.hasMatch(notes[i])) {
        return '"${notes[i]}" is not a valid note. Use A-G with optional # or b';
      }
    }

    return null; // Valid
  }

  /// Validate the name input
  String? _validateName(String input) {
    if (input.trim().isEmpty) {
      return 'Please enter a name for this tuning';
    }
    if (input.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null; // Valid
  }

  /// Check if both inputs are valid
  bool get _isValid {
    return _validateStrings(_stringsController.text) == null &&
        _validateName(_nameController.text) == null;
  }

  /// Handle save button tap
  Future<void> _handleSave() async {
    if (!_isValid || _isSaving) return;

    // Final validation with error display
    final stringsError = _validateStrings(_stringsController.text);
    final nameError = _validateName(_nameController.text);

    if (stringsError != null || nameError != null) {
      setState(() {
        _stringsError = stringsError;
        _nameError = nameError;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Parse and normalize strings input
      final normalized = _stringsController.text
          .trim()
          .toUpperCase()
          .split(RegExp(r'[\s,\-]+'))
          .where((s) => s.isNotEmpty)
          .join(' ');

      // Save to service
      final service = CustomTuningService();
      final tuning = await service.saveCustomTuning(
        name: _nameController.text.trim(),
        strings: normalized,
      );

      HapticFeedback.mediumImpact();

      // Return the created tuning
      if (mounted) {
        Navigator.of(context).pop(tuning);
      }
    } catch (e) {
      setState(() {
        _stringsError = 'Failed to save: $e';
        _isSaving = false;
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _handleCancel() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate bottom padding for keyboard
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: Container(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              _buildDragHandle(),

              // Header
              _buildHeader(),

              // Divider
              Divider(
                color: context.colors.border,
                height: 1,
                thickness: 1,
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(Spacing.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instructions
                    _buildInstructions(),

                    const SizedBox(height: Spacing.space24),

                    // Strings input
                    _buildStringsInput(),

                    const SizedBox(height: Spacing.space20),

                    // Name input
                    _buildNameInput(),

                    const SizedBox(height: Spacing.space32),

                    // Action buttons
                    _buildActionButtons(),

                    const SizedBox(height: Spacing.space8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(
        top: Spacing.space12,
        bottom: Spacing.space8,
      ),
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.colors.textMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space4,
        Spacing.pagePadding,
        Spacing.space12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Add Custom Tuning', style: AppTextStyles.title3),
          GestureDetector(
            onTap: _handleCancel,
            child: Container(
              padding: const EdgeInsets.all(Spacing.space4),
              child: Icon(
                AppIcons.close,
                color: context.colors.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, color: AppColors.primary, size: 20),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Text(
              'Enter strings from low to high\nExample: E A D G B E',
              style: TextStyle(
                fontSize: AppFontSizes.caption,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStringsInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guitar Strings (Low to High)',
          style: TextStyle(
            fontSize: AppFontSizes.subhead,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        AppTextField(
          controller: _stringsController,
          focusNode: _stringsFocusNode,
          enabled: !_isSaving,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          hintText: 'E A D G B E',
          inputFormatters: [_StringsInputFormatter()],
        ),
        if (_stringsError != null) ...[
          const SizedBox(height: Spacing.space8),
          Text(
            _stringsError!,
            style: TextStyle(
              fontSize: AppFontSizes.caption,
              color: context.colors.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tuning Name',
          style: TextStyle(
            fontSize: AppFontSizes.subhead,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        AppTextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          enabled: !_isSaving,
          autocorrect: true,
          textCapitalization: TextCapitalization.words,
          hintText: 'My Custom Tuning',
        ),
        if (_nameError != null) ...[
          const SizedBox(height: Spacing.space8),
          Text(
            _nameError!,
            style: TextStyle(
              fontSize: AppFontSizes.caption,
              color: context.colors.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Cancel button
        Expanded(
          child: AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outlined,
            onPressed: _isSaving ? null : _handleCancel,
          ),
        ),

        const SizedBox(width: Spacing.space12),

        // Save button
        Expanded(
          flex: 2,
          child: _isSaving
              ? AppButton(
                  label: '',
                  variant: AppButtonVariant.secondary,
                  onPressed: null,
                  isLoading: true,
                )
              : AppButton(
                  label: 'Save Tuning',
                  variant: AppButtonVariant.secondary,
                  onPressed: (_isValid && !_isSaving) ? _handleSave : null,
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// INPUT FORMATTER
// Real-time uppercase normalization and space collapsing for guitar strings.
// Allows: A-G, #, b (flat), and spaces.
// =============================================================================

class _StringsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow only valid characters: letters A-G (case-insensitive), #, b, space
    final filtered = newValue.text.replaceAll(RegExp(r'[^A-Ga-g#b ]'), '');

    // Uppercase note letters (A-G) but preserve lowercase 'b' for flats
    final buffer = StringBuffer();
    for (int i = 0; i < filtered.length; i++) {
      final char = filtered[i];
      if (char == 'b' &&
          i > 0 &&
          RegExp(r'[A-G]').hasMatch(buffer.toString().isNotEmpty
              ? filtered[i - 1].toUpperCase()
              : '')) {
        // Lowercase 'b' right after a note letter = flat modifier, keep as-is
        buffer.write('b');
      } else if (char == '#') {
        buffer.write('#');
      } else if (char == ' ') {
        buffer.write(' ');
      } else {
        // Note letter — uppercase it
        buffer.write(char.toUpperCase());
      }
    }

    // Collapse multiple spaces into single spaces
    final collapsed = buffer.toString().replaceAll(RegExp(r' {2,}'), ' ');

    // Preserve cursor position proportionally
    final selectionIndex = collapsed.length < newValue.selection.end
        ? collapsed.length
        : newValue.selection.end.clamp(0, collapsed.length);

    return TextEditingValue(
      text: collapsed,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}
