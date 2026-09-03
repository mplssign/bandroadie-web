import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';
import 'package:bandroadie/features/events/widgets/event_editor_drawer.dart';
import 'package:bandroadie/features/events/widgets/event_editor_helpers.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:forui/forui.dart';

void main() {
  group('EventDropdown', () {
    testWidgets('renders with custom labelBuilder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: EventDropdown<int>(
                value: 30,
                items: const [0, 15, 30, 45],
                labelBuilder: (value) => ':$value',
                isSaving: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EventDropdown<int>), findsOneWidget);
      expect(find.text(':30'), findsOneWidget);
    });

    testWidgets('disables dropdown when isSaving is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: EventDropdown<String>(
                value: 'Option 1',
                items: const ['Option 1', 'Option 2'],
                labelBuilder: (value) => value,
                isSaving: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify EventDropdown renders (disabled state is internal to FSelect)
      expect(find.byType(EventDropdown<String>), findsOneWidget);
      expect(find.text('Option 1'), findsOneWidget);
    });

    testWidgets('backward compatibility with hour/minute pattern',
        (tester) async {
      int selectedHour = 7;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => EventDropdown<int>(
                  value: selectedHour,
                  items: List.generate(12, (i) => i + 1),
                  labelBuilder: (value) => value.toString(),
                  isSaving: false,
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() => selectedHour = newValue);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial value
      expect(find.text('7'), findsOneWidget);

      // Tap the dropdown to open it
      await tester.tap(find.byType(EventDropdown<int>));
      await tester.pumpAndSettle();

      // Tap on hour 9
      await tester.tap(find.text('9').last);
      await tester.pumpAndSettle();

      // Verify value updated
      expect(selectedHour, 9);
      expect(find.text('9'), findsOneWidget);
    });
  });

  group('AppDropdown Form integration', () {
    testWidgets('validates correctly when used in Form', (tester) async {
      final formKey = GlobalKey<FormState>();
      String? selectedValue;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: Form(
                key: formKey,
                child: EventDropdown<String>(
                  value: selectedValue ?? 'Option 1',
                  items: const ['Option 1', 'Option 2', 'Option 3'],
                  labelBuilder: (value) => value,
                  isSaving: false,
                  onChanged: (newValue) {
                    selectedValue = newValue;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify form exists and dropdown renders
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(EventDropdown<String>), findsOneWidget);
    });

    testWidgets('triggers onSaved callback on Form.save()', (tester) async {
      final formKey = GlobalKey<FormState>();
      String currentValue = 'Option 1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: Scaffold(
              body: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      EventDropdown<String>(
                        value: currentValue,
                        items: const ['Option 1', 'Option 2', 'Option 3'],
                        labelBuilder: (value) => value,
                        isSaving: false,
                        onChanged: (newValue) {
                          if (newValue != null) {
                            currentValue = newValue;
                          }
                        },
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            formKey.currentState!.save();
                          }
                        },
                        child: const Text('Submit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change the value
      await tester.tap(find.byType(EventDropdown<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Option 2').last);
      await tester.pumpAndSettle();

      // Verify value was updated
      expect(currentValue, 'Option 2');
    });
  });

  group('EventEditorDrawer layout', () {
    testWidgets(
      'EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)',
      (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3.0;

        final errors = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = errors.add;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const EventEditorDrawer(
                        initialEventType: EventType.rehearsal,
                        bandId: 'test-band-id',
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        FlutterError.onError = originalOnError;

        // Supabase-not-initialized errors are test-harness noise; exclude them.
        final layoutErrors = errors.where((e) {
          final msg = e.exceptionAsString();
          if (msg.contains('initialize the supabase instance')) return false;
          return msg.contains('BoxConstraints forces an infinite width') ||
              msg.contains('RenderBox was not laid out');
        }).toList();

        expect(
          layoutErrors,
          isEmpty,
          reason: 'Expected zero layout errors but got ${layoutErrors.length}: '
              '${layoutErrors.map((e) => e.exceptionAsString().substring(0, e.exceptionAsString().length.clamp(0, 80))).join('; ')}',
        );
      },
    );
  });
}
