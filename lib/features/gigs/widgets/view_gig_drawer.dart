import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/app_icons.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../contacts/models/contact.dart';
import '../../contacts/widgets/contact_detail_drawer.dart';
import '../../contacts/widgets/contact_form_screen.dart';
import '../gig_controller.dart';
import '../../setlists/setlist_detail_screen.dart';
import '../../../app/theme/app_animations.dart';
import 'gig_notes_sheet.dart';

class ViewGigDrawer extends ConsumerStatefulWidget {
  final Gig gig;
  final String bandTimezone;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onSaved;

  const ViewGigDrawer({
    super.key,
    required this.gig,
    required this.bandTimezone,
    required this.canEdit,
    required this.onEdit,
    this.onSaved,
  });

  @override
  ConsumerState<ViewGigDrawer> createState() => _ViewGigDrawerState();

  static Future<void> show(
    BuildContext context, {
    required Gig gig,
    required String bandTimezone,
    required bool canEdit,
    required VoidCallback onEdit,
    VoidCallback? onSaved,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      mainAxisMaxRatio: 0.95,
      useSafeArea: true,
      builder: (_) => ViewGigDrawer(
        gig: gig,
        bandTimezone: bandTimezone,
        canEdit: canEdit,
        onEdit: onEdit,
        onSaved: onSaved,
      ),
    );
  }
}

class _ViewGigDrawerState extends ConsumerState<ViewGigDrawer> {
  late Gig _displayGig;

