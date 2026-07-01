import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/app_icons.dart';
import '../../../components/ui/brand_action_button.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../setlists/setlist_detail_screen.dart';
import '../../../app/theme/app_animations.dart';
import 'gig_notes_sheet.dart';

class ViewGigDrawer extends StatelessWidget {
  final Gig gig;
  final String bandTimezone;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onSaved;

  const ViewGigDrawer({
    super.key,
    required this.gig,
    required this.bandTimezone,
    required this.canEdit,
    required this.onEdit,
    this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required Gig gig,
    required String bandTimezone,
    required bool canEdit,
    required VoidCallback onEdit,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewGigDrawer(
        gig: gig,
        bandTimezone: bandTimezone,
        canEdit: canEdit,
        onEdit: onEdit,
        onSaved: onSaved,
      ),
    );
  }

  Future<void> _openNavigation(BuildContext context) async {
    final hasAddress = gig.address != null && gig.address!.trim().isNotEmpty;
    final query = Uri.encodeComponent(
      hasAddress
          ? '${gig.address} ${gig.location}'
          : '${gig.name} ${gig.location}',
    );
    final uri = Uri.parse('https://maps.google.com/?q=$query');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showAppSnackBar(context, message: 'Could not open maps');
      }
    }
  }

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    onEdit();
  }

  String _formatFullDate(DateTime date) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
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

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Spacing.space16),

                  // Header block: name + location + Navigate button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Venue/event name
                        Text(
                          gig.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: Spacing.space4),
                        // Location row + Navigate button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                gig.location,
                                style: AppTextStyles.callout.copyWith(
                                  color: context.colors.textMuted,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.navigation2),
                              color: AppColors.primary,
                              iconSize: 20,
                              onPressed: () => _openNavigation(context),
                              tooltip: 'Navigate',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),

                  // Date/Time block
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatFullDate(gig.date),
                          style: AppTextStyles.title3.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Spacing.space4),
                        Text(
                          gig.timeRange,
                          style: AppTextStyles.headline.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),
                  const Divider(height: 1),

                  // Detail rows
                  if (gig.loadInTime != null)
                    _DetailRow(
                      label: 'Load in',
                      value: gig.loadInTime!,
                    ),

                  if (gig.setlistId != null)
                    _DetailRow(
                      label: 'Setlist',
                      value: gig.setlistName ?? 'Unnamed Setlist',
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        fadeSlideRoute(
                          page: SetlistDetailScreen(
                            setlistId: gig.setlistId!,
                            setlistName: gig.setlistName ?? 'Setlist',
                          ),
                        ),
                      ),
                    ),

                  if (gig.gigPayCents != null)
                    _DetailRow(
                      label: 'Gig pay',
                      value: gig.formattedPay ?? '',
                    ),

                  if (gig.notes != null && gig.notes!.isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: '',
                      showChevron: true,
                      onTap: () => GigNotesSheet.show(
                        context,
                        notes: gig.notes!,
                        gigName: gig.name,
                      ),
                    ),

                  const SizedBox(height: Spacing.space24),
                ],
              ),
            ),
          ),

          // Footer
          Padding(
            padding: EdgeInsets.only(
              left: Spacing.pagePadding,
              right: Spacing.pagePadding,
              bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
            ),
            child: Column(
              children: [
                BrandActionButton(
                  label: 'Done',
                  fullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (canEdit) ...[
                  const SizedBox(height: Spacing.space12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => _handleEdit(context),
                      child: Text(
                        'Edit',
                        style: AppTextStyles.calloutEmphasized.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showChevron;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: Spacing.space4),
            Icon(
              AppIcons.forward,
              size: 16,
              color: context.colors.textMuted,
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        Divider(height: 1, color: context.colors.border),
      ],
    );
  }
}
