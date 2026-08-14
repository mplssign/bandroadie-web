import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_dropdown.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppDropdown', () {
    testWidgets('renders with custom format function', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: AppDropdown<int>(
                value: 1,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('One')),
                  DropdownMenuItem(value: 2, child: Text('Two')),
                  DropdownMenuItem(value: 3, child: Text('Three')),
                ],
                format: (value) => 'Custom: $value',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdown<int>), findsOneWidget);
      expect(find.text('Custom: 1'), findsOneWidget);
    });

    testWidgets('renders with labelBuilder alias', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: AppDropdown<int>(
                value: 2,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('One')),
                  DropdownMenuItem(value: 2, child: Text('Two')),
                  DropdownMenuItem(value: 3, child: Text('Three')),
                ],
                labelBuilder: (value) => 'Label: $value',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdown<int>), findsOneWidget);
      expect(find.text('Label: 2'), findsOneWidget);
    });

    testWidgets('respects enabled/disabled state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: AppDropdown<String>(
                value: 'Option 1',
                items: const [
                  DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                  DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
                ],
                enabled: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dropdown renders (behavior of disabled state is internal to FSelect)
      expect(find.byType(AppDropdown<String>), findsOneWidget);
      expect(find.text('Option 1'), findsOneWidget);
    });

    testWidgets('renders successfully without manual Container wrapper',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: AppDropdown<String>(
                value: 'Option 1',
                items: const [
                  DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                  DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AppDropdown renders successfully and displays the selected value.
      // FSelect.rich (used internally) provides its own field chrome, so no
      // manual Container wrapper is needed.
      expect(find.byType(AppDropdown<String>), findsOneWidget);
      expect(find.text('Option 1'), findsOneWidget);
    });

    testWidgets('fires onChanged callback and reflects value prop',
        (tester) async {
      String? selectedValue = 'Option 1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => AppDropdown<String>(
                  value: selectedValue,
                  items: const [
                    DropdownMenuItem(
                        value: 'Option 1', child: Text('Option 1')),
                    DropdownMenuItem(
                        value: 'Option 2', child: Text('Option 2')),
                    DropdownMenuItem(
                        value: 'Option 3', child: Text('Option 3')),
                  ],
                  onChanged: (newValue) {
                    setState(() => selectedValue = newValue);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial value is reflected
      expect(find.text('Option 1'), findsOneWidget);

      // Tap the dropdown to open it
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();

      // Tap on Option 2 in the dropdown menu
      await tester.tap(find.text('Option 2').last);
      await tester.pumpAndSettle();

      // Verify callback was fired and value updated
      expect(selectedValue, 'Option 2');
      expect(find.text('Option 2'), findsOneWidget);
    });

    testWidgets('disabled dropdown blocks interaction — onChanged never fires',
        (tester) async {
      int callbackInvocationCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: AppDropdown<String>(
                value: 'Option 1',
                items: const [
                  DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                  DropdownMenuItem(value: 'Option 2', child: Text('Option 2')),
                  DropdownMenuItem(value: 'Option 3', child: Text('Option 3')),
                ],
                enabled: false,
                onChanged: (_) {
                  callbackInvocationCount++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Option 1'), findsOneWidget);
      expect(callbackInvocationCount, 0);

      // Attempt to tap the dropdown trigger field
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();

      // Verify dropdown menu never opened (no Option 2 or Option 3 in overlay)
      expect(find.text('Option 2'), findsNothing);
      expect(find.text('Option 3'), findsNothing);

      // Verify callback was never invoked
      expect(callbackInvocationCount, 0);
    });
  });
}
