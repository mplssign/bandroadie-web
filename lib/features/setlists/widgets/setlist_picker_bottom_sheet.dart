import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../models/setlist.dart';
import '../setlists_screen.dart' show setlistsProvider;
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_icon_button.dart';
import '../../../components/ui/app_button.dart';

// ============================================================================
// SETLIST PICKER BOTTOM SHEET
// Bottom sheet for selecting an existing setlist or creating a new one.
//
// USE CASE:
// When user selects songs in the Catalog and taps "Add To Setlist",
// this sheet presents:
// 1. List of existing setlists (excluding Catalog)
// 2. Option to create a new setlist
//
// DESIGN:
// - Matches existing bottom sheet patterns (physics-based animation)
// - Rose accent for selected/action states
// - Empty state if no setlists exist (only "Create New")
// ============================================================================

/// Result from the setlist picker
class SetlistPickerResult {
  /// The selected setlist ID (null if creating new)
  final String? setlistId;

  /// The selected setlist name (null if creating new)
  final String? setlistName;

  /// True if user chose to create a new setlist
  final bool createNew;

  /// The new setlist name (only if createNew is true)
  final String? newSetlistName;

  /// True if Move mode was selected (only relevant when source setlist provided)
  final bool isMoveMode;

  const SetlistPickerResult({
    this.setlistId,
    this.setlistName,
    this.createNew = false,
    this.newSetlistName,
    this.isMoveMode = false,
  });

  /// Factory for selecting an existing setlist
  SetlistPickerResult.existing({
    required this.setlistId,
    required this.setlistName,
    this.isMoveMode = false,
  })  : createNew = false,
        newSetlistName = null;

  /// Factory for creating a new setlist
  SetlistPickerResult.createNew({
    required String name,
    this.isMoveMode = false,
  })  : setlistId = null,
        setlistName = null,
        createNew = true,
        newSetlistName = name;
}

/// Show the setlist picker bottom sheet.
///
/// [selectedSongCount] - Number of songs being added (for header text)
/// [sourceSetlistId] - Optional source setlist ID (enables Move/Copy toggle)
/// [sourceSetlistName] - Optional source setlist name (for Catalog detection)
///
/// Returns a [SetlistPickerResult] with the selected setlist or new name,
/// or null if cancelled.
Future<SetlistPickerResult?> showSetlistPickerBottomSheet(
  BuildContext context, {
  required int selectedSongCount,
  String? sourceSetlistId,
  String? sourceSetlistName,
}) async {
  HapticFeedback.lightImpact();

  return showAppBottomSheet<SetlistPickerResult>(
    context: context,
    isScrollControlled: true,
    mainAxisMaxRatio: 0.85,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _SetlistPickerSheet(
      selectedSongCount: selectedSongCount,
      sourceSetlistId: sourceSetlistId,
      sourceSetlistName: sourceSetlistName,
    ),
  );
}

// =============================================================================
// BOTTOM SHEET WIDGET
// =============================================================================

class _SetlistPickerSheet extends ConsumerStatefulWidget {
  final int selectedSongCount;
  final String? sourceSetlistId;
  final String? sourceSetlistName;

  const _SetlistPickerSheet({
    required this.selectedSongCount,
    this.sourceSetlistId,
    this.sourceSetlistName,
  });

  @override
  ConsumerState<_SetlistPickerSheet> createState() =>
      _SetlistPickerSheetState();
}

