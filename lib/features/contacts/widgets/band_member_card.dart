import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../members/member_vm.dart';

// ============================================================================
// BAND MEMBER CARD
// Simplified card for displaying a band member in the A-Z list.
// Matches VenueCard visual language (plain surface, 16px radius).
// Crown-only role badge for admins/owners; tap opens the detail drawer.
// ============================================================================

class BandMemberCard extends StatelessWidget {
  final MemberVM member;
  final VoidCallback? onTap;

  const BandMemberCard({
    super.key,
    required this.member,
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
            // Header row: crown-only role badge + name
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    member.name,
                    style: TextStyle(
                      fontSize: AppFontSizes.title,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (member.isAdmin)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 10),
                    child: Icon(
                      AppIcons.crown,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),

            // Musical roles (always reserve space for uniform card height)
            const SizedBox(height: 6),
            Text(
              member.musicalRoles.join(', '),
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
}
