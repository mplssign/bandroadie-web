# QA_REPORT — bug/band-switch-stale-scoped-data

## Feature Slug

`bug/band-switch-stale-scoped-data`

## Feature Title

Band switching throws an unhandled `CircularDependencyError` on every single
switch (from `ActiveBandNotifier.selectBand()`)

## Cycle Number

2

## Final Verdict

**APPROVED**

## Validation Summary

Branch `bug/band-switch-stale-scoped-data` is clean except for the expected
uncommitted diff. The working-tree diff contains exactly the two-line
deletion the plan specified (net −3 lines counting the orphaned blank line in
`reset()`), in exactly one file:
[lib/features/bands/active_band_controller.dart](../../../lib/features/bands/active_band_controller.dart).
The one untracked non-doc file,
[test/features/bands/active_band_controller_circular_dependency_test.dart](../../../test/features/bands/active_band_controller_circular_dependency_test.dart),
is the regression test the plan explicitly required as a "Files to Create"
item, and its contents match the plan's Case A / Case B spec. `flutter
analyze` on the touched files is clean, the regression test and sibling
invalidation test both pass, and the full `test/features/` suite reproduces
Engineer's reported 146/150 with the same 4 pre-existing/unrelated failures
in `band_currency_picker_test.dart`. This is code-path/analyzer/test
verification only — no on-device runtime verification was performed or
claimed; that is Tony's job per the plan's owner-run punch list below.

## Architect Scope Review

- `git diff --name-only HEAD` → exactly one tracked file changed:
  `lib/features/bands/active_band_controller.dart`. Matches plan's "Files to
  Modify" exactly.
- Untracked files: `docs/features/bug/band-switch-stale-scoped-data/` (this
  pipeline's own docs, expected) and
  `test/features/bands/active_band_controller_circular_dependency_test.dart`
  (the plan's one required new file). No other new files.
- No off-limits files touched: the five "Log Out" screens, all tab-provider
  files (`gig_controller.dart`, `rehearsal_controller.dart`,
  `setlists_screen.dart`, `calendar_controller.dart`,
  `financials_controller.dart`), `band_permissions_provider.dart`,
  `_invalidateBandScopedProviders()`, and the `loadAndSelectBand()`
  `Future.microtask` block are all untouched — confirmed both by the
  `git diff --name-only` scope (only one file changed) and by reading the
  diff hunk itself.
- `pubspec.yaml` / `pubspec.lock`: no diff — confirmed via
  `git diff --stat -- pubspec.yaml pubspec.lock` (empty output).

## Completeness Check

All 5 Architect tasks verified done:

1. ✅ Line `ref.invalidate(currentUserPermissionsProvider);` deleted from
   `selectBand()`. Post-edit body read from disk matches the plan's expected
   snippet verbatim (state update → `_invalidateBandScopedProviders()` →
   `selectedSetlistProvider.notifier.clear()` →
   `currentTabProvider.notifier.setTab(dashboard)` → `_persistBandId`).
2. ✅ Line `ref.invalidate(currentUserPermissionsProvider);` deleted from
   `reset()`, including the orphaned blank line above the closing brace.
   Post-edit body matches the plan's expected snippet verbatim.
3. ✅ Import `'../members/permissions/band_permissions_provider.dart';`
   untouched at line 12, and still referenced (line 387, inside
   `loadAndSelectBand()`'s microtask, which the plan says to leave alone) —
   `flutter analyze` confirms no unused-import diagnostic.
4. ✅ Regression test file exists with both Case A (`selectBand`) and Case B
   (`reset`) exactly as specified: `_SeededActiveBandNotifier` seeding
   `userBands: [_band1, _band2]`/`activeBand: _band1`,
   `currentUserPermissionsProvider` override watching
   `activeBandIdProvider`, forced `fireImmediately: true` listen,
   `SharedPreferences.setMockInitialValues({})` in `setUp`, and the specified
   assertions on both tests (including the `activeBandIdProvider` reactive
   check in Case A).
5. ✅ `flutter analyze` and `flutter test test/features/bands/` were run by
   Engineer per the report; QA independently re-ran the equivalent commands
   (see Analyzer Results / Test Results below) with matching results.

No partial implementations, no skipped edge cases relative to the plan's
5-item task breakdown.

## Behavior Verification

Root cause (synchronous `ref.invalidate()` on a provider that transitively
watches the invoking notifier, tripping Riverpod's
`_debugAssertCanDependOn` guard) is fixed by removing the two offending
calls, not by suppressing the exception's surface symptom. This is a pure
deletion of dead-on-arrival code — both call sites are exactly what the plan
identified as the throw site, confirmed against the diff hunk. No extra
behavior was added beyond the plan's two deletions plus the already-required
regression test.

**Verification performed: code-path analysis, static diff review, analyzer,
and automated test execution — no manual/on-device runtime verification.**
That class of check is explicitly deferred to Tony per the plan's owner-run
punch list (CRASH-1 through CRASH-5, FIN-1).

## Regression Check

Plan's System Impact Map areas re-checked, risk rated per area:

| Area | Risk | Notes |
|---|---|---|
| Gigs / Rehearsals / Setlists / Calendar | LOW | Untouched providers; all watch `activeBandIdProvider` or `bandFullStateProvider` in `build()`, unaffected by the deletion. Confirmed no changes to any of these files in the diff. |
| Members / Contacts / Venues | LOW | `_invalidateBandScopedProviders()` itself untouched; it now actually executes since the throw before it is removed — this is the intended fix, matches the existing (unmodified) invalidation test, which still passes. |
| Auth / session | LOW | `reset()` (all 5 Log Out call sites) no longer throws; no auth/session file touched. |
| Routing / Tab | LOW | `setTab(NavTabIndex.dashboard)` inside `selectBand()` now reachable for the four non-`app_shell.dart` callers — an intentional, plan-documented behavior change, not a regression. |
| Notifications | LOW | `notification_navigation_handler.dart` not touched; awaited `selectBand()` now completes normally instead of never resolving past the throw point. |
| Financials | LOW / unverified at runtime | Code path unchanged; plan explicitly defers confirmation to owner-run FIN-1. |
| Platforms | LOW | Pure Dart/Riverpod change, no platform-conditional code touched. |
| Init order | LOW | Not touched; `loadAndSelectBand()` microtask block (init/deep-link path) explicitly untouched per diff review. |

No `SECURITY DEFINER`/RPC-signature/RLS concerns — this ticket has zero
database impact per the plan, confirmed by no `supabase/` files in the diff.

**Overall regression risk: LOW**, consistent with the plan's own rating.

## Database Safety

N/A — no migration, RPC, or SQL file in the diff. Confirmed via
`git diff --name-only HEAD` showing zero files under `supabase/`.

## Analyzer Results

```
flutter analyze lib/features/bands/active_band_controller.dart test/features/bands/active_band_controller_circular_dependency_test.dart
Analyzing 2 items...
No issues found! (ran in 2.3s)
```

Zero issues at every severity for both touched files.

## Test Results

- `flutter test test/features/bands/active_band_controller_circular_dependency_test.dart test/features/bands/active_band_controller_invalidation_test.dart`
  → **All 5 tests passed** (T1-B and T1-C independently re-run by QA).
- `flutter test test/features/` (T1-D) → **150 tests: 146 passed, 4 failed.**
  QA independently re-ran the full suite; failures are identical to those
  reported by Engineer, all in
  [test/features/bands/band_currency_picker_test.dart](../../../test/features/bands/band_currency_picker_test.dart)
  (`Bulgaria retains composite row and Ecuador is fully absent`, `USD and EUR
  use one exact composite row in the correct group`, `picker groups have the
  exact order and cardinalities`, `picker rows have globally unique labels
  and ISO values`). This file is not in the diff (`git diff --name-only HEAD`
  confirms only `active_band_controller.dart` changed) — pre-existing,
  unrelated to `ActiveBandNotifier`/`CircularDependencyError`.

## Diff Safety Review

- No secrets, API keys, or credentials in the diff or the new test file.
- No `TODO`/`FIXME`/`debugPrint(` anywhere in the diff or the new test file
  (grepped explicitly, not eyeballed).
- No leftover test scaffolding, no accidental deletions beyond the two
  targeted lines (plus the one orphaned blank line in `reset()`, which the
  plan's own expected post-edit snippet shows as intentional), no unrelated
  formatting churn — `dart format` reported 0 changes per Engineer's report,
  and the diff hunk contains no whitespace-only lines outside the two
  deletions.

## Change Budget Review

- Plan budget: `active_band_controller.dart` **−2** net lines (two
  `ref.invalidate` calls); actual: **−3** (0 insertions / 3 deletions per
  `git diff --numstat`) — the extra deletion is the orphaned blank line in
  `reset()`, explicitly shown as part of the plan's own expected post-edit
  `reset()` snippet. Within budget, no scope creep.
- New file: exactly 1 (`active_band_controller_circular_dependency_test.dart`),
  matching the plan's "Expected new files: 1". Actual line count ~104 lines,
  within the ±30 tolerance of the plan's +~110 estimate.
- New public classes/methods: 0. New dependencies: 0. Matches plan exactly.
- No new symbol was introduced in production code to grep for a pre-existing
  equivalent — this cycle is a pure deletion in `active_band_controller.dart`.
  The test file's `_SeededActiveBandNotifier` is an explicitly plan-mandated
  reuse of the sibling invalidation test's existing pattern, not a new
  abstraction — confirmed by direct comparison against
  [active_band_controller_invalidation_test.dart](../../../test/features/bands/active_band_controller_invalidation_test.dart),
  which defines the same shape.
- Bug fix with 3 deleted / 0 added lines: `ENGINEER_REPORT.md` explicitly
  states the reason nothing needed adding — root cause was two lines of
  dead-on-arrival code, not a missing check. Satisfies the stated-reason
  requirement.

## Code Efficiency Review

No AI-shaped bloat found: no single-use helper methods, no new
provider/notifier for widget-owned state, no hand-rolled loops duplicating
`package:collection`, no unnecessary try/catch, no unused fields/params, no
barrel file, no speculative "for future use" additions. The change is a
strict subset of the plan's two-line deletion plus the one already-planned
test file.

## Manual Verification Punch List

The following require a running app on a physical device and are Tony's to
execute — QA did not and cannot attempt these:

1. **CRASH-1 (Primary — confirms the fix)**
   - Run the app on the same physical device used for the original repro,
     with the debug console attached.
   - Sign in, land on Home/Dashboard, open the band switcher, tap 5
     different bands in sequence.
   - **Expected:** zero `CircularDependencyError` lines and zero
     `Unhandled Exception:` lines with a `dart_vm_initializer` preamble
     across all 5 switches. `[GigController] resetForBandChange` and the
     per-tab RPC/fetch log lines still appear as before.

2. **CRASH-2 (Persistence)**
   - From CRASH-1's final state (band X active), fully force-quit the app,
     then cold-launch it again.
   - **Expected:** the app opens with band X still active.

3. **CRASH-3 (Members / Contacts / Venues no longer stale)**
   - Cold-start on band A, note the Members tab list. Switch to band B via
     the band switcher. Reopen the Members tab.
   - **Expected:** band B's members shown, not band A's cached list. Repeat
     for Contacts and Venues.

4. **CRASH-4 (Selected-setlist clear)**
   - Cold-start on band A, open Setlists, tap into a setlist (selecting it).
     Switch to band B via the band switcher. Return to the Setlists tab.
   - **Expected:** Setlists tab shows band B's list at its root, not band
     A's detail screen.

5. **CRASH-5 (Non-shell caller tab reset)**
   - Cold-start on band A, navigate to Calendar (tab index != 0). Open the
     band switcher from within Calendar and switch to band B.
   - **Expected:** app returns to the Dashboard tab.

6. **FIN-1 (Financials — not exercised in the original log)**
   - Cold-start on band A with at least one financial entry, note the
     Financials tab entries. Switch to band B (different/no financial
     entries). Reopen Financials.
   - **Expected:** band B's entries shown, not band A's. If band A's entries
     persist, file that as a separate follow-up ticket per the plan (adding
     `financialsProvider` to `_invalidateBandScopedProviders()` would then
     be safe, since this ticket's `CircularDependencyError` root cause is
     already fixed).

## Issues Found

None.

No Critical, Warning, or Suggestion items — the diff is an exact, minimal
match to the Architect plan with no scope creep, no regressions, no bloat,
and all mechanically-executable verification passing.
