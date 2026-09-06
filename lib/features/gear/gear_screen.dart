import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_button.dart';

import '../bands/active_band_controller.dart';
import '../members/member_vm.dart';
import '../members/members_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../setlists/widgets/back_only_app_bar.dart';
import 'gear_controller.dart';
import 'models/gear_item.dart';
import 'widgets/gear_empty_state.dart';
import 'widgets/gear_form_sheet.dart';
import 'widgets/gear_row.dart';

class GearScreen extends ConsumerStatefulWidget {
  const GearScreen({super.key});

  @override
  ConsumerState<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends ConsumerState<GearScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(gearProvider.notifier).load(bandId);
        ref.read(membersProvider.notifier).loadMembers(bandId);
      }
    });
  }

  Future<void> _refresh() async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    await ref.read(gearProvider.notifier).refresh(bandId);
  }

  Future<void> _openForm({GearItem? item, required bool canManageGear}) async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    final result = await GearFormSheet.show(
      context,
      bandId: bandId,
      item: item,
      canManageGear: canManageGear,
    );

    if (result == true) {
      if (!mounted) return;
      await ref.read(gearProvider.notifier).refresh(bandId);
    }
  }

  String _memberOwnedLabel(String? ownerUserId, List<MemberVM> members) {
    if (ownerUserId == null) return 'Member-owned';

    MemberVM? member;
    for (final m in members) {
      if (m.userId == ownerUserId) {
        member = m;
        break;
      }
    }
    if (member == null) return 'Member-owned';

    final first = (member.firstName ?? '').trim();
    final last = (member.lastName ?? '').trim();

    if (first.isNotEmpty && last.isNotEmpty) {
      return '$first ${last[0]}.';
    }
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return '${last[0]}.';
    return member.name;
  }

  String _ownerLabel(GearItem item, List<MemberVM> members) {
    if (item.ownerType == GearOwnerType.band) {
      return 'Band-owned';
    }
    return _memberOwnedLabel(item.ownerUserId, members);
  }

  @override
  Widget build(BuildContext context) {
    final gearState = ref.watch(gearProvider);
    final bandState = ref.watch(activeBandProvider);
    final membersState = ref.watch(membersProvider);
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);

    final canManageGear = permissionsAsync.when(
      data: (p) => p.canManageGear,
      loading: () => false,
      error: (_, __) => false,
    );

    ref.listen<ActiveBandState>(activeBandProvider, (previous, next) {
      if (previous?.activeBandId != next.activeBandId) {
        ref.read(gearProvider.notifier).reset();
        if (next.activeBandId != null) {
          ref.read(gearProvider.notifier).load(next.activeBandId);
          ref.read(membersProvider.notifier).loadMembers(next.activeBandId);
        }
      }
    });

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackOnlyAppBar(onBack: () => Navigator.of(context).pop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.space20,
                Spacing.pagePadding,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gear',
                      style: AppTextStyles.pageTitle.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  if (canManageGear)
                    TextButton.icon(
                      onPressed: () => _openForm(canManageGear: true),
                      icon: const Icon(AppIcons.add, size: 18),
                      label: const Text('Add Gear'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.space12),
            Expanded(
              child: _buildContent(
                gearState: gearState,
                bandId: bandState.activeBandId,
                canManageGear: canManageGear,
                members: membersState.members,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required GearState gearState,
    required String? bandId,
    required bool canManageGear,
    required List<MemberVM> members,
  }) {
    if (bandId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
          child: Text(
            'No band selected. Pick a band to view your gear inventory.',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: AppFontSizes.body,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (gearState.isLoading && !gearState.hasItems) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (gearState.error != null && !gearState.hasItems) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
              child: Text(
                gearState.error!,
                style: TextStyle(color: context.colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Spacing.space12),
            AppButton(
              label: 'Retry',
              variant: AppButtonVariant.text,
              onPressed: _refresh,
            ),
          ],
        ),
      );
    }

    if (!gearState.hasItems) {
      return GearEmptyState(
        canManageGear: canManageGear,
        onAddTap: canManageGear ? () => _openForm(canManageGear: true) : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      backgroundColor: context.colors.surface,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          Spacing.pagePadding,
          Spacing.space8,
          Spacing.pagePadding,
          Spacing.bottomNavHeight + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: gearState.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: Spacing.space12),
        itemBuilder: (context, index) {
          final item = gearState.items[index];
          return GearRow(
            item: item,
            ownerLabel: _ownerLabel(item, members),
            onTap: () => _openForm(item: item, canManageGear: canManageGear),
          );
        },
      ),
    );
  }
}
