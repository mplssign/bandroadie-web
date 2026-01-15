import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// MASKED DURATION INPUT
// A currency-style input for time duration in MM:SS format.
//
// Behavior:
// - When focused/tapped, the value clears to 00:00 and cursor goes to end
// - Digits are inserted from the right and shift left as more are added
// - The colon (:) remains fixed at position 2
// - Backspace removes the rightmost digit and shifts remaining digits right
// - Only numeric input is accepted (0-9)
// - Maximum of 4 digits (MMSS)
// - Cursor always stays at the end
//
// Example typing sequence:
//   Initial: 03:30 (existing value)
//   Tap/Focus → 00:00 (cleared)
//   Type 1 → 00:01
//   Type 2 → 00:12
//   Type 3 → 01:23
//   Type 4 → 12:34
// ============================================================================

/// Formats a raw numeric string (up to 4 digits) into MM:SS format.
///
/// Examples:
///   "" → "00:00"
///   "1" → "00:01"
///   "12" → "00:12"
///   "123" → "01:23"
///   "1234" → "12:34"
///   "12345" → "23:45" (overflow: only last 4 digits kept)
String formatDurationMasked(String rawDigits) {
  // Remove any non-digit characters
  final digits = rawDigits.replaceAll(RegExp(r'[^0-9]'), '');

  // Take only the last 4 digits (in case of overflow)
  final trimmed = digits.length > 4
      ? digits.substring(digits.length - 4)
      : digits;

  // Pad with leading zeros to ensure 4 characters
  final padded = trimmed.padLeft(4, '0');

  // Insert colon at position 2
  return '${padded.substring(0, 2)}:${padded.substring(2, 4)}';
}

/// Parses a MM:SS formatted string back to total seconds.
///
/// Examples:
///   "00:00" → 0
///   "01:30" → 90
///   "12:34" → 754
int parseDurationMasked(String formatted) {
  final parts = formatted.split(':');
  if (parts.length != 2) return 0;

  final minutes = int.tryParse(parts[0]) ?? 0;
  final seconds = int.tryParse(parts[1]) ?? 0;

  return (minutes * 60) + seconds;
}

/// Converts total seconds to the raw 4-digit string for the masked input.
///
/// Examples:
///   0 → "0000"
///   90 → "0130"
///   754 → "1234"
String secondsToRawDigits(int totalSeconds) {
  // Clamp to max of 99:59 (5999 seconds)
  final clamped = totalSeconds.clamp(0, 5999);
  final minutes = clamped ~/ 60;
  final seconds = clamped % 60;
  return '${minutes.toString().padLeft(2, '0')}${seconds.toString().padLeft(2, '0')}';
}

/// A masked text input for duration in MM:SS format.
///
/// Behaves like a currency input where digits shift from right to left.
class MaskedDurationInput extends StatefulWidget {
  /// Initial value in total seconds
  final int initialSeconds;

  /// Called when the duration changes (value in seconds)
  final ValueChanged<int>? onChanged;

  /// Text style for the input
  final TextStyle? textStyle;

  /// Background color
  final Color? backgroundColor;

  /// Border color
  final Color? borderColor;

  /// Whether the input is enabled
  final bool enabled;

  /// Focus node (optional, one will be created if not provided)
  final FocusNode? focusNode;

  const MaskedDurationInput({
    super.key,
    this.initialSeconds = 0,
    this.onChanged,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<MaskedDurationInput> createState() => _MaskedDurationInputState();
}

class _MaskedDurationInputState extends State<MaskedDurationInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  // Raw digits without formatting (max 4 digits: MMSS)
  String _rawDigits = '';

  // Track if user has typed any digits during this focus session
  // Used to restore original value if user blurs without typing
  bool _hasTypedDuringFocus = false;

  // Store the original digits before clearing on focus
  String _originalDigitsBeforeFocus = '';

  @override
  void initState() {
    super.initState();

    // Initialize raw digits from initial seconds
    _rawDigits = secondsToRawDigits(widget.initialSeconds);

    // Create controller with formatted initial value
    _controller = TextEditingController(text: formatDurationMasked(_rawDigits));

    // Use provided focus node or create our own
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }

    // Ensure cursor is always at the end when focused
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(MaskedDurationInput oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If initial seconds changed externally, update the display
    if (widget.initialSeconds != oldWidget.initialSeconds) {
      _rawDigits = secondsToRawDigits(widget.initialSeconds);
      _updateDisplay();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Store original value before clearing
      _originalDigitsBeforeFocus = _rawDigits;
      _hasTypedDuringFocus = false;

      // Clear display to 00:00 when gaining focus for fresh entry
      // But DON'T notify parent yet - only notify when user actually types digits
      // This prevents accidental clearing of duration when user just taps the field
      _rawDigits = '';
      _updateDisplay();
    } else {
      // Losing focus - if user didn't type anything, restore original value
      if (!_hasTypedDuringFocus && _originalDigitsBeforeFocus.isNotEmpty) {
        _rawDigits = _originalDigitsBeforeFocus;
        _updateDisplay();
        // No need to notify parent since value is unchanged
      }
      _originalDigitsBeforeFocus = '';
    }
  }

  void _moveCursorToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
  }

