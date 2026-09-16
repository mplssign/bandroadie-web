import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:bandroadie/components/ui/field_hint.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';
import 'package:bandroadie/features/events/widgets/rehearsal_form_fields.dart';
import 'package:bandroadie/features/members/members_controller.dart';

// Stub so membersProvider never hits Supabase during tests.
class _StubMembersNotifier extends MembersNotifier {
  @override
  MembersState build() => const MembersState();
}

// Pumps only the potential-toggle section to avoid wiring up the full form.
Future<void> _pumpPotentialSection(
  WidgetTester tester, {
  required bool isPotential,
  List<AdditionalDateEntry> additionalDates = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        membersProvider.overrideWith(_StubMembersNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: Scaffold(
            body: _PotentialSectionWrapper(
              isPotential: isPotential,
              additionalDates: additionalDates,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Calls buildPotentialSection directly so only _buildPotentialToggle renders.
class _PotentialSectionWrapper extends ConsumerWidget {
  const _PotentialSectionWrapper({
    required this.isPotential,
    required this.additionalDates,
  });

  final bool isPotential;
  final List<AdditionalDateEntry> additionalDates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = RehearsalFormFields(
      isSaving: false,
      locationAutocompleteController: FAutocompleteController(),
      locationHintController: FieldHintController(),
      locationSuggestions: const [],
      onLocationTextChanged: (_) {},
      fieldErrors: const {},
      isPotential: isPotential,
      onPotentialToggled: (_) {},
      additionalDates: additionalDates,
      primaryStartTime: '',
      isRecurring: false,
      onRecurringToggled: (_) {},
      recurringSlideAnimation: const AlwaysStoppedAnimation(Offset.zero),
      recurringFadeAnimation: const AlwaysStoppedAnimation(0.0),
      selectedDays: const {},
      onDayToggled: (_) {},
      frequency: RecurrenceFrequency.weekly,
      onFrequencyChanged: (_) {},
      untilDate: null,
      onUntilDateTap: () {},
      onUntilDateCleared: () {},
      selectedDate: DateTime(2024),
      onMarkDirty: () {},
      memberAvailability: const {},
      isLoadingMemberAvailability: false,
      isLoadingUserResponse: false,
      isEditMode: true,
      existingEventId: 'rehearsal-1',
    );
    return fields.buildPotentialSection(context, ref);
  }
}

// Pumps the full form via build() to check the location label + errors.
Future<void> _pumpLocationField(
  WidgetTester tester, {
  Map<String, String> fieldErrors = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        membersProvider.overrideWith(_StubMembersNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: Scaffold(
            body: _LocationFieldWrapper(fieldErrors: fieldErrors),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Calls build() directly so the location autocomplete label renders.
class _LocationFieldWrapper extends ConsumerWidget {
  const _LocationFieldWrapper({required this.fieldErrors});

  final Map<String, String> fieldErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = RehearsalFormFields(
      isSaving: false,
      locationAutocompleteController: FAutocompleteController(),
      locationHintController: FieldHintController(),
      locationSuggestions: const [],
      onLocationTextChanged: (_) {},
      fieldErrors: fieldErrors,
      isPotential: false,
      onPotentialToggled: (_) {},
      additionalDates: const [],
      primaryStartTime: '',
      isRecurring: false,
      onRecurringToggled: (_) {},
      recurringSlideAnimation: const AlwaysStoppedAnimation(Offset.zero),
      recurringFadeAnimation: const AlwaysStoppedAnimation(0.0),
      selectedDays: const {},
      onDayToggled: (_) {},
      frequency: RecurrenceFrequency.weekly,
      onFrequencyChanged: (_) {},
      untilDate: null,
      onUntilDateTap: () {},
      onUntilDateCleared: () {},
      selectedDate: DateTime(2024),
      onMarkDirty: () {},
      memberAvailability: const {},
      isLoadingMemberAvailability: false,
      isLoadingUserResponse: false,
      isEditMode: true,
      existingEventId: 'rehearsal-1',
    );
    return fields.build(context, ref);
  }
}

void main() {
  group('RehearsalFormFields location label', () {
    testWidgets('location label shows required marker', (tester) async {
      await _pumpLocationField(tester);

      expect(find.text('Location *'), findsOneWidget);
    });

    testWidgets('location fieldErrors renders inline error', (tester) async {
      await _pumpLocationField(
        tester,
        fieldErrors: const {'location': 'Location is required'},
      );

      expect(find.text('Location is required'), findsOneWidget);
    });
  });

  group('RehearsalFormFields potential toggle subtext', () {
    testWidgets('subtext is absent when isPotential is false', (tester) async {
      await _pumpPotentialSection(tester, isPotential: false);

      expect(find.text('Potential Rehearsal'), findsOneWidget);
      expect(
        find.text('Choose a date below to make the rehearsal official.'),
        findsNothing,
      );
    });

    testWidgets('subtext is present when isPotential is true', (tester) async {
      await _pumpPotentialSection(tester, isPotential: true);

      expect(find.text('Potential Rehearsal'), findsOneWidget);
      expect(
        find.text('Choose a date below to make the rehearsal official.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'AppSwitch renders to the left of the Potential Rehearsal label',
        (tester) async {
      await _pumpPotentialSection(tester, isPotential: true);

      final switchX = tester.getTopLeft(find.byType(AppSwitch)).dx;
      final labelX = tester.getTopLeft(find.text('Potential Rehearsal')).dx;
      expect(switchX, lessThan(labelX));
    });
  });

  testWidgets('edit panel omits availability and duplicate date options',
      (tester) async {
    await _pumpPotentialSection(
      tester,
      isPotential: true,
      additionalDates: [
        AdditionalDateEntry(
          date: DateTime(2026, 10, 10),
          hour: 8,
          minutes: 30,
          isPM: true,
        ),
      ],
    );

    expect(find.text('Your Availability'), findsNothing);
    expect(find.text('Proposed Dates'), findsNothing);
    expect(find.text('NO'), findsNothing);
    expect(find.text('YES'), findsNothing);
  });
}
