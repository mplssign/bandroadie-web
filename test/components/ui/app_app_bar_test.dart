import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';

void main() {
  group('AppAppBar', () {
    testWidgets('renders with String title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar: const AppAppBar(title: 'Test Title'),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('renders with Widget title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar: const AppAppBar(title: Text('Widget Title')),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.text('Widget Title'), findsOneWidget);
    });

    testWidgets('delegates leading prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar: AppAppBar(
              title: 'Test',
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {},
              ),
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('delegates actions prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar: AppAppBar(
              title: 'Test',
              actions: [
                IconButton(icon: const Icon(Icons.search), onPressed: () {}),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('backgroundColor prop is ignored in Forui preview',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            appBar:
                const AppAppBar(title: 'Test', backgroundColor: Colors.blue),
            body: const SizedBox(),
          ),
        ),
      );

      // Note: backgroundColor is ignored in Forui preview, so we can't verify it
      // Just verify the app bar renders
      expect(find.text('Test'), findsOneWidget);
    });
  });
}
