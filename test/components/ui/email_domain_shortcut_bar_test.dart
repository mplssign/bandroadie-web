import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';
import 'package:bandroadie/components/ui/app_chip.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:forui/forui.dart';

void main() {
  group('EmailDomainShortcutBar', () {
    // Test 1: Tap-to-apply mode (backward compatibility)
    testWidgets('tap-to-apply mode mutates controller text correctly',
        (tester) async {
      final controller = TextEditingController(text: 'tony');

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: EmailDomainShortcutBar(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Verify chips are rendered
      expect(find.text('@gmail.com'), findsOneWidget);
      expect(find.text('@icloud.com'), findsOneWidget);

      // Tap the first domain chip (@gmail.com)
      await tester.tap(find.text('@gmail.com'));
      await tester.pumpAndSettle();

      // Verify controller text was mutated (appended domain)
      expect(controller.text, 'tony@gmail.com');
      expect(controller.selection.baseOffset, 14); // cursor at end

      // Reset and test with existing @ sign (should replace)
      controller.text = 'tony@yahoo.com';
      await tester.tap(find.text('@icloud.com'));
      await tester.pumpAndSettle();

      expect(controller.text, 'tony@icloud.com');

      // Test with empty input (should do nothing)
      controller.text = '';
      await tester.tap(find.text('@gmail.com'));
      await tester.pumpAndSettle();

      expect(controller.text, ''); // unchanged
    });

    // Test 2: Selection mode
    testWidgets('selection mode renders selected chip and fires callback',
        (tester) async {
      final controller = TextEditingController(text: 'test');
      String? selectedDomain = '@gmail.com';
      String? callbackDomain;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: FTheme(
                data: AppTheme.foruiTheme(Brightness.light),
                child: Scaffold(
                  body: EmailDomainShortcutBar(
                    controller: controller,
                    selectedDomain: selectedDomain,
                    onDomainSelected: (domain) {
                      callbackDomain = domain;
                      setState(() {
                        selectedDomain = domain;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Verify all domain chips are rendered
      expect(find.text('@gmail.com'), findsOneWidget);
      expect(find.text('@icloud.com'), findsOneWidget);

      // Find the selected chip (should be FTappable with selected: true)
      final tappables = tester.widgetList<FTappable>(find.byType(FTappable));
      expect(tappables.length, emailDomainShortcuts.length);

      // First chip should be selected
      final firstTappable = tappables.first;
      expect(firstTappable.selected, isTrue);

      // Tap an unselected chip (@icloud.com)
      await tester.tap(find.text('@icloud.com'));
      await tester.pumpAndSettle();

      // Verify callback was fired with correct domain
      expect(callbackDomain, '@icloud.com');

      // Verify controller text was NOT mutated in selection mode
      expect(controller.text, 'test'); // unchanged
    });

    // Test 3: Enabled/disabled state
    testWidgets('disabled chips do not fire callbacks', (tester) async {
      final controller = TextEditingController(text: 'tony');
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: EmailDomainShortcutBar(
                controller: controller,
                enabled: false,
                selectedDomain: '@gmail.com',
                onDomainSelected: (domain) => tapCount++,
              ),
            ),
          ),
        ),
      );

      // Verify chips are rendered
      expect(find.text('@gmail.com'), findsOneWidget);

      // Tap a chip while disabled
      await tester.tap(find.text('@icloud.com'));
      await tester.pumpAndSettle();

      // Verify callback was NOT fired
      expect(tapCount, 0);

      // Verify all FTappable widgets have null onPress (disabled)
      final tappables = tester.widgetList<FTappable>(find.byType(FTappable));
      for (final tappable in tappables) {
        expect(tappable.onPress, isNull);
      }
    });

    // Test 4: Email mutation logic via applyEmailDomainShortcut
    testWidgets('verifies applyEmailDomainShortcut behavior', (tester) async {
      // Test 1: Empty input
      expect(applyEmailDomainShortcut('', '@gmail.com'), '');

      // Test 2: No @ sign present (append)
      expect(applyEmailDomainShortcut('tony', '@gmail.com'), 'tony@gmail.com');

      // Test 3: @ sign present (replace from @ onward)
      expect(applyEmailDomainShortcut('tony@yahoo.com', '@gmail.com'),
          'tony@gmail.com');

      // Test 4: Plus addressing preserved
      expect(applyEmailDomainShortcut('tony+test', '@gmail.com'),
          'tony+test@gmail.com');
      expect(applyEmailDomainShortcut('tony+test@old.com', '@gmail.com'),
          'tony+test@gmail.com');

      // Test 5: Whitespace trimmed
      expect(
          applyEmailDomainShortcut('  tony  ', '@gmail.com'), 'tony@gmail.com');

      // Test 6: Just @ (edge case)
      expect(applyEmailDomainShortcut('@', '@gmail.com'), '@gmail.com');

      // Test 7: Multiple @ signs (replace from first @)
      expect(applyEmailDomainShortcut('tony@test@old.com', '@gmail.com'),
          'tony@gmail.com');
    });

    // Additional test: Verify all 5 domain shortcuts are rendered
    testWidgets('renders all 5 email domain shortcuts', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: EmailDomainShortcutBar(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Verify all 5 domains from emailDomainShortcuts constant
      expect(find.text('@gmail.com'), findsOneWidget);
      expect(find.text('@icloud.com'), findsOneWidget);
      expect(find.text('@yahoo.com'), findsOneWidget);
      expect(find.text('@hotmail.com'), findsOneWidget);
      expect(find.text('@outlook.com'), findsOneWidget);

      // Verify correct number of chips
      expect(find.byType(AppChip), findsNWidgets(5));
    });

    // Additional test: SingleChildScrollView horizontal scroll
    testWidgets('wraps chips in horizontal SingleChildScrollView',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.light),
            child: Scaffold(
              body: EmailDomainShortcutBar(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Verify SingleChildScrollView with horizontal axis
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.scrollDirection, Axis.horizontal);
    });
  });
}
