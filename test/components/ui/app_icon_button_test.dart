import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppIconButton', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppIconButton(icon: Icons.add, onPressed: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);
    });

    testWidgets('responds to tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppIconButton(
              icon: Icons.add,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppIconButton));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('color prop is ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppIconButton(
              icon: Icons.add,
              onPressed: () {},
              color: Colors.red,
            ),
          ),
        ),
      );

      // Note: color is ignored in Forui preview (dropped prop)
      expect(find.byType(FButton), findsOneWidget);
    });

    testWidgets('size prop is ignored in Forui preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppIconButton(icon: Icons.add, onPressed: () {}, size: 32.0),
          ),
        ),
      );

      // Note: size is ignored in Forui preview (dropped prop)
      expect(find.byType(FButton), findsOneWidget);
    });

    testWidgets('disables when onPressed is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
              body: AppIconButton(icon: Icons.add, onPressed: null)),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.onPress, isNull);
    });
  });
}
