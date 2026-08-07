import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_dropdown.dart';

void main() {
  group('AppDropdown', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdown<String>(
              value: 'Option 1',
              items: const [
                DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('Option 1'), findsOneWidget);
    });

    testWidgets('displays hint when value is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdown<String>(
              value: null,
              items: const [
                DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
              ],
              onChanged: (_) {},
              hint: const Text('Select an option'),
            ),
          ),
        ),
      );

      expect(find.text('Select an option'), findsOneWidget);
    });

    testWidgets('calls onChanged callback', (tester) async {
      String? value = 'Option 1';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppDropdown<String>(
                value: value,
                items: const [
                  DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                  DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
                ],
                onChanged: (newValue) {
                  setState(() => value = newValue);
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Option 2').last);
      await tester.pumpAndSettle();

      expect(value, 'Option 2');
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppDropdown<String>(
              value: 'Option 1',
              items: [
                DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
              ],
              onChanged: null,
            ),
          ),
        ),
      );

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.onChanged, isNull);
    });
  });
}
