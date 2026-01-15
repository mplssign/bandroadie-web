import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../tips/tips_and_tricks_screen.dart';
import '../../components/ui/confirm_action_dialog.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../bands/edit_band_screen.dart';
import '../feedback/bug_report_screen.dart';
import '../gigs/gig_controller.dart';
import '../home/home_screen.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../profile/my_profile_screen.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../settings/settings_screen.dart';
import '../../app/constants/app_constants.dart';
import 'new_setlist_screen.dart';
import 'models/setlist.dart';
import 'setlist_detail_screen.dart';
import 'setlist_repository.dart';
import 'widgets/empty_setlists_state.dart';
import 'widgets/setlists_app_bar.dart';
import 'widgets/setlists_bottom_nav_bar.dart';
import 'widgets/swipeable_setlist_card.dart';

// ============================================================================
// SETLISTS SCREEN
// Displays all setlists for the active band.
// Figma: "Setlists" artboard - cards with blue borders, rose FAB
//
// STATES:
// 1. Loading - fetching setlists
// 2. Empty - no setlists, show empty state with CTA
// 3. Content - list of setlist cards
// ============================================================================

// =============================================================================
// STATE & PROVIDER
// =============================================================================

/// State for setlists list
class SetlistsState {
  final List<Setlist> setlists;
  final bool isLoading;
  final String? error;

  const SetlistsState({
    this.setlists = const [],
    this.isLoading = false,
    this.error,
  });

  SetlistsState copyWith({
    List<Setlist>? setlists,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return SetlistsState(
      setlists: setlists ?? this.setlists,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for setlists
class SetlistsNotifier extends Notifier<SetlistsState> {
  /// Track the last band ID we loaded for to prevent duplicate loads
  String? _lastLoadedBandId;

  /// Cache the last successfully loaded state
  SetlistsState? _cachedState;

  @override
  SetlistsState build() {
    // Watch the active band - when it changes, refetch setlists
    final bandId = ref.watch(activeBandIdProvider);

    if (bandId == null || bandId.isEmpty) {
      _lastLoadedBandId = null;
      _cachedState = null;
      return const SetlistsState(error: 'No band selected');
    }

    // Only trigger load if band actually changed
    if (bandId != _lastLoadedBandId) {
      _lastLoadedBandId = bandId;
      _cachedState = null;
      Future.microtask(() => loadSetlists());
      return const SetlistsState(isLoading: true);
    }

    // Band hasn't changed - return cached state if available
    // This handles provider invalidation without triggering a reload
    if (_cachedState != null) {
      return _cachedState!;
    }

    // Fallback: trigger a load (shouldn't normally reach here)
    Future.microtask(() => loadSetlists());
    return const SetlistsState(isLoading: true);
  }

  SetlistRepository get _repository => ref.read(setlistRepositoryProvider);
  String? get _bandId => ref.read(activeBandIdProvider);

  Future<void> loadSetlists() async {
    final bandId = _bandId;
    if (bandId == null || bandId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final setlists = await _repository.fetchSetlistsForBand(bandId);

      // Debug: Check if Catalog is in the response
      if (kDebugMode) {
        debugPrint(
          '[SetlistsNotifier] Loaded ${setlists.length} setlists from repository',
        );
        final hasCatalogInResponse = setlists.any(
          (s) => s.isCatalog || isCatalogName(s.name),
        );
        debugPrint(
          '[SetlistsNotifier] Catalog in response: $hasCatalogInResponse',
        );
        for (final s in setlists) {
          debugPrint(
            '[SetlistsNotifier]   - "${s.name}" isCatalog=${s.isCatalog}',
          );
        }
      }

      final newState = state.copyWith(setlists: setlists, isLoading: false);
      state = newState;
      _cachedState = newState; // Cache for rebuild resilience
    } on SetlistQueryError catch (e) {
      final newState = state.copyWith(isLoading: false, error: e.userMessage);
      state = newState;
      _cachedState = newState;
    } on NoBandSelectedError {
      final newState = state.copyWith(
        isLoading: false,
        error: 'No band selected',
      );
      state = newState;
      _cachedState = newState;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistsNotifier] Error loading setlists: $e');
      }
      final newState = state.copyWith(
        isLoading: false,
        error: 'Failed to load setlists. Please try again.',
      );
      state = newState;
      _cachedState = newState;
    }
  }

  Future<void> refresh() => loadSetlists();

  /// Deletes a setlist and removes it from the local state.
  /// Returns a tuple: (success, errorMessage).
  /// If success is true, errorMessage will be null.
  Future<(bool, String?)> deleteSetlist(String setlistId) async {
    final bandId = _bandId;
    if (bandId == null || bandId.isEmpty) {
      return (false, 'No band selected');
    }

    try {
      await _repository.deleteSetlist(bandId: bandId, setlistId: setlistId);

      // Remove from local state
      final updatedSetlists = state.setlists
          .where((s) => s.id != setlistId)
          .toList();
      state = state.copyWith(setlists: updatedSetlists);

      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Deleted setlist $setlistId');
      }
      return (true, null);
    } on SetlistQueryError catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Delete error: ${e.message}');
      }
      // Return user-friendly error message
      final userMessage = switch (e.reason) {
        'catalog_protected' => 'Cannot delete the Catalog setlist',
        'permission_denied' =>
          'You do not have permission to delete this setlist',
        'not_found' => 'Setlist not found',
        _ => e.userMessage,
      };
      return (false, userMessage);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Unexpected delete error: $e');
      }
      return (false, 'Failed to delete setlist. Please try again.');
    }
  }

  /// Duplicates a setlist and adds it to the local state.
  /// Returns true if successful, false otherwise.
  Future<bool> duplicateSetlist(String setlistId) async {
    final bandId = _bandId;
    if (bandId == null || bandId.isEmpty) return false;

    try {
      await _repository.duplicateSetlist(bandId: bandId, setlistId: setlistId);

      // Refresh the list to show the new setlist
      await loadSetlists();

      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Duplicated setlist $setlistId');
      }
      return true;
    } on SetlistQueryError catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Duplicate error: ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistsScreen] Unexpected duplicate error: $e');
      }
      return false;
    }
  }
}

