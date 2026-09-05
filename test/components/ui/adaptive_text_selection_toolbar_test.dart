import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/adaptive_text_selection_toolbar.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_text_form_field.dart';
import 'package:forui/forui.dart';

void main() {
  group('localized adaptive text selection toolbar', () {
    testWidgets('AppTextField uses the shared context menu builder',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField()),
        ),
      );

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(
        textField.contextMenuBuilder,
        buildLocalizedAdaptiveTextSelectionToolbar,
      );
    });

    testWidgets('AppTextFormField uses the shared context menu builder',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextFormField()),
        ),
      );

      final formField =
          tester.widget<FTextFormField>(find.byType(FTextFormField));
      expect(
        formField.contextMenuBuilder,
        buildLocalizedAdaptiveTextSelectionToolbar,
      );
    });

    testWidgets(
        'builds the toolbar on iOS without app-level Cupertino localizations',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final controller = TextEditingController(text: 'hello roadie');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          // Deliberately omits GlobalCupertinoLocalizations, mirroring the
          // app's delegates, to reproduce the original crash conditions.
          home: Scaffold(
            body: TextField(
              controller: controller,
              contextMenuBuilder: buildLocalizedAdaptiveTextSelectionToolbar,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      final state = tester.state<EditableTextState>(find.byType(EditableText));
      state.userUpdateTextEditingValue(
        controller.value.copyWith(
          selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        ),
        SelectionChangedCause.tap,
      );
      await tester.pump();

      state.showToolbar();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });
}
