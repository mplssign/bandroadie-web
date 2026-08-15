import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../models/venue.dart';
import '../../../components/ui/app_card.dart';

// ============================================================================
// VENUE CARD
// Simplified card for displaying venue preview in list.
// Shows only venue name + city/state for scannable list view.
// Full details accessible via VenueDetailScreen.
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
    final cityState = _formatCityState();

    return AnimatedCardPressable(
      onTap: onTap,
      child: AppCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Venue Name
              Text(
                venue.name,
                style: TextStyle(
                  fontSize: AppFontSizes.title,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.2,
                ),
              ),

              // City, State (always reserve space for uniform card height)
              const SizedBox(height: 6),
              Text(
                cityState ?? '',
                style: TextStyle(
                  fontSize: AppFontSizes.body,
                  fontWeight: FontWeight.w400,
                  color: context.colors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _formatCityState() {
    final hasCity = venue.city != null && venue.city!.isNotEmpty;
    final hasState = venue.state != null && venue.state!.isNotEmpty;

    if (hasCity && hasState) {
      return '${venue.city}, ${venue.state}';
    } else if (hasCity) {
      return venue.city;
    } else if (hasState) {
      return venue.state;
    }
    return null;
  }
}
