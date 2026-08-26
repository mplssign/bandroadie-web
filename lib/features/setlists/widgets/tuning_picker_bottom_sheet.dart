import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';
import '../tuning/tuning_helpers.dart';
import '../services/custom_tuning_service.dart';
import 'custom_tuning_modal.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// TUNING PICKER BOTTOM SHEET
// Reusable guitar tuning picker with grouped sections.
//
// Features:
// - Grouped by "Standard & Drop Tunings", "Open Tunings", "Special Tunings"
// - Custom Tunings section with add/delete
// - Capo fret selector (horizontal toggle, frets 1-12)
// - Explicit Save / Cancel (no auto-save)
// - 2-line rows: name + string notes
// - Rose/500 accent for selection
// - Physics-based entrance/exit animation
// - Micro-interactions on tap
// ============================================================================

// =============================================================================
// DATA MODEL
// =============================================================================

/// Represents a single tuning option
class TuningOption {
  final String id;
  final String name;
  final String strings;

  const TuningOption({
    required this.id,
    required this.name,
    required this.strings,
  });
}

/// Represents a group of tuning options
class TuningGroup {
  final String title;
  final List<TuningOption> options;

  const TuningGroup({required this.title, required this.options});
}

/// Result returned by the tuning picker when saved.
class TuningPickerResult {
  final String tuningId;
  final int? capoFret;

  const TuningPickerResult({required this.tuningId, this.capoFret});
}

const TuningOption _noneTuningOption = TuningOption(
  id: '',
  name: 'None',
  strings: 'No tuning set',
);

// =============================================================================
// TUNING DATA
// =============================================================================

/// All available tunings, grouped and ordered exactly as specified
const List<TuningGroup> tuningGroups = [
  TuningGroup(
    title: 'Standard & Drop Tunings',
    options: [
      TuningOption(
        id: 'standard_e',
        name: 'Standard (E)',
        strings: 'E A D G B E',
      ),
      TuningOption(
        id: 'half_step_down',
        name: 'Half Step Down (Eb)',
        strings: 'Eb Ab Db Gb Bb Eb',
      ),
      TuningOption(
        id: 'whole_step_down',
        name: 'Whole Step Down (D)',
        strings: 'D G C F A D',
      ),
      TuningOption(id: 'drop_d', name: 'Drop D', strings: 'D A D G B E'),
      TuningOption(id: 'drop_c', name: 'Drop C', strings: 'C G C F A D'),
      TuningOption(
        id: 'drop_db',
        name: 'Drop Db (C#)',
        strings: 'C# G# C# F# A# D#',
      ),
      TuningOption(
        id: 'd_standard',
        name: 'D Standard',
        strings: 'D G C F A D',
      ),
      TuningOption(
        id: 'c_standard',
        name: 'C Standard',
        strings: 'C F Bb Eb G C',
      ),
      TuningOption(id: 'drop_b', name: 'Drop B', strings: 'B F# B E G# C#'),
      TuningOption(
        id: 'b_standard',
        name: 'B Standard (Baritone)',
        strings: 'B E A D F# B',
      ),
      TuningOption(id: 'drop_a', name: 'Drop A', strings: 'A E A D F# B'),
    ],
  ),
  TuningGroup(
    title: 'Open Tunings',
    options: [
      TuningOption(id: 'open_g', name: 'Open G', strings: 'D G D G B D'),
      TuningOption(id: 'open_d', name: 'Open D', strings: 'D A D F# A D'),
      TuningOption(id: 'open_e', name: 'Open E', strings: 'E B E G# B E'),
      TuningOption(id: 'open_a', name: 'Open A', strings: 'E A E A C# E'),
      TuningOption(id: 'open_c', name: 'Open C', strings: 'C G C G C E'),
    ],
  ),
  TuningGroup(
    title: 'Special Tunings',
    options: [
      TuningOption(id: 'dadgad', name: 'DADGAD', strings: 'D A D G A D'),
      TuningOption(
        id: 'nashville',
        name: 'Nashville',
        strings: 'E A D G B E (high)',
      ),
    ],
  ),
];

