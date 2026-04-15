import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../models/special_item.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// PAUSE SCREEN
// Sub-screen inside the Add to Setlist overlay for configuring a Pause.
//
// - Wrapping purpose chips (toggleable)
// - Custom purpose text fields with + to add more
// - Optional duration checkbox with smart M:SS digit entry
// - "Save for quick reuse" checkbox
// - Saved Pauses list
//
// Calls [onSubmit] with a PauseConfig. The overlay pops on success.
// ============================================================================

/// Result from the pause screen.
class PauseConfig {
  final List<String> purposes;
  final List<String> customPurposes;
  final int? durationSeconds;
  final bool saveAsTemplate;

  const PauseConfig({
    this.purposes = const [],
    this.customPurposes = const [],
    this.durationSeconds,
    this.saveAsTemplate = false,
  });
}

/// Predefined purpose labels.
const List<String> kPredefinedPurposes = [
  'Guitar Change',
  'Band Intro',
  'Crowd Interaction',
  'Instrument Swap',
  'Acoustic Transition',
  'Story/Song Intro',
  'Guest Appearance',
  'Pause for Encore',
  'Tempo Reset',
  'Guitar Solo',
  'Drum Solo',
  'Keys Solo',
  'Bass Solo',
  'Medley Transition',
];

/// Callback when a pause is submitted via configuration.
/// Returns true if the item was added successfully.
typedef OnPauseSubmitted = Future<bool> Function(PauseConfig config);

/// Callback when a pause is updated (edit mode).
/// Returns true if the item was updated successfully.
typedef OnPauseUpdated = Future<bool> Function(
  String specialItemId,
  PauseConfig config,
);

/// Callback when a saved template is tapped (quick add).
/// Returns true if the item was added successfully.
typedef OnSavedPauseSelected = Future<bool> Function(SpecialItem template);

/// Callback to delete a saved template. Returns true on success.
typedef OnDeletePauseTemplate = Future<bool> Function(String templateId);

class PauseScreen extends StatefulWidget {
  final OnPauseSubmitted onSubmit;
  final OnPauseUpdated? onUpdate;
  final OnSavedPauseSelected? onSavedPauseSelected;
  final OnDeletePauseTemplate? onDeleteTemplate;
  final VoidCallback onBack;
  final VoidCallback? onClose;

  /// If non-null, we're in edit mode — prepopulate and update on submit.
  final SpecialItem? editingItem;

  /// Previously saved pause templates for the "Saved Pauses" section.
  final List<SpecialItem> savedPauses;

  const PauseScreen({
    super.key,
    required this.onSubmit,
    this.onUpdate,
    this.onSavedPauseSelected,
    this.onDeleteTemplate,
    required this.onBack,
    this.onClose,
    this.editingItem,
    this.savedPauses = const [],
  });

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  final Set<String> _selectedPurposes = {};

  /// Each entry is a (controller, focusNode) pair for custom purpose fields.
  final List<(TextEditingController, FocusNode)> _customFields = [];

  /// Local mutable copy of saved templates so dismissals update the UI.
  late final List<SpecialItem> _savedPauses;

  /// Controller for the duration text field.
  final TextEditingController _durationController = TextEditingController();

  final FocusNode _durationFocusNode = FocusNode();

  /// Raw digit buffer (max 3 digits). Source of truth for duration value.
  String _rawDigits = '';

  /// Guard to prevent recursive onChanged calls during formatting.
  bool _isFormatting = false;

  bool _showDuration = false;
  bool _saveForReuse = false;
  bool _isSubmitting = false;

  Color get _accent => context.colors.warning; // amber

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    _savedPauses = List<SpecialItem>.from(widget.savedPauses);

    if (widget.editingItem != null) {
      // Prepopulate from editing item
      final item = widget.editingItem!;
      _selectedPurposes.addAll(item.purposes);
      _saveForReuse = item.isSavedTemplate;

      // Prepopulate custom purposes
      if (item.customPurposes.isNotEmpty) {
        for (final cp in item.customPurposes) {
          final controller = TextEditingController(text: cp);
          final focusNode = FocusNode();
          _customFields.add((controller, focusNode));
        }
      } else {
        _addCustomField();
      }

      // Prepopulate duration
      if (item.durationSeconds != null && item.durationSeconds! > 0) {
        _showDuration = true;
        final m = item.durationSeconds! ~/ 60;
        final s = item.durationSeconds! % 60;
        _rawDigits = '$m${s.toString().padLeft(2, '0')}';
        final formatted = '$m:${s.toString().padLeft(2, '0')}';
        _durationController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    } else {
      // Start with one custom purpose field
      _addCustomField();
    }
  }

  @override
  void dispose() {
    for (final (ctrl, focus) in _customFields) {
      ctrl.dispose();
      focus.dispose();
    }
    _durationController.dispose();
    _durationFocusNode.dispose();
    super.dispose();
  }

