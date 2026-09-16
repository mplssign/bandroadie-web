# QA REPORT — Calendar events reset on band switch

## Feature Slug

`bug/calendar-events-reset-on-band-switch`

## Feature Title

Calendar "This Month's Events" list resets to current month after switching bands, while calendar grid keeps the selected month

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

The implementation matches the Architect plan exactly: `CalendarNotifier` gained
one library-private instance field (`_selectedMonth`) and the four localized
edits specified in the plan (`build()` both branches, `setSelectedMonth`,
`reset()`). No widget files were touched. The new unit test covers all three
Verification Plan cases and passes, along with the two named regression test
files. Analyzer is clean on both touched files. No secrets, debug artifacts, or
out-of-scope changes found in the diff.

## Architect Scope Review

- Branch `bug/calendar-events-reset-on-band-switch`, plan and engineer report
  slugs match the branch. Confirmed.
- Files modified: only `lib/features/calendar/calendar_controller.dart` — matches
  plan's "Files to Modify" exactly.
- Files created: only `test/features/calendar/calendar_selected_month_preservation_test.dart`
  — matches plan's "Files to Create" exactly.
- Files off-limits (`calendar_screen.dart`, `calendar_tab_content.dart`,
  `calendar_grid.dart`, `active_band_controller.dart`, `pubspec.yaml`, all other
  feature directories, migrations, platform folders) — confirmed untouched via
  `git status --short`.
- No database/migration/Edge Function work — confirmed n/a per plan and no such
  files appear in the change set.

## Completeness Check

All 5 Engineer Task Breakdown items completed:

1. ✅ `_selectedMonth` instance field added below `_cache`, initialized to current month.
2. ✅ Both `build()` return branches (`bandId == null` guard and normal path) use `_selectedMonth`.
3. ✅ `setSelectedMonth` writes `_selectedMonth` before mutating `state`.
4. ✅ `reset()` resets `_selectedMonth` alongside `state`.
5. ✅ Test file created covering Case A (survives band switch), Case B (fresh-load
   default is current month), Case C (`reset()` returns to current month).

No partial implementation, no missing edge cases relative to the plan.

## Behavior Verification

**Method: code-path analysis + automated unit test execution. No manual/runtime
device verification was performed (out of scope for QA — see Manual
Verification Punch List below).**

- Root cause (two independent stores of "which month is being viewed," with
  `build()` unconditionally resetting to `DateTime.now()` on every
  `activeBandIdProvider` change) is fixed at its source: `build()` no longer
  reads `DateTime.now()` at all — it reads the persisted instance field.
  `setSelectedMonth` is the only place `_selectedMonth` and `state` are written
  together at user-driven navigation, and `reset()` is the only place both are
  explicitly returned to "now" (sign-out), matching the plan's intended
  behavior. This is not a symptom patch — it collapses the two-store split
  described in Root Cause into one source of truth, as designed.
  Confirmed by diff review (see below), not by running the app.
- No extra behavior added beyond the plan's four edits.

## Regression Check

