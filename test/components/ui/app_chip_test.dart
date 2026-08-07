import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_chip.dart';

void main() {
  group('AppChip', () {
    testWidgets('renders default variant as Chip', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Test Chip',
              variant: AppChipVariant.defaultChip,
            ),
          ),
        ),
      );

      expect(find.text('Test Chip'), findsOneWidget);
      expect(find.byType(Chip), findsOneWidget);
    });

    testWidgets('renders filter variant as FilterChip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Filter Chip',
              variant: AppChipVariant.filter,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Filter Chip'), findsOneWidget);
      expect(find.byType(FilterChip), findsOneWidget);
    });

    testWidgets('renders action variant as ActionChip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Action Chip',
              variant: AppChipVariant.action,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Action Chip'), findsOneWidget);
      expect(find.byType(ActionChip), findsOneWidget);
    });

    testWidgets('filter chip reflects selection state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Filter Chip',
              variant: AppChipVariant.filter,
              isSelected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final filterChip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(filterChip.selected, isTrue);
    });

    testWidgets('action chip calls onTap callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Action Chip',
              variant: AppChipVariant.action,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ActionChip));
      expect(tapped, isTrue);
    });

    testWidgets('filter chip calls onTap callback on selection', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChip(
              label: 'Filter Chip',
              variant: AppChipVariant.filter,
              isSelected: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FilterChip));
      expect(tapped, isTrue);
    });
  });
}
