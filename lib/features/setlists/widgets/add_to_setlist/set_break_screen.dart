import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../models/special_item.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_button.dart';

// ============================================================================
// SET BREAK SCREEN
// Sub-screen inside the Add to Setlist overlay for configuring a Set Break.
// Duration stepper with +/- 5-minute buttons (5–60 min, default 15).
//
// Supports both create and edit mode.
// Edit mode: pass [editingItem] to prepopulate fields and update on submit.
//
// Calls [onSubmit] with the chosen duration and save preference.
// Calls [onUpdate] when editing an existing item.
// The overlay pops on success.
// ============================================================================

/// Callback when a set break is submitted (create mode).
/// Returns true if the item was added successfully.
typedef OnSetBreakSubmitted = Future<bool> Function(
  int durationMinutes, {
  bool saveAsTemplate,
});

/// Callback when a set break is updated (edit mode).
/// Returns true if the item was updated successfully.
typedef OnSetBreakUpdated = Future<bool> Function(
  String specialItemId,
  int durationMinutes,
);

/// Callback when a saved set break template is tapped (quick add).
typedef OnSavedSetBreakSelected = Future<bool> Function(SpecialItem template);

/// Callback to delete a saved template. Returns true on success.
typedef OnDeleteTemplate = Future<bool> Function(String templateId);

class SetBreakScreen extends StatefulWidget {
  final OnSetBreakSubmitted onSubmit;
  final OnSetBreakUpdated? onUpdate;
  final OnSavedSetBreakSelected? onSavedSetBreakSelected;
  final OnDeleteTemplate? onDeleteTemplate;
  final VoidCallback onBack;
  final VoidCallback? onClose;

  /// If non-null, we're in edit mode — prepopulate and update on submit.
  final SpecialItem? editingItem;

  /// The setlist_songs row ID (for edit context tracking).
  final String? editingSetlistSongId;

  /// Previously saved set break templates.
  final List<SpecialItem> savedSetBreaks;

  const SetBreakScreen({
    super.key,
    required this.onSubmit,
    this.onUpdate,
    this.onSavedSetBreakSelected,
    this.onDeleteTemplate,
    required this.onBack,
    this.onClose,
    this.editingItem,
    this.editingSetlistSongId,
    this.savedSetBreaks = const [],
  });

  @override
  State<SetBreakScreen> createState() => _SetBreakScreenState();
}

class _SetBreakScreenState extends State<SetBreakScreen> {
  int _minutes = 15;
  bool _saveForReuse = false;
  bool _isSubmitting = false;

  /// Local mutable copy of saved templates so dismissals update the UI.
  late final List<SpecialItem> _savedSetBreaks;

  static const int _minMinutes = 5;
  static const int _maxMinutes = 60;
  static const int _step = 5;

