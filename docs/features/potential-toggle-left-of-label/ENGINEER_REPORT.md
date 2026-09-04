# ENGINEER_REPORT.md

## Feature Slug
`potential-toggle-left-of-label`

## Feature Title
Move Potential Rehearsal/Gig toggle to the left of its label

## Cycle Number
1

## Goal
Move the `AppSwitch` from the right end of the "Potential Rehearsal" / "Potential Gig" Row to the left of the `Expanded` label column, inserting a `const SizedBox(width: Spacing.space12)` spacer between them. Pure widget-tree reorder; no state, no data, no new dependencies.

## Architect Tasks Completed
1. Rehearsal: moved `AppSwitch` to head of `Row.children` in `_buildPotentialToggle`, inserted `SizedBox(width: Spacing.space12)` spacer. Preserved conditional subtext gating verbatim.
2. Gig: moved `AppSwitch` to head of `Row.children` in `_buildPotentialGigContainer`, inserted `SizedBox(width: Spacing.space12)` spacer. Preserved unconditional subtext and `(isSaving || forcePotentialOnly)` disabled expression verbatim.
3. Test: added `import 'package:bandroadie/components/ui/app_switch.dart';` and one new `testWidgets` case asserting `switchX < labelX` inside the existing group.

## Files Created
None.

## Files Modified
- `lib/features/events/widgets/rehearsal_form_fields.dart` (+5 / −4; net +1)
- `lib/features/events/widgets/gig_form_fields.dart` (+7 / −6; net +1)
- `test/features/events/widgets/rehearsal_form_fields_test.dart` (+14 / −0; net +14 including import + test case)

## Analyzer Results
```
Analyzing 3 items...
No issues found! (ran in 2.5s)
```
Zero errors, warnings, or infos.

## Test Results
`flutter test test/features/events/widgets/rehearsal_form_fields_test.dart`

- `subtext is absent when isPotential is false` — PASSED
- `subtext is present when isPotential is true` — PASSED
- `AppSwitch renders to the left of the Potential Rehearsal label` — PASSED

3/3 passed, 0 failed.

## Code Efficiency / Bloat Check
- Searched `lib/` for existing horizontal-spacer or toggle-row helpers before adding the `SizedBox`; the codebase uses inline `SizedBox(width: …)` throughout — no shared wrapper exists or is warranted for a single-use spacer.
- No new classes, methods, providers, or helpers introduced.
- Both `AppSwitch(...)` blocks moved verbatim; zero logic changes.
- Diff is exactly the minimum described in the plan (child reorder + one spacer line per file).

## Verification
- Confirmed `Row.children` order in both files after edit: `AppSwitch` → `SizedBox(width: Spacing.space12)` → `Expanded(...)`.
- Confirmed rehearsal conditional subtext `if (isPotential) ...[ ... ]` is untouched.
- Confirmed gig `(isSaving || forcePotentialOnly) ? null : onPotentialGigToggled` expression is untouched.
- Confirmed `AnimatedContainer` wrapper and member-grid block below the `Row` are untouched in both files.
- `dart format` applied to all three changed files; one formatting change (test file indentation).
- Re-ran `flutter analyze` after formatting: still no issues.

## Deviations From Plan
None.

## Blockers Encountered
None.

## Ready For QA
Yes
