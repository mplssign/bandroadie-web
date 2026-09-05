import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Ensures Cupertino/Material localizations are available when building the
/// adaptive text selection toolbar.
Widget buildLocalizedAdaptiveTextSelectionToolbar(
  BuildContext context,
  EditableTextState state,
) {
  return Localizations(
    locale: Localizations.localeOf(context),
    delegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    child: AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
  );
}
