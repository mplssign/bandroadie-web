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
import 'venue_card.dart';
import 'venue_detail_screen.dart';
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

  // Shared helper: Maps section letter to flat index of its header
  int _getFlatIndexForSection(
      String targetLetter, Map<String, List<Venue>> grouped) {
    int currentIndex = 0;

    for (final key in grouped.keys) {
      if (key == targetLetter) {
        return currentIndex; // Return header index
      }
      // Skip this section: 1 header + N venues
      currentIndex += 1 + grouped[key]!.length;
    }

    return 0; // Fallback to first item
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
    await Navigator.of(context).push(
      fadeSlideRoute(page: VenueDetailScreen(venue: venue)),
    );
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
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.pagePadding,
              Spacing.space8,
              rightPadding,
              Spacing.space8,
            ),
            child: Text(
              section.key,
              style: TextStyle(
                fontSize: AppFontSizes.pageTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
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

  Map<String, List<Venue>> _groupVenuesByLetter(List<Venue> venues) {
    final Map<String, List<Venue>> grouped = {};
    for (final venue in venues) {
      // Get first character, default to '#' if empty
      final firstChar = venue.name.isEmpty ? '#' : venue.name[0].toUpperCase();
      // Map non-A-Z characters to '#'
      final letter = RegExp(r'^[A-Z]$').hasMatch(firstChar) ? firstChar : '#';
      grouped.putIfAbsent(letter, () => []).add(venue);
    }
    // Sort so A-Z come first, then '#' at the end
    return Map.fromEntries(
      grouped.entries.toList()
        ..sort((a, b) {
          if (a.key == '#' && b.key != '#') return 1; // '#' goes after letters
          if (a.key != '#' && b.key == '#') return -1; // letters go before '#'
          return a.key.compareTo(b.key); // normal alphabetical sort
        }),
    );
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
    final isSearching = venuesState.searchQuery.isNotEmpty;
    final displayVenues =
        isSearching ? venuesState.filteredVenues : venuesState.venues;
    final grouped = isSearching
        ? const <String, List<Venue>>{}
        : _groupVenuesByLetter(displayVenues);

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
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search venues, names, cities',
        hintStyle: TextStyle(
          color: context.colors.textSecondary,
          fontSize: AppFontSizes.body,
        ),
        prefixIcon: Icon(
          AppIcons.search,
          color: context.colors.textSecondary,
        ),
        suffixIcon: venuesState.searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(
                  AppIcons.close,
                  color: context.colors.textSecondary,
                ),
                onPressed: () {
                  _searchController.clear();
                  ref.read(venuesProvider.notifier).setSearchQuery('');
                },
              )
            : null,
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: context.colors.border,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: context.colors.border,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
      ),
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: AppFontSizes.body,
      ),
      onChanged: (value) {
        ref.read(venuesProvider.notifier).setSearchQuery(value);
      },
    );
  }

  Widget _buildIndexColumn(
    BuildContext context,
    List<Venue> venues,
    Map<String, List<Venue>> grouped,
  ) {
    // Always show A-Z plus # (all 27 letters)
    final allLetters = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
      '#'
    ];

    // Calculate dynamic positioning
    // Top: align with the top of the search field, i.e. the height of the
    // title row alone (top/bottom padding + its button-driven row height).
    const double topOffset = Spacing.space24 + 40 + Spacing.space8;

    // Bottom: respect bottom nav and safe area
    final bottomPadding =
        Spacing.bottomNavHeight + MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 8,
      top: topOffset,
      bottom: bottomPadding,
      child: Column(
        children: allLetters.map((letter) {
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // If section doesn't exist, find nearest populated section
                String targetLetter = letter;
                if (!grouped.containsKey(letter)) {
                  // Find nearest populated section
                  String? nearestLetter;
                  for (final key in grouped.keys) {
                    if (key.compareTo(letter) >= 0 || key == '#') {
                      nearestLetter = key;
                      break;
                    }
                  }
                  // If no section after, use last section
                  nearestLetter ??= grouped.keys.last;
                  targetLetter = nearestLetter;
                }

                // Use shared helper to get flat index
                final targetIndex =
                    _getFlatIndexForSection(targetLetter, grouped);

                if (_itemScrollController.isAttached) {
                  _itemScrollController.scrollTo(
                    index: targetIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    // Dim letters that have no venues
                    color: grouped.containsKey(letter)
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
