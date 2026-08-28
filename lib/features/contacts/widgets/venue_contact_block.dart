import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';
import '../../../shared/utils/phone_input_formatter.dart';
import 'title_pill_selector.dart';
import '../../../components/ui/app_icon_button.dart';
import '../../../components/ui/app_text_field.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
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
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.delete,
                size: 20,
                color: AppColors.error,
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Name
          AppTextField(
            controller: _nameController,
            focusNode: _nameFocus,
            labelText: 'Name',
          ),
          const SizedBox(height: 16),

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
            onChanged: (title) {
              setState(() => _selectedTitle = title);
              _emitChange();
            },
          ),
          const SizedBox(height: 16),

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
            enabled: true,
          ),
          const SizedBox(height: 16),

          // Notes
          AppTextField(
            controller: _notesController,
            focusNode: _notesFocus,
            labelText: 'Notes',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