/// Find a tuning option by ID or name.
/// Handles various naming conventions and legacy data.
TuningOption? findTuningByIdOrName(String? idOrName) {
  if (idOrName == null || idOrName.isEmpty) return null;

  final input = idOrName.trim();
  final inputLower = input.toLowerCase();

  // Map various user inputs and legacy values to canonical IDs
  const aliasToId = <String, String>{
    // Standard tuning aliases
    'standard': 'standard_e',
    'standard e': 'standard_e',
    'e standard': 'standard_e',

    // Half-step down aliases
    'half_step': 'half_step_down',
    'half-step': 'half_step_down',
    'half step': 'half_step_down',
    'half-step down': 'half_step_down',
    'eb standard': 'half_step_down',
    'eb': 'half_step_down',

    // Full/Whole step down aliases
    'full_step': 'whole_step_down',
    'full-step': 'whole_step_down',
    'full step': 'whole_step_down',
    'full-step down': 'whole_step_down',
    'whole step': 'whole_step_down',
    'whole-step': 'whole_step_down',
    'd tuning': 'whole_step_down',

    // Drop D aliases
    'drop d': 'drop_d',
    'dropd': 'drop_d',

    // Drop C aliases
    'drop c': 'drop_c',
    'dropc': 'drop_c',

    // Drop Db / C# aliases
    'drop db': 'drop_db',
    'drop c#': 'drop_db',
    'drop c sharp': 'drop_db',

    // D Standard aliases
    'd standard': 'd_standard',
    'dstandard': 'd_standard',

    // C Standard aliases
    'c standard': 'c_standard',
    'cstandard': 'c_standard',

    // Drop B aliases
    'drop b': 'drop_b',
    'dropb': 'drop_b',

    // B Standard aliases
    'b standard': 'b_standard',
    'bstandard': 'b_standard',
    'baritone': 'b_standard',

    // Drop A aliases
    'drop a': 'drop_a',
    'dropa': 'drop_a',

    // A Standard aliases
    'a standard': 'a_standard',
    'astandard': 'a_standard',

    // Open tuning aliases
    'open g': 'open_g',
    'openg': 'open_g',
    'open d': 'open_d',
    'opend': 'open_d',
    'open e': 'open_e',
    'opene': 'open_e',
    'open a': 'open_a',
    'opena': 'open_a',
    'open c': 'open_c',
    'openc': 'open_c',

    // Special tunings
    'dad gad': 'dadgad',
    'd a d g a d': 'dadgad',
  };

  // Try alias lookup first (case-insensitive)
  final aliasMatch = aliasToId[inputLower];
  if (aliasMatch != null) {
    for (final group in tuningGroups) {
      for (final option in group.options) {
        if (option.id == aliasMatch) return option;
      }
    }
  }

  // Try exact match on ID or name
  for (final group in tuningGroups) {
    for (final option in group.options) {
      if (option.id == input || option.name == input) {
        return option;
      }
    }
  }

  // Try case-insensitive match on ID or name
  for (final group in tuningGroups) {
    for (final option in group.options) {
      if (option.id.toLowerCase() == inputLower ||
          option.name.toLowerCase() == inputLower) {
        return option;
      }
    }
  }

  return null;
}

// =============================================================================
// PUBLIC API
// =============================================================================

/// Show the tuning picker bottom sheet.
///
/// Returns a [TuningPickerResult] with both tuning and optional capo fret,
/// or null if cancelled.
///
/// [selectedTuningIdOrName] can be either an ID (e.g., "drop_d") or
/// a name (e.g., "Drop D") for matching the current selection.
/// [selectedCapoFret] is the currently saved capo fret (1-12), or null.
Future<TuningPickerResult?> showTuningPickerBottomSheet(
  BuildContext context, {
  required String? selectedTuningIdOrName,
  int? selectedCapoFret,
}) async {
  // Light haptic feedback on open
  HapticFeedback.lightImpact();

  return showModalBottomSheet<TuningPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _TuningPickerSheet(
      selectedTuningIdOrName: selectedTuningIdOrName,
      selectedCapoFret: selectedCapoFret,
    ),
  );
}

// =============================================================================
// BOTTOM SHEET WIDGET
// =============================================================================

class _TuningPickerSheet extends StatefulWidget {
  final String? selectedTuningIdOrName;
  final int? selectedCapoFret;

  const _TuningPickerSheet({
    this.selectedTuningIdOrName,
    this.selectedCapoFret,
  });

  @override
  State<_TuningPickerSheet> createState() => _TuningPickerSheetState();
}

