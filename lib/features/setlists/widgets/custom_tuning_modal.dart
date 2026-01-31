import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../services/custom_tuning_service.dart';

// ============================================================================
// CUSTOM TUNING MODAL
// Modal for creating a new custom guitar tuning.
//
// Features:
// - Input for 6 guitar strings (low to high)
// - Input for tuning name
// - Validation: 6 strings required, A-G only
// - Save button disabled until valid
// - Returns the created CustomTuning on success
// ============================================================================

/// Show modal to create a custom tuning
/// Returns the created CustomTuning if saved, null if cancelled
Future<CustomTuning?> showCustomTuningModal(BuildContext context) async {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<CustomTuning>(
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

  /// Validate the strings input
  /// Returns error message if invalid, null if valid
  String? _validateStrings(String input) {
    if (input.trim().isEmpty) {
      return 'Please enter 6 guitar strings';
    }

    // Normalize: remove extra spaces, convert to uppercase
    final normalized = input.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    // Split into individual notes
    final notes = normalized.split(' ');

    if (notes.length != 6) {
      return 'Must be exactly 6 strings (found ${notes.length})';
    }

    // Validate each note: must be A-G with optional # or b
    final validNotePattern = RegExp(r'^[A-G][#b]?$');
    for (int i = 0; i < notes.length; i++) {
      if (!validNotePattern.hasMatch(notes[i])) {
        return 'String ${i + 1} ("${notes[i]}") is invalid. Use A-G with optional # or b';
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
      // Normalize strings input
      final normalized = _stringsController.text
          .trim()
          .toUpperCase()
          .replaceAll(RegExp(r'\s+'), ' ');

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
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
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
              const Divider(
                color: AppColors.borderMuted,
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
          color: AppColors.textMuted.withValues(alpha: 0.5),
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
              child: const Icon(
                Icons.close_rounded,
                color: AppColors.textSecondary,
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
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Text(
              'Enter 6 guitar strings from low to high\nExample: E A D G B E',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        TextField(
          controller: _stringsController,
          focusNode: _stringsFocusNode,
          enabled: !_isSaving,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'E A D G B E',
            hintStyle: TextStyle(color: AppColors.textMuted),
            errorText: _stringsError,
            filled: true,
            fillColor: AppColors.scaffoldBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.accent, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: Colors.red.shade400),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.space16,
              vertical: Spacing.space12,
            ),
          ),
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
            letterSpacing: 1.2,
          ),
        ),
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        TextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          enabled: !_isSaving,
          autocorrect: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'My Custom Tuning',
            hintStyle: TextStyle(color: AppColors.textMuted),
            errorText: _nameError,
            filled: true,
            fillColor: AppColors.scaffoldBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: AppColors.accent, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: Colors.red.shade400),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.space16,
              vertical: Spacing.space12,
            ),
          ),
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Cancel button
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : _handleCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: Spacing.space14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              side: BorderSide(color: AppColors.borderMuted),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),

        const SizedBox(width: Spacing.space12),

        // Save button
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: (_isValid && !_isSaving) ? _handleSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(vertical: Spacing.space14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
            ),
            child: _isSaving
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Save Tuning',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