/// Provider for setlists
final setlistsProvider = NotifierProvider<SetlistsNotifier, SetlistsState>(
  SetlistsNotifier.new,
);

class SetlistsScreen extends ConsumerStatefulWidget {
  const SetlistsScreen({super.key});

  @override
  ConsumerState<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends ConsumerState<SetlistsScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  List<Animation<double>> _fadeAnimations = [];
  List<Animation<Offset>> _slideAnimations = [];

  // Drawer state
  bool _isDrawerOpen = false;
  bool _isBandSwitcherOpen = false;

  // User profile data
  String? _userFirstName;
  String? _userLastName;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Load user profile data
    _loadUserProfile();
  }

  /// Update animations when setlist count changes
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

    // Start animation after items are built
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  Future<void> _loadUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('users')
          .select('first_name, last_name')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _userFirstName = response['first_name'] as String?;
          _userLastName = response['last_name'] as String?;
        });
      }
    } catch (e) {
      debugPrint('[SetlistsScreen] Failed to load user profile: $e');
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    setState(() => _isDrawerOpen = true);
  }

  void _closeDrawer() {
    setState(() => _isDrawerOpen = false);
  }

  void _openBandSwitcher() {
    setState(() => _isBandSwitcherOpen = true);
  }

  void _closeBandSwitcher() {
    setState(() => _isBandSwitcherOpen = false);
  }

  void _handleBandSelected(Band band) {
    _closeBandSwitcher();
    debugPrint('[Dashboard] activeBand changed: ${band.id}');
    ref.read(gigProvider.notifier).resetForBandChange();
    ref.read(rehearsalProvider.notifier).resetForBandChange();
    ref.read(activeBandProvider.notifier).selectBand(band);
  }

  Future<void> _signOut() async {
    await ref.read(activeBandProvider.notifier).reset();
    await supabase.auth.signOut();
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: AppDurations.fast,
      ),
    );
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

  /// Shows confirmation dialog for deleting a setlist.
  /// Returns true if user confirms and deletion succeeds.
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
      final (success, errorMessage) = await ref
          .read(setlistsProvider.notifier)
          .deleteSetlist(setlist.id);
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

  /// Shows confirmation dialog for duplicating a setlist.
  /// Returns true if user confirms and duplication succeeds.
  Future<bool> _confirmDuplicate(Setlist setlist) async {
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: 'Duplicate Setlist?',
      message:
          'Create a copy of "${setlist.name}" with all songs and settings?',
      confirmLabel: 'Duplicate',
      confirmColor: AppColors.success,
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

  /// Shows a dialog to rename a setlist.
  Future<void> _showRenameDialog(Setlist setlist) async {
    final controller = TextEditingController(text: setlist.name);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text(
          'Rename Setlist',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Setlist Name',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.textSecondary),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name cannot be empty';
              }
              return null;
            },
            onFieldSubmitted: (value) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName != setlist.name && mounted) {
      try {
        final bandId = ref.read(activeBandIdProvider);
        if (bandId == null) return;

        await ref
            .read(setlistRepositoryProvider)
            .renameSetlist(
              bandId: bandId,
              setlistId: setlist.id,
              newName: newName,
            );

        // Refresh the list
        await ref.read(setlistsProvider.notifier).refresh();

        if (mounted) {
          showAppSnackBar(context, message: 'Renamed to "$newName"');
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, message: 'Failed to rename setlist');
        }
      }
    }
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

    // Watch setlists provider (automatically reloads when band changes)
    final setlistsState = ref.watch(setlistsProvider);

    final bandName = displayBand?.name ?? bandState.activeBand?.name ?? 'Band';
    final bandAvatarColor =
        displayBand?.avatarColor ?? bandState.activeBand?.avatarColor;
    final bandImageUrl =
        displayBand?.imageUrl ?? bandState.activeBand?.imageUrl;

    // Get current user info for drawer
    final currentUser = supabase.auth.currentUser;
    String userName;
    if (_userFirstName != null || _userLastName != null) {
      userName = '${_userFirstName ?? ''} ${_userLastName ?? ''}'.trim();
      if (userName.isEmpty) userName = 'User';
    } else {
      userName =
          currentUser?.userMetadata?['full_name'] as String? ??
          currentUser?.userMetadata?['name'] as String? ??
          'User';
    }
    final userEmail = currentUser?.email ?? '';

    // Ensure Catalog always exists in the list for display purposes
    // Create a placeholder Catalog to use if none exists in the response
    final placeholderCatalog = Setlist(
      id: 'placeholder-catalog',
      name: kCatalogSetlistName,
      songCount: 0,
      totalDuration: Duration.zero,
      bandId: bandState.activeBand?.id,
      isCatalog: true,
    );

    // If setlists exist but no Catalog is in the list, add the placeholder
    final List<Setlist> setlistsToShow;
    if (setlistsState.setlists.isNotEmpty) {
      final hasCatalog = setlistsState.setlists.any(
        (s) => s.isCatalog || isCatalogName(s.name),
      );
      if (kDebugMode) {
        debugPrint(
          '[SetlistsScreen] setlists count: ${setlistsState.setlists.length}',
        );
        debugPrint('[SetlistsScreen] hasCatalog: $hasCatalog');
        for (final s in setlistsState.setlists) {
          debugPrint(
            '[SetlistsScreen]   - "${s.name}" isCatalog: ${s.isCatalog}, isCatalogName: ${isCatalogName(s.name)}',
          );
        }
      }
      if (hasCatalog) {
        setlistsToShow = setlistsState.setlists;
      } else {
        // Catalog missing from response - add placeholder at the beginning
        setlistsToShow = [placeholderCatalog, ...setlistsState.setlists];
      }
    } else if (!setlistsState.isLoading) {
      // Empty or error - show placeholder Catalog so user always sees something
      setlistsToShow = [placeholderCatalog];
    } else {
      setlistsToShow = [];
    }

    // Update animations when setlists change
    if (!setlistsState.isLoading && setlistsToShow.isNotEmpty) {
      final itemCount = setlistsToShow.length + 1; // +1 for header
      _updateAnimations(itemCount);
    }

    // Determine what to show
    final showLoading = setlistsState.isLoading;
    final showError = setlistsState.error != null && setlistsToShow.isEmpty;
    final showEmpty = !showLoading && !showError && setlistsToShow.isEmpty;

    // Main content
    final content = Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: showLoading
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
          : showEmpty
          ? _buildEmptyState(
              bandName,
              bandAvatarColor,
              bandImageUrl,
              localImageFile,
            )
          : _buildContentState(
              bandName,
              bandAvatarColor,
              bandImageUrl,
              localImageFile,
              setlistsToShow,
            ),
      bottomNavigationBar: SetlistsBottomNavBar(
        onDashboardTap: _navigateToDashboard,
        // Use default navigation for Calendar and Members
        onCalendarTap: null,
        onMembersTap: null,
      ),
    );

    // Wrap with DrawerOverlay and BandSwitcherOverlay
    return DrawerOverlay(
      isOpen: _isDrawerOpen,
      onClose: _closeDrawer,
      userName: userName,
      userEmail: userEmail,
      onProfileTap: () {
        // Use custom fade+slide transition for smooth navigation
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const MyProfileScreen()));
      },
      onSettingsTap: () {
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const SettingsScreen()));
      },
      onTipsAndTricksTap: () {
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const TipsAndTricksScreen()));
      },
      onReportBugsTap: () {
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const BugReportScreen()));
      },
      onLogOutTap: _signOut,
      child: BandSwitcherOverlay(
        isOpen: _isBandSwitcherOpen,
        onClose: _closeBandSwitcher,
        bands: bandState.userBands,
        activeBandId: bandState.activeBand?.id,
        onBandSelected: _handleBandSelected,
        onCreateBand: () {
          _closeBandSwitcher();
          // Use custom fade+slide transition for smooth navigation
          Navigator.of(
            context,
          ).push(fadeSlideRoute(page: const CreateBandScreen()));
        },
        onEditBand: () {
          final activeBand = bandState.activeBand;
          if (activeBand != null) {
            _closeBandSwitcher();
            Navigator.of(
              context,
            ).push(fadeSlideRoute(page: EditBandScreen(band: activeBand)));
          }
        },
        child: content,
      ),
    );
  }

  Widget _buildEmptyState(
    String bandName,
    String? bandAvatarColor,
    String? bandImageUrl,
    File? localImageFile,
  ) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: SetlistsAppBar(
            bandName: bandName,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
            bandAvatarColor: bandAvatarColor,
            bandImageUrl: bandImageUrl,
            localImageFile: localImageFile,
            backOnly: true,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptySetlistsState(onCreateSetlist: _navigateToCreateSetlist),
        ),
      ],
    );
  }

  Widget _buildLoadingState(
    String bandName,
    String? bandAvatarColor,
    String? bandImageUrl,
    File? localImageFile,
  ) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SetlistsAppBar(
            bandName: bandName,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
            bandAvatarColor: bandAvatarColor,
            bandImageUrl: bandImageUrl,
            localImageFile: localImageFile,
            backOnly: true,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(
    String bandName,
    String? bandAvatarColor,
    String? bandImageUrl,
    File? localImageFile,
    String error,
  ) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SetlistsAppBar(
            bandName: bandName,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
            bandAvatarColor: bandAvatarColor,
            bandImageUrl: bandImageUrl,
            localImageFile: localImageFile,
            backOnly: true,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: Spacing.space16),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: Spacing.space24),
                  FilledButton(
                    onPressed: () {
                      ref.read(setlistsProvider.notifier).refresh();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentState(
    String bandName,
    String? bandAvatarColor,
    String? bandImageUrl,
    File? localImageFile,
    List<Setlist> setlists,
  ) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // App bar
        SliverToBoxAdapter(
          child: SetlistsAppBar(
            bandName: bandName,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
            bandAvatarColor: bandAvatarColor,
            bandImageUrl: bandImageUrl,
            localImageFile: localImageFile,
            backOnly: true,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),

        // Content
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.space24),

                // Section title with + New button
                _buildAnimatedSection(
                  0,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Setlists',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _navigateToCreateSetlist,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Spacing.space12),

                // Setlist cards with staggered animation
                ...List.generate(setlists.length, (index) {
                  final setlist = setlists[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < setlists.length - 1 ? Spacing.space12 : 0,
                    ),
                    child: _buildAnimatedSection(
                      index + 1,
                      SwipeableSetlistCard(
                        setlist: setlist,
                        onTap: () => _onSetlistTap(setlist),
                        onEditName: setlist.isCatalog
                            ? null
                            : () => _showRenameDialog(setlist),
                        onDeleteConfirmed: _confirmDelete,
                        onDuplicateConfirmed: _confirmDuplicate,
                      ),
                    ),
                  );
                }),

                // Bottom padding
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
