import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../../shared/utils/phone_input_formatter.dart';
import '../../bands/active_band_controller.dart';
import '../contacts_controller.dart';
import '../contacts_repository.dart';
import '../models/contact.dart';
import 'title_pill_selector.dart';

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
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;
  late FocusNode _nameFocus;
  late FocusNode _phoneFocus;
  late FocusNode _emailFocus;
  late FocusNode _notesFocus;
  String? _selectedTitle;

  bool _isSaving = false;

  bool get _isEditMode => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _emailFocus = FocusNode();
    _notesFocus = FocusNode();
    _selectedTitle = c?.title;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Contact?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
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

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  List<TextInputFormatter> _getPhoneFormatters() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    return isUSTimezone(tz) ? [USPhoneInputFormatter(isUSTimezone: true)] : [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(AppIcons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditMode ? 'Edit Contact' : 'New Contact',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        children: [
          // Name
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Name *'),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Title',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TitlePillSelector(
            selectedTitle: _selectedTitle,
            onChanged: (title) => setState(() => _selectedTitle = title),
          ),
          const SizedBox(height: 20),

          // Address fields are intentionally omitted from standalone contacts.
          // Contacts (agents, promoters) are lightweight records. Venues carry full address data.

          // Phone
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Phone'),
            keyboardType: TextInputType.phone,
            inputFormatters: _getPhoneFormatters(),
          ),
          const SizedBox(height: 16),

          // Email
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),

          // Notes
          TextField(
            controller: _notesController,
            focusNode: _notesFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Notes'),
            maxLines: 3,
          ),

          // Delete button (edit mode only)
          if (_isEditMode) ...[
            const SizedBox(height: 32),
            Center(
              child: TextButton(
                onPressed: _deleteContact,
                child: const Text(
                  'Delete Contact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.error,
                  ),
                ),
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
