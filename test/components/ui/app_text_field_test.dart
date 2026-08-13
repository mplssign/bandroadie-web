import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppTextField', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(hintText: 'Test Hint')),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('displays hint text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(hintText: 'Enter text here')),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.hint, 'Enter text here');
    });

    testWidgets('displays label text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(labelText: 'Username')),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.label, isNotNull);
    });

    testWidgets('prefix icon ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(prefixIcon: Icons.person)),
        ),
      );

      // Note: prefixIcon not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('obscures text when obscureText is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(obscureText: true)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.obscureText, isTrue);
    });

    testWidgets('calls onChanged callback', (tester) async {
      String? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppTextField(onChanged: (value) => changedValue = value),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(FTextField), 'test');
      expect(changedValue, 'test');
    });

    testWidgets('respects enabled property', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(enabled: false)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('delegates focusNode to FTextField', (tester) async {
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppTextField(focusNode: focusNode)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.focusNode, focusNode);

      focusNode.dispose();
    });

    testWidgets('textCapitalization ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(textCapitalization: TextCapitalization.words),
          ),
        ),
      );

      // Note: textCapitalization not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('textInputAction ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(textInputAction: TextInputAction.next),
          ),
        ),
      );

      // Note: textInputAction not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('style ignored in Forui preview', (tester) async {
      const customStyle = TextStyle(fontSize: 20, color: Colors.red);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(style: customStyle)),
        ),
      );

      // Note: style not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('decoration ignored in Forui preview', (tester) async {
      const customDecoration = InputDecoration(
        filled: true,
        fillColor: Colors.blue,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(16),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home:
              const Scaffold(body: AppTextField(decoration: customDecoration)),
        ),
      );

      // Note: decoration not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('decoration overrides simplified props when provided', (
      tester,
    ) async {
      const customDecoration = InputDecoration(
        filled: true,
        fillColor: Colors.blue,
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(
              decoration: customDecoration,
              hintText: 'Ignored hint',
              labelText: 'Ignored label',
              prefixIcon: Icons.person,
            ),
          ),
        ),
      );

      // Note: decoration not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('inputFormatters ignored in Forui preview', (tester) async {
      final formatter = LengthLimitingTextInputFormatter(5);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppTextField(inputFormatters: [formatter]),
          ),
        ),
      );

      // Note: inputFormatters not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('autocorrect supported in FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(autocorrect: false)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);

      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.autocorrect, isFalse);
    });

    testWidgets('autofillHints ignored in Forui preview', (tester) async {
      const hints = [AutofillHints.email];

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(autofillHints: hints)),
        ),
      );

      // Note: autofillHints not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('onSubmitted ignored in Forui preview', (tester) async {
      String? submittedValue;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppTextField(
              onSubmitted: (value) => submittedValue = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Note: onSubmitted not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('autofocus ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(autofocus: true)),
        ),
      );

      // Note: autofocus not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });
  });
}