  Color get _accent => context.colors.primaryDim; // rose

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    _savedSetBreaks = List<SpecialItem>.from(widget.savedSetBreaks);
    // Prepopulate from editing item
    if (widget.editingItem != null) {
      final mins = widget.editingItem!.durationMinutes ?? 15;
      _minutes = (mins ~/ _step) * _step; // snap to nearest step
      if (_minutes < _minMinutes) _minutes = _minMinutes;
      if (_minutes > _maxMinutes) _minutes = _maxMinutes;
      _saveForReuse = widget.editingItem!.isSavedTemplate;
    }
  }

  void _increment() {
    if (_minutes + _step <= _maxMinutes) {
      HapticFeedback.selectionClick();
      setState(() => _minutes += _step);
    }
  }

  void _decrement() {
    if (_minutes - _step >= _minMinutes) {
      HapticFeedback.selectionClick();
      setState(() => _minutes -= _step);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    bool success;
    if (_isEditing && widget.onUpdate != null) {
      success = await widget.onUpdate!(
        widget.editingItem!.id,
        _minutes,
      );
    } else {
      success = await widget.onSubmit(
        _minutes,
        saveAsTemplate: _saveForReuse,
      );
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(); // Close entire overlay
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  /// Swipe-to-delete a saved set break template.
  Future<bool> _handleDeleteTemplate(SpecialItem template) async {
    if (widget.onDeleteTemplate == null) return false;
    final success = await widget.onDeleteTemplate!(template.id);
    if (success && mounted) {
      setState(() => _savedSetBreaks.remove(template));
    }
    return success;
  }

  Future<void> _handleSavedSetBreakTap(SpecialItem template) async {
    if (_isSubmitting) return;
    if (widget.onSavedSetBreakSelected == null) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final success = await widget.onSavedSetBreakSelected!(template);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Scrollable content area ──
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),

                // Subtitle
                Text(
                  'How long is this break?',
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),

                const SizedBox(height: 48),

                // ── Duration stepper ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StepperButton(
                      icon: AppIcons.remove,
                      enabled: _minutes > _minMinutes && !_isSubmitting,
                      accent: _accent,
                      onTap: _decrement,
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          Text(
                            '$_minutes',
                            style: AppTextStyles.displayLarge.copyWith(
                              fontSize: AppFontSizes.hero,
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'minutes',
                            style: AppTextStyles.label.copyWith(
                              color: context.colors.textMuted,
                              fontSize: AppFontSizes.subhead,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    _StepperButton(
                      icon: AppIcons.add,
                      enabled: _minutes < _maxMinutes && !_isSubmitting,
                      accent: _accent,
                      onTap: _increment,
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Save for quick reuse (create mode only) ──
                if (!_isEditing) ...[
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _saveForReuse = !_saveForReuse);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CheckBox(isChecked: _saveForReuse, accent: _accent),
                        const SizedBox(width: 10),
                        Text(
                          'Save for quick reuse',
                          style: AppTextStyles.body.copyWith(
                            color: context.colors.textSecondary,
                            fontSize: AppFontSizes.subhead,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Saved Set Breaks ──
                if (!_isEditing && _savedSetBreaks.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SAVED SET BREAKS',
                      style: AppTextStyles.label.copyWith(
                        color: context.colors.textMuted,
                        fontSize: AppFontSizes.caption,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final template in _savedSetBreaks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Dismissible(
                        key: Key('saved_sb_${template.id}'),
                        direction: DismissDirection.endToStart,
                        dismissThresholds: const {
                          DismissDirection.endToStart: 0.4,
                        },
                        confirmDismiss: (_) => _handleDeleteTemplate(template),
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
                                  fontSize: AppFontSizes.subhead,
                                ),
                              ),
                              SizedBox(width: Spacing.space8),
                              Icon(AppIcons.delete,
                                  color: Colors.white, size: 22),
                            ],
                          ),
                        ),
                        child: _SavedSetBreakCard(
                          template: template,
                          accent: _accent,
                          onTap: () => _handleSavedSetBreakTap(template),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        // ── Fixed bottom action bar ──
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
              // Add Set Break button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: AppButton(
                  label: _isEditing ? 'Save Set Break' : 'Add Set Break',
                  onPressed: _handleSubmit,
                  variant: AppButtonVariant.secondary,
                  isLoading: _isSubmitting,
                  fullWidth: true,
                  backgroundColor: _accent,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  elevation: 0,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.4),
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
                      fontSize: AppFontSizes.body,
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

/// Circular +/- stepper button.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? accent : context.colors.textDisabled;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          color: enabled ? context.colors.surface : Colors.transparent,
        ),
        child: Icon(icon, color: color, size: 28),
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

/// Saved set break template card.
class _SavedSetBreakCard extends StatelessWidget {
  final SpecialItem template;
  final Color accent;
  final VoidCallback onTap;

  const _SavedSetBreakCard({
    required this.template,
    required this.accent,
    required this.onTap,
  });

  String get _title {
    final mins = template.durationMinutes ?? 0;
    return 'SET BREAK${mins > 0 ? ' – $mins mins' : ''}';
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
            AppIcons.timer,
            color: accent,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _title,
              style: AppTextStyles.headline.copyWith(
                color: context.colors.textPrimary,
                fontSize: AppFontSizes.caption,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
