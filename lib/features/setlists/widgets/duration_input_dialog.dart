import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';
import 'bpm_input_dialog.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_button.dart';

/// Shows a dialog for duration input in mm:ss format
///
/// Returns:
/// - [DialogCancelled] if user taps Cancel
/// - [DialogCleared] if user taps Clear
/// - [DialogValue] with seconds if user taps Save with valid input
Future<DialogResult<int>> showDurationInputDialog(
  BuildContext context, {
  int initialSeconds = 0,
}) async {
  final result = await showDialog<DialogResult<int>>(
    context: context,
    builder: (context) => _DurationInputDialog(initialSeconds: initialSeconds),
  );
  return result ?? DialogCancelled<int>();
}

class _DurationInputDialog extends StatefulWidget {
  final int initialSeconds;

  const _DurationInputDialog({required this.initialSeconds});

  @override
  State<_DurationInputDialog> createState() => _DurationInputDialogState();
}

class _DurationInputDialogState extends State<_DurationInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final minutes = widget.initialSeconds ~/ 60;
    final seconds = widget.initialSeconds % 60;
    final formatted = widget.initialSeconds > 0
        ? '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '';
    _controller = TextEditingController(text: formatted);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _parseSeconds() {
    final text = _controller.text.trim();
    if (text.isEmpty) return 0;

    final parts = text.split(':');
    if (parts.length != 2) return null;

    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);

    if (minutes == null || seconds == null) return null;
    if (minutes < 0 || minutes > 99) return null;
    if (seconds < 0 || seconds > 59) return null;

    return (minutes * 60) + seconds;
  }

  void _handleSave() {
    final seconds = _parseSeconds();
    if (seconds != null) {
      Navigator.of(context).pop(DialogValue<int>(seconds));
    }
  }

  void _handleClear() {
    Navigator.of(context).pop(DialogCleared<int>());
  }

  void _handleCancel() {
    Navigator.of(context).pop(DialogCancelled<int>());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(
        'Duration',
        style: AppTextStyles.headline.copyWith(
          color: Colors.white,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              _DurationFormatter(),
            ],
            autofocus: true,
            hintText: 'MM:SS',
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _handleCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.space12,
                      vertical: Spacing.space8,
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.title3.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _handleClear,
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.space12,
                      vertical: Spacing.space8,
                    ),
                  ),
                  child: Text(
                    'Clear',
                    style: AppTextStyles.title3.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.space12),
            AppButton(
              label: 'Save',
              variant: AppButtonVariant.primary,
              fullWidth: true,
              backgroundColor: AppColors.primary,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: _handleSave,
            ),
          ],
        ),
      ],
    );
  }
}

/// Formatter that ensures MM:SS format
class _DurationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Remove all non-digits
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 4 digits (MMSS)
    final limited =
        digitsOnly.length > 4 ? digitsOnly.substring(0, 4) : digitsOnly;

    // Format as MM:SS
    String formatted;
    if (limited.isEmpty) {
      formatted = '';
    } else if (limited.length <= 2) {
      formatted = limited;
    } else {
      final minutes = limited.substring(0, limited.length - 2);
      final seconds = limited.substring(limited.length - 2);
      formatted = '$minutes:$seconds';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
