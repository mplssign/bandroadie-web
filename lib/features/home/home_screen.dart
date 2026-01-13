import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../tips/tips_and_tricks_screen.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../bands/edit_band_screen.dart';
import '../calendar/calendar_controller.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../feedback/bug_report_screen.dart';
import '../profile/my_profile_screen.dart';
import '../settings/settings_screen.dart';
import '../gigs/gig_controller.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../setlists/new_setlist_screen.dart';
import '../setlists/setlists_screen.dart' show SetlistsState, setlistsProvider;
import 'widgets/bottom_nav_bar.dart';
import 'widgets/confirmed_gig_card.dart';
import 'widgets/empty_home_state.dart';
import 'widgets/empty_section_card.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/no_band_state.dart';
import 'widgets/potential_gig_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/rehearsal_card.dart';
import 'widgets/section_header.dart';
import 'widgets/side_drawer.dart';
import 'widgets/band_switcher.dart';

// ============================================================================
// HOME SCREEN
// The main dashboard. Shows different states based on band membership and gigs.
//
// STATES:
// 1. Loading — fetching bands or gigs
// 2. Error — something went wrong (with retry)
// 3. No Band — user has zero band memberships
// 4. Empty — user has a band but zero gigs/rehearsals
// 5. Content — user has a band with data to show
//
// BAND ISOLATION: All data is fetched ONLY for the active band.
// ============================================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Drawer state
  bool _isDrawerOpen = false;
  bool _isBandSwitcherOpen = false;

  // User profile data
  String? _userFirstName;
  String? _userLastName;

  @override
  void initState() {
    super.initState();

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

    // Load user's bands when screen initializes
    Future.microtask(() {
      ref.read(activeBandProvider.notifier).loadUserBands();
    });

    // Load user profile data
    _loadUserProfile();

    // Start entrance animation
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
      debugPrint('[HomeScreen] Failed to load user profile: $e');
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await ref.read(activeBandProvider.notifier).reset();
    ref.read(gigProvider.notifier).reset();
    ref.read(rehearsalProvider.notifier).reset();
    await supabase.auth.signOut();
  }

  void _retry() {
    ref.read(activeBandProvider.notifier).loadUserBands();
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
    // Close the switcher immediately for better UX
    _closeBandSwitcher();

    // Reset gig/rehearsal state before band switch to clear stale errors
    debugPrint('[Dashboard] activeBand changed: ${band.id}');
    ref.read(gigProvider.notifier).resetForBandChange();
    ref.read(rehearsalProvider.notifier).resetForBandChange();

    // Select the new band - this will trigger automatic refetch of gigs/rehearsals
    // via the Riverpod providers that watch activeBandIdProvider
    ref.read(activeBandProvider.notifier).selectBand(band);
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

  /// Open the Edit Event drawer for an existing gig
  void _openEditGigSheet(Gig gig) {
    final bandId = ref.read(activeBandIdProvider);
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      mode: EventFormMode.edit,
      initialType: EventType.gig,
      existingEventId: gig.id,
      initialData: EventFormData.fromGig(gig),
      onSaved: () {
        debugPrint('[DeleteEvent] onSaved callback for gig ${gig.id}');
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
    final setlistsState = ref.watch(setlistsProvider);
    final hasRehearsal = rehearsalState.hasUpcomingRehearsal;

    // Watch display band for header avatar (shows draft during editing)
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Determine which state widget to show
    final Widget stateWidget;
    final String stateKey;

    if (bandState.isLoading) {
      stateKey = 'loading-bands';
      stateWidget = _buildLoadingScreen('Tuning up...');
    } else if (bandState.error != null) {
      stateKey = 'error-bands';
      stateWidget = _buildErrorScreen(
        'The roadie tripped over a cable.',
        bandState.error!,
      );
    } else if (!bandState.hasBands) {
      stateKey = 'no-band';
      stateWidget = const NoBandState();
    } else if (gigState.isLoading) {
      stateKey = 'loading-gigs';
      stateWidget = _buildLoadingScreen('Loading the setlist...');
    } else if (gigState.error != null) {
      stateKey = 'error-gigs';
      stateWidget = _buildErrorScreen(
        'Couldn\'t load your gigs.',
        gigState.error!,
      );
    } else if (!gigState.hasGigs && !hasRehearsal) {
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
    } else {
      stateKey = 'content';
      stateWidget = _buildContentScreen(
        bandState,
        gigState,
        rehearsalState,
        setlistsState,
        displayBand,
      );
    }

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

    // Wrap in AnimatedSwitcher for smooth state transitions
    final content = AnimatedSwitcher(
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

    // Wrap with DrawerOverlay for side navigation
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

  /// Loading screen with roadie-style message
  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated loading indicator
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

  /// Error screen with humor and retry button
  Widget _buildErrorScreen(String title, String details) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.space32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error icon with glow effect
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
              SizedBox(
                width: 180,
                child: FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.space24,
                      vertical: Spacing.space16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.space24),
              // Debug info (subtle)
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: AppColors.cardBg,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(Spacing.cardRadius),
                      ),
                    ),
                    builder: (context) => Padding(
                      padding: const EdgeInsets.all(Spacing.space24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Technical Details',
                            style: AppTextStyles.cardTitle,
                          ),
                          const SizedBox(height: Spacing.space12),
                          Text(
                            details,
                            style: AppTextStyles.label.copyWith(
                              fontFamily: 'monospace',
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: Spacing.space24),
                        ],
                      ),
                    ),
                  );
                },
                child: Text(
                  'View technical stuff',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textDisabled,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Main content screen with gigs and rehearsals
  Widget _buildContentScreen(
    ActiveBandState bandState,
    GigState gigState,
    RehearsalState rehearsalState,
    SetlistsState setlistsState,
    Band?
    displayBand, // Band to display in header (may be draft during editing)
  ) {
    final activeBand = bandState.activeBand;
    final potentialGig = gigState.nextPotentialGig;
    final upcomingGig = gigState.nextConfirmedGig;
    final nextRehearsal = rehearsalState.nextRehearsal;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      extendBody: true,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const BottomNavBar(),
      body: Stack(
        children: [
          // Scrollable content (behind nav bars)
          Positioned.fill(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.cardBg,
              onRefresh: () async {
                await ref.read(gigProvider.notifier).refresh();
                await ref.read(rehearsalProvider.notifier).refresh();
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

                              // Potential gig card (urgent, needs response)
                              if (potentialGig != null) ...[
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 0),
                                  child: PotentialGigCard(
                                    gig: potentialGig,
                                    onTap: () =>
                                        _openEditGigSheet(potentialGig),
                                  ),
                                ),
                                const SizedBox(height: Spacing.space24),
                              ],

                              // Next rehearsal card (no section header per Figma)
                              _AnimatedCardEntrance(
                                delay: const Duration(milliseconds: 80),
                                child: nextRehearsal != null
                                    ? Builder(
                                        builder: (context) {
                                          // Look up setlist name from setlistId
                                          String? setlistName;
                                          if (nextRehearsal.setlistId != null) {
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

                              // Upcoming gigs section - horizontal scroll
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

                              // Quick actions - horizontal scroll
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
          // Static app bar at top (floating over content)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: HomeAppBar(
              // Use displayBand for header avatar (shows draft during editing)
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

  /// Horizontally scrollable list of gig cards
  Widget _buildHorizontalGigsList(GigState gigState) {
    final confirmedGigs = gigState.confirmedGigs;
    if (confirmedGigs.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: Spacing.gigCardHeight, // 126px
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

// ============================================================================
// ANIMATED CARD ENTRANCE
// Staggered fade + slide animation for cards
// ============================================================================

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
