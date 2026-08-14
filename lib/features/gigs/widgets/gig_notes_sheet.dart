import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/app_button.dart';

class GigNotesSheet extends StatelessWidget {
  final String notes;
  final String gigName;

  const GigNotesSheet({
    super.key,
    required this.notes,
    required this.gigName,
  });

  static void show(
    BuildContext context, {
    required String notes,
    required String gigName,
  }) {
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GigNotesSheet(notes: notes, gigName: gigName),
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
              gigName,
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

          const SizedBox(height: Spacing.space16),

          // Footer
          Padding(
            padding: EdgeInsets.only(
              left: Spacing.pagePadding,
              right: Spacing.pagePadding,
              bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
            ),
            child: AppButton(
              label: 'Done',
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(),
              variant: AppButtonVariant.primary,
            ),
          ),
        ],
      ),
    );
  }
}
