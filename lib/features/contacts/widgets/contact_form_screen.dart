import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';
import '../../../shared/utils/phone_input_formatter.dart';
import '../../bands/active_band_controller.dart';
import '../contacts_controller.dart';
import '../contacts_repository.dart';
import '../models/contact.dart';
import 'title_pill_selector.dart';
import '../../../components/ui/app_scaffold.dart';
import '../../../components/ui/app_app_bar.dart';
import '../../../components/ui/app_icon_button.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_dialog.dart';

// ============================================================================
// CONTACT FORM SCREEN
// Full-screen create/edit form for standalone contacts.
// ============================================================================

class ContactFormScreen extends ConsumerStatefulWidget {
  final Contact? contact; // null = create mode, non-null = edit mode

  const ContactFormScreen({super.key, this.contact});

  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final _repository = ContactsRepository();

  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;
  late FocusNode _nameFocus;
  late FocusNode _companyFocus;
  late FocusNode _phoneFocus;
  late FocusNode _emailFocus;
  late FocusNode _notesFocus;
  String? _selectedTitle;
  String? _selectedDomain;

  bool _isSaving = false;

  bool get _isEditMode => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.name ?? '');
    _companyController = TextEditingController(text: c?.company ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
    _nameFocus = FocusNode();
    _companyFocus = FocusNode();
    _phoneFocus = FocusNode();
    _emailFocus = FocusNode();
    _notesFocus = FocusNode();
    _selectedTitle = c?.title;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _companyFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _applyDomainShortcut(String domain) {
    if (_isSaving) return;

    final current = _emailController.text;
    final result = applyEmailDomainShortcut(current, domain);

    if (result.isEmpty) {
      return;
    }

    _emailController.text = result;
    _emailController.selection = TextSelection.fromPosition(
      TextPosition(offset: result.length),
    );

    setState(() {
      _selectedDomain = domain;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    setState(() => _isSaving = true);

    try {
      final data = <String, dynamic>{
        'name': name,
        'title': _selectedTitle,
        'company': _companyController.text.trim().isEmpty
            ? null
            : _companyController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      };

      if (_isEditMode) {
        await _repository.updateContact(id: widget.contact!.id, data: data);
      } else {
        await _repository.createContact(bandId: bandId, data: data);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteContact() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Delete Contact?',
      message: 'This action cannot be undone.',
      actions: [
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DialogAction(
          label: 'Delete',
          onPressed: () => Navigator.of(context).pop(true),
          isDestructive: true,
        ),
      ],
    );

    if (confirmed != true) return;

    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    final success = await ref
        .read(contactsProvider.notifier)
        .delete(id: widget.contact!.id, bandId: bandId);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      }
    }
  }

  List<TextInputFormatter> _getPhoneFormatters() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    return isUSTimezone(tz) ? [USPhoneInputFormatter(isUSTimezone: true)] : [];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.background,
        leading: AppIconButton(
          icon: AppIcons.close,
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditMode ? 'Edit Contact' : 'New Contact',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.title,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          AppButton(
            label: 'Save',
            variant: AppButtonVariant.text,
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        children: [
          // Name
          AppTextField(
            controller: _nameController,
            focusNode: _nameFocus,
            labelText: 'Name *',
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Title',
            style: TextStyle(
              fontSize: AppFontSizes.subhead,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TitlePillSelector(
            selectedTitle: _selectedTitle,
            onChanged: (title) => setState(() => _selectedTitle = title),
          ),
          const SizedBox(height: 20),

          // Company
          AppTextField(
            controller: _companyController,
            focusNode: _companyFocus,
            labelText: 'Company',
          ),
          const SizedBox(height: 20),

          // Address fields are intentionally omitted from standalone contacts.
          // Contacts (agents, promoters) are lightweight records. Venues carry full address data.

          // Phone
          AppTextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            labelText: 'Phone',
            keyboardType: TextInputType.phone,
            inputFormatters: _getPhoneFormatters(),
          ),
          const SizedBox(height: 16),

          // Email
          AppTextField(
            controller: _emailController,
            focusNode: _emailFocus,
            labelText: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          EmailDomainShortcutBar(
            controller: _emailController,
            selectedDomain: _selectedDomain,
            onDomainSelected: (domain) => _applyDomainShortcut(domain),
            enabled: !_isSaving,
          ),
          const SizedBox(height: 16),

          // Notes
          AppTextField(
            controller: _notesController,
            focusNode: _notesFocus,
            labelText: 'Notes',
            maxLines: 3,
          ),

          // Delete button (edit mode only)
          if (_isEditMode) ...[
            const SizedBox(height: 32),
            Center(
              child: AppButton(
                label: 'Delete Contact',
                variant: AppButtonVariant.destructive,
                onPressed: _deleteContact,
              ),
            ),
          ],

          // Bottom padding
          SizedBox(
            height:
                Spacing.space48 + MediaQuery.of(context).padding.bottom + 32,
          ),
        ],
      ),
    );
  }
}
