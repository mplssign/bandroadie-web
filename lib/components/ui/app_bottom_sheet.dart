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
/// The [mainAxisMaxRatio] parameter controls the maximum height of the sheet as a
/// fraction of the screen height. Defaults to Forui's default (9/16, or ~56%).
/// Pass a higher value (e.g., 0.95 or 1.0) for taller sheets.
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
  double? mainAxisMaxRatio,
}) {
  return showFSheet<T>(
    context: context,
    builder: (context) => Material(
      color: Colors.transparent,
      child: builder(context),
    ),
    side: FLayout.btt, // Bottom-to-top sheet
    barrierDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
    mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16),
    useSafeArea: useSafeArea,
  );
}
