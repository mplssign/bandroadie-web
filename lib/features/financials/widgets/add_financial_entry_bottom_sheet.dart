// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_date_picker.dart';
import '../../../components/ui/app_dropdown.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/confirm_action_dialog.dart';
import '../../../features/members/member_vm.dart';
import '../../members/permissions/band_permissions_provider.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../models/financial_entry.dart';

// ============================================================================
// ADD FINANCIAL ENTRY BOTTOM SHEET
// Allows band members to manually record income or expenses.
// onSave is called with the form values; throws on failure.
// ============================================================================

typedef _SaveCallback = Future<void> Function({
  required FinancialEntryType entryType,
  required String category,
  required int amountCents,
  required DateTime entryDate,
  String? description,
  bool? is1099Expected,
  String? payerName,
  String? paidToName,
  String? paidToUserId,
  Map<String, int>? disbursements,
  bool? depositToSavings,
  int? depositToSavingsCents,
});

const _kDefaultIncomeTypes = ['Gig Pay', 'Merch Sale', 'Equipment Sale'];
const _kDefaultExpenseTypes = [
  'Rent',
  'Marketing',
  'Equipment',
  'Website',
  'Domain name'
];

/// Maps a display label back to the nearest [FinancialEntryType].
FinancialEntryType _labelToEntryType(String label, {required bool isIncome}) {
  switch (label) {
    case 'Gig Pay':
      return FinancialEntryType.gigPay;
    case 'Merch Sale':
      return FinancialEntryType.merchSale;
    case 'Equipment Sale':
      return FinancialEntryType.equipmentSale;
    case 'Expense':
      return FinancialEntryType.expense;
    default:
      return isIncome
          ? FinancialEntryType.miscIncome
          : FinancialEntryType.expense;
  }
}

/// Shows the bottom sheet and wires up [onSave].
/// Pass [initialEntry] to pre-fill the form for editing.
/// Pass [savingsTotalCents] to display the band's running savings balance next
/// to the "Deposit to Savings" toggle label. If null, no balance is shown.
/// Pass [onDelete] to enable the delete button (only shown when editing).
Future<void> showAddFinancialEntrySheet(
  BuildContext context, {
  required _SaveCallback onSave,
  VoidCallback? onDelete,
  bool initialIsIncome = true,
  FinancialEntry? initialEntry,
  List<MemberVM> members = const [],
  int? savingsTotalCents,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddFinancialEntryBottomSheet(
      onSave: onSave,
      onDelete: onDelete,
      initialIsIncome: initialEntry?.isIncome ?? initialIsIncome,
      initialEntry: initialEntry,
      members: members,
      savingsTotalCents: savingsTotalCents,
    ),
  );
}