  // ── Purpose chips ──

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

  // ── Custom purpose fields ──

  void _addCustomField() {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    setState(() {
      _customFields.add((controller, focusNode));
    });
    // Focus the new field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  void _removeCustomField(int index) {
    final (ctrl, focus) = _customFields[index];
    ctrl.dispose();
    focus.dispose();
    setState(() => _customFields.removeAt(index));
  }

  List<String> get _customPurposeValues {
    return _customFields
        .map((e) => e.$1.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // ── Duration ──

  int? get _durationSeconds {
    if (!_showDuration) return null;
    if (_rawDigits.isEmpty) return null;
    final padded = _rawDigits.padLeft(3, '0');
    final minutes = int.parse(padded[0]);
    final seconds = int.parse(padded.substring(1, 3));
    final total = minutes * 60 + seconds;
    return total > 0 ? total : null;
  }

  /// Deterministic 3-digit rolling timer formatter.
  ///
  /// Digits shift left as the user types (like a digital timer):
  ///   2 → 0:02,  25 → 0:25,  250 → 2:50,  2505 → 5:05
  ///
  /// Always keeps cursor at the end. No seconds validation — raw display.
  void _onDurationChanged(String value) {
    if (_isFormatting) return;
    _isFormatting = true;

    // 1. Strip everything except digits
    final digits = value.replaceAll(RegExp('[^0-9]'), '');

    // 2. Keep only the LAST 3 digits (rolling window)
    final trimmed =
        digits.length <= 3 ? digits : digits.substring(digits.length - 3);

    // 3. Store raw digits
    _rawDigits = trimmed;

    // 4. Pad left to 3 and format as M:SS
    final padded = trimmed.padLeft(3, '0');
    final minutes = int.parse(padded[0]);
    final seconds = int.parse(padded.substring(1, 3));
    final formatted = '$minutes:${seconds.toString().padLeft(2, '0')}';

    // 5. Update controller with cursor pinned to end
    _durationController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    _isFormatting = false;
    setState(() {});
  }

  /// Force cursor to end whenever the user taps inside the duration field.
  void _onDurationTap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final len = _durationController.text.length;
      if (_durationController.selection.baseOffset != len) {
        _durationController.selection = TextSelection.collapsed(offset: len);
      }
    });
  }

  // ── Submission ──

  bool get _hasContent =>
      _selectedPurposes.isNotEmpty ||
      _customPurposeValues.isNotEmpty ||
      _durationSeconds != null;

  Future<void> _handleSubmit() async {
    if (_isSubmitting || !_hasContent) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final config = PauseConfig(
      purposes: _selectedPurposes.toList(),
      customPurposes: _customPurposeValues,
      durationSeconds: _durationSeconds,
      saveAsTemplate: _saveForReuse,
    );

    bool success;
    if (_isEditing && widget.onUpdate != null) {
      success = await widget.onUpdate!(widget.editingItem!.id, config);
    } else {
      success = await widget.onSubmit(config);
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(); // Close entire overlay
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  /// Swipe-to-delete a saved pause template.
  Future<bool> _handleDeletePauseTemplate(SpecialItem template) async {
    if (widget.onDeleteTemplate == null) return false;
    final success = await widget.onDeleteTemplate!(template.id);
    if (success && mounted) {
      setState(() => _savedPauses.remove(template));
    }
    return success;
  }

  Future<void> _handleSavedPauseTap(SpecialItem template) async {
    if (_isSubmitting) return;
    if (widget.onSavedPauseSelected == null) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final success = await widget.onSavedPauseSelected!(template);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── PURPOSE title ──
                Text(
                  'Purpose',
                  style: AppTextStyles.title3.copyWith(
                    color: context.colors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Purpose chips (horizontal scroll) ──
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kPredefinedPurposes.length,
                    separatorBuilder: (__, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final purpose = kPredefinedPurposes[index];
                      return _PurposeChip(
                        label: purpose,
                        isSelected: _selectedPurposes.contains(purpose),
                        accent: _accent,
                        onTap: () => _togglePurpose(purpose),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // ── Custom purpose fields ──
                for (var i = 0; i < _customFields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
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
                              controller: _customFields[i].$1,
                              focusNode: _customFields[i].$2,
                              style: AppTextStyles.body.copyWith(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Custom purpose...',
                                hintStyle: AppTextStyles.body.copyWith(
                                  color: context.colors.textDisabled,
                                  fontSize: 14,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: InputBorder.none,
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                // If this field has text, add another
                                if (_customFields[i]
                                    .$1
                                    .text
                                    .trim()
                                    .isNotEmpty) {
                                  _addCustomField();
                                }
                              },
                            ),
                          ),
                        ),
                        // Remove button for extra fields (keep at least one)
                        if (_customFields.length > 1) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _removeCustomField(i),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(
                                  Spacing.buttonRadius,
                                ),
                                border: Border.all(
                                  color: context.colors.border,
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                AppIcons.close,
                                color: context.colors.textMuted,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // ── Add another custom purpose button ──
                GestureDetector(
                  onTap: _addCustomField,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(Spacing.buttonRadius),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Icon(AppIcons.add, color: _accent, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add another',
                        style: AppTextStyles.body.copyWith(
                          color: _accent,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Duration toggle ──
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _showDuration = !_showDuration;
                      if (!_showDuration) {
                        _durationController.clear();
                        _rawDigits = '';
                      }
                    });
                    if (_showDuration) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _durationFocusNode.requestFocus();
                      });
                    }
                  },
                  child: Row(
                    children: [
                      _CheckBox(isChecked: _showDuration, accent: _accent),
                      const SizedBox(width: 10),
                      Text(
                        'Add duration',
                        style: AppTextStyles.body.copyWith(
                          color: context.colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Duration input (animated) ──
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _showDuration
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: 120,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                        border: Border.all(
                          color: _showDuration
                              ? _accent.withValues(alpha: 0.6)
                              : context.colors.border,
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _durationController,
                        focusNode: _durationFocusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: _onDurationChanged,
                        onTap: _onDurationTap,
                        style: AppTextStyles.headline.copyWith(
                          color: context.colors.textPrimary,
                          fontSize: 24,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                        decoration: InputDecoration(
                          hintText: '0:00',
                          hintStyle: AppTextStyles.headline.copyWith(
                            color: context.colors.textDisabled,
                            fontSize: 24,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                ),

                const SizedBox(height: 20),

                // ── Save for quick reuse (create mode only) ──
                if (!_isEditing) ...[
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _saveForReuse = !_saveForReuse);
                    },
                    child: Row(
                      children: [
                        _CheckBox(isChecked: _saveForReuse, accent: _accent),
                        const SizedBox(width: 10),
                        Text(
                          'Save for quick reuse',
                          style: AppTextStyles.body.copyWith(
                            color: context.colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Saved Pauses (create mode only) ──
                if (!_isEditing && _savedPauses.isNotEmpty) ...[
                  Text(
                    'SAVED PAUSES',
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final template in _savedPauses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Dismissible(
                        key: Key('saved_pause_${template.id}'),
                        direction: DismissDirection.endToStart,
                        dismissThresholds: const {
                          DismissDirection.endToStart: 0.4,
                        },
                        confirmDismiss: (_) =>
                            _handleDeletePauseTemplate(template),
                        background: const SizedBox.shrink(),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding:
                              const EdgeInsets.only(right: Spacing.space24),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: Spacing.space8),
                              Icon(AppIcons.delete,
                                  color: Colors.white, size: 22),
                            ],
                          ),
                        ),
                        child: _SavedPauseCard(
                          template: template,
                          accent: _accent,
                          onTap: () => _handleSavedPauseTap(template),
                        ),
                      ),
                    ),
                ],

                // Extra scroll space
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // ── Bottom action bar ──
        Container(
          padding: EdgeInsets.only(
            left: Spacing.pagePadding,
            right: Spacing.pagePadding,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border(
              top: BorderSide(
                color: context.colors.border.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Add Pause button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_hasContent && !_isSubmitting) ? _handleSubmit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.25),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEditing ? 'Save Pause' : 'Add Pause',
                          style: AppTextStyles.button.copyWith(
                            color: _hasContent
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Cancel link
              GestureDetector(
                onTap: widget.onClose ?? () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PRIVATE WIDGETS
// ============================================================================

/// Selectable purpose chip.
class _PurposeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _PurposeChip({
    required this.label,
    required this.isSelected,
    required this.accent,
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
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: isSelected ? accent : context.colors.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Checkbox-style toggle.
class _CheckBox extends StatelessWidget {
  final bool isChecked;
  final Color accent;

  const _CheckBox({required this.isChecked, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isChecked ? accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isChecked ? accent : context.colors.textMuted,
          width: 1.5,
        ),
      ),
      child: isChecked ? Icon(AppIcons.check, size: 16, color: accent) : null,
    );
  }
}

/// Saved pause template card.
class _SavedPauseCard extends StatelessWidget {
  final SpecialItem template;
  final Color accent;
  final VoidCallback onTap;

  const _SavedPauseCard({
    required this.template,
    required this.accent,
    required this.onTap,
  });

  String get _title {
    final allPurposes = [...template.purposes, ...template.customPurposes];
    if (allPurposes.isNotEmpty) {
      return allPurposes.join(' – ').toUpperCase();
    }
    return 'PAUSE';
  }

  String? get _subtitle {
    final secs = template.totalDurationSeconds;
    if (secs <= 0) return null;
    final m = secs ~/ 60;
    final s = secs % 60;
    return '($m:${s.toString().padLeft(2, '0')})';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            color: accent,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: AppTextStyles.headline.copyWith(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _subtitle!,
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Icon(AppIcons.add, color: accent, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
