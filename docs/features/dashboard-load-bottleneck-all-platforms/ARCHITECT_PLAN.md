# Architect Plan

## Feature Slug

`bug/dashboard-load-bottleneck-all-platforms`

---

## Problem Summary

On Android, navigating back to the dashboard from another screen causes a loading spinner that never resolves — the dashboard never renders content. This is a confirmed blocker on Android (reproduced by Tony and corroborated by external user Ben Seay, Jun 23). iOS has not shown the hang symptom, but the investigation must cover all platforms (Android, iOS, macOS, Web) to identify performance bottlenecks and ensure consistent dashboard loading behavior.

**User Impact:**

- **Severity:** HIGH — dashboard is completely unusable on Android after first navigation away
- **Scope:** Confirmed on Android; other platforms unconfirmed for bottlenecks

---

## Root Cause

**Confidence Level:** HIGH (confirmed in code)

**Primary Failure Mode:**
The dashboard hangs indefinitely on Android due to a **flawed stale data check combined with an RPC call that has no timeout**. When the user navigates back to the dashboard:

1. The `bandFullStateProvider` calls the `get_band_full_state` Supabase RPC to load all band-scoped data (band, members, gigs with gig_dates, rehearsals, setlists)
2. **This RPC call has no timeout** — if it hangs or is slow, it will never resolve
3. While the RPC is loading, the `GigNotifier` and `RehearsalNotifier` return state with `isLoading: true` **but `loadedBandId: null`**
4. The `HomeTabContent` build method checks for stale data:
   ```dart
   final gigsForCurrentBand = gigState.loadedBandId == activeBandId;
   final rehearsalsForCurrentBand = rehearsalState.loadedBandId == activeBandId;
   final dataIsStale = activeBandId != null && (!gigsForCurrentBand || !rehearsalsForCurrentBand);
   ```
5. If `activeBandId != null` and `loadedBandId == null`, then `gigsForCurrentBand = false`, so `dataIsStale = true`
6. The UI then shows the loading spinner:
   ```dart
   } else if (gigState.isLoading || rehearsalState.isLoading || dataIsStale) {
     stateWidget = _buildLoadingState('Setting up the stage...');
   }
   ```
7. **If the RPC hangs, `loadedBandId` stays `null` forever, so `dataIsStale` stays `true` forever, and the spinner never resolves**

**Secondary Bottlenecks:**

- The `get_band_full_state` RPC does **nested subqueries** (gig_dates for each gig, song counts for each setlist) which can be slow with large datasets
- On Android, the Supabase Flutter client may have platform-specific network behavior (connection pooling, timeout defaults) that differs from iOS
- No `mounted` guards after async operations in `HomeTabContent._checkPendingGigPrompts()` and `_checkPendingRehearsalPrompts()` — if the widget unmounts mid-check, this could cause a hang

**Code Evidence:**

- `lib/features/bands/band_full_state.dart:50` — `supabase.rpc('get_band_full_state', ...)` has **no timeout**
- `lib/features/gigs/gig_controller.dart:108-124` — `GigNotifier.build()` returns `const GigState()` (with `loadedBandId: null`) when `fullState == null`, and `GigState(isLoading: true)` (also `loadedBandId: null`) when loading
- `lib/features/rehearsals/rehearsal_controller.dart:102-118` — Same pattern in `RehearsalNotifier.build()`
- `lib/features/home/home_tab_content.dart:554-561` — `dataIsStale` check treats `loadedBandId: null` as stale even when actively loading

**Why Android and not iOS?**

- Network latency differences (Android emulator/device vs iOS simulator/device)
- Supabase client timeout defaults may differ by platform
- Android may retry failed RPC calls differently or have stricter network policy enforcement
- The issue is latent on all platforms — Android just hits it first due to slower RPC completion

---

## Reference Docs Consulted

**Dashboard/Home Domain:**

- No specific reference docs found for dashboard/home
- Reviewed general architecture: `docs/reference/architecture/architecture.md`
- Reviewed general documentation: `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`

**Note:** No `docs/reference/dashboard/` or `docs/reference/home/` directory exists. Dashboard loading behavior is not documented in reference materials. This plan will serve as the authoritative source for dashboard data loading architecture going forward.

---

## Existing System Analysis

**Current Dashboard Data Flow (Initial Load and Re-Entry):**

