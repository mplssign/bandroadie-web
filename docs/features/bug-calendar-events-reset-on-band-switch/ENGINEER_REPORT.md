# ENGINEER REPORT — Calendar events reset on band switch

## Feature Slug

`bug/calendar-events-reset-on-band-switch`

## Feature Title

Calendar "This Month's Events" list resets to current month after switching bands, while calendar grid keeps the selected month

## Cycle Number

1

## Goal

Make `CalendarState.selectedMonth` survive a band switch (instance-level view
state on `CalendarNotifier`) instead of resetting to `DateTime.now()` every time
`build()` re-runs due to `activeBandIdProvider` changing.

## Architect Tasks Completed

1. Added library-private instance field `DateTime _selectedMonth` on
   `CalendarNotifier`, initialized to the current month, placed immediately
   below the existing `static final Map<String, MonthData> _cache` field.
2. Updated both `build()` return branches (`bandId == null` guard and normal
   path) to use `_selectedMonth` instead of `DateTime.now()`.
3. Updated `setSelectedMonth` to write `_selectedMonth` before mutating `state`.
4. Updated `reset()` to reset `_selectedMonth` alongside `state`.
5. Created `test/features/calendar/calendar_selected_month_preservation_test.dart`
   covering the three cases from the Verification Plan (survives band switch,
   fresh-load default is current month, `reset()` returns to current month).

## Files Created

- [test/features/calendar/calendar_selected_month_preservation_test.dart](test/features/calendar/calendar_selected_month_preservation_test.dart)

## Files Modified

- [lib/features/calendar/calendar_controller.dart](lib/features/calendar/calendar_controller.dart)

## Analyzer Results

`flutter analyze` on both touched files: **No issues found.**

`dart fix --dry-run .` (whole-package, read-only preview per instructions):
no suggestions touching either file.

## Test Results

`flutter test test/features/calendar/`: **5/5 passed** (2 existing
`calendar_markers_test.dart` tests unchanged + 3 new tests in the created file).

Also ran the QA-flagged regression files as a sanity check (not required by the
plan, but low-cost and directly named in "QA Regression Areas"):
`flutter test test/features/bands/active_band_controller_invalidation_test.dart
test/features/bands/active_band_controller_circular_dependency_test.dart` —
**5/5 passed**.

## Code Efficiency/Bloat Check

- Net change on `calendar_controller.dart`: +8/-4 lines, matching the plan's
  change budget (expected net +3; the extra lines are the field's leading
  comment, which the plan's own task breakdown specified verbatim).
- No new public API, no new providers/notifiers, no new dependencies.
- No `_buildX()` methods, no duplicated helpers — reused the existing
  `_selectedMonth` field as the single source of truth everywhere the plan
  specified.
- Searched for an existing zone-error-swallowing test helper before adding
  `_guarded()` to the new test file (grep across `test/` for
  `runZonedGuarded`) — no existing equivalent; this is a test-only helper
  local to one file, not a `lib/` addition, so no barrel/reuse concern applies.

## Verification (manual steps performed)

- Read `lib/features/calendar/calendar_controller.dart` in full before editing
  to confirm exact surrounding context of `build()`, `setSelectedMonth`,
  `reset()`.
- Ran the new test file standalone and confirmed all 3 cases pass with the
  swallowed-Supabase-error path exercised as the plan's network-avoidance note
  predicted (`[BlockOutRepository] Failed to load block_dates...` /
  `[CalendarController] Error loading events...` debug output visible, and
  `state.selectedMonth` assertions still pass through it).
- Confirmed `git diff` for the modified file matches the plan's four localized
  edits exactly, no unrelated changes.

## Deviations From Plan

- **Test-only, not production code.** The plan's network-avoidance note
  anticipated flutter_test's zone possibly flagging the caught repository
  error and suggested wrapping `selectBand(...)` in `runZonedGuarded` "if
  needed." It *was* needed, but not only where the plan guessed: the actual
  unhandled-error source is the two **sibling** repository futures
  (`rehearsalsFuture`, `blockOutsFuture` in `_loadEventsForBand`) that are
  created eagerly before any `await` and never get awaited once the first
  (`gigsFuture`) rejection sends control to the `catch` block — those orphaned
  futures raise zone-level errors on a later microtask. Additionally,
  `NotifierProvider` rebuilds are pull-based: invalidating `activeBandIdProvider`
  via `selectBand()` doesn't re-run `build()` synchronously — it re-runs on the
  *next* `container.read(calendarProvider)` call. So the test wraps every
  `container.read(calendarProvider)` call that can trigger a `build()` (initial
  read, and the read immediately after `selectBand()`) in a local
  `runZonedGuarded` helper (`_guarded`), not just the `selectBand()` call
  itself. This is confined to the new test file; no production code was
  touched beyond what the plan specified.

## Blockers Encountered

None.

## Ready For QA

Yes.
