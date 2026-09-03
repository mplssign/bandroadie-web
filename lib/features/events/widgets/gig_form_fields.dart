import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_dialog.dart';
import '../../../components/ui/app_progress_indicator.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../contacts/contacts_controller.dart';
import '../../financials/models/financial_entry.dart';
import '../../members/member_vm.dart';
import '../../members/members_controller.dart';
import '../../contacts/models/contact.dart';
import '../../contacts/widgets/title_pill_selector.dart';
import '../models/event_form_data.dart';
import 'gig_expense_subview.dart';
import 'button_group_grid.dart';
import 'event_editor_helpers.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

class GigContactRowsController {
  GigContactRowsController({required this.onRowBlur});

  final ValueChanged<int> onRowBlur;
  final List<FAutocompleteController> controllers = [];
  final List<FocusNode> focusNodes = [];
  final List<String?> _resolvedContactIds = [];

  bool get isEmpty => controllers.isEmpty;
  int get length => controllers.length;

  String? resolvedContactIdAt(int index) {
    if (index < 0 || index >= _resolvedContactIds.length) return null;
    return _resolvedContactIds[index];
  }

  String rowTextAt(int index) {
    if (index < 0 || index >= controllers.length) return '';
    return controllers[index].text;
  }

  void setResolvedContactId(int index, String? contactId) {
    if (index < 0 || index >= _resolvedContactIds.length) return;
    _resolvedContactIds[index] = contactId;
  }

  void setRowText(int index, String text) {
    if (index < 0 || index >= controllers.length) return;
    controllers[index].text = text;
  }

  void selectContact(int index, Contact contact) {
    if (index < 0 || index >= controllers.length) return;
    controllers[index].text = contact.name;
    _resolvedContactIds[index] = contact.id;
  }

  void dispose() {
    for (final focusNode in focusNodes) {
      focusNode.unfocus();
      focusNode.dispose();
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  void replaceRows(List<Contact> contacts) {
    dispose();
    focusNodes.clear();
    controllers.clear();
    _resolvedContactIds.clear();

    for (final contact in contacts) {
      addRow(contact: contact);
    }
  }

  void addRow({Contact? contact}) {
    final controller = FAutocompleteController(text: contact?.name ?? '');
    final focusNode = FocusNode();

    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        final index = focusNodes.indexOf(focusNode);
        if (index != -1) {
          onRowBlur(index);
        }
      }
    });

