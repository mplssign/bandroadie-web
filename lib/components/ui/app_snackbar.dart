import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Snackbar type for styling
enum SnackbarType {
  /// Informational snackbar
  info,

  /// Success snackbar
  success,

  /// Error snackbar
  error,
}

/// Shows an app-themed toast using Forui design system.
///
/// Use this instead of [ScaffoldMessenger.showSnackBar] to ensure
/// consistent toast styling across the app.
///
/// **Note for preview cycle:** The [type] parameter maps to Forui variants:
/// - [SnackbarType.info] and [SnackbarType.success] → .primary variant
/// - [SnackbarType.error] → .destructive variant
void showAppSnackbar({
  required BuildContext context,
  required String message,
  SnackBarAction? action,
  Duration? duration,
  SnackbarType type = SnackbarType.info,
}) {
  // Map SnackbarType to FToastVariant
  final variant = type == SnackbarType.error
      ? FToastVariant.destructive
      : FToastVariant.primary;

  showFToast(
    context: context,
    title: Text(message),
    variant: variant,
    duration: duration ?? const Duration(seconds: 4),
    suffixBuilder: action != null
        ? (context, entry) => TextButton(
              onPressed: action.onPressed,
              child: Text(action.label),
            )
        : null,
  );
}
