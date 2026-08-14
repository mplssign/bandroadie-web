import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/app_button.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../auth/splash_complete_provider.dart';
import '../bands/active_band_controller.dart';
import '../bands/band_full_state.dart';
import '../calendar/calendar_controller.dart';

import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../gigs/gig_controller.dart';
import '../gigs/gig_response_repository.dart';
import '../gigs/widgets/view_gig_drawer.dart';
import '../gigs/potential_gig_prompt_service.dart';
import '../members/members_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../rehearsals/rehearsal_response_repository.dart';
import '../rehearsals/potential_rehearsal_prompt_service.dart';
import '../rehearsals/rehearsal_pagination_controller.dart';
import '../rehearsals/rehearsal_display_helper.dart';
import '../rehearsals/widgets/view_rehearsal_drawer.dart';
import '../financials/financials_screen.dart';
import '../setlists/new_setlist_screen.dart';
import '../setlists/setlists_screen.dart' show SetlistsState, setlistsProvider;
import '../shell/overlay_state.dart';
import 'widgets/confirmed_gig_card.dart';
import 'widgets/empty_home_state.dart';
import 'widgets/empty_section_card.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/no_band_state.dart';
import 'widgets/potential_gig_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/rehearsal_card.dart';
import 'widgets/section_header.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// HOME TAB CONTENT
// Dashboard content for AppShell IndexedStack. Does NOT include bottom nav.
// ============================================================================

class HomeTabContent extends ConsumerStatefulWidget {
  const HomeTabContent({super.key});

  @override
  ConsumerState<HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends ConsumerState<HomeTabContent>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // NOTE: Response summaries are now managed by potentialGigResponseSummariesProvider
  // for proper synchronization with the Edit Gig drawer. See gig_response_repository.dart.

  /// Subscription for band ID changes - must be stored to prevent memory leaks
  ProviderSubscription<String?>? _bandIdSubscription;

  /// ScrollController for rehearsals horizontal list (enables infinite scroll)
  late ScrollController _rehearsalScrollController;

  @override
  void initState() {
    super.initState();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize rehearsal scroll controller
    _rehearsalScrollController = ScrollController();

    // Add scroll listener for infinite scroll on rehearsals list
    _rehearsalScrollController.addListener(_onRehearsalScroll);

    // Entrance animation controller
    _entranceController = AnimationController(
      duration: AppDurations.entrance,
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppCurves.ease,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppCurves.slideIn,
      ),
    );

