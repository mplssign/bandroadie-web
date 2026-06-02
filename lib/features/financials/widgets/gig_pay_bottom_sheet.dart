import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context),
        child: child!,
      ),
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
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final enabled = _amountController.cents > 0;

    if (widget.viewOnly) {
      return Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(
            top: BorderSide(
              color: context.colors.border.withValues(alpha: 0.5),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: Spacing.space16,
          right: Spacing.space16,
          top: 12,
          bottom: bottomSafe + 12,
        ),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
              side: BorderSide(color: context.colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              minimumSize: const Size(0, 48),
            ),
            child: const Text('Close'),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 12,
        bottom: bottomSafe + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: enabled
                    ? AppColors.primary
                    : context.colors.border.withValues(alpha: 0.3),
                disabledBackgroundColor:
                    context.colors.border.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: Text(
                'Save',
                style: AppTextStyles.body.copyWith(
                  color: enabled ? Colors.white : context.colors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
                    label: 'Amount',
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
                        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
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
                  TextField(
                    controller: _payerController,
                    enabled: !widget.viewOnly,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.done,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g., Venue Name or Organizer',
                      hintStyle: AppTextStyles.callout
                          .copyWith(color: context.colors.textMuted),
                      filled: true,
                      fillColor: context.colors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                        borderSide: BorderSide(color: context.colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.background,
                        border: Border.all(color: context.colors.border),
                        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _paidToUserId,
                          isExpanded: true,
                          dropdownColor: context.colors.surfaceElevated,
                          style: AppTextStyles.callout
                              .copyWith(color: context.colors.textPrimary),
                          hint: Text(
                            'No member selected',
                            style: AppTextStyles.callout
                                .copyWith(color: context.colors.textMuted),
                          ),
                          onChanged: widget.viewOnly
                              ? null
                              : (value) {
                                  setState(() => _paidToUserId = value);
                                },
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
                      ),
                    ),
                    const SizedBox(height: Spacing.space12),
                    // Custom name field shown when "Other" is selected
                    if (_isOtherSelected) ...[
                      TextField(
                        controller: _paidToOtherController,
                        enabled: !widget.viewOnly,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.done,
                        style: AppTextStyles.callout
                            .copyWith(color: context.colors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Enter name',
                          hintStyle: AppTextStyles.callout
                              .copyWith(color: context.colors.textMuted),
                          filled: true,
                          fillColor: context.colors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                            borderSide: BorderSide(color: context.colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                            borderSide: BorderSide(color: context.colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(Spacing.buttonRadius),
                            borderSide:
                                const BorderSide(color: AppColors.primary),
                          ),
                        ),
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
                      Switch(
                        value: _is1099Expected,
                        activeThumbColor: AppColors.primary,
                        activeTrackColor: AppColors.primary.withAlpha(128),
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
