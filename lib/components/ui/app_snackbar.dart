import 'package:flutter/material.dart';

/// Snackbar type for styling
enum SnackbarType {
  /// Informational snackbar (theme default)
  info,

  /// Success snackbar (green background)
  success,

  /// Error snackbar (red background)
  error,
}

/// Shows an app-themed snackbar with message and optional action.
///
/// Use this instead of [ScaffoldMessenger.showSnackBar] to ensure
/// consistent snackbar styling across the app.
///
/// The [type] parameter controls the background color:
/// - [SnackbarType.info]: uses theme default
/// - [SnackbarType.success]: green background
/// - [SnackbarType.error]: red background
void showAppSnackbar({
  required BuildContext context,
  required String message,
  SnackBarAction? action,
  Duration? duration,
  SnackbarType type = SnackbarType.info,
}) {
  // Determine background color based on type
  Color? backgroundColor;
  switch (type) {
    case SnackbarType.info:
      backgroundColor = null; // Use theme default
    case SnackbarType.success:
      backgroundColor = Colors.green;
    case SnackbarType.error:
      backgroundColor = Colors.red;
  }

  final snackBar = SnackBar(
    content: Text(message),
    action: action,
    duration: duration ?? const Duration(seconds: 4),
    backgroundColor: backgroundColor,
  );

  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}
