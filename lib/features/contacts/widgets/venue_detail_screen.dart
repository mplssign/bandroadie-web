import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/shared/utils/snackbar_helper.dart';
import '../models/venue.dart';
import 'venue_form_screen.dart';

// ============================================================================
// VENUE DETAIL SCREEN
// Read-only detail view for a venue.
// Displays venue info (address, city, state, phone, notes) and contacts.
// ============================================================================

class VenueDetailScreen extends StatelessWidget {
  final Venue venue;

  const VenueDetailScreen({
    super.key,
    required this.venue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text('Venue Details', style: AppTextStyles.title3),
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: venue name (wraps) + Edit action
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.space24,
                Spacing.pagePadding,
                Spacing.space24,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      venue.name,
                      style: AppTextStyles.pageTitle.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final edited = await Navigator.push<bool>(
                        context,
                        fadeSlideRoute(page: VenueFormScreen(venue: venue)),
                      );
                      if (edited == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    child: const Text(
                      'Edit',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: AppFontSizes.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                0,
                Spacing.pagePadding,
                Spacing.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildGroups(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context) {
    final groups = <Widget>[];

    // Group 1: Address + Phone
    final addressPhoneFields = <Widget>[];
    if ((venue.address != null && venue.address!.isNotEmpty) ||
        (venue.city != null && venue.city!.isNotEmpty) ||
        (venue.state != null && venue.state!.isNotEmpty)) {
      addressPhoneFields.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildFieldEntry(
                context,
                'Address',
                _formatAddress(),
                maxLines: 3,
              ),
            ),
            IconButton(
              icon:
                  const Icon(LucideIcons.navigation2, color: AppColors.primary),
              color: AppColors.primary,
              iconSize: 20,
              tooltip: 'Navigate',
              onPressed: () => _openNavigation(context),
              style: IconButton.styleFrom(
                side: const BorderSide(
                    color: AppColors.primary, width: BrandButton.borderWidth),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius)),
              ),
            ),
          ],
        ),
      );
    }
    if (venue.phone != null && venue.phone!.isNotEmpty) {
      addressPhoneFields.add(_buildFieldEntry(
        context,
        'Phone',
        venue.phone!,
        onTap: () => _launchPhone(venue.phone!),
      ));
    }
    if (addressPhoneFields.isNotEmpty) {
      groups.add(_buildGroupCard(context, addressPhoneFields));
    }

    // Group 2: one per contact
    for (final contact in venue.contacts) {
      final contactFields = <Widget>[
        _buildFieldEntry(
          context,
          'Contact Person',
          contact.name,
          valueFontSize: AppFontSizes.title,
        ),
      ];
      if (contact.title != null && contact.title!.isNotEmpty) {
        contactFields.add(
          _buildFieldEntry(context, null, contact.title!),
        );
      }
      if (contact.phone != null && contact.phone!.isNotEmpty) {
        contactFields.add(_buildFieldEntry(
          context,
          null,
          contact.phone!,
          onTap: () => _launchPhone(contact.phone!),
        ));
      }
      if (contact.email != null && contact.email!.isNotEmpty) {
        contactFields.add(
          _buildFieldEntry(
            context,
            null,
            contact.email!,
            onTap: () => _launchEmail(contact.email!),
          ),
        );
      }
      groups.add(_buildGroupCard(context, contactFields));
    }

    // Notes: its own standalone container
    if (venue.notes != null && venue.notes!.isNotEmpty) {
      groups.add(_buildGroupCard(context, [
        _buildFieldEntry(context, 'Notes', venue.notes!, maxLines: 10),
      ]));
    }

    final spaced = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 16));
      spaced.add(groups[i]);
    }
    return spaced;
  }

  Future<void> _launchPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  String _navigationQuery() {
    final parts = <String>[];
    if (venue.address != null && venue.address!.isNotEmpty) {
      parts.add(venue.address!);
    } else {
      parts.add(venue.name);
    }
    if (venue.city != null && venue.city!.isNotEmpty) parts.add(venue.city!);
    if (venue.state != null && venue.state!.isNotEmpty) parts.add(venue.state!);
    return parts.join(' ');
  }

  Future<void> _openNavigation(BuildContext context) async {
    final query = _navigationQuery();

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
    return showModalBottomSheet<_NavigationApp>(
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

  // Renders ONE surface-colored, full-width container holding multiple
  // label/value field entries stacked vertically.
  Widget _buildGroupCard(BuildContext context, List<Widget> fields) {
    final children = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 14));
      children.add(fields[i]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // A single label/value pair, used inside a group card (no outer container).
  Widget _buildFieldEntry(
    BuildContext context,
    String? label,
    String value, {
    VoidCallback? onTap,
    int maxLines = 2,
    double valueFontSize = AppFontSizes.body,
  }) {
    final entry = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSizes.caption,
              fontWeight: FontWeight.w400,
              color: context.colors.textSecondary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          value,
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: FontWeight.w400,
            color: context.colors.textPrimary,
            height: 1.4,
          ),
          maxLines: maxLines,
          overflow: TextOverflow.visible,
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: entry,
      );
    }

    return entry;
  }

  String _formatAddress() {
    final lines = <String>[];

    // Line 1: street address
    if (venue.address != null && venue.address!.isNotEmpty) {
      lines.add(venue.address!);
    }

    // Line 2: city, state
    final cityState = <String>[];
    if (venue.city != null && venue.city!.isNotEmpty) {
      cityState.add(venue.city!);
    }
    if (venue.state != null && venue.state!.isNotEmpty) {
      cityState.add(venue.state!);
    }
    if (cityState.isNotEmpty) {
      lines.add(cityState.join(', '));
    }

    return lines.join('\n');
  }
}

enum _NavigationApp {
  appleMaps,
  googleMaps,
  waze,
}
