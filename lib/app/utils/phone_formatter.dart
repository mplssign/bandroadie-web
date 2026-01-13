import 'package:flutter/services.dart';

// ============================================================================
// PHONE NUMBER INPUT FORMATTER
// Formats US phone numbers as (xxx) xxx-xxxx while the user types.
//
// Features:
// - Live formatting as user types
// - Natural cursor positioning (no jumping to end)
// - Accepts only digits
// - Max 10 digits
// - Handles paste of formatted or unformatted numbers
// - Backspace works naturally
// ============================================================================

class PhoneNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Extract only digits from the new value
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Limit to 10 digits
    final digits = digitsOnly.length > 10
        ? digitsOnly.substring(0, 10)
        : digitsOnly;

    // Format the digits
    final formatted = _formatPhoneNumber(digits);

    // Calculate new cursor position
    final newCursorPosition = _calculateCursorPosition(
      oldValue: oldValue,
      newValue: newValue,
      formatted: formatted,
      digits: digits,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPosition),
    );
  }

  /// Format digits into (xxx) xxx-xxxx pattern
  String _formatPhoneNumber(String digits) {
    if (digits.isEmpty) return '';

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i == 0) buffer.write('(');
      if (i == 3) buffer.write(') ');
      if (i == 6) buffer.write('-');
      buffer.write(digits[i]);
    }

    // Close parenthesis if we have exactly 1-3 digits
    // (handled by the loop adding open paren at 0)

    return buffer.toString();
  }

  /// Calculate the appropriate cursor position after formatting
  int _calculateCursorPosition({
    required TextEditingValue oldValue,
    required TextEditingValue newValue,
    required String formatted,
    required String digits,
  }) {
    // If text was deleted, find the right position
    if (newValue.text.length < oldValue.text.length) {
      // Count digits before cursor in old value
      final oldDigitsBefore = _countDigitsBefore(
        oldValue.text,
        oldValue.selection.end,
      );
      // User deleted, so we want one fewer digit
      final targetDigits = oldDigitsBefore - 1;
      return _positionAfterDigits(
        formatted,
        targetDigits.clamp(0, digits.length),
      );
    }

    // For additions (typing or paste), count digits typed
    final newDigitsInInput = newValue.text
        .replaceAll(RegExp(r'[^\d]'), '')
        .length;
    final oldDigitsBeforeCursor = _countDigitsBefore(
      oldValue.text,
      oldValue.selection.end,
    );

    // How many digits were added at the cursor position
    final digitsAdded =
        newDigitsInInput -
        oldValue.text.replaceAll(RegExp(r'[^\d]'), '').length;
    final targetDigits = (oldDigitsBeforeCursor + digitsAdded).clamp(
      0,
      digits.length,
    );

    return _positionAfterDigits(formatted, targetDigits);
  }

  /// Count how many digits appear before a given position in a string
  int _countDigitsBefore(String text, int position) {
    int count = 0;
    for (int i = 0; i < position && i < text.length; i++) {
      if (RegExp(r'\d').hasMatch(text[i])) {
        count++;
      }
    }
    return count;
  }

  /// Find the position in formatted string after N digits
  int _positionAfterDigits(String formatted, int digitCount) {
    int seen = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        seen++;
        if (seen == digitCount) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }
}

/// Helper to strip formatting from a phone number
/// Returns only the digits (e.g., "(312) 550-7844" → "3125507844")
String stripPhoneFormatting(String formattedPhone) {
  return formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
}

/// Normalize a US phone number to digits only (10 digits max)
/// Returns empty string if input has no digits
/// (e.g., "(312) 550-7844" → "3125507844", "+1 312-550-7844" → "3125507844")
String normalizeUsPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^\d]'), '');
  // If starts with "1" and has 11 digits, strip the leading 1 (country code)
  if (digits.length == 11 && digits.startsWith('1')) {
    return digits.substring(1);
  }
  // Return first 10 digits
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

/// Check if a phone string represents a valid 10-digit US phone number
bool isValidUsPhone(String input) {
  final normalized = normalizeUsPhone(input);
  return normalized.length == 10;
}

/// Normalize phone for storage - returns null if empty, digits-only otherwise
/// Use this before saving to Supabase
String? normalizePhoneForStorage(String input) {
  final normalized = normalizeUsPhone(input);
  return normalized.isEmpty ? null : normalized;
}

/// Helper to format a raw phone number string
/// (e.g., "3125507844" → "(312) 550-7844")
String formatPhoneNumber(String digits) {
  final cleaned = digits.replaceAll(RegExp(r'[^\d]'), '');
  if (cleaned.isEmpty) return '';

  final buffer = StringBuffer();
  for (int i = 0; i < cleaned.length && i < 10; i++) {
    if (i == 0) buffer.write('(');
    if (i == 3) buffer.write(') ');
    if (i == 6) buffer.write('-');
    buffer.write(cleaned[i]);
  }
  return buffer.toString();
}
