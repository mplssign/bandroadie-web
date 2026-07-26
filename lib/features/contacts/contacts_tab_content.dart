import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../bands/active_band_controller.dart';
import '../home/widgets/home_app_bar.dart';
import '../members/member_vm.dart';
import '../members/members_controller.dart';
import '../shell/overlay_state.dart';
import '../../shared/widgets/segmented_toggle.dart';
import 'contacts_controller.dart';
import 'venues_controller.dart';
import 'widgets/band_member_edit_drawer.dart';
import 'widgets/band_members_view.dart';
import 'widgets/contacts_view.dart';
import 'widgets/invite_members_screen.dart';
import 'widgets/venues_view.dart';

// ============================================================================
// CONTACTS TAB CONTENT
// Container widget that replaces MembersTabContent in AppShell.
// Hosts a segmented toggle switching between Band, Venues, Contacts views.
// ============================================================================

class ContactsTabContent extends ConsumerStatefulWidget {
  const ContactsTabContent({super.key});

  @override
  ConsumerState<ContactsTabContent> createState() => _ContactsTabContentState();
}

class _ContactsTabContentState extends ConsumerState<ContactsTabContent>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _selectedSegment = 0;
  final Set<int> _loadedSegments = {0}; // Band is loaded by default

  @override
  void initState() {
    super.initState();

    // Entrance animation (matches MembersTabContent)
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

    // Load members data
    Future.microtask(() {
      final bandState = ref.read(activeBandProvider);
      if (bandState.activeBandId != null) {
        ref.read(membersProvider.notifier).loadMembers(bandState.activeBandId);
      }
    });

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

  Future<void> _onMembersRefresh() async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    await ref.read(membersProvider.notifier).refresh(bandId);
  }

  void _openInviteScreen() {
    final bandState = ref.read(activeBandProvider);
    if (bandState.activeBand != null) {
      Navigator.of(context).push(
        fadeSlideRoute(
          page: InviteMembersScreen(band: bandState.activeBand!),
        ),
      );
    }
  }

  void _openRoleManagement(MemberVM member) {
    final membersState = ref.read(membersProvider);
    final adminCount =
        membersState.members.where((m) => m.isAdmin && m.isActive).length;

    BandMemberEditDrawer.show(
      context,
      member: member,
      adminCount: adminCount,
    );
  }

  void _onSegmentChanged(int index) {
    if (index == _selectedSegment) return;
    setState(() => _selectedSegment = index);

    // Lazy-load data for newly selected segment
    if (!_loadedSegments.contains(index)) {
      _loadedSegments.add(index);
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        if (index == 1) {
          ref.read(venuesProvider.notifier).load(bandId);
        } else if (index == 2) {
          ref.read(contactsProvider.notifier).load(bandId);
        }
      }
    }
  }

  Widget _buildActiveView() {
    switch (_selectedSegment) {
      case 0:
        final membersState = ref.watch(membersProvider);
        final bandState = ref.watch(activeBandProvider);
        return BandMembersView(
          key: const ValueKey('band'),
          membersState: membersState,
          bandState: bandState,
          onRefresh: _onMembersRefresh,
          onInvite: _openInviteScreen,
          onManageRole: _openRoleManagement,
        );
      case 1:
        return const VenuesView(key: ValueKey('venues'));
      case 2:
        return const ContactsView(key: ValueKey('contacts'));
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bandState = ref.watch(activeBandProvider);
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Listen for band changes — reset state (Task 14)
    ref.listen<ActiveBandState>(activeBandProvider, (previous, next) {
      if (previous?.activeBandId != next.activeBandId &&
          next.activeBandId != null) {
        // Reset venues and contacts providers
        ref.read(venuesProvider.notifier).reset();
        ref.read(contactsProvider.notifier).reset();

        // Reset segment to Band
        setState(() {
          _selectedSegment = 0;
          _loadedSegments.clear();
          _loadedSegments.add(0);
        });

        // Reload members
        ref.read(membersProvider.notifier).loadMembers(next.activeBandId);
      }
    });

    return Stack(
      children: [
        // Scrollable content
        Positioned.fill(
          child: Column(
            children: [
              // Top padding for app bar
              SizedBox(
                height:
                    Spacing.appBarHeight + MediaQuery.of(context).padding.top,
              ),

              // Content with entrance animation
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
                        return false;
                      },
                      child: Column(
                        children: [
                          // Segmented toggle
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Spacing.pagePadding,
                              Spacing.space16,
                              Spacing.pagePadding,
                              0,
                            ),
                            child: SegmentedToggle(
                              labels: const ['Band', 'Venues', 'Contacts'],
                              selectedIndex: _selectedSegment,
                              onChanged: _onSegmentChanged,
                            ),
                          ),

                          const SizedBox(height: Spacing.space8),

                          // Active view with animated switching
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: AppDurations.normal,
                              switchInCurve: AppCurves.slideIn,
                              switchOutCurve: AppCurves.ease,
                              transitionBuilder: (child, animation) {
                                final slideAnimation = Tween<Offset>(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: slideAnimation,
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildActiveView(),
                            ),
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

        // Positioned app bar at top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: HomeAppBar(
            bandName:
                displayBand?.name ?? bandState.activeBand?.name ?? 'BandRoadie',
            onMenuTap: _openDrawer,
            onAvatarTap: _openBandSwitcher,
            bandAvatarColor:
                displayBand?.avatarColor ?? bandState.activeBand?.avatarColor,
            bandImageUrl:
                displayBand?.imageUrl ?? bandState.activeBand?.imageUrl,
            localImageFile: draftLocalImage,
          ),
        ),
      ],
    );
  }
}
