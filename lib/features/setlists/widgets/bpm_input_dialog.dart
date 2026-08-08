import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../components/ui/app_text_field.dart';
import '../../../components/ui/app_button.dart';

/// Result type for dialogs that can be cancelled, cleared, or return a value
sealed class DialogResult<T> {}

class DialogCancelled<T> extends DialogResult<T> {}

class DialogCleared<T> extends DialogResult<T> {}

class DialogValue<T> extends DialogResult<T> {
  final T value;
  DialogValue(this.value);
}

/// Shows a dialog for BPM input with validation
///
/// Returns:
/// - [DialogCancelled] if user taps Cancel
/// - [DialogCleared] if user taps Clear
/// - [DialogValue] with the BPM if user taps Save with valid input
Future<DialogResult<int>> showBpmInputDialog(
  BuildContext context, {
  int? initialBpm,
}) async {
  final result = await showDialog<DialogResult<int>>(
    context: context,
    builder: (context) => _BpmInputDialog(initialBpm: initialBpm),
  );
  return result ?? DialogCancelled<int>();
}

class _BpmInputDialog extends StatefulWidget {
  final int? initialBpm;

  const _BpmInputDialog({this.initialBpm});

  @override
  State<_BpmInputDialog> createState() => _BpmInputDialogState();
}

class _BpmInputDialogState extends State<_BpmInputDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialBpm?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorText = null;
      });
      return;
    }

    final value = int.tryParse(text);
    if (value == null) {
      setState(() {
        _errorText = 'Invalid number';
      });
      return;
    }

    if (value < 20 || value > 300) {
      setState(() {
        _errorText = 'BPM must be between 20 and 300';
      });
      return;
    }

    setState(() {
      _errorText = null;
    });
  }

  void _handleSave() {
    _validate();
    if (_errorText != null) {
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(DialogCleared<int>());
      return;
    }

    final value = int.tryParse(text);
    if (value != null && value >= 20 && value <= 300) {
      Navigator.of(context).pop(DialogValue<int>(value));
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
        'BPM',
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
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            autofocus: true,
            style: AppTextStyles.callout.copyWith(
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'Enter BPM (20-300)',
              hintStyle: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(
                  color: context.colors.border,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(
                  color: context.colors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide(
                  color: AppColors.primary,
                  width: 2.0,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: const BorderSide(
                  color: AppColors.error,
                  width: 2.0,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: const BorderSide(
                  color: AppColors.error,
                  width: 2.0,
                ),
              ),
              errorText: _errorText,
            ),
            onChanged: (_) => _validate(),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.text,
          onPressed: _handleCancel,
        ),
        AppButton(
          label: 'Clear',
          variant: AppButtonVariant.text,
          onPressed: _handleClear,
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.text,
          onPressed: _handleSave,
        ),
      ],
    );
  }
}