  @override
  void initState() {
    super.initState();
    _displayGig = widget.gig;

    if (widget.gig.contacts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadHydratedGig();
      });
    }
  }

  Future<void> _loadHydratedGig() async {
    try {
      final hydratedGig = await ref.read(gigRepositoryProvider).fetchGigById(
            gigId: widget.gig.id,
            bandId: widget.gig.bandId,
          );
      if (!mounted) return;
      setState(() {
        _displayGig = hydratedGig;
      });
    } catch (_) {}
  }

  Future<void> _openNavigation(BuildContext context) async {
    final gig = _displayGig;
    final hasAddress = gig.address != null && gig.address!.trim().isNotEmpty;
    final query = hasAddress
        ? '${gig.address} ${gig.location}'
        : '${gig.name} ${gig.location}';

    final defaultUri = _buildDefaultNavigationUri(query);
    final openedDefault = await launchUrl(
      defaultUri,
      mode: LaunchMode.externalApplication,
    );
    if (openedDefault) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final provider = await _showNavigationAppPicker(context);
    if (provider == null) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    await _launchFallbackProvider(
      context,
      provider: provider,
      query: query,
    );
  }

  Uri _buildDefaultNavigationUri(String query) {
    final encoded = Uri.encodeComponent(query);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return Uri.parse('maps://?q=$encoded');
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return Uri.parse('geo:0,0?q=$encoded');
    }

    return Uri.parse('https://maps.google.com/?q=$encoded');
  }

  Future<_NavigationApp?> _showNavigationAppPicker(BuildContext context) {
    return showAppBottomSheet<_NavigationApp>(
      context: context,
      backgroundColor: context.colors.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.pagePadding,
              Spacing.space16,
              Spacing.pagePadding,
              Spacing.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open with',
                  style: AppTextStyles.title3.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.space12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apple Maps'),
                  onTap: () => Navigator.of(sheetContext).pop(
                    _NavigationApp.appleMaps,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Google Maps'),
                  onTap: () => Navigator.of(sheetContext).pop(
                    _NavigationApp.googleMaps,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Waze'),
                  onTap: () => Navigator.of(sheetContext).pop(
                    _NavigationApp.waze,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchFallbackProvider(
    BuildContext context, {
    required _NavigationApp provider,
    required String query,
  }) async {
    final appName = _appName(provider);
    final uri = _providerUri(provider, query);

    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: '$appName is not available on this device',
        );
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showAppSnackBar(context, message: 'Could not open $appName');
    }
  }

  Uri _providerUri(_NavigationApp app, String query) {
    final encoded = Uri.encodeComponent(query);

    switch (app) {
      case _NavigationApp.appleMaps:
        return Uri.parse('maps://?q=$encoded');
      case _NavigationApp.googleMaps:
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          return Uri.parse('comgooglemaps://?q=$encoded');
        }
        return Uri.parse('google.navigation:q=$encoded');
      case _NavigationApp.waze:
        return Uri.parse('waze://?q=$encoded&navigate=yes');
    }
  }

  String _appName(_NavigationApp app) {
    switch (app) {
      case _NavigationApp.appleMaps:
        return 'Apple Maps';
      case _NavigationApp.googleMaps:
        return 'Google Maps';
      case _NavigationApp.waze:
        return 'Waze';
    }
  }

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    widget.onEdit();
  }

  void _openContactDetail(BuildContext context, Contact contact) {
    ContactDetailDrawer.show(
      context,
      contact: contact,
      onEdit: () => Navigator.of(context).push(
        fadeSlideRoute(page: ContactFormScreen(contact: contact)),
      ),
    );
  }

  String _contactSummary(Contact contact) {
    final title = contact.title?.trim();
    final company = contact.company?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final hasCompany = company != null && company.isNotEmpty;

    if (hasCompany && hasTitle) {
      return '$company, $title';
    }
    if (hasCompany) {
      return company;
    }
    if (hasTitle) {
      return title;
    }
    return '';
  }

  String _formatFullDate(DateTime date) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final gig = _displayGig;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Spacing.space16),

                  // Header block: name + location + Navigate button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Venue/event name
                        Text(
                          gig.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: Spacing.space4),
                        // Location row + Navigate button
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                gig.fullLocationDisplay,
                                style: AppTextStyles.callout.copyWith(
                                  color: context.colors.textMuted,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.navigation2,
                                  color: AppColors.primary),
                              color: AppColors.primary,
                              iconSize: 20,
                              onPressed: () => _openNavigation(context),
                              tooltip: 'Navigate',
                              style: IconButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.primary,
                                  width: BrandButton.borderWidth,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      Spacing.buttonRadius),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),

                  // Date/Time block
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatFullDate(gig.date),
                          style: AppTextStyles.title3.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Spacing.space4),
                        Text(
                          gig.timeRange,
                          style: AppTextStyles.headline.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),
                  const Divider(height: 1),

                  // Detail rows
                  if (gig.loadInTime != null)
                    _DetailRow(
                      label: 'Load in',
                      value: gig.loadInTime!,
                    ),

                  if (gig.setlistId != null)
                    _DetailRow(
                      label: 'Setlist',
                      value: gig.setlistName ?? 'Unnamed Setlist',
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        fadeSlideRoute(
                          page: SetlistDetailScreen(
                            setlistId: gig.setlistId!,
                            setlistName: gig.setlistName ?? 'Setlist',
                          ),
                        ),
                      ),
                    ),

                  if (gig.gigPayCents != null)
                    _DetailRow(
                      label: 'Gig pay',
                      value: gig.formattedPay ?? '',
                    ),

                  if (gig.contacts.isNotEmpty)
                    for (var i = 0; i < gig.contacts.length; i++)
                      _DetailRow(
                        label: i == 0 ? 'Contacts' : '',
                        value: gig.contacts[i].name,
                        subtitle: _contactSummary(gig.contacts[i]),
                        showChevron: true,
                        onTap: () =>
                            _openContactDetail(context, gig.contacts[i]),
                      ),

                  if (gig.notes != null && gig.notes!.isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: '',
                      showChevron: true,
                      onTap: () => GigNotesSheet.show(
                        context,
                        notes: gig.notes!,
                        gigName: gig.name,
                      ),
                    ),

                  const SizedBox(height: Spacing.space24),
                ],
              ),
            ),
          ),

          // Footer
          SheetFooter(
            primaryLabel: 'Done',
            onPrimary: () => Navigator.of(context).pop(),
            cancelLabel: 'Edit',
            onCancel: widget.canEdit ? () => _handleEdit(context) : null,
          ),
        ],
      ),
    );
  }
}

enum _NavigationApp {
  appleMaps,
  googleMaps,
  waze,
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final bool showChevron;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.subtitle,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.start,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.start,
                    style: AppTextStyles.footnote.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: Spacing.space4),
            Icon(
              AppIcons.forward,
              size: 16,
              color: context.colors.textMuted,
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        Divider(height: 1, color: context.colors.border),
      ],
    );
  }
}
