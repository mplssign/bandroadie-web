import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/phone_formatter.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../models/contact.dart';

// ============================================================================
// CONTACT DETAIL DRAWER
// Read-only bottom drawer showing a contact's full details.
// Mirrors BandMemberDetailDrawer's mechanics (slide-up, rounded top corners,
// drag handle, scrollable body of conditional detail rows, fixed Done/Edit
// footer).
// ============================================================================

class ContactDetailDrawer extends StatelessWidget {
  final Contact contact;
  final VoidCallback onEdit;

  const ContactDetailDrawer({
    super.key,
    required this.contact,
    required this.onEdit,
  });

  static Future<void> show(
    BuildContext context, {
    required Contact contact,
    required VoidCallback onEdit,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      mainAxisMaxRatio: 0.95,
      useSafeArea: true,
      builder: (_) => ContactDetailDrawer(
        contact: contact,
        onEdit: onEdit,
      ),
    );
  }

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    onEdit();
  }

  /// Launch phone dialer with the given phone number.
  /// Fails silently if the device cannot handle the action.
  Future<void> _launchPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: digits);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {
      // Fail silently
    }
  }

  /// Launch email client with the given email address.
  /// Fails silently if the device cannot handle the action.
  Future<void> _launchEmail(String email) async {
    if (email.isEmpty) return;

    final uri = Uri(scheme: 'mailto', path: email);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {
      // Fail silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
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

                  // Header: contact name (no icon badge)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Text(
                      contact.name,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),
                  const Divider(height: 1),

                  // Detail rows
                  if (contact.title != null && contact.title!.isNotEmpty)
                    _DetailRow(
                      label: 'Title',
                      value: contact.title!,
                    ),

                  if (contact.company != null && contact.company!.isNotEmpty)
                    _DetailRow(
                      label: 'Company',
                      value: contact.company!,
                    ),

                  if (contact.phone != null && contact.phone!.isNotEmpty)
                    _DetailRow(
                      label: 'Phone',
                      value: formatPhoneNumber(contact.phone!),
                      onTap: () => _launchPhone(contact.phone!),
                    ),

                  if (contact.email != null && contact.email!.isNotEmpty)
                    _DetailRow(
                      label: 'Email',
                      value: contact.email!,
                      onTap: () => _launchEmail(contact.email!),
                    ),

                  if (contact.notes != null && contact.notes!.isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: contact.notes!,
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
                AppButton(
                  label: 'Done',
                  fullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.primary,
                ),
                const SizedBox(height: Spacing.space12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Edit',
                    variant: AppButtonVariant.text,
                    onPressed: () => _handleEdit(context),
                  ),
                ),
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
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
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
            width: 96,
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
