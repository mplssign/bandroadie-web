import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/sheet_footer.dart';
import 'package:forui/forui.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (context, c) => FTheme(data: FTheme.neutral.dark.touch, child: c!),
    home: Scaffold(body: child),
  );
}

void main() {
  group('SheetFooter', () {
    testWidgets('primary renders right-aligned with primary variant', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
          ),
        ),
      );

      final buttons = tester.widgetList<AppButton>(find.byType(AppButton));
      final list = buttons.toList();
      // Two buttons: cancel on the left (index 0), primary on the right (index 1)
      expect(list.length, 2);
      expect(list[0].variant, AppButtonVariant.text);
      expect(list[1].variant, AppButtonVariant.primary);
    });

    testWidgets('cancel renders left with text variant', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
          ),
        ),
      );

      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      expect(buttons[0].variant, AppButtonVariant.text);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel is hidden when onCancel is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Done',
            onPrimary: () {},
          ),
        ),
      );

      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      expect(buttons.length, 1);
      expect(buttons[0].variant, AppButtonVariant.primary);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets(
        'destructive renders above the row when label+callback supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
            destructiveLabel: 'Delete',
            onDestructive: () {},
          ),
        ),
      );

      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      // 3 buttons: destructive, cancel, primary
      expect(buttons.length, 3);
      expect(buttons[0].variant, AppButtonVariant.destructive);
      expect(buttons[1].variant, AppButtonVariant.text);
      expect(buttons[2].variant, AppButtonVariant.primary);

      // Destructive is inside a Column above the Row
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('destructive is absent when only label supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
            destructiveLabel: 'Delete',
            // onDestructive intentionally omitted
          ),
        ),
      );

      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      expect(buttons.length, 2);
      expect(buttons.any((b) => b.variant == AppButtonVariant.destructive),
          isFalse);
    });

    testWidgets('destructive is absent when only callback supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
            // destructiveLabel intentionally omitted
            onDestructive: () {},
          ),
        ),
      );

      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      expect(buttons.length, 2);
      expect(buttons.any((b) => b.variant == AppButtonVariant.destructive),
          isFalse);
    });

    testWidgets(
        'primaryIsLoading shows spinner and disables primary and cancel', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
            primaryIsLoading: true,
          ),
        ),
      );

      // The primary AppButton is in loading mode (spinner shown, label hidden)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);

      // Both buttons' onPressed should be null (disabled)
      final fButtons =
          tester.widgetList<FButton>(find.byType(FButton)).toList();
      for (final btn in fButtons) {
        expect(btn.onPress, isNull);
      }
    });

    testWidgets('onPrimary null renders primary as disabled', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SheetFooter(
            primaryLabel: 'Save',
            onPrimary: null,
          ),
        ),
      );

      final fButtons =
          tester.widgetList<FButton>(find.byType(FButton)).toList();
      expect(fButtons.length, 1);
      expect(fButtons[0].onPress, isNull);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('tapping primary invokes callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('tapping cancel invokes callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('tapping destructive invokes callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
            destructiveLabel: 'Delete',
            onDestructive: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('custom cancelLabel renders on the left button',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            cancelLabel: 'Edit',
            onCancel: () {},
          ),
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
      final buttons =
          tester.widgetList<AppButton>(find.byType(AppButton)).toList();
      expect(buttons[0].label, 'Edit');
      expect(buttons[0].variant, AppButtonVariant.text);
    });

    testWidgets('primaryIcon renders icon on primary button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Edit Entry',
            onPrimary: () {},
            primaryIcon: Icons.edit,
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      final button = tester.widgetList<AppButton>(find.byType(AppButton)).first;
      expect(button.icon, Icons.edit);
    });

    testWidgets('both actions → each button is wrapped in an Expanded',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
          ),
        ),
      );

      final expandeds =
          tester.widgetList<Expanded>(find.byType(Expanded)).toList();
      expect(expandeds.length, 2);
      expect(expandeds[0].child, isA<AppButton>());
      expect(expandeds[1].child, isA<AppButton>());
    });

    testWidgets(
        'both actions → inter-button gap is SizedBox(width: Spacing.space12)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SheetFooter(
            primaryLabel: 'Save',
            onPrimary: () {},
            onCancel: () {},
          ),
        ),
      );

      final sizeBoxes =
          tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
      final gap = sizeBoxes.firstWhere(
        (s) => s.width == Spacing.space12 && s.height == null,
        orElse: () => throw TestFailure('No SizedBox gap found'),
      );
      expect(gap.width, Spacing.space12);
    });

    testWidgets('lone primary (onCancel null) → fullWidth true, no Expanded',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SheetFooter(
            primaryLabel: 'Done',
            onPrimary: null,
          ),
        ),
      );

      expect(find.byType(Expanded), findsNothing);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.fullWidth, isTrue);
    });
  });
}
