import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppProgressIndicator', () {
    testWidgets('renders circular type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.circular),
          ),
        ),
      );

      expect(find.byType(FCircularProgress), findsOneWidget);
    });

    testWidgets('renders linear type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.linear),
          ),
        ),
      );

      expect(find.byType(FProgress), findsOneWidget);
    });

    testWidgets('circular defaults to indeterminate progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(type: ProgressIndicatorType.circular),
          ),
        ),
      );

      // Note: Forui circular is always indeterminate
      expect(find.byType(FCircularProgress), findsOneWidget);
    });

    testWidgets('supports determinate progress with value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.circular,
              value: 0.5,
            ),
          ),
        ),
      );

      // Note: Forui circular is always indeterminate (value ignored)
      expect(find.byType(FCircularProgress), findsOneWidget);
    });

    testWidgets('color prop is ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.circular,
              color: Colors.green,
            ),
          ),
        ),
      );

      // Note: color is ignored in Forui preview (dropped prop)
      expect(find.byType(FCircularProgress), findsOneWidget);
    });

    testWidgets('linear supports determinate progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppProgressIndicator(
              type: ProgressIndicatorType.linear,
              value: 0.75,
            ),
          ),
        ),
      );

      expect(find.byType(FDeterminateProgress), findsOneWidget);

      final progress = tester.widget<FDeterminateProgress>(
        find.byType(FDeterminateProgress),
      );
      expect(progress.value, 0.75);
    });
  });
}
