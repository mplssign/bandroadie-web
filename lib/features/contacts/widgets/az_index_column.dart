import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// AZ INDEX COLUMN
// Shared right-side A-Z+# index column. Reports which letter was tapped;
// the caller resolves the target section and drives its own scroll
// controller — this widget does not own scrolling.
// ============================================================================

class AzIndexColumn extends StatelessWidget {
  final Map<String, List> grouped;
  final void Function(String letter) onLetterTap;
  final double topOffset;
  final double bottomPadding;

  const AzIndexColumn({
    super.key,
    required this.grouped,
    required this.onLetterTap,
    required this.topOffset,
    required this.bottomPadding,
  });

  static const List<String> _allLetters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#'
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      top: topOffset,
      bottom: bottomPadding,
      child: Column(
        children: _allLetters.map((letter) {
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onLetterTap(letter),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: grouped.containsKey(letter)
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
