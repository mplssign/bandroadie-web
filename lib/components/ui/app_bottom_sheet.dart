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
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
    backgroundColor: backgroundColor,
    shape: shape,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    barrierColor: barrierColor,
  );
}