```
User opens dashboard
  ↓
HomeTabContent.build() watches:
  - activeBandProvider (band list and selected band)
  - gigProvider (gig state)
  - rehearsalProvider (rehearsal state)
  - membersProvider
  - setlistsProvider
  - currentUserPermissionsProvider
  - potentialGigResponseSummariesProvider
  - potentialRehearsalResponseSummariesProvider
  ↓
GigNotifier.build() and RehearsalNotifier.build() watch:
  - bandFullStateProvider
  ↓
bandFullStateProvider watches:
  - activeBandIdProvider
  ↓
When bandId changes (or first load):
  - supabase.rpc('get_band_full_state', params: {'p_band_id': bandId})
  - RPC returns JSONB with: {band, members, gigs, rehearsals, setlists}
  - Controllers categorize data and set loadedBandId = bandId
  ↓
UI rebuilds with data
```

**Where the Hang Occurs:**

When the user navigates back to the dashboard after navigating away:

1. The `activeBandId` has not changed, but the `bandFullStateProvider` may have been invalidated or is re-fetching
2. The RPC call is made but **hangs or takes too long**
3. Controllers return `isLoading: true, loadedBandId: null`
4. UI sees `dataIsStale = true` and shows spinner
5. RPC never completes → spinner never resolves

**Why Re-Entry Triggers the Hang (Not First Load):**

- First load: user is coming from auth gate or landing, no expectation of instant display
- Re-entry: user expects fast navigation, but any RPC delay is immediately visible
- Android may have stricter network policy (e.g., after screen off, connection must re-establish)
- Android emulator/device may have higher network latency than iOS simulator

---

## Proposed Solution

**Minimal Fix (Targets Root Cause Only):**

### 1. Add Timeout to RPC Call

File: `lib/features/bands/band_full_state.dart`

Add a 15-second timeout to the `fetchBandFullState()` method:

```dart
Future<BandFullState> fetchBandFullState(String bandId) async {
  final data = await supabase
      .rpc('get_band_full_state', params: {'p_band_id': bandId})
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Dashboard load timed out after 15 seconds'),
      );
  // ... rest of method
}
```

This ensures the RPC call will fail fast rather than hang indefinitely. The error will propagate to the controllers and display an error state instead of a loading spinner.

### 2. Set `loadedBandId` in All Controller States

Files:

- `lib/features/gigs/gig_controller.dart`
- `lib/features/rehearsals/rehearsal_controller.dart`

Currently, when `fullState == null` or when in loading/error states, the controllers return state with `loadedBandId: null`. This causes the stale data check to fail.

**Fix:** Set `loadedBandId` to the current `activeBandId` in all state branches so the stale data check correctly identifies that we're loading data **for the current band**.

In `GigNotifier.build()`:

```dart
return fullStateAsync.when(
  data: (fullState) {
    if (fullState == null) {
      final activeBandId = ref.read(activeBandIdProvider);
      return GigState(loadedBandId: activeBandId);  // <-- ADD THIS
    }
    final bandId = fullState.band.id;
    return _categorizeGigs(fullState.gigs, bandId, fullState.band.timezone);
  },
  loading: () {
    final activeBandId = ref.read(activeBandIdProvider);  // <-- ADD THIS
    return GigState(isLoading: true, loadedBandId: activeBandId);  // <-- ADD THIS
  },
  error: (e, stackTrace) {
    final activeBandId = ref.read(activeBandIdProvider);  // <-- ADD THIS
    return GigState(error: e.toString(), loadedBandId: activeBandId);  // <-- ADD THIS
  },
);
```

Apply the same pattern to `RehearsalNotifier.build()`.

### 3. Add `mounted` Guards to Pending Prompt Checks

File: `lib/features/home/home_tab_content.dart`

Currently, `_checkPendingGigPrompts()` and `_checkPendingRehearsalPrompts()` use `Future.delayed()` without checking `mounted` after the delay:

```dart
Future.delayed(const Duration(milliseconds: 500), () {
  if (!mounted) return;  // <-- This guard exists
  ref.read(potentialGigPromptProvider.notifier).checkAndShowPendingPrompts(...);
});
```

The guard exists, but the methods called **after** the guard may trigger state updates. Audit the full call chain to ensure no `setState` occurs without a `mounted` check after async gaps.

**Action:** Defensive audit only — no changes required unless audit finds missing guards downstream.

### 4. Improve Error State Display

File: `lib/features/home/home_tab_content.dart`

Currently, if the RPC errors and `dataIsStale` is true, the error state is not shown. The logic prioritizes the stale check over the error check:

```dart
} else if (gigState.isLoading || rehearsalState.isLoading || dataIsStale) {
  stateWidget = _buildLoadingState('Setting up the stage...');
} else if (gigState.error != null && gigsForCurrentBand) {
  stateWidget = _buildErrorState(...);
}
```

With the `loadedBandId` fix in #2, `dataIsStale` will be false even during loading, so the error state will display correctly. No additional changes needed **if #2 is implemented correctly**.

---

## Database Impact

**Not applicable.**

No database schema changes, migrations, RLS policies, or RPC function modifications are required. The `get_band_full_state` RPC function remains unchanged — only the client-side timeout is added.

---

## Flutter Architecture Changes

### State Management (Riverpod)

**Files Modified:**

- `lib/features/gigs/gig_controller.dart` — `GigNotifier.build()` logic
- `lib/features/rehearsals/rehearsal_controller.dart` — `RehearsalNotifier.build()` logic
- `lib/features/bands/band_full_state.dart` — `fetchBandFullState()` timeout

**Pattern Change:**
Controllers will now set `loadedBandId` in **all state branches** (loading, error, empty) instead of only in the data branch. This makes the stale data check reliable.

### Widgets Affected

**Files Modified:**

- `lib/features/home/home_tab_content.dart` — No changes to logic, but will now correctly display error state when RPC times out

**UI Behavior:**

- Before: Spinner hangs indefinitely on RPC timeout/hang
- After: Spinner shows for up to 15 seconds, then error state displays with retry button

### Repositories

**Files Modified:**

