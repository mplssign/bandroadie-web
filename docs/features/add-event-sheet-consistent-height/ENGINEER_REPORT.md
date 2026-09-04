# ENGINEER_REPORT — add-event-sheet-consistent-height

## Feature Slug
`add-event-sheet-consistent-height`

## Feature Title
Add Event sheet height should stay constant across Rehearsal/Gig/Block out tabs

## Cycle Number
1

## Goal
Fix the Add Event bottom sheet so its outer height stays constant when the user switches between Rehearsal, Gig, and Block out event types. Body content scrolls internally; the sheet chrome does not resize.

## Architect Tasks Completed

1. In `_EventEditorDrawerState.build()` (lines 2703–2735):
   - Replaced `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height)` with `height: MediaQuery.of(context).size.height` on the outer `Container`.
   - Replaced `Flexible` with `Expanded` around the `SingleChildScrollView`.
   - Removed `mainAxisSize: MainAxisSize.min` from the `Column`.

## Files Created
None.

## Files Modified

| File | Change summary |
| ---- | -------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Three-property layout fix in `_EventEditorDrawerState.build()` as specified. |

## Analyzer Results

```
Analyzing event_editor_drawer.dart...
No issues found! (ran in 2.6s)
```

Zero errors, warnings, or info-level findings.

## Test Results

```
flutter test test/features/events/widgets/event_dropdown_test.dart
Summary: passed=6 failed=0
```

All 6 tests pass, including `EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)`.

## Code Efficiency / Bloat Check

- No new helpers, extensions, utils, or private widget classes added.
- No new providers, notifiers, or controllers.
- No `_buildX()` methods or private `_Foo` widgets added.
- No unused imports, variables, or dead code introduced.
- Search performed for existing helpers: change is a direct property swap; no helper warranted or applicable.

**Net line delta:** The plan states −1; the actual diff is −2 (3 lines removed for the multi-line `BoxConstraints(…)` block, 1 line added for `height:`; `mainAxisSize` removal is −1; `Flexible` → `Expanded` is 0 net). The plan described the `BoxConstraints(…)` block as "one line" but it spanned 3 lines in the file. Behavior is identical to the plan.

## Verification

- Read the modified hunk before and after the edit to confirm no unintended whitespace or structural changes.
- `dart format` reported 0 changes (file was already formatted after the edit).
- `git diff` output reviewed in full — diff matches exactly the three intended changes and nothing else.

## Deviations From Plan
None in behavior or scope. The net line delta is −2 rather than the plan's estimate of −1 due to the `BoxConstraints(…)` block being 3 source lines (not 1 as the plan described). No functional or structural deviation.

## Blockers Encountered
None.

## Ready For QA
Yes
