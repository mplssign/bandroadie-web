import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

/// Domain chip widget — displays an email domain shortcut as an animated pill.
///
/// Used for email domain shortcuts (e.g., @gmail.com, @icloud.com).
/// Supports selection state and enabled/disabled state.
class DomainChip extends StatelessWidget {
  final String domain;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  const DomainChip({
    super.key,
    required this.domain,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(100), // Pill shape
          border: Border.all(
            color:
                isSelected ? AppColors.primary : context.colors.surfaceOverlay,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          domain,
          style: TextStyle(
            color: isEnabled
                ? (isSelected
                    ? context.colors.primaryLight
                    : context.colors.textSecondary)
                : context.colors.textMuted,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
