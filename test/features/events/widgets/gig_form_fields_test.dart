import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/field_hint.dart';
import 'package:bandroadie/features/events/widgets/gig_form_fields.dart';
import 'package:bandroadie/features/members/members_controller.dart';

// Stub so membersProvider never hits Supabase during tests.
class _StubMembersNotifier extends MembersNotifier {
  @override
  MembersState build() => const MembersState();
}

// Pumps the gig name field (via build()) and city field (via the public
// buildCityAutocomplete helper) to check the required-marker labels + errors.
Future<void> _pumpGigFields(
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
            body: _GigFieldsWrapper(fieldErrors: fieldErrors),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Calls build() and buildCityAutocomplete() directly so both labels render.
class _GigFieldsWrapper extends ConsumerWidget {
  const _GigFieldsWrapper({required this.fieldErrors});

  final Map<String, String> fieldErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = GigFormFields(
      isSaving: false,
      isEditMode: false,
      existingEventId: null,
      availableContacts: const [],
      isLoadingContacts: false,
      contactAutocompleteControllers: const [],
      contactFocusNodes: const [],
      onAddContact: () {},
      onRemoveContact: (_) {},
      onContactTextChanged: (_, __) {},
      onContactSelected: (_, __) {},
      onContactEditingComplete: (_) {},
      onContactSubmitted: (_, __) {},
      gigNameAutocompleteController: FAutocompleteController(),
      venueHintController: FieldHintController(),
      gigNameSuggestions: const [],
      onGigNameChanged: (_) {},
      onGigNameSelected: (_) {},
      onGigNameTextChanged: (_) {},
      fieldErrors: fieldErrors,
      gigCityAutocompleteController: FAutocompleteController(),
      cityHintController: FieldHintController(),
      gigCitySuggestions: const [],
      onGigCityChanged: (_) {},
      onGigCityTextChanged: (_) {},
      addressController: TextEditingController(),
      addressHintController: FieldHintController(),
      gigAddressFocusNode: FocusNode(),
      stateController: TextEditingController(),
      isPotentialGig: false,
      forcePotentialOnly: false,
      onPotentialGigToggled: (_) {},
      memberAvailability: const {},
      isLoadingMemberAvailability: false,
      perDateAvailability: const {},
      isLoadingPerDateAvailability: false,
      currentUserResponse: null,
      isLoadingUserResponse: false,
      onUserResponseChanged: (_) {},
      additionalDates: const [],
      primaryStartTime: '',
      selectedDate: DateTime(2024),
      existingGigDateIds: const {},
      onPerDateResponseChanged: (_, __, ___) {},
      loadInHour: null,
      loadInMinutes: null,
      loadInIsPM: null,
      onLoadInTimeSet: () {},
      onLoadInTimeCleared: () {},
      onLoadInHourChanged: (_) {},
      onLoadInMinutesChanged: (_) {},
      onLoadInAmPmChanged: (_) {},
      gigPayDetails: null,
      onGigPayTap: () {},
      showExpensesSection: false,
      canEditExpenses: false,
      gigExpenses: const [],
      onAddExpense: () {},
      onExpenseTap: (_) {},
      onMarkDirty: () {},
      currentUserId: null,
    );
    return Column(
      children: [
        fields.build(context, ref),
        fields.buildCityAutocomplete(context),
      ],
    );
  }
}

void main() {
  group('GigFormFields required field labels', () {
    testWidgets('gig name and city labels show required marker',
        (tester) async {
      await _pumpGigFields(tester);

      expect(find.text('Gig Venue / Festival / Name *'), findsOneWidget);
      expect(find.text('City *'), findsOneWidget);
    });

    testWidgets('gig name fieldErrors renders inline error', (tester) async {
      await _pumpGigFields(
        tester,
        fieldErrors: const {'name': 'Gig name is required'},
      );

      expect(find.text('Gig name is required'), findsOneWidget);
    });

    testWidgets('city fieldErrors renders inline error', (tester) async {
      await _pumpGigFields(
        tester,
        fieldErrors: const {'city': 'City is required'},
      );

      expect(find.text('City is required'), findsOneWidget);
    });
  });
}
