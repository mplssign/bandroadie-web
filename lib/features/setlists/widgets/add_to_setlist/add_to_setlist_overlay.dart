import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../models/setlist_item_type.dart';
import '../../models/special_item.dart';
import '../../setlist_repository.dart';
import 'category_screen.dart';
import 'cover_song_screen.dart';
import 'original_song_screen.dart';
import 'bulk_entry_screen.dart';
import 'set_break_screen.dart';
import 'pause_screen.dart';

// ============================================================================
// ADD TO SETLIST OVERLAY
// Full-screen overlay with animated transitions and structured category
// selection. Single entry point for adding songs to a setlist.
//
// FLOW:
// 1. Category selection (Cover / Original / Bulk)
// 2. Detail screen for chosen category
// 3. Add → close with slide-down
//
// REUSES: Existing services, repositories, and business logic.
// ============================================================================

/// The add modes available
enum AddToSetlistCategory { cover, original, bulk, setBreak, pause }

/// Shows the unified "Add to Setlist" overlay.
///
/// [bandId] - The active band
/// [setlistId] - Target setlist
/// [bandName] - Active band name (for original song auto-fill)
/// [onSongAdded] - Callback when a single song is added (cover/original)
/// [onBulkComplete] - Callback when bulk songs are added
Future<void> showAddToSetlistOverlay({
  required BuildContext context,
  required String bandId,
  required String setlistId,
  required String bandName,
  bool isCatalog = false,
  required Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded,
  required void Function(int addedCount, List<String> setlistSongIds)
  onBulkComplete,
  required Future<bool> Function({
    required SetlistItemType type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool saveAsTemplate,
  })
  onAddSpecialItem,
  required Future<bool> Function(SpecialItem template) onAddExistingTemplate,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) {
      return AddToSetlistOverlay(
        bandId: bandId,
        setlistId: setlistId,
        bandName: bandName,
        isCatalog: isCatalog,
        onSongAdded: onSongAdded,
        onBulkComplete: onBulkComplete,
        onAddSpecialItem: onAddSpecialItem,
        onAddExistingTemplate: onAddExistingTemplate,
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
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class AddToSetlistOverlay extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final String bandName;
  final bool isCatalog;
  final Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded;
  final void Function(int addedCount, List<String> setlistSongIds)
  onBulkComplete;
  final Future<bool> Function({
    required SetlistItemType type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool saveAsTemplate,
  })
  onAddSpecialItem;
  final Future<bool> Function(SpecialItem template) onAddExistingTemplate;

  const AddToSetlistOverlay({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.bandName,
    this.isCatalog = false,
    required this.onSongAdded,
    required this.onBulkComplete,
    required this.onAddSpecialItem,
    required this.onAddExistingTemplate,
  });

  @override
  ConsumerState<AddToSetlistOverlay> createState() =>
      _AddToSetlistOverlayState();
}

class _AddToSetlistOverlayState extends ConsumerState<AddToSetlistOverlay>
    with TickerProviderStateMixin {
  AddToSetlistCategory? _selectedCategory;

  // Navigation animation controller
  late AnimationController _navController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isAnimatingForward = true;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _navController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _navController.dispose();
    super.dispose();
  }

  /// Navigate to a detail screen with slide animation
  void _navigateToCategory(AddToSetlistCategory category) {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _isAnimatingForward = true;
      _selectedCategory = category;
    });

    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: _navController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _navController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _navController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
      }
    });
  }

  /// Navigate back to category screen with slide animation
  void _navigateBack() {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _isAnimatingForward = false;
    });

    _slideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(1.0, 0)).animate(
          CurvedAnimation(parent: _navController, curve: Curves.easeInCubic),
        );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _navController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _navController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _selectedCategory = null;
          _isTransitioning = false;
        });
        _navController.reset();
      }
    });
  }

  // ── Special item handlers ─────────────────────────────────────────────

  Future<void> _handleSetBreakResult(SetBreakScreenResult result) async {
    if (result.isTemplate) {
      final success = await widget.onAddExistingTemplate(result.template!);
      if (mounted && success) Navigator.of(context).pop();
    } else {
      final success = await widget.onAddSpecialItem(
        type: SetlistItemType.setBreak,
        durationMinutes: result.durationMinutes,
        saveAsTemplate: result.saveAsTemplate ?? false,
      );
      if (mounted && success) Navigator.of(context).pop();
    }
  }

  Future<void> _handlePauseResult(PauseScreenResult result) async {
    if (result.isTemplate) {
      final success = await widget.onAddExistingTemplate(result.template!);
      if (mounted && success) Navigator.of(context).pop();
    } else {
      final success = await widget.onAddSpecialItem(
        type: SetlistItemType.pause,
        purposes: result.purposes,
        customPurposes: result.customPurposes,
        durationSeconds: result.durationSeconds,
        saveAsTemplate: result.saveAsTemplate ?? false,
      );
      if (mounted && success) Navigator.of(context).pop();
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
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: AppColors.borderMuted, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Column(
              children: [
                _buildHeader(),
                const Divider(color: AppColors.borderMuted, height: 1),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final showBack = _selectedCategory != null && !_isTransitioning;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      child: Row(
        children: [
          // Back to options (hidden on category screen)
          AnimatedOpacity(
            opacity: showBack ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: showBack ? _navigateBack : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // Title
          Text(
            'Add to Setlist',
            style: AppTextStyles.title3.copyWith(fontSize: 18),
          ),

          const Spacer(),

          // Close (X) button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.close_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Currently on category screen
    if (_selectedCategory == null && !_isTransitioning) {
      return CategoryScreen(
        onCategorySelected: _navigateToCategory,
        isCatalog: widget.isCatalog,
      );
    }

    // Animating backward — show detail sliding out, category underneath
    if (_isTransitioning && !_isAnimatingForward) {
      return Stack(
        children: [
          // Category screen underneath (visible as detail slides away)
          CategoryScreen(
            onCategorySelected: _navigateToCategory,
            isCatalog: widget.isCatalog,
          ),
          // Detail screen sliding out
          AnimatedBuilder(
            animation: _navController,
            builder: (context, child) {
              return SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    color: AppColors.scaffoldBg,
                    child: _buildDetailScreen(),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    // Animating forward — show category underneath, detail sliding in
    if (_isTransitioning && _isAnimatingForward) {
      return Stack(
        children: [
          // Category screen underneath
          CategoryScreen(
            onCategorySelected: _navigateToCategory,
            isCatalog: widget.isCatalog,
          ),
          // Detail screen sliding in
          AnimatedBuilder(
            animation: _navController,
            builder: (context, child) {
              return SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    color: AppColors.scaffoldBg,
                    child: _buildDetailScreen(),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    // Static detail screen (after forward animation completes)
    return _buildDetailScreen();
  }

  Widget _buildDetailScreen() {
    switch (_selectedCategory) {
      case AddToSetlistCategory.cover:
        return CoverSongScreen(
          bandId: widget.bandId,
          setlistId: widget.setlistId,
          onSongAdded: widget.onSongAdded,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.original:
        return OriginalSongScreen(
          bandId: widget.bandId,
          setlistId: widget.setlistId,
          bandName: widget.bandName,
          onSongAdded: widget.onSongAdded,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.bulk:
        return BulkEntryScreen(
          bandId: widget.bandId,
          setlistId: widget.setlistId,
          onComplete: widget.onBulkComplete,
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.setBreak:
        return SetBreakScreen(
          bandId: widget.bandId,
          onAdd: (result) => _handleSetBreakResult(result),
          onClose: () => Navigator.of(context).pop(),
        );
      case AddToSetlistCategory.pause:
        return PauseScreen(
          bandId: widget.bandId,
          onAdd: (result) => _handlePauseResult(result),
          onClose: () => Navigator.of(context).pop(),
        );
      case null:
        return const SizedBox.shrink();
    }
  }
}
