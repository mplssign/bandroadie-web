import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/special_item.dart';
import 'masked_duration_input.dart';

// ============================================================================
// PAUSE CREATOR
// Bottom sheet for creating/editing a Pause item.
//
// Layout:
//   - Drag handle
//   - Title: "Pause"
//   - Purpose toggle chips (multi-select from PausePurposes.predefined)
//   - Add Custom Purpose text field
//   - Optional duration input (seconds-based, MM:SS display)
//   - Save to library toggle
//   - Add button
// ============================================================================

/// Result from the Pause Creator
class PauseResult {
  final List<String> purposes;
  final List<String> customPurposes;
  final int? durationSeconds;
  final bool saveAsTemplate;
  final bool deleted;

  const PauseResult({
    required this.purposes,
    required this.customPurposes,
    this.durationSeconds,
    required this.saveAsTemplate,
    this.deleted = false,
  });
}

/// Shows the Pause creator bottom sheet.
///
/// If [existingItem] is provided, opens in edit mode.
/// Returns [PauseResult] if user creates/saves, null if dismissed.
Future<PauseResult?> showPauseCreator(
  BuildContext context, {
  SpecialItem? existingItem,
}) {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<PauseResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _PauseCreatorSheet(existingItem: existingItem),
  );
}

class _PauseCreatorSheet extends StatefulWidget {
  final SpecialItem? existingItem;

  const _PauseCreatorSheet({this.existingItem});

  @override
  State<_PauseCreatorSheet> createState() => _PauseCreatorSheetState();
}

class _PauseCreatorSheetState extends State<_PauseCreatorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late Set<String> _selectedPurposes;
  late List<String> _customPurposes;
  final _customPurposeController = TextEditingController();
  final _customPurposeFocus = FocusNode();

  // Duration in seconds (optional)
  int? _durationSeconds;
  bool _hasDuration = false;

  bool _saveAsTemplate = true;

  @override
  void initState() {
    super.initState();

    // Initialize from existing item if editing
    _selectedPurposes = Set<String>.from(widget.existingItem?.purposes ?? []);
    _customPurposes = List<String>.from(
      widget.existingItem?.customPurposes ?? [],
    );
    _durationSeconds = widget.existingItem?.durationSeconds;
    _hasDuration = _durationSeconds != null && _durationSeconds! > 0;
    _saveAsTemplate = widget.existingItem?.isSavedTemplate ?? true;

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
  }

  @override
  void dispose() {
    _customPurposeController.dispose();
    _customPurposeFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingItem != null;

  bool get _hasSelections =>
      _selectedPurposes.isNotEmpty || _customPurposes.isNotEmpty;

  void _addCustomPurpose() {
    final text = _customPurposeController.text.trim();
    if (text.isNotEmpty && !_customPurposes.contains(text)) {
      HapticFeedback.selectionClick();
      setState(() {
        _customPurposes.add(text);
        _customPurposeController.clear();
      });
    }
  }

  void _removeCustomPurpose(String purpose) {
    HapticFeedback.selectionClick();
    setState(() {
      _customPurposes.remove(purpose);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            _buildHeader(),
            const Divider(color: AppColors.borderMuted, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Purpose selection label
                    const Text(
                      'PURPOSE',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Purpose toggle chips
                    _buildPurposeChips(),
                    const SizedBox(height: 16),

                    // Custom purpose input
                    _buildCustomPurposeInput(),

                    // Custom purposes list
                    if (_customPurposes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildCustomPurposesList(),
                    ],

                    const SizedBox(height: 24),

                    // Optional duration
                    _buildDurationSection(),
                    const SizedBox(height: 24),

                    // Save to library toggle
                    _buildSaveToggle(),
                    const SizedBox(height: 24),

                    // Action button
                    _buildActionButton(),
                    if (_isEditing) ...[
                      const SizedBox(height: 12),
                      _buildDeleteButton(),
                    ],
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.3),
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
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_outline_rounded,
            color: Color(0xFFF59E0B),
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing ? 'Edit Pause' : 'Pause',
              style: AppTextStyles.title3.copyWith(fontSize: 18),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PausePurposes.predefined.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final purpose = PausePurposes.predefined[index];
          final isSelected = _selectedPurposes.contains(purpose);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedPurposes.remove(purpose);
                } else {
                  _selectedPurposes.add(purpose);
                }
              });
            },
            child: AnimatedContainer(
              duration: AppDurations.instant,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                    : AppColors.scaffoldBg,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFF59E0B)
                      : AppColors.borderMuted,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(Spacing.chipRadius),
              ),
              child: Text(
                purpose,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFF59E0B)
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomPurposeInput() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _customPurposeController,
              focusNode: _customPurposeFocus,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Add custom purpose...',
                hintStyle: AppTextStyles.body.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.scaffoldBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.borderMuted),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.borderMuted),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(
                    color: Color(0xFFF59E0B),
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _addCustomPurpose(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _addCustomPurpose,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFFF59E0B),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomPurposesList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _customPurposes.map((purpose) {
        return Container(
          padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1),
            borderRadius: BorderRadius.circular(Spacing.chipRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                purpose,
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _removeCustomPurpose(purpose),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFF59E0B),
                  size: 16,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle for duration
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasDuration = !_hasDuration;
              if (!_hasDuration) {
                _durationSeconds = null;
              }
            });
          },
          child: Row(
            children: [
              Icon(
                _hasDuration
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: _hasDuration
                    ? const Color(0xFFF59E0B)
                    : AppColors.textMuted,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'DURATION (OPTIONAL)',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),

        // Duration input (shown when toggle is on)
        if (_hasDuration) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 110,
            height: 48,
            child: MaskedDurationInput(
              initialSeconds: _durationSeconds ?? 0,
              maxDigits: 3,
              onChanged: (seconds) {
                setState(() {
                  _durationSeconds = seconds > 0 ? seconds : null;
                });
              },
              textStyle: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              backgroundColor: AppColors.scaffoldBg,
              borderColor: AppColors.borderMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter minutes and seconds',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveToggle() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _saveAsTemplate = !_saveAsTemplate);
      },
      child: Row(
        children: [
          Icon(
            _saveAsTemplate
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: _saveAsTemplate
                ? const Color(0xFFF59E0B)
                : AppColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Save to library for quick reuse',
              style: TextStyle(
                color: _saveAsTemplate
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _hasSelections
            ? () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop(
                  PauseResult(
                    purposes: _selectedPurposes.toList(),
                    customPurposes: _customPurposes,
                    durationSeconds: _hasDuration ? _durationSeconds : null,
                    saveAsTemplate: _saveAsTemplate,
                  ),
                );
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF59E0B),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(
            0xFFF59E0B,
          ).withValues(alpha: 0.2),
          disabledForegroundColor: AppColors.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
        ),
        child: Text(
          _isEditing ? 'Save Changes' : 'Add Pause',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Center(
      child: TextButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(
            PauseResult(
              purposes: _selectedPurposes.toList(),
              customPurposes: _customPurposes,
              saveAsTemplate: _saveAsTemplate,
              deleted: true,
            ),
          );
        },
        child: const Text(
          'Delete',
          style: TextStyle(
            color: AppColors.error,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
