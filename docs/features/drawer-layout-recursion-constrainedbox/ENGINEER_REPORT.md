# ENGINEER_REPORT.md

## Feature Slug
`drawer-layout-recursion-constrainedbox`

## Feature Title
Add Event drawer crashes with `'!_debugDoingThisLayout'` layout recursion

## Cycle Number
1

## Goal
Fix two regressions introduced in PR #228 that made the Add Event drawer crash and caused excessive `ref.watch()` calls.

## Architect Tasks Completed
- Change 1: Replaced `DecoratedBox` with `Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height))` in `build()`. This restores the `RenderConstrainedBox` ancestor that `FAutocomplete` requires to resolve its overlay anchor without triggering a layout recursion.
- Change 2: Refactored `_buildScrollableBody` to create `gigFormFields`, `rehearsalFormFields`, and `eventFormFields` once at the top, then pass them into section builders. Removed `_buildGigSection` (one-line wrapper, no longer needed). Updated signatures of `_buildScheduleSection`, `_buildLocationSection`, `_buildShowPrepSection`, `_buildMoneySection`, `_buildNotesSection` to accept pre-built form field objects.

## Files Created
None.

## Files Modified
- `lib/features/events/widgets/event_editor_drawer.dart`

## Analyzer Results
`flutter analyze --no-pub lib/features/events/widgets/event_editor_drawer.dart` → **No issues found.**

## Test Results
No plan-required tests. No existing coverage for this widget.

## Code Efficiency / Bloat Check
- **Helper search**: No existing helper for `BoxConstraints(maxHeight: MediaQuery.of(...).size.height)` — used inline, single call site.
- `_buildGigSection` was a one-liner wrapper used exactly once; removed (now the section card takes `gigFormFields!` directly).
- `_createRehearsalFormFields()` is kept as an internal call inside `_buildScheduleSection` because (a) its signature was not specified to include `rehearsalFormFields`, (b) `_createRehearsalFormFields()` does not call `ref.watch()` so there is no performance concern, and (c) it would be a deviation from the specified signatures to add an extra parameter.

## Verification
- Confirmed `DecoratedBox` → `Container(constraints:…)` in `build()` at line 2701.
- Confirmed `_createGigFormFields()` is no longer called inside any section builder method body.
- Confirmed `_createEventFormFields(context)` is no longer called inside any section builder method body.
- Confirmed `_buildGigSection` method is deleted.
- `flutter analyze` → 0 issues before and after `dart format`.

## Deviations From Plan
- `_buildScheduleSection` retains an internal `_createRehearsalFormFields().buildPotentialSection()` call. The plan's specified signature for this method (`GigFormFields? gigFormFields, EventFormFields eventFormFields`) does not include `rehearsalFormFields`, and `_createRehearsalFormFields()` carries no `ref.watch()` overhead, so the deviation does not reintroduce the performance regression.

## Blockers Encountered
None.

## Ready For QA
Yes
