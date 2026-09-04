import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/sheet_footer.dart';

class RehearsalNotesSheet extends StatelessWidget {
  final String notes;

  const RehearsalNotesSheet({
    super.key,
    required this.notes,
  });

  static void show(
    BuildContext context, {
    required String notes,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RehearsalNotesSheet(notes: notes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            child: Text(
              'Rehearsal Notes',
              style: AppTextStyles.pageTitle.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),

          const SizedBox(height: Spacing.space16),

          const Divider(height: 1),

          // Notes content — scrollable
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
                vertical: Spacing.space16,
              ),
              child: Text(
                notes,
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),

          // Footer
          SheetFooter(
            primaryLabel: 'Done',
            onPrimary: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
