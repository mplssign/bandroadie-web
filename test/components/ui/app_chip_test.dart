import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_chip.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppChip', () {
    testWidgets('renders default variant with FBadge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: const Scaffold(
              body: AppChip(
                label: 'Test Chip',
                variant: AppChipVariant.defaultChip,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Chip'), findsOneWidget);
      expect(find.byType(FBadge), findsOneWidget);
    });

    testWidgets('renders filter variant with FTappable.static', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Filter Chip',
                variant: AppChipVariant.filter,
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Filter Chip'), findsOneWidget);
      expect(find.byType(FBadge), findsOneWidget);
      expect(find.byType(FTappable), findsOneWidget);
    });

    testWidgets('renders action variant with FTappable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Action Chip',
                variant: AppChipVariant.action,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Action Chip'), findsOneWidget);
      expect(find.byType(FBadge), findsOneWidget);
      expect(find.byType(FTappable), findsOneWidget);
    });

    testWidgets('filter chip reflects selection state via FTappable.static',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Filter Chip',
                variant: AppChipVariant.filter,
                isSelected: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Verify FTappable has selected property set correctly
      final tappable = tester.widget<FTappable>(find.byType(FTappable));
      expect(tappable.selected, isTrue);
    });

    testWidgets('action chip calls onTap callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Action Chip',
                variant: AppChipVariant.action,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FTappable));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('filter chip calls onTap callback on selection', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Filter Chip',
                variant: AppChipVariant.filter,
                isSelected: false,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FTappable));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    // Test 5: Filter variant with selection (from Architect plan)
    testWidgets('filter variant renders with correct selection state',
        (tester) async {
      // Test with selected: true
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Selected Chip',
                variant: AppChipVariant.filter,
                isSelected: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final selectedTappable = tester.widget<FTappable>(find.byType(FTappable));
      expect(selectedTappable.selected, isTrue);

      // Test with selected: false
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Unselected Chip',
                variant: AppChipVariant.filter,
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final unselectedTappable =
          tester.widget<FTappable>(find.byType(FTappable));
      expect(unselectedTappable.selected, isFalse);
    });

    // Test 6: Action variant tap callback (from Architect plan)
    testWidgets('action variant triggers onTap callback', (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Action Chip',
                variant: AppChipVariant.action,
                onTap: () => tapCount++,
              ),
            ),
          ),
        ),
      );

      expect(tapCount, 0);

      await tester.tap(find.byType(FTappable));
      await tester.pumpAndSettle();
      expect(tapCount, 1);

      await tester.tap(find.byType(FTappable));
      await tester.pumpAndSettle();
      expect(tapCount, 2);
    });

    // Test 7: Disabled state (from Architect plan)
    testWidgets('disabled chip does not trigger onTap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: AppChip(
                label: 'Disabled Chip',
                variant: AppChipVariant.action,
                onTap: () => tapped = true,
                enabled: false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FTappable));
      await tester.pumpAndSettle();

      // onTap should not fire when enabled: false
      expect(tapped, isFalse);

      // Verify FTappable's onPress is null when disabled
      final tappable = tester.widget<FTappable>(find.byType(FTappable));
      expect(tappable.onPress, isNull);
    });
  });
}