class _TuningPickerSheetState extends State<_TuningPickerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Temporary state — not persisted until Save
  TuningOption? _selectedOption;
  int? _selectedCapoFret;

  // Initial values — used to determine if anything has changed
  TuningOption? _initialOption;
  int? _initialCapoFret;

  List<TuningOption> _customTunings = [];
  bool _isLoadingCustom = true;

  bool get _hasChanges =>
      _selectedOption != null &&
      (_selectedOption?.id != _initialOption?.id ||
          _selectedCapoFret != _initialCapoFret);

  @override
  void initState() {
    super.initState();

    // Parse capo from the stored tuning string (e.g. "standard_e|capo:3")
    final parsed = parseCapoTuning(widget.selectedTuningIdOrName);
    final baseTuningId = parsed.tuningId;

    // Initialize temporary state from incoming values
    _selectedOption = findTuningByIdOrName(baseTuningId);
    // Explicit param takes priority, then parsed value from the string
    _selectedCapoFret = widget.selectedCapoFret ?? parsed.capoFret;

    // Snapshot initial values for change detection
    _initialOption = _selectedOption;
    _initialCapoFret = _selectedCapoFret;

    // Load custom tunings
    _loadCustomTunings();

    // Setup entrance animation with physics-based curve
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

  Future<void> _loadCustomTunings() async {
    final service = CustomTuningService();
    final customTunings = await service.getCustomTunings();

    setState(() {
      _customTunings = customTunings
          .map(
            (ct) => TuningOption(id: ct.id, name: ct.name, strings: ct.strings),
          )
          .toList();
      _isLoadingCustom = false;
    });

    // If selected tuning is custom, update selected option
    final baseTuningId =
        parseCapoTuning(widget.selectedTuningIdOrName).tuningId;
    if (baseTuningId != null &&
        CustomTuningService.isCustomTuningId(baseTuningId)) {
      final selected =
          _customTunings.where((t) => t.id == baseTuningId).firstOrNull;
      if (selected != null) {
        setState(() => _selectedOption = selected);
      }
    }
  }

  Future<void> _handleAddCustomTuning() async {
    final customTuning = await showCustomTuningModal(context);

    if (customTuning != null) {
      // Update the cache with the new tuning name
      cacheCustomTuningName(customTuning.id, customTuning.name);

      // Reload custom tunings to include the new one
      await _loadCustomTunings();

      // Auto-select the newly created tuning in temp state
      HapticFeedback.selectionClick();
      if (!mounted) return;
      final newOption =
          _customTunings.where((t) => t.id == customTuning.id).firstOrNull;
      if (newOption != null) {
        setState(() => _selectedOption = newOption);
      }
    }
  }

  Future<void> _handleDeleteCustomTuning(TuningOption option) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
        ),
        title: Text(
          'Delete Custom Tuning?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${option.name}"? This cannot be undone.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.text,
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.mediumImpact();

      // Delete from service
      final service = CustomTuningService();
      await service.deleteCustomTuning(option.id);

      // Remove from cache
      removeCachedCustomTuning(option.id);

      // If the deleted tuning was selected, clear selection
      if (_selectedOption?.id == option.id) {
        setState(() => _selectedOption = null);
      }

      // Reload custom tunings
      await _loadCustomTunings();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _selectTuning(TuningOption option) {
    HapticFeedback.selectionClick();
    setState(() => _selectedOption = option);
  }

  void _selectCapoFret(int fret) {
    HapticFeedback.selectionClick();
    setState(() {
      // Toggle: tap same fret to deselect
      if (_selectedCapoFret == fret) {
        _selectedCapoFret = null;
      } else {
        _selectedCapoFret = fret;
      }
    });
  }

  void _handleSave() {
    if (_selectedOption == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      TuningPickerResult(
        tuningId: _selectedOption!.id,
        capoFret: _selectedCapoFret,
      ),
    );
  }

  void _handleCancel() {
    Navigator.of(context).pop();
  }

  bool _isSelected(TuningOption option) {
    if (_selectedOption == null) return false;
    return option.id == _selectedOption!.id;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.6, 0.95],
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Spacing.cardRadius),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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

                // Scrollable tuning list + capo
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      _buildSectionHeader('None'),
                      _TuningOptionRow(
                        option: _noneTuningOption,
                        isSelected: _isSelected(_noneTuningOption),
                        onTap: () => _selectTuning(_noneTuningOption),
                      ),

                      // Preset tuning groups
                      for (final group in tuningGroups) ...[
                        _buildSectionHeader(group.title),
                        for (final option in group.options)
                          _TuningOptionRow(
                            option: option,
                            isSelected: _isSelected(option),
                            onTap: () => _selectTuning(option),
                          ),
                      ],

                      // Custom tunings section
                      if (!_isLoadingCustom || _customTunings.isNotEmpty) ...[
                        _buildSectionHeader('Custom Tunings'),
                        for (final option in _customTunings)
                          _TuningOptionRow(
                            option: option,
                            isSelected: _isSelected(option),
                            onTap: () => _selectTuning(option),
                            onDelete: () => _handleDeleteCustomTuning(option),
                          ),
                      ],

                      // Add Custom Tuning button
                      _buildAddCustomTuningButton(),

                      // Capo section
                      _buildSectionHeader('Capo'),
                      _buildCapoSubtext(),
                      _buildCapoFretSelector(),

                      const SizedBox(height: Spacing.space16),
                    ],
                  ),
                ),

                // Fixed footer: Save / Cancel
                _buildFixedBottomActions(),
              ],
            ),
          );
        },
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
          Text('Select Tuning', style: AppTextStyles.title3),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space20,
        Spacing.pagePadding,
        Spacing.space8,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSizes.body,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildAddCustomTuningButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space12,
        Spacing.pagePadding,
        Spacing.space4,
      ),
      child: GestureDetector(
        onTap: _handleAddCustomTuning,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space16,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.add, color: AppColors.primary, size: 22),
              const SizedBox(width: Spacing.space8),
              Text(
                'Add Custom Tuning',
                style: TextStyle(
                  fontSize: AppFontSizes.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapoSubtext() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        0,
        Spacing.pagePadding,
        Spacing.space12,
      ),
      child: Text(
        'Select fret',
        style: TextStyle(
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w400,
          color: context.colors.textSecondary,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildCapoFretSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        itemCount: 12,
        separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final fret = index + 1;
          final isSelected = _selectedCapoFret == fret;
          return _CapoFretButton(
            fret: fret,
            isSelected: isSelected,
            onTap: () => _selectCapoFret(fret),
          );
        },
      ),
    );
  }

  Widget _buildFixedBottomActions() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 12,
        bottom: bottomSafe + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Save',
            onPressed: _hasChanges ? _handleSave : null,
            variant: AppButtonVariant.primary,
            backgroundColor: _hasChanges
                ? AppColors.primary
                : context.colors.border.withValues(alpha: 0.3),
            disabledBackgroundColor:
                context.colors.border.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 16),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            fullWidth: true,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Cancel',
            onPressed: _handleCancel,
            variant: AppButtonVariant.text,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CAPO FRET BUTTON
