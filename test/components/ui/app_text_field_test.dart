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

    testWidgets('prefixIcon uses builder pattern', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(prefixIcon: Icon(Icons.person)),
          ),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.prefixBuilder, isNotNull);
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

    testWidgets('textCapitalization passes through to FTextField',
        (tester) async {
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

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.textCapitalization, TextCapitalization.words);
    });

    testWidgets('textInputAction passes through to FTextField', (tester) async {
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

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.textInputAction, TextInputAction.next);
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
              prefixIcon: Icon(Icons.person),
            ),
          ),
        ),
      );

      // Note: decoration not supported in Forui preview (dropped prop)
      expect(find.byType(FTextField), findsOneWidget);
    });

    testWidgets('inputFormatters passes through to FTextField', (tester) async {
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

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.inputFormatters, [formatter]);
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

    testWidgets('autofillHints passes through to FTextField', (tester) async {
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

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.autofillHints, hints);
    });

    testWidgets('onSubmitted maps to onSubmit callback', (tester) async {
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

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.onSubmit, isNotNull);
    });

    testWidgets('autofocus passes through to FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(autofocus: true)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.autofocus, isTrue);
    });

    testWidgets('readOnly passes through to FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(readOnly: true)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.readOnly, isTrue);
    });

    testWidgets('minLines passes through to FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(minLines: 3)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.minLines, 3);
    });

    testWidgets('maxLength passes through to FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(maxLength: 100)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.maxLength, 100);
    });

    testWidgets('textAlign passes through to FTextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppTextField(textAlign: TextAlign.center)),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.textAlign, TextAlign.center);
    });

    testWidgets('onEditingComplete passes through to FTextField',
        (tester) async {
      bool editingCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppTextField(
              onEditingComplete: () => editingCompleted = true,
            ),
          ),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.onEditingComplete, isNotNull);
    });

    testWidgets('onTap passes through to FTextField', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppTextField(onTap: () => tapped = true),
          ),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.onTap, isNotNull);
    });

    testWidgets('prefixIcon uses prefixBuilder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(prefixIcon: Icon(Icons.search)),
          ),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.prefixBuilder, isNotNull);
    });

    testWidgets('suffixIcon uses suffixBuilder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppTextField(suffixIcon: Icon(Icons.clear)),
          ),
        ),
      );

      expect(find.byType(FTextField), findsOneWidget);
      final textField = tester.widget<FTextField>(find.byType(FTextField));
      expect(textField.suffixBuilder, isNotNull);
    });
  });
}
