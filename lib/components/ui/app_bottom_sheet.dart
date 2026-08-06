import 'package:flutter/material.dart';

/// Shows an app-themed modal bottom sheet.
///
/// Use this instead of [showModalBottomSheet] to ensure
/// consistent bottom sheet styling across the app.
///
/// Returns the result passed to [Navigator.pop] when the bottom sheet is dismissed.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
  );
}
