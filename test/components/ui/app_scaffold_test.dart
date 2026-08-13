import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppScaffold', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const AppScaffold(body: Text('Test Body')),
        ),
      );

      expect(find.text('Test Body'), findsOneWidget);
      expect(find.byType(FScaffold), findsOneWidget);
    });

    testWidgets('delegates appBar prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: AppScaffold(
            appBar: AppBar(title: const Text('Test AppBar')),
            body: const Text('Test Body'),
          ),
        ),
      );

      expect(find.text('Test AppBar'), findsOneWidget);
      expect(find.byType(FScaffold), findsOneWidget);
    });

    testWidgets('floatingActionButton prop is not supported in Forui preview',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: AppScaffold(
            body: const Text('Test Body'),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      // Note: floatingActionButton is ignored (not supported by FScaffold)
      // Just verify the scaffold body renders
      expect(find.text('Test Body'), findsOneWidget);
    });

    testWidgets('backgroundColor prop is ignored in Forui preview',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const AppScaffold(
            body: Text('Test Body'),
            backgroundColor: Colors.blue,
          ),
        ),
      );

      // Note: backgroundColor is ignored in Forui preview (dropped prop)
      expect(find.text('Test Body'), findsOneWidget);
      expect(find.byType(FScaffold), findsOneWidget);
    });

    testWidgets('delegates resizeToAvoidBottomInset prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const AppScaffold(
            body: Text('Test Body'),
            resizeToAvoidBottomInset: false,
          ),
        ),
      );

      expect(find.byType(FScaffold), findsOneWidget);

      final scaffold = tester.widget<FScaffold>(find.byType(FScaffold));
      expect(scaffold.resizeToAvoidBottomInset, isFalse);
    });
  });
}