// Styled to match the birthday toggle buttons in my_profile_screen.dart
// =============================================================================

class _CapoFretButton extends StatefulWidget {
  final int fret;
  final bool isSelected;
  final VoidCallback onTap;

  const _CapoFretButton({
    required this.fret,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CapoFretButton> createState() => _CapoFretButtonState();
}

class _CapoFretButtonState extends State<_CapoFretButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.isSelected ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  widget.isSelected ? AppColors.primary : context.colors.border,
            ),
          ),
          child: Center(
            child: Text(
              widget.fret.toString(),
              style: TextStyle(
                fontSize: AppFontSizes.subhead,
                fontWeight: FontWeight.w500,
                color: widget.isSelected
                    ? Colors.white
                    : context.colors.textSecondary,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TUNING OPTION ROW
// =============================================================================

class _TuningOptionRow extends StatefulWidget {
  final TuningOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete; // Optional delete callback for custom tunings

  const _TuningOptionRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<_TuningOptionRow> createState() => _TuningOptionRowState();
}

class _TuningOptionRowState extends State<_TuningOptionRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _tapController.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _tapController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(
            horizontal: Spacing.pagePadding,
            vertical: Spacing.space4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space12,
          ),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : (_isPressed
                    ? context.colors.background.withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary, width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              // Color indicator dot (preview of badge color)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: Spacing.space12),
                decoration: BoxDecoration(
                  color: tuningBadgeColor(widget.option.name),
                  shape: BoxShape.circle,
                ),
              ),

              // Tuning info (2 lines)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line 1: Tuning name
                    Text(
                      widget.option.name,
                      style: TextStyle(
                        fontSize: AppFontSizes.body,
                        fontWeight: FontWeight.w500,
                        color: widget.isSelected
                            ? context.colors.textPrimary
                            : context.colors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Line 2: String notes
                    Text(
                      widget.option.strings,
                      style: TextStyle(
                        fontSize: AppFontSizes.subhead,
                        fontWeight: FontWeight.w400,
                        color: context.colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Check icon for selected
              if (widget.isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: Spacing.space12),
                  child: Icon(
                    AppIcons.check,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),

              // Delete button for custom tunings
              if (widget.onDelete != null)
                GestureDetector(
                  onTap: widget.onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Spacing.space8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        AppIcons.delete,
                        color: Colors.red.shade400,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
