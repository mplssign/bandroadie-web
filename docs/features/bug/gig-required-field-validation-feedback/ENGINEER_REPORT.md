# Engineer Report

## Feature Slug

`bug/gig-required-field-validation-feedback`

## Feature Title

Add Event form gives no indication of which required fields are missing

## Cycle Number

2

## Goal

Make Create reachable in create mode so the existing `_fieldErrors` /
`EventFormData.validate()` inline-error path runs, and add `*` required
markers to the gig-name, city, and rehearsal-location labels. Cycle 2 applies
the plan amendment adding
[test/features/events/widgets/event_dropdown_test.dart](../../../../test/features/events/widgets/event_dropdown_test.dart)
to Files to Modify, resolving the Cycle 1 blocker.

## Architect Tasks Completed

1. Collapsed the create-mode `switch (_eventType)` block inside `_canSave`
   in [lib/features/events/widgets/event_editor_drawer.dart](../../../../lib/features/events/widgets/event_editor_drawer.dart)
   to a single `return true;`. All other guards (`_isEditingExpense`,
   `_isSaving`, `_isDeleting`, `widget.viewOnly`, edit-mode `_isDirty` gate)
   left untouched.
2. Updated the two gig labels in
   [lib/features/events/widgets/gig_form_fields.dart](../../../../lib/features/events/widgets/gig_form_fields.dart)
   to `'Gig Venue / Festival / Name *'` and `'City *'`.
3. Updated the rehearsal label in
   [lib/features/events/widgets/rehearsal_form_fields.dart](../../../../lib/features/events/widgets/rehearsal_form_fields.dart)
   to `'Location *'`.
4. Extended
   [test/features/events/widgets/rehearsal_form_fields_test.dart](../../../../test/features/events/widgets/rehearsal_form_fields_test.dart)
   with a `RehearsalFormFields location label` group (label + `fieldErrors`
   cases), and created
   [test/features/events/widgets/gig_form_fields_test.dart](../../../../test/features/events/widgets/gig_form_fields_test.dart)
   (did not previously exist) with an equivalent `GigFormFields required
   field labels` group covering gig-name and city labels plus one
   `fieldErrors` case per field.
5. **(Cycle 2)** In
   [test/features/events/widgets/event_dropdown_test.dart](../../../../test/features/events/widgets/event_dropdown_test.dart),
   confined to `group('EventEditorDrawer setlist selector (rehearsal)',
   ...)`:
   - Renamed the existing test case to `'create mode preserves button
     enablement across setlist selection'`, dropped the initial
     `expect(addButton().onPressed, isNull);` assertion (button is enabled
     immediately in create mode now), and flipped the two post-selection
     assertions (after tapping `Road Set`, after tapping `None`) from
     `isNull` to `isNotNull`. All other lines in that test case are
     untouched.
   - Added one new sibling `testWidgets` case, `'create mode with empty
     location surfaces inline error and does not call repository'`,
     asserting `onPressed` is not null on open, tapping `Add Rehearsal`
     with no location text, then asserting `find.text('Location is
     required')` matches `findsAtLeastNWidgets(1)` and the repository
     never captured form data.
   - No other group in the file was touched.

## Files Created

- [test/features/events/widgets/gig_form_fields_test.dart](../../../../test/features/events/widgets/gig_form_fields_test.dart)

## Files Modified

- [lib/features/events/widgets/event_editor_drawer.dart](../../../../lib/features/events/widgets/event_editor_drawer.dart)
- [lib/features/events/widgets/gig_form_fields.dart](../../../../lib/features/events/widgets/gig_form_fields.dart)
- [lib/features/events/widgets/rehearsal_form_fields.dart](../../../../lib/features/events/widgets/rehearsal_form_fields.dart)
- [test/features/events/widgets/rehearsal_form_fields_test.dart](../../../../test/features/events/widgets/rehearsal_form_fields_test.dart)
- [test/features/events/widgets/event_dropdown_test.dart](../../../../test/features/events/widgets/event_dropdown_test.dart) *(Cycle 2)*

## Analyzer Results

`flutter analyze` on all six touched files (3 source + 3 test):
**No issues found.**

## Test Results

- `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart
  test/features/events/widgets/gig_form_fields_test.dart` — **all 9 tests
  pass** (2 new rehearsal cases, 3 new gig cases, plus the 4 pre-existing
  rehearsal potential-toggle tests).
- `flutter test test/features/events/widgets/event_dropdown_test.dart` —
  **all 8 tests pass**, including the amended `'create mode preserves
  button enablement across setlist selection'` case and the new `'create
  mode with empty location surfaces inline error and does not call
  repository'` case. The other three groups in the file (`'EventDropdown'`,
  `'AppDropdown Form integration'`, `'EventEditorDrawer layout'`) are
  unchanged and green.
- Full-suite `flutter test` — **all tests pass**, zero regressions anywhere
  in the repo. This resolves the Cycle 1 blocker.

## Code Efficiency/Bloat Check

- No new helpers/utils/extensions added. Reused the existing
  `_StubMembersNotifier` / `ProviderScope` / `AppTheme` / `FTheme` pumping
  pattern already established in `rehearsal_form_fields_test.dart` for both
  test files — searched `test/features/events/widgets/` first and found no
  existing gig-form-fields test to extend instead of create.
- `gig_form_fields_test.dart` calls the widget's public `build()` and
  `buildCityAutocomplete()` methods directly (same style already used by
  `rehearsal_form_fields_test.dart`'s `buildPotentialSection()` call) rather
  than introducing a new isolation helper.
- No production helper/abstraction added — the `_canSave` change is a
  net-negative-line deletion (7 lines removed → 1 line), matching the
  Change Budget's `-4`-ish estimate.
- The new `event_dropdown_test.dart` sibling case reuses the amended case's
  exact setup boilerplate (same `ProviderScope` overrides, same
  `_CapturingEventsRepository`, same widget tree) verbatim per the plan —
  no new test helper extracted, matching the plan's explicit instruction to
  duplicate the boilerplate rather than factor it out.
- File sizes: no touched file crosses its size target as a result of this
  change.

## Verification (manual steps performed)

- Read the full `_canSave` getter, `_buildGigNameAutocomplete`,
  `_buildGigCityAutocomplete`, and `_buildLocationAutocomplete` bodies before
  editing to confirm the diff would touch only the specified literals/logic.
- Confirmed via `git status`/`git diff --stat` that only the files the plan
  lists are changed.
- Ran `dart format` on all 6 touched files — 0 changes (already formatted).
- Ran targeted `flutter analyze` and `flutter test` on touched files (all
  clean), then a full-suite `flutter test` — all green, no regressions.

## Deviations From Plan

- In the new `'create mode with empty location surfaces inline error and
  does not call repository'` test case, the plan's `_CapturingEventsRepository
  repository` declaration was written as `late` (matching the amended case).
  That fails at runtime here with a `LateInitializationError`: the rehearsal
  location guard in `_handleSave` short-circuits *before* `_handleSave` ever
  reads `eventsRepositoryProvider` (the only place that provider is read in
  the drawer), so the override callback that assigns `repository` never
  runs. Declared it as `_CapturingEventsRepository? repository;` instead and
  asserted `repository?.capturedFormData` is null — this preserves the
  plan's intent (repository never captured/created a rehearsal) without
  throwing. No other line in the plan's task 5 instructions required
  deviation.

## Blockers Encountered

None. The Cycle 1 blocker (out-of-scope `event_dropdown_test.dart` failure
caused by Task 1's `_canSave` change) is resolved by this cycle's plan
amendment adding that file to Files to Modify.

## Ready For QA

Yes.