    // Start entrance animation after splash completes
    // Check immediately in case splash already completed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartAnimation();
    });

    // Note: We no longer call loadUserBands() here because AuthGate
    // already loads bands before mounting AppShell/HomeTabContent.

    // Listen for when the band becomes available and check pending prompts
    // This is more reliable than addPostFrameCallback since band loads async
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForBandAndCheckPrompts();
    });
  }

  /// Check if splash is complete and start entrance animation
  void _checkAndStartAnimation() {
    if (!mounted) return;
    final splashComplete = ref.read(splashCompleteProvider);
    if (splashComplete) {
      debugPrint(
          '[HomeTabContent] Splash complete, starting entrance animation');
      _entranceController.forward();
    } else {
      // Listen for splash completion
      debugPrint('[HomeTabContent] Waiting for splash to complete...');
      ref.listenManual<bool>(
        splashCompleteProvider,
        (previous, next) {
          if (next == true && mounted) {
            debugPrint(
                '[HomeTabContent] Splash completed, starting entrance animation');
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) _entranceController.forward();
            });
          }
        },
      );
    }
  }

  /// Track if we've already checked for this band to avoid duplicate checks
  String? _lastCheckedBandId;

  /// Whether the band listener has been set up
  bool _listenerSetUp = false;

  /// Throttle for app resume to prevent rapid re-checks
  DateTime? _lastResumeCheck;

  /// Listen for band to become available, then check pending gig prompts
  void _listenForBandAndCheckPrompts() {
    // Only set up the listener once to prevent memory leaks
    if (_listenerSetUp) return;
    _listenerSetUp = true;

    // Store the subscription so it can be closed on dispose
    _bandIdSubscription = ref.listenManual(activeBandIdProvider, (
      previous,
      next,
    ) {
      if (next != null && next != _lastCheckedBandId) {
        debugPrint(
          '[HomeTabContent] Band became available: $next, checking prompts',
        );
        _lastCheckedBandId = next;

        // Reset pagination state when band changes
        ref.read(rehearsalPaginationProvider.notifier).reset();

        _checkPendingGigPrompts();
        _checkPendingRehearsalPrompts();
      }
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // When app resumes from background, check for pending potential gig prompts
    // Throttle to prevent rapid re-checks (e.g., during magic link auth on iOS)
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeCheck != null &&
          now.difference(_lastResumeCheck!).inSeconds < 5) {
        debugPrint('[HomeTabContent] App resumed, but throttled (within 5s)');
        return;
      }
      _lastResumeCheck = now;
      debugPrint('[HomeTabContent] App resumed, checking pending gig prompts');
      // Reset the check so we re-check on resume
      _lastCheckedBandId = null;
      _checkPendingGigPrompts();
      _checkPendingRehearsalPrompts();
    }
  }

  /// Check for pending potential gigs and show prompt modals.
  /// Shows every time the app opens until the user responds to each pending gig.
  /// Once a user responds, that gig is filtered out by fetchPendingPotentialGigs().
  void _checkPendingGigPrompts() {
    debugPrint('[HomeTabContent] _checkPendingGigPrompts called');

    if (!mounted) {
      debugPrint('[HomeTabContent] Not mounted, returning');
      return;
    }

    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) {
      debugPrint('[HomeTabContent] No band selected, returning');
      return;
    }

    debugPrint(
      '[HomeTabContent] Checking pending gig prompts for band $bandId',
    );

    // Delay slightly to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      ref.read(potentialGigPromptProvider.notifier).checkAndShowPendingPrompts(
        context,
        onResponseSubmitted: () {
          // Refresh gig data after user responds.
          // Response summaries auto-refresh via potentialGigResponseSummariesProvider
          // which watches gigProvider - no manual invalidation needed here.
          ref.read(gigProvider.notifier).refresh();
          ref.invalidate(potentialGigResponseSummariesProvider);
        },
      );
    });

    // NOTE: Response summaries now load automatically via potentialGigResponseSummariesProvider
    // which watches gigProvider and activeBandIdProvider. No manual load needed.
  }

  /// Check for pending potential rehearsals and show prompt modals.
  /// Shows every time the app opens until the user responds to each pending rehearsal.
  /// Once a user responds, that rehearsal is filtered out by fetchPendingPotentialRehearsals().
  void _checkPendingRehearsalPrompts() {
    debugPrint('[HomeTabContent] _checkPendingRehearsalPrompts called');

    if (!mounted) {
      debugPrint('[HomeTabContent] Not mounted, returning');
      return;
    }

    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) {
      debugPrint('[HomeTabContent] No band selected, returning');
      return;
    }

    debugPrint(
      '[HomeTabContent] Checking pending rehearsal prompts for band $bandId',
    );

    // Delay slightly to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      ref
          .read(potentialRehearsalPromptProvider.notifier)
          .checkAndShowPendingPrompts(
        context,
        onResponseSubmitted: () {
          // Refresh rehearsal data after user responds.
          // Response summaries auto-refresh via potentialRehearsalResponseSummariesProvider
          // which watches rehearsalProvider - no manual invalidation needed here.
          ref.read(rehearsalProvider.notifier).refresh();
          ref.invalidate(potentialRehearsalResponseSummariesProvider);
        },
      );
    });

    // NOTE: Response summaries now load automatically via potentialRehearsalResponseSummariesProvider
    // which watches rehearsalProvider and activeBandIdProvider. No manual load needed.
  }

  /// Scroll listener for rehearsals horizontal list
  void _onRehearsalScroll() {
    if (!_rehearsalScrollController.hasClients) return;

    final position = _rehearsalScrollController.position;
    const threshold = 200.0; // pixels from end

    // When user scrolls within threshold of the end, auto-load more
    if (position.pixels >= position.maxScrollExtent - threshold) {
      _loadMoreRehearsalsIfNeeded();
    }
  }

  /// Auto-load more rehearsals when scroll threshold is reached
  void _loadMoreRehearsalsIfNeeded() {
    // Get current rehearsal state
    final rehearsalState = ref.read(rehearsalProvider);
    if (rehearsalState.confirmedRehearsals.isEmpty) return;

    // Get current pagination state
    final paginationState = ref.read(rehearsalPaginationProvider);

    // Group rehearsals into series
    final series = RehearsalDisplayHelper.groupIntoSeries(
      rehearsalState.confirmedRehearsals,
    );

    // Find the first series that has more to load
    for (final s in series) {
      final visibleCount =
          paginationState.visibleCountBySeriesId[s.seriesId] ?? 10;
      if (s.hasMore(visibleCount)) {
        // Trigger load more for this series
        ref.read(rehearsalPaginationProvider.notifier).loadMore(s.seriesId);
        // Only load one series at a time to avoid rapid multiple loads
        break;
      }
    }
  }

  @override
  void dispose() {
    // Close the band ID subscription to prevent memory leaks
    _bandIdSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    _rehearsalScrollController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _retry() {
    ref.read(activeBandProvider.notifier).loadUserBands();
  }

  void _openDrawer() {
    debugPrint('[HomeTabContent] _openDrawer called');
    ref.read(overlayStateProvider.notifier).openMenuDrawer();
  }

  void _openBandSwitcher() {
    debugPrint('[HomeTabContent] _openBandSwitcher called');
    ref.read(overlayStateProvider.notifier).openBandSwitcher();
  }

  void _openAddEventSheet(EventType eventType) {
    final bandId = ref.read(activeBandIdProvider);
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      initialType: eventType,
      onSaved: () {
        // Refresh dashboard data
        ref.read(gigProvider.notifier).refresh();
        ref.read(rehearsalProvider.notifier).refresh();
        // Refresh calendar to keep in sync
        if (bandId != null) {
          ref
              .read(calendarProvider.notifier)
              .invalidateAndRefresh(bandId: bandId);
        }
      },
    );
  }

  void _handleAddEvent() {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (__, _) => null,
    );
    // Default to rehearsal for admin/member, gig for contributor
    final eventType =
        (perms?.isContributor == true) ? EventType.gig : EventType.rehearsal;
    _openAddEventSheet(eventType);
  }

  void _handleOpenFinancials() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FinancialsScreen(),
        fullscreenDialog: false,
      ),
    );
  }

  /// Open the Edit Event drawer for an existing gig
  void _openEditGigSheet(Gig gig) {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (__, _) => null,
    );
    // Allow contributors to edit potential gigs they can create
    final canEdit = perms != null &&
        (perms.canEditGigs || (gig.isPotential && perms.canEditPotentialGigs));
    if (!canEdit) return;

    debugPrint(
      '[EditGig] Opening edit sheet for gig ${gig.id}, isMultiDate=${gig.isMultiDate}, additionalDates=${gig.additionalDates.length}',
    );
    final bandId = ref.read(activeBandIdProvider);
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      mode: EventFormMode.edit,
      initialType: EventType.gig,
      existingEventId: gig.id,
      initialData: EventFormData.fromGig(gig),
      onSaved: () {
        debugPrint('[EditGig] onSaved callback for gig ${gig.id}');
        ref.read(gigProvider.notifier).refresh();
        ref.read(rehearsalProvider.notifier).refresh();
        // Invalidate response summaries provider to fetch fresh availability counts.
        // This ensures the Potential Gig card footer updates after user changes availability.
        ref.invalidate(potentialGigResponseSummariesProvider);
        // Refresh calendar to keep in sync after edit/delete
        if (bandId != null) {
          ref
              .read(calendarProvider.notifier)
              .invalidateAndRefresh(bandId: bandId);
        }
      },
    );
  }

  void _openViewGigSheet(Gig gig) {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, __) => null,
    );
    final canEdit = perms != null &&
        (perms.canEditGigs || (gig.isPotential && perms.canEditPotentialGigs));

    final bandTimezone =
        ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';

    ViewGigDrawer.show(
      context,
      gig: gig,
      bandTimezone: bandTimezone,
      canEdit: canEdit,
      onEdit: () => _openEditGigSheet(gig),
    );
  }

  /// Open the View Rehearsal drawer for a confirmed rehearsal
  void _openViewRehearsalSheet(Rehearsal rehearsal) {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, __) => null,
    );
    final canEdit = perms != null && perms.canEditGigs;

    final bandTimezone =
        ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';

    ViewRehearsalDrawer.show(
      context,
      rehearsal: rehearsal,
      bandTimezone: bandTimezone,
      canEdit: canEdit,
      onEdit: () => _openEditRehearsalSheet(rehearsal),
    );
  }

  /// Open the Edit Event drawer for an existing rehearsal
  void _openEditRehearsalSheet(Rehearsal rehearsal) {
    // Contributors cannot open the edit drawer
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (__, _) => null,
    );
    if (perms == null || !perms.canEditGigs) return;

    final bandId = ref.read(activeBandIdProvider);
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      mode: EventFormMode.edit,
      initialType: EventType.rehearsal,
      existingEventId: rehearsal.id,
      initialData: EventFormData.fromRehearsal(rehearsal),
      onSaved: () {
        debugPrint(
          '[DeleteEvent] onSaved callback for rehearsal ${rehearsal.id}',
        );
        ref.read(gigProvider.notifier).refresh();
        ref.read(rehearsalProvider.notifier).refresh();
        // Refresh calendar to keep in sync after edit/delete
        if (bandId != null) {
          ref
              .read(calendarProvider.notifier)
              .invalidateAndRefresh(bandId: bandId);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandState = ref.watch(activeBandProvider);
    final gigState = ref.watch(gigProvider);
    final rehearsalState = ref.watch(rehearsalProvider);
    final membersState = ref.watch(membersProvider);
    final setlistsState = ref.watch(setlistsProvider);
    final hasRehearsal = rehearsalState.hasUpcomingRehearsal;
    final activeBandId = bandState.activeBandId;

    // RBAC: Watch permissions for gating quick actions
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canCreateGig = permissionsAsync.when(
      data: (perms) => perms.canCreateGigs,
      loading: () => false, // Fail-closed — hide until permissions resolve
      error: (__, _) => false,
    );
    final canCreateSetlist = permissionsAsync.when(
      data: (perms) => perms.canCreateSetlists,
      loading: () => false,
      error: (__, _) => false,
    );
    // NOTE: canCreateGig/canCreateSetlist are passed to _buildContentState below

    final isContributor = permissionsAsync.when(
      data: (perms) => perms.isContributor,
      loading: () => false,
      error: (__, _) => false,
    );
    final canViewFinancials = permissionsAsync.when(
      data: (perms) => perms.canViewFinancials,
      loading: () => false,
      error: (_, __) => false,
    );

    // Watch response summaries for potential gigs - this is the source of truth
    // for availability counts displayed on the PotentialGigCard.
    // The provider auto-refreshes when gigs/band change, and is invalidated
    // by the Edit Gig drawer after availability updates.
    final responseSummariesAsync = ref.watch(
      potentialGigResponseSummariesProvider,
    );
    // Use .when() pattern to safely extract value, defaulting to empty map while loading/error
    final Map<String, GigResponseSummary> responseSummaries =
        responseSummariesAsync.when(
      data: (summaries) => summaries,
      loading: () => {},
      error: (__, _) => {},
    );

    // Watch response summaries for potential rehearsals - mirrors gig pattern
    final rehearsalResponseSummariesAsync = ref.watch(
      potentialRehearsalResponseSummariesProvider,
    );
    final Map<String, RehearsalResponseSummary> rehearsalResponseSummaries =
        rehearsalResponseSummariesAsync.when(
      data: (summaries) => summaries,
      loading: () => {},
      error: (__, _) => {},
    );

    // Watch current user's own inline responses for the card YES/NO buttons
    final Map<String, String?> gigUserResponses =
        ref.watch(currentUserGigResponsesProvider).when(
              data: (r) => r,
              loading: () => {},
              error: (__, _) => {},
            );

    // Watch per-date responses for multi-date potential gig cards
    final Map<String, Map<String?, String?>> gigAllDateResponses =
        ref.watch(currentUserGigAllDateResponsesProvider).when(
              data: (r) => r,
              loading: () => {},
              error: (__, _) => {},
            );

    final Map<String, String?> rehearsalUserResponses =
        ref.watch(currentUserRehearsalResponsesProvider).when(
              data: (r) => r,
              loading: () => {},
              error: (__, _) => {},
            );

    // Watch per-date responses for multi-date potential rehearsal cards
    final Map<String, Map<String?, String?>> rehearsalAllDateResponses =
        ref.watch(currentUserRehearsalAllDateResponsesProvider).when(
              data: (r) => r,
              loading: () => {},
              error: (_, __) => {},
            );

    // Watch display band for header avatar (shows draft during editing)
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Check if data is for the current band (prevents stale error display)
    final gigsForCurrentBand = gigState.loadedBandId == activeBandId;
    final rehearsalsForCurrentBand =
        rehearsalState.loadedBandId == activeBandId;
    final dataIsStale = activeBandId != null &&
        (!gigsForCurrentBand || !rehearsalsForCurrentBand);

    // Determine which state widget to show
    final Widget stateWidget;
    final String stateKey;

    if (bandState.isLoading) {
      stateKey = 'loading-bands';
      stateWidget = _buildLoadingState('Setting up the stage...');
    } else if (bandState.error != null) {
      stateKey = 'error-bands';
      stateWidget = _buildErrorState(
        'The roadie tripped over a cable.',
        bandState.error!,
      );
    } else if (!bandState.hasBands) {
      stateKey = 'no-band';
      stateWidget = const NoBandState();
    } else if (gigState.isLoading || rehearsalState.isLoading || dataIsStale) {
      // Show loading if either is loading OR data is from a different band
      stateKey = 'loading-gigs';
      stateWidget = _buildLoadingState('Setting up the stage...');
    } else if (!gigState.hasGigs && !hasRehearsal) {
      // Check empty BEFORE error — empty is not an error condition
      stateKey = 'empty';
      stateWidget = EmptyHomeState(
        bandName:
            displayBand?.name ?? bandState.activeBand?.name ?? 'BandRoadie',
        bandAvatarColor:
            displayBand?.avatarColor ?? bandState.activeBand?.avatarColor,
        bandImageUrl: displayBand?.imageUrl ?? bandState.activeBand?.imageUrl,
        localImageFile: draftLocalImage,
        onMenuTap: _openDrawer,
        onAvatarTap: _openBandSwitcher,
        onCreateRehearsal: isContributor
            ? null
            : () => _openAddEventSheet(EventType.rehearsal),
        onCreateGig:
            canCreateGig ? () => _openAddEventSheet(EventType.gig) : null,
        onCreateSetlist: canCreateSetlist
            ? () {
                // Use custom fade+slide transition for smooth navigation
                Navigator.of(
                  context,
                ).push(fadeSlideRoute(page: const NewSetlistScreen()));
              }
            : null,
      );
    } else if (gigState.error != null && gigsForCurrentBand) {
      // Only show error if it's for the current band
      stateKey = 'error-gigs';
      stateWidget = _buildErrorState(
        'Couldn\'t load your gigs.',
        gigState.error!,
      );
    } else {
      stateKey = 'content';
      stateWidget = _buildContentState(
        bandState,
        gigState,
        rehearsalState,
        membersState,
        setlistsState,
        displayBand,
        responseSummaries,
        rehearsalResponseSummaries,
        gigUserResponses: gigUserResponses,
        gigAllDateResponses: gigAllDateResponses,
        rehearsalUserResponses: rehearsalUserResponses,
        rehearsalAllDateResponses: rehearsalAllDateResponses,
        canCreateGig: canCreateGig,
        canCreateSetlist: canCreateSetlist,
        isContributor: isContributor,
        canViewFinancials: canViewFinancials,
      );
    }

    // Wrap in AnimatedSwitcher for smooth state transitions
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      switchInCurve: AppCurves.ease,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.02),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppCurves.slideIn));

        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(stateKey), child: stateWidget),
    );
  }

  Widget _buildLoadingState(String message) {
    return Container(
      color: context.colors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Container(
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
            ),
            const SizedBox(height: Spacing.space24),
            Text(
              message,
              style:
                  AppTextStyles.body.copyWith(color: context.colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String title, String details) {
    return Container(
      color: context.colors.background,
      child: Center(
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
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.displayMedium,
              ),
              const SizedBox(height: Spacing.space12),
              Text(
                'Don\'t worry, even the best roadies\ndrop a cable sometimes.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: Spacing.space40),
              AppButton(
                label: 'Try Again',
                icon: AppIcons.refresh,
                onPressed: _retry,
                variant: AppButtonVariant.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentState(
    ActiveBandState bandState,
    GigState gigState,
    RehearsalState rehearsalState,
    MembersState membersState,
    SetlistsState setlistsState,
    Band? displayBand,
    Map<String, GigResponseSummary> responseSummaries,
    Map<String, RehearsalResponseSummary> rehearsalResponseSummaries, {
    required Map<String, String?> gigUserResponses,
    required Map<String, Map<String?, String?>> gigAllDateResponses,
    required Map<String, String?> rehearsalUserResponses,
    required Map<String, Map<String?, String?>> rehearsalAllDateResponses,
    required bool canCreateGig,
    required bool canCreateSetlist,
    required bool isContributor,
    required bool canViewFinancials,
  }) {
    final activeBand = bandState.activeBand;
    final upcomingGig = gigState.nextConfirmedGig;

    // Content WITHOUT Scaffold - just the body content
    return Container(
      color: context.colors.background,
      child: Stack(
        children: [
          // Scrollable content
          Positioned.fill(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: context.colors.surface,
              onRefresh: () async {
                ref.invalidate(bandFullStateProvider);
                await ref.read(bandFullStateProvider.future);
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Update scroll blur for bottom nav glass effect
                  if (notification.metrics.axis == Axis.vertical) {
                    ref
                        .read(scrollBlurProvider.notifier)
                        .updateFromOffset(notification.metrics.pixels);
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // Top padding for app bar
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: Spacing.appBarHeight +
                            MediaQuery.of(context).padding.top,
                      ),
                    ),
                    // Main content with staggered entrance
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.pagePadding,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: Spacing.space24),

                                // Potential events (gigs + rehearsals) in horizontal scroll
                                // Availability counts come from responseSummaries and rehearsalResponseSummaries,
                                // which are watched from their respective providers.
                                // This ensures counts update immediately when user changes
                                // availability in modals or edit drawers.
                                if (gigState.potentialGigs.isNotEmpty ||
                                    rehearsalState
                                        .potentialRehearsals.isNotEmpty) ...[
                                  _AnimatedCardEntrance(
                                    delay: const Duration(milliseconds: 0),
                                    child: _buildHorizontalPotentialEvents(
                                      gigState.potentialGigs,
                                      rehearsalState.potentialRehearsals,
                                      gigAllDateResponses,
                                      rehearsalUserResponses,
                                      rehearsalAllDateResponses,
                                      setlistsState,
                                    ),
                                  ),
                                  // Only add spacing when rehearsal section won't have title
                                  // (title provides topSpacing when confirmed rehearsals exist)
                                  if (rehearsalState
                                      .confirmedRehearsals.isEmpty)
                                    const SizedBox(height: Spacing.space24),
                                ],

                                // Upcoming rehearsals section
                                // Title — only when confirmed rehearsals exist
                                if (rehearsalState
                                    .confirmedRehearsals.isNotEmpty) ...[
                                  const SectionHeader(
                                      title: 'Upcoming Rehearsals',
                                      topSpacing: Spacing.space24),
                                  const SizedBox(height: Spacing.space12),
                                ],

                                // Content — always shown unless only potential rehearsals exist
                                if (rehearsalState
                                    .confirmedRehearsals.isNotEmpty)
                                  _AnimatedCardEntrance(
                                    delay: const Duration(milliseconds: 80),
                                    child: _buildHorizontalRehearsalsList(
                                        rehearsalState),
                                  )
                                else if (rehearsalState
                                    .potentialRehearsals.isEmpty)
                                  _AnimatedCardEntrance(
                                    delay: const Duration(milliseconds: 80),
                                    child: EmptySectionCard(
                                      title: 'No Rehearsal Scheduled',
                                      buttonLabel: 'Schedule Rehearsal',
                                      onButtonPressed: isContributor
                                          ? null
                                          : () => _openAddEventSheet(
                                                EventType.rehearsal,
                                              ),
                                    ),
                                  ),

                                // Upcoming gigs section
                                const SectionHeader(
                                    title: 'Upcoming Gigs',
                                    topSpacing: Spacing.space24),
                                const SizedBox(height: Spacing.space12),
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 160),
                                  child: upcomingGig != null
                                      ? _buildHorizontalGigsList(gigState)
                                      : EmptySectionCard(
                                          title: 'No Gigs Booked',
                                          buttonLabel: 'Create Gig',
                                          onButtonPressed: canCreateGig
                                              ? () => _openAddEventSheet(
                                                  EventType.gig)
                                              : null,
                                        ),
                                ),

                                // Quick actions (hidden for contributors)
                                // Quick actions - show section if at least one action button is visible
                                Builder(builder: (context) {
                                  final showAddEvent =
                                      !isContributor || canCreateGig;
                                  final hasAnyButton = showAddEvent ||
                                      canCreateSetlist ||
                                      !isContributor;
                                  if (!hasAnyButton) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SectionHeader(
                                          title: 'Quick Actions',
                                          topSpacing: Spacing.space24),
                                      const SizedBox(height: Spacing.space16),
                                      _AnimatedCardEntrance(
                                        delay:
                                            const Duration(milliseconds: 240),
                                        child: QuickActionsRow(
                                          onAddEvent: showAddEvent
                                              ? _handleAddEvent
                                              : null,
                                          onCreateSetlist: canCreateSetlist
                                              ? () {
                                                  // Use custom fade+slide transition
                                                  Navigator.of(context).push(
                                                    fadeSlideRoute(
                                                      page:
                                                          const NewSetlistScreen(),
                                                    ),
                                                  );
                                                }
                                              : null,
                                          onFinancials: canViewFinancials
                                              ? _handleOpenFinancials
                                              : null,
                                          showAddEvent: showAddEvent,
                                          showCreateSetlist: canCreateSetlist,
                                          showFinancials: canViewFinancials,
                                        ),
                                      ),
                                    ],
                                  );
                                }),

                                // Bottom padding for nav bar (extra space to scroll past)
                                SizedBox(
                                  height: Spacing.space48 +
                                      Spacing.bottomNavHeight +
                                      MediaQuery.of(context).padding.bottom +
                                      32, // Extra scroll clearance
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: HomeAppBar(
              bandName: displayBand?.name ?? activeBand?.name ?? 'BandRoadie',
              onMenuTap: _openDrawer,
              onAvatarTap: _openBandSwitcher,
              bandAvatarColor:
                  displayBand?.avatarColor ?? activeBand?.avatarColor,
              bandImageUrl: displayBand?.imageUrl ?? activeBand?.imageUrl,
              localImageFile: ref.watch(draftLocalImageProvider),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a horizontal scrolling list of potential events (gigs + rehearsals), sorted by date proximity.
  Widget _buildHorizontalPotentialEvents(
    List<Gig> potentialGigs,
    List<Rehearsal> potentialRehearsals,
    Map<String, Map<String?, String?>> gigAllDateResponses,
    Map<String, String?> rehearsalUserResponses,
    Map<String, Map<String?, String?>> rehearsalAllDateResponses,
    SetlistsState setlistsState,
  ) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    final upcomingGigs = potentialGigs
        .where((g) => g.date.isAfter(yesterday))
        .map((g) => {'type': 'gig', 'date': g.date, 'gig': g})
        .toList();

    // Filter potential rehearsals to only show parent rehearsals for recurring series
    // (child instances with parentRehearsalId are excluded)
    final upcomingRehearsals = potentialRehearsals
        .where((r) => r.date.isAfter(yesterday) && r.parentRehearsalId == null)
        .map((r) => {'type': 'rehearsal', 'date': r.date, 'rehearsal': r})
        .toList();

    final allPotentialEvents = [...upcomingGigs, ...upcomingRehearsals];
    allPotentialEvents.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    if (allPotentialEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    final bandTimezone =
        ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';
    final bandId = ref.read(activeBandIdProvider);
    final userId = supabase.auth.currentUser?.id;

    return SizedBox(
      height: Spacing.potentialGigCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: allPotentialEvents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final event = allPotentialEvents[index];
          final type = event['type'] as String;

          if (type == 'gig') {
            final gig = event['gig'] as Gig;
            return PotentialGigCard(
              gig: gig,
              width: Spacing.potentialGigCardWidth,
              bandTimezone: bandTimezone,
              perDateUserResponses: gigAllDateResponses[gig.id],
              onRespondForDate: (bandId == null || userId == null)
                  ? null
                  : (response, gigDateId) async {
                      if (response == null) {
                        // Delete response for this specific date
                        await ref
                            .read(gigResponseRepositoryProvider)
                            .deleteResponseForDate(
                              gigId: gig.id,
                              userId: userId,
                              gigDateId: gigDateId,
                            );
                      } else {
                        // Upsert response for this specific date
                        await ref
                            .read(gigResponseRepositoryProvider)
                            .upsertResponseForDate(
                              gigId: gig.id,
                              gigDateId: gigDateId,
                              userId: userId,
                              response: response,
                            );
                      }
                      ref.invalidate(currentUserGigAllDateResponsesProvider);
                      ref.invalidate(currentUserGigResponsesProvider);
                      ref.invalidate(potentialGigResponseSummariesProvider);
                    },
              onTap: () => _openEditGigSheet(gig),
            );
          } else {
            final rehearsal = event['rehearsal'] as Rehearsal;
            String? setlistName;
            if (rehearsal.setlistId != null) {
              setlistName = setlistsState.setlists
                  .where((s) => s.id == rehearsal.setlistId)
                  .firstOrNull
                  ?.name;
            }
            return SizedBox(
              width: Spacing.potentialGigCardWidth,
              child: RehearsalCard(
                rehearsal: rehearsal,
                setlistName: setlistName,
                bandTimezone: bandTimezone,
                additionalDates: rehearsal.additionalDates,
                perDateUserResponses:
                    rehearsalAllDateResponses[rehearsal.id] ?? {},
                onRespondForDate: (bandId == null || userId == null)
                    ? null
                    : (response, rehearsalDateId) async {
                        if (response == null) {
                          // Delete response for this specific date
                          await ref
                              .read(rehearsalResponseRepositoryProvider)
                              .deleteResponseForDate(
                                rehearsalId: rehearsal.id,
                                userId: userId,
                                rehearsalDateId: rehearsalDateId,
                              );
                        } else {
                          // Upsert response for this specific date
                          await ref
                              .read(rehearsalResponseRepositoryProvider)
                              .upsertResponseForDate(
                                rehearsalId: rehearsal.id,
                                rehearsalDateId: rehearsalDateId,
                                userId: userId,
                                response: response,
                              );
                        }
                        ref.invalidate(
                            currentUserRehearsalAllDateResponsesProvider);
                        ref.invalidate(currentUserRehearsalResponsesProvider);
                        ref.invalidate(
                            potentialRehearsalResponseSummariesProvider);
                      },
                onTap: () => _openEditRehearsalSheet(rehearsal),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildHorizontalGigsList(GigState gigState) {
    final confirmedGigs = gigState.confirmedGigs;
    if (confirmedGigs.isEmpty) {
      return const SizedBox.shrink();
    }

    final bandTimezone =
        ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < confirmedGigs.length; index++) ...[
            if (index > 0) const SizedBox(width: 16),
            ConfirmedGigCard(
              gig: confirmedGigs[index],
              index: index,
              bandTimezone: bandTimezone,
              onTap: () => _openViewGigSheet(confirmedGigs[index]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalRehearsalsList(RehearsalState rehearsalState) {
    final confirmedRehearsals = rehearsalState.confirmedRehearsals;
    if (confirmedRehearsals.isEmpty) {
      return const SizedBox.shrink();
    }

    final setlistsState = ref.watch(setlistsProvider);
    final paginationState = ref.watch(rehearsalPaginationProvider);

    // Group rehearsals into series and apply pagination
    final series = RehearsalDisplayHelper.groupIntoSeries(confirmedRehearsals);
    final displayItems = RehearsalDisplayHelper.flattenForDisplay(
      series,
      paginationState.visibleCountBySeriesId,
    );

    // Filter out load-more markers for infinite scroll
    final rehearsalItems =
        displayItems.where((item) => item.isRehearsal).toList();

    return SizedBox(
      height: Spacing.rehearsalCardHeight,
      child: ListView.separated(
        controller: _rehearsalScrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: rehearsalItems.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = rehearsalItems[index];

          // All items are now rehearsals (load-more markers filtered out)
          final rehearsal = item.rehearsal!;
          String? setlistName;
          if (rehearsal.setlistId != null) {
            final setlist = setlistsState.setlists
                .where((s) => s.id == rehearsal.setlistId)
                .firstOrNull;
            setlistName = setlist?.name;
          }
          return RehearsalCard(
            rehearsal: rehearsal,
            setlistName: setlistName,
            bandTimezone: ref.watch(activeBandProvider).activeBand?.timezone ??
                'America/Chicago',
            onTap: () => _openViewRehearsalSheet(rehearsal),
          );
        },
      ),
    );
  }
}

// Animated card entrance helper
class _AnimatedCardEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _AnimatedCardEntrance({required this.child, required this.delay});

  @override
  State<_AnimatedCardEntrance> createState() => _AnimatedCardEntranceState();
}

class _AnimatedCardEntranceState extends State<_AnimatedCardEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppDurations.medium,
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppCurves.ease,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.slideIn));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
