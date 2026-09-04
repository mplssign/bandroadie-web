# ENGINEER_REPORT.md

## Feature Slug
`bug/add-event-date-picker-calendar-header-overflow`

## Feature Title
Calendar header RenderFlex overflow in the "Add Event" date picker for certain months (e.g. September)

## Cycle Number
2

## Goal
Implement Plan revision-2 Part B: add a `headerBuilder:` to `FCalendar.grid(...)` in
`lib/components/ui/app_date_picker.dart` that wraps the built-in forui header widget in a
`LayoutBuilder → SingleChildScrollView → ConstrainedBox → IntrinsicWidth` chain so that
header content wider than forui's internal 308-px `SizedBox` hard cap never causes a
`RenderFlex` overflow error. Part A (dialog widening via `FDialogStyleDelta` + `FDialog.constraints`)
was already on disk and was preserved without modification.

## Architect Tasks Completed

| # | Task | Status |
|---|------|--------|
| 1 | Preserve Part A: `FDialog.style` inset-padding reduction + `FDialog.constraints (280, 360)` + no inner `ConstrainedBox` | ✅ preserved as-is |
| 2 | Add `headerBuilder:` to `FCalendar.grid(...)` exactly as specified: `LayoutBuilder → SingleChildScrollView(horizontal) → ConstrainedBox(minWidth: viewport.maxWidth) → IntrinsicWidth(child: header)` | ✅ done |
| 3 | No new imports (all types already in scope via `flutter/material.dart`) | ✅ confirmed |
| 4 | No `physics:` argument on `SingleChildScrollView` (default intentional) | ✅ confirmed |
| 5 | All other `FCalendar.grid` arguments preserved verbatim | ✅ confirmed |

## Files Created
None.

## Files Modified
- `lib/components/ui/app_date_picker.dart` — added `headerBuilder:` argument to `FCalendar.grid(...)` (+11 lines net, within the ≤+14 change budget)

## Analyzer Results

Command: `flutter analyze lib/components/ui/app_date_picker.dart test/components/ui/app_date_picker_test.dart`

```
Analyzing 2 items...

   info • The value of the argument is redundant because it matches the default
          value. Try removing the argument •
          lib/components/ui/app_date_picker.dart:19:25 •
          avoid_redundant_argument_values
   info • The value of the argument is redundant because it matches the default
          value. Try removing the argument •
          lib/components/ui/app_date_picker.dart:38:21 •
          avoid_redundant_argument_values

2 issues found. (ran in 1.5s)
```

**Errors: 0. Warnings: 0. Info: 2** (both `avoid_redundant_argument_values` for
`barrierDismissible: true` line 19 and `fixedWeeks: false` line 38 — explicitly
accepted by the plan: "info-level lint about redundant defaults is acceptable").

`dart fix --dry-run` on the changed file proposed exactly those same 2 fixes and nothing
else. Not applied — plan calls them acceptable.

## Test Results

Command: `flutter test test/components/ui/app_date_picker_test.dart --reporter=expanded`

```
00:00 +0: loading .../app_date_picker_test.dart
00:00 +0: showAppDatePicker header overflow (narrow phones) September 2026 renders without overflow at 360×800
00:00 +1: showAppDatePicker header overflow (narrow phones) February 2026 renders without overflow at 360×800
00:00 +2: All tests passed!
```

**Both cases PASS.**

## Code Efficiency / Bloat Check

- No helper, extension, util, or private widget class added; the `headerBuilder` callback is
  an inline closure at the single call site, which is the correct scope.
- No new provider, notifier, repository, or model.
- No `_buildX()` method or private `_Foo` widget.
- No unused imports or variables.
- No `TODO`/`FIXME`/`debugPrint` left in diff.
- Existing helper search: `IntrinsicWidth`, `SingleChildScrollView`, `LayoutBuilder`,
  `ConstrainedBox` are all Flutter framework types used directly — no existing BandRoadie
  helper wraps any of these in a relevant way. "No existing helper for overflow-tolerant
  header layout" is the finding; confirmed by `grep_search` of `lib/`.
- File size: `app_date_picker.dart` is 53 lines — well within 500-line target.
- Pure addition of a `headerBuilder:` to an existing call site: the bug was a missing
  overflow-tolerant wrapper, so zero deleted lines in Part B is correct (the defective code
  is in third-party forui source; our fix adds a wrapper rather than patching the defect).

## Verification

1. Read ARCHITECT_PLAN.md (revision 2) in full — plan and branch slug match.
2. Confirmed `headerBuilder` typedef in forui-0.26.0:
   `FCalendarHeaderBuilder<C> = Widget Function(BuildContext context, C controller, FDateSelectionController<Object?> selectionController, Widget child)` — 4th param is `child` (plan uses `header` as local name, compatible).
3. Confirmed `FCalendar.grid` factory accepts `headerBuilder` with a default, so passing a custom one is valid.
4. Part A verified on disk before making any change.
5. Added `headerBuilder:` per plan spec.
6. `flutter analyze` — 0 errors, 2 info lints (accepted).
7. `flutter test` — both September 2026 and February 2026 cases PASS.
8. `dart format lib/components/ui/app_date_picker.dart` — 0 changes (already formatted).

## Deviations From Plan
None.

## Blockers Encountered
None.

## Ready For QA
**Yes** — 0 analyzer errors; both acceptance test cases pass.
