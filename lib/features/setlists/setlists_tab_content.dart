import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/brand_action_button.dart';
import '../../components/ui/confirm_action_dialog.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../shell/overlay_state.dart';
import 'models/setlist.dart';
import 'new_setlist_screen.dart';
import 'setlist_detail_screen.dart';
import 'setlists_screen.dart' show setlistsProvider;
import 'widgets/setlists_app_bar.dart';
import 'widgets/swipeable_setlist_card.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// SETLISTS TAB CONTENT
// Setlists content for AppShell IndexedStack. Does NOT include bottom nav.
// ============================================================================

/// Provider reference for setlists (reuse from setlists_screen.dart)
// Note: We import the provider from the main file

class SetlistsTabContent extends ConsumerStatefulWidget {
  const SetlistsTabContent({super.key});

  @override
  ConsumerState<SetlistsTabContent> createState() => _SetlistsTabContentState();
}

class _SetlistsTabContentState extends ConsumerState<SetlistsTabContent>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  List<Animation<double>> _fadeAnimations = [];
  List<Animation<Offset>> _slideAnimations = [];
  Timer? _reorderDebounceTimer;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
  }

  void _updateAnimations(int itemCount) {
    if (_fadeAnimations.length == itemCount) return;

    _fadeAnimations = List.generate(itemCount, (index) {
      final start = (index * 0.1).clamp(0.0, 0.7);
      final end = (start + 0.3).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });

    _slideAnimations = List.generate(itemCount, (index) {
      final start = (index * 0.1).clamp(0.0, 0.7);
      final end = (start + 0.3).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start, end, curve: AppCurves.slideIn),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _reorderDebounceTimer?.cancel();
    _entranceController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    ref.read(overlayStateProvider.notifier).openMenuDrawer();
  }

  void _openBandSwitcher() {
    ref.read(overlayStateProvider.notifier).openBandSwitcher();
  }

  void _navigateToCreateSetlist() {
    // Use custom fade+slide transition for smooth navigation
    Navigator.of(context).push(fadeSlideRoute(page: const NewSetlistScreen()));
  }

  void _onSetlistTap(Setlist setlist) {
    // Use custom fade+slide transition for smooth navigation
    Navigator.of(context).push(
      fadeSlideRoute(
        page: SetlistDetailScreen(
          setlistId: setlist.id,
          setlistName: setlist.name,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(Setlist setlist) async {
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: 'Delete Setlist?',
      message:
          'Are you sure you want to delete "${setlist.name}"? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true) {
      final (success, errorMessage) =
          await ref.read(setlistsProvider.notifier).deleteSetlist(setlist.id);
      if (success && mounted) {
        showAppSnackBar(context, message: '"${setlist.name}" deleted');
      } else if (!success && mounted) {
        showErrorSnackBar(
          context,
          message: errorMessage ?? 'Failed to delete setlist',
        );
      }
      return success;
    }
    return false;
  }

  Future<bool> _confirmDuplicate(Setlist setlist) async {
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: 'Duplicate Setlist?',
      message:
          'Create a copy of "${setlist.name}" with all songs and settings?',
      confirmLabel: 'Duplicate',
      confirmColor: context.colors.success,
    );

    if (confirmed == true) {
      final success = await ref
          .read(setlistsProvider.notifier)
          .duplicateSetlist(setlist.id);
      if (success && mounted) {
        showSuccessSnackBar(context, message: '"${setlist.name}" duplicated');
      } else if (!success && mounted) {
        showErrorSnackBar(context, message: 'Failed to duplicate setlist');
      }
      return success;
    }
    return false;
  }

  /// Handle setlist reorder (drag-to-reorder)
  void _handleReorder(int oldIndex, int newIndex) {
    final notifier = ref.read(setlistsProvider.notifier);

    // Apply local change immediately (optimistic UI)
    notifier.reorderLocal(oldIndex, newIndex);

    // Cancel any pending persist
    _reorderDebounceTimer?.cancel();

    // Schedule persist after debounce period
    _reorderDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      final success = await notifier.persistReorder();

      if (!success && mounted) {
        showErrorSnackBar(context, message: 'Failed to reorder setlists');
      }
    });
  }

  Widget _buildAnimatedSection(int index, Widget child) {
    if (index >= _fadeAnimations.length) {
      return child;
    }
    return SlideTransition(
      position: _slideAnimations[index],
      child: FadeTransition(opacity: _fadeAnimations[index], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandState = ref.watch(activeBandProvider);
    final displayBand = ref.watch(displayBandProvider);
    final localImageFile = ref.watch(draftLocalImageProvider);

    // RBAC: Watch permissions for setlist mutation gating
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canEdit = permissionsAsync.when(
      data: (p) => p.canEditSetlists,
      loading: () => false, // Fail closed — no mutation flicker
      error: (__, _) => false, // Fail closed on error
    );

    // Watch setlists provider
    final setlistsState = ref.watch(setlistsProvider);

    // Create a placeholder Catalog for new bands
    final placeholderCatalog = Setlist(
      id: 'placeholder-catalog',
      name: kCatalogSetlistName,
      songCount: 0,
      totalDuration: Duration.zero,
      bandId: bandState.activeBand?.id,
      isCatalog: true,
    );

    // Ensure Catalog always exists in the list for display purposes
    // If the database fetch returned empty OR errored, show a placeholder Catalog
    final List<Setlist> setlistsToShow;
    if (setlistsState.setlists.isNotEmpty) {
      // Has setlists from DB - use them
      setlistsToShow = setlistsState.setlists;
    } else if (!setlistsState.isLoading) {
      // Empty or error - show placeholder Catalog so user always sees something
      setlistsToShow = [placeholderCatalog];
    } else {
      setlistsToShow = [];
    }

    // Update animations when setlists change
    if (!setlistsState.isLoading && setlistsToShow.isNotEmpty) {
      final itemCount = setlistsToShow.length + 1;
      _updateAnimations(itemCount);
    }

    final bandName = displayBand?.name ?? bandState.activeBand?.name ?? 'Band';
    final bandAvatarColor =
        displayBand?.avatarColor ?? bandState.activeBand?.avatarColor;
    final bandImageUrl =
        displayBand?.imageUrl ?? bandState.activeBand?.imageUrl;

    final showLoading = setlistsState.isLoading;
    // Don't show error if we have a placeholder Catalog to show
    final showError = setlistsState.error != null && setlistsToShow.isEmpty;

    // Main content WITHOUT bottom nav
    // Wrap content with scroll notification for glass effect
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          ref
              .read(scrollBlurProvider.notifier)
              .updateFromOffset(notification.metrics.pixels);
        }
        return false; // Allow notification to continue bubbling
      },
      child: Container(
        color: context.colors.background,
        child: showLoading
            ? _buildLoadingState(
                bandName,
                bandAvatarColor,
                bandImageUrl,
                localImageFile,
              )
            : showError
                ? _buildErrorState(
                    bandName,
                    bandAvatarColor,
                    bandImageUrl,
                    localImageFile,
                    setlistsState.error!,
                  )
                : _buildContentState(
                    bandName,
                    bandAvatarColor,
                    bandImageUrl,
                    localImageFile,
                    setlistsToShow,
                    canEdit,
                  ),
      ),
    );
  }

  Widget _buildLoadingState(
    String bandName,
    String? avatarColor,
    String? imageUrl,
    dynamic localImage,
  ) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.colors.primarySubtle,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.space24),
              Text(
                'Setting up the stage...',
                style: AppTextStyles.body.copyWith(color: context.colors.textMuted),
              ),
            ],
          ),
        ),
        _buildAppBar(bandName, avatarColor, imageUrl, localImage),
      ],
    );
  }

  Widget _buildErrorState(
    String bandName,
    String? avatarColor,
    String? imageUrl,
    dynamic localImage,
    String error,
  ) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.space32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: context.colors.primarySubtle,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    AppIcons.musicOff,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: Spacing.space32),
                Text(
                  'Couldn\'t load setlists',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayMedium,
                ),
                const SizedBox(height: Spacing.space12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
                const SizedBox(height: Spacing.space40),
                BrandActionButton(
                  label: 'Try Again',
                  icon: AppIcons.refresh,
                  onPressed: () =>
                      ref.read(setlistsProvider.notifier).refresh(),
                ),
              ],
            ),
          ),
        ),
        _buildAppBar(bandName, avatarColor, imageUrl, localImage),
      ],
    );
  }

  Widget _buildContentState(
    String bandName,
    String? avatarColor,
    String? imageUrl,
    dynamic localImage,
    List<Setlist> setlists,
    bool canEdit,
  ) {
    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            await ref.read(setlistsProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      Spacing.appBarHeight + MediaQuery.of(context).padding.top,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: Spacing.space24),
                      _buildAnimatedSection(
                        0,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Setlists',
                              style: AppTextStyles.pageTitle.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            if (canEdit)
                              TextButton.icon(
                                onPressed: _navigateToCreateSetlist,
                                icon: const Icon(AppIcons.add, size: 18),
                                label: const Text('New'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Spacing.space16),
                    ],
                  ),
                ),
              ),
              // Catalog setlists (non-reorderable)
              ...setlists.where((s) => s.isCatalog).map((setlist) {
                final idx = setlists.indexOf(setlist);
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.space12),
                      child: _buildAnimatedSection(
                        idx + 1,
                        SwipeableSetlistCard(
                          setlist: setlist,
                          onTap: () => _onSetlistTap(setlist),
                          onDeleteConfirmed:
                              canEdit ? (s) => _confirmDelete(s) : null,
                          onDuplicateConfirmed:
                              canEdit ? (s) => _confirmDuplicate(s) : null,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Setlist cards: reorderable when canEdit, static list otherwise
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                sliver: canEdit
                    ? SliverReorderableList(
                        itemCount: setlists.where((s) => !s.isCatalog).length,
                        onReorder: _handleReorder,
                        itemBuilder: (context, index) {
                          final reorderableSetlists =
                              setlists.where((s) => !s.isCatalog).toList();
                          final setlist = reorderableSetlists[index];
                          return Padding(
                            key: ValueKey(setlist.id),
                            padding:
                                const EdgeInsets.only(bottom: Spacing.space12),
                            child: SwipeableSetlistCard(
                              setlist: setlist,
                              index: index,
                              isDraggable: true,
                              onTap: () => _onSetlistTap(setlist),
                              onDeleteConfirmed: (s) => _confirmDelete(s),
                              onDuplicateConfirmed: (s) => _confirmDuplicate(s),
                            ),
                          );
                        },
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              final scale = Tween<double>(
                                begin: 1.0,
                                end: 1.02,
                              ).evaluate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                ),
                              );
                              return Transform.scale(
                                scale: scale,
                                child: Material(
                                  color: Colors.transparent,
                                  elevation: 8,
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(
                                    Spacing.buttonRadius,
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: child,
                          );
                        },
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final readOnlySetlists =
                                setlists.where((s) => !s.isCatalog).toList();
                            final setlist = readOnlySetlists[index];
                            return Padding(
                              key: ValueKey(setlist.id),
                              padding: const EdgeInsets.only(
                                  bottom: Spacing.space12),
                              child: SwipeableSetlistCard(
                                setlist: setlist,
                                onTap: () => _onSetlistTap(setlist),
                                onDeleteConfirmed: null,
                                onDuplicateConfirmed: null,
                              ),
                            );
                          },
                          childCount:
                              setlists.where((s) => !s.isCatalog).length,
                        ),
                      ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: Spacing.space32 +
                      Spacing.bottomNavHeight +
                      MediaQuery.of(context).padding.bottom,
                ),
              ),
            ],
          ),
        ),
        _buildAppBar(bandName, avatarColor, imageUrl, localImage),
      ],
    );
  }

  Widget _buildAppBar(
    String bandName,
    String? avatarColor,
    String? imageUrl,
    dynamic localImage,
  ) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SetlistsAppBar(
        bandName: bandName,
        bandAvatarColor: avatarColor,
        bandImageUrl: imageUrl,
        localImageFile: localImage,
        onMenuTap: _openDrawer,
        onAvatarTap: _openBandSwitcher,
        // Tab content shows full app bar with menu + title + avatar
        backOnly: false,
      ),
    );
  }
}
