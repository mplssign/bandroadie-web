import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppButton', () {
    testWidgets('renders primary variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.primary);
      expect(button.onPress, isNotNull);
    });

    testWidgets('renders secondary variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.secondary,
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.secondary);
    });

    testWidgets('renders text variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.text,
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.ghost);
    });

    testWidgets('renders outlined variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.outlined,
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.outline);
    });

    testWidgets('shows loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              isLoading: true,
            ),
          ),
        ),
      );

      // Loading state shows CircularProgressIndicator, label hidden
      expect(find.text('Test Button'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              icon: Icons.add,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('expands to full width when fullWidth is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              fullWidth: true,
            ),
          ),
        ),
      );

      // fullWidth wraps in SizedBox(width: double.infinity)
      expect(find.text('Test Button'), findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(sizedBox.width, double.infinity);
    });

    testWidgets('disables button when onPressed is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(
            body: AppButton(label: 'Test Button', onPressed: null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.onPress, isNull);
    });

    testWidgets('renders destructive variant with error styling',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Delete',
              onPressed: () {},
              variant: AppButtonVariant.destructive,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.destructive);
      expect(button.onPress, isNotNull);
    });

    testWidgets('renders destructive variant with icon correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Delete',
              onPressed: () {},
              icon: Icons.delete,
              variant: AppButtonVariant.destructive,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('backgroundColor applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              backgroundColor: Colors.red,
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);
      final button = tester.widget<FButton>(find.byType(FButton));
      // Verify style is a delta (proving backgroundColor was applied)
      expect(button.style, isA<FButtonStyleDelta>());
    });

    testWidgets('borderRadius applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);
      final button = tester.widget<FButton>(find.byType(FButton));
      // Verify style is a delta (proving borderRadius was applied)
      expect(button.style, isA<FButtonStyleDelta>());
    });

    testWidgets('padding applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              padding: const EdgeInsets.all(24),
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);
      final button = tester.widget<FButton>(find.byType(FButton));
      // Verify style is a delta (proving padding was applied)
      expect(button.style, isA<FButtonStyleDelta>());
    });

    testWidgets('respects custom height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.primary,
              height: 52,
            ),
          ),
        ),
      );

      expect(find.byType(FButton), findsOneWidget);

      // Find the SizedBox that wraps for height
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));

      // Should find a SizedBox with height: 52
      final heightBox = sizedBoxes.firstWhere(
        (box) => box.height == 52,
        orElse: () => throw Exception('No SizedBox with height 52 found'),
      );

      expect(heightBox.height, 52);
    });
  });
}
