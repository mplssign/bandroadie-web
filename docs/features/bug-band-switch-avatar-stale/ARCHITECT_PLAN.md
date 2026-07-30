# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/band-switch-avatar-stale`

---

## 2. Problem Summary

Nav bar profile avatar (top-right of the header, `HomeAppBar`/`CalendarAppBar`/`SetlistsAppBar` → `BandAvatar`) intermittently continues showing the previously-active band's avatar after switching bands. Not reproducible on every switch — periodic/timing-dependent.

The Feature Input's suspected root cause was the documented known issue in `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` (§C2, "Band switching does NOT reset all band-scoped state — `ref.invalidate()` not called in `selectBand()`"). This investigation confirms that specific issue is **already fixed** and is not the current cause. See §3.

---

## 3. Root Cause

**Confidence: `MEDIUM`**

### 3.1 The originally-suspected defect is already fixed — ruled out

`lib/features/bands/active_band_controller.dart:320-334` (current `selectBand()`):

```dart
Future<void> selectBand(Band band) async {
  if (!state.userBands.any((b) => b.id == band.id)) {
    return;
  }

  await _persistBandId(band.id);
  state = state.copyWith(activeBand: band);
  ref.invalidate(displayBandProvider);        // <-- already present

  ref.invalidate(currentUserPermissionsProvider);

  ref.read(selectedSetlistProvider.notifier).clear();

  ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
}
```

`ref.invalidate(displayBandProvider)` — the exact call the known-issue note says is missing — is present. Two prior tickets confirm this in detail and should be read as part of this investigation's evidence trail:

