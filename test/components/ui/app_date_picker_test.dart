import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_date_picker.dart';
import 'package:forui/forui.dart';

void main() {
  group('showAppDatePicker header overflow (narrow phones)', () {
    testWidgets('September 2026 renders without overflow at 360×800',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3.0, 800 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDatePicker(
                    context: context,
                    initialDate: DateTime(2026, 9, 15),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030, 12, 31),
                  );
                },
                child: const Text('Open Date Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Date Picker'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FCalendar), findsOneWidget);
    });

    testWidgets('February 2026 renders without overflow at 360×800',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3.0, 800 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDatePicker(
                    context: context,
                    initialDate: DateTime(2026, 2, 15),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030, 12, 31),
                  );
                },
                child: const Text('Open Date Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Date Picker'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FCalendar), findsOneWidget);
    });
  });
}
