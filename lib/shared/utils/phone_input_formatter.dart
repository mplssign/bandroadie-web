import 'package:flutter/services.dart';

/// Formats a phone number as (123) 456-7890 for US timezone bands.
/// Pass isUSTimezone: true to activate formatting; false passes input through unchanged.
class USPhoneInputFormatter extends TextInputFormatter {
  final bool isUSTimezone;

  const USPhoneInputFormatter({required this.isUSTimezone});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!isUSTimezone) return newValue;

    // Strip all non-digit characters
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Truncate to 10 digits max
    final capped = digits.length > 10 ? digits.substring(0, 10) : digits;

    // Build formatted string
    final formatted = _format(capped);

    // Place cursor at end of formatted text
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _format(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 3) return '($digits';
    if (digits.length <= 6) {
      return '(${digits.substring(0, 3)}) ${digits.substring(3)}';
    }
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  }
}

/// Returns true if the given IANA timezone identifier is a US timezone.
bool isUSTimezone(String? timezone) {
  const usTZs = {
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
  };
  return usTZs.contains(timezone);
}

/// Returns true if the given IANA timezone identifier is a Canadian timezone.
bool isCanadianTimezone(String? timezone) {
  const caTZs = {
    'America/Vancouver',
    'America/Edmonton',
    'America/Regina',
    'America/Toronto',
    'America/Halifax',
    'America/St_Johns',
  };
  return caTZs.contains(timezone);
}

/// Returns true if the given IANA timezone identifier is a UK timezone.
bool isUKTimezone(String? timezone) {
  return timezone == 'Europe/London';
}
