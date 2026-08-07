import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_button.dart';

void main() {
  group('AppButton', () {
    testWidgets('renders primary variant as FilledButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('renders secondary variant as ElevatedButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.secondary,
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('renders text variant as TextButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.text,
            ),
          ),
        ),
      );

      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('renders outlined variant as OutlinedButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              variant: AppButtonVariant.outlined,
            ),
          ),
        ),
      );

      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('shows loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Test Button'), findsNothing);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
          home: Scaffold(
            body: AppButton(
              label: 'Test Button',
              onPressed: () {},
              fullWidth: true,
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(sizedBox.width, double.infinity);
    });

    testWidgets('disables button when onPressed is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppButton(label: 'Test Button', onPressed: null),
          ),
        ),
      );

      final filledButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(filledButton.onPressed, isNull);
    });

    testWidgets(
        'renders destructive variant as FilledButton with error styling',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Delete',
              onPressed: () {},
              variant: AppButtonVariant.destructive,
            ),
          ),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      final filledButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(filledButton.style, isNotNull);
    });

    testWidgets('renders destructive variant with icon correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
