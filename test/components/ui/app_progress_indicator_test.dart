import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';

void main() {
  group('AppProgressIndicator', () {
    testWidgets('renders circular type as CircularProgressIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.circular),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders linear type as LinearProgressIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.linear),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('circular defaults to indeterminate progress', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.circular),
          ),
        ),
      );

      final progressIndicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progressIndicator.value, isNull);
    });

    testWidgets('supports determinate progress with value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.circular,
              value: 0.5,
            ),
          ),
        ),
      );

      final progressIndicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progressIndicator.value, 0.5);
    });

    testWidgets('respects color override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.circular,
              color: Colors.green,
            ),
          ),
        ),
      );

      final progressIndicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progressIndicator.color, Colors.green);
    });

    testWidgets('linear supports determinate progress', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.linear,
              value: 0.75,
            ),
          ),
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, 0.75);
    });
  });
}
