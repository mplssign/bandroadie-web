import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_dropdown.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../../members/member_vm.dart';

class GigExpenseDraft {
  const GigExpenseDraft({
    required this.localId,
    required this.amountCents,
    required this.category,
    required this.entryDate,
    this.existingEntryId,
    this.paidByUserId,
    this.paidByName,
    this.notes,
    this.isReimbursed = false,
    this.reimbursedDate,
  });

  final String localId;
  final String? existingEntryId;
  final int amountCents;
  final String category;
  final DateTime entryDate;
  final String? paidByUserId;
  final String? paidByName;
  final String? notes;
  final bool isReimbursed;
  final DateTime? reimbursedDate;

  String get formattedAmount {
    final dollars = amountCents ~/ 100;
    final cents = amountCents % 100;
    final dollarsFormatted = NumberFormat('#,##0').format(dollars);
    return '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';
  }

  GigExpenseDraft copyWith({
    String? localId,
    String? existingEntryId,
    int? amountCents,
    String? category,
    DateTime? entryDate,
    String? paidByUserId,
    String? paidByName,
    String? notes,
    bool? isReimbursed,
    DateTime? reimbursedDate,
    bool clearExistingEntryId = false,
    bool clearPaidByUserId = false,
    bool clearPaidByName = false,
    bool clearNotes = false,
    bool clearReimbursedDate = false,
  }) {
    return GigExpenseDraft(
      localId: localId ?? this.localId,
      existingEntryId: clearExistingEntryId
          ? null
          : (existingEntryId ?? this.existingEntryId),
      amountCents: amountCents ?? this.amountCents,
      category: category ?? this.category,
      entryDate: entryDate ?? this.entryDate,
      paidByUserId:
          clearPaidByUserId ? null : (paidByUserId ?? this.paidByUserId),
      paidByName: clearPaidByName ? null : (paidByName ?? this.paidByName),
      notes: clearNotes ? null : (notes ?? this.notes),
      isReimbursed: isReimbursed ?? this.isReimbursed,
      reimbursedDate:
          clearReimbursedDate ? null : (reimbursedDate ?? this.reimbursedDate),
    );
  }
}

class GigExpenseSubView extends StatefulWidget {
  const GigExpenseSubView({
    super.key,
    required this.members,
    required this.defaultDate,
    required this.onBack,
    required this.onSave,
    required this.canEdit,
    required this.canDelete,
    this.initialExpense,
    this.onDelete,
    this.isSaving = false,
    this.isDeleting = false,
  });

  final List<MemberVM> members;
  final DateTime defaultDate;
  final GigExpenseDraft? initialExpense;
  final VoidCallback onBack;
  final Future<void> Function(GigExpenseDraft draft) onSave;
  final Future<void> Function(GigExpenseDraft draft)? onDelete;
  final bool canEdit;
  final bool canDelete;
  final bool isSaving;
  final bool isDeleting;

  @override
  State<GigExpenseSubView> createState() => _GigExpenseSubViewState();
}

class _GigExpenseSubViewState extends State<GigExpenseSubView> {
  static const String _kOther = '__other__';
  static const List<String> _kPresetCategories = [
    'Marketing',
    'Equipment Rental',
    'Sound Company',
    'Travel Fees',
    'Vehicle Rental (Van/Trailer)',
    'Lodging',
    'Meals & Per Diems',
    'Merch/Supplies',
    'Booking/Agent Fee',
    'Venue Fee',
    'Other',
  ];

  late final CurrencyInputController _amountController;
  late final TextEditingController _customCategoryController;
  late final TextEditingController _paidByOtherController;
  late final TextEditingController _notesController;

  late DateTime _entryDate;
  DateTime? _reimbursedDate;
  late String _selectedCategory;
  String? _paidByUserId;
  bool _isReimbursed = false;

  bool get _isOtherCategory => _selectedCategory == 'Other';
  bool get _isOtherPaidBy => _paidByUserId == _kOther;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExpense;

    _amountController = CurrencyInputController(initial?.amountCents ?? 0);
    _customCategoryController = TextEditingController();
    _paidByOtherController = TextEditingController();
    _notesController = TextEditingController(text: initial?.notes ?? '');

    _entryDate = initial?.entryDate ?? widget.defaultDate;
    _isReimbursed = initial?.isReimbursed ?? false;
    _reimbursedDate = initial?.reimbursedDate;

    final initialCategory = initial?.category;
    if (initialCategory != null &&
        _kPresetCategories.contains(initialCategory) &&
        initialCategory != 'Other') {
      _selectedCategory = initialCategory;
    } else if (initialCategory != null && initialCategory.isNotEmpty) {
      _selectedCategory = 'Other';
      _customCategoryController.text = initialCategory;
    } else {
      _selectedCategory = _kPresetCategories.first;
    }