- `docs/features/bug/band-switch-stale-avatar/` (ARCHITECT_PLAN.md + ENGINEER_REPORT.md + QA_REPORT.md) — root-caused the original missing-invalidation defect and added this exact line (merged as commit `62e384f`, PR #32, 2026-06-14).
- `docs/features/band-switch-header-stale-state/ARCHITECT_PLAN.md` — a later investigation of a recurrence of this same-looking symptom. It independently confirmed via `git blame`/`git merge-base` that the PR #32 fix is on `main` and untouched since, traced the full `selectBand() → displayBandProvider → HomeTabContent/*TabContent → HomeAppBar/*AppBar → BandAvatar` data flow end-to-end and found no break, and **explicitly investigated and ruled out** a `draftBandProvider`-leak theory (§3.4 of that document) on architectural grounds: `EditBandScreen`/`BandFormScreen` is pushed as a full-screen route via `Navigator.push` on top of `AppShell`, and the band switcher (`BandSwitcherOverlayContent`) is rendered inside `AppShell`'s own `Stack` (confirmed independently in this pass at `lib/features/shell/app_shell.dart:306`) — so the switcher is unreachable while an edit-band draft is in progress, and `BandFormScreen.dispose()` clears the draft on every exit path before the switcher becomes reachable again. That theory does not hold up and is not re-proposed here.

Given two independent investigations confirm the on-record defect is fixed and the full watch chain is intact, this pass did not re-litigate that ground. Only files/paths not already covered by both prior investigations were examined further (see §3.2).

### 3.2 The one confirmed, unresolved timing gap: `selectBand()`'s persist-before-state-update ordering

Both this pass and `band-switch-header-stale-state` (§3.3 of that document) independently landed on the same remaining defect, found directly in code:

```dart
await _persistBandId(band.id);              // <-- async gap BEFORE state mutation
state = state.copyWith(activeBand: band);
ref.invalidate(displayBandProvider);
```

`_persistBandId()` (`active_band_controller.dart:234-245`) calls `SharedPreferences.getInstance()` then `.setString(...)` — both async plugin-channel calls. This means the UI-visible state mutation (`state = state.copyWith(activeBand: band)`, which is what makes `displayBandProvider` — and therefore the header avatar — reflect the new band) does not happen until *after* this disk-I/O round-trip completes.

Every call site invokes `selectBand()` fire-and-forget, not awaited (`home_screen.dart:173`, `calendar_screen.dart:166`, `app_shell.dart:318`, `no_band_shell.dart:712`, `setlists_screen.dart:419`, `notification_navigation_handler.dart:48`). Nothing blocks the UI while this gap is open, so:

- On a fast path (SharedPreferences instance already cached, no plugin-channel contention), the gap is sub-frame and invisible.
- On a slower path (first call this session, private-browsing/web fallback per the `catch` block at `active_band_controller.dart:239-244`, GC pause, or plugin-channel congestion), the gap widens to tens of milliseconds or more, during which the header still renders the *previous* `activeBand` — a visible, but self-correcting, flash of the stale avatar once the state update finally lands one or more frames later.

This matches the Feature Input's actual wording — **"intermittently fails to refresh," "occurs periodically, not on every switch"** — much better than a persistent, non-self-correcting staleness. It is also consistent with `band-switch-header-stale-state`'s own finding (§3.3 of that document), which identified the identical ordering but characterized it as a "brief flash," not the reported symptom's framing at the time (which read as more persistent). This ticket's own phrasing ("periodic," "intermittent") is consistent with that flash, so this investigation proposes fixing it now rather than leaving it as a documented-but-unactioned note a second time.

**As a secondary, related benefit:** because the state mutation currently happens *after* an `await`, two overlapping `selectBand()` invocations (e.g., a rapid double-tap in the band switcher, or a notification-driven `selectBand()` racing a manual tap) can have their async gaps interleave, and whichever call's `_persistBandId` resolves last wins the final `state.copyWith(...)` — not necessarily the band the user tapped last. Moving the state mutation before the `await` closes this too: each invocation's synchronous prefix (up to its own first `await`) runs to completion without yielding, so the state update from a later call can no longer be overwritten by an earlier call's delayed completion.

### 3.3 Why `MEDIUM`, not `HIGH`

The ordering defect is directly observed in code and plausibly explains the reported symptom's timing profile, but it cannot be reproduced or timed from static reading alone — a device/network-dependent flash is not fully provable without a live run. Per `band-switch-header-stale-state`'s own conclusion, no other break exists anywhere in the watch chain for a plain switch. If QA cannot reproduce any improvement after this fix, treat the symptom as still open and follow the diagnostic-capture steps that plan recommended (build provenance, tab/band-count/switch-sequence context, `[ActiveBand]` debug log capture at the moment of switch) rather than re-guessing at a third hypothesis.

---

## 4. Reference Docs Consulted

- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — source of the §C2 known-issue note the Feature Input cites; confirmed stale (fix already shipped, flagged as such by the prior `band-switch-header-stale-state` plan too).
- `docs/features/bug/band-switch-stale-avatar/ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md` — prior fix for the original missing-invalidation defect (PR #32).
- `docs/features/band-switch-header-stale-state/ARCHITECT_PLAN.md` — most recent prior investigation of this same-looking symptom; ruled out the on-record known issue and the `draftBandProvider` theory, flagged the persist-ordering timing note this plan now acts on.
- No `docs/reference/bands/` or `docs/reference/state-management/` directory exists (confirmed by both this pass and the prior one).

---

## 5. Existing System Analysis

Data flow, confirmed unbroken end-to-end (re-verified in this pass, consistent with both prior tickets):

1. User taps a band in `BandSwitcher`/`BandSwitcherOverlayContent` → `onBandSelected(band)` (the tapped band object, no stale-closure risk — `lib/features/home/widgets/band_switcher.dart:166-171`).
2. Caller (varies by screen — `app_shell.dart`, `home_screen.dart`, `calendar_screen.dart`, `setlists_screen.dart`, `no_band_shell.dart`, `notification_navigation_handler.dart`) calls `ref.read(activeBandProvider.notifier).selectBand(band)`, fire-and-forget.
3. `selectBand()`: currently awaits `_persistBandId(band.id)` **before** mutating `state`. This is the confirmed gap (§3.2).
4. `state = state.copyWith(activeBand: band)` fires; `displayBandProvider` (which watches `activeBandProvider` and `draftBandProvider`) is invalidated explicitly and would also be invalidated automatically via Riverpod's dependency graph.
5. Every tab-content file that renders a header (`home_tab_content.dart`, `setlists_tab_content.dart`, `calendar_tab_content.dart`, `contacts_tab_content.dart`, `members_tab_content.dart`) watches `displayBandProvider`/`activeBandProvider` directly via `ref.watch` in its own `build()` and passes `displayBand?.imageUrl ?? activeBand?.imageUrl` etc. into its app bar widget — none read a locally cached copy.
6. `HomeAppBar`/`CalendarAppBar`/`SetlistsAppBar` are plain `ConsumerWidget`s with no local caching; `BandAvatar` is a `StatelessWidget` with no `initState` caching — both re-render fresh from constructor params on every parent rebuild.

No break in this chain other than the timing gap in step 3.

---

## 6. Proposed Solution

Reorder `selectBand()` so the UI-visible state mutation (and the explicit `displayBandProvider` invalidation) happens **synchronously, immediately**, and the SharedPreferences persistence write happens **after**, as a trailing background operation that no longer gates the header update:

```dart
Future<void> selectBand(Band band) async {
  if (!state.userBands.any((b) => b.id == band.id)) {
    return;
  }

  state = state.copyWith(activeBand: band);
  ref.invalidate(displayBandProvider);

  ref.invalidate(currentUserPermissionsProvider);

  ref.read(selectedSetlistProvider.notifier).clear();

  ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);

  await _persistBandId(band.id);
}
```

### Why this is minimal and safe

- One function, four lines moved — no new abstractions, no new files, no signature changes.
- `_persistBandId` has no downstream dependents within `selectBand()` itself — nothing else in the method (or in `loadUserBands()`'s read path) needs the write to have completed before proceeding; it only needs to have been *called* so the value is available on next app launch.
- Removes the interleaving window for overlapping `selectBand()` calls as a side effect (§3.2), with no additional code.
- Does not touch `displayBandProvider`, `BandAvatar`, `HomeAppBar`/`CalendarAppBar`/`SetlistsAppBar`, or any call site — all independently confirmed correct by this and the prior investigation.
- Consistent with the existing "optimistic UI, persist after" pattern already used elsewhere in this controller (e.g., `updateActiveBand()` mutates state directly with no persistence gate at all).

---

## 7. Database Impact

**Database: not applicable.** Client-side Riverpod state ordering only. No RLS, RPC, trigger, or migration involvement.

---

## 8. Flutter Architecture Changes

**Affected:** `ActiveBandNotifier.selectBand()` — statement order only, no new state fields, no new providers, no widget changes.

**Confirmed unaffected (do not touch):** `displayBandProvider`, `BandAvatar`, `HomeAppBar`, `CalendarAppBar`, `SetlistsAppBar`, `draftBandProvider`, `BandFormScreen`, `band_switcher.dart` — all traced and confirmed correct by this pass and/or the prior `band-switch-header-stale-state` pass.

---

## 9. Files to Create

`none`

---

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/bands/active_band_controller.dart` | In `selectBand()` (lines ~320-334): move the `await _persistBandId(band.id);` line from before `state = state.copyWith(activeBand: band);` to after the existing invalidation/reset/navigation statements, so it executes last. No other logic in the method changes. |

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/bands/widgets/band_avatar.dart` | Confirmed correct — stateless, no caching, re-renders fresh every build. Not the defect. |
| `lib/features/home/widgets/home_app_bar.dart`, `lib/features/calendar/widgets/calendar_app_bar.dart`, `lib/features/setlists/widgets/setlists_app_bar.dart` | Confirmed correct — plain `ConsumerWidget`s, all props re-derived from constructor args every rebuild. |
| `lib/features/bands/band_form_screen.dart` | Draft-clear-on-dispose logic confirmed correct and architecturally unreachable as a cause (band switcher unreachable while an edit draft is active — see §3.1). Do not touch. |
| `lib/features/bands/active_band_controller.dart` — `displayBandProvider`, `ActiveBandState.==`/`hashCode` | Already correct; do not modify equality semantics or the provider itself, only the statement order inside `selectBand()`. |
| `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` §C2 | Stale known-issue note (already fixed by PR #32) — flagged for Manager/Tony to update directly; not this plan's job to edit agent/reference docs. |

---

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected — `resetForBandChange()` calls at call sites unchanged |
| Rehearsals | unaffected — `resetForBandChange()` calls at call sites unchanged |
| Setlists / Catalog | unaffected — `selectedSetlistProvider.clear()` still runs, unchanged position in sequence |
| Members / RBAC | unaffected — `currentUserPermissionsProvider` invalidation still runs, unchanged position in sequence |
| Auth / Session | unaffected |
| Routing | unaffected — `currentTabProvider.setTab()` still runs; now runs slightly earlier relative to the persistence write, not relative to anything user-visible |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | all affected equally — `_persistBandId`'s try/catch already handles the web/private-browsing fallback path (`active_band_controller.dart:239-244`); moving its call site doesn't change that behavior, only its timing relative to the rest of the method |
| **Avatar / header display** | **affected — directly fixed** by removing the pre-state-update async gap |

---

## 13. Regression Risk

**Risk level: `LOW`**

- Single statement reordering in one method; no new logic, no new state.
- `_persistBandId` failure handling (try/catch, debug logging) is unchanged — only called later.
- No other method or provider reads `state.activeBand` between the old and new call sites in a way that would observe a difference (nothing in `selectBand()` between those points depends on persistence having completed).
- Two independent Architect passes (this one and `band-switch-header-stale-state`) traced the full watch chain and found nothing else to change.

---

## 14. Engineer Task Breakdown

1. **Modify `selectBand()`** in `lib/features/bands/active_band_controller.dart` (currently lines ~320-334):
   - Remove `await _persistBandId(band.id);` from its current position (first line of the method body, before `state = state.copyWith(...)`).
   - Add it back as the **last statement** in the method, after `ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);`.
   - Keep the `await` keyword and the method's `async` signature — only the statement's position changes.
   - Do not reorder or modify any other line in the method.
2. Run `flutter analyze` — expect 0 errors, 0 warnings.
3. Do not touch any other file listed in §11.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (code inspection + analyzer, no build required)

```dart
// PRE-DEPLOY TEST 1:
// Code inspection — confirm the only change in active_band_controller.dart
// is the position of `await _persistBandId(band.id);` within selectBand().
// Confirm no other statement in the method was reordered, removed, or added.
```

```dart
// PRE-DEPLOY TEST 2:
// Run: flutter analyze
// Expected: 0 errors, 0 warnings in active_band_controller.dart (and repo-wide).
```

### Tier 2 — Post-deployment (manual, on a running build)

```text
// POST-DEPLOY TEST 1:
// Baseline regression: switch between two bands with visibly different
// avatars (different uploaded images or different avatarColor/initials).
// Expected: header (name + avatar) updates immediately every time, same
// as before this change — no functional regression.

// POST-DEPLOY TEST 2:
// Targeted repro attempt for the reported intermittency:
// Perform 15-20 rapid consecutive band switches (tap avatar → tap a
// different band → repeat), including on a throttled/slower test device
// or with iOS Simulator's "Slow Animations" / a throttled network profile
// active if available, to widen any remaining timing windows.
// Expected: avatar and name always match the just-selected band; no flash
// or stale frame of the previous band's avatar is observed.

// POST-DEPLOY TEST 3:
// Rapid double-tap on two different bands in the switcher in quick
// succession (simulating the overlapping-call scenario from §3.2).
// Expected: header settles on whichever band was tapped LAST, not
// whichever band's persistence write happened to finish last.

// POST-DEPLOY TEST 4:
// Cold-start check: force-quit and relaunch the app, confirm the
// previously active band is still restored correctly on launch
// (regression check on _persistBandId / _loadPersistedBandId, since the
// write now happens later in the method but is still awaited before
// selectBand()'s own Future completes).

// POST-DEPLOY TEST 5 (only if TEST 2/3 still show staleness):
// Capture flutter logs / Xcode console output for [ActiveBand] debug
// prints at the moment of a reproduced switch, and note: tab the user
// was on, band count (2 vs 3+), and whether it's the first switch after
// launch or a later one — per band-switch-header-stale-state §6.2. This
// would indicate a different, not-yet-identified cause requiring a new
// Architect pass rather than a variation on this fix.
```

---

## 16. QA Regression Areas

- **Primary:** header avatar + name update immediately and correctly on every band switch, across iOS/Android/Web.
- **No regression:** cold-start band restoration (persisted band ID still written and read correctly, just later in the method).
- **No regression:** permissions re-fetch on switch (`currentUserPermissionsProvider` invalidation — unchanged, still runs).
- **No regression:** setlist selection clearing on switch (`selectedSetlistProvider.clear()` — unchanged, still runs).
- **No regression:** navigation to Dashboard tab on switch (unchanged, still runs).
- **No regression:** gig/rehearsal reset-on-band-change logic at call sites (untouched by this fix).
- **Edge case:** rapid/repeated switching and rapid double-tap on two different bands (see Tier 2 tests 2-3) — must not crash, hang, or leave the header on the wrong band.
- **Edge case:** private-browsing/web `SharedPreferences`-unavailable fallback path — confirm existing debug-log fallback behavior (`active_band_controller.dart:239-244`) still triggers correctly and doesn't block the header update (it shouldn't, since it's now after the UI-visible mutation).

---

## 17. Rollout / Migration Strategy

Single-statement-reorder change, no staged rollout required:

1. Engineer applies the reorder and commits.
2. QA runs Tier 2 manual tests on iOS, Android, and Web.
3. If intermittency is confirmed gone (or was never reproducible in QA's environment to begin with — acceptable, given the symptom is timing-dependent), merge to `main`.
4. If Tier 2 Test 2/3 still shows staleness, do **not** merge — return to Architect with the Test 5 diagnostic data for a new pass, per §3.3.

---

## 18. Out of Scope

- Re-investigating or re-fixing the original missing-`ref.invalidate()` defect — already fixed (PR #32), confirmed present in current code by two independent passes.
- The `draftBandProvider`/`BandFormScreen.dispose()` theory — investigated and ruled out architecturally by the prior `band-switch-header-stale-state` pass, independently re-verified in this pass (`app_shell.dart:306` confirms the switcher lives inside `AppShell`'s `Stack`, below any pushed `EditBandScreen` route).
- Broader `ref.invalidate()` sweep across all band-scoped providers (setlists, gigs, rehearsals, members) per the stale `BAND_ROADIE_DOCUMENTATION.md` §C2 note — those already have call-site-level resets (`resetForBandChange()`, `selectedSetlistProvider.clear()`) and are not implicated in this specific avatar symptom. Not touched here.
- Updating `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`'s stale §C2 entry — flagged for Tony/Manager, not an Architect-pass code task.
- Adding a sequence token / generation counter to guard against overlapping `selectBand()` calls beyond what the reorder already provides — not needed once the state mutation is moved ahead of the only `await` in the method (see §3.2).

---

## Stop-and-Escalate Conditions

None triggered. Root cause confidence is `MEDIUM` (not `LOW`), the fix is minimal and independently corroborated by two Architect passes' worth of evidence, and regression risk is `LOW`.

If Tier 2 Test 2 or 3 still reproduces staleness after this fix ships, escalate per §17 rather than attempting a third hypothesis without new diagnostic data.