/// Formats an integer cents value as a dollar string, matching the
/// [FinancialEntry.formattedAmount] pattern (e.g. 52354 → "\$523.54").
String _formatSavingsCents(int cents) {
  final dollars = cents ~/ 100;
  final remainder = cents % 100;
  final dollarsFormatted = NumberFormat('#,##0').format(dollars);
  return '\$$dollarsFormatted.${remainder.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Private sheet widget
// ---------------------------------------------------------------------------

class _AddFinancialEntryBottomSheet extends StatefulWidget {
  const _AddFinancialEntryBottomSheet({
    required this.onSave,
    this.onDelete,
    this.initialIsIncome = true,
    this.initialEntry,
    this.members = const [],
    this.savingsTotalCents,
  });

  final _SaveCallback onSave;
  final VoidCallback? onDelete;
  final bool initialIsIncome;
  final FinancialEntry? initialEntry;
  final List<MemberVM> members;
  final int? savingsTotalCents;

  @override
  State<_AddFinancialEntryBottomSheet> createState() =>
      _AddFinancialEntryBottomSheetState();
}

class _AddFinancialEntryBottomSheetState
    extends State<_AddFinancialEntryBottomSheet> {
  late bool _isIncome;
  late List<String> _incomeTypeLabels;
  late List<String> _expenseTypeLabels;
  late String _selectedTypeName;
  bool _isDeleteTypeMode = false;
  late DateTime _entryDate;
  bool _is1099Expected = false;
  bool _isSaving = false;
  bool _disburse = false;
  bool _depositToSavings = false;
  final Map<String, CurrencyInputController> _splitControllers = {};

  late final CurrencyInputController _depositToSavingsController;

  late final CurrencyInputController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _payerController;
  late final TextEditingController _paidToOtherController;

  String? _paidToUserId;
  static const String _kOther = '__other__';
  bool get _isOtherPaidToSelected => _paidToUserId == _kOther;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _isIncome = entry?.isIncome ?? widget.initialIsIncome;
    _incomeTypeLabels = List.from(_kDefaultIncomeTypes);
    _expenseTypeLabels = List.from(_kDefaultExpenseTypes);

    if (entry != null) {
      // Pre-fill from existing entry — use saved category label, not generic displayName
      final typeName = entry.category;
      if (_isIncome && !_incomeTypeLabels.contains(typeName)) {
        _incomeTypeLabels.add(typeName);
      } else if (!_isIncome && !_expenseTypeLabels.contains(typeName)) {
        _expenseTypeLabels.add(typeName);
      }
      _selectedTypeName = typeName;
      _entryDate = entry.entryDate;
      _is1099Expected = entry.is1099Expected ?? false;
      _depositToSavings = entry.depositToSavings ?? false;
      _depositToSavingsController = CurrencyInputController(
        entry.depositToSavingsCents ?? 0,
      );
      _amountController = CurrencyInputController(entry.amountCents);
      _descriptionController =
          TextEditingController(text: entry.description ?? '');
      _payerController = TextEditingController(text: entry.payerName ?? '');
      _paidToOtherController = TextEditingController();
      // Pre-fill paid-to: member userId takes priority; free-text name => Other
      if (entry.paidToUserId != null) {
        _paidToUserId = entry.paidToUserId;
      } else if (entry.paidToName != null) {
        _paidToUserId = _kOther;
        _paidToOtherController.text = entry.paidToName!;
      }
    } else {
      _selectedTypeName =
          _isIncome ? _kDefaultIncomeTypes.first : _kDefaultExpenseTypes.first;
      _entryDate = DateTime.now();
      _amountController = CurrencyInputController();
      _depositToSavingsController = CurrencyInputController();
      _descriptionController = TextEditingController();
      _payerController = TextEditingController();
      _paidToOtherController = TextEditingController();
    }
    _amountController.addListener(_onDisbursementChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onDisbursementChanged);
    _amountController.dispose();
    _descriptionController.dispose();
    _payerController.dispose();
    _paidToOtherController.dispose();
    for (final c in _splitControllers.values) {
      c.removeListener(_onDisbursementChanged);
      c.dispose();
    }
    _depositToSavingsController.dispose();
    super.dispose();
  }

  void _setIsIncome(bool isIncome) {
    setState(() {
      _isIncome = isIncome;
      _isDeleteTypeMode = false;
      final labels = isIncome ? _incomeTypeLabels : _expenseTypeLabels;
      _selectedTypeName = labels.isNotEmpty ? labels.first : '';
      if (!isIncome && _disburse) {
        _disburse = false;
      }
      if (!isIncome && _depositToSavings) {
        _depositToSavings = false;
        _depositToSavingsController.cents = 0;
      }
    });
  }

  void _onDisburseToggle(bool value) {
    setState(() {
      _disburse = value;
      if (value) {
        _populateSplits();
      } else {
        for (final c in _splitControllers.values) {
          c.cents = 0;
        }
      }
    });
  }

  void _populateSplits() {
    final members = widget.members;
    if (members.isEmpty) return;
    final total = _amountController.cents;
    final count = members.length;
    final perMember = total ~/ count;
    final remainder = total - perMember * count;
    for (var i = 0; i < members.length; i++) {
      final m = members[i];
      final isNew = !_splitControllers.containsKey(m.userId);
      _splitControllers.putIfAbsent(m.userId, () => CurrencyInputController());
      if (isNew) {
        _splitControllers[m.userId]!.addListener(_onDisbursementChanged);
      }
      _splitControllers[m.userId]!.cents =
          i == 0 ? perMember + remainder : perMember;
    }
  }

  /// Called whenever the total amount or any split value changes.
  /// Keeps the savings field in sync with the undisbursed remainder.
  void _onDisbursementChanged() {
    if (!_depositToSavings || !_disburse) return;
    final totalDisbursed =
        _splitControllers.values.fold<int>(0, (sum, c) => sum + c.cents);
    final remaining = _amountController.cents - totalDisbursed;
    _depositToSavingsController.cents = remaining > 0 ? remaining : 0;
  }

  String _shortName(MemberVM member) {
    final first = member.firstName;
    final last = member.lastName;
    if (first != null && first.isNotEmpty) {
      if (last != null && last.isNotEmpty) {
        return '$first ${last[0]}.';
      }
      return first;
    }
    return member.name;
  }

  Future<void> _showAddTypeDialog() async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void submit() {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                setDialogState(() => errorText = 'Enter a type name');
                return;
              }
              final list = _isIncome ? _incomeTypeLabels : _expenseTypeLabels;
              if (list.contains(trimmed)) {
                setDialogState(() => errorText = 'Type already exists');
                return;
              }
              Navigator.of(ctx).pop(trimmed);
            }

            return AlertDialog(
              backgroundColor: Theme.of(ctx).colorScheme.surface,
              title: const Text('Add Type'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: controller,
                    autofocus: true,
                    hintText: 'e.g., Streaming Revenue',
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => submit(),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: Spacing.space8),
                    Text(
                      errorText!,
                      style: AppTextStyles.footnote.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submit,
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      final list = _isIncome ? _incomeTypeLabels : _expenseTypeLabels;
      list.add(result);
      _selectedTypeName = result;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() => _entryDate = picked);
  }

  Future<void> _save() async {
    if (_amountController.cents <= 0) return;
    setState(() => _isSaving = true);

    Map<String, int>? disbursements;
    if (_disburse && widget.members.isNotEmpty) {
      disbursements = {
        for (final m in widget.members)
          m.userId: _splitControllers[m.userId]?.cents ?? 0,
      };
    }

    final depositToSavingsCents = (_isIncome &&
            _depositToSavings &&
            _depositToSavingsController.cents > 0)
        ? _depositToSavingsController.cents
        : null;

    try {
      await widget.onSave(
        entryType: _labelToEntryType(_selectedTypeName, isIncome: _isIncome),
        category: _selectedTypeName,
        amountCents: _amountController.cents,
        entryDate: _entryDate,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        is1099Expected: _isIncome ? _is1099Expected : null,
        payerName: _payerController.text.trim().isEmpty
            ? null
            : _payerController.text.trim(),
        paidToUserId: _paidToUserId == _kOther ? null : _paidToUserId,
        paidToName: () {
          if (_paidToUserId == _kOther) {
            final t = _paidToOtherController.text.trim();
            return t.isEmpty ? null : t;
          } else if (_paidToUserId != null) {
            return widget.members
                .where((m) => m.userId == _paidToUserId)
                .firstOrNull
                ?.name;
          }
          return null;
        }(),
        disbursements: disbursements,
        depositToSavings: _isIncome ? _depositToSavings : null,
        depositToSavingsCents: depositToSavingsCents,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showErrorSnackBar(context, message: e.toString());
    }
  }

  Future<void> _handleDelete() async {
    final entry = widget.initialEntry;
    if (entry == null) return;

    final entryType = entry.isIncome ? 'income' : 'expense';
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: 'Delete Entry?',
      message:
          'Are you sure you want to delete this $entryType entry? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    Navigator.of(context).pop();
    widget.onDelete?.call();
  }

  Widget _buildFixedBottomActions() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final enabled = _amountController.cents > 0;

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
          // Save and Cancel side by side
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.colors.border),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save',
                          style: AppTextStyles.body.copyWith(
                            color: enabled
                                ? Colors.white
                                : context.colors.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSizes.body,
                          ),
                        ),
                ),
              ),
            ],
          ),
          // Delete button (only when editing and user has permission)
          if (widget.initialEntry != null && widget.onDelete != null)
            Consumer(
              builder: (context, ref, _) {
                final permissionsAsync =
                    ref.watch(currentUserPermissionsProvider);
                final canDelete = permissionsAsync.when(
                  data: (p) => p.canDeleteFinancials,
                  loading: () => false,
                  error: (_, __) => false,
                );
                if (!canDelete) {
                  return const SizedBox.shrink();
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _handleDelete,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 24),
                      ),
                      child: Text(
                        widget.initialEntry!.isIncome
                            ? 'Delete income'
                            : 'Delete expense',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(_entryDate);
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      // Push the sheet above the software keyboard when it is visible.
      padding: EdgeInsets.only(bottom: keyboardHeight),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Spacing.cardRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrollable form content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
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
                    widget.initialEntry != null ? 'Edit Entry' : 'Add Entry',
                    style: AppTextStyles.displayMedium
                        .copyWith(color: context.colors.textPrimary),
                  ),
                  const SizedBox(height: Spacing.space20),

                  // Income / Expense segmented toggle
                  _SegmentedToggle(
                    isIncome: _isIncome,
                    onChanged: _setIsIncome,
                  ),
                  const SizedBox(height: Spacing.space20),

                  // Entry type pills
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Type',
                        style: AppTextStyles.footnote
                            .copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      _TypePillRow(
                        labels:
                            _isIncome ? _incomeTypeLabels : _expenseTypeLabels,
                        selected: _selectedTypeName,
                        isDeleteMode: _isDeleteTypeMode,
                        onSelect: (label) {
                          if (!_isDeleteTypeMode) {
                            setState(() => _selectedTypeName = label);
                          }
                        },
                        onAdd: () {
                          if (_isDeleteTypeMode) {
                            setState(() => _isDeleteTypeMode = false);
                          }
                          _showAddTypeDialog();
                        },
                        onToggleDelete: () => setState(
                            () => _isDeleteTypeMode = !_isDeleteTypeMode),
                        onRemove: (label) => setState(() {
                          final list = _isIncome
                              ? _incomeTypeLabels
                              : _expenseTypeLabels;
                          list.remove(label);
                          if (_selectedTypeName == label) {
                            _selectedTypeName =
                                list.isNotEmpty ? list.first : '';
                          }
                        }),
                      ),
                      const SizedBox(height: Spacing.space16),
                    ],
                  ),

                  CurrencyTextField(
                    controller: _amountController,
                    label: 'Amount',
                    hint: r'$0.00',
                    enabled: true,
                  ),
                  const SizedBox(height: Spacing.space16),

                  // Date
                  Text(
                    'Date',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
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

                  // Payer (income) / Paid To (expense)
                  Text(
                    _isIncome ? 'Payer (optional)' : 'Paid To (optional)',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _payerController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    hintText: _isIncome
                        ? 'e.g., Bowery Electric'
                        : 'e.g., Drum World',
                  ),
                  const SizedBox(height: Spacing.space16),

                  // Paid To (income) / Paid By (expense)
                  Text(
                    _isIncome ? 'Paid To (optional)' : 'Paid By (optional)',
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
                    enabled: true,
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
                  if (_isOtherPaidToSelected) ...[
                    AppTextField(
                      controller: _paidToOtherController,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.next,
                      hintText: 'Enter name',
                    ),
                    const SizedBox(height: Spacing.space16),
                  ] else
                    const SizedBox(height: Spacing.space4),

                  // Description
                  Text(
                    'Description (optional)',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    hintText: 'e.g. Purchased P.A. System',
                  ),
                  const SizedBox(height: Spacing.space16),

                  // 1099 toggle (income only)
                  Visibility(
                    visible: _isIncome,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Column(
                      children: [
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
                              onChanged: (v) =>
                                  setState(() => _is1099Expected = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.space16),
                      ],
                    ),
                  ),

                  // Disburse to Band toggle (income only, when members available)
                  if (_isIncome && widget.members.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Disburse to Band',
                          style: AppTextStyles.callout
                              .copyWith(color: context.colors.textPrimary),
                        ),
                        AppSwitch(
                          value: _disburse,
                          onChanged: _onDisburseToggle,
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _disburse
                          ? Padding(
                              padding:
                                  const EdgeInsets.only(top: Spacing.space12),
                              child: Column(
                                children: widget.members.map((member) {
                                  final ctrl = _splitControllers[member.userId];
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: Spacing.space12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _shortName(member),
                                            style: AppTextStyles.callout
                                                .copyWith(
                                                    color: context
                                                        .colors.textPrimary),
                                          ),
                                        ),
                                        const SizedBox(width: Spacing.space12),
                                        Expanded(
                                          child: ctrl != null
                                              ? CurrencyTextField(
                                                  controller: ctrl,
                                                  label: '',
                                                  hint: r'$0.00',
                                                  clearOnFocus: true,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: Spacing.space16),
                  ],

                  // Deposit to Savings toggle (income only)
                  if (_isIncome) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Deposit to Savings',
                              style: AppTextStyles.callout
                                  .copyWith(color: context.colors.textPrimary),
                            ),
                            if (widget.savingsTotalCents != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${_formatSavingsCents(widget.savingsTotalCents!)})',
                                style: AppTextStyles.callout
                                    .copyWith(color: context.colors.success),
                              ),
                            ],
                          ],
                        ),
                        AppSwitch(
                          value: _depositToSavings,
                          onChanged: (v) {
                            setState(() {
                              _depositToSavings = v;
                              if (v && _disburse) {
                                final totalDisbursed = _splitControllers.values
                                    .fold<int>(0, (sum, c) => sum + c.cents);
                                final remaining =
                                    _amountController.cents - totalDisbursed;
                                if (remaining > 0) {
                                  _depositToSavingsController.cents = remaining;
                                }
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _depositToSavings
                          ? Padding(
                              padding:
                                  const EdgeInsets.only(top: Spacing.space12),
                              child: CurrencyTextField(
                                controller: _depositToSavingsController,
                                label: 'Savings Amount',
                                hint: r'$0.00',
                                clearOnFocus: true,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: Spacing.space16),
                  ],
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

// ---------------------------------------------------------------------------
// SEGMENTED TOGGLE  (Income / Expense)
// ---------------------------------------------------------------------------

class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle({required this.isIncome, required this.onChanged});

  final bool isIncome;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final currentIndex = isIncome ? 0 : 1;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                alignment: Alignment(-1.0 + (2.0 * currentIndex), 0.0),
                duration: AppDurations.fast,
                curve: AppCurves.ease,
                child: Container(
                  width: segmentWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        onChanged(true);
                        HapticFeedback.selectionClick();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: AppDurations.fast,
                          curve: AppCurves.ease,
                          style: TextStyle(
                            fontSize: AppFontSizes.subhead,
                            fontWeight: FontWeight.w600,
                            color: isIncome
                                ? Colors.white
                                : context.colors.textPrimary,
                          ),
                          child: const Text('Income'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        onChanged(false);
                        HapticFeedback.selectionClick();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: AppDurations.fast,
                          curve: AppCurves.ease,
                          style: TextStyle(
                            fontSize: AppFontSizes.subhead,
                            fontWeight: FontWeight.w600,
                            color: !isIncome
                                ? Colors.white
                                : context.colors.textPrimary,
                          ),
                          child: const Text('Expense'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TYPE PILL ROW  (+ Add | Remove  label1  label2  …)
// ---------------------------------------------------------------------------

class _TypePillRow extends StatelessWidget {
  const _TypePillRow({
    required this.labels,
    required this.selected,
    required this.isDeleteMode,
    required this.onSelect,
    required this.onAdd,
    required this.onToggleDelete,
    required this.onRemove,
  });

  final List<String> labels;
  final String selected;
  final bool isDeleteMode;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onToggleDelete;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // + Add button
          _TypePill(
            label: '+ Add',
            isSelected: false,
            isAddButton: true,
            onTap: onAdd,
          ),
          const SizedBox(width: 8),
          // Remove / Done toggle button
          _TypePill(
            label: isDeleteMode ? 'Done' : 'Remove',
            isSelected: isDeleteMode,
            isRemoveButton: true,
            onTap: onToggleDelete,
          ),
          const SizedBox(width: 16),
          // Type labels
          ...labels.expand(
            (label) => [
              _TypePill(
                label: label,
                isSelected: !isDeleteMode && selected == label,
                showDeleteIcon: isDeleteMode,
                onTap: isDeleteMode
                    ? () => onRemove(label)
                    : () => onSelect(label),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TYPE PILL  (individual chip, mirrors _RolePill from my_profile_screen)
// ---------------------------------------------------------------------------

class _TypePill extends StatefulWidget {
  const _TypePill({
    required this.label,
    required this.isSelected,
    this.isAddButton = false,
    this.isRemoveButton = false,
    this.showDeleteIcon = false,
    this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isAddButton;
  final bool isRemoveButton;
  final bool showDeleteIcon;
  final VoidCallback? onTap;

  @override
  State<_TypePill> createState() => _TypePillState();
}

class _TypePillState extends State<_TypePill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const rose600 = AppColors.primary;

    Color borderColor;
    if (widget.isAddButton || widget.isRemoveButton) {
      borderColor = rose600;
    } else if (widget.isSelected) {
      borderColor = context.colors.primaryDim;
    } else {
      borderColor = context.colors.surfaceOverlay;
    }

    Color textColor;
    if (widget.isAddButton || widget.isRemoveButton) {
      textColor = widget.isSelected ? Colors.white : rose600;
    } else if (widget.isSelected) {
      textColor = Colors.white;
    } else {
      textColor = context.colors.textSecondary;
    }

    Color bgColor;
    if (widget.isRemoveButton && widget.isSelected) {
      bgColor = rose600;
    } else if (widget.isSelected && !widget.isAddButton) {
      bgColor = context.colors.primaryDim;
    } else {
      bgColor = Colors.transparent;
    }

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showDeleteIcon) ...[
                  const Icon(AppIcons.close, size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ).copyWith(color: textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
