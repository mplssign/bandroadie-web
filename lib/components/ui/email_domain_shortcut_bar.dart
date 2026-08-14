import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/components/ui/app_chip.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';

/// Email domain shortcut bar — displays common email domain buttons.
///
/// Supports two modes:
/// 1. **Tap-to-apply mode** (default): Tapping a domain mutates the controller
///    by appending domain (if no @) or replacing from @ onward.
/// 2. **Selection mode**: When [selectedDomain] and [onDomainSelected] are
///    provided, renders chips as selectable. Useful for showing current selection
///    state without mutating controller immediately.
///
/// The [enabled] flag disables all chips when false (e.g., during loading).
///
/// **Migration note:** Consolidated with DomainChip in Cycle 4
/// (feature/domain-chip-forui-consolidation).
class EmailDomainShortcutBar extends StatelessWidget {
  const EmailDomainShortcutBar({
    super.key,
    required this.controller,
    this.selectedDomain,
    this.onDomainSelected,
    this.enabled = true,
  });

  /// The TextEditingController for the email field
  final TextEditingController controller;

  /// Optional: currently selected domain (enables selection mode)
  final String? selectedDomain;

  /// Optional: callback when domain selected (enables selection mode)
  final ValueChanged<String>? onDomainSelected;

  /// Whether chips are enabled (tappable)
  final bool enabled;

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
    // Determine if we're in selection mode
    final bool isSelectionMode =
        selectedDomain != null && onDomainSelected != null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: emailDomainShortcuts.map((domain) {
          return Padding(
            padding: const EdgeInsets.only(right: Spacing.space8),
            child: AppChip(
              label: domain,
              variant: isSelectionMode
                  ? AppChipVariant.filter
                  : AppChipVariant.action,
              isSelected: isSelectionMode ? (selectedDomain == domain) : null,
              onTap: isSelectionMode
                  ? () => onDomainSelected!(domain)
                  : () => _applyDomain(domain),
              enabled: enabled,
            ),
          );
        }).toList(),
      ),
    );
  }
}
