import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Shows an app-themed date picker dialog using Forui's FCalendar.grid.
///
/// Drop-in replacement for Material's [showDatePicker] with the same
/// parameter signature.
///
/// Returns the selected [DateTime] (normalized to midnight UTC), or null
/// if the user cancels or dismisses the dialog.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  return showFDialog<DateTime?>(
    context: context,
    barrierDismissible: true,
    builder: (context, style, animation) => FDialog(
      style: const FDialogStyleDelta.delta(
        insetPadding: EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      builder: (context, dialogStyle) => FCalendar.grid(
        control: FGridCalendarControl(
          start: firstDate,
          end: lastDate,
          initial: initialDate,
        ),
        selectionControl: FDateSelectionControl.managedSingle(
          initial: initialDate,
          toggleable: false,
          onChange: (date) => Navigator.of(context).pop(date),
        ),
        fixedWeeks: false,
        headerBuilder: (context, controller, selectionController, header) =>
            LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: viewport.maxWidth),
              child: IntrinsicWidth(child: header),
            ),
          ),
        ),
      ),
    ),
  );
}