  /// Updates the display text from raw digits
  void _updateDisplay() {
    final formatted = formatDurationMasked(_rawDigits);
    _controller.text = formatted;
    _moveCursorToEnd();
  }

  /// Handles a key press (digit or backspace)
  void _handleKeyPress(String key) {
    // Mark that user has typed during this focus session
    _hasTypedDuringFocus = true;

    if (key == 'backspace') {
      // Remove rightmost digit by removing last character from raw digits
      // Then shift remaining digits right (which happens naturally with padLeft)
      if (_rawDigits.isNotEmpty) {
        // Remove trailing zeros to find actual digits, then remove last one
        final trimmed = _rawDigits.replaceFirst(RegExp(r'^0+'), '');
        if (trimmed.isNotEmpty) {
          _rawDigits = trimmed.substring(0, trimmed.length - 1);
        } else {
          _rawDigits = '';
        }
      }
    } else if (RegExp(r'^[0-9]$').hasMatch(key)) {
      // Add digit to the right (append to raw digits)
      // The formatting will handle the left-shift display
      final newRaw = _rawDigits.replaceFirst(RegExp(r'^0+'), '') + key;

      // Limit to 4 digits max (99:59)
      if (newRaw.length <= 4) {
        _rawDigits = newRaw;
      } else {
        // Overflow: keep only last 4 digits
        _rawDigits = newRaw.substring(newRaw.length - 4);
      }
    }

    _updateDisplay();

    // Notify listener of change
    if (widget.onChanged != null) {
      final seconds = parseDurationMasked(_controller.text);
      widget.onChanged!(seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTextStyle =
        widget.textStyle ??
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Color(0xFFF5F5F5),
        );

    final effectiveBgColor = widget.backgroundColor ?? const Color(0xFF2C2C2C);
    final effectiveBorderColor = widget.borderColor ?? Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: effectiveBgColor,
        border: Border.all(color: effectiveBorderColor, width: 1),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: KeyboardListener(
        focusNode: FocusNode(), // Dummy focus node for keyboard listener
        onKeyEvent: (event) {
          if (!widget.enabled) return;
          if (event is! KeyDownEvent) return;

          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.backspace) {
            _handleKeyPress('backspace');
          }
        },
        child: GestureDetector(
          onTap: widget.enabled
              ? () {
                  _focusNode.requestFocus();
                }
              : null,
          child: AbsorbPointer(
            // Use AbsorbPointer to prevent TextField from handling taps
            // This ensures our custom keyboard handling works
            absorbing: false,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              readOnly: false,
              showCursor: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: effectiveTextStyle,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              // Intercept all input via inputFormatters
              inputFormatters: [
                _DurationInputFormatter(
                  onDigit: (digit) => _handleKeyPress(digit),
                  onBackspace: () => _handleKeyPress('backspace'),
                  getCurrentText: () => _controller.text,
                ),
              ],
              onChanged: (_) {
                // Input is handled by formatter, just ensure cursor is at end
                _moveCursorToEnd();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom input formatter that intercepts input and converts it to our masked format.
///
/// This formatter:
/// 1. Extracts any new digits from the input
/// 2. Calls the onDigit callback for each new digit
/// 3. Detects backspace (when text gets shorter) and calls onBackspace
/// 4. Returns the current formatted text (unchanged by direct input)
class _DurationInputFormatter extends TextInputFormatter {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final String Function() getCurrentText;

  _DurationInputFormatter({
    required this.onDigit,
    required this.onBackspace,
    required this.getCurrentText,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    // Detect backspace: new text is shorter and a suffix of old text
    if (newText.length < oldText.length) {
      onBackspace();
      // Return current text to prevent direct modification
      final current = getCurrentText();
      return TextEditingValue(
        text: current,
        selection: TextSelection.collapsed(offset: current.length),
      );
    }

    // Detect new input: extract digits from new text that weren't in old text
    if (newText.length > oldText.length) {
      // Find the new characters
      String newChars;

      // Check if it's insertion at end (most common case)
      if (newValue.selection.baseOffset == newText.length) {
        newChars = newText.substring(oldText.length);
      } else {
        // For paste or insertion elsewhere, find all new chars
        newChars = newText.replaceAll(RegExp(r'[^0-9]'), '');
        final oldDigits = oldText.replaceAll(RegExp(r'[^0-9]'), '');
        if (newChars.length > oldDigits.length) {
          newChars = newChars.substring(oldDigits.length);
        } else {
          newChars = '';
        }
      }

      // Process each new digit
      for (final char in newChars.split('')) {
        if (RegExp(r'^[0-9]$').hasMatch(char)) {
          onDigit(char);
        }
      }

      // Return current text to prevent direct modification
      final current = getCurrentText();
      return TextEditingValue(
        text: current,
        selection: TextSelection.collapsed(offset: current.length),
      );
    }

    // No change in length (could be selection change or other)
    // Just ensure cursor stays at end
    return TextEditingValue(
      text: oldText,
      selection: TextSelection.collapsed(offset: oldText.length),
    );
  }
}
