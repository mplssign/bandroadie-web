import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../bands/active_band_controller.dart';
import '../venues_controller.dart';
import 'venue_card.dart';
import 'venue_form_screen.dart';
import 'venues_empty_state.dart';

// ============================================================================
// VENUES VIEW
// List view for venues, backed by venuesProvider.
// ============================================================================

class VenuesView extends ConsumerStatefulWidget {
  const VenuesView({super.key});

  @override
  ConsumerState<VenuesView> createState() => _VenuesViewState();
}

class _VenuesViewState extends ConsumerState<VenuesView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(venuesProvider.notifier).load(bandId);
      }
    });
  }

  Future<void> _onRefresh() async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    await ref.read(venuesProvider.notifier).refresh(bandId);
  }

  Future<void> _openVenueForm({
    required BuildContext context,
    venue,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      fadeSlideRoute(page: VenueFormScreen(venue: venue)),
    );
    if (result == true) {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(venuesProvider.notifier).refresh(bandId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final venuesState = ref.watch(venuesProvider);

    // Loading state
    if (venuesState.isLoading && !venuesState.hasVenues) {
      return _buildLoadingState();
    }

    // Error state
    if (venuesState.error != null && !venuesState.hasVenues) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              venuesState.error!,
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _onRefresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (!venuesState.hasVenues) {
      return VenuesEmptyState(
        onAddTap: () => _openVenueForm(context: context),
      );
    }

    // Venues list
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      backgroundColor: context.colors.surface,
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
                  Expanded(
                    child: Text(
                      'Venues',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openVenueForm(context: context),
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
          SliverPadding(
            padding: const EdgeInsets.all(Spacing.pagePadding),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final venue = venuesState.venues[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < venuesState.venues.length - 1
                          ? Spacing.space16
                          : 0,
                    ),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: index * 50),
                      child: VenueCard(
                        venue: venue,
                        onTap: () =>
                            _openVenueForm(context: context, venue: venue),
                      ),
                    ),
                  );
                },
                childCount: venuesState.venues.length,
              ),
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
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: context.colors.border.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}
