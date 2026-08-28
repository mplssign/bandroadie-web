import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../shared/utils/snackbar_helper.dart';
import 'bug_report_email_service.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_text_form_field.dart';

// ============================================================================
// BUG REPORT SCREEN
// Allows users to report bugs or request features.
// Sends via email (mailto:) - NO Supabase writes.
// ============================================================================

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  _FeedbackType _selectedType = _FeedbackType.bug;
  bool _isSubmitting = false;

  // For clipboard fallback when email fails
  String? _fallbackReportText;
  String? _fallbackErrorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    // Prevent double-submit
    if (_isSubmitting) return;

    // Validate form
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _fallbackReportText = null;
      _fallbackErrorMessage = null;
    });

    final result = await BugReportEmailService.send(
      type: _selectedType.name,
      description: _descriptionController.text.trim(),
      screenName: 'Report Bugs',
    );

    if (!mounted) return;

    switch (result) {
      case BugReportSuccess():
        // Success - show toast and close screen
        showSuccessSnackBar(
          context,
          message: _selectedType == _FeedbackType.bug
              ? "Bug report sent! We'll look into it."
              : "Feature request sent! Thanks for the idea.",
        );
        Navigator.of(context).pop();

      case BugReportEmailAppNotFound(:final reportText):
        // Can't open email - show fallback with copy button
        setState(() {
          _isSubmitting = false;
          _fallbackErrorMessage = "Couldn't send your report automatically.";
          _fallbackReportText = reportText;
        });

      case BugReportLaunchFailed(:final reportText):
        // Failed to launch - show fallback with copy button
        setState(() {
          _isSubmitting = false;
          _fallbackErrorMessage = "Something went wrong sending your report.";
          _fallbackReportText = reportText;
        });
    }
  }

  void _copyReportToClipboard() {
    if (_fallbackReportText == null) return;

    final fullText = '''
To: ${BugReportEmailService.recipientEmail}
Subject: BandRoadie ${_selectedType == _FeedbackType.bug ? 'Bug Report' : 'Feature Request'}

$_fallbackReportText
''';

    Clipboard.setData(ClipboardData(text: fullText));

    showSuccessSnackBar(context, message: 'Report copied to clipboard!');
  }

  void _dismissFallback() {
    setState(() {
      _fallbackReportText = null;
      _fallbackErrorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.appBarBg,
        title: Text(
          'Report Bugs',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppFontSizes.title2,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: AppIconButton(
          icon: AppIcons.arrowLeft,
          color: AppColors.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Material(
        color: Colors.transparent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.space24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header text
                Text('Help us improve BandRoadie', style: AppTextStyles.title3),
                const SizedBox(height: Spacing.space8),
                Text(
                  'Report a bug you encountered or suggest a new feature you\'d like to see.',
                  style: AppTextStyles.callout,
                ),

                const SizedBox(height: Spacing.space32),

                // Type selector
                Text(
                  'Type',
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space12),
                Row(
                  children: [
                    Expanded(
                      child: _TypeChip(
                        label: 'Bug Report',
                        icon: AppIcons.bug,
                        isSelected: _selectedType == _FeedbackType.bug,
                        onTap: () =>
                            setState(() => _selectedType = _FeedbackType.bug),
                      ),
                    ),
                    const SizedBox(width: Spacing.space12),
                    Expanded(
                      child: _TypeChip(
                        label: 'Feature Request',
                        icon: Icons.lightbulb_outline_rounded,
                        isSelected: _selectedType == _FeedbackType.feature,
                        onTap: () => setState(
                            () => _selectedType = _FeedbackType.feature),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: Spacing.space24),

                // Description field
                Text(
                  'Description',
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                AppTextFormField(
                  controller: _descriptionController,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  hintText: _selectedType == _FeedbackType.bug
                      ? 'What happened? What did you expect to happen? Steps to reproduce...'
                      : 'Describe the feature and how it would help you...',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please provide some details';
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide more details (at least 10 characters)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: Spacing.space32),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: Spacing.space16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                      ),
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _selectedType == _FeedbackType.bug
                                ? 'Submit Bug Report'
                                : 'Submit Feature Request',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppFontSizes.body,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: Spacing.space16),

                // Note about response
                Center(
                  child: Text(
                    'We read every submission and appreciate your feedback!',
                    style: AppTextStyles.footnote.copyWith(
                      color: context.colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Fallback UI when email can't be opened
                if (_fallbackReportText != null) ...[
                  const SizedBox(height: Spacing.space24),
                  _FallbackCard(
                    errorMessage:
                        _fallbackErrorMessage ?? 'Unable to open email',
                    onCopy: _copyReportToClipboard,
                    onDismiss: _dismissFallback,
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

/// Fallback card shown when email app can't be opened.
class _FallbackCard extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  const _FallbackCard({
    required this.errorMessage,
    required this.onCopy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.warning, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.warning,
                color: context.colors.warning,
                size: 20,
              ),
              const SizedBox(width: Spacing.space8),
              Expanded(
                child: Text(
                  errorMessage,
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  AppIcons.close,
                  color: context.colors.textSecondary,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.space12),
          Text(
            'No worries! Copy your report below and email it to us at ${BugReportEmailService.recipientEmail}',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.space12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(AppIcons.copy, size: 18),
              label: const Text('Copy Report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _FeedbackType { bug, feature }

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space14,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color:
                  isSelected ? AppColors.primary : context.colors.textSecondary,
            ),
            const SizedBox(width: Spacing.space8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.footnote.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : context.colors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
