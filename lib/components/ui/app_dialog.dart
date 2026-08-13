import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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

/// Shows an app-themed dialog using Forui design system.
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
    // Custom builder: wrap in showFDialog with 3-param signature
    return showFDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context, style, animation) => builder(context),
    );
  }

  if (title == null || message == null || actions == null) {
    throw ArgumentError(
      'Either provide builder or provide title, message, and actions',
    );
  }

  return showFDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context, style, animation) =>
        AppAlertDialog(title: title, message: message, actions: actions),
  );
}

/// Alert dialog widget using Forui design system.
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
    return FDialog(
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions.map((action) {
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FButton(
                  onPress: action.onPressed,
                  variant: action.isDestructive
                      ? FButtonVariant.destructive
                      : FButtonVariant.outline,
                  child: Text(action.label),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