    if (initial?.paidByUserId != null) {
      _paidByUserId = initial!.paidByUserId;
    } else if (initial?.paidByName != null && initial!.paidByName!.isNotEmpty) {
      _paidByUserId = _kOther;
      _paidByOtherController.text = initial.paidByName!;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _customCategoryController.dispose();
    _paidByOtherController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
    );
    if (!mounted || picked == null) return;
    setState(() => _entryDate = picked);
  }

  Future<void> _pickReimbursedDate() async {
    final initialDate = _reimbursedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
    );
    if (!mounted || picked == null) return;
    setState(() => _reimbursedDate = picked);
  }

  String _resolvedCategory() {
    if (!_isOtherCategory) return _selectedCategory;
    return _customCategoryController.text.trim();
  }

  String? _resolvePaidByName() {
    if (_isOtherPaidBy) {
      final value = _paidByOtherController.text.trim();
      return value.isEmpty ? null : value;
    }

    if (_paidByUserId == null) return null;
    return widget.members
        .where((m) => m.userId == _paidByUserId)
        .firstOrNull
        ?.name;
  }

  Future<void> _handleSave() async {
    if (!widget.canEdit || widget.isSaving) return;

    final category = _resolvedCategory();
    if (_amountController.cents <= 0 || category.isEmpty) return;

    final existing = widget.initialExpense;
    final draft = GigExpenseDraft(
      localId: existing?.localId ??
          'expense_${DateTime.now().microsecondsSinceEpoch.toString()}',
      existingEntryId: existing?.existingEntryId,
      amountCents: _amountController.cents,
      category: category,
      entryDate: _entryDate,
      paidByUserId: _isOtherPaidBy ? null : _paidByUserId,
      paidByName: _resolvePaidByName(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      isReimbursed: _isReimbursed,
      reimbursedDate:
          _isReimbursed ? (_reimbursedDate ?? DateTime.now()) : null,
    );

    await widget.onSave(draft);
  }

  Future<void> _handleDelete() async {
    if (!widget.canDelete || widget.isDeleting) return;
    final onDelete = widget.onDelete;
    final existing = widget.initialExpense;
    if (onDelete == null || existing == null) return;
    await onDelete(existing);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = widget.canEdit &&
        !widget.isSaving &&
        _amountController.cents > 0 &&
        _resolvedCategory().isNotEmpty;
    final dateLabel = DateFormat('MMM d, yyyy').format(_entryDate);
    final reimbursedDateLabel =
        DateFormat('MMM d, yyyy').format(_reimbursedDate ?? DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CurrencyTextField(
          controller: _amountController,
          label: 'Amount',
          hint: '\$0.00',
          enabled: widget.canEdit && !widget.isSaving,
        ),
        const SizedBox(height: Spacing.space16),
        Text(
          'Category',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppDropdown<String>(
          value: _selectedCategory,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedCategory = value);
          },
          enabled: widget.canEdit && !widget.isSaving,
          items: _kPresetCategories
              .map(
                (value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(
                    value,
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (_isOtherCategory) ...[
          const SizedBox(height: Spacing.space12),
          AppTextField(
            controller: _customCategoryController,
            enabled: widget.canEdit && !widget.isSaving,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Custom category',
              hintStyle: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
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
        ],
        const SizedBox(height: Spacing.space16),
        Text(
          'Date',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppButton(
          label: dateLabel,
          variant: AppButtonVariant.outlined,
          icon: AppIcons.calendar,
          fullWidth: true,
          onPressed: widget.canEdit && !widget.isSaving ? _pickDate : null,
        ),
        const SizedBox(height: Spacing.space16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Mark as Reimbursed',
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            AppSwitch(
              value: _isReimbursed,
              activeColor: AppColors.primary,
              onChanged: widget.canEdit && !widget.isSaving
                  ? (value) {
                      setState(() {
                        _isReimbursed = value;
                        if (value && _reimbursedDate == null) {
                          _reimbursedDate = DateTime.now();
                        }
                        if (!value) {
                          _reimbursedDate = null;
                        }
                      });
                    }
                  : null,
            ),
          ],
        ),
        if (_isReimbursed) ...[
          const SizedBox(height: Spacing.space12),
          Text(
            'Reimbursement date',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          AppButton(
            label: reimbursedDateLabel,
            variant: AppButtonVariant.outlined,
            icon: AppIcons.calendar,
            fullWidth: true,
            onPressed:
                widget.canEdit && !widget.isSaving ? _pickReimbursedDate : null,
          ),
        ],
        const SizedBox(height: Spacing.space16),
        Text(
          'Paid by (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppDropdown<String?>(
          value: _paidByUserId,
          onChanged: (value) {
            setState(() => _paidByUserId = value);
          },
          enabled: widget.canEdit && !widget.isSaving,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'None',
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            ...widget.members.map(
              (member) => DropdownMenuItem<String?>(
                value: member.userId,
                child: Text(
                  member.name,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
            DropdownMenuItem<String?>(
              value: _kOther,
              child: Text(
                'Other',
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (_isOtherPaidBy) ...[
          const SizedBox(height: Spacing.space12),
          AppTextField(
            controller: _paidByOtherController,
            enabled: widget.canEdit && !widget.isSaving,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Who paid?',
              hintStyle: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
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
        ],
        const SizedBox(height: Spacing.space16),
        Text(
          'Description (optional)',
          style: AppTextStyles.footnote
              .copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: _notesController,
          enabled: widget.canEdit && !widget.isSaving,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          minLines: 3,
          maxLines: 4,
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Add optional details',
            hintStyle: AppTextStyles.callout.copyWith(
              color: context.colors.textMuted,
            ),
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
        const SizedBox(height: Spacing.space24),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.outlined,
                onPressed:
                    widget.isSaving || widget.isDeleting ? null : widget.onBack,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(
                label: 'Save Expense',
                variant: AppButtonVariant.primary,
                onPressed: canSave ? _handleSave : null,
                isLoading: widget.isSaving,
              ),
            ),
          ],
        ),
        if (widget.initialExpense != null && widget.onDelete != null) ...[
          const SizedBox(height: Spacing.space12),
          AppButton(
            label: 'Delete Expense',
            variant: AppButtonVariant.destructive,
            icon: AppIcons.delete,
            fullWidth: true,
            onPressed:
                widget.canDelete && !widget.isSaving && !widget.isDeleting
                    ? _handleDelete
                    : null,
            isLoading: widget.isDeleting,
          ),
        ],
      ],
    );
  }
}
