// ============================================================================
// LOAD MORE REHEARSALS CARD
// A card that appears in the horizontal rehearsals list to load more occurrences.
// ============================================================================

import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../components/ui/app_card.dart';

class LoadMoreRehearsalsCard extends StatefulWidget {
  final int currentCount;
  final int totalCount;
  final VoidCallback onLoadMore;

  const LoadMoreRehearsalsCard({
    super.key,
    required this.currentCount,
    required this.totalCount,
    required this.onLoadMore,
  });

  @override
  State<LoadMoreRehearsalsCard> createState() => _LoadMoreRehearsalsCardState();
}

class _LoadMoreRehearsalsCardState extends State<LoadMoreRehearsalsCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final remaining = widget.totalCount - widget.currentCount;
    final nextBatch = remaining > 10 ? 10 : remaining;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onLoadMore();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AppCard(
          padding: EdgeInsets.zero,
          height: Spacing.rehearsalCardHeight,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(Spacing.space16),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  AppIcons.add,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  'Load More',
                  style: TextStyle(
                    fontSize: AppFontSizes.headline,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+$nextBatch rehearsals',
                  style: TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '($remaining more)',
                  style: TextStyle(
                    fontSize: AppFontSizes.caption,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
