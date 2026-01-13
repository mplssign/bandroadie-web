import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../components/ui/brand_action_button.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../bands/active_band_controller.dart';
import '../calendar/calendar_controller.dart';
import '../calendar/widgets/add_block_out_drawer.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../gigs/gig_controller.dart';
import '../gigs/gig_response_repository.dart';
import '../gigs/potential_gig_prompt_service.dart';
import '../members/members_controller.dart';
import '../rehearsals/rehearsal_controller.dart';
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

  /// Session-level flag to only show availability popup once per app session
  /// Static so it persists across widget rebuilds but resets when app restarts
  static bool _hasShownAvailabilityPromptThisSession = false;

  @override
  void initState() {
    super.initState();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

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

    // Start entrance animation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });

    // Note: We no longer call loadUserBands() here because AuthGate
    // already loads bands before mounting AppShell/HomeTabContent.

    // Listen for when the band becomes available and check pending prompts
    // This is more reliable than addPostFrameCallback since band loads async
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForBandAndCheckPrompts();
    });
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
        _checkPendingGigPrompts();
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
    }
  }

  /// Check for pending potential gigs and show prompt modals
  /// Only shows once per app session (first visit to dashboard)
  void _checkPendingGigPrompts() {
    debugPrint('[HomeTabContent] _checkPendingGigPrompts called');

    // Only show availability popup once per session
    if (_hasShownAvailabilityPromptThisSession) {
      debugPrint(
        '[HomeTabContent] Already shown availability prompt this session, skipping',
      );
      return;
    }

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

    // Mark as shown for this session
    _hasShownAvailabilityPromptThisSession = true;

    // Delay slightly to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      ref
          .read(potentialGigPromptProvider.notifier)
          .checkAndShowPendingPrompts(
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

  @override
  void dispose() {
    // Close the band ID subscription to prevent memory leaks
    _bandIdSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
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

  void _handleBlockOut() {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;
    BlockOutDrawer.show(
      context,
      ref: ref,
      bandId: bandId,
      mode: BlockOutDrawerMode.create,
      onSaved: () {
        // Refresh calendar data after creating block out
        ref
            .read(calendarProvider.notifier)
            .invalidateAndRefresh(bandId: bandId);
      },
    );
  }

  /// Open the Edit Event drawer for an existing gig
  void _openEditGigSheet(Gig gig) {
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

  /// Open the Edit Event drawer for an existing rehearsal
  void _openEditRehearsalSheet(Rehearsal rehearsal) {
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
          error: (_, __) => {},
        );

    // Watch display band for header avatar (shows draft during editing)
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Check if data is for the current band (prevents stale error display)
    final gigsForCurrentBand = gigState.loadedBandId == activeBandId;
    final rehearsalsForCurrentBand =
        rehearsalState.loadedBandId == activeBandId;
    final dataIsStale =
        activeBandId != null &&
        (!gigsForCurrentBand || !rehearsalsForCurrentBand);

    // Determine which state widget to show
    final Widget stateWidget;
    final String stateKey;

    if (bandState.isLoading) {
      stateKey = 'loading-bands';
      stateWidget = _buildLoadingState('Tuning up...');
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
      stateWidget = _buildLoadingState('Loading the setlist...');
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
        onScheduleRehearsal: () => _openAddEventSheet(EventType.rehearsal),
        onCreateGig: () => _openAddEventSheet(EventType.gig),
        onCreateSetlist: () {
          // Use custom fade+slide transition for smooth navigation
          Navigator.of(
            context,
          ).push(fadeSlideRoute(page: const NewSetlistScreen()));
        },
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
      color: AppColors.scaffoldBg,
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
                decoration: const BoxDecoration(
                  color: AppColors.accentMuted,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.space24),
            Text(
              message,
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String title, String details) {
    return Container(
      color: AppColors.scaffoldBg,
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
                  color: AppColors.accentMuted,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.music_off_rounded,
                  size: 40,
                  color: AppColors.accent,
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
              BrandActionButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                onPressed: _retry,
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
  ) {
    final activeBand = bandState.activeBand;
    final upcomingGig = gigState.nextConfirmedGig;
    final nextRehearsal = rehearsalState.nextRehearsal;

    // Content WITHOUT Scaffold - just the body content
    return Container(
      color: AppColors.scaffoldBg,
      child: Stack(
        children: [
          // Scrollable content
          Positioned.fill(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.cardBg,
              onRefresh: () async {
                await ref.read(gigProvider.notifier).refresh();
                await ref.read(rehearsalProvider.notifier).refresh();
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
                        height:
                            Spacing.appBarHeight +
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

                                // Potential gig cards (stacked, sorted by date proximity)
                                // Availability counts come from responseSummaries, which is
                                // watched from potentialGigResponseSummariesProvider.
                                // This ensures counts update immediately when user changes
                                // availability in the Edit Gig drawer.
                                if (gigState.potentialGigs.isNotEmpty) ...[
                                  _AnimatedCardEntrance(
                                    delay: const Duration(milliseconds: 0),
                                    child: _buildStackedPotentialGigs(
                                      gigState.potentialGigs,
                                      responseSummaries,
                                      membersState.members.length,
                                    ),
                                  ),
                                  const SizedBox(height: Spacing.space24),
                                ],

                                // Next rehearsal card
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 80),
                                  child: nextRehearsal != null
                                      ? Builder(
                                          builder: (context) {
                                            // Look up setlist name from setlistId
                                            String? setlistName;
                                            if (nextRehearsal.setlistId !=
                                                null) {
                                              final setlist = setlistsState
                                                  .setlists
                                                  .where(
                                                    (s) =>
                                                        s.id ==
                                                        nextRehearsal.setlistId,
                                                  )
                                                  .firstOrNull;
                                              setlistName = setlist?.name;
                                            }
                                            return RehearsalCard(
                                              rehearsal: nextRehearsal,
                                              setlistName: setlistName,
                                              onTap: () =>
                                                  _openEditRehearsalSheet(
                                                    nextRehearsal,
                                                  ),
                                            );
                                          },
                                        )
                                      : EmptySectionCard(
                                          title: 'No Rehearsal Scheduled',
                                          subtitle:
                                              'The stage is empty and the amps are cold.',
                                          buttonLabel: 'Schedule Rehearsal',
                                          onButtonPressed: () =>
                                              _openAddEventSheet(
                                                EventType.rehearsal,
                                              ),
                                        ),
                                ),

                                // Upcoming gigs section
                                const SectionHeader(title: 'Upcoming Gigs'),
                                const SizedBox(height: Spacing.space12),
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 160),
                                  child: upcomingGig != null
                                      ? _buildHorizontalGigsList(gigState)
                                      : EmptySectionCard(
                                          title: 'No Gigs Booked',
                                          subtitle:
                                              'The world clearly isn\'t ready yet.',
                                          buttonLabel: 'Create Gig',
                                          onButtonPressed: () =>
                                              _openAddEventSheet(EventType.gig),
                                        ),
                                ),

                                // Quick actions
                                const SectionHeader(title: 'Quick Actions'),
                                const SizedBox(height: Spacing.space16),
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 240),
                                  child: QuickActionsRow(
                                    onScheduleRehearsal: () =>
                                        _openAddEventSheet(EventType.rehearsal),
                                    onCreateGig: () =>
                                        _openAddEventSheet(EventType.gig),
                                    onCreateSetlist: () {
                                      // Use custom fade+slide transition
                                      Navigator.of(context).push(
                                        fadeSlideRoute(
                                          page: const NewSetlistScreen(),
                                        ),
                                      );
                                    },
                                    onBlockOut: _handleBlockOut,
                                  ),
                                ),

                                // Bottom padding for nav bar (extra space to scroll past)
                                SizedBox(
                                  height:
                                      Spacing.space48 +
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

  /// Builds a vertical list of potential gig cards, sorted by date proximity
  Widget _buildStackedPotentialGigs(
    List<Gig> potentialGigs,
    Map<String, GigResponseSummary> responseSummaries,
    int memberCount,
  ) {
    // Filter out past gigs
    final now = DateTime.now();
    final upcomingPotentialGigs = potentialGigs
        .where((g) => g.date.isAfter(now.subtract(const Duration(days: 1))))
        .toList();

    if (upcomingPotentialGigs.isEmpty) {
      return const SizedBox.shrink();
    }

    // Display as a vertical list with spacing
    return Column(
      children: [
        for (int i = 0; i < upcomingPotentialGigs.length; i++) ...[
          Builder(
            builder: (context) {
              final gig = upcomingPotentialGigs[i];
              return PotentialGigCard(
                gig: gig,
                onTap: () => _openEditGigSheet(gig),
              );
            },
          ),
          if (i < upcomingPotentialGigs.length - 1)
            const SizedBox(height: Spacing.space16),
        ],
      ],
    );
  }

  Widget _buildHorizontalGigsList(GigState gigState) {
    final confirmedGigs = gigState.confirmedGigs;
    if (confirmedGigs.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: Spacing.gigCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: confirmedGigs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final gig = confirmedGigs[index];
          return ConfirmedGigCard(
            gig: gig,
            index: index,
            onTap: () => _openEditGigSheet(gig),
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
