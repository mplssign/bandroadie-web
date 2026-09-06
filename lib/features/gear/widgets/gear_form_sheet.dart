import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/features/members/member_vm.dart';
import 'package:bandroadie/features/members/members_controller.dart';
import 'package:bandroadie/shared/utils/snackbar_helper.dart';

import '../gear_controller.dart';
import '../models/gear_item.dart';

class GearFormSheet extends ConsumerStatefulWidget {
  final String bandId;
  final GearItem? item;
  final bool canManageGear;

  const GearFormSheet({
    super.key,
    required this.bandId,
    this.item,
    required this.canManageGear,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String bandId,
    GearItem? item,
    required bool canManageGear,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GearFormSheet(
        bandId: bandId,
        item: item,
        canManageGear: canManageGear,
      ),
    );
  }

  @override
  ConsumerState<GearFormSheet> createState() => _GearFormSheetState();
}

class _GearFormSheetState extends ConsumerState<GearFormSheet> {
  late TextEditingController _nameController;
  late TextEditingController _purchasedFromController;
  late TextEditingController _priceController;

  late FocusNode _nameFocus;
  late FocusNode _purchasedFromFocus;
  late FocusNode _priceFocus;

  late GearOwnerType _ownerType;
  String? _ownerUserId;
  DateTime? _purchasedOn;
  bool _isSaving = false;

  bool get _isEditMode => widget.item != null;
  bool get _isReadOnly => !widget.canManageGear;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _nameController = TextEditingController(text: item?.name ?? '');
    _purchasedFromController =
        TextEditingController(text: item?.purchasedFrom ?? '');
    _priceController = TextEditingController(
      text: item?.priceCents != null
          ? (item!.priceCents! / 100).toStringAsFixed(2)
          : '',
    );

    _nameFocus = FocusNode();
    _purchasedFromFocus = FocusNode();
    _priceFocus = FocusNode();

    _ownerType = item?.ownerType ?? GearOwnerType.band;
    _ownerUserId = item?.ownerUserId;
    _purchasedOn = item?.purchasedOn;

