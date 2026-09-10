// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:bandroadie/app/models/gig.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/event_editor_theme.dart';
import '../../../components/ui/adaptive_text_selection_toolbar.dart';
import '../../../components/ui/app_date_picker.dart';
import '../../../components/ui/app_dropdown.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/confirm_action_dialog.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../features/members/member_vm.dart';
import '../../bands/active_band_controller.dart';
import '../../contacts/contacts_controller.dart';
import '../../contacts/venues_controller.dart';
import '../../gigs/gig_controller.dart';
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
  String? gigId,
  bool? isReimbursed,
  DateTime? reimbursedDate,
  String? reimbursementMethod,
  String? notes,
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
/// [onSave] additionally receives gigId, isReimbursed, reimbursedDate,
/// reimbursementMethod, and notes for the redesigned drawer's new fields.
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
    useSafeArea: true,
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

class _AddFinancialEntryBottomSheet extends ConsumerStatefulWidget {
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
  ConsumerState<_AddFinancialEntryBottomSheet> createState() =>
      _AddFinancialEntryBottomSheetState();
}

class _AddFinancialEntryBottomSheetState
    extends ConsumerState<_AddFinancialEntryBottomSheet> {
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
  Map<String, String> _distributionErrors = const {};
  final Map<String, CurrencyInputController> _splitControllers = {};

  late final CurrencyInputController _depositToSavingsController;

  late final CurrencyInputController _amountController;
  late final TextEditingController _descriptionController;
  late final FAutocompleteController _payerController;
  late final TextEditingController _paidToOtherController;
  late final TextEditingController _reimbursementMethodOtherController;
  late final TextEditingController _notesController;

  String? _paidToUserId;
  static const String _kOther = '__other__';
  bool get _isOtherPaidToSelected => _paidToUserId == _kOther;

  static const List<String> _kReimbursementMethods = [
    'Zelle',
    'Venmo',
    'Cash',
    'Check',
    'Other',
  ];

  String? _selectedGigId;
  bool _isReimbursed = false;
  DateTime? _reimbursedDate;
  String? _reimbursementMethod;

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
      _payerController = FAutocompleteController(text: entry.payerName ?? '');
      _paidToOtherController = TextEditingController();
      _notesController = TextEditingController(text: entry.notes ?? '');
      _selectedGigId = entry.gigId;
      _isReimbursed = entry.isReimbursed;
      _reimbursedDate = entry.reimbursedDate;
      final method = entry.reimbursementMethod;
      if (method != null && _kReimbursementMethods.contains(method)) {
        _reimbursementMethod = method;
        _reimbursementMethodOtherController = TextEditingController();
      } else if (method != null && method.isNotEmpty) {
        _reimbursementMethod = 'Other';
        _reimbursementMethodOtherController =
            TextEditingController(text: method);
      } else {
        _reimbursementMethodOtherController = TextEditingController();
      }
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
      _payerController = FAutocompleteController();
      _paidToOtherController = TextEditingController();
      _reimbursementMethodOtherController = TextEditingController();
      _notesController = TextEditingController();
    }
    _amountController.addListener(_onAmountChanged);
    _distributionErrors = _computeInitialDistributionErrors();

    Future.microtask(() {
      if (!mounted) return;
      final bandId = ref.read(activeBandIdProvider);
      if (bandId == null) return;
      if (ref.read(contactsProvider).contacts.isEmpty) {
        ref.read(contactsProvider.notifier).load(bandId);
      }
      if (ref.read(venuesProvider).venues.isEmpty) {
        ref.read(venuesProvider.notifier).load(bandId);
      }
      if (ref.read(gigProvider).allGigs.isEmpty) {
        ref.read(gigProvider.notifier).loadGigs();
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _descriptionController.dispose();
    _payerController.dispose();
    _paidToOtherController.dispose();
    _reimbursementMethodOtherController.dispose();
    _notesController.dispose();
    for (final c in _splitControllers.values) {
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
      if (!isIncome) {
        _distributionErrors = const {};
      }
      if (isIncome && _isReimbursed) {
        _isReimbursed = false;
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
    _syncDistributionState();
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
      _splitControllers.putIfAbsent(m.userId, CurrencyInputController.new);
      _splitControllers[m.userId]!.cents =
          i == 0 ? perMember + remainder : perMember;
    }
  }

  /// Called on every user edit of the total Amount field. Amount changes
  /// have no natural field of their own, so attribution always falls back.
  void _onAmountChanged() => _syncDistributionState();

  /// Pure (no setState) computation of the initial distribution error map,
  /// used to seed `_distributionErrors` in `initState` for pre-existing
  /// over-allocated entries (e.g. edit-mode data saved before this
  /// validation existed).
  Map<String, String> _computeInitialDistributionErrors() {
    final total = _amountController.cents;
    final savingsCents =
        _depositToSavings ? _depositToSavingsController.cents : 0;
    final totalSplits = _disburse
        ? _splitControllers.values.fold<int>(0, (s, c) => s + c.cents)
        : 0;
    final overBy = (totalSplits + savingsCents) - total;
    if (overBy > 0) {
      final attributeTo = _pickFallbackErrorAttribution();
      if (attributeTo != null) {
        return {attributeTo: 'Exceeds remaining balance'};
      }
    }
    return const {};
  }

  /// Used when the trigger has no natural field to attribute to (Amount
  /// change, Disburse toggle, income/expense switch). Prefers Savings when
  /// it's the only enabled destination; otherwise flags the largest
  /// non-zero split (most likely to be user-set high).
  String? _pickFallbackErrorAttribution() {
    if (_depositToSavings && _depositToSavingsController.cents > 0) {
      return 'savings';
    }
    if (_disburse) {
      String? key;
      int max = 0;
      for (final entry in _splitControllers.entries) {
        if (entry.value.cents > max) {
          max = entry.value.cents;
          key = 'split:${entry.key}';
        }
      }
      return key;
    }
    return null;
  }

  /// Re-runs the Disburse-ON auto-balance side effect (unchanged from the
  /// prior `_onDisbursementChanged` behavior — preserved verbatim, including
  /// the setState-wrapped Deposit-to-Savings auto-enable) and then recomputes
  /// the over-allocation error map, attributing any violation to
  /// [changedFieldKey] when given, or a fallback field otherwise.
  void _syncDistributionState({String? changedFieldKey}) {
    if (_disburse) {
      final totalDisbursed =
          _splitControllers.values.fold<int>(0, (sum, c) => sum + c.cents);
      final remaining = _amountController.cents - totalDisbursed;
      if (remaining > 0) {
        _depositToSavingsController.cents = remaining;
        if (!_depositToSavings) {
          setState(() => _depositToSavings = true);
        }
      } else {
        _depositToSavingsController.cents = 0;
      }
    }

    final total = _amountController.cents;
    final savingsCents =
        _depositToSavings ? _depositToSavingsController.cents : 0;
    final totalSplits = _disburse
        ? _splitControllers.values.fold<int>(0, (s, c) => s + c.cents)
        : 0;
    final overBy = (totalSplits + savingsCents) - total;

    Map<String, String> next = const {};
    if (overBy > 0) {
      final attributeTo = changedFieldKey ?? _pickFallbackErrorAttribution();
      if (attributeTo != null) {
        next = {attributeTo: 'Exceeds remaining balance'};
      }
    }
    if (!mapEquals(next, _distributionErrors)) {
      setState(() => _distributionErrors = next);
    }
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

    final isReimbursed = !_isIncome ? _isReimbursed : null;
    final reimbursedDate =
        (!_isIncome && _isReimbursed) ? _reimbursedDate : null;
    String? reimbursementMethod;
    if (!_isIncome && _isReimbursed) {
      if (_reimbursementMethod == 'Other') {
        final other = _reimbursementMethodOtherController.text.trim();
        reimbursementMethod = other.isEmpty ? null : other;
      } else {
        reimbursementMethod = _reimbursementMethod;
      }
    }

    final notes = _notesController.text.trim();

    String? paidToUserId;
    String? paidToName;
    if (_isIncome) {
      // Income mode no longer edits paid-to; preserve whatever was saved.
      paidToUserId = widget.initialEntry?.paidToUserId;
      paidToName = widget.initialEntry?.paidToName;
    } else {
      paidToUserId = _paidToUserId == _kOther ? null : _paidToUserId;
      paidToName = () {
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
      }();
    }

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
        paidToUserId: paidToUserId,
        paidToName: paidToName,
        disbursements: disbursements,
        depositToSavings: _isIncome ? _depositToSavings : null,
        depositToSavingsCents: depositToSavingsCents,
        gigId: _selectedGigId,
        isReimbursed: isReimbursed,
        reimbursedDate: reimbursedDate,
        reimbursementMethod: reimbursementMethod,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (e.code == '23505' && e.message.contains('uniq_gig_pay_entry')) {
        showErrorSnackBar(
          context,
          message:
              'This gig already has a Gig Pay entry. Open the gig to edit it instead.',
        );
      } else {
        showErrorSnackBar(context, message: e.message);
      }
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
    final enabled = _amountController.cents > 0 && _distributionErrors.isEmpty;
    final canDelete = ref.watch(currentUserPermissionsProvider).when(
          data: (p) => p.canDeleteFinancials,
          loading: () => false,
          error: (_, __) => false,
        );
    final showDestructive =
        widget.initialEntry != null && widget.onDelete != null && canDelete;
    return SheetFooter(
      primaryLabel: widget.initialEntry != null ? 'Save' : 'Add Transaction',
      onPrimary: enabled ? _save : null,
      primaryIsLoading: _isSaving,
      onCancel: () => Navigator.of(context).pop(),
      destructiveLabel: showDestructive
          ? (widget.initialEntry!.isIncome ? 'Delete Income' : 'Delete Expense')
          : null,
      onDestructive: showDestructive ? _handleDelete : null,
    );
  }

  Widget _buildStickyHeader(BuildContext context) {
    final isEdit = widget.initialEntry != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit Transaction' : 'Add Transaction',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFAFAFA),
                ),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 2),
                const Text(
                  "Track your band's income or expense.",
                  style: TextStyle(fontSize: 14, color: Color(0xFF8b8b93)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 16, color: Color(0xFFA1A1AA)),
            style: IconButton.styleFrom(
              backgroundColor: kEdCardBorder,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    final dateStr = DateFormat('MMM d, yyyy').format(_entryDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type',
          style: AppTextStyles.footnote
              .copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        _TypePillRow(
          labels: _isIncome ? _incomeTypeLabels : _expenseTypeLabels,
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
          onToggleDelete: () =>
              setState(() => _isDeleteTypeMode = !_isDeleteTypeMode),
          onRemove: (label) => setState(() {
            final list = _isIncome ? _incomeTypeLabels : _expenseTypeLabels;
            list.remove(label);
            if (_selectedTypeName == label) {
              _selectedTypeName = list.isNotEmpty ? list.first : '';
            }
          }),
        ),
        const SizedBox(height: Spacing.space16),
        CurrencyTextField(
          controller: _amountController,
          label: 'Amount',
        ),
        const SizedBox(height: Spacing.space16),
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
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            ),
            minimumSize: const Size(double.infinity, 48),
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: Spacing.space16),
        Text(
          'Short description',
          style: AppTextStyles.footnote
              .copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          hintText: _isIncome
              ? 'Where did the money come from?'
              : 'e.g., Dinner after rehearsal',
        ),
      ],
    );
  }

  /// Merged, deduplicated (by lowercased name) contact + venue suggestions.
  /// Used for both income "Payment from" and expense "Paid to".
  Widget _buildPaymentFromAutocomplete(BuildContext context) {
    final contacts = ref.watch(contactsProvider).contacts;
    final venues = ref.watch(venuesProvider).venues;

    final tagByName = <String, String>{};
    final names = <String>[];
    for (final c in contacts) {
      final key = c.name.trim().toLowerCase();
      if (key.isEmpty || tagByName.containsKey(key)) continue;
      tagByName[key] = 'Contact';
      names.add(c.name);
    }
    for (final v in venues) {
      final key = v.name.trim().toLowerCase();
      if (key.isEmpty || tagByName.containsKey(key)) continue;
      tagByName[key] = 'Venue';
      names.add(v.name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isIncome ? 'Payment from' : 'Paid to',
          style: AppTextStyles.footnote
              .copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        FAutocomplete.textBuilder(
          control: FAutocompleteControl.managed(
            controller: _payerController,
            onChange: (_) {},
          ),
          filter: (query) {
            if (query.length < 2) return const Iterable<String>.empty();
            final lower = query.toLowerCase();
            return names.where((n) => n.toLowerCase().contains(lower));
          },
          contentBuilder: (context, query, values) {
            final trimmed = query.trim();
            if (trimmed.length < 2) return const [];
            final items = <FAutocompleteItemMixin<String>>[
              for (final name in values)
                FAutocompleteItem.item(
                  value: name,
                  title: Row(
                    children: [
                      Expanded(child: Text(name)),
                      Text(
                        tagByName[name.toLowerCase()] ?? '',
                        style: AppTextStyles.footnote
                            .copyWith(color: context.colors.textMuted),
                      ),
                    ],
                  ),
                ),
            ];
            final hasExactMatch =
                names.any((n) => n.toLowerCase() == trimmed.toLowerCase());
            if (!hasExactMatch) {
              items.add(
                FAutocompleteItem.item(
                  value: trimmed,
                  title: Text('Use "$trimmed"'),
                ),
              );
            }
            return items;
          },
          hint: _isIncome ? 'e.g., Bowery Electric' : 'e.g., Drum World',
          textCapitalization: TextCapitalization.words,
          contextMenuBuilder: buildLocalizedAdaptiveTextSelectionToolbar,
        ),
      ],
    );
  }

  Widget _buildPaidByDropdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paid by',
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
          items: [
            DropdownMenuItem<String?>(
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
        if (_isOtherPaidToSelected)
          AppTextField(
            controller: _paidToOtherController,
            textInputAction: TextInputAction.next,
            hintText: 'Enter name',
          ),
      ],
    );
  }

  Widget _buildRelatedGigDropdown(BuildContext context) {
    final gigs = List<Gig>.from(ref.watch(gigProvider).allGigs)
      ..sort((a, b) => b.date.compareTo(a.date));
    String labelFor(Gig gig) =>
        '${gig.name} — ${DateFormat('MMM d, yyyy').format(gig.date)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Related to Gig (optional)',
          style: AppTextStyles.footnote
              .copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        AppDropdown<String?>(
          value: _selectedGigId,
          onChanged: (value) => setState(() => _selectedGigId = value),
          labelBuilder: (value) {
            if (value == null) return 'Not linked';
            final gig = gigs
                .cast<Gig?>()
                .firstWhere((g) => g!.id == value, orElse: () => null);
            return gig != null ? labelFor(gig) : 'Unknown gig';
          },
          items: [
            DropdownMenuItem<String?>(
              child: Text(
                'Not linked',
                style: AppTextStyles.callout
                    .copyWith(color: context.colors.textMuted),
              ),
            ),
            ...gigs.map(
              (gig) => DropdownMenuItem<String?>(
                value: gig.id,
                child: Text(labelFor(gig)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentDetailsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPaymentFromAutocomplete(context),
        const SizedBox(height: Spacing.space16),
        if (!_isIncome) ...[
          _buildPaidByDropdown(context),
          const SizedBox(height: Spacing.space16),
        ],
        _buildRelatedGigDropdown(context),
      ],
    );
  }

  Widget _buildDistributionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              onChanged: (v) => setState(() => _is1099Expected = v),
            ),
          ],
        ),
        const SizedBox(height: Spacing.space16),
        if (widget.members.isNotEmpty) ...[
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
                    padding: const EdgeInsets.only(top: Spacing.space12),
                    child: Column(
                      children: widget.members.map((member) {
                        final ctrl = _splitControllers[member.userId];
                        final error =
                            _distributionErrors['split:${member.userId}'];
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: Spacing.space12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _shortName(member),
                                      style: AppTextStyles.callout.copyWith(
                                          color: context.colors.textPrimary),
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.space12),
                                  Expanded(
                                    child: ctrl != null
                                        ? CurrencyTextField(
                                            controller: ctrl,
                                            label: '',
                                            clearOnFocus: true,
                                            onChanged: () =>
                                                _syncDistributionState(
                                              changedFieldKey:
                                                  'split:${member.userId}',
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Expanded(child: SizedBox.shrink()),
                                    const SizedBox(width: Spacing.space12),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: AppTextStyles.footnote
                                            .copyWith(color: AppColors.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                  if (!v) {
                    _depositToSavingsController.cents = 0;
                  } else if (_disburse) {
                    final totalDisbursed = _splitControllers.values
                        .fold<int>(0, (sum, c) => sum + c.cents);
                    final remaining = _amountController.cents - totalDisbursed;
                    _depositToSavingsController.cents =
                        remaining > 0 ? remaining : 0;
                  } else {
                    _depositToSavingsController.cents = _amountController.cents;
                  }
                });
                _syncDistributionState();
              },
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _depositToSavings
              ? Padding(
                  padding: const EdgeInsets.only(top: Spacing.space12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CurrencyTextField(
                        controller: _depositToSavingsController,
                        label: 'Savings Amount',
                        clearOnFocus: true,
                        onChanged: () => _syncDistributionState(
                          changedFieldKey: 'savings',
                        ),
                      ),
                      if (_distributionErrors['savings'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _distributionErrors['savings']!,
                          style: AppTextStyles.footnote
                              .copyWith(color: AppColors.error),
                        ),
                      ] else if (_disburse) ...[
                        const SizedBox(height: Spacing.space4),
                        Text(
                          'Automatically calculated from remaining amount.',
                          style: AppTextStyles.footnote
                              .copyWith(color: context.colors.textMuted),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _pickReimbursedDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _reimbursedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() => _reimbursedDate = picked);
  }

  Widget _buildReimbursementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reimbursed by Band',
              style: AppTextStyles.callout
                  .copyWith(color: context.colors.textPrimary),
            ),
            AppSwitch(
              value: _isReimbursed,
              onChanged: (v) {
                setState(() {
                  _isReimbursed = v;
                  if (v) {
                    _reimbursedDate ??= DateTime.now();
                  }
                });
              },
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isReimbursed
              ? Padding(
                  padding: const EdgeInsets.only(top: Spacing.space12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reimbursed on',
                        style: AppTextStyles.footnote
                            .copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _pickReimbursedDate,
                        icon: const Icon(AppIcons.calendar, size: 16),
                        label: Text(DateFormat('MMM d, yyyy')
                            .format(_reimbursedDate ?? DateTime.now())),
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
                      Text(
                        'Method',
                        style: AppTextStyles.footnote
                            .copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      AppDropdown<String?>(
                        value: _reimbursementMethod,
                        onChanged: (v) =>
                            setState(() => _reimbursementMethod = v),
                        labelBuilder: (value) => value ?? 'Select method',
                        items: [
                          DropdownMenuItem<String?>(
                            child: Text(
                              'Select method',
                              style: AppTextStyles.callout
                                  .copyWith(color: context.colors.textMuted),
                            ),
                          ),
                          ..._kReimbursementMethods.map(
                            (method) => DropdownMenuItem<String?>(
                              value: method,
                              child: Text(method),
                            ),
                          ),
                        ],
                      ),
                      if (_reimbursementMethod == 'Other') ...[
                        const SizedBox(height: Spacing.space12),
                        AppTextField(
                          controller: _reimbursementMethodOtherController,
                          textInputAction: TextInputAction.done,
                          hintText: 'e.g., PayPal',
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return AppTextField(
      controller: _notesController,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      minLines: 3,
      maxLines: 5,
      hintText: 'Add any extra context…',
    );
  }

  Widget _buildScrollableBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStickyHeader(context),
        const SizedBox(height: 12),
        _SegmentedToggle(
          isIncome: _isIncome,
          onChanged: _setIsIncome,
        ),
        const SizedBox(height: 16),
        _SectionCard(title: 'About', child: _buildAboutSection()),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Payment Details',
          child: _buildPaymentDetailsSection(context),
        ),
        const SizedBox(height: 16),
        if (_isIncome)
          _SectionCard(
            title: 'Distribution',
            child: _buildDistributionSection(),
          )
        else
          _SectionCard(
            title: 'Reimbursement',
            child: _buildReimbursementSection(),
          ),
        const SizedBox(height: 16),
        _SectionCard(title: 'Notes', child: _buildNotesSection()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTheme(
      data: buildEventEditorTheme(),
      child: Container(
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          color: kEdSurface,
          border: Border.all(color: kEdCardBorder),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 60,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildScrollableBody(context),
              ),
            ),
            _buildFixedBottomActions(),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kEdCardBg,
        border: Border.all(color: kEdCardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.7,
              color: Color(0xFFFAFAFA),
            ),
          ),
          const SizedBox(height: 20),
          child,
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
