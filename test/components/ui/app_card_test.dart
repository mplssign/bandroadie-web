import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_card.dart';

void main() {
  group('AppCard', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppCard(child: Text('Card Content'))),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('applies padding when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(
              padding: EdgeInsets.all(24),
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      // Verify padding was applied (find our custom Padding widget)
      final paddingWidgets = tester.widgetList<Padding>(find.byType(Padding));
      expect(
        paddingWidgets.any((p) => p.padding == const EdgeInsets.all(24)),
        isTrue,
      );
    });

    testWidgets('adds InkWell when onTap is provided', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped = true,
              child: const Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('does not add InkWell when onTap is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppCard(child: Text('Card Content'))),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
    });
  });
}
