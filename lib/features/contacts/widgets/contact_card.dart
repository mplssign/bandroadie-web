import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../models/contact.dart';

// ============================================================================
// CONTACT CARD
// Simplified card for displaying a standalone contact.
// Matches VenueCard visual language (plain surface, 16px radius).
// ============================================================================

class ContactCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback? onTap;

  const ContactCard({
    super.key,
    required this.contact,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCardPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Text(
              contact.name,
              style: TextStyle(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                height: 1.2,
              ),
            ),

            // Role/title + company (always reserve space for uniform card height)
            const SizedBox(height: 6),
            Text(
              _subtitle(contact),
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
    );
  }

  String _subtitle(Contact contact) {
    final title = contact.title?.trim();
    final company = contact.company?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final hasCompany = company != null && company.isNotEmpty;
    if (hasTitle && hasCompany) return '$title, $company';
    if (hasTitle) return title;
    if (hasCompany) return company;
    return '';
  }
}
