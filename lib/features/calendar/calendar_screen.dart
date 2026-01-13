import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/utils/event_permission_helper.dart';
import '../tips/tips_and_tricks_screen.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../bands/edit_band_screen.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../feedback/bug_report_screen.dart';
import '../gigs/gig_controller.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../profile/my_profile_screen.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../settings/settings_screen.dart';
import 'calendar_controller.dart';
import 'models/calendar_event.dart';
import 'widgets/add_block_out_drawer.dart';
import 'widgets/calendar_app_bar.dart';
import 'widgets/calendar_bottom_nav_bar.dart';
import 'widgets/calendar_event_card.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/day_detail_bottom_sheet.dart';

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

    // Reset gig/rehearsal state before band switch
    debugPrint('[Dashboard] activeBand changed: ${band.id}');
    ref.read(gigProvider.notifier).resetForBandChange();
    ref.read(rehearsalProvider.notifier).resetForBandChange();

    // Select the new band - this will trigger automatic refetch
    ref.read(activeBandProvider.notifier).selectBand(band);
  }

  void _handleAddEvent() {
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      initialType: EventType.rehearsal,
      onSaved: _refreshCalendarData,
    );
  }

  void _handleBlockOut() {
    final bandId = ref.read(activeBandProvider).activeBand?.id ?? '';
    BlockOutDrawer.show(
      context,
      ref: ref,
      bandId: bandId,
      mode: BlockOutDrawerMode.create,
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
    final bandState = ref.read(activeBandProvider);
    final bandId = bandState.activeBand?.id;

    // Block outs: open the block out drawer with permission check
    // Only the creator can edit/delete their own block out dates
    if (event.isBlockOut && event.blockOutSpan != null) {
      final currentUserId = supabase.auth.currentUser?.id;
      final permissionHelper = EventPermissionHelper(
        currentUserId: currentUserId,
      );
      final canEdit = permissionHelper.canEditEvent(event);

      BlockOutDrawer.show(
        context,
        ref: ref,
        bandId: bandId ?? '',
        mode: canEdit ? BlockOutDrawerMode.edit : BlockOutDrawerMode.viewOnly,
        existingBlockOut: event.blockOutSpan,
        onSaved: _refreshCalendarData,
      );
      return;
    }

    // Gigs and rehearsals: any band member can edit
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
      userName =
          currentUser?.userMetadata?['full_name'] as String? ??
          currentUser?.userMetadata?['name'] as String? ??
          'User';
    }
    final userEmail = currentUser?.email ?? '';

    // Build the main content
    final content = Scaffold(
      backgroundColor: AppColors.scaffoldBg,
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
                child: _buildContent(calendarState),
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

  Widget _buildContent(CalendarState calendarState) {
    if (calendarState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (calendarState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
            const SizedBox(height: Spacing.space16),
            Text(
              calendarState.error!,
              style: AppTextStyles.callout.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space16),
            TextButton(
              onPressed: () => ref.read(calendarProvider.notifier).loadEvents(),
              child: const Text('Retry'),
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
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.add_rounded,
                  label: 'Add Event',
                  onTap: _handleAddEvent,
                ),
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.block_rounded,
                  label: 'Block Out',
                  onTap: _handleBlockOut,
                ),
              ),
            ],
          ),

          const SizedBox(height: Spacing.space24),

          // This Month's Events section
          _EventsSection(
            events: calendarState.eventsForMonth,
            onEventTap: _openEditEventSheet,
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
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textPrimary, size: 20),
            const SizedBox(width: Spacing.space8),
            Text(label, style: AppTextStyles.button),
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
  final void Function(CalendarEvent event)? onEventTap;

  const _EventsSection({required this.events, this.onEventTap});

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
              color: AppColors.cardBgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    color: AppColors.textMuted,
                    size: 48,
                  ),
                  const SizedBox(height: Spacing.space12),
                  Text(
                    'No events this month',
                    style: AppTextStyles.callout.copyWith(
                      color: AppColors.textMuted,
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
                onTap: () => onEventTap?.call(event),
              ),
            ),
          ),
      ],
    );
  }
}
