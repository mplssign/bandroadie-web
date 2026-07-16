import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// PAUSE CREATOR
// Bottom sheet for configuring a Pause: purpose chips + optional M:SS duration.
// Returns a PauseConfig or null if cancelled.
// ============================================================================

/// Result from the pause creator.
class PauseConfig {
  final List<String> purposes;
  final List<String> customPurposes;
  final int? durationSeconds;

  const PauseConfig({
    this.purposes = const [],
    this.customPurposes = const [],
    this.durationSeconds,
  });
}

/// Predefined purpose labels.
const List<String> _predefinedPurposes = [
  'Guitar Change',
  'Tuning',
  'Band Intro',
  'Audience Interaction',
  'Costume Change',
  'Equipment Swap',
];

/// Show the Pause creator bottom sheet.
Future<PauseConfig?> showPauseCreator(BuildContext context) async {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<PauseConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => const _PauseCreatorSheet(),
  );
}

class _PauseCreatorSheet extends StatefulWidget {
  const _PauseCreatorSheet();

  @override
  State<_PauseCreatorSheet> createState() => _PauseCreatorSheetState();
}

class _PauseCreatorSheetState extends State<_PauseCreatorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final Set<String> _selectedPurposes = {};
  final List<String> _customPurposes = [];
  final TextEditingController _customPurposeController =
      TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();
  final FocusNode _customPurposeFocus = FocusNode();

  Color get _accent => context.colors.warning; // amber

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AppDurations.normal,
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.15, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: AppCurves.slideIn),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _customPurposeController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _customPurposeFocus.dispose();
    super.dispose();
  }

  void _togglePurpose(String purpose) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPurposes.contains(purpose)) {
        _selectedPurposes.remove(purpose);
      } else {
        _selectedPurposes.add(purpose);
      }
    });
  }

  void _addCustomPurpose() {
    final text = _customPurposeController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _customPurposes.add(text);
      _customPurposeController.clear();
    });
    _customPurposeFocus.requestFocus();
  }

  void _removeCustomPurpose(int index) {
    HapticFeedback.selectionClick();
    setState(() => _customPurposes.removeAt(index));
  }

  int? get _durationSeconds {
    final m = int.tryParse(_minutesController.text) ?? 0;
    final s = int.tryParse(_secondsController.text) ?? 0;
    final total = m * 60 + s;
    return total > 0 ? total : null;
  }

  bool get _hasContent =>
      _selectedPurposes.isNotEmpty ||
      _customPurposes.isNotEmpty ||
      _durationSeconds != null;

  void _submit() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      PauseConfig(
        purposes: _selectedPurposes.toList(),
        customPurposes: List.from(_customPurposes),
        durationSeconds: _durationSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.only(bottom: bottomInset),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.colors.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Title row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pause_circle_outline_rounded,
                        color: _accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Pause',
                        style: AppTextStyles.title3.copyWith(color: _accent),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(
                          AppIcons.close,
                          color: context.colors.textMuted,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: Text(
                    'What\'s this pause for?',
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Purpose chips ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final purpose in _predefinedPurposes)
                        _PurposeChip(
                          label: purpose,
                          isSelected: _selectedPurposes.contains(purpose),
                          accent: _accent,
                          onTap: () => _togglePurpose(purpose),
                        ),
                      // Custom purpose chips
                      for (var i = 0; i < _customPurposes.length; i++)
                        _PurposeChip(
                          label: _customPurposes[i],
                          isSelected: true,
                          accent: _accent,
                          isCustom: true,
                          onTap: () => _removeCustomPurpose(i),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Custom purpose input ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                            border: Border.all(
                              color: context.colors.border,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: _customPurposeController,
                            focusNode: _customPurposeFocus,
                            style: AppTextStyles.body.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: AppFontSizes.subhead,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Custom reason…',
                              hintStyle: AppTextStyles.body.copyWith(
                                color: context.colors.textDisabled,
                                fontSize: AppFontSizes.subhead,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: InputBorder.none,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addCustomPurpose(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _addCustomPurpose,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            AppIcons.add,
                            color: _accent,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Optional duration ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: Text(
                    'Duration (optional)',
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.textMuted,
                      fontSize: AppFontSizes.caption,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: Row(
                    children: [
                      // Minutes
                      SizedBox(
                        width: 64,
                        height: 42,
                        child: _DurationField(
                          controller: _minutesController,
                          hint: 'M',
                          maxValue: 59,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          ':',
                          style: AppTextStyles.headline.copyWith(
                            color: context.colors.textMuted,
                            fontSize: AppFontSizes.title2,
                          ),
                        ),
                      ),
                      // Seconds
                      SizedBox(
                        width: 64,
                        height: 42,
                        child: _DurationField(
                          controller: _secondsController,
                          hint: 'SS',
                          maxValue: 59,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Add button ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _hasContent ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _accent.withValues(alpha: 0.25),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(Spacing.buttonRadius),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Add Pause',
                        style: AppTextStyles.button.copyWith(
                          color: _hasContent
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selectable purpose chip.
class _PurposeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color accent;
  final bool isCustom;
  final VoidCallback onTap;

  const _PurposeChip({
    required this.label,
    required this.isSelected,
    required this.accent,
    this.isCustom = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.15)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(Spacing.chipRadius),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.5)
                : context.colors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: isSelected ? accent : context.colors.textSecondary,
                fontSize: AppFontSizes.caption,
              ),
            ),
            if (isCustom && isSelected) ...[
              const SizedBox(width: 4),
              Icon(AppIcons.close, size: 14, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small numeric field for M:SS duration input.
class _DurationField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxValue;

  const _DurationField({
    required this.controller,
    required this.hint,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.border, width: 1),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        style: AppTextStyles.headline.copyWith(
          color: context.colors.textPrimary,
          fontSize: AppFontSizes.body,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          _MaxValueFormatter(maxValue),
        ],
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.headline.copyWith(
            color: context.colors.textDisabled,
            fontSize: AppFontSizes.body,
          ),
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// Input formatter that caps numeric value.
class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  _MaxValueFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final val = int.tryParse(newValue.text);
    if (val == null || val > max) return oldValue;
    return newValue;
  }
}
