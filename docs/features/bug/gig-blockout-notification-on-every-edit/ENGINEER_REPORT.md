# ENGINEER_REPORT — bug/gig-blockout-notification-on-every-edit

## Feature Slug

`bug/gig-blockout-notification-on-every-edit`

## Feature Title

Block-out conflict notifications re-sent on every gig edit

## Cycle Number

1

## Goal

Stop `EventsRepository.updateGig()` / `updateRehearsal()` from unconditionally
resyncing (delete + re-insert) auto-generated `block_dates` rows on every edit,
which re-fires the `blockout_created_notification` trigger and spams other
bands' members even when the edit didn't change scheduling. Gate the resync so
it only runs when the edit's main date, `is_potential`, or (for gigs)
additional-dates set actually changed.

## Architect Tasks Completed

1. Added two top-level `@visibleForTesting` pure comparators in
   `lib/features/events/events_repository.dart`: `didGigSchedulingChange` and
   `didRehearsalSchedulingChange`, plus a private `_normalizeDate` helper,
   placed immediately after the imports, before `NoBandSelectedError`.
2. Gated `updateGig`'s existing resync block: added a pre-update snapshot
   fetch (`select(_gigSelectClause)` on `gigs`, hydrated via `Gig.fromJson`)
   before the `data` map is built, then wrapped the existing
   `clearAutoBlocksForSource` + `autoBlockConflictingDates` `try/catch` in
   `if (didGigSchedulingChange(preGig, formData)) { … }`. Surrounding
   `.update()`, `_syncGigDates`, `_syncGigContacts`, `invalidateCache`, and
   final re-fetch left untouched.
3. Gated `updateRehearsal`'s standard-update-path resync: added a minimal
   pre-update snapshot fetch (`select('id, band_id, date, is_potential')`)
   placed after the `isBecomingRecurring` / `isStoppingRecurring` branches
   (so it only runs on the standard path) and before the `.update()` call,
   hydrated into a light `Rehearsal` instance, then wrapped the tail resync
   `try/catch` in `if (didRehearsalSchedulingChange(preRehearsal, formData))`.
   `_updateAndGenerateRecurringSeries` was left untouched per plan.
4. Added `test/features/events/events_repository_scheduling_test.dart` with
   `group('didGigSchedulingChange')` (9 cases) and
   `group('didRehearsalSchedulingChange')` (4 cases), covering every case
   listed in the plan's Tier 1 verification list plus the additional-date
   swap case.
5. Ran `flutter analyze` and `flutter test` on the changed files and the full
   `test/features/events` suite (see below).

## Files Created

- `test/features/events/events_repository_scheduling_test.dart` (161 lines)

## Files Modified

- `lib/features/events/events_repository.dart` (+121 / -52, net +69)

No other files were touched. `git status --short` confirms only these two
paths plus the untracked `docs/features/bug/gig-blockout-notification-on-every-edit/`
folder are dirty.

## Analyzer Results

```
flutter analyze lib/features/events/events_repository.dart test/features/events/events_repository_scheduling_test.dart
Analyzing 2 items...
No issues found! (ran in 1.0s)
```

## Test Results

```
flutter test test/features/events/events_repository_scheduling_test.dart
00:00 +13: All tests passed!
```

```
flutter test test/features/events
00:09 +38: All tests passed!
```

All 38 tests across `test/features/events` pass, including the pre-existing
`widgets/event_dropdown_test.dart` spy (`_CapturingEventsRepository extends
EventsRepository`), confirming the `updateGig`/`updateRehearsal` public
signatures are unchanged.

## Code Efficiency/Bloat Check

- No new provider/notifier, no new public class, no new public method — the
  two comparators are the only new symbols, both `@visibleForTesting`
  top-level functions per plan.
- No `_buildX()` / private widget introduced.
- No hand-rolled dedupe logic beyond the required `Set` comparison, which is
  the simplest correct form for "same set regardless of order."
- No `TODO`/`FIXME`/stray `debugPrint` added (the existing `debugPrint` in the
  `catch` blocks is unchanged, pre-existing code, now just nested one level
  deeper inside the `if`).
- Searched for an existing scheduling-comparison helper before adding new
  ones: no existing helper compares `Gig`/`Rehearsal` snapshots against
  `EventFormData` for scheduling equality — this is a new, narrowly-scoped
  concern the plan explicitly calls for as new top-level functions.
- `events_repository.dart` net delta (+69) is within the plan's budget of
  +55 to +75.

## Verification (manual steps performed)

- Read the full diff against `ARCHITECT_PLAN.md` line-by-line: pre-update
  snapshot placement, gating conditions, and untouched
  `_updateAndGenerateRecurringSeries` all match the plan's task breakdown.
- Confirmed `git status --short` shows no stray files outside the plan's
  Files to Create / Files to Modify list.
- Ran `flutter analyze` scoped to both changed files: clean.
- Ran the new test file in isolation (13/13 pass) and the full
  `test/features/events` suite (38/38 pass).

## Deviations From Plan

- The new test file is 161 lines vs. the plan's estimated +80 to +110. This
  is due to four small builder helpers (`_gig`, `_rehearsal`, `_gigForm`,
  `_rehearsalForm`) needed to construct valid `Gig`/`Rehearsal`/
  `EventFormData` instances with all required constructor fields, plus one
  extra case (additional-date swap) beyond the plan's minimum list. All
  required Tier 1 test cases are present; no scope was added beyond pure
  comparator testing.

## Blockers Encountered

None.

## Ready For QA

Yes
