import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../bands/active_band_controller.dart';
import '../contacts_controller.dart';
import 'contact_card.dart';
import 'contact_form_screen.dart';
import 'contacts_empty_state.dart';

// ============================================================================
// CONTACTS VIEW
// List view for standalone contacts, backed by contactsProvider.
// ============================================================================

class ContactsView extends ConsumerStatefulWidget {
  const ContactsView({super.key});

  @override
  ConsumerState<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends ConsumerState<ContactsView> {
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
              style: const TextStyle(color: AppColors.textSecondary),
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
    if (!contactsState.hasContacts) {
      return ContactsEmptyState(
        onAddTap: () => _openContactForm(context: context),
      );
    }

    // Contacts list
    return RefreshIndicator(
      onRefresh: _onRefresh,
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
                      'Contacts',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openContactForm(context: context),
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
                  final contact = contactsState.contacts[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < contactsState.contacts.length - 1
                          ? Spacing.space16
                          : 0,
                    ),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: index * 50),
                      child: ContactCard(
                        contact: contact,
                        onTap: () => _openContactForm(
                            context: context, contact: contact),
                      ),
                    ),
                  );
                },
                childCount: contactsState.contacts.length,
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}