    if (_ownerType == GearOwnerType.band) {
      _ownerUserId = null;
    }
  }

  @override
  void dispose() {
    _nameFocus.unfocus();
    _purchasedFromFocus.unfocus();
    _priceFocus.unfocus();

    _nameController.dispose();
    _purchasedFromController.dispose();
    _priceController.dispose();

    _nameFocus.dispose();
    _purchasedFromFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  List<MemberVM> _activeMembers() {
    return ref
        .read(membersProvider)
        .members
        .where((m) => m.status == 'active')
        .toList();
  }

  String _title() {
    if (_isReadOnly) return 'Gear Details';
    return _isEditMode ? 'Edit Gear Item' : 'New Gear Item';
  }

  String _dateLabel() {
    if (_purchasedOn == null) return 'Select date';
    return DateFormat('MMM d, yyyy').format(_purchasedOn!);
  }

  Future<void> _pickPurchasedOn() async {
    if (_isReadOnly || _isSaving) return;

    final now = DateTime.now();
    final initial = _purchasedOn ?? now;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 1),
    );

    if (!mounted || selected == null) return;
    setState(() => _purchasedOn = selected);
  }

  int? _parsePriceCents() {
    final raw = _priceController.text.trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceAll(',', '');
    final dollars = double.tryParse(normalized);
    if (dollars == null || dollars < 0) return null;

    return (dollars * 100).round();
  }

  Map<String, dynamic>? _buildPayload() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showErrorSnackBar(context, message: 'Gear name is required.');
      return null;
    }

    final cents = _parsePriceCents();
    if (_priceController.text.trim().isNotEmpty && cents == null) {
      showErrorSnackBar(
        context,
        message: 'Price must be a valid non-negative amount.',
      );
      return null;
    }

    if (_ownerType == GearOwnerType.member &&
        (_ownerUserId == null || _ownerUserId!.isEmpty)) {
      showErrorSnackBar(
        context,
        message: 'Select a member when ownership is set to member.',
      );
      return null;
    }

    final purchasedFrom = _purchasedFromController.text.trim();
    return {
      'name': name,
      'purchased_on': _purchasedOn?.toIso8601String().split('T').first,
      'purchased_from': purchasedFrom.isEmpty ? null : purchasedFrom,
      'price_cents': cents,
      'owner_type': _ownerType.dbValue,
      'owner_user_id': _ownerType == GearOwnerType.member ? _ownerUserId : null,
    };
  }

  Future<void> _save() async {
    if (_isReadOnly || _isSaving) return;

    final payload = _buildPayload();
    if (payload == null) return;

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(gearProvider.notifier);
      if (_isEditMode) {
        final updated = await notifier.update(
          id: widget.item!.id,
          bandId: widget.bandId,
          data: payload,
        );
        if (!mounted) return;
        if (updated == null) {
          showErrorSnackBar(context, message: 'Failed to update gear item.');
          setState(() => _isSaving = false);
          return;
        }
        showSuccessSnackBar(context, message: 'Gear item updated.');
      } else {
        final created =
            await notifier.create(bandId: widget.bandId, data: payload);
        if (!mounted) return;
        if (created == null) {
          showErrorSnackBar(context, message: 'Failed to add gear item.');
          setState(() => _isSaving = false);
          return;
        }
        showSuccessSnackBar(context, message: 'Gear item added.');
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      showErrorSnackBar(context, message: 'Could not save this gear item.');
      setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (_isReadOnly || !_isEditMode || _isSaving) return;

    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Delete gear item?',
      message: 'This action cannot be undone.',
      actions: [
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DialogAction(
          label: 'Delete',
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    final success = await ref.read(gearProvider.notifier).delete(
          id: widget.item!.id,
          bandId: widget.bandId,
        );

    if (!mounted) return;
    if (!success) {
      showErrorSnackBar(context, message: 'Failed to delete gear item.');
      setState(() => _isSaving = false);
      return;
    }

    showSuccessSnackBar(context, message: 'Gear item deleted.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final members = _activeMembers();
    final canEditMemberOwner = !_isReadOnly && !_isSaving;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: Spacing.pagePadding,
            right: Spacing.pagePadding,
            top: Spacing.space16,
            bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.space16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          context.colors.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox(
                      width: 48,
                      height: 4,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.space16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title(),
                        style: AppTextStyles.pageTitle.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        AppIcons.close,
                        color: context.colors.textSecondary,
                      ),
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.space16),
                AppTextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  labelText: 'Name *',
                  enabled: !_isReadOnly && !_isSaving,
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  'Owner',
                  style: TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                SegmentedButton<GearOwnerType>(
                  segments: const [
                    ButtonSegment<GearOwnerType>(
                      value: GearOwnerType.band,
                      label: Text('Band-owned'),
                    ),
                    ButtonSegment<GearOwnerType>(
                      value: GearOwnerType.member,
                      label: Text('Member-owned'),
                    ),
                  ],
                  selected: <GearOwnerType>{_ownerType},
                  onSelectionChanged: _isReadOnly || _isSaving
                      ? null
                      : (selected) {
                          if (selected.isEmpty) return;
                          setState(() {
                            _ownerType = selected.first;
                            if (_ownerType == GearOwnerType.band) {
                              _ownerUserId = null;
                            }
                          });
                        },
                ),
                if (_ownerType == GearOwnerType.member) ...[
                  const SizedBox(height: Spacing.space12),
                  DropdownButtonFormField<String>(
                    initialValue: _ownerUserId,
                    decoration: const InputDecoration(
                      labelText: 'Member *',
                    ),
                    items: members
                        .map(
                          (m) => DropdownMenuItem<String>(
                            value: m.userId,
                            child: Text(m.name),
                          ),
                        )
                        .toList(),
                    onChanged: canEditMemberOwner
                        ? (value) => setState(() => _ownerUserId = value)
                        : null,
                  ),
                  if (members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.space8),
                      child: Text(
                        'No active members are available in this band.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: AppFontSizes.caption,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: Spacing.space16),
                AppTextField(
                  controller: _purchasedFromController,
                  focusNode: _purchasedFromFocus,
                  labelText: 'Purchased From',
                  enabled: !_isReadOnly && !_isSaving,
                ),
                const SizedBox(height: Spacing.space16),
                AppTextField(
                  controller: _priceController,
                  focusNode: _priceFocus,
                  labelText: 'Price (USD)',
                  enabled: !_isReadOnly && !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  'Purchased On',
                  style: TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                OutlinedButton.icon(
                  onPressed: _isReadOnly || _isSaving ? null : _pickPurchasedOn,
                  icon: const Icon(AppIcons.calendar, size: 18),
                  label: Text(_dateLabel()),
                ),
                if (_purchasedOn != null && !_isReadOnly) ...[
                  const SizedBox(height: Spacing.space8),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => setState(() => _purchasedOn = null),
                    child: const Text('Clear date'),
                  ),
                ],
                const SizedBox(height: Spacing.space24),
                if (!_isReadOnly)
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Save',
                          onPressed: _save,
                          isLoading: _isSaving,
                        ),
                      ),
                    ],
                  ),
                if (_isEditMode && !_isReadOnly) ...[
                  const SizedBox(height: Spacing.space12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Delete Item',
                          variant: AppButtonVariant.destructive,
                          onPressed: _isSaving ? null : _delete,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
