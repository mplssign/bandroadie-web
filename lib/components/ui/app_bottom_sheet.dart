import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Shows an app-themed modal bottom sheet using Forui design system.
///
/// Use this instead of [showModalBottomSheet] to ensure
/// consistent bottom sheet styling across the app.
///
/// **Note for preview cycle:** The `backgroundColor`, `shape`, `isScrollControlled`,
/// `useSafeArea`, and `barrierColor` props are not supported in Forui preview.
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
  return showFSheet<T>(
    context: context,
    builder: builder,
    side: FLayout.btt, // Bottom-to-top sheet
    barrierDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
  );
}
