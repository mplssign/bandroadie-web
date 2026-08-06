import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';

void main() {
  group('AppTextField', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(hintText: 'Test Hint')),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays hint text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(hintText: 'Enter text here')),
        ),
      );

      expect(find.text('Enter text here'), findsOneWidget);
    });

    testWidgets('displays label text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(labelText: 'Username')),
        ),
      );

      expect(find.text('Username'), findsOneWidget);
    });

    testWidgets('displays prefix icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(prefixIcon: Icons.person)),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('obscures text when obscureText is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(obscureText: true)),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);
    });

    testWidgets('calls onChanged callback', (tester) async {
      String? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextField(onChanged: (value) => changedValue = value),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test');
      expect(changedValue, 'test');
    });

    testWidgets('respects enabled property', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppTextField(enabled: false))),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('delegates focusNode to TextField', (tester) async {
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppTextField(focusNode: focusNode)),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode, focusNode);

      focusNode.dispose();
    });

    testWidgets('delegates textCapitalization to TextField', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(textCapitalization: TextCapitalization.words),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textCapitalization, TextCapitalization.words);
    });

    testWidgets('delegates textInputAction to TextField', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(textInputAction: TextInputAction.next),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textInputAction, TextInputAction.next);
    });

    testWidgets('delegates style to TextField', (tester) async {
      const customStyle = TextStyle(fontSize: 20, color: Colors.red);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(style: customStyle)),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.style, customStyle);
    });

    testWidgets('uses full decoration when provided', (tester) async {
      const customDecoration = InputDecoration(
        filled: true,
        fillColor: Colors.blue,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(16),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(decoration: customDecoration)),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration, customDecoration);
    });

    testWidgets('decoration overrides simplified props when provided', (
      tester,
    ) async {
      const customDecoration = InputDecoration(
        filled: true,
        fillColor: Colors.blue,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(
              decoration: customDecoration,
              hintText: 'Ignored hint',
              labelText: 'Ignored label',
              prefixIcon: Icons.person,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration, customDecoration);
      // Verify simplified props are not in the decoration
      expect(find.text('Ignored hint'), findsNothing);
      expect(find.text('Ignored label'), findsNothing);
      expect(find.byIcon(Icons.person), findsNothing);
    });
  });
}
