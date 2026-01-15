import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../tuning/tuning_helpers.dart';

// ============================================================================
// TUNING PICKER BOTTOM SHEET
// Reusable guitar tuning picker with grouped sections.
//
// Features:
// - Grouped by "Standard & Drop Tunings" and "Open Tunings"
// - 2-line rows: name + string notes
// - Rose/500 accent for selection
// - Physics-based entrance/exit animation
// - Micro-interactions on tap
//
// NOTE: Currently limited to 4 tunings supported by legacy database enum.
// Once migration is applied, all tunings can be enabled.
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
      TuningOption(id: 'custom', name: 'Custom', strings: 'Custom tuning'),
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
/// Returns the selected tuning's name, or null if cancelled.
/// [selectedTuningIdOrName] can be either an ID (e.g., "drop_d") or
/// a name (e.g., "Drop D") for matching the current selection.
Future<String?> showTuningPickerBottomSheet(
  BuildContext context, {
  required String? selectedTuningIdOrName,
}) async {
  // Light haptic feedback on open
  HapticFeedback.lightImpact();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) =>
        _TuningPickerSheet(selectedTuningIdOrName: selectedTuningIdOrName),
  );
}

// =============================================================================
// BOTTOM SHEET WIDGET
// =============================================================================

class _TuningPickerSheet extends StatefulWidget {
  final String? selectedTuningIdOrName;

  const _TuningPickerSheet({this.selectedTuningIdOrName});

  @override
  State<_TuningPickerSheet> createState() => _TuningPickerSheetState();
}

class _TuningPickerSheetState extends State<_TuningPickerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  TuningOption? _selectedOption;

  @override
  void initState() {
    super.initState();

    // Find the currently selected option
    _selectedOption = findTuningByIdOrName(widget.selectedTuningIdOrName);

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

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _selectTuning(TuningOption option) {
    HapticFeedback.selectionClick();
    // Return the ID (e.g., "drop_d") for database storage
    Navigator.of(context).pop(option.id);
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
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        snap: true,
        snapSizes: const [0.4, 0.65, 0.85],
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
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
                const Divider(
                  color: AppColors.borderMuted,
                  height: 1,
                  thickness: 1,
                ),

                // Tuning list
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: Spacing.space32),
                    itemCount: _buildItemCount(),
                    itemBuilder: (context, index) {
                      return _buildListItem(index);
                    },
                  ),
                ),
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
          Text('Select Tuning', style: AppTextStyles.title3),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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

  int _buildItemCount() {
    int count = 0;
    for (final group in tuningGroups) {
      count += 1; // Section header
      count += group.options.length; // Options
    }
    return count;
  }

  Widget _buildListItem(int index) {
    int currentIndex = 0;

    for (final group in tuningGroups) {
      // Section header
      if (index == currentIndex) {
        return _buildSectionHeader(group.title);
      }
      currentIndex++;

      // Options in this group
      for (final option in group.options) {
        if (index == currentIndex) {
          return _TuningOptionRow(
            option: option,
            isSelected: _isSelected(option),
            onTap: () => _selectTuning(option),
          );
        }
        currentIndex++;
      }
    }

    return const SizedBox.shrink();
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
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
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

  const _TuningOptionRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
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
                ? AppColors.accent.withValues(alpha: 0.12)
                : (_isPressed
                      ? AppColors.scaffoldBg.withValues(alpha: 0.5)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: widget.isSelected
                ? Border.all(color: AppColors.accent, width: 1.5)
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
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: widget.isSelected
                            ? AppColors.textPrimary
                            : AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Line 2: String notes
                    Text(
                      widget.option.strings,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
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
                    Icons.check_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
