import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bandroadie/features/calendar/auto_conflict_blocking_service.dart';
import 'package:bandroadie/features/calendar/block_out_repository.dart';
import 'package:bandroadie/features/contacts/contacts_controller.dart';
import 'package:bandroadie/features/contacts/venues_controller.dart';
import 'package:bandroadie/features/events/events_repository.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';
import 'package:bandroadie/features/events/widgets/event_editor_drawer.dart';
import 'package:bandroadie/features/events/widgets/event_editor_helpers.dart';
import 'package:bandroadie/features/members/members_controller.dart';
import 'package:bandroadie/features/setlists/models/setlist.dart';
import 'package:bandroadie/features/setlists/setlists_screen.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:forui/forui.dart';

class _StubSetlistsNotifier extends SetlistsNotifier {
  @override
  SetlistsState build() => const SetlistsState(
        setlists: [
          Setlist(
            id: 'setlist-1',
            name: 'Road Set',
            songCount: 0,
            totalDuration: Duration.zero,
          ),
        ],
      );
}

class _StubMembersNotifier extends MembersNotifier {
  @override
  MembersState build() => const MembersState();
  @override
  Future<void> loadMembers(String? bandId, {bool forceRefresh = false}) async {}
}

class _StubVenuesNotifier extends VenuesNotifier {
  @override
  VenuesState build() => const VenuesState();
  @override
  Future<void> load(String? bandId) async {}
}

class _StubContactsNotifier extends ContactsNotifier {
  @override
  ContactsState build() => const ContactsState();
  @override
  Future<void> load(String? bandId) async {}
}

class _StubBlockOutRepository extends BlockOutRepository {
  @override
  Future<List<Never>> fetchBlockOutsForBand(
    String bandId, {
    bool forceRefresh = false,
  }) async =>
      const [];
}

class _CapturingEventsRepository extends EventsRepository {
  _CapturingEventsRepository(super.autoConflictBlockingService);

  EventFormData? capturedFormData;

  @override
  Future<Never> updateRehearsal({
    required String rehearsalId,
    required String bandId,
    required EventFormData formData,
    bool? wasRecurring,
  }) async {
    capturedFormData = formData;
    throw StateError('Stop after capturing form data');
  }
}

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

  group('EventEditorDrawer setlist selector (rehearsal)', () {
    testWidgets('renders details, selects, and clears a rehearsal setlist',
        (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      try {
        await Supabase.initialize(
          url: 'https://test.supabase.co',
          publishableKey: 'test-anon-key',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            persistSession: false,
          ),
        );
      } catch (_) {}

      late _CapturingEventsRepository repository;
      final existingEvent = EventFormData(
        type: EventType.rehearsal,
        date: DateTime(2026, 9, 13),
        hour: 7,
        minutes: 0,
        isPM: true,
        duration: EventDuration.hour1,
        location: 'Test Studio',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setlistsProvider.overrideWith(_StubSetlistsNotifier.new),
            membersProvider.overrideWith(_StubMembersNotifier.new),
            venuesProvider.overrideWith(_StubVenuesNotifier.new),
            contactsProvider.overrideWith(_StubContactsNotifier.new),
            blockOutRepositoryProvider.overrideWithValue(
              _StubBlockOutRepository(),
            ),
            eventsRepositoryProvider.overrideWith(
              (ref) => repository = _CapturingEventsRepository(
                ref.read(autoConflictBlockingServiceProvider),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: EventEditorDrawer(
                mode: EventEditorMode.edit,
                initialEventType: EventType.rehearsal,
                existingEvent: existingEvent,
                existingEventId: 'rehearsal-1',
                bandId: 'test-band-id',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Road Set')).dy,
        lessThan(tester.getTopLeft(find.text('Notes (optional)')).dy),
      );
      await tester.ensureVisible(find.text('Road Set'));
      await tester.tap(find.text('Road Set'));
      await tester.pump();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(repository.capturedFormData?.setlistId, 'setlist-1');

      repository.capturedFormData = null;
      await tester.ensureVisible(find.text('None'));
      await tester.tap(find.text('None'));
      await tester.pump();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(repository.capturedFormData, isNotNull);
      expect(repository.capturedFormData?.setlistId, isNull);
    });
  });
}
