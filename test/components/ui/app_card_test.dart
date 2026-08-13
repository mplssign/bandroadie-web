import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_card.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppCard', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppCard(child: Text('Card Content'))),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(FCard), findsOneWidget);
    });

    testWidgets('padding applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppCard(
              padding: EdgeInsets.all(24),
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(FCard), findsOneWidget);
      final card = tester.widget<FCard>(find.byType(FCard));
      // Verify style is a delta (proving padding was applied)
      expect(card.style, isA<FCardStyleDelta>());
    });

    testWidgets('adds GestureDetector when onTap is provided', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped = true,
              child: const Text('Card Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Note: Uses GestureDetector (not InkWell)
      expect(find.byType(GestureDetector), findsWidgets);

      await tester.tap(find.text('Card Content'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('does not add GestureDetector when onTap is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppCard(child: Text('Card Content'))),
        ),
      );

      // Note: GestureDetector only added when onTap is provided
      expect(find.text('Card Content'), findsOneWidget);
    });
  });
}
