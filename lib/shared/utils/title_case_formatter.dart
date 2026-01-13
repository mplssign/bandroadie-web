import 'package:flutter/services.dart';

// ============================================================================
// TITLE CASE TEXT FORMATTER
// Capitalizes the first letter of each word as user types.
// Words are split on spaces and hyphens.
// ============================================================================

/// Converts a string to Title Case.
///
/// Title Case rules:
/// - Split on spaces and hyphens
/// - Uppercase first letter of each word
/// - Keep the rest lowercase
///
/// Examples:
/// - "hello world" → "Hello World"
/// - "new-york city" → "New-York City"
/// - "TESTING case" → "Testing Case"
/// - "the beatles" → "The Beatles"
String toTitleCase(String input) {
  if (input.isEmpty) return input;

  final result = StringBuffer();
  bool capitalizeNext = true;

  for (int i = 0; i < input.length; i++) {
    final char = input[i];

    if (char == ' ' || char == '-') {
      result.write(char);
      capitalizeNext = true;
    } else if (capitalizeNext) {
      result.write(char.toUpperCase());
      capitalizeNext = false;
    } else {
      result.write(char.toLowerCase());
    }
  }

  return result.toString();
}

/// Text input formatter that converts input to Title Case in real time.
///
/// Title Case rules:
/// - Split on spaces and hyphens
/// - Uppercase first letter of each word
/// - Keep the rest lowercase
///
/// Examples:
/// - "hello world" → "Hello World"
/// - "new-york city" → "New-York City"
/// - "TESTING case" → "Testing Case"
class TitleCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final result = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < newValue.text.length; i++) {
      final char = newValue.text[i];

      if (char == ' ' || char == '-') {
        result.write(char);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        result.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        result.write(char.toLowerCase());
      }
    }

    return TextEditingValue(
      text: result.toString(),
      selection: newValue.selection,
    );
  }
}
