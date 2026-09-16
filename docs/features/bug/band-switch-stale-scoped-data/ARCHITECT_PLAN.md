# ARCHITECT_PLAN — bug/band-switch-stale-scoped-data

## Feature Slug

`bug/band-switch-stale-scoped-data`

## Feature Title

Band switching throws an unhandled `CircularDependencyError` on every single
switch (from `ActiveBandNotifier.selectBand()`); the originally-suspected
"stale tab data" symptom was NOT observed on-device

## Problem Summary

On every tap of a band in the band switcher, `ActiveBandNotifier.selectBand()`
throws an unhandled `CircularDependencyError` from Riverpod's self-dependency
guard at [lib/features/bands/active_band_controller.dart#L338](lib/features/bands/active_band_controller.dart#L338)
(`ref.invalidate(currentUserPermissionsProvider)`). Because `selectBand()` is
`async` and every call site fires it without `await`, the rejected Future is
logged as an unhandled zone exception and the app keeps running — but every
side effect ordered after that line inside `selectBand()` is silently skipped:

1. `_invalidateBandScopedProviders()` — `membersProvider` / `contactsProvider` /
   `venuesProvider` never get invalidated on band switch.
2. `ref.read(selectedSetlistProvider.notifier).clear()` — a setlist selected in
   band A stays "selected" after switching to band B.
3. `ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard)` —
   `selectBand()`'s own tab reset never runs.
4. `await _persistBandId(band.id)` — the newly-selected band is **not**
   persisted to SharedPreferences; on the next cold start, the app restores
   whatever band was persisted before this bug started firing.

The four self-refreshing tab providers Tony verified in his on-device log
(`gigProvider` / `rehearsalProvider` / `setlistsProvider` / `calendarProvider`)
all correctly re-fetch the new band's data because each of them watches
`activeBandIdProvider` (directly or via `bandFullStateProvider`) in `build()`
and re-runs on the state update at
[active_band_controller.dart#L335](lib/features/bands/active_band_controller.dart#L335)
(which executes before the throw). That state update is why the switch
*visually* works despite the crash. `financialsProvider` was not exercised in
Tony's log but its `build()` follows the identical `ref.watch(activeBandIdProvider)`
pattern at [financials_controller.dart#L84](lib/features/financials/financials_controller.dart#L84).

Symptoms Tony did **not** report but that are latent in the current build,
caused by the same skipped side-effects:

- Members / Contacts / Venues showing the previous band's rows after a switch
  (`_invalidateBandScopedProviders()` never runs).
- A cross-band setlist selection persisting after the switch
  (`selectedSetlistProvider.clear()` never runs).
- On cold restart, the app opening to a stale band because
  `_persistBandId()` never runs on any in-session switch.

## Root Cause

**HIGH confidence.** Riverpod's `Ref.invalidate(target)` internally invokes
`_debugAssertCanDependOn(target)` (visible at `#0` in Tony's stack trace).
That guard throws `CircularDependencyError` when `target` transitively depends
on the provider whose notifier is currently invoking `.invalidate()`.

The dependency chain at runtime is:

```
currentUserPermissionsProvider  (FutureProvider)
  └── ref.watch(activeBandIdProvider)
       └── ref.watch(activeBandProvider)   ← the NotifierProvider whose
                                              ActiveBandNotifier is running
                                              selectBand() and calling
                                              ref.invalidate(currentUserPerm…)
```

Confirmed by direct source read:

- [band_permissions_provider.dart#L29-L35](lib/features/members/permissions/band_permissions_provider.dart#L29-L35) —
  `currentUserPermissionsProvider` calls `ref.watch(activeBandIdProvider)` at
  the top of its callback.
- [active_band_controller.dart#L527-L529](lib/features/bands/active_band_controller.dart#L527-L529) —
  `activeBandIdProvider = Provider<String?>((ref) =>
  ref.watch(activeBandProvider).activeBandId);`
- `ActiveBandNotifier` is the notifier for `activeBandProvider`
  ([active_band_controller.dart#L499-L502](lib/features/bands/active_band_controller.dart#L499-L502)).

The dependency edge only exists at runtime after `currentUserPermissionsProvider`
has actually been listened to at least once. On real devices, `app_shell.dart`
listens to it for the "Edit Band" gate at
[app_shell.dart#L376-L380](lib/features/shell/app_shell.dart#L376-L380),
so the edge is established as soon as the shell renders — which is why the
crash reproduces on 100% of on-device band switches but does **not** reproduce
in the existing headless test at
[test/features/bands/active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart)
(that test never listens to `currentUserPermissionsProvider`, so the edge is
never registered, so the guard silently passes).

Why the identical-pattern call inside `loadAndSelectBand()`
([active_band_controller.dart#L387-L391](lib/features/bands/active_band_controller.dart#L387-L391))
does *not* throw: it's wrapped in `Future.microtask(...)`, which runs after
the current synchronous frame unwinds — outside the notifier-mutation window
that the guard treats as "currently a dependent's producer". The guard fires
only for the synchronous, in-method invalidate at line 338 (and, by the same
pattern, at line 485 inside `reset()`).

## Existing System Analysis

**Provider families and how each reacts to a band switch:**

| Provider | `build()` watches | Behaviour on `activeBand` state change |
|---|---|---|
| `bandFullStateProvider` | `activeBandIdProvider` | Re-fetches full RPC ([band_full_state.dart#L121](lib/features/bands/band_full_state.dart#L121)) |
| `gigProvider` | `bandFullStateProvider` | Auto-refresh (log-confirmed) |
| `rehearsalProvider` | `bandFullStateProvider` | Auto-refresh (log-confirmed) |
| `setlistsProvider` | `activeBandIdProvider` | Auto-refresh (log-confirmed) |
| `calendarProvider` | `activeBandIdProvider` | Auto-refresh (log-confirmed) |
| `financialsProvider` | `activeBandIdProvider` | Auto-refresh (pattern-matched, **not** log-confirmed — Tony did not exercise this tab) |
| `currentUserPermissionsProvider` | `activeBandIdProvider` + `authStateProvider` | Auto-refresh — the explicit `ref.invalidate()` is redundant |
| `membersProvider` | *nothing* | Only refreshes via explicit `_invalidateBandScopedProviders()` — currently skipped by the throw |
| `contactsProvider` | *nothing* | Only refreshes via explicit `_invalidateBandScopedProviders()` — currently skipped by the throw |
| `venuesProvider` | *nothing* | Only refreshes via explicit `_invalidateBandScopedProviders()` — currently skipped by the throw |

**Verified against source:**

- `GigNotifier.build()`: [gig_controller.dart#L108-L143](lib/features/gigs/gig_controller.dart#L108-L143)
  watches `bandFullStateProvider`.
- `RehearsalNotifier.build()`: [rehearsal_controller.dart#L102-L131](lib/features/rehearsals/rehearsal_controller.dart#L102-L131)
  watches `bandFullStateProvider`.
- `SetlistsNotifier.build()`: [setlists_screen.dart#L85-L101](lib/features/setlists/setlists_screen.dart#L85-L101)
  watches `activeBandIdProvider`.
- `CalendarNotifier.build()`: [calendar_controller.dart#L172-L195](lib/features/calendar/calendar_controller.dart#L172-L195)
  watches `activeBandIdProvider`.
- `FinancialsNotifier.build()`: [financials_controller.dart#L82-L88](lib/features/financials/financials_controller.dart#L82-L88)
  watches `activeBandIdProvider`.
- `MembersNotifier.build()`: [members_controller.dart#L92-L95](lib/features/members/members_controller.dart#L92-L95)
  returns `const MembersState()` — no watch.
- `ContactsNotifier`, `VenuesNotifier`: same shape — no watch of
  `activeBandIdProvider` anywhere in
  [contacts_controller.dart](lib/features/contacts/contacts_controller.dart) or
  [venues_controller.dart](lib/features/contacts/venues_controller.dart).

**Call sites of `selectBand()`** (all currently affected by the throw):

- [app_shell.dart#L361](lib/features/shell/app_shell.dart#L361) — the primary
  band-switcher entry point (matches Tony's stack trace). The caller *also*
  calls `setTab(0)` on line 363, which is why the tab reset still appears
  to work despite `selectBand()`'s internal `setTab(dashboard)` being skipped.
- [calendar_screen.dart#L188](lib/features/calendar/calendar_screen.dart#L188)
- [home_screen.dart#L173](lib/features/home/home_screen.dart#L173)
- [setlists_screen.dart#L422](lib/features/setlists/setlists_screen.dart#L422)
- [no_band_shell.dart#L710](lib/features/shell/no_band_shell.dart#L710)
- [notification_navigation_handler.dart#L48](lib/features/notifications/notification_navigation_handler.dart#L48)

Only the first caller does its own post-`selectBand` `setTab(0)`. The other
five rely on `selectBand()`'s internal `setTab(NavTabIndex.dashboard)` — which
is currently being skipped by the throw. After the fix these callers will
finally reset to Dashboard on band-switch, which is the intent documented at
[app_shell.dart#L364](lib/features/shell/app_shell.dart#L364) (*"Always
navigate to Dashboard when switching bands"*).

## Proposed Solution

Delete the two synchronous `ref.invalidate(currentUserPermissionsProvider)`
calls that Riverpod's guard rejects. They are redundant: because
`currentUserPermissionsProvider.build()` already `ref.watch`es
`activeBandIdProvider`, Riverpod re-runs it automatically whenever the active
band changes — which the log at each of Tony's five switches already shows
happening for the other four `activeBandIdProvider`-watching providers.

**Not changing:**

- The `ref.invalidate(currentUserPermissionsProvider)` inside
  `loadAndSelectBand()`'s `Future.microtask` block
  ([active_band_controller.dart#L387-L391](lib/features/bands/active_band_controller.dart#L387-L391))
  — it's also redundant, but it currently works and is outside the reported
  crash path. Touching it risks regressing initial-load / deep-link paths
  (auth gate, invite acceptance, demo session, band-form completion) with no
  matching upside. Leave it.
- The `ref.invalidate(currentUserPermissionsProvider)` inside
  `MembersNotifier.updateRole()`
  ([members_controller.dart#L196](lib/features/members/members_controller.dart#L196))
  — different notifier context; no cycle.
- `_invalidateBandScopedProviders()` and its three invalidations
  (members / contacts / venues) — they don't self-refresh and are exactly
  what Tony's log-invisible latent bugs need.
- The 5-provider add-list from the original ticket
  (`gigProvider`, `setlistsProvider`, `calendarProvider`, `financialsProvider`,
  `rehearsalProvider`). Adding any of them to `_invalidateBandScopedProviders()`
  would re-trigger the *same* `CircularDependencyError` shape we're fixing,
  because each of them transitively watches `activeBandIdProvider`. On-device
  evidence contradicts the premise for four of them; the fifth (financials)
  follows the identical code pattern and is expected to behave identically —
  Tony should exercise it once after the fix ships to confirm (see
  Verification Plan → owner-run § FIN-1).

## Database Impact

n/a — pure client-side Riverpod refactor. No migration, no RPC, no RLS change.

## Flutter Architecture Changes

None. This preserves the existing pattern where providers that need
band-scoped auto-refresh watch `activeBandIdProvider` in `build()`, and
providers that don't (members / contacts / venues) are imperatively
invalidated in `_invalidateBandScopedProviders()`. The fix simply removes two
lines that violated the pattern by trying to imperatively invalidate a
provider that already self-refreshes.

## Files to Create

- `test/features/bands/active_band_controller_circular_dependency_test.dart`
  — regression test file. Kept separate from
  [active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart)
  because the setup shape differs materially: this test must actively
  `listen()` to `currentUserPermissionsProvider` to establish the runtime
  dependency edge that the existing test deliberately doesn't, and mixing the
  two setups in one file blurs what each is proving.

## Files to Modify

- [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart)
  — delete two lines (see Engineer Task Breakdown).

## Files Off-Limits

- The five separate "Log Out" implementations in
  [home_screen.dart](lib/features/home/home_screen.dart),
  [calendar_screen.dart](lib/features/calendar/calendar_screen.dart),
  [setlists_screen.dart](lib/features/setlists/setlists_screen.dart),
  [app_shell.dart](lib/features/shell/app_shell.dart),
  [no_band_shell.dart](lib/features/shell/no_band_shell.dart) — explicitly
  called out by Tony as out-of-scope for this ticket.
- All tab-provider files (`gig_controller.dart`, `rehearsal_controller.dart`,
  `setlists_screen.dart`'s `SetlistsNotifier`, `calendar_controller.dart`,
  `financials_controller.dart`) — they already self-refresh correctly per
  the log; touching them would just add another crash surface.
- `band_permissions_provider.dart` — the provider itself is fine; the bug is
  in how it's *invalidated*, not in the provider.
- `_invalidateBandScopedProviders()` — must **not** grow the invalidation
  list per the analysis above.
- The `Future.microtask` block in
  [`loadAndSelectBand()`](lib/features/bands/active_band_controller.dart#L387-L391)
  — separately-working code path; out of scope.

## Change Budget

| File | Expected net line delta |
|---|---|
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) | **−2** (delete two `ref.invalidate(currentUserPermissionsProvider);` lines) |
| [test/features/bands/active_band_controller_circular_dependency_test.dart](test/features/bands/active_band_controller_circular_dependency_test.dart) | **+~110** (new file, two test cases + shared `setUp` + a minimal `_SeededActiveBandNotifier` mirroring the one in the sibling invalidation test — reused pattern, not shared code) |

- Expected new files: **1** (the regression test).
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.

## System Impact Map

| Area | Affected? | Notes |
|---|---|---|
| Gigs | Affected (indirectly, for the better) | Continues to self-refresh via `bandFullStateProvider`; no behaviour change. `currentTabProvider.setTab(dashboard)` inside `selectBand()` will now actually run — for callers other than `app_shell.dart` (which already resets on its own) this means switching bands from the Gigs list now returns the user to Dashboard, matching the intent comment at [app_shell.dart#L364](lib/features/shell/app_shell.dart#L364). |
| Rehearsals | Affected (indirectly, for the better) | Same as Gigs. |
| Setlists | Affected (indirectly, for the better) | `selectedSetlistProvider.clear()` now actually runs on band switch → no cross-band selected-setlist retention. |
| Members / Contacts / Venues | Affected (indirectly, for the better) | `_invalidateBandScopedProviders()` now actually runs → these three providers correctly invalidate on switch, matching what the existing headless test at [active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart) already asserts. |
| Auth | Affected (indirectly, for the better) | `reset()` (invoked from all five Log Out call sites) no longer throws. `currentUserPermissionsProvider` still self-refreshes to `BandPermissions.admin` when `activeBandId` goes null. |
| Routing / Tab | Affected (indirectly, for the better) | See Gigs row. |
| Notifications | Affected (indirectly) | `notification_navigation_handler.dart#L48` awaits `selectBand()` before `Navigator.push`-ing to a detail screen. With the fix, `selectBand()` completes normally and its `setTab(dashboard)` runs *before* the `Navigator.push` — this is fine (the push targets a full-screen route, the tab index is only visible when the user pops back). |
| Deep links | Unaffected | Deep links use `loadAndSelectBand()` (auth_gate, invite_screen, demo_session_service, band_form_screen), not `selectBand()`; that call path is not being modified. |
| Financials | Unaffected by the code change | `FinancialsNotifier.build()` already watches `activeBandIdProvider`; behaviour after the fix is expected to match the log-confirmed gigs/rehearsals/setlists/calendar behaviour. Owner-run check § FIN-1 in the Verification Plan confirms this against a live device. |
| Platforms | Unaffected differentially | Pure Riverpod change — no platform-conditional code touched. iOS, Android, macOS, and web all fix identically. |

## Regression Risk

**LOW.** The fix deletes two lines, both of which currently throw before doing
any useful work. Every downstream provider that previously depended on the
imperative invalidate for freshness already re-runs via
`ref.watch(activeBandIdProvider)` in its own `build()`. The change does not
touch auth, session, routing, init order, or database code. The one class of
observable behaviour change is that side-effects previously skipped by the
throw (SharedPreferences persistence, non-self-refreshing provider
invalidation, selected-setlist clear, dashboard tab-reset from non-shell
callers) will now actually execute — all of them matching the code's
already-documented intent.

## Engineer Task Breakdown

1. **Delete line 338 of
   [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart)**,
   the single line `    ref.invalidate(currentUserPermissionsProvider);`
   inside `selectBand()`. Do not modify any surrounding lines. `selectBand()`
   after this edit reads:

    ```dart
    Future<void> selectBand(Band band) async {
      if (!state.userBands.any((b) => b.id == band.id)) {
        return;
      }

      state = state.copyWith(activeBand: band);

      _invalidateBandScopedProviders();

      ref.read(selectedSetlistProvider.notifier).clear();

      ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);

      await _persistBandId(band.id);
    }
    ```

2. **Delete line 485 of the same file**, the single line
   `    ref.invalidate(currentUserPermissionsProvider);` inside `reset()`.
   `reset()` after this edit reads:

    ```dart
    Future<void> reset() async {
      await _clearPersistedBandId();
      state = const ActiveBandState();
    }
    ```

3. **Do not touch the `import '../members/permissions/band_permissions_provider.dart';` line.**
   The import is still needed by the `ref.invalidate(currentUserPermissionsProvider)`
   call that remains inside `loadAndSelectBand()`'s
   `Future.microtask` block (line 388).

4. **Create the regression test at
   [test/features/bands/active_band_controller_circular_dependency_test.dart](test/features/bands/active_band_controller_circular_dependency_test.dart)**
   with two cases:
    - **Case A — `selectBand does not throw CircularDependencyError`:**
      Build a `ProviderContainer` that overrides
      `activeBandProvider` with a `_SeededActiveBandNotifier` (seeds
      `userBands: [_band1, _band2]`, `activeBand: _band1` — identical shape
      to the one in the sibling
      [active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart#L45))
      **and** overrides `currentUserPermissionsProvider` with an override
      whose callback does `ref.watch(activeBandIdProvider);` and returns
      `BandPermissions.admin` (this preserves the runtime dependency edge
      the guard checks, without needing a Supabase mock). Call
      `container.listen<AsyncValue<BandPermissions>>(currentUserPermissionsProvider, (_, __) {}, fireImmediately: true)`
      to force the provider to build and register the edge. Then
      `await container.read(activeBandProvider.notifier).selectBand(_band2);`
      inside `expectLater(..., completes)` and additionally assert
      `container.read(activeBandProvider).activeBand?.id == _band2.id`.
      Also assert `container.read(activeBandIdProvider) == _band2.id` (proves
      the reactive watch path is intact after the fix).
    - **Case B — `reset does not throw CircularDependencyError`:** Same
      container / same override / same forced listen. Then
      `await container.read(activeBandProvider.notifier).reset();` inside
      `expectLater(..., completes)` and assert
      `container.read(activeBandProvider).activeBand == null`.
    - Use `SharedPreferences.setMockInitialValues({})` in `setUp` (matches
      the sibling test's approach — `reset()` and `selectBand()` both touch
      `_clearPersistedBandId` / `_persistBandId`).

5. **Run `flutter analyze` and `flutter test test/features/bands/`** to
   confirm nothing else was affected. (Engineer runs these, not QA.)

## Verification Plan

### Tier 1 — pre-deploy, mechanically executable by QA

- **T1-A `flutter analyze`** — must complete with zero new warnings or errors
  attributable to the touched files. This catches accidental orphaned imports
  or unused-variable warnings after the two deletions.
- **T1-B `flutter test test/features/bands/active_band_controller_circular_dependency_test.dart`**
  — must pass. Both cases must complete without throwing
  `CircularDependencyError`. If either case fails specifically with the
  `CircularDependencyError` message from Tony's stack trace, the fix has
  regressed.
- **T1-C `flutter test test/features/bands/active_band_controller_invalidation_test.dart`**
  — the existing invalidation test must still pass unchanged. This confirms
  `_invalidateBandScopedProviders()` still runs after the fix (it now
  actually reaches that call instead of being skipped by the throw).
- **T1-D `flutter test test/features/`** — full features test suite must
  pass to catch any incidental regressions (`invite_screen_test.dart` and
  `auth_gate_anonymous_recovery_test.dart` also exercise the notifier).

### Tier 2 — post-deploy, mechanically executable

n/a — no server-side migration, RPC, or edge-function change. All
verification is Tier 1 or owner-run.

### Owner-run at PR-test / apply time — Tony reproduces on a real device

QA hands this punch list to Tony verbatim. QA does not attempt these — they
require the app to actually be running, which QA's environment cannot do.

- **CRASH-1 (Primary — confirms the fix)**
  1. Run the app on the same physical device Tony used for the original
     repro, with the debug console attached.
  2. Sign in and land on the Home / Dashboard.
  3. Open the band switcher.
  4. Tap 5 different bands in sequence (matching the original repro).
  5. **Expected:** the debug console shows **zero** `CircularDependencyError`
     lines and **zero** `Unhandled Exception:` lines with a `dart_vm_initializer`
     preamble across all 5 switches. `[GigController] resetForBandChange`
     and the per-tab RPC / fetch log lines still appear as they did in the
     original log.

- **CRASH-2 (Persistence)**
  1. From CRASH-1's final state (some band X now active).
  2. Fully force-quit the app (swipe-close on iOS / stop from IDE / equivalent).
  3. Cold-launch the app again.
  4. **Expected:** the app opens with band X still active (proves the
     `await _persistBandId(band.id)` line inside `selectBand()` now
     actually runs).

- **CRASH-3 (Members / Contacts / Venues no longer stale)**
  1. Cold-start, active band = band A.
  2. Open the Members tab and note the visible list of member names.
  3. Open the band switcher and switch to band B.
  4. Open the Members tab.
  5. **Expected:** the Members tab shows band B's members (a different set
     from step 2), not band A's cached members. Repeat the same three-step
     check for the Contacts and Venues tabs.

- **CRASH-4 (Selected-setlist clear)**
  1. Cold-start, active band = band A.
  2. Open the Setlists tab and tap into any setlist so it becomes the
     currently-selected one.
  3. Open the band switcher and switch to band B.
  4. Return to the Setlists tab.
  5. **Expected:** no cross-band selected-setlist state remains — the
     Setlists tab shows band B's setlist list at its root, not band A's
     detail screen.

- **CRASH-5 (Non-shell caller tab reset)**
  1. Cold-start, active band = band A. Navigate to the Calendar tab
     (index != 0).
  2. Open the band switcher from within the Calendar tab and switch to
     band B.
  3. **Expected:** the app returns to the Dashboard tab, matching the
     intent documented at
     [app_shell.dart#L364](lib/features/shell/app_shell.dart#L364).

- **FIN-1 (Financials — the one provider Tony didn't exercise in the
  original log)**
  1. Cold-start, active band = band A that has at least one financial entry.
  2. Open the Financials tab and note the visible entries.
  3. Open the band switcher and switch to band B (a band with different
     financial entries — or none).
  4. Open the Financials tab.
  5. **Expected:** band B's entries are shown, not band A's. If band A's
     entries still appear, that's the same-shape self-refresh gap that
     was NOT observable in the original log — file it as a follow-up
     ticket (add `financialsProvider` to
     `_invalidateBandScopedProviders()` would then be the fix, and would
     be safe *because the CircularDependencyError root cause is fixed
     first by this ticket*).

## QA Regression Areas

QA reviews (mechanically, without running the app):

- **Static SQL / migration review:** n/a — no SQL touched.
- **[active_band_controller.dart](lib/features/bands/active_band_controller.dart)
  diff review:** confirm the diff contains exactly two line deletions, both
  of `ref.invalidate(currentUserPermissionsProvider);`, in `selectBand()`
  and `reset()`. No other lines in this file should be touched. If the diff
  contains any other change to this file, flag it — Warning (needs
  justification) or Critical if it touches `_invalidateBandScopedProviders`
  / `loadAndSelectBand` / import block / new methods.
- **Change Budget check:** actual `git diff --stat` for
  `active_band_controller.dart` must show `2 deletions` (or as close as line
  counting on adjacent blank lines gets). Larger diffs indicate scope creep.
  New test file line count within roughly ±30 of the +110 estimate.
- **No new dependencies:** `pubspec.yaml` and `pubspec.lock` must be
  unchanged.
- **No touched off-limits files:** run `git diff --name-only main...HEAD` —
  the changed-files list must be exactly:
  1. `lib/features/bands/active_band_controller.dart`
  2. `test/features/bands/active_band_controller_circular_dependency_test.dart`
  Nothing else. Any additional file is a scope violation.
- **Existing test suite unchanged:** the sibling test at
  [active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart)
  must not be modified — it validates a distinct behaviour (`_invalidateBandScopedProviders`
  fires the three imperative invalidations) and after the fix it should now
  *actually* pass for the right reason (the path runs to completion) rather
  than for the wrong reason (short-circuit before the throw was previously
  irrelevant because nothing in that test container triggered the guard).

## Rollout Strategy

- Standard PR → review → merge → auto-deploy to production over the normal
  channel. No feature flag. No migration. No coordinated infra step.
- Because `reset()` is called from all five Log Out call sites, and the fix
  changes those from "throws then silently persists no-op" to "cleanly runs
  to completion", the first cold-boot after deployment for any active user
  will see `currentUserPermissionsProvider` self-refresh once as the
  activeBandId transitions to null — this is a normal reactive re-run and
  needs no coordination.
- Rollback path: git-revert the PR. Because the two deleted lines were
  causing an unhandled exception that the app was already surviving via the
  top-level zone handler, reintroducing them via revert would return the app
  to its currently-shipping (imperfect but functional) behaviour without
  any migration or data implications.

## Out of Scope

- The five separate "Log Out" implementations across `home_screen.dart`,
  `calendar_screen.dart`, `setlists_screen.dart`, `app_shell.dart`, and
  `no_band_shell.dart` — explicitly called out by Tony as out-of-scope in
  both the original ticket and the updated brief.
- Consolidating or removing the redundant
  `ref.invalidate(currentUserPermissionsProvider)` inside
  `loadAndSelectBand()`'s `Future.microtask` block — untouched code path,
  currently working, not in the reported crash trace.
- Adding any of `gigProvider` / `setlistsProvider` / `calendarProvider` /
  `financialsProvider` / `rehearsalProvider` to
  `_invalidateBandScopedProviders()` — on-device evidence contradicts the
  premise, and adding any of them would re-trigger the same self-dependency
  guard.
- Refactoring `MembersNotifier` / `ContactsNotifier` / `VenuesNotifier` to
  `ref.watch(activeBandIdProvider)` in `build()` so they self-refresh (which
  would remove the need for `_invalidateBandScopedProviders()` entirely) —
  a plausible follow-up, but requires touching three unrelated features and
  their tests, and isn't needed to fix the reported crash.
- Extending the existing test at
  [active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart)
  to also cover the guard scenario — kept as a separate file because the
  setup shapes (with vs. without a live `currentUserPermissionsProvider`
  listener) prove different things and are clearer apart.
