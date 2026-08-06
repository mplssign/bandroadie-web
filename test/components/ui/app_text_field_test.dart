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
  });
}
