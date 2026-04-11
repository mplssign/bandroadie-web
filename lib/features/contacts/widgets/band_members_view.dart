import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../bands/active_band_controller.dart';
import '../../members/members_controller.dart';
import '../../members/member_vm.dart';
import '../../members/widgets/member_card.dart';
import '../../members/widgets/member_card_skeleton.dart';
import '../../members/widgets/members_empty_state.dart';

// ============================================================================
// BAND MEMBERS VIEW
// Extracted member list view used within ContactsTabContent.
// Reuses existing member widgets — does NOT modify any members/ files.
// ============================================================================

class BandMembersView extends StatelessWidget {
  final MembersState membersState;
  final ActiveBandState bandState;
  final Future<void> Function() onRefresh;
  final VoidCallback onInvite;
  final void Function(MemberVM) onManageRole;

  const BandMembersView({
    super.key,
    required this.membersState,
    required this.bandState,
    required this.onRefresh,
    required this.onInvite,
    required this.onManageRole,
  });

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (membersState.isLoading && !membersState.hasMembers) {
      return _buildLoadingState();
    }

    // Error state
    if (membersState.error != null && !membersState.hasMembers) {
      return _buildErrorState(membersState.error!);
    }

    // Empty state
    if (!membersState.hasMembers) {
      return MembersEmptyState(onInviteTap: onInvite);
    }

    // Members list
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceDark,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.space24,
                Spacing.pagePadding,
                Spacing.space8,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Band Members',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(AppIcons.add, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (membersState.hasMembers)
            SliverPadding(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final member = membersState.members[index];
                  return Padding(
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
                      showAdminActions: membersState.isCurrentUserAdmin,
                      onManageRole: () => onManageRole(member),
                      onTap: () {},
                    ),
                  );
                }, childCount: membersState.members.length),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: Spacing.space48 +
                  Spacing.bottomNavHeight +
                  MediaQuery.of(context).padding.bottom +
                  32,
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
              AppIcons.error,
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
              onPressed: onRefresh,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
