import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';

// ============================================================================
// TIPS & TRICKS SCREEN
// Full-page screen displaying tips & tricks grouped by screen
// White section headers with bulleted lists
// ============================================================================

/// Data model for a single tip
class Tip {
  final String text;

  const Tip(this.text);
}

/// Data model for a tip section (group of tips for a screen)
class TipSection {
  final String title;
  final List<Tip> tips;

  const TipSection({required this.title, required this.tips});
}

/// All tips organized by screen
const List<TipSection> kTipSections = [
  TipSection(
    title: 'Dashboard',
    tips: [
      Tip(
        'Tap + Schedule Rehearsal or + Create Gig to get things on the calendar fast.',
      ),
      Tip('Tap any upcoming event to edit it — no digging required.'),
      Tip("Quick Actions are shortcuts — they don't bite. Use them."),
    ],
  ),
  TipSection(
    title: 'Setlists',
    tips: [
      Tip(
        'The Catalog is your master song list. Deleting a song from a setlist does not delete it from the Catalog.',
      ),
      Tip('Swipe a setlist left to delete, right to duplicate.'),
      Tip('Use Song Lookup to pull songs from outside your Catalog.'),
      Tip(
        'Bulk Paste supports comma-separated entries — hit Enter to add another song.',
      ),
      Tip('Sort setlists by tuning using the tuning toggle.'),
      Tip('Duplicated setlists keep songs, order, and duration totals.'),
    ],
  ),
  TipSection(
    title: 'Calendar',
    tips: [
      Tip('Tap any day to add an event instantly.'),
      Tip('Tap an existing event to edit it.'),
      Tip('Green line = Gig. Blue line = Rehearsal. Rose line = Block Out.'),
      Tip(
        'Block Out dates prevent scheduling conflicts — only the creator can edit them.',
      ),
      Tip('Recurring rehearsals save time. Your future self will thank you.'),
    ],
  ),
];

class TipsAndTricksScreen extends StatelessWidget {
  const TipsAndTricksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.appBarBg,
        title: Text(
          'Tips & Tricks',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppFontSizes.title2,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: AppIconButton(
          icon: AppIcons.arrowLeft,
          color: AppColors.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.pagePadding,
          vertical: Spacing.space16,
        ),
        itemCount: kTipSections.length,
        itemBuilder: (context, sectionIndex) {
          final section = kTipSections[sectionIndex];
          return _TipSectionWidget(
            section: section,
            isLast: sectionIndex == kTipSections.length - 1,
          );
        },
      ),
    );
  }
}

/// Widget for rendering a single tip section
class _TipSectionWidget extends StatelessWidget {
  final TipSection section;
  final bool isLast;

  const _TipSectionWidget({required this.section, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header - white text
        Padding(
          padding: const EdgeInsets.only(
            top: Spacing.space8,
            bottom: Spacing.space12,
          ),
          child: Text(
            section.title,
            style: AppTextStyles.headline.copyWith(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSizes.sectionTitle,
            ),
          ),
        ),

        // Tips list with bullet points
        ...section.tips.map((tip) => _TipRow(tip: tip)),

        // Section spacing
        if (!isLast) const SizedBox(height: Spacing.space24),
      ],
    );
  }
}

/// Widget for rendering a single tip row with bullet point
class _TipRow extends StatelessWidget {
  final Tip tip;

  const _TipRow({required this.tip});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet point
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Text(
              '•',
              style: AppTextStyles.body.copyWith(
                color: isLight
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                fontSize: AppFontSizes.body,
                height: 1.5,
              ),
            ),
          ),
          // Tip text
          Expanded(
            child: Text(
              tip.text,
              style: AppTextStyles.body.copyWith(
                color: isLight
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                height: 1.5,
                fontSize: AppFontSizes.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
