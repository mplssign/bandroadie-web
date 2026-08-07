import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/app_scaffold.dart';
import '../../components/ui/app_progress_indicator.dart';
import '../../components/ui/app_button.dart';
import '../../shared/utils/event_permission_helper.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../tips/tips_and_tricks_screen.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../bands/edit_band_screen.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../feedback/bug_report_screen.dart';
import '../gigs/gig_controller.dart';
import '../gigs/widgets/view_gig_drawer.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../profile/my_profile_screen.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../settings/settings_screen.dart';
import 'calendar_controller.dart';
import 'models/calendar_event.dart';
import 'widgets/add_block_out_drawer.dart';
import 'widgets/view_block_out_drawer.dart';
import 'widgets/calendar_app_bar.dart';
import 'widgets/calendar_subscription_dialog.dart';
import 'widgets/calendar_bottom_nav_bar.dart';
import 'widgets/calendar_event_card.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/day_detail_bottom_sheet.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CALENDAR SCREEN
// Monthly calendar view showing gigs and rehearsals.
// Figma: "Calendar" artboard
//
// Features:
// - Monthly calendar grid with navigation
// - Event indicators (blue = rehearsal, green = gig)
// - Today highlighted with rose accent
// - "This Month's Events" section
// - Action buttons: "+ Add Event", "+ Block Out"
// ============================================================================

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
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
      debugPrint('[CalendarScreen] Failed to load user profile: $e');
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await ref.read(activeBandProvider.notifier).reset();
    ref.read(calendarProvider.notifier).reset();
    await supabase.auth.signOut();
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

    final currentBandId = ref.read(activeBandIdProvider);
    if (band.id == currentBandId) return;

    // Reset gig/rehearsal state before band switch
    debugPrint('[Dashboard] activeBand changed: ${band.id}');
    ref.read(gigProvider.notifier).resetForBandChange();
    ref.read(rehearsalProvider.notifier).resetForBandChange();

    // Select the new band - this will trigger automatic refetch
    ref.read(activeBandProvider.notifier).selectBand(band);
  }

  void _handleAddEvent() {
    // RBAC: Check permissions before opening event editor
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, __) => null,
    );
    if (perms == null) return;
    if (perms.isContributor && !perms.canCreateGigs) return;

    // Contributors can only create gigs, not rehearsals
    final eventType = perms.isContributor ? EventType.gig : EventType.rehearsal;

    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      initialType: eventType,
      onSaved: _refreshCalendarData,
    );
  }

  void _handleDayTap(DateTime date) {
    final calendarState = ref.read(calendarProvider);
    final eventsForDay = calendarState.eventsForDate(date);

    if (eventsForDay.isNotEmpty) {
      DayDetailBottomSheet.show(
        context,
        date: date,
        events: eventsForDay,
        bandTimezone: ref.read(activeBandProvider).activeBand?.timezone ??
            'America/Chicago',
        onEventTap: (event) {
          Navigator.of(context).pop(); // Close bottom sheet
          _openEditEventSheet(event);
        },
      );
    }
  }

  /// Refresh calendar data after changes
  void _refreshCalendarData() {
    ref.read(calendarProvider.notifier).loadEvents(forceRefresh: true);
  }

  /// Open the Edit Event drawer for an existing calendar event
  void _openEditEventSheet(CalendarEvent event) {
    // Block outs: open the dedicated BlockOutDrawer with permission check
    // Only the creator can edit/delete their own block out dates
    if (event.isBlockOut && event.blockOutSpan != null) {
      final currentUserId = supabase.auth.currentUser?.id;
      final permissionHelper = EventPermissionHelper(
        currentUserId: currentUserId,
      );
      final canEdit = permissionHelper.canEditEvent(event);
      final activeBandId = ref.read(activeBandProvider).activeBand?.id;

      if (activeBandId == null) return;

      ViewBlockOutDrawer.show(
        context,
        existingBlockOut: event.blockOutSpan!,
        canEdit: canEdit,
        onEdit: () {
          BlockOutDrawer.show(
            context,
            ref: ref,
            bandId: activeBandId,
            mode: BlockOutDrawerMode.edit,
            existingBlockOut: event.blockOutSpan,
            onSaved: _refreshCalendarData,
          );
        },
      );
      return;
    }

    // Gigs and rehearsals: check edit permissions
    final editPermsAsync = ref.read(currentUserPermissionsProvider);
    final editPerms = editPermsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, __) => null,
    );

    // Confirmed gigs: show read-only view drawer first
    if (event.isConfirmedGig && event.gig != null) {
      final bandTimezone = ref.read(activeBandProvider).activeBand?.timezone ??
          'America/Chicago';
      final canEdit = editPerms != null && editPerms.canEditGigs;
      ViewGigDrawer.show(
        context,
        gig: event.gig!,
        bandTimezone: bandTimezone,
        canEdit: canEdit,
        onEdit: () => AddEditEventBottomSheet.show(
          context,
          ref: ref,
          mode: EventFormMode.edit,
          initialType: EventType.gig,
          existingEventId: event.id,
          initialData: EventFormData.fromCalendarEvent(event),
          onSaved: _refreshCalendarData,
        ),
      );
      return;
    }

    // Allow contributors to edit potential gigs they can create
    final canEditEvent = editPerms != null &&
        (editPerms.canEditGigs ||
            (event.isPotentialGig && editPerms.canEditPotentialGigs));
    if (!canEditEvent) return;

    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      mode: EventFormMode.edit,
      initialType: event.isGig ? EventType.gig : EventType.rehearsal,
      existingEventId: event.id,
      initialData: EventFormData.fromCalendarEvent(event),
      onSaved: _refreshCalendarData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandState = ref.watch(activeBandProvider);
    final calendarState = ref.watch(calendarProvider);

    // RBAC: Watch permissions for action button gating
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final isContributor = permissionsAsync.when(
      data: (p) => p.isContributor,
      loading: () => true, // Fail-closed while loading
      error: (_, __) => true,
    );
    final canCreateGig = permissionsAsync.when(
      data: (p) => p.canCreateGigs,
      loading: () => false,
      error: (_, __) => false,
    );

    // Watch display band for header avatar (shows draft during editing)
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Get current user info for drawer
    final currentUser = supabase.auth.currentUser;
    String userName;
    if (_userFirstName != null || _userLastName != null) {
      userName = '${_userFirstName ?? ''} ${_userLastName ?? ''}'.trim();
      if (userName.isEmpty) userName = 'User';
    } else {
      userName = currentUser?.userMetadata?['full_name'] as String? ??
          currentUser?.userMetadata?['name'] as String? ??
          'User';
    }
    final userEmail = currentUser?.email ?? '';

    // Build the main content
    final content = AppScaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          // Safe area padding at top
          SizedBox(height: MediaQuery.of(context).padding.top),

          // App bar
          CalendarAppBar(
            bandName: displayBand?.name ?? bandState.activeBand?.name ?? '',
            bandAvatarColor:
                displayBand?.avatarColor ?? bandState.activeBand?.avatarColor,
            bandImageUrl:
                displayBand?.imageUrl ?? bandState.activeBand?.imageUrl,
            localImageFile: draftLocalImage,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
          ),

          // Main scrollable content
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildContent(calendarState,
                    isContributor: isContributor, canCreateGig: canCreateGig),
              ),
            ),
          ),

          // Bottom nav bar
          const CalendarBottomNavBar(),
        ],
      ),
    );

    // Wrap with DrawerOverlay for side navigation
    return DrawerOverlay(
      isOpen: _isDrawerOpen,
      onClose: _closeDrawer,
      userName: userName,
      userEmail: userEmail,
      onProfileTap: () {
        _closeDrawer();
        // Use custom fade+slide transition for smooth navigation
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const MyProfileScreen()));
      },
      onSettingsTap: () {
        _closeDrawer();
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
        _closeDrawer();
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

  Widget _buildContent(CalendarState calendarState,
      {required bool isContributor, required bool canCreateGig}) {
    if (calendarState.isLoading) {
      return const Center(
        child: AppProgressIndicator(
          type: ProgressIndicatorType.circular,
          color: AppColors.primary,
        ),
      );
    }

    if (calendarState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.error, color: AppColors.error, size: 48),
            const SizedBox(height: Spacing.space16),
            Text(
              calendarState.error!,
              style: AppTextStyles.callout
                  .copyWith(color: context.colors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space16),
            AppButton(
              label: 'Retry',
              variant: AppButtonVariant.text,
              onPressed: () => ref.read(calendarProvider.notifier).loadEvents(),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.space16),

          // Calendar grid with swipe and day tap support
          CalendarGrid(
            selectedMonth: calendarState.selectedMonth,
            calendarState: calendarState,
            onPreviousMonth: () =>
                ref.read(calendarProvider.notifier).previousMonth(),
            onNextMonth: () => ref.read(calendarProvider.notifier).nextMonth(),
            onDayTap: _handleDayTap,
          ),

          const SizedBox(height: Spacing.space16),

          // Action buttons row
          // Admin/Member/Contributor with permissions: single "Add Event" button
          // Contributor without canCreateGigs: no buttons
          if (!isContributor || canCreateGig) ...[
            _ActionButton(
              icon: AppIcons.add,
              label: 'Add Event',
              onTap: _handleAddEvent,
            ),
          ],

          // Subscribe to Calendar link
          const SizedBox(height: Spacing.space16),
          Center(
            child: GestureDetector(
              onTap: () {
                final activeBand = ref.read(activeBandProvider).activeBand;
                final bandId = activeBand?.id;
                final bandName = activeBand?.name ?? 'Band';
                if (bandId != null) {
                  showCalendarSubscriptionDialog(
                    context,
                    ref,
                    bandId: bandId,
                    bandName: bandName,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.space16,
                  vertical: Spacing.space8,
                ),
                child: Text(
                  '+ Subscribe to Calendar',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: Spacing.space24),

          // This Month's Events section
          _EventsSection(
            events: calendarState.eventsForMonth,
            bandTimezone: ref.watch(activeBandProvider).activeBand?.timezone ??
                'America/Chicago',
            onEventTap: _openEditEventSheet,
          ),

          // Bottom padding for nav bar (extra space to scroll past)
          SizedBox(
            height: Spacing.space48 +
                Spacing.bottomNavHeight +
                MediaQuery.of(context).padding.bottom +
                32, // Extra scroll clearance
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ACTION BUTTON
// ============================================================================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: Spacing.space8),
            Text(label,
                style: AppTextStyles.button.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EVENTS SECTION
// ============================================================================

class _EventsSection extends StatelessWidget {
  final List<CalendarEvent> events;
  final String bandTimezone;
  final void Function(CalendarEvent event)? onEventTap;

  const _EventsSection({
    required this.events,
    required this.bandTimezone,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Text("This Month's Events", style: AppTextStyles.title3),
        const SizedBox(height: Spacing.space12),

        if (events.isEmpty)
          Container(
            padding: const EdgeInsets.all(Spacing.space24),
            decoration: BoxDecoration(
              color: context.colors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    AppIcons.calendarCheck,
                    color: context.colors.textMuted,
                    size: 48,
                  ),
                  const SizedBox(height: Spacing.space12),
                  Text(
                    'No events this month',
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.space12),
              child: CalendarEventCard(
                event: event,
                bandTimezone: bandTimezone,
                onTap: () => onEventTap?.call(event),
              ),
            ),
          ),
      ],
    );
  }
}
