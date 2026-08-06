import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';

void main() {
  group('AppAppBar', () {
    testWidgets('renders with String title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: AppAppBar(title: 'Test Title')),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('renders with Widget title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: AppAppBar(title: Text('Widget Title'))),
        ),
      );

      expect(find.text('Widget Title'), findsOneWidget);
    });

    testWidgets('delegates leading prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppAppBar(
              title: 'Test',
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('delegates actions prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppAppBar(
              title: 'Test',
              actions: [
                IconButton(icon: const Icon(Icons.search), onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('respects backgroundColor override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: AppAppBar(title: 'Test', backgroundColor: Colors.blue),
          ),
        ),
      );

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.blue);
    });
  });
}
