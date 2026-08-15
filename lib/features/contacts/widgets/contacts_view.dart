import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../bands/active_band_controller.dart';
import '../contacts_controller.dart';
import '../models/contact.dart';
import 'az_index_column.dart';
import 'az_list_helpers.dart';
import 'az_search_field.dart';
import 'az_section_header.dart';
import 'contact_card.dart';
import 'contact_detail_drawer.dart';
import 'contact_form_screen.dart';
import 'contacts_empty_state.dart';
import '../../../components/ui/app_button.dart';

// ============================================================================
// CONTACTS VIEW
// List view for standalone contacts, backed by contactsProvider.
// Follows the same A-Z search/section/index-column pattern as VenuesView.
// ============================================================================

class ContactsView extends ConsumerStatefulWidget {
  const ContactsView({super.key});

  @override
  ConsumerState<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends ConsumerState<ContactsView> {
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
        ref.read(contactsProvider.notifier).load(bandId);
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
    await ref.read(contactsProvider.notifier).refresh(bandId);
  }

  Future<void> _openContactForm({
    required BuildContext context,
    contact,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      fadeSlideRoute(page: ContactFormScreen(contact: contact)),
    );
    if (result == true) {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(contactsProvider.notifier).refresh(bandId);
      }
    }
  }

  int _calculateItemCount(
    bool isSearching,
    List<Contact> contacts,
    Map<String, List<Contact>> grouped,
  ) {
    if (isSearching) {
      return contacts.length + 1;
    } else {
      int count = 0;
      for (final section in grouped.entries) {
        count += 1; // section header
        count += section.value.length; // contacts
      }
      count += 1; // bottom spacer
      return count;
    }
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    bool isSearching,
    List<Contact> contacts,
    Map<String, List<Contact>> grouped,
  ) {
    // Right padding accounts for index column (40px)
    const double rightPadding = Spacing.pagePadding + 40;

    if (isSearching) {
      if (index < contacts.length) {
        final contact = contacts[index];
        return Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.pagePadding,
            0,
            rightPadding,
            index < contacts.length - 1 ? Spacing.space16 : 0,
          ),
          child: FadeSlideIn(
            delay: Duration(milliseconds: index * 50),
            child: ContactCard(
              contact: contact,
              onTap: () => ContactDetailDrawer.show(
                context,
                contact: contact,
                onEdit: () =>
                    _openContactForm(context: context, contact: contact),
              ),
            ),
          ),
        );
      } else {
        return SizedBox(
          height: Spacing.space48 +
              Spacing.bottomNavHeight +
              MediaQuery.of(context).padding.bottom +
              32,
        );
      }
    } else {
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

        // Contacts in section
        if (index < currentIndex + section.value.length) {
          final contactIdx = index - currentIndex;
          final contact = section.value[contactIdx];
          return Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.pagePadding,
              0,
              rightPadding,
              contactIdx < section.value.length - 1
                  ? Spacing.space16
                  : Spacing.space24,
            ),
            child: ContactCard(
              contact: contact,
              onTap: () => ContactDetailDrawer.show(
                context,
                contact: contact,
                onEdit: () =>
                    _openContactForm(context: context, contact: contact),
              ),
            ),
          );
        }
        currentIndex += section.value.length;
      }

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
    final contactsState = ref.watch(contactsProvider);

    // Loading state
    if (contactsState.isLoading && !contactsState.hasContacts) {
      return _buildLoadingState();
    }

    // Error state
    if (contactsState.error != null && !contactsState.hasContacts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              contactsState.error!,
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
    if (!contactsState.hasContacts) {
      return ContactsEmptyState(
        onAddTap: () => _openContactForm(context: context),
      );
    }

    // Contacts list
    final isSearching = contactsState.searchQuery.isNotEmpty;
    final displayContacts =
        isSearching ? contactsState.filteredContacts : contactsState.contacts;
    final grouped = isSearching
        ? const <String, List<Contact>>{}
        : groupByLetter(displayContacts, (c) => c.name);

    // Handle empty search results
    if (isSearching && displayContacts.isEmpty) {
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
                        'Contacts',
                        style: AppTextStyles.pageTitle.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    AppButton(
                      label: 'Add',
                      icon: AppIcons.add,
                      variant: AppButtonVariant.text,
                      onPressed: () => _openContactForm(context: context),
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
                child: _buildSearchBar(context, contactsState),
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
                      'No contacts found',
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
                        'Contacts',
                        style: AppTextStyles.pageTitle.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    AppButton(
                      label: 'Add',
                      icon: AppIcons.add,
                      variant: AppButtonVariant.text,
                      onPressed: () => _openContactForm(context: context),
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
                child: _buildSearchBar(context, contactsState),
              ),
              // Scrollable contacts list
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _calculateItemCount(
                      isSearching, displayContacts, grouped),
                  itemBuilder: (context, index) {
                    return _buildItem(
                        context, index, isSearching, displayContacts, grouped);
                  },
                ),
              ),
            ],
          ),
          // A-Z Index column (only visible when not searching)
          if (!isSearching)
            _buildIndexColumn(context, displayContacts, grouped),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ContactsState contactsState) {
    return AzSearchField(
      controller: _searchController,
      hintText: 'Search contacts',
      currentQuery: contactsState.searchQuery,
      onChanged: (value) {
        ref.read(contactsProvider.notifier).setSearchQuery(value);
      },
      onClear: () {
        _searchController.clear();
        ref.read(contactsProvider.notifier).setSearchQuery('');
      },
    );
  }

  Widget _buildIndexColumn(
    BuildContext context,
    List<Contact> contacts,
    Map<String, List<Contact>> grouped,
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
