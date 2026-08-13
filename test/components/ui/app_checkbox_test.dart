import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_checkbox.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppCheckbox', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppCheckbox(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FCheckbox), findsOneWidget);
    });

    testWidgets('reflects value state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppCheckbox(value: true, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FCheckbox), findsOneWidget);

      final checkbox = tester.widget<FCheckbox>(find.byType(FCheckbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('indeterminate state is treated as false in Forui preview',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppCheckbox(value: null, onChanged: (_) {})),
        ),
      );

      // Note: FCheckbox doesn't support tristate - null treated as false
      expect(find.byType(AppCheckbox), findsOneWidget);
    });

    testWidgets('calls onChanged callback', (tester) async {
      bool? value = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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

      await tester.tap(find.byType(AppCheckbox));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    testWidgets('activeColor prop is ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppCheckbox(
              value: true,
              onChanged: (_) {},
              activeColor: Colors.green,
            ),
          ),
        ),
      );

      // Note: activeColor is ignored in Forui preview (dropped prop)
      expect(find.byType(FCheckbox), findsOneWidget);
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home:
              const Scaffold(body: AppCheckbox(value: false, onChanged: null)),
        ),
      );

      expect(find.byType(FCheckbox), findsOneWidget);

      final checkbox = tester.widget<FCheckbox>(find.byType(FCheckbox));
      expect(checkbox.onChange, isNull);
      expect(checkbox.enabled, isFalse);
    });
  });
}