    controllers.add(controller);
    focusNodes.add(focusNode);
    _resolvedContactIds.add(contact?.id);
  }

  bool removeRow(int index) {
    if (index < 0 || index >= controllers.length) return false;

    final controller = controllers.removeAt(index);
    final focusNode = focusNodes.removeAt(index);
    _resolvedContactIds.removeAt(index);

    focusNode.unfocus();
    focusNode.dispose();
    controller.dispose();
    return true;
  }

  Contact? findContactByName(String name, List<Contact> availableContacts) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    for (final contact in availableContacts) {
      if (contact.name.trim().toLowerCase() == trimmed.toLowerCase()) {
        return contact;
      }
    }
    return null;
  }

  Contact? resolvedContactForRow(int index, List<Contact> availableContacts) {
    final resolvedId = resolvedContactIdAt(index);
    if (resolvedId == null) return null;

    for (final contact in availableContacts) {
      if (contact.id == resolvedId) {
        return contact;
      }
    }
    return null;
  }

  bool isRowResolved(int index, List<Contact> availableContacts) {
    if (index < 0 || index >= controllers.length) return true;

    final text = controllers[index].text.trim();
    if (text.isEmpty) return true;

    final resolvedContact = resolvedContactForRow(index, availableContacts);
    if (resolvedContact == null) return false;

    return resolvedContact.name.trim().toLowerCase() == text.toLowerCase();
  }

  static Future<Contact?> showCreateDialog(
    BuildContext context, {
    required WidgetRef ref,
    required String bandId,
    required String initialName,
    required bool isSaving,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final companyController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final notesController = TextEditingController();
    final nameFocusNode = FocusNode();
    final companyFocusNode = FocusNode();
    final phoneFocusNode = FocusNode();
    final emailFocusNode = FocusNode();
    final notesFocusNode = FocusNode();
    String? selectedTitle;

    try {
      final draft = await showAppDialog<Map<String, String?>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final trimmedName = nameController.text.trim();

              return FDialog(
                builder: (dialogContext, style) => Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: dialogContext.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Spacing.pagePadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"$initialName" is not in your contacts list',
                          style: AppTextStyles.title3.copyWith(
                            color: dialogContext.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Spacing.space8),
                        Text(
                          'Add it as a shared band contact for this gig.',
                          style: AppTextStyles.callout.copyWith(
                            color: dialogContext.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Spacing.space16),
                        AppTextField(
                          controller: nameController,
                          focusNode: nameFocusNode,
                          labelText: 'Name *',
                          enabled: !isSaving,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: Spacing.space16),
                        Text(
                          'Title',
                          style: AppTextStyles.footnote.copyWith(
                            color: dialogContext.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Spacing.space8),
                        TitlePillSelector(
                          selectedTitle: selectedTitle,
                          onChanged: (title) =>
                              setDialogState(() => selectedTitle = title),
                        ),
                        const SizedBox(height: Spacing.space16),
                        AppTextField(
                          controller: companyController,
                          focusNode: companyFocusNode,
                          labelText: 'Company',
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: Spacing.space16),
                        AppTextField(
                          controller: phoneController,
                          focusNode: phoneFocusNode,
                          labelText: 'Phone',
                          keyboardType: TextInputType.phone,
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: Spacing.space16),
                        AppTextField(
                          controller: emailController,
                          focusNode: emailFocusNode,
                          labelText: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: Spacing.space16),
                        AppTextField(
                          controller: notesController,
                          focusNode: notesFocusNode,
                          labelText: 'Notes',
                          maxLines: 3,
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: Spacing.space20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: Text(
                                'Cancel',
                                style: AppTextStyles.calloutEmphasized.copyWith(
                                  color: dialogContext.colors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: Spacing.space8),
                            TextButton(
                              onPressed: trimmedName.isEmpty
                                  ? null
                                  : () => Navigator.of(dialogContext).pop({
                                        'name': trimmedName,
                                        'title': selectedTitle,
                                        'company':
                                            companyController.text.trim(),
                                        'phone': phoneController.text.trim(),
                                        'email': emailController.text.trim(),
                                        'notes': notesController.text.trim(),
                                      }),
                              child: Text(
                                'Create Contact',
                                style: AppTextStyles.calloutEmphasized.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (draft == null) {
        return null;
      }

      final contact = await ref.read(contactsProvider.notifier).create(
        bandId: bandId,
        data: {
          'name': draft['name'],
          'title': draft['title'],
          'company':
              (draft['company']?.isEmpty ?? true) ? null : draft['company'],
          'phone': (draft['phone']?.isEmpty ?? true) ? null : draft['phone'],
          'email': (draft['email']?.isEmpty ?? true) ? null : draft['email'],
          'notes': (draft['notes']?.isEmpty ?? true) ? null : draft['notes'],
        },
      );

      if (contact == null && context.mounted) {
        showErrorSnackBar(
          context,
          message: 'Couldn\'t add that contact right now.',
        );
      }

      return contact;
    } finally {
      nameController.dispose();
      companyController.dispose();
      phoneController.dispose();
      emailController.dispose();
      notesController.dispose();
      nameFocusNode.dispose();
      companyFocusNode.dispose();
      phoneFocusNode.dispose();
      emailFocusNode.dispose();
      notesFocusNode.dispose();
    }
  }
}

/// Gig-specific form fields: venue name autocomplete, city autocomplete,
/// potential-gig toggle with member availability, load-in time, and gig pay.
class GigFormFields extends ConsumerWidget {
  const GigFormFields({
    super.key,
    required this.isSaving,
    required this.isEditMode,
    required this.existingEventId,
    required this.availableContacts,
    required this.isLoadingContacts,
    required this.contactAutocompleteControllers,
    required this.contactFocusNodes,
    required this.onAddContact,
    required this.onRemoveContact,
    required this.onContactTextChanged,
    required this.onContactSelected,
    required this.onContactEditingComplete,
    required this.onContactSubmitted,
    // Gig name autocomplete
    required this.gigNameAutocompleteController,
    required this.venueHintController,
    required this.gigNameSuggestions,
    required this.onGigNameChanged,
    required this.onGigNameSelected,
    required this.onGigNameTextChanged,
    required this.fieldErrors,
    // City autocomplete
    required this.gigCityAutocompleteController,
    required this.cityHintController,
    required this.gigCitySuggestions,
    required this.onGigCityChanged,
    required this.onGigCityTextChanged,
    // Address field
    required this.addressController,
    required this.addressHintController,
    required this.gigAddressFocusNode,
    required this.stateController,
    // Potential gig
    required this.isPotentialGig,
    required this.forcePotentialOnly,
    required this.onPotentialGigToggled,
    // Member availability (edit mode)
    required this.memberAvailability,
    required this.isLoadingMemberAvailability,
    required this.perDateAvailability,
    required this.isLoadingPerDateAvailability,
    // User availability (edit mode)
    required this.currentUserResponse,
    required this.isLoadingUserResponse,
    required this.onUserResponseChanged,
    // Multi-date (potential gig)
    required this.additionalDates,
    required this.primaryStartTime,
    required this.selectedDate,
    required this.existingGigDateIds,
    required this.onPerDateResponseChanged,
    // Load-in time
    required this.loadInHour,
    required this.loadInMinutes,
    required this.loadInIsPM,
    required this.onLoadInTimeSet,
    required this.onLoadInTimeCleared,
    required this.onLoadInHourChanged,
    required this.onLoadInMinutesChanged,
    required this.onLoadInAmPmChanged,
    // Soundcheck time (optional)
    this.soundcheckHour,
    this.soundcheckMinutes,
    this.soundcheckIsPM,
    this.onSoundcheckTimeSet,
    this.onSoundcheckTimeCleared,
    this.onSoundcheckHourChanged,
    this.onSoundcheckMinutesChanged,
    this.onSoundcheckAmPmChanged,
    // Gig pay
    required this.gigPayDetails,
    required this.onGigPayTap,
    // Gig expenses
    required this.showExpensesSection,
    required this.canEditExpenses,
    required this.gigExpenses,
    required this.onAddExpense,
    required this.onExpenseTap,
    // General
    required this.onMarkDirty,
    required this.currentUserId,
  });

  final bool isSaving;
  final bool isEditMode;
  final String? existingEventId;

  // --- Gig contacts ---
  final List<Contact> availableContacts;
  final bool isLoadingContacts;
  final List<FAutocompleteController> contactAutocompleteControllers;
  final List<FocusNode> contactFocusNodes;
  final VoidCallback onAddContact;
  final ValueChanged<int> onRemoveContact;
  final void Function(int index, String text) onContactTextChanged;
  final void Function(int index, Contact contact) onContactSelected;
  final ValueChanged<int> onContactEditingComplete;
  final void Function(int index, String text) onContactSubmitted;

  // --- Gig name autocomplete ---
  final FAutocompleteController gigNameAutocompleteController;
  final FieldHintController venueHintController;
  final List<String> gigNameSuggestions;
  final ValueChanged<String> onGigNameChanged;
  final ValueChanged<String> onGigNameSelected;
  final ValueChanged<String> onGigNameTextChanged;
  final Map<String, String> fieldErrors;

  // --- City autocomplete ---
  final FAutocompleteController gigCityAutocompleteController;
  final FieldHintController cityHintController;
  final List<String> gigCitySuggestions;
  final ValueChanged<String> onGigCityChanged;
  final ValueChanged<String> onGigCityTextChanged;

  // --- Address field ---
  final TextEditingController addressController;
  final FieldHintController addressHintController;
  final FocusNode gigAddressFocusNode;
  final TextEditingController stateController;

  // --- Potential gig ---
  final bool isPotentialGig;
  final bool forcePotentialOnly;
  final ValueChanged<bool> onPotentialGigToggled;

  // --- Member availability ---
  final Map<String, String?> memberAvailability;
  final bool isLoadingMemberAvailability;
  final Map<String, Map<String, String?>> perDateAvailability;
  final bool isLoadingPerDateAvailability;

  // --- User availability ---
  final String? currentUserResponse;
  final bool isLoadingUserResponse;
  final ValueChanged<String> onUserResponseChanged;

  // --- Multi-date ---
  final List<AdditionalDateEntry> additionalDates;
  final String primaryStartTime;
  final DateTime selectedDate;
  final Map<DateTime, String> existingGigDateIds;
  final void Function(DateTime date, bool isPrimaryDate, String response)
      onPerDateResponseChanged;

  // --- Load-in time ---
  final int? loadInHour;
  final int? loadInMinutes;
  final bool? loadInIsPM;
  final VoidCallback onLoadInTimeSet;
  final VoidCallback onLoadInTimeCleared;
  final ValueChanged<int> onLoadInHourChanged;
  final ValueChanged<int> onLoadInMinutesChanged;
  final ValueChanged<bool> onLoadInAmPmChanged;

  // --- Soundcheck time ---
  final int? soundcheckHour;
  final int? soundcheckMinutes;
  final bool? soundcheckIsPM;
  final VoidCallback? onSoundcheckTimeSet;
  final VoidCallback? onSoundcheckTimeCleared;
  final ValueChanged<int>? onSoundcheckHourChanged;
  final ValueChanged<int>? onSoundcheckMinutesChanged;
  final ValueChanged<bool>? onSoundcheckAmPmChanged;

  // --- Gig pay ---
  final GigPayDetails? gigPayDetails;
  final VoidCallback onGigPayTap;

  // --- Gig expenses ---
  final bool showExpensesSection;
  final bool canEditExpenses;
  final List<GigExpenseDraft> gigExpenses;
  final VoidCallback onAddExpense;
  final ValueChanged<GigExpenseDraft> onExpenseTap;

  // --- General ---
  final VoidCallback onMarkDirty;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gig Name autocomplete
        _buildGigNameAutocomplete(context),
        const SizedBox(height: Spacing.space16),

        // Potential Gig container with member availability
        _buildPotentialGigContainer(context, ref),
        const SizedBox(height: Spacing.space12),
      ],
    );
  }

  /// Builds the city autocomplete field (called from parent build method).
  Widget buildCityAutocomplete(BuildContext context) {
    return _buildGigCityAutocomplete(context);
  }

  /// Builds the address field (full width, called from parent build method).
  Widget buildAddressField(BuildContext context) {
    return _buildAddressField(context);
  }

  /// Builds city (left, flex 3) + state (right, flex 2) in a single row.
  Widget buildCityStateRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: _buildGigCityAutocomplete(context),
        ),
        const SizedBox(width: Spacing.space8),
        Expanded(
          flex: 2,
          child: _buildStateField(context),
        ),
      ],
    );
  }

  Widget _buildAddressField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Address',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: addressController,
          focusNode: gigAddressFocusNode,
          enabled: !isSaving,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          hintText: 'e.g., 123 Main St',
          onChanged: (_) => onMarkDirty(),
        ),
        FieldHint(
          text: 'Street address (optional)',
          controller: addressHintController,
        ),
      ],
    );
  }

  /// Builds the load-in time selector (called from parent build method).
  Widget buildLoadInTimeSelector(BuildContext context) {
    return _buildLoadInTimeSelector(context);
  }

  /// Builds the soundcheck time selector (same pattern as load-in).
  Widget buildSoundcheckRow(BuildContext context) {
    if (soundcheckHour == null ||
        soundcheckMinutes == null ||
        soundcheckIsPM == null) {
      return GestureDetector(
        onTap: isSaving ? null : onSoundcheckTimeSet,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.add, color: context.colors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Text(
                '+ Set Soundcheck Time (Optional)',
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Soundcheck Time',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            GestureDetector(
              onTap: isSaving ? null : onSoundcheckTimeCleared,
              child: Text(
                'Clear',
                style: AppTextStyles.footnote.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: EventDropdown<int>(
                value: soundcheckHour!,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) {
                  if (v != null) onSoundcheckHourChanged?.call(v);
                },
                labelBuilder: (v) => v.toString(),
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EventDropdown<int>(
                value: soundcheckMinutes!,
                items: const [0, 15, 30, 45],
                onChanged: (v) {
                  if (v != null) onSoundcheckMinutesChanged?.call(v);
                },
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmPmToggleButton(
                    label: 'AM',
                    isSelected: !soundcheckIsPM!,
                    isSaving: isSaving,
                    onTap: () => onSoundcheckAmPmChanged?.call(false),
                  ),
                  AmPmToggleButton(
                    label: 'PM',
                    isSelected: soundcheckIsPM!,
                    isSaving: isSaving,
                    onTap: () => onSoundcheckAmPmChanged?.call(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the repeatable gig contacts section.
  Widget buildContactsSection(BuildContext context) {
    return _buildContactsSection(context);
  }

  /// Builds the gig pay button (called from parent build method).
  Widget buildGigPayButton(BuildContext context) {
    final hasDetails = gigPayDetails != null && gigPayDetails!.amountCents > 0;
    final label = hasDetails
        ? '${gigPayDetails!.formattedAmount}${gigPayDetails!.payerName != null ? ' · ${gigPayDetails!.payerName}' : ''}'
        : 'Set Gig Pay';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gig Pay (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppButton(
          label: label,
          variant: AppButtonVariant.outlined,
          icon: hasDetails ? AppIcons.edit : AppIcons.dollar,
          fullWidth: true,
          onPressed: isSaving ? null : onGigPayTap,
        ),
      ],
    );
  }

  /// Builds the expenses section shown beneath Gig Pay.
  Widget buildExpensesSection(BuildContext context) {
    if (!showExpensesSection) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expenses',
                style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            AppButton(
              label: 'Add Expense',
              variant: AppButtonVariant.text,
              icon: AppIcons.add,
              onPressed: (isSaving || !canEditExpenses) ? null : onAddExpense,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (gigExpenses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: context.colors.border),
            ),
            child: Text(
              'No expenses added yet.',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          )
        else
          ...gigExpenses.map(
            (expense) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.space8),
              child: InkWell(
                onTap: canEditExpenses ? () => onExpenseTap(expense) : null,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    expense.category,
                                    style: AppTextStyles.callout.copyWith(
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (expense.isReimbursed) ...[
                                  const SizedBox(width: 8),
                                  _buildReimbursedBadge(context),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              expense.isReimbursed
                                  ? _buildReimbursementDetailLine(expense)
                                  : _formatDate(expense.entryDate),
                              style: AppTextStyles.footnote.copyWith(
                                color: context.colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        expense.formattedAmount,
                        style: AppTextStyles.calloutEmphasized.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      if (canEditExpenses) ...[
                        const SizedBox(width: 8),
                        Icon(
                          AppIcons.forward,
                          size: 14,
                          color: context.colors.textMuted,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReimbursedBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.colors.success.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Reimbursed',
        style: AppTextStyles.footnote.copyWith(
          color: context.colors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _buildReimbursementDetailLine(GigExpenseDraft expense) {
    final reimbursedDate = expense.reimbursedDate;
    final reimbursedTo =
        (expense.paidByName != null && expense.paidByName!.trim().isNotEmpty)
            ? expense.paidByName!.trim()
            : 'Unknown payer';
    final reimbursedDateText =
        reimbursedDate != null ? _formatDate(reimbursedDate) : 'Unknown date';

    return 'Purchased ${_formatDate(expense.entryDate)} · Reimbursed $reimbursedDateText to $reimbursedTo';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Builds the state field (private, called from buildAddressCityRow).
  Widget _buildStateField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'State',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: stateController,
          enabled: !isSaving,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          maxLength: 2,
          hintText: 'ST',
          onChanged: (value) {
            // Enforce uppercase formatting
            final upperValue = value.toUpperCase();
            if (value != upperValue) {
              final cursorPosition = stateController.selection.baseOffset;
              stateController.value = stateController.value.copyWith(
                text: upperValue,
                selection: TextSelection.collapsed(offset: cursorPosition),
              );
            }
            onMarkDirty();
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Gig Name Autocomplete
  // ---------------------------------------------------------------------------

  Widget _adaptiveTextSelectionToolbar(
      BuildContext context, EditableTextState state) {
    return Localizations(
      locale: Localizations.localeOf(context),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child:
          AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
    );
  }

  Widget _buildGigNameAutocomplete(BuildContext context) {
    final hasError = fieldErrors.containsKey('name');
    final errorText = hasError ? fieldErrors['name'] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gig Venue / Festival / Name',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        FAutocomplete.text(
          items: gigNameSuggestions,
          control: FAutocompleteControl.managed(
            controller: gigNameAutocompleteController,
            onChange: (value) {
              onGigNameTextChanged(value.text);
            },
          ),
          filter: (query) {
            onGigNameChanged(query);
            if (query.length < 2) return const Iterable<String>.empty();
            return gigNameSuggestions.where(
                (name) => name.toLowerCase().contains(query.toLowerCase()));
          },
          hint: 'e.g., The Blue Note, SummerFest 2026',
          enabled: !isSaving,
          textCapitalization: TextCapitalization.sentences,
          forceErrorText: hasError ? errorText : null,
          contextMenuBuilder: _adaptiveTextSelectionToolbar,
          onItemPress: (selection) {
            onGigNameSelected(selection);
            onMarkDirty();
          },
        ),
        FieldHint(
          text: "Start typing to reuse past venues.",
          controller: venueHintController,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // City Autocomplete
  // ---------------------------------------------------------------------------

  Widget _buildGigCityAutocomplete(BuildContext context) {
    final hasError = fieldErrors.containsKey('city');
    final errorText = hasError ? fieldErrors['city'] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'City',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        FAutocomplete.textBuilder(
          control: FAutocompleteControl.managed(
            controller: gigCityAutocompleteController,
            onChange: (value) {
              onGigCityTextChanged(value.text);
            },
          ),
          filter: (query) async {
            onGigCityChanged(query);
            if (query.length < 2) return const Iterable<String>.empty();
            // Wait briefly for parent's debounced query to update gigCitySuggestions
            await Future.delayed(const Duration(milliseconds: 350));
            return gigCitySuggestions;
          },
          hint: 'e.g., Chicago',
          enabled: !isSaving,
          textCapitalization: TextCapitalization.sentences,
          forceErrorText: hasError ? errorText : null,
          contextMenuBuilder: _adaptiveTextSelectionToolbar,
          onItemPress: (selection) {
            onMarkDirty();
          },
          contentBuilder: (context, query, values) => [
            for (final value in values) FAutocompleteItem.item(value: value),
          ],
        ),
        FieldHint(
          text: "Auto-fills based on past gigs.",
          controller: cityHintController,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Potential Gig Container
  // ---------------------------------------------------------------------------

  Widget _buildPotentialGigContainer(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(membersProvider);
    final members = membersState.members;

    final isMultiDateEditMode =
        isEditMode && existingEventId != null && additionalDates.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isPotentialGig
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Title + Toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Gig',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Toggle off once confirmed to make it official.',
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: isPotentialGig,
                onChanged: (isSaving || forcePotentialOnly)
                    ? null
                    : onPotentialGigToggled,
              ),
            ],
          ),

          // Member grid (only visible when toggle is ON)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: isPotentialGig
                ? isMultiDateEditMode
                    ? _buildMultiDateAvailabilitySection(
                        context, members, membersState.isLoading)
                    : Column(
                        children: [
                          _buildMemberSelectionGrid(
                              context, members, membersState.isLoading),
                          if (isEditMode && existingEventId != null)
                            _buildUserAvailabilitySection(context),
                        ],
                      )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-Date Availability
  // ---------------------------------------------------------------------------

  Widget _buildMultiDateAvailabilitySection(
    BuildContext context,
    List<MemberVM> members,
    bool isLoading,
  ) {
    // Build (date, timeDisplay) pairs sorted by date
    final allEntries = <(DateTime, String)>[
      (selectedDate, primaryStartTime),
      ...additionalDates.map((e) => (e.date, e.startTimeDisplay)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.space12),
        for (int i = 0; i < allEntries.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.space16),
          _buildPerDateSection(
            context: context,
            date: allEntries[i].$1,
            timeDisplay: allEntries[i].$2,
            members: members,
            isLoading: isLoading,
            isPrimaryDate: allEntries[i].$1 == selectedDate,
          ),
        ],
      ],
    );
  }

  Widget _buildPerDateSection({
    required BuildContext context,
    required DateTime date,
    required String timeDisplay,
    required List<MemberVM> members,
    required bool isLoading,
    required bool isPrimaryDate,
  }) {
    final dateKey = isPrimaryDate ? 'primary' : existingGigDateIds[date];
    final availability = dateKey != null
        ? perDateAvailability[dateKey] ?? {}
        : <String, String?>{};

    final userResponse =
        currentUserId != null ? availability[currentUserId] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date + time header
        Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space8),
          child: Text(
            '${_formatDateDisplay(date)} · $timeDisplay',
            style: AppTextStyles.calloutEmphasized.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),

        // Member availability grid
        if (isLoading || isLoadingPerDateAvailability)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: AppProgressIndicator(),
              ),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
            child: Text(
              'No members to notify',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          ButtonGroupGrid<MemberVM>(
            items: members,
            labelBuilder: (member) => _getMemberLabel(member, members),
            labelWidgetBuilder: (member) =>
                _buildMemberLabelWidget(context, member, members, availability),
            isSelected: (member) => false,
            availabilityMode: true,
            availabilityState: (member) {
              final response = availability[member.userId];
              if (response == 'yes') return AvailabilityState.available;
              if (response == 'no') return AvailabilityState.notAvailable;
              return AvailabilityState.notResponded;
            },
            buttonHeight: 48,
          ),

        // Your Availability for this date
        const SizedBox(height: Spacing.space8),
        Text(
          'Your Availability',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Row(
          children: [
            Expanded(
              child: AvailabilityButton(
                label: 'NO',
                icon: AppIcons.close,
                isSelected: userResponse == 'no',
                isPositive: false,
                isLoading: false,
                onPressed: () =>
                    onPerDateResponseChanged(date, isPrimaryDate, 'no'),
              ),
            ),
            const SizedBox(width: Spacing.space12),
            Expanded(
              child: AvailabilityButton(
                label: 'YES',
                icon: AppIcons.check,
                isSelected: userResponse == 'yes',
                isPositive: true,
                isLoading: false,
                onPressed: () =>
                    onPerDateResponseChanged(date, isPrimaryDate, 'yes'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // User Availability Section (single-date)
  // ---------------------------------------------------------------------------

  Widget _buildUserAvailabilitySection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: Spacing.space12),
            color: context.colors.border,
          ),
          Text(
            'Your Availability',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.space8),
          if (isLoadingUserResponse)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.space8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: AppProgressIndicator(),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AvailabilityButton(
                    label: 'NO',
                    icon: AppIcons.close,
                    isSelected: currentUserResponse == 'no',
                    isPositive: false,
                    isLoading: false,
                    onPressed: () => onUserResponseChanged('no'),
                  ),
                ),
                const SizedBox(width: Spacing.space12),
                Expanded(
                  child: AvailabilityButton(
                    label: 'YES',
                    icon: AppIcons.check,
                    isSelected: currentUserResponse == 'yes',
                    isPositive: true,
                    isLoading: false,
                    onPressed: () => onUserResponseChanged('yes'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Member Selection Grid
  // ---------------------------------------------------------------------------

  Widget _buildMemberSelectionGrid(
      BuildContext context, List<MemberVM> members, bool isLoading) {
    if (isLoading || isLoadingMemberAvailability) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: AppProgressIndicator(),
          ),
        ),
      );
    }

    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
        child: Text(
          'No members to notify',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space12),
      child: ButtonGroupGrid<MemberVM>(
        items: members,
        labelBuilder: (member) => _getMemberLabel(member, members),
        labelWidgetBuilder: (member) => _buildMemberLabelWidget(
            context, member, members, memberAvailability),
        isSelected: (member) => false,
        availabilityMode: true,
        availabilityState: (member) {
          final response = memberAvailability[member.userId];
          if (response == 'yes') return AvailabilityState.available;
          if (response == 'no') return AvailabilityState.notAvailable;
          return AvailabilityState.notResponded;
        },
        buttonHeight: 48,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Load-in Time Selector
  // ---------------------------------------------------------------------------

  Widget _buildLoadInTimeSelector(BuildContext context) {
    if (loadInHour == null || loadInMinutes == null || loadInIsPM == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Load-in Time',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isSaving ? null : onLoadInTimeSet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.add,
                    color: context.colors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Set Load-in Time (Optional)',
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Load-in Time',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            GestureDetector(
              onTap: isSaving ? null : onLoadInTimeCleared,
              child: Text(
                'Clear',
                style: AppTextStyles.footnote.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Hour dropdown
            Expanded(
              child: EventDropdown<int>(
                value: loadInHour!,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) {
                  if (v != null) onLoadInHourChanged(v);
                },
                labelBuilder: (v) => v.toString(),
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            // Minutes dropdown
            Expanded(
              child: EventDropdown<int>(
                value: loadInMinutes!,
                items: const [0, 15, 30, 45],
                onChanged: (v) {
                  if (v != null) onLoadInMinutesChanged(v);
                },
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            // AM/PM toggle
            Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmPmToggleButton(
                    label: 'AM',
                    isSelected: !loadInIsPM!,
                    isSaving: isSaving,
                    onTap: () => onLoadInAmPmChanged(false),
                  ),
                  AmPmToggleButton(
                    label: 'PM',
                    isSelected: loadInIsPM!,
                    isSaving: isSaving,
                    onTap: () => onLoadInAmPmChanged(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactsSection(BuildContext context) {
    final contactNames =
        availableContacts.map((contact) => contact.name).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Contacts',
                style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            AppButton(
              label: contactAutocompleteControllers.isEmpty
                  ? 'Add'
                  : 'Add another',
              variant: AppButtonVariant.text,
              icon: AppIcons.add,
              onPressed: isSaving ? null : onAddContact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (contactAutocompleteControllers.isEmpty)
          InkWell(
            onTap: isSaving ? null : onAddContact,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: context.colors.border),
              ),
              child: Text(
                isLoadingContacts
                    ? 'Loading your shared contacts...'
                    : 'No contacts linked — tap to add one',
                style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < contactAutocompleteControllers.length; i++) ...[
            if (i > 0) const SizedBox(height: Spacing.space8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FAutocomplete.text(
                    items: contactNames,
                    control: FAutocompleteControl.managed(
                      controller: contactAutocompleteControllers[i],
                      onChange: (value) {
                        onContactTextChanged(i, value.text);
                      },
                    ),
                    filter: (query) {
                      if (query.trim().isEmpty) {
                        return const Iterable<String>.empty();
                      }

                      return contactNames.where(
                        (name) =>
                            name.toLowerCase().contains(query.toLowerCase()),
                      );
                    },
                    hint: 'Start typing a shared contact name',
                    enabled: !isSaving,
                    focusNode: contactFocusNodes[i],
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    contextMenuBuilder: _adaptiveTextSelectionToolbar,
                    onItemPress: (selection) {
                      final selectedContact = availableContacts.firstWhere(
                        (contact) =>
                            contact.name.trim().toLowerCase() ==
                            selection.trim().toLowerCase(),
                      );
                      onContactSelected(i, selectedContact);
                      onMarkDirty();
                    },
                    onEditingComplete: () => onContactEditingComplete(i),
                    onSubmit: (value) => onContactSubmitted(i, value),
                  ),
                ),
                const SizedBox(width: Spacing.space8),
                IconButton(
                  onPressed: isSaving ? null : () => onRemoveContact(i),
                  icon: Icon(
                    AppIcons.close,
                    size: 18,
                    color: context.colors.textMuted,
                  ),
                  tooltip: 'Remove contact',
                ),
              ],
            ),
          ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Member Label Helpers
  // ---------------------------------------------------------------------------

  String _getMemberLabel(MemberVM member, List<MemberVM> allMembers) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null) {
      final name = member.name;
      return name.length > 10 ? '${name.substring(0, 9)}…' : name;
    }
    return disambiguation.line1;
  }

  Widget? _buildMemberLabelWidget(
    BuildContext context,
    MemberVM member,
    List<MemberVM> allMembers,
    Map<String, String?> availability,
  ) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null || !disambiguation.requiresTwoLines) {
      return null;
    }

    final response = availability[member.userId];
    final textColor = (response == 'yes' || response == 'no')
        ? Colors.white
        : context.colors.textSecondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          disambiguation.line1,
          style: AppTextStyles.footnote.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSizes.caption,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            disambiguation.line2!,
            style: AppTextStyles.navLabel.copyWith(
              color: textColor.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  MemberDisambiguation? _getMemberDisambiguation(
    MemberVM member,
    List<MemberVM> allMembers,
  ) {
    final firstName = member.firstName;
    if (firstName == null || firstName.isEmpty) return null;

    final sameFirstName =
        allMembers.where((m) => m.firstName == firstName).toList();

    if (sameFirstName.length <= 1) {
      final label =
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName;
      return MemberDisambiguation(line1: label);
    }

    if (member.lastName == null || member.lastName!.isEmpty) {
      final label =
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName;
      return MemberDisambiguation(line1: label);
    }

    final lastInitial = member.lastName![0].toUpperCase();
    final sameFirstAndInitial = sameFirstName.where((m) {
      final mLastName = m.lastName;
      if (mLastName == null || mLastName.isEmpty) return false;
      return mLastName[0].toUpperCase() == lastInitial;
    }).toList();

    if (sameFirstAndInitial.length <= 1) {
      final label = '$firstName $lastInitial.';
      return MemberDisambiguation(
        line1: label.length > 10 ? '${label.substring(0, 9)}…' : label,
      );
    }

    return MemberDisambiguation(
      line1:
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName,
      line2: member.lastName,
      requiresTwoLines: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static String _formatDateDisplay(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dayName = days[date.weekday % 7];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}, ${date.year}';
  }
}