class _SetlistPickerSheetState extends ConsumerState<_SetlistPickerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Create new setlist mode
  bool _isCreatingNew = false;
  final TextEditingController _newNameController = TextEditingController();
  final FocusNode _newNameFocus = FocusNode();
  String? _validationError;

  // Move/Copy mode (only shown when sourceSetlistId != null)
  bool _isMoveMode = false;

  @override
  void initState() {
    super.initState();

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
    _newNameController.dispose();
    _newNameFocus.dispose();
    super.dispose();
  }

  void _handleSelectSetlist(Setlist setlist) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      SetlistPickerResult.existing(
        setlistId: setlist.id,
        setlistName: setlist.name,
        isMoveMode: _isMoveMode,
      ),
    );
  }

  void _handleCreateNew() {
    setState(() {
      _isCreatingNew = true;
      _validationError = null;
    });
    // Focus the text field after rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _newNameFocus.requestFocus();
    });
  }

  void _handleConfirmCreate() {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _validationError = 'Name cannot be empty';
      });
      return;
    }

    // Check for duplicate names
    final setlistsState = ref.read(setlistsProvider);
    final existingNames =
        setlistsState.setlists.map((s) => s.name.toLowerCase()).toSet();
    if (existingNames.contains(name.toLowerCase())) {
      setState(() {
        _validationError = 'A setlist with this name already exists';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      SetlistPickerResult.createNew(name: name, isMoveMode: _isMoveMode),
    );
  }

  void _handleCancelCreate() {
    setState(() {
      _isCreatingNew = false;
      _validationError = null;
      _newNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final setlistsState = ref.watch(setlistsProvider);

    // Filter out Catalog setlist
    final selectableSetlists =
        setlistsState.setlists.where((s) => !s.isCatalog).toList();

    // Get keyboard height to push content above keyboard
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 100),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(),

              // Content (existing setlists or create new)
              Flexible(
                child: _isCreatingNew
                    ? _buildCreateNewForm()
                    : _buildSetlistList(selectableSetlists),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final songsText = widget.selectedSongCount == 1
        ? '1 song'
        : '${widget.selectedSongCount} songs';

    // Check if source is Catalog (Move option should be disabled)
    final isSourceCatalog = widget.sourceSetlistName != null &&
        isCatalogName(widget.sourceSetlistName!);

    // Show Move/Copy toggle only when source setlist is provided
    final showToggle = widget.sourceSetlistId != null && !isSourceCatalog;

    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCreatingNew ? 'Create New Setlist' : 'Add To Setlist',
                      style: AppTextStyles.title3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adding $songsText',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              AppIconButton(
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          // Move/Copy toggle (only shown when source setlist provided and not Catalog)
          if (showToggle) ...[
            const SizedBox(height: Spacing.space12),
            _buildMoveCopyToggle(),
          ],
        ],
      ),
    );
  }

  Widget _buildMoveCopyToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(
          color: context.colors.textSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleOption(
              label: 'Copy',
              isSelected: !_isMoveMode,
              onTap: () {
                setState(() {
                  _isMoveMode = false;
                });
                HapticFeedback.lightImpact();
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildToggleOption(
              label: 'Move',
              isSelected: _isMoveMode,
              onTap: () {
                setState(() {
                  _isMoveMode = true;
                });
                HapticFeedback.lightImpact();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.space8,
          horizontal: Spacing.space12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius - 2),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.callout.copyWith(
              color: isSelected ? Colors.white : context.colors.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetlistList(List<Setlist> setlists) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Create New option (always first)
        _SetlistOptionTile(
          icon: AppIcons.add,
          title: 'Create New Setlist',
          subtitle: 'Start a fresh setlist with selected songs',
          isCreateNew: true,
          onTap: _handleCreateNew,
        ),

        // Divider
        if (setlists.isNotEmpty)
          Divider(
            color: context.colors.textSecondary.withValues(alpha: 0.2),
            height: 1,
          ),

        // Existing setlists
        if (setlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.space24),
            child: Column(
              children: [
                Icon(
                  AppIcons.setlists,
                  size: 48,
                  color: context.colors.textMuted,
                ),
                const SizedBox(height: Spacing.space12),
                Text(
                  'No setlists yet',
                  style: AppTextStyles.headline.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Text(
                  'Create one to add your songs!',
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: setlists.length,
              itemBuilder: (context, index) {
                final setlist = setlists[index];
                return _SetlistOptionTile(
                  icon: AppIcons.setlists,
                  title: setlist.name,
                  subtitle: '${setlist.songCount} songs',
                  onTap: () => _handleSelectSetlist(setlist),
                );
              },
            ),
          ),

        // Bottom padding
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }

  Widget _buildCreateNewForm() {
    return Padding(
      padding: const EdgeInsets.all(Spacing.space16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text field
          AppTextField(
            controller: _newNameController,
            focusNode: _newNameFocus,
            autofocus: true,
            hintText: 'Setlist name',
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_validationError != null) {
                setState(() {
                  _validationError = null;
                });
              }
            },
            onSubmitted: (_) => _handleConfirmCreate(),
          ),

          const SizedBox(height: Spacing.space16),

          // Action buttons
          Row(
            children: [
              // Cancel
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.outlined,
                  onPressed: _handleCancelCreate,
                ),
              ),

              const SizedBox(width: Spacing.space12),

              // Create & Add
              Expanded(
                child: AppButton(
                  label: 'Create & Add',
                  variant: AppButtonVariant.primary,
                  onPressed: _handleConfirmCreate,
                ),
              ),
            ],
          ),

          // Bottom safe area padding (keyboard handled at container level)
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// =============================================================================
// SETLIST OPTION TILE
// =============================================================================

class _SetlistOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCreateNew;
  final VoidCallback onTap;

  const _SetlistOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isCreateNew = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space14,
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isCreateNew
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : context.colors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isCreateNew
                      ? AppColors.primary
                      : context.colors.textPrimary,
                ),
              ),

              const SizedBox(width: Spacing.space12),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.headline.copyWith(
                        color: isCreateNew
                            ? AppColors.primary
                            : context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                AppIcons.forward,
                size: 20,
                color: context.colors.textSecondary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
