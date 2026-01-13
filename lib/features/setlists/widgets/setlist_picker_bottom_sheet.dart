import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist.dart';
import '../setlists_screen.dart' show setlistsProvider;

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

  const SetlistPickerResult({
    this.setlistId,
    this.setlistName,
    this.createNew = false,
    this.newSetlistName,
  });

  /// Factory for selecting an existing setlist
  const SetlistPickerResult.existing({
    required this.setlistId,
    required this.setlistName,
  }) : createNew = false,
       newSetlistName = null;

  /// Factory for creating a new setlist
  const SetlistPickerResult.createNew({required String name})
    : setlistId = null,
      setlistName = null,
      createNew = true,
      newSetlistName = name;
}

/// Show the setlist picker bottom sheet.
///
/// [selectedSongCount] - Number of songs being added (for header text)
///
/// Returns a [SetlistPickerResult] with the selected setlist or new name,
/// or null if cancelled.
Future<SetlistPickerResult?> showSetlistPickerBottomSheet(
  BuildContext context, {
  required int selectedSongCount,
}) async {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<SetlistPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) =>
        _SetlistPickerSheet(selectedSongCount: selectedSongCount),
  );
}

// =============================================================================
// BOTTOM SHEET WIDGET
// =============================================================================

class _SetlistPickerSheet extends ConsumerStatefulWidget {
  final int selectedSongCount;

  const _SetlistPickerSheet({required this.selectedSongCount});

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
    final existingNames = setlistsState.setlists
        .map((s) => s.name.toLowerCase())
        .toSet();
    if (existingNames.contains(name.toLowerCase())) {
      setState(() {
        _validationError = 'A setlist with this name already exists';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(SetlistPickerResult.createNew(name: name));
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
    final selectableSetlists = setlistsState.setlists
        .where((s) => !s.isCatalog)
        .toList();

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 100),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
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
    );
  }

  Widget _buildHeader() {
    final songsText = widget.selectedSongCount == 1
        ? '1 song'
        : '${widget.selectedSongCount} songs';

    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
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
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Close button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetlistList(List<Setlist> setlists) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Create New option (always first)
        _SetlistOptionTile(
          icon: Icons.add_rounded,
          title: 'Create New Setlist',
          subtitle: 'Start a fresh setlist with selected songs',
          isCreateNew: true,
          onTap: _handleCreateNew,
        ),

        // Divider
        if (setlists.isNotEmpty)
          Divider(
            color: AppColors.textSecondary.withValues(alpha: 0.2),
            height: 1,
          ),

        // Existing setlists
        if (setlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.space24),
            child: Column(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: Spacing.space12),
                Text(
                  'No setlists yet',
                  style: AppTextStyles.headline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Text(
                  'Create one to add your songs!',
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textMuted,
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
                  icon: Icons.queue_music_rounded,
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
          TextField(
            controller: _newNameController,
            focusNode: _newNameFocus,
            autofocus: true,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Setlist name',
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
              ),
              errorText: _validationError,
              filled: true,
              fillColor: AppColors.scaffoldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(color: AppColors.accent, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(color: AppColors.accent, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(color: AppColors.error, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(color: AppColors.error, width: 1.5),
              ),
            ),
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
                child: OutlinedButton(
                  onPressed: _handleCancelCreate,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: Spacing.space12),

              // Create & Add
              Expanded(
                child: FilledButton(
                  onPressed: _handleConfirmCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Create & Add',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          // Bottom padding
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
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isCreateNew ? AppColors.accent : AppColors.textPrimary,
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
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.footnote.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
