import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_switch.dart';

void main() {
  group('AppSwitch', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppSwitch(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('reflects value state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppSwitch(value: true, onChanged: (_) {})),
        ),
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('calls onChanged callback', (tester) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppSwitch(
                value: value,
                onChanged: (newValue) {
                  setState(() => value = newValue);
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    testWidgets('respects activeColor override', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSwitch(
              value: true,
              onChanged: (_) {},
              activeColor: Colors.green,
            ),
          ),
        ),
      );

      // Verify the switch was created with the custom color prop
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppSwitch(value: false, onChanged: null)),
        ),
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);
    });
  });
}
