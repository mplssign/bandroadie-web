import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Locale used when no ambient [Localizations] scope provides one. The app
/// only ships English strings (`MaterialApp.supportedLocales` is `en`).
const Locale _fallbackLocale = Locale('en');

/// Builds the platform-adaptive text selection toolbar inside its own
/// [Localizations] scope.
///
/// On iOS/macOS the adaptive toolbar renders Cupertino widgets, which throw
/// `No CupertinoLocalizations found` when the surrounding app does not provide
/// [GlobalCupertinoLocalizations]. Wrapping the toolbar in a local
/// [Localizations] scope guarantees the Material, Widgets and Cupertino
/// delegates are always available without changing the app-level delegates.
///
/// When no ambient locale is available, [_fallbackLocale] is used.
Widget buildLocalizedAdaptiveTextSelectionToolbar(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return Localizations(
    locale: Localizations.maybeLocaleOf(context) ?? _fallbackLocale,
    delegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    child: AdaptiveTextSelectionToolbar.editableText(
      editableTextState: editableTextState,
    ),
  );
}
