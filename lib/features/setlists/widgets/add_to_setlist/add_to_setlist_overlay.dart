import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../models/bulk_song_row.dart';
import '../../models/setlist_item_type.dart';
import '../../models/special_item.dart';
import 'bulk_entry_screen.dart';
import 'category_screen.dart';
import 'original_song_screen.dart';
import 'pause_screen.dart';
import 'set_break_screen.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// ADD TO SETLIST OVERLAY
// Full-screen modal overlay (matches Song Lookup overlay style).
// Shows CategoryScreen and navigates to sub-screens with slide animations.
// ============================================================================

enum AddToSetlistCategory {
  cover,
  original,
  bulk,
  setBreak,
  pause,
}

/// Show the Add to Setlist overlay as a full-screen general dialog.
///
/// [onCategorySelected] fires for categories handled externally (cover).
/// The overlay pops before invoking the callback.
///
/// [defaultArtist] is auto-filled into the Artist field for original songs.
///
/// [onOriginalSongsSubmitted] is called when the user submits original songs
/// from within the overlay. It receives a list of (title, artist) records and
/// should return the number of songs successfully added.
///
/// [onBulkSongsSubmitted] is called when the user submits from the Bulk Entry
/// screen. It receives a list of valid [BulkSongRow] objects.
///
/// [onSetBreakSubmitted] is called when the user configures and submits a Set
/// Break from within the overlay. Returns true if added successfully.
///
/// [onPauseSubmitted] is called when the user configures and submits a Pause.
/// Returns true if added successfully.
///
/// [onSavedPauseSelected] is called when a saved pause template is tapped.
///
/// [savedPauses] is a list of previously saved pause templates.
Future<void> showAddToSetlistOverlay({
  required BuildContext context,
  required void Function(AddToSetlistCategory category) onCategorySelected,
  bool isCatalog = false,
  String defaultArtist = '',
  OnOriginalSongsSubmitted? onOriginalSongsSubmitted,
  OnBulkSongsSubmitted? onBulkSongsSubmitted,
  OnSetBreakSubmitted? onSetBreakSubmitted,
  OnPauseSubmitted? onPauseSubmitted,
  OnSavedPauseSelected? onSavedPauseSelected,
  OnSavedSetBreakSelected? onSavedSetBreakSelected,
  OnDeleteTemplate? onDeleteTemplate,
  List<SpecialItem> savedPauses = const [],
  List<SpecialItem> savedSetBreaks = const [],
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _AddToSetlistOverlay(
        onCategorySelected: (category) {
          // Original, bulk, setBreak, pause are handled inside the overlay
          if (category == AddToSetlistCategory.original) return;
          if (category == AddToSetlistCategory.bulk) return;
          if (category == AddToSetlistCategory.setBreak) return;
          if (category == AddToSetlistCategory.pause) return;
          Navigator.of(dialogContext).pop();
          onCategorySelected(category);
        },
        isCatalog: isCatalog,
        defaultArtist: defaultArtist,
        onOriginalSongsSubmitted: onOriginalSongsSubmitted,
        onBulkSongsSubmitted: onBulkSongsSubmitted,
        onSetBreakSubmitted: onSetBreakSubmitted,
        onPauseSubmitted: onPauseSubmitted,
        onSavedPauseSelected: onSavedPauseSelected,
        onSavedSetBreakSelected: onSavedSetBreakSelected,
        onDeleteTemplate: onDeleteTemplate,
        savedPauses: savedPauses,
        savedSetBreaks: savedSetBreaks,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class _AddToSetlistOverlay extends StatefulWidget {
  final void Function(AddToSetlistCategory category) onCategorySelected;
  final bool isCatalog;
  final String defaultArtist;
  final OnOriginalSongsSubmitted? onOriginalSongsSubmitted;
  final OnBulkSongsSubmitted? onBulkSongsSubmitted;
  final OnSetBreakSubmitted? onSetBreakSubmitted;
  final OnPauseSubmitted? onPauseSubmitted;
  final OnSavedPauseSelected? onSavedPauseSelected;
  final OnSavedSetBreakSelected? onSavedSetBreakSelected;
  final OnDeleteTemplate? onDeleteTemplate;
  final List<SpecialItem> savedPauses;
  final List<SpecialItem> savedSetBreaks;

  const _AddToSetlistOverlay({
    required this.onCategorySelected,
    required this.isCatalog,
    required this.defaultArtist,
    this.onOriginalSongsSubmitted,
    this.onBulkSongsSubmitted,
    this.onSetBreakSubmitted,
    this.onPauseSubmitted,
    this.onSavedPauseSelected,
    this.onSavedSetBreakSelected,
    this.onDeleteTemplate,
    this.savedPauses = const [],
    this.savedSetBreaks = const [],
  });

  @override
  State<_AddToSetlistOverlay> createState() => _AddToSetlistOverlayState();
}

class _AddToSetlistOverlayState extends State<_AddToSetlistOverlay> {
  /// null = category screen, otherwise the selected sub-category
  AddToSetlistCategory? _activeCategory;

  void _handleCategorySelected(AddToSetlistCategory category) {
    if (category == AddToSetlistCategory.original ||
        category == AddToSetlistCategory.bulk ||
        category == AddToSetlistCategory.setBreak ||
        category == AddToSetlistCategory.pause) {
      setState(() {
        _activeCategory = category;
      });
    } else {
      widget.onCategorySelected(category);
    }
  }

  void _handleBack() {
    setState(() {
      _activeCategory = null;
    });
  }

  String get _title {
    switch (_activeCategory) {
      case AddToSetlistCategory.original:
        return 'Original Song';
      case AddToSetlistCategory.bulk:
        return 'Bulk Entry';
      case AddToSetlistCategory.setBreak:
        return 'Set Break';
      case AddToSetlistCategory.pause:
        return 'Pause';
      default:
        return 'Add to Setlist';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(Spacing.space16),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: context.colors.border, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Column(
              children: [
                // ── Header ──
                _buildHeader(),

                Divider(color: context.colors.border, height: 1),

                // ── Content area with animated transitions ──
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      child: Row(
        children: [
          // Back button — left
          GestureDetector(
            onTap: _activeCategory != null
                ? _handleBack
                : () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.back,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  Text(
                    'Back',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Centered title
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _title,
                  key: ValueKey(_title),
                  style: AppTextStyles.title3.copyWith(
                    fontSize: 18,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),

          // Close button — right
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                AppIcons.close,
                size: 24,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_activeCategory) {
      case AddToSetlistCategory.original:
        return OriginalSongScreen(
          key: const ValueKey('original-song'),
          defaultArtist: widget.defaultArtist,
          onSubmit: widget.onOriginalSongsSubmitted ??
              (_) async => 0, // no-op fallback
          onBack: _handleBack,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.bulk:
        return BulkEntryScreen(
          key: const ValueKey('bulk-entry'),
          onSubmit: widget.onBulkSongsSubmitted ??
              (_) async => const BulkEntryResult(
                    addedCount: 0,
                    setlistSongIds: [],
                  ),
          onBack: _handleBack,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.setBreak:
        return SetBreakScreen(
          key: const ValueKey('set-break'),
          onSubmit: widget.onSetBreakSubmitted ??
              (_, {saveAsTemplate = false}) async => false,
          onSavedSetBreakSelected: widget.onSavedSetBreakSelected,
          onDeleteTemplate: widget.onDeleteTemplate,
          savedSetBreaks: widget.savedSetBreaks,
          onBack: _handleBack,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.pause:
        return PauseScreen(
          key: const ValueKey('pause'),
          onSubmit: widget.onPauseSubmitted ?? (_) async => false,
          onSavedPauseSelected: widget.onSavedPauseSelected,
          onDeleteTemplate: widget.onDeleteTemplate,
          onBack: _handleBack,
          onClose: () => Navigator.of(context).pop(),
          savedPauses: widget.savedPauses,
        );
      default:
        return CategoryScreen(
          key: const ValueKey('category'),
          onCategorySelected: _handleCategorySelected,
          isCatalog: widget.isCatalog,
        );
    }
  }
}

// ============================================================================
// EDIT SPECIAL ITEM OVERLAY
// Opens a Set Break or Pause screen directly in edit mode, prepopulated
// with the existing item's data. Uses the same full-screen dialog chrome.
// ============================================================================

/// Show a full-screen edit overlay for an existing Set Break or Pause.
Future<void> showEditSpecialItemOverlay({
  required BuildContext context,
  required SpecialItem item,
  required OnSetBreakUpdated onSetBreakUpdated,
  required OnPauseUpdated onPauseUpdated,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _EditSpecialItemOverlay(
        item: item,
        onSetBreakUpdated: onSetBreakUpdated,
        onPauseUpdated: onPauseUpdated,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class _EditSpecialItemOverlay extends StatelessWidget {
  final SpecialItem item;
  final OnSetBreakUpdated onSetBreakUpdated;
  final OnPauseUpdated onPauseUpdated;

  const _EditSpecialItemOverlay({
    required this.item,
    required this.onSetBreakUpdated,
    required this.onPauseUpdated,
  });

  String get _title =>
      item.type == SetlistItemType.setBreak ? 'Edit Set Break' : 'Edit Pause';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(Spacing.space16),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: context.colors.border, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Column(
              children: [
                // ── Header ──
                Container(
                  height: 56,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.space16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppIcons.back,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              Text(
                                'Back',
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _title,
                            style: AppTextStyles.title3.copyWith(
                              fontSize: 18,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            AppIcons.close,
                            size: 24,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(color: context.colors.border, height: 1),

                // ── Content ──
                Expanded(
                  child: _buildContent(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (item.type == SetlistItemType.setBreak) {
      return SetBreakScreen(
        key: const ValueKey('edit-set-break'),
        editingItem: item,
        onSubmit: (_, {saveAsTemplate = false}) async => false,
        onUpdate: onSetBreakUpdated,
        onBack: () => Navigator.of(context).pop(),
        onClose: () => Navigator.of(context).pop(),
      );
    }

    return PauseScreen(
      key: const ValueKey('edit-pause'),
      editingItem: item,
      onSubmit: (_) async => false,
      onUpdate: onPauseUpdated,
      onBack: () => Navigator.of(context).pop(),
      onClose: () => Navigator.of(context).pop(),
    );
  }
}
