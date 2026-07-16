import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../models/venue.dart';
import '../models/venue_contact.dart';

// ============================================================================
// VENUE CARD
// Card for displaying a venue in the Venues list.
// Matches MemberCard visual language (rose border, glow, 24px radius).
// ============================================================================

class VenueCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;

  const VenueCard({
    super.key,
    required this.venue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCardPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.05),
                        Colors.transparent,
                        AppColors.primary.withValues(alpha: 0.03),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Venue Name
                    Text(
                      venue.name,
                      style: TextStyle(
                        fontSize: AppFontSizes.pageTitle,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        height: 1.2,
                      ),
                    ),

                    // Address line (Address, City State)
                    if (_hasLocation) ...[
                      const SizedBox(height: 10),
                      _buildInfoRow(
                        context: context,
                        icon: AppIcons.location,
                        value: _formatFullAddress(),
                      ),
                    ],

                    // Phone
                    if (venue.phone != null && venue.phone!.isNotEmpty)
                      _buildInfoRow(
                        context: context,
                        icon: AppIcons.phone,
                        value: venue.phone!,
                        onTap: () => _launchPhone(venue.phone!),
                      ),

                    // Venue contacts
                    for (int i = 0; i < venue.contacts.length; i++) ...[
                      Divider(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        thickness: 1,
                        height: 24,
                      ),
                      _buildVenueContactSection(context, venue.contacts[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasLocation =>
      (venue.address != null && venue.address!.isNotEmpty) ||
      (venue.city != null && venue.city!.isNotEmpty) ||
      (venue.state != null && venue.state!.isNotEmpty);

  String _formatFullAddress() {
    final parts = <String>[];
    if (venue.address != null && venue.address!.isNotEmpty) {
      parts.add(venue.address!);
    }
    final cityState = <String>[];
    if (venue.city != null && venue.city!.isNotEmpty) {
      cityState.add(venue.city!);
    }
    if (venue.state != null && venue.state!.isNotEmpty) {
      cityState.add(venue.state!);
    }
    if (cityState.isNotEmpty) {
      parts.add(cityState.join(' '));
    }
    return parts.join(', ');
  }

  Widget _buildVenueContactSection(BuildContext context, VenueContact contact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contact name
        Text(
          contact.name,
          style: TextStyle(
            fontSize: AppFontSizes.title,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
            height: 1.3,
          ),
        ),

        // Title badge
        if (contact.title != null && contact.title!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary,
                width: 1,
              ),
            ),
            child: Text(
              contact.title!,
              style: const TextStyle(
                fontSize: AppFontSizes.caption,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
                height: 1.2,
              ),
            ),
          ),
        ],

        // Email
        if (contact.email != null && contact.email!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildInfoRow(
            context: context,
            icon: AppIcons.email,
            value: contact.email!,
          ),
        ],

        // Phone
        if (contact.phone != null && contact.phone!.isNotEmpty)
          _buildInfoRow(
            context: context,
            icon: AppIcons.phone,
            value: contact.phone!,
            onTap: () => _launchPhone(contact.phone!),
          ),
      ],
    );
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

  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String value,
    VoidCallback? onTap,
    int maxLines = 2,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: AppFontSizes.body,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textPrimary,
                  height: 1.3,
                ),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
