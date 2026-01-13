import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../../components/ui/brand_action_button.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../../shared/utils/event_permission_helper.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../gigs/gig_controller.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../shell/overlay_state.dart';
import 'calendar_controller.dart';
import 'models/calendar_event.dart';
import 'widgets/add_block_out_drawer.dart';
import 'widgets/calendar_app_bar.dart';
import 'widgets/calendar_event_card.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/day_detail_bottom_sheet.dart';

// ============================================================================
// CALENDAR TAB CONTENT
// Content-only version for IndexedStack in AppShell.
// No Scaffold, no bottom nav - those are owned by AppShell.
// ============================================================================

class CalendarTabContent extends ConsumerStatefulWidget {
  const CalendarTabContent({super.key});

  @override
  ConsumerState<CalendarTabContent> createState() => _CalendarTabContentState();
}

class _CalendarTabContentState extends ConsumerState<CalendarTabContent>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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

    // Start entrance animation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    ref.read(overlayStateProvider.notifier).openMenuDrawer();
  }

  void _openBandSwitcher() {
    ref.read(overlayStateProvider.notifier).openBandSwitcher();
  }

  void _handleAddEvent() {
    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      initialType: EventType.rehearsal,
      onSaved: _refreshCalendarData,
    );
  }

  void _refreshCalendarData() {
    // Refresh rehearsals and gigs
    ref.read(rehearsalProvider.notifier).refresh();
    ref.read(gigProvider.notifier).refresh();
    ref.read(calendarProvider.notifier).loadEvents();
  }

  void _handleBlockOut() {
    final bandState = ref.read(activeBandProvider);
    final bandId = bandState.activeBand?.id;

    if (bandId == null) {
      showAppSnackBar(context, message: 'Please select a band first');
      return;
    }

    BlockOutDrawer.show(
      context,
      ref: ref,
      bandId: bandId,
      mode: BlockOutDrawerMode.create,
      onSaved: () {
        // Refresh calendar to show new block out markers
        _refreshCalendarData();
      },
    );
  }

  void _handleDayTap(DateTime date) {
    final calendarState = ref.read(calendarProvider);
    final eventsForDay = calendarState.eventsForDate(date);

    // If no events on this day, open Add Event drawer directly
    if (eventsForDay.isEmpty) {
      AddEditEventBottomSheet.show(
        context,
        ref: ref,
        initialType: EventType.rehearsal,
        initialDate: date,
        onSaved: _refreshCalendarData,
      );
      return;
    }

    // Otherwise show Day Detail with events
    DayDetailBottomSheet.show(
      context,
      date: date,
      events: eventsForDay,
      onEventTap: (event) {
        Navigator.of(context).pop(); // Close bottom sheet
        _openEditEventSheet(event);
      },
      onAddEvent: () {
        Navigator.of(context).pop(); // Close day detail sheet
        AddEditEventBottomSheet.show(
          context,
          ref: ref,
          initialType: EventType.rehearsal,
          initialDate: date,
          onSaved: _refreshCalendarData,
        );
      },
    );
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

    // Build the main content (no Scaffold - AppShell owns that)
    return Stack(
      children: [
        // Scrollable content
        Positioned.fill(
          child: Column(
            children: [
              // Top padding for app bar (app bar now includes safe area)
              SizedBox(
                height:
                    Spacing.appBarHeight + MediaQuery.of(context).padding.top,
              ),

              // Main scrollable content with scroll notification for glass effect
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification) {
                          ref
                              .read(scrollBlurProvider.notifier)
                              .updateFromOffset(notification.metrics.pixels);
                        }
                        return false; // Allow notification to continue bubbling
                      },
                      child: _buildContent(calendarState),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Positioned app bar at top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CalendarAppBar(
            bandName: displayBand?.name ?? bandState.activeBand?.name ?? '',
            bandAvatarColor:
                displayBand?.avatarColor ?? bandState.activeBand?.avatarColor,
            bandImageUrl:
                displayBand?.imageUrl ?? bandState.activeBand?.imageUrl,
            localImageFile: draftLocalImage,
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
          ),
        ),
      ],
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

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBg,
      onRefresh: () async {
        await ref.read(rehearsalProvider.notifier).refresh();
        await ref.read(gigProvider.notifier).refresh();
        ref.read(calendarProvider.notifier).loadEvents();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
                child: BrandActionButton(
                  icon: Icons.add_rounded,
                  label: 'Add Event',
                  onPressed: _handleAddEvent,
                ),
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: BrandActionButton(
                  icon: Icons.block_rounded,
                  label: 'Block Out',
                  onPressed: _handleBlockOut,
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
    ),
    );
  }
}

// ============================================================================
// ACTION BUTTON
// ============================================================================

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
