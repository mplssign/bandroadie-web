import 'package:flutter/material.dart';

/// Dialog action button configuration
class DialogAction {
  const DialogAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  /// Button label text
  final String label;

  /// Callback when button is pressed
  final VoidCallback? onPressed;

  /// Whether this is a destructive action (styled differently)
  final bool isDestructive;
}

/// Shows an app-themed dialog with title, message, and action buttons.
///
/// Use this instead of [showDialog] with [AlertDialog] to ensure
/// consistent dialog styling across the app.
///
/// When [builder] is provided, it is used to construct a custom dialog,
/// and [title], [message], and [actions] are ignored.
/// When [builder] is null, [title], [message], and [actions] must be provided
/// to construct a standard [AppAlertDialog].
///
/// Returns the result passed to [Navigator.pop] when the dialog is dismissed.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  String? title,
  String? message,
  List<DialogAction>? actions,
  bool barrierDismissible = true,
  WidgetBuilder? builder,
}) {
  if (builder != null) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  if (title == null || message == null || actions == null) {
    throw ArgumentError(
      'Either provide builder or provide title, message, and actions',
    );
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) =>
        AppAlertDialog(title: title, message: message, actions: actions),
  );
}

/// Alert dialog widget that respects app theme configuration.
///
/// Typically used via [showAppDialog] helper function rather than directly.
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
  });

  /// Dialog title text
  final String title;

  /// Dialog message text
  final String message;

  /// List of action buttons
  final List<DialogAction> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: actions.map((action) {
        if (action.isDestructive) {
          return FilledButton(
            onPressed: action.onPressed,
            child: Text(action.label),
          );
        }
        return TextButton(
          onPressed: action.onPressed,
          child: Text(action.label),
        );
      }).toList(),
    );
  }
}
