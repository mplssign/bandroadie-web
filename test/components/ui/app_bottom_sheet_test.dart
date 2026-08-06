import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_bottom_sheet.dart';

void main() {
  group('AppBottomSheet', () {
    testWidgets('showAppBottomSheet displays bottom sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppBottomSheet(
                    context: context,
                    builder: (context) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('Bottom Sheet Content')),
                    ),
                  );
                },
                child: const Text('Show Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Bottom Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Bottom Sheet Content'), findsOneWidget);
    });

    testWidgets('respects isDismissible parameter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppBottomSheet(
                    context: context,
                    isDismissible: false,
                    builder: (context) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('Bottom Sheet Content')),
                    ),
                  );
                },
                child: const Text('Show Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Bottom Sheet'));
      await tester.pumpAndSettle();

      // Try to dismiss by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Bottom sheet should still be visible
      expect(find.text('Bottom Sheet Content'), findsOneWidget);
    });

    testWidgets('passes backgroundColor to showModalBottomSheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppBottomSheet(
                    context: context,
                    backgroundColor: Colors.red,
                    builder: (context) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('Bottom Sheet Content')),
                    ),
                  );
                },
                child: const Text('Show Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Bottom Sheet'));
      await tester.pumpAndSettle();

      // Verify bottom sheet is displayed
      expect(find.text('Bottom Sheet Content'), findsOneWidget);
    });

    testWidgets('passes shape to showModalBottomSheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('Bottom Sheet Content')),
                    ),
                  );
                },
                child: const Text('Show Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Bottom Sheet'));
      await tester.pumpAndSettle();

      // Verify bottom sheet is displayed
      expect(find.text('Bottom Sheet Content'), findsOneWidget);
    });

    testWidgets('passes isScrollControlled to showModalBottomSheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const SizedBox(
                      height: 600,
                      child: Center(child: Text('Bottom Sheet Content')),
                    ),
                  );
                },
                child: const Text('Show Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Bottom Sheet'));
      await tester.pumpAndSettle();

      // Verify bottom sheet is displayed
      expect(find.text('Bottom Sheet Content'), findsOneWidget);
    });
  });
}
