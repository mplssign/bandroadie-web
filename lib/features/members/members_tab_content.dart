import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../../shared/scroll/scroll_blur_notifier.dart';
import '../bands/active_band_controller.dart';
import '../bands/band_form_screen.dart';
import '../home/widgets/home_app_bar.dart';
import '../shell/overlay_state.dart';
import 'members_controller.dart';
import 'widgets/member_card.dart';
import 'widgets/member_card_skeleton.dart';
import 'widgets/members_empty_state.dart';

// ============================================================================
// MEMBERS TAB CONTENT
// Shows all band members in large polished cards.
// Includes hamburger menu, band switcher, pull-to-refresh.
// ============================================================================

class MembersTabContent extends ConsumerStatefulWidget {
  const MembersTabContent({super.key});

  @override
  ConsumerState<MembersTabContent> createState() => _MembersTabContentState();
}

class _MembersTabContentState extends ConsumerState<MembersTabContent>
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

    // Load data
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

  Future<void> _onRefresh() async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    await ref.read(membersProvider.notifier).refresh(bandId);
  }

  void _openInviteScreen() {
    final bandState = ref.read(activeBandProvider);
    if (bandState.activeBand != null) {
      // Use custom fade+slide transition for smooth navigation
      Navigator.of(context).push(
        fadeSlideRoute(
          page: BandFormScreen(
            mode: BandFormMode.edit,
            initialBand: bandState.activeBand,
          ),
        ),
      );
    }
  }

  Future<void> _removeMember(String memberId) async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId != null) {
      final success = await ref
          .read(membersProvider.notifier)
          .removeMember(memberId, bandId);

      if (mounted) {
        if (success) {
          showSuccessSnackBar(context, message: 'Member removed');
        } else {
          showErrorSnackBar(context, message: 'Failed to remove member');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bandState = ref.watch(activeBandProvider);
    final membersState = ref.watch(membersProvider);
    final displayBand = ref.watch(displayBandProvider);
    final draftLocalImage = ref.watch(draftLocalImageProvider);

    // Listen for band changes
    ref.listen<ActiveBandState>(activeBandProvider, (previous, next) {
      if (previous?.activeBandId != next.activeBandId &&
          next.activeBandId != null) {
        ref.read(membersProvider.notifier).loadMembers(next.activeBandId);
      }
    });

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

              // Content with scroll notification for glass effect
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
                      child: _buildContent(membersState, bandState),
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

  Widget _buildContent(MembersState membersState, ActiveBandState bandState) {
    // Loading state
    if (membersState.isLoading && !membersState.hasMembers) {
      return _buildLoadingState();
    }

    // Error state
    if (membersState.error != null && !membersState.hasMembers) {
      return _buildErrorState(membersState.error!);
    }

    // Empty state (no members)
    if (!membersState.hasMembers) {
      return MembersEmptyState(onInviteTap: _openInviteScreen);
    }

    // Members list with optional pending invites section
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceDark,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ============================================
          // SECTION 1: MEMBERS
          // ============================================
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.space24,
                Spacing.pagePadding,
                Spacing.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Members',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Everyone in this band. Try not to break up before the next gig.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Members list
          if (membersState.hasMembers)
            SliverPadding(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final member = membersState.members[index];
                  return Padding(
                    // Key ensures rebuild when member data changes
                    key: ValueKey(
                      'member_${member.memberId}_${member.musicalRoles.join(',')}',
                    ),
                    padding: EdgeInsets.only(
                      bottom: index < membersState.members.length - 1
                          ? Spacing.space16
                          : 0,
                    ),
                    child: MemberCard(
                      member: member,
                      showRemoveOption: membersState.isCurrentUserAdmin,
                      onRemove: () => _removeMember(member.memberId),
                      onTap: () {
                        // TODO: Open member detail in future
                      },
                    ),
                  );
                }, childCount: membersState.members.length),
              ),
            ),

          // NOTE: Pending invites are shown in Edit Band screen, not here
          // Only actual band members (completed profile) appear on this page

          // Bottom padding for nav bar (extra space to scroll past)
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  Spacing.space48 +
                  Spacing.bottomNavHeight +
                  MediaQuery.of(context).padding.bottom +
                  32, // Extra scroll clearance
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index < 2 ? Spacing.space16 : 0),
          child: const MemberCardSkeleton(),
        );
      },
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                final bandId = ref.read(activeBandProvider).activeBandId;
                ref.read(membersProvider.notifier).loadMembers(bandId);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
