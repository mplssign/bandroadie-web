import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';

/// Email domain shortcut bar — tap to replace/append domain to an email field.
///
/// Displays a horizontally scrollable row of common email domain buttons.
/// Tapping a domain either replaces everything from @ onward (if @ is present)
/// or appends the domain to the end of the current text.
class EmailDomainShortcutBar extends StatelessWidget {
  const EmailDomainShortcutBar({super.key, required this.controller});

  /// The TextEditingController for the email field
  final TextEditingController controller;

  void _applyDomain(String domain) {
    final result = applyEmailDomainShortcut(controller.text, domain);
    if (result.isEmpty) return; // empty input — do nothing
    controller.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: emailDomainShortcuts.map((domain) {
          return Padding(
            padding: const EdgeInsets.only(right: Spacing.space8),
            child: ActionChip(
              label: Text(domain),
              onPressed: () => _applyDomain(domain),
              backgroundColor: context.colors.surface,
              side: BorderSide(color: context.colors.border, width: 1),
              labelStyle: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          );
        }).toList(),
      ),
    );
  }
}