**Risk rating: LOW** (matches Architect's own assessment).

- Gigs / Rehearsals / Setlists / Members / Auth / Routing / Notifications /
  Init order / RLS-RPCs-migrations: no files in any of these systems appear in
  the diff; confirmed unaffected.
- `activeBandProvider` / `activeBandIdProvider`: untouched; the two named
  regression tests (`active_band_controller_invalidation_test.dart`,
  `active_band_controller_circular_dependency_test.dart`) pass unchanged (5/5).
- Pre-existing `calendar_markers_test.dart` passes unchanged (does not exercise
  `selectedMonth`).
- Grep for `selectedMonth` across `test/` prior to this change returns only
  the new test file — no pre-existing test asserts
  `selectedMonth == DateTime.now()` that this change could break. Confirmed
  independently (not solely relying on Engineer's grep claim).
- Grep for `runZonedGuarded` across `test/` returns only the new test file —
  no pre-existing zone-guard test helper was duplicated.
- Platform parity: fix is pure Dart state code with no platform-conditional
  paths; no platform folders touched.

## Database Safety

N/A — no migrations, RPCs, or Edge Functions in this change. Confirmed no
`supabase/` files appear in the diff.

## Analyzer Results

```
flutter analyze lib/features/calendar/calendar_controller.dart test/features/calendar/calendar_selected_month_preservation_test.dart
Analyzing 2 items...
No issues found! (ran in 1.8s)
```

Clean at every severity on both touched files.

## Test Results

Ran independently via the test runner:

- `test/features/calendar/calendar_selected_month_preservation_test.dart` (3 tests)
- `test/features/calendar/calendar_markers_test.dart` (existing suite)
- `test/features/bands/active_band_controller_invalidation_test.dart`
- `test/features/bands/active_band_controller_circular_dependency_test.dart`

**Result: 10/10 passed.**

## Diff Safety Review

- No secrets or API keys in the diff.
- Grepped the diff hunks specifically (`git diff HEAD | grep`) for
  `TODO|FIXME|debugPrint(` — zero matches. Note: `calendar_controller.dart`
  does contain pre-existing `debugPrint(` calls elsewhere in the file (lines
  273, 287, 297, 334), but none are within the changed hunks (169–197,
  456–470) — pre-existing, not introduced by this diff.
- No leftover test scaffolding, no accidental deletions, no unrelated
  formatting churn — the diff is exactly the four localized edits described in
  the plan.

## Change Budget Review

| Path | Budgeted | Actual | Ratio |
| --- | --- | --- | --- |
| `lib/features/calendar/calendar_controller.dart` | +6/-3 (net +3, total 9 changed lines) | +11/-4 (net +7, total 15 changed lines) | 1.67x total-lines |
| `test/features/calendar/calendar_selected_month_preservation_test.dart` | ~90 new lines | 128 new lines | 1.42x |

**Finding (Warning, code-quality):** the controller file's change is 1.67x the
budgeted total line count, which crosses the ">1.5x → Warning" threshold. Root
cause is fully explained, not scope creep: the plan's own "Engineer Task
Breakdown" section (item 1) specified the added field's 3-line leading comment
verbatim, but the plan's summarized "Change Budget" table did not account for
those comment lines when it estimated "+6/-3." The actual diff is a byte-for-
byte match to the literal code the plan told the Engineer to write (verified
line-by-line against Task Breakdown items 1–4) — there is no extra field,
method, or logic beyond what the plan specified. This is a plan-authoring
underestimate, not implementation bloat. Does not affect the verdict.

The Engineer Report's own stated diff stat ("+8/-4") does not match the actual
`git diff --numstat` result ("+11/-4") — a minor reporting inaccuracy in
`ENGINEER_REPORT.md`, not a code issue. Noted as a Suggestion.

Test file at 128 lines vs. ~90 budgeted (1.42x) is within the ~1.5x tolerance —
noted, no action needed.

No new files beyond the one the plan named. No new public classes on
production code (the private test-only `_guarded` helper is test scaffolding,
not a production symbol). No new dependencies.

## Code Efficiency Review

- `_selectedMonth` is the single source of truth used everywhere the plan
  specified (`build()` x2, `setSelectedMonth`, `reset()`) — no duplication.
- No new `_buildX()` methods, no new providers/notifiers for state a single
  widget owns, no hand-rolled logic that duplicates an existing utility.
- Test helper `_guarded()` is local to the one new test file, not exported, not
  a candidate for a shared test-helper location given it's a single-use zone
  wrapper; independently confirmed no pre-existing equivalent exists in `test/`.
- Bug fix has non-zero deletions (4 lines removed, all `DateTime.now()` call
  sites replaced) — no zero-deletion concern applies.
- No file crossed a size target requiring justification.

## Manual Verification Punch List

The plan's Verification Plan already classifies the following as an
**owner-run check** ("Owner-run PR-test punch list (Tony, on device — QA cannot
execute these)"). QA has not attempted any of these steps, per QA's operating
rules; handing verbatim to Tony via Manager:

1. Launch the app on the iOS TestFlight build containing this fix; sign in.
   **Expected:** Calendar tab loads; grid shows the current real-world month
   (e.g. September 2026); "This Month's Events" shows the same month's events
   for the active band.
2. On the Calendar tab, in Band A, swipe or wheel-scroll the calendar grid
   forward two months (e.g. September 2026 → November 2026).
   **Expected:** grid now shows November 2026; "This Month's Events" heading
   and list content also show November 2026 for Band A.
3. Tap the band avatar to open the band switcher; select Band B.
   **Expected:** grid continues to display November 2026 (unchanged); "This
   Month's Events" **stays on November 2026** and now shows Band B's November
   2026 events (not September's). This is the regression this fix targets.
4. Open the band switcher again; select Band A.
   **Expected:** grid still on November 2026; events list still on November
   2026, now showing Band A's November 2026 events again.
5. Swipe the grid back two months to September 2026.
   **Expected:** events list follows to September 2026.
6. Switch to Band B, then back to Band A.
   **Expected:** both grid and events list stay on September 2026 through both
   switches.
7. Sign out via the drawer, sign back in, open Calendar tab.
   **Expected:** fresh session opens on the current real-world month in both
   grid and events list.
8. Repeat steps 2–3 on Android and web (Vercel preview) if a TestFlight-like
   build is available for those platforms. **Expected:** behaviour identical
   to iOS.

## Issues Found

### Critical

None.

### Warnings

1. **[code-quality]** `calendar_controller.dart` diff is 1.67x the budgeted
   total changed-line count (15 vs. 9). Root cause identified: the Architect's
   own Change Budget table undercounted the verbatim 3-line comment its own
   Task Breakdown instructed the Engineer to add. The actual code matches the
   plan's literal instructions exactly — no unrequested logic was added.
   Recommend Architect account for comment lines in future Change Budget
   estimates when the Task Breakdown specifies a comment verbatim. Does not
   block approval.

### Suggestions

1. **[code-quality]** `ENGINEER_REPORT.md`'s stated diff stat ("+8/-4") does
   not match the actual `git diff --numstat` result ("+11/-4"). Minor
   reporting inaccuracy, no code impact.
