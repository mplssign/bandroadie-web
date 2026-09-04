import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
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
            body: _PotentialSectionWrapper(isPotential: isPotential),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Calls buildPotentialSection directly so only _buildPotentialToggle renders.
class _PotentialSectionWrapper extends ConsumerWidget {
  const _PotentialSectionWrapper({required this.isPotential});

  final bool isPotential;

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
    );
    return fields.buildPotentialSection(context, ref);
  }
}

void main() {
  group('RehearsalFormFields potential toggle subtext', () {
    testWidgets('subtext is absent when isPotential is false', (tester) async {
      await _pumpPotentialSection(tester, isPotential: false);

      expect(find.text('Potential Rehearsal'), findsOneWidget);
      expect(
        find.text('Toggle off once confirmed to make it official.'),
        findsNothing,
      );
    });

    testWidgets('subtext is present when isPotential is true', (tester) async {
      await _pumpPotentialSection(tester, isPotential: true);

      expect(find.text('Potential Rehearsal'), findsOneWidget);
      expect(
        find.text('Toggle off once confirmed to make it official.'),
        findsOneWidget,
      );
    });
  });
}
