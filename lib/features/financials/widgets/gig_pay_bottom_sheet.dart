import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_date_picker.dart';
import '../../../components/ui/app_dropdown.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../features/members/member_vm.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../models/financial_entry.dart';

// ============================================================================
// GIG PAY BOTTOM SHEET
// Captures payment details for a gig:
//   - Amount, Payment Date, Payer Name, Paid-to Member, 1099 toggle.
//
// Returns GigPayDetails via Navigator.pop on save.
// Returns null on dismiss/cancel (no changes applied).
// ============================================================================

class GigPayBottomSheet extends StatefulWidget {
  const GigPayBottomSheet({
    super.key,
    required this.defaultPaymentDate,
    required this.bandId,
    required this.members,
    this.defaultPayerName,
    this.initialDetails,
    this.viewOnly = false,
  });

  /// Prefills the payment date from the gig date.
  final DateTime defaultPaymentDate;

  /// Band ID for context.
  final String bandId;

  /// Pre-loaded band members for the "Paid To" dropdown.
  final List<MemberVM> members;

  /// Default payer name (e.g. venue/gig name) shown when creating a new entry.
  final String? defaultPayerName;

  /// Pre-fills all fields in edit mode.
  final GigPayDetails? initialDetails;

  /// When true, all fields are read-only.
  final bool viewOnly;

  @override
  State<GigPayBottomSheet> createState() => _GigPayBottomSheetState();
}

class _GigPayBottomSheetState extends State<GigPayBottomSheet> {
  late final CurrencyInputController _amountController;
  late final TextEditingController _payerController;
  late final TextEditingController _paidToOtherController;
  late DateTime _paymentDate;
  String? _paidToUserId;
  bool _is1099Expected = false;

  static const String _kOther = '__other__';
  bool get _isOtherSelected => _paidToUserId == _kOther;

  @override
  void initState() {
    super.initState();
    _amountController = CurrencyInputController();
    _payerController = TextEditingController();
    _paidToOtherController = TextEditingController();

    final initial = widget.initialDetails;
    if (initial != null) {
      _amountController.cents = initial.amountCents;
      _payerController.text = initial.payerName ?? '';
      _paymentDate = initial.paymentDate;
      _is1099Expected = initial.is1099Expected;
      // If there's a paidToName but no userId, it was an "Other" entry
      if (initial.paidToUserId != null) {
        _paidToUserId = initial.paidToUserId;
      } else if (initial.paidToName != null) {
        _paidToUserId = _kOther;
        _paidToOtherController.text = initial.paidToName!;
      } else {
        _paidToUserId = initial.paidToUserId;
      }
    } else {
      _paymentDate = widget.defaultPaymentDate;
      // Default payer name to the venue/gig name when creating a new entry
      if (widget.defaultPayerName != null &&
          widget.defaultPayerName!.trim().isNotEmpty) {
        _payerController.text = widget.defaultPayerName!.trim();
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _payerController.dispose();
    _paidToOtherController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  }

  void _save() {
    final isOther = _paidToUserId == _kOther;

    // Resolve paid-to name: free text for Other, member display name for a member
    String? resolvedPaidToName;
    if (isOther) {
      final text = _paidToOtherController.text.trim();
      resolvedPaidToName = text.isEmpty ? null : text;
    } else if (_paidToUserId != null) {
      final member =
          widget.members.where((m) => m.userId == _paidToUserId).firstOrNull;
      resolvedPaidToName = member?.name;
    }

    final result = GigPayDetails(
      amountCents: _amountController.cents,
      is1099Expected: _is1099Expected,
      payerName: _payerController.text.trim().isEmpty
          ? null
          : _payerController.text.trim(),
      paidToUserId: isOther ? null : _paidToUserId,
      paidToName: resolvedPaidToName,
      paymentDate: _paymentDate,
      existingEntryId: widget.initialDetails?.existingEntryId,
    );
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    Navigator.of(context).pop(null);
  }

  Widget _buildFixedBottomActions() {
    final enabled = _amountController.cents > 0;

    if (widget.viewOnly) {
      return SheetFooter(
        primaryLabel: 'Close',
        onPrimary: _cancel,
      );
    }

    return SheetFooter(
      primaryLabel: 'Save',
      onPrimary: enabled ? _save : null,
      onCancel: _cancel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(_paymentDate);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Spacing.cardRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: Spacing.pagePadding,
                right: Spacing.pagePadding,
                top: Spacing.space24,
                bottom: Spacing.space8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.space20),

                  // Title
                  Text(
                    'Gig Pay Details',
                    style: AppTextStyles.displayMedium
                        .copyWith(color: context.colors.textPrimary),
                  ),
                  const SizedBox(height: Spacing.space24),

                  // Amount
                  Text(
                    'Amount',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  CurrencyTextField(
                    controller: _amountController,
                    label: '',
                    hint: '\$0.00',
                    enabled: !widget.viewOnly,
                  ),
                  const SizedBox(height: Spacing.space16),

                  // Payment Date
                  Text(
                    'Payment Date',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: widget.viewOnly ? null : _pickDate,
                    icon: const Icon(AppIcons.calendar, size: 16),
                    label: Text(dateStr),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                      side: BorderSide(color: context.colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                      ),
                      minimumSize: const Size(double.infinity, 48),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  const SizedBox(height: Spacing.space16),

                  // Payer Name
                  Text(
                    'Payer Name (optional)',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _payerController,
                    enabled: !widget.viewOnly,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.done,
                    hintText: 'e.g., Venue Name or Organizer',
                  ),
                  const SizedBox(height: Spacing.space16),

                  // Paid To Member
                  if (widget.members.isNotEmpty) ...[
                    Text(
                      'Paid To (optional)',
                      style: AppTextStyles.footnote
                          .copyWith(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    AppDropdown<String?>(
                      value: _paidToUserId,
                      onChanged: (value) {
                        setState(() => _paidToUserId = value);
                      },
                      labelBuilder: (value) {
                        if (value == null) return 'No member selected';
                        if (value == _kOther) return 'Other';
                        return widget.members
                                .where((m) => m.userId == value)
                                .firstOrNull
                                ?.name ??
                            'Unknown';
                      },
                      enabled: !widget.viewOnly,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'No member selected',
                            style: AppTextStyles.callout
                                .copyWith(color: context.colors.textMuted),
                          ),
                        ),
                        ...widget.members.map(
                          (member) => DropdownMenuItem<String?>(
                            value: member.userId,
                            child: Text(member.name),
                          ),
                        ),
                        DropdownMenuItem<String?>(
                          value: _kOther,
                          child: Text(
                            'Other',
                            style: AppTextStyles.callout
                                .copyWith(color: context.colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.space12),
                    // Custom name field shown when "Other" is selected
                    if (_isOtherSelected) ...[
                      AppTextField(
                        controller: _paidToOtherController,
                        enabled: !widget.viewOnly,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.done,
                        hintText: 'Enter name',
                      ),
                      const SizedBox(height: Spacing.space16),
                    ] else
                      const SizedBox(height: Spacing.space16),
                  ],

                  // 1099 Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1099 Expected',
                        style: AppTextStyles.callout
                            .copyWith(color: context.colors.textPrimary),
                      ),
                      AppSwitch(
                        value: _is1099Expected,
                        onChanged: widget.viewOnly
                            ? null
                            : (value) {
                                setState(() => _is1099Expected = value);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.space8),
                ],
              ),
            ),
          ),
          _buildFixedBottomActions(),
        ],
      ),
    );
  }
}
