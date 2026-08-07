import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../bands/active_band_controller.dart';
import '../models/venue.dart';
import '../venues_controller.dart';
import 'az_index_column.dart';
import 'az_list_helpers.dart';
import 'az_search_field.dart';
import 'az_section_header.dart';
import 'venue_card.dart';
import 'venue_detail_screen.dart';
import 'venue_form_screen.dart';
import 'venues_empty_state.dart';
import '../../../components/ui/app_button.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openVenueDetail({
    required BuildContext context,
    required Venue venue,
  }) async {
    final needsRefresh = await Navigator.of(context).push<bool>(
      fadeSlideRoute(page: VenueDetailScreen(venue: venue)),
    );
    if (needsRefresh == true) {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(venuesProvider.notifier).refresh(bandId);
      }
    }
  }

  int _calculateItemCount(
    bool isSearching,
    List<Venue> venues,
    Map<String, List<Venue>> grouped,
  ) {
    if (isSearching) {
      // flat venues + bottom spacer (no title/search in list anymore)
      return venues.length + 1;
    } else {
      // sectioned venues (headers + venues) + bottom spacer
      int count = 0;
      for (final section in grouped.entries) {
        count += 1; // section header
        count += section.value.length; // venues
      }
      count += 1; // bottom spacer
      return count;
    }
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    bool isSearching,
    List<Venue> venues,
    Map<String, List<Venue>> grouped,
  ) {
    // Right padding accounts for index column (40px)
    const double rightPadding = Spacing.pagePadding + 40;

    if (isSearching) {
      // Flat filtered list: index 0+ are venues
      if (index < venues.length) {
        final venue = venues[index];
        return Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.pagePadding,
            0,
            rightPadding,
            index < venues.length - 1 ? Spacing.space16 : 0,
          ),
          child: FadeSlideIn(
            delay: Duration(milliseconds: index * 50),
            child: VenueCard(
              venue: venue,
              onTap: () => _openVenueDetail(
                context: context,
                venue: venue,
              ),
            ),
          ),
        );
      } else {
        // Bottom spacer
        return SizedBox(
          height: Spacing.space48 +
              Spacing.bottomNavHeight +
              MediaQuery.of(context).padding.bottom +
              32,
        );
      }
    } else {
      // Sectioned list: calculate which section and item
      final sections = grouped.entries.toList();

      int currentIndex = 0;
      for (int sectionIdx = 0; sectionIdx < sections.length; sectionIdx++) {
        final section = sections[sectionIdx];

        // Section header
        if (index == currentIndex) {
          return AzSectionHeader(
            letter: section.key,
            rightPadding: rightPadding,
          );
        }
        currentIndex++;

        // Venues in section
        if (index < currentIndex + section.value.length) {
          final venueIdx = index - currentIndex;
          final venue = section.value[venueIdx];
          return Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.pagePadding,
              0,
              rightPadding,
              venueIdx < section.value.length - 1
                  ? Spacing.space16
                  : Spacing.space24,
            ),
            child: VenueCard(
              venue: venue,
              onTap: () => _openVenueDetail(
                context: context,
                venue: venue,
              ),
            ),
          );
        }
        currentIndex += section.value.length;
      }

      // Bottom spacer
      return SizedBox(
        height: Spacing.space48 +
            Spacing.bottomNavHeight +
            MediaQuery.of(context).padding.bottom +
            32,
      );
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
            AppButton(
              label: 'Retry',
              variant: AppButtonVariant.text,
              onPressed: _onRefresh,
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
    final isSearching = venuesState.searchQuery.isNotEmpty;
    final displayVenues =
        isSearching ? venuesState.filteredVenues : venuesState.venues;
    final grouped = isSearching
        ? const <String, List<Venue>>{}
        : groupByLetter(displayVenues, (v) => v.name);

    // Handle empty search results
    if (isSearching && displayVenues.isEmpty) {
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
                        style: AppTextStyles.pageTitle.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    AppButton(
                      label: 'Add',
                      icon: AppIcons.add,
                      variant: AppButtonVariant.text,
                      onPressed: () => _openVenueForm(context: context),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.pagePadding,
                  0,
                  Spacing.pagePadding + 40,
                  Spacing.space16,
                ),
                child: _buildSearchBar(context, venuesState),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      AppIcons.search,
                      size: 64,
                      color: context.colors.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No venues found',
                      style: TextStyle(
                        fontSize: AppFontSizes.title,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      backgroundColor: context.colors.surface,
      child: Stack(
        children: [
          Column(
            children: [
              // Fixed title row
              Padding(
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
                        style: AppTextStyles.pageTitle.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    AppButton(
                      label: 'Add',
                      icon: AppIcons.add,
                      variant: AppButtonVariant.text,
                      onPressed: () => _openVenueForm(context: context),
                    ),
                  ],
                ),
              ),
              // Fixed search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.pagePadding,
                  0,
                  Spacing.pagePadding + 40,
                  Spacing.space16,
                ),
                child: _buildSearchBar(context, venuesState),
              ),
              // Scrollable venues list
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount:
                      _calculateItemCount(isSearching, displayVenues, grouped),
                  itemBuilder: (context, index) {
                    return _buildItem(
                        context, index, isSearching, displayVenues, grouped);
                  },
                ),
              ),
            ],
          ),
          // A-Z Index column (only visible when not searching)
          if (!isSearching) _buildIndexColumn(context, displayVenues, grouped),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, VenuesState venuesState) {
    return AzSearchField(
      controller: _searchController,
      hintText: 'Search venues, names, cities',
      currentQuery: venuesState.searchQuery,
      onChanged: (value) {
        ref.read(venuesProvider.notifier).setSearchQuery(value);
      },
      onClear: () {
        _searchController.clear();
        ref.read(venuesProvider.notifier).setSearchQuery('');
      },
    );
  }

  Widget _buildIndexColumn(
    BuildContext context,
    List<Venue> venues,
    Map<String, List<Venue>> grouped,
  ) {
    // Calculate dynamic positioning
    // Top: align with the top of the search field, i.e. the height of the
    // title row alone (top/bottom padding + its button-driven row height).
    const double topOffset = Spacing.space24 + 40 + Spacing.space8;

    // Bottom: respect bottom nav and safe area
    final bottomPadding =
        Spacing.bottomNavHeight + MediaQuery.of(context).padding.bottom;

    return AzIndexColumn(
      grouped: grouped,
      topOffset: topOffset,
      bottomPadding: bottomPadding,
      onLetterTap: (letter) {
        final targetLetter = resolveTargetLetter(letter, grouped);
        final targetIndex = flatIndexForSection(targetLetter, grouped);

        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: targetIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
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
