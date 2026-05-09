import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/domain_chip.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';
import '../../../shared/utils/phone_input_formatter.dart';
import 'title_pill_selector.dart';

// ============================================================================
// VENUE CONTACT BLOCK
// Self-contained form block for one venue contact within VenueFormScreen.
// Parent AnimatedList handles enter/exit animation.
// ============================================================================

class VenueContactBlock extends StatefulWidget {
  final String? initialName;
  final String? initialTitle;
  final String? initialPhone;
  final String? initialEmail;
  final String? initialNotes;
  final String? timezone;
  final VoidCallback onRemove;
  final ValueChanged<Map<String, String?>> onChanged;

  const VenueContactBlock({
    super.key,
    this.initialName,
    this.initialTitle,
    this.initialPhone,
    this.initialEmail,
    this.initialNotes,
    this.timezone,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<VenueContactBlock> createState() => _VenueContactBlockState();
}

class _VenueContactBlockState extends State<VenueContactBlock> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;
  late FocusNode _nameFocus;
  late FocusNode _phoneFocus;
  late FocusNode _emailFocus;
  late FocusNode _notesFocus;
  String? _selectedTitle;
  String? _selectedDomain;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _notesController = TextEditingController(text: widget.initialNotes ?? '');
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _emailFocus = FocusNode();
    _notesFocus = FocusNode();
    _selectedTitle = widget.initialTitle;

    _nameController.addListener(_emitChange);
    _phoneController.addListener(_emitChange);
    _emailController.addListener(_emitChange);
    _notesController.addListener(_emitChange);
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

  void _emitChange() {
    widget.onChanged({
      'name': _nameController.text,
      'title': _selectedTitle,
      'phone': _phoneController.text,
      'email': _emailController.text,
      'notes': _notesController.text,
    });
  }

  List<TextInputFormatter> _getPhoneFormatters() {
    return isUSTimezone(widget.timezone)
        ? [USPhoneInputFormatter(isUSTimezone: true)]
        : [];
  }

  void _applyDomainShortcut(String domain) {
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

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.colors.textMuted),
      filled: true,
      fillColor: context.colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with remove button
          Row(
            children: [
              Expanded(
                child: Text(
                  'Contact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(AppIcons.delete, size: 20),
                color: AppColors.error,
                onPressed: widget.onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Name
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Name'),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            'Title',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TitlePillSelector(
            selectedTitle: _selectedTitle,
            onChanged: (title) {
              setState(() => _selectedTitle = title);
              _emitChange();
            },
          ),
          const SizedBox(height: 12),

          // Phone
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Phone'),
            keyboardType: TextInputType.phone,
            inputFormatters: _getPhoneFormatters(),
          ),
          const SizedBox(height: 12),

          // Email
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: emailDomainShortcuts.asMap().entries.map((entry) {
                final index = entry.key;
                final domain = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index < emailDomainShortcuts.length - 1 ? 8 : 0,
                  ),
                  child: DomainChip(
                    domain: domain,
                    isSelected: _selectedDomain == domain,
                    isEnabled: true,
                    onTap: () => _applyDomainShortcut(domain),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Notes
          TextField(
            controller: _notesController,
            focusNode: _notesFocus,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Notes'),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
