import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// TIPS & TRICKS OVERLAY
// A lightweight, discoverable reference for app features
//
// STRUCTURE:
// - Grouped by screen (Dashboard, Setlists, Calendar)
// - Section headers with strong typography
// - Simple text rows with subtle dividers
// - No emojis inside tips, just clear, band-friendly copy
//
// USAGE:
// showModalBottomSheet(
//   context: context,
//   isScrollControlled: true,
//   backgroundColor: Colors.transparent,
//   builder: (context) => const TipsAndTricksOverlay(),
// );
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
/// Easy to add new tips: just append to the appropriate section
const List<TipSection> kTipSections = [
  TipSection(
    title: 'Dashboard',
    tips: [
      Tip(
        'Tap + Schedule Rehearsal or + Create Gig to get things on the calendar fast.',
      ),
      Tip('Tap any upcoming event to edit it — no digging required.'),
      Tip('Swipe a setlist card left to delete, right to duplicate.'),
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

/// Bottom sheet overlay displaying tips & tricks grouped by screen
class TipsAndTricksOverlay extends StatelessWidget {
  const TipsAndTricksOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with close button
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                  vertical: Spacing.space8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tips & Tricks', style: AppTextStyles.title3),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textMuted,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Divider(color: AppColors.borderMuted, height: 1, thickness: 1),

              // Tips content
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
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
              ),
            ],
          ),
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(
            top: Spacing.space8,
            bottom: Spacing.space12,
          ),
          child: Text(
            section.title,
            style: AppTextStyles.headline.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        // Tips list
        ...section.tips.asMap().entries.map((entry) {
          final index = entry.key;
          final tip = entry.value;
          final isLastTip = index == section.tips.length - 1;

          return _TipRow(tip: tip, showDivider: !isLastTip);
        }),

        // Section spacing
        if (!isLast) const SizedBox(height: Spacing.space24),
      ],
    );
  }
}

/// Widget for rendering a single tip row
class _TipRow extends StatelessWidget {
  final Tip tip;
  final bool showDivider;

  const _TipRow({required this.tip, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space10),
          child: Text(
            tip.text,
            style: AppTextStyles.body.copyWith(
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
        if (showDivider)
          Divider(
            color: AppColors.borderMuted.withValues(alpha: 0.5),
            height: 1,
            thickness: 1,
          ),
      ],
    );
  }
}

/// Helper function to show the Tips & Tricks overlay
void showTipsAndTricksOverlay(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const TipsAndTricksOverlay(),
  );
}
