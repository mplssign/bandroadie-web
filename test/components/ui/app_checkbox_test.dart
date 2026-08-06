import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_checkbox.dart';

void main() {
  group('AppCheckbox', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppCheckbox(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('reflects value state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppCheckbox(value: true, onChanged: (_) {})),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('supports indeterminate state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppCheckbox(value: null, onChanged: (_) {})),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isNull);
    });

    testWidgets('calls onChanged callback', (tester) async {
      bool? value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppCheckbox(
                value: value,
                onChanged: (newValue) {
                  setState(() => value = newValue);
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    testWidgets('respects activeColor override', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCheckbox(
              value: true,
              onChanged: (_) {},
              activeColor: Colors.green,
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.activeColor, Colors.green);
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppCheckbox(value: false, onChanged: null)),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNull);
    });
  });
}
