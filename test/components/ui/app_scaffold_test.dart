import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';

void main() {
  group('AppScaffold', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppScaffold(body: Text('Test Body'))),
      );

      expect(find.text('Test Body'), findsOneWidget);
    });

    testWidgets('delegates appBar prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar: AppBar(title: const Text('Test AppBar')),
            body: const Text('Test Body'),
          ),
        ),
      );

      expect(find.text('Test AppBar'), findsOneWidget);
    });

    testWidgets('delegates floatingActionButton prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            body: const Text('Test Body'),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('respects backgroundColor override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppScaffold(
            body: Text('Test Body'),
            backgroundColor: Colors.blue,
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.blue);
    });
  });
}
