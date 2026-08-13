import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppSwitch', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
    });

    testWidgets('reflects value state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: true, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);

      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('calls onChanged callback', (tester) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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

      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    testWidgets('activeColor applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppSwitch(
              value: true,
              onChanged: (_) {},
              activeColor: Colors.green,
            ),
          ),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      // Verify style is a delta (proving activeColor was applied)
      expect(switchWidget.style, isA<FSwitchStyleDelta>());
    });

    testWidgets('activeTrackColor applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppSwitch(
              value: true,
              onChanged: (_) {},
              activeTrackColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      // Verify style is a delta (proving activeTrackColor was applied)
      expect(switchWidget.style, isA<FSwitchStyleDelta>());
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppSwitch(value: false, onChanged: null)),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);

      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      expect(switchWidget.onChange, isNull);
      expect(switchWidget.enabled, isFalse);
    });
  });
}