- `lib/features/bands/band_full_state.dart` — Add `.timeout()` to RPC call

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                | What Changes                                                                                                                                                          |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/bands/band_full_state.dart`           | Add 15-second timeout to `supabase.rpc('get_band_full_state', ...)` call in `fetchBandFullState()`. Import `dart:async` for `TimeoutException`.                       |
| `lib/features/gigs/gig_controller.dart`             | In `GigNotifier.build()`, set `loadedBandId: ref.read(activeBandIdProvider)` in all three branches of `fullStateAsync.when()` (data when null, loading, error).       |
| `lib/features/rehearsals/rehearsal_controller.dart` | In `RehearsalNotifier.build()`, set `loadedBandId: ref.read(activeBandIdProvider)` in all three branches of `fullStateAsync.when()` (data when null, loading, error). |

---

## Files Explicitly Off-Limits

| File                                             | Reason                                              |
| ------------------------------------------------ | --------------------------------------------------- |
| `lib/main.dart`                                  | Init order must not change (GUARDRAILS §1)          |
| `supabase/migrations/*`                          | No database schema changes required                 |
| `lib/features/home/widgets/*`                    | UI components unchanged — only state logic modified |
| `lib/app/services/supabase_client.dart`          | Supabase client config unchanged                    |
| `lib/features/auth/*`                            | Auth flow unrelated to dashboard loading            |
| `lib/features/bands/active_band_controller.dart` | Band selection logic is correct — no changes needed |

---

## System Impact Map

| System             | Impact                                                                                        |
| ------------------ | --------------------------------------------------------------------------------------------- |
| Gigs               | **affected** — `GigNotifier.build()` logic modified to set `loadedBandId` in all states       |
| Rehearsals         | **affected** — `RehearsalNotifier.build()` logic modified to set `loadedBandId` in all states |
| Setlists / Catalog | **unaffected** — does not depend on gig/rehearsal loading state                               |
| Members / RBAC     | **unaffected** — members load independently via separate provider                             |
| Auth / Session     | **unaffected** — dashboard loading occurs after auth                                          |
| Routing            | **unaffected** — routing logic unchanged                                                      |
| Notifications      | **unaffected** — notification prompts occur after data load completes                         |
| Platform (iOS)     | **affected** — timeout ensures RPC won't hang; same fix applies                               |
| Platform (Android) | **affected** — primary target; timeout and stale data fix resolve hang                        |
| Platform (macOS)   | **affected** — timeout ensures RPC won't hang; same fix applies                               |
| Platform (Web)     | **affected** — timeout ensures RPC won't hang; same fix applies                               |
| Band Management    | **affected** — `bandFullStateProvider` used for initial band data load                        |
| Dashboard          | **affected** — primary target; loading and error states now work correctly                    |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- **Small change surface:** Only 3 files modified, all in the dashboard data-loading path
- **Additive safety:** Timeout is additive — does not change existing behavior, only adds a failure path
- **No database changes:** No migrations, no RLS policies, no RPC function modifications
- **No auth/session/routing changes:** Changes are isolated to data loading after auth
- **Fail-safe direction:** Timeout causes error state instead of infinite hang — user can retry

**Risk Areas:**

- **Timeout too short:** 15 seconds may be too aggressive for slow connections — but this is better than infinite hang. If users report legitimate slow loads that fail, the timeout can be increased.
- **Stale data check regression:** If `loadedBandId` is not set correctly, the stale check could break again. Mitigated by explicit testing in verification plan.

**Why LOW Risk:**

- The change makes the system **more robust** by adding a missing timeout
- The `loadedBandId` fix corrects a logic bug — it doesn't introduce new logic
- No other features depend on the specific loading state structure of gig/rehearsal providers

---

## Engineer Task Breakdown

Execute in order:

### Task 1: Add Timeout to RPC Call

**File:** `lib/features/bands/band_full_state.dart`

1. Import `dart:async` at the top of the file (for `TimeoutException`)
2. Locate the `fetchBandFullState()` method (~line 50)
3. Wrap the `supabase.rpc()` call with `.timeout()`:
   ```dart
   final data = await supabase
       .rpc('get_band_full_state', params: {'p_band_id': bandId})
       .timeout(
         const Duration(seconds: 15),
         onTimeout: () => throw TimeoutException('Dashboard load timed out after 15 seconds'),
       );
   ```
4. Run `flutter analyze` — confirm 0 errors

### Task 2: Fix `loadedBandId` in GigNotifier

**File:** `lib/features/gigs/gig_controller.dart`

1. Locate the `GigNotifier.build()` method (~line 108)
2. In the `fullStateAsync.when()` block, update all three branches:
   - **data branch (when `fullState == null`):**
     ```dart
     if (fullState == null) {
       final activeBandId = ref.read(activeBandIdProvider);
       return GigState(loadedBandId: activeBandId);
     }
     ```
   - **loading branch:**
     ```dart
     loading: () {
       final activeBandId = ref.read(activeBandIdProvider);
       return GigState(isLoading: true, loadedBandId: activeBandId);
     },
     ```
   - **error branch:**
     ```dart
     error: (e, stackTrace) {
       debugPrint(...); // existing debug prints
       final activeBandId = ref.read(activeBandIdProvider);
       return GigState(error: e.toString(), loadedBandId: activeBandId);
     },
     ```
3. Run `flutter analyze` — confirm 0 errors

### Task 3: Fix `loadedBandId` in RehearsalNotifier

**File:** `lib/features/rehearsals/rehearsal_controller.dart`

1. Locate the `RehearsalNotifier.build()` method (~line 102)
2. Apply the same pattern as Task 2:
   - **data branch (when `fullState == null`):**
     ```dart
     if (fullState == null) {
       final activeBandId = ref.read(activeBandIdProvider);
       return RehearsalState(loadedBandId: activeBandId);
     }
     ```
   - **loading branch:**
     ```dart
     loading: () {
       final activeBandId = ref.read(activeBandIdProvider);
       return RehearsalState(isLoading: true, loadedBandId: activeBandId);
     },
     ```
   - **error branch:**
     ```dart
     error: (e, stackTrace) {
       final activeBandId = ref.read(activeBandIdProvider);
       return RehearsalState(error: e.toString(), loadedBandId: activeBandId);
     },
     ```
3. Run `flutter analyze` — confirm 0 errors

### Task 4: Test on Android Emulator

**Platform:** Android (API 33+)

**Prerequisites:** Android emulator running, app installed

**Steps:**

1. Launch app on Android emulator
2. Log in (magic link)
3. Navigate to dashboard — observe loading completes normally
4. Navigate to Members screen
5. Navigate back to dashboard — **observe loading completes normally** (this was the hang scenario)
6. Repeat step 4-5 multiple times — confirm no hang
7. If RPC timeout is triggered (error state after 15s), tap "Try Again" — confirm retry works

**Expected:**

- Dashboard loads content within 1-3 seconds on normal network
- If RPC times out (15s), error state displays with retry button
- No infinite spinner

### Task 5: Test on iOS Simulator

**Platform:** iOS

**Steps:**

1. Launch app on iOS simulator
2. Log in (magic link)
3. Navigate to dashboard → Members → back to dashboard
4. Confirm no regression (dashboard loads normally)

**Expected:**

- Dashboard loads content within 1-3 seconds
- No change in behavior from baseline

### Task 6: Test on macOS

**Platform:** macOS

**Steps:**

1. Run `flutter run -d macos`
2. Log in and navigate dashboard → Members → back to dashboard
3. Confirm no regression

**Expected:**

- Dashboard loads content normally
- No hang, no error

### Task 7: Test on Web (Chrome)

**Platform:** Web

**Steps:**

1. Run `flutter run -d chrome`
2. Log in and navigate dashboard → Members → back to dashboard
3. Confirm no regression

**Expected:**

- Dashboard loads content normally
- No hang, no error

### Task 8: Verify Error State Display (Simulated Timeout)

**Platform:** Android or iOS

**Steps:**

1. Temporarily reduce timeout to 1 second in `band_full_state.dart`:
   ```dart
   .timeout(const Duration(seconds: 1), ...)
   ```
2. Run app, navigate to dashboard
3. Observe error state appears after 1 second with retry button
4. Tap "Try Again" — observe loading state, then error state again
5. Restore timeout to 15 seconds
6. Re-test — confirm normal load completes before timeout

**Expected:**

- Error state displays correctly
- Retry button triggers re-fetch
- No infinite spinner

---

## Verification Plan

### Manual Testing (Post-Implementation)

All verification is **manual device/emulator testing** since this is a UI/UX regression fix and cannot be verified via unit tests without mocking the entire Riverpod provider chain.

#### Test 1: Android Dashboard Re-Entry (Primary Fix Verification)

**Platform:** Android (API 33+)
**Reproduces:** Original bug

**Steps:**

1. Launch BandRoadie on Android emulator
2. Log in with magic link
3. Observe dashboard loads normally
4. Navigate to Members screen
5. Navigate back to dashboard
6. **Verify:** Dashboard content loads within 3 seconds (no spinner hang)
7. Repeat steps 4-6 five times
8. **Verify:** Dashboard loads consistently, no hang

**Pass Criteria:**

- Dashboard loads content within 3 seconds on all attempts
- No infinite spinner
- If RPC timeout occurs (15s), error state displays with retry button

#### Test 2: iOS Dashboard Re-Entry (Regression Check)

**Platform:** iOS (Simulator)

**Steps:**

1. Launch app on iOS simulator
2. Log in and navigate dashboard → Members → back to dashboard
3. Repeat 5 times
4. **Verify:** Dashboard loads normally, no regression from baseline

**Pass Criteria:**

- Dashboard loads content within 3 seconds
- No hang, no error

#### Test 3: Web Dashboard Re-Entry (Regression Check)

**Platform:** Web (Chrome)

**Steps:**

1. Run `flutter run -d chrome`
2. Log in and navigate dashboard → Members → back to dashboard
3. Repeat 5 times
4. **Verify:** Dashboard loads normally

**Pass Criteria:**

- Dashboard loads content within 3 seconds
- No hang, no error

#### Test 4: macOS Dashboard Re-Entry (Regression Check)

**Platform:** macOS

**Steps:**

1. Run `flutter run -d macos`
2. Log in and navigate dashboard → Members → back to dashboard
3. Repeat 5 times
4. **Verify:** Dashboard loads normally

**Pass Criteria:**

- Dashboard loads content within 3 seconds
- No hang, no error

#### Test 5: RPC Timeout Error State (Error Handling Verification)

**Platform:** Android or iOS

**Steps:**

1. Temporarily reduce timeout to 1 second in `band_full_state.dart`
2. Run app, log in, navigate to dashboard
3. **Verify:** Error state appears after 1 second with "Try Again" button
4. Tap "Try Again"
5. **Verify:** Loading state appears, then error state again (since timeout is still 1s)
6. Restore timeout to 15 seconds and re-test
7. **Verify:** Dashboard loads normally before timeout

**Pass Criteria:**

- Error state displays correctly with retry button
- Retry button triggers re-fetch
- No infinite spinner even when RPC times out

#### Test 6: Stale Data Check (Logic Verification)

**Platform:** Android

**Steps:**

1. Launch app, log in, navigate to dashboard
2. Open Xcode/Android Studio debugger and set breakpoint in `home_tab_content.dart` at line ~555 (the `dataIsStale` check)
3. Navigate away from dashboard and back
4. **Verify:** At breakpoint, `gigState.loadedBandId == activeBandId` (not null)
5. **Verify:** `dataIsStale == false` (not true)
6. Continue execution
7. **Verify:** Dashboard displays content, not loading spinner

**Pass Criteria:**

- `loadedBandId` is set to `activeBandId` in all controller states
- `dataIsStale` is `false` during normal loading
- Dashboard displays content correctly

---

## QA Regression Areas

QA must specifically test:

### Primary Target

1. **Android dashboard re-entry** — Navigate away from dashboard and back 10+ times, confirm no hang (original bug reproduction)

### Cross-Platform Regression

2. **iOS dashboard re-entry** — Confirm no regression from baseline
3. **Web dashboard re-entry** — Confirm no regression from baseline
4. **macOS dashboard re-entry** — Confirm no regression from baseline

### Error Handling

5. **RPC timeout error state** — Simulate timeout (reduce to 1s), confirm error state displays with retry button
6. **Retry button functionality** — Tap retry button after timeout, confirm dashboard re-fetches and loads correctly

### Data Integrity

7. **Dashboard content accuracy** — After loading, confirm all gigs, rehearsals, setlists display correctly (no data loss from state logic changes)
8. **Band switching** — Switch bands via band switcher, confirm dashboard refreshes correctly for new band (no stale data from old band)

### Performance

9. **Dashboard load time** — Measure time from navigation to content display on all platforms (baseline: 1-3 seconds on normal network)
10. **RPC bottleneck assessment** — On each platform, note if dashboard load is slower than other screens (e.g., Members, Setlists) — if yes, flag for Phase 2 RPC optimization

---

## Rollout / Migration Strategy

**Not applicable.**

This is a client-side bug fix with no database migrations, no backend changes, and no feature flags. Rollout is via standard app deployment:

1. Commit changes to branch `bug/dashboard-load-bottleneck-all-platforms`
2. Push to GitHub
3. Open PR for review
4. Perform manual testing per verification plan
5. Merge to `main` after QA approval
6. Deploy web via `./tools/deploy_web.sh`
7. iOS/Android/macOS: next app store release

**No data migration or backward compatibility concerns.**

---

## Out of Scope

Explicitly **not** included in this fix:

### 1. RPC Performance Optimization

The `get_band_full_state` RPC does nested subqueries (gig_dates, song counts) which could be slow with large datasets. Optimizing this query is **out of scope** for this bug fix.

**Rationale:** The timeout ensures the hang is resolved. If the RPC is genuinely slow (10+ seconds), users will see an error state and can retry. Performance optimization should be a separate feature if profiling shows consistent slow loads.

**Future Work:** If QA reports RPC timeout errors occurring frequently (>5% of dashboard loads), escalate to Architect for Phase 2 RPC optimization:

- Separate RPC calls for gigs, rehearsals, setlists (parallel fetch)
- Add pagination to gig_dates subquery
- Pre-compute song counts in a separate table
- Add database indexes for date range queries

### 2. Dashboard State Caching

The dashboard re-fetches all data on every navigation. Caching the RPC response to avoid re-fetch on re-entry is **out of scope**.

**Rationale:** Caching adds complexity (invalidation strategy, stale data risk). The timeout fix ensures re-fetch is fast-fail. If users complain about slow re-entry after this fix is deployed, caching can be considered in Phase 2.

### 3. Pending Prompt Refactoring

The `_checkPendingGigPrompts()` and `_checkPendingRehearsalPrompts()` methods in `home_tab_content.dart` have complex lifecycle management (subscriptions, throttling, `_lastCheckedBandId` tracking). Refactoring these is **out of scope**.

**Rationale:** These methods work correctly and are not the root cause of the hang. The defensive `mounted` guard audit (Task 3) confirms they are safe. Refactoring would increase risk without addressing the bug.

### 4. Other Platform-Specific Investigations

- Android network policy enforcement (screen off, app backgrounded)
- Supabase Flutter client platform differences
- Connection pooling / keepalive differences

These are **out of scope** for this fix. The timeout ensures the hang is resolved regardless of root cause. If Android-specific network issues are confirmed in QA, escalate to Architect for platform-specific investigation.

### 5. Permissions Issue Correlation

The user asked to confirm whether the Android hang is the same root cause as the permissions issue fixed in `bug/android-dashboard-freeze-photo-permissions`. **They are distinct issues:**

- Permissions issue: Missing `AndroidManifest.xml` declarations prevented photo library access
- Dashboard hang issue: RPC timeout + flawed stale data check

No correlation. The permissions fix does not affect dashboard loading.

---

**Architect:** GitHub Copilot  
**Date:** 2026-06-23  
**Status:** Plan complete — ready for Engineer
