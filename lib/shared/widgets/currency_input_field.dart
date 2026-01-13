import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/design_tokens.dart';

// ============================================================================
// CURRENCY INPUT FIELD
// POS-style currency input where digits shift like a cash register.
// Example: Typing "1", "2", "5", "0", "0" → $0.01 → $0.12 → $1.25 → $12.50 → $125.00
//
// Internal storage: Integer cents (avoids floating-point precision issues)
// Display: Formatted as $X.XX
// ============================================================================

/// Controller for managing currency input values.
/// Stores value internally as integer cents for precision.
class CurrencyInputController extends ValueNotifier<int> {
  CurrencyInputController([super.initialCents = 0]);

  /// Current value in cents (integer)
  int get cents => value;

  /// Current value as dollars (for display/storage)
  double get dollars => value / 100.0;

  /// Set value from cents
  set cents(int newCents) {
    value = newCents.clamp(0, 99999999); // Max $999,999.99
  }

  /// Set value from dollars (converts to cents)
  set dollars(double newDollars) {
    value = (newDollars * 100).round().clamp(0, 99999999);
  }

  /// Format current value as currency string (e.g., "$125.00")
  String get formattedValue {
    final dollarPart = value ~/ 100;
    final centsPart = value % 100;

    // Add thousands separators for large amounts
    final dollarStr = _formatWithCommas(dollarPart);

    return '\$$dollarStr.${centsPart.toString().padLeft(2, '0')}';
  }

  /// Format integer with thousands separators
  static String _formatWithCommas(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    final length = str.length;

    for (int i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }

    return buffer.toString();
  }

  /// Clear to zero
  void clear() {
    value = 0;
  }

  /// Returns true if value is zero
  bool get isEmpty => value == 0;

  /// Returns true if value is non-zero
  bool get isNotEmpty => value != 0;
}

/// POS-style currency input field widget.
/// Digits shift from right to left like a cash register display.
class CurrencyInputField extends StatefulWidget {
  const CurrencyInputField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.hint = '\$0.00',
    this.enabled = true,
    this.onChanged,
  });

  final CurrencyInputController controller;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  State<CurrencyInputField> createState() => _CurrencyInputFieldState();
}

class _CurrencyInputFieldState extends State<CurrencyInputField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.formattedValue,
    );
    _focusNode = FocusNode();

    // Listen to controller changes to update display
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final newText = widget.controller.formattedValue;
    if (_textController.text != newText) {
      _textController.text = newText;
      // Move cursor to end
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
    }
  }

  /// Handle key input for POS-style behavior
  void _handleKeyInput(String key) {
    if (!widget.enabled) return;

    if (key == 'backspace') {
      // Remove rightmost digit: shift right (divide by 10)
      widget.controller.cents = widget.controller.cents ~/ 10;
    } else {
      // Parse digit and shift left (multiply by 10, add new digit)
      final digit = int.tryParse(key);
      if (digit != null && digit >= 0 && digit <= 9) {
        final newCents = widget.controller.cents * 10 + digit;
        // Prevent overflow (max $999,999.99)
        if (newCents <= 99999999) {
          widget.controller.cents = newCents;
        }
      }
    }

    // Update text field display
    _textController.text = widget.controller.formattedValue;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );

    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              final logicalKey = event.logicalKey;

              // Handle digit keys (both numpad and regular)
              if (logicalKey.keyId >= LogicalKeyboardKey.digit0.keyId &&
                  logicalKey.keyId <= LogicalKeyboardKey.digit9.keyId) {
                final digit = logicalKey.keyId - LogicalKeyboardKey.digit0.keyId;
                _handleKeyInput(digit.toString());
              } else if (logicalKey.keyId >= LogicalKeyboardKey.numpad0.keyId &&
                  logicalKey.keyId <= LogicalKeyboardKey.numpad9.keyId) {
                final digit = logicalKey.keyId - LogicalKeyboardKey.numpad0.keyId;
                _handleKeyInput(digit.toString());
              } else if (logicalKey == LogicalKeyboardKey.backspace ||
                  logicalKey == LogicalKeyboardKey.delete) {
                _handleKeyInput('backspace');
              }
            }
          },
          child: GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? AppColors.accent
                      : AppColors.borderMuted,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.controller.isEmpty
                          ? widget.hint
                          : widget.controller.formattedValue,
                      style: AppTextStyles.callout.copyWith(
                        color: widget.controller.isEmpty
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.controller.isNotEmpty && widget.enabled)
                    GestureDetector(
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged?.call();
                      },
                      child: Icon(
                        Icons.clear,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Alternative: Simple text field with custom input handling for mobile.
/// This version uses a raw text field that intercepts input.
class CurrencyTextField extends StatefulWidget {
  const CurrencyTextField({
    super.key,
    required this.controller,
    this.label = 'Gig Pay (optional)',
    this.hint = '\$0.00',
    this.enabled = true,
    this.onChanged,
  });

  final CurrencyInputController controller;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  State<CurrencyTextField> createState() => _CurrencyTextFieldState();
}

class _CurrencyTextFieldState extends State<CurrencyTextField> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.isEmpty ? '' : widget.controller.formattedValue,
    );
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _textController.dispose();
    super.dispose();
  }

  void _syncFromController() {
    final display =
        widget.controller.isEmpty ? '' : widget.controller.formattedValue;
    if (_textController.text != display) {
      _textController.text = display;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: display.length),
      );
    }
    setState(() {});
  }

  void _onChanged(String value) {
    // Extract only digits from input
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      widget.controller.cents = 0;
    } else {
      // Parse as cents (POS style: digits represent cents)
      final cents = int.tryParse(digitsOnly) ?? 0;
      widget.controller.cents = cents.clamp(0, 99999999);
    }

    // Update display
    final display =
        widget.controller.isEmpty ? '' : widget.controller.formattedValue;
    _textController.text = display;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: display.length),
    );

    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _textController,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _CurrencyInputFormatter(widget.controller),
          ],
          style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTextStyles.callout.copyWith(
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.scaffoldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
            suffixIcon: widget.controller.isNotEmpty && widget.enabled
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    color: AppColors.textMuted,
                    onPressed: () {
                      widget.controller.clear();
                      _textController.clear();
                      widget.onChanged?.call();
                      setState(() {});
                    },
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Custom input formatter for POS-style currency entry
class _CurrencyInputFormatter extends TextInputFormatter {
  _CurrencyInputFormatter(this.controller);

  final CurrencyInputController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Extract digits only
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      controller.cents = 0;
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Parse as cents
    final cents = int.tryParse(digitsOnly) ?? 0;
    controller.cents = cents.clamp(0, 99999999);

    // Format for display
    final formatted = controller.formattedValue;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
