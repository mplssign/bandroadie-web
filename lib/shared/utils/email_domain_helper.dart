/// Helper utilities for email domain shortcuts on login screen.
///
/// These functions handle appending or replacing email domains
/// without touching any auth logic.
library;

/// Applies an email domain shortcut to the current input.
///
/// Rules:
/// - If [current] is empty or only whitespace, returns empty string (no change).
/// - If [current] has no @, appends [domain] (e.g., "tony" + "@gmail.com" → "tony@gmail.com").
/// - If [current] already has @, replaces everything from @ onward with [domain].
/// - Trims whitespace from [current] before processing.
///
/// Example:
/// ```dart
/// applyEmailDomainShortcut('tony', '@gmail.com');       // 'tony@gmail.com'
/// applyEmailDomainShortcut('tony@yahoo.com', '@icloud.com'); // 'tony@icloud.com'
/// applyEmailDomainShortcut('  ', '@gmail.com');         // ''
/// applyEmailDomainShortcut('', '@gmail.com');           // ''
/// ```
String applyEmailDomainShortcut(String current, String domain) {
  final trimmed = current.trim();

  // Empty input → do nothing
  if (trimmed.isEmpty) {
    return '';
  }

  // Check if @ already exists
  final atIndex = trimmed.indexOf('@');

  if (atIndex == -1) {
    // No @ present → append domain
    return '$trimmed$domain';
  } else {
    // @ exists → replace everything from @ onward
    final localPart = trimmed.substring(0, atIndex);
    return '$localPart$domain';
  }
}

/// Common email domains for shortcuts.
const List<String> emailDomainShortcuts = [
  '@gmail.com',
  '@yahoo.com',
  '@icloud.com',
  '@outlook.com',
];
