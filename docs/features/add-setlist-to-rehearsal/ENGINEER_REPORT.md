# ENGINEER REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

3

## Goal

Diagnose Tony's runtime finding that selecting a rehearsal setlist left Add Rehearsal disabled, without weakening the required-location validation, and add create-mode coverage for the actual Location control, setlist selection, button enablement, and submitted form data.

## Architect Tasks Completed

1. Reviewed the create-mode state path in `EventEditorDrawer`: the managed Location autocomplete calls `onLocationTextChanged`, which updates `_rehearsalLocationText` inside `setState`; `_canSave` requires its trimmed value to be non-empty; setlist selection updates only the selected setlist fields.
2. Reworked the existing rehearsal selector widget test from edit mode with a prefilled location to create mode using the actual `FAutocomplete` Location input and Add Rehearsal button.
3. Verified that selecting a setlist while Location is empty leaves Add Rehearsal disabled, preserving required-location validation.
4. Verified that entering a valid Location enables Add Rehearsal and subsequently selecting or clearing a setlist preserves the enabled state.
5. Extended the existing fake repository to capture `createRehearsal` form data and verified the submitted Location, selected `setlistId`, and cleared `setlistId`.
6. Reproduced the required behavior successfully, so no production change was made.

## Files Created

None.

## Files Modified

- `test/features/events/widgets/event_dropdown_test.dart`
- `docs/features/add-setlist-to-rehearsal/ENGINEER_REPORT.md`

## Analyzer Results

- Initial `dart fix --dry-run` identified two scoped test suggestions; both were applied manually.
- Final `dart fix --dry-run`: `Nothing to fix!`
- `flutter analyze test/features/events/widgets/event_dropdown_test.dart`: `No issues found! (ran in 1.9s)`.

## Test Results

- New create-mode regression test passed independently.
- Focused: `flutter test test/features/events/widgets/event_dropdown_test.dart` passed 7/7 tests after formatting.
- Full suite: `flutter test` passed 311/311 tests.

## Code Efficiency/Bloat Check

- No production code was added because the focused reproduction passed against the existing implementation.
- The test reuses the existing private repository fake and provider stubs; only a `createRehearsal` override and direct interaction assertions were added. No new helper, widget, provider, dependency, or test hook was introduced.
- The revised test deletes the edit-mode fixture and replaces it with the smaller create-mode setup needed to expose the reported interaction.
- The changed hunks contain no `TODO`, `FIXME`, or `debugPrint` calls.

## Verification

- Ran `dart format test/features/events/widgets/event_dropdown_test.dart`; formatting made no changes.
- The create-mode widget test exercised the actual Location autocomplete control and asserted the Add Rehearsal callback state before and after setlist and Location interactions.
- The fake repository captured `location: 'Test Studio'` with `setlistId: 'setlist-1'`, then captured `setlistId: null` after selecting None.
- Changed-file analysis, the focused test file, and the full Flutter suite passed after formatting.
- No running-app or platform manual verification was performed by Engineer.

## Deviations From Plan

- Cycle 3 required diagnosis did not reproduce a production defect at the current PR head. The production file was reviewed but not modified; only the plan-approved test file and mandatory Engineer report changed.
- The current implementation intentionally keeps Add Rehearsal disabled when Location is empty, even after selecting a setlist. Entering Location triggers `setState`, and later setlist selection does not clear `_rehearsalLocationText`, so the button remains enabled and save carries the selected setlist.

## Blockers Encountered

None.

## Ready For QA

Ready For QA: Yes
