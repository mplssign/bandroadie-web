import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../../components/ui/brand_action_button.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../../shared/utils/event_permission_helper.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../bands/band_full_state.dart';
import '../events/models/event_form_data.dart';
import '../events/widgets/add_edit_event_bottom_sheet.dart';
import '../gigs/gig_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../members/permissions/band_permissions.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../shell/overlay_state.dart';
import 'calendar_controller.dart';
import 'models/calendar_event.dart';

import 'widgets/calendar_app_bar.dart';
import 'widgets/calendar_event_card.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/calendar_subscription_dialog.dart';
import 'widgets/day_detail_bottom_sheet.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

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
    // RBAC self-defense: verify permission before opening event editor
    final permissionsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permissionsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, _) => null,
    );
    if (perms == null) return; // Still loading — no-op
    if (perms.isContributor && !perms.canCreateGigs) {
      showAppSnackBar(
        context,
        message: 'You don\'t have permission to create events.',
      );
      return;
    }

    // Contributors can only create gigs, not rehearsals
    final eventType = perms.isContributor ? EventType.gig : EventType.rehearsal;

    AddEditEventBottomSheet.show(
      context,
      ref: ref,
      initialType: eventType,
      onSaved: _refreshCalendarData,
    );
  }

  void _refreshCalendarData() {
    debugPrint('[CalendarTabContent] _refreshCalendarData called');
    // Refresh rehearsals and gigs
    ref.read(rehearsalProvider.notifier).refresh();
    ref.read(gigProvider.notifier).refresh();
    ref.read(calendarProvider.notifier).loadEvents();
  }

  void _handleDayTap(DateTime date) {
    final calendarState = ref.read(calendarProvider);
    final eventsForDay = calendarState.eventsForDate(date);

    // RBAC: Check if contributor can create events
    final permissionsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permissionsAsync.whenOrNull(data: (p) => p);

    // If no events on this day, open Add Event drawer directly
    if (eventsForDay.isEmpty) {
      // Contributor without gig permission: show snackbar instead
      if (perms != null && perms.isContributor && !perms.canCreateGigs) {
        showAppSnackBar(
          context,
          message: 'You don\'t have permission to create events.',
        );
        return;
      }

      // Contributors can only create gigs, not rehearsals
      final eventType =
          (perms?.isContributor == true) ? EventType.gig : EventType.rehearsal;

      AddEditEventBottomSheet.show(
        context,
        ref: ref,
        initialType: eventType,
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
      bandTimezone: ref.read(activeBandProvider).activeBand?.timezone ??
          'America/Chicago',
      onEventTap: (event) {
        Navigator.of(context).pop(); // Close bottom sheet
        _openEditEventSheet(event);
      },
      // RBAC: Only pass onAddEvent if user has permission to create events
      onAddEvent: (perms != null && perms.canCreateGigs)
          ? () {
              Navigator.of(context).pop(); // Close day detail sheet
              // Contributors can only create gigs, not rehearsals
              final eventType =
                  perms.isContributor ? EventType.gig : EventType.rehearsal;
              AddEditEventBottomSheet.show(
                context,
                ref: ref,
                initialType: eventType,
                initialDate: date,
                onSaved: _refreshCalendarData,
              );
            }
          : null,
    );
  }

  /// Open the Edit Event drawer for an existing calendar event
  void _openEditEventSheet(CalendarEvent event) {
    // Block outs: open the event editor with permission check
    // Only the creator can edit/delete their own block out dates
    if (event.isBlockOut && event.blockOutSpan != null) {
      final currentUserId = supabase.auth.currentUser?.id;
      final permissionHelper = EventPermissionHelper(
        currentUserId: currentUserId,
      );
      final canEdit = permissionHelper.canEditEvent(event);

      AddEditEventBottomSheet.show(
        context,
        ref: ref,
        mode: canEdit ? EventFormMode.edit : EventFormMode.create,
        initialType: EventType.blockOut,
        existingBlockOut: event.blockOutSpan,
        viewOnly: !canEdit,
        onSaved: _refreshCalendarData,
      );
      return;
    }

    // Gigs and rehearsals: check edit permissions
    final editPermsAsync = ref.read(currentUserPermissionsProvider);
    final editPerms = editPermsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, _) => null,
    );
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

    // RBAC: Watch permissions for calendar action gating
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final perms = permissionsAsync.when(
      data: (p) => p,
      loading: () =>
          null, // null while loading — hide buttons to prevent flicker
      error: (_, _) => null,
    );

    debugPrint(
      '[CalendarTabContent] build called with ${calendarState.allEvents.length} events, ${calendarState.eventsForMonth.length} this month',
    );

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
                      child: _buildContent(calendarState, perms),
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

  /// Build action buttons based on permissions.
  /// Admin/Member/Contributor with permissions: single "Add Event" button.
  /// Contributor without canCreateGigs: no buttons.
  /// While permissions are loading (perms == null): no buttons to prevent flicker.
  Widget _buildActionButtons(BandPermissions? perms) {
    if (perms == null) {
      // Loading — hide buttons to prevent flicker
      return const SizedBox.shrink();
    }

    if (perms.isContributor && !perms.canCreateGigs) {
      // Contributor without gig permission: no buttons
      return const SizedBox.shrink();
    }

    // Single "Add Event" button for all permitted roles
    return BrandActionButton(
      icon: AppIcons.add,
      label: 'Add Event',
      onPressed: _handleAddEvent,
    );
  }

  Widget _buildContent(CalendarState calendarState, BandPermissions? perms) {
    if (calendarState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
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
            TextButton(
              onPressed: () => ref.read(calendarProvider.notifier).loadEvents(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        ref.invalidate(bandFullStateProvider);
        await ref.read(bandFullStateProvider.future);
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
              onNextMonth: () =>
                  ref.read(calendarProvider.notifier).nextMonth(),
              onDayTap: _handleDayTap,
            ),

            const SizedBox(height: Spacing.space16),

            // Action buttons row — permission-gated
            _buildActionButtons(perms),

            // + Subscribe to Calendar text button
            const SizedBox(height: Spacing.space16),
            Center(
              child: GestureDetector(
                onTap: () {
                  final bandState = ref.read(activeBandProvider);
                  final bandId = bandState.activeBand?.id;
                  final bandName = bandState.activeBand?.name ?? 'Band';
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
                      fontSize: 14,
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
              bandTimezone:
                  ref.watch(activeBandProvider).activeBand?.timezone ??
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
  final String bandTimezone;
  final void Function(CalendarEvent event)? onEventTap;

  const _EventsSection(
      {required this.events, required this.bandTimezone, this.onEventTap});

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
