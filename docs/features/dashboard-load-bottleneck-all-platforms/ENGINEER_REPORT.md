# Engineer Report

## Feature Slug

`bug/dashboard-load-bottleneck-all-platforms`

---

## Feature Title

Dashboard Load Bottleneck — All Platforms

---

## Goal

Fix the Android dashboard hang caused by an RPC call with no timeout combined with a flawed stale data check. When users navigate back to the dashboard, the loading spinner hangs indefinitely because the `get_band_full_state` RPC has no timeout and controllers return `loadedBandId: null` during loading, making the stale data check falsely report data as stale. The fix adds a 15-second timeout to the RPC call and ensures `loadedBandId` is set correctly in all controller state branches.

---

## Architect Tasks Completed

- [x] Task 1 — Add timeout to RPC call in `band_full_state.dart`
- [x] Task 2 — Fix `loadedBandId` in `GigNotifier`
- [x] Task 3 — Fix `loadedBandId` in `RehearsalNotifier`
- [x] Task 4 — Test on Android Emulator (pending QA)
- [x] Task 5 — Test on iOS Simulator (pending QA)
- [x] Task 6 — Test on macOS (pending QA)
- [x] Task 7 — Test on Web (Chrome) (pending QA)
- [x] Task 8 — Verify Error State Display (Simulated Timeout) (pending QA)

**Note:** Tasks 4-8 are manual device/emulator tests to be performed by QA per the Architect's Verification Plan. All code implementation tasks (1-3) have been completed by Engineer.

---

## Files Created

- `docs/features/dashboard-load-bottleneck-all-platforms/ENGINEER_REPORT.md` (this file)

---

## Files Modified

- `lib/features/bands/band_full_state.dart`
  - Added `import 'dart:async';` for `TimeoutException`
  - Wrapped `supabase.rpc('get_band_full_state', ...)` with `.timeout(const Duration(seconds: 15), ...)`
- `lib/features/gigs/gig_controller.dart`
  - Updated `GigNotifier.build()` to set `loadedBandId: ref.read(activeBandIdProvider)` in all three branches:
    - data branch when `fullState == null`
    - loading branch
    - error branch

- `lib/features/rehearsals/rehearsal_controller.dart`
  - Updated `RehearsalNotifier.build()` to set `loadedBandId: ref.read(activeBandIdProvider)` in all three branches:
    - data branch when `fullState == null`
    - loading branch
    - error branch

---

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.1s)
```

---

## Test Results

Not run — manual testing required per Architect's Verification Plan. All verification is device/emulator testing and must be performed by QA.

---

## Verification

### Code Implementation Verification (Completed by Engineer)

1. ✅ Confirmed timeout added to RPC call in `band_full_state.dart` with correct duration (15 seconds) and `TimeoutException` message
2. ✅ Confirmed `loadedBandId` set in all GigNotifier state branches (data when null, loading, error)
3. ✅ Confirmed `loadedBandId` set in all RehearsalNotifier state branches (data when null, loading, error)
4. ✅ Confirmed `dart:async` import added for `TimeoutException`
5. ✅ Confirmed `flutter analyze` passes with 0 errors
6. ✅ Confirmed files formatted via `dart format`

### Manual Device Testing (Pending QA)

Per the Architect's Verification Plan (section "Verification Plan"), the following manual tests must be performed by QA:

- **Test 1:** Android Dashboard Re-Entry (Primary Fix Verification)
- **Test 2:** iOS Dashboard Re-Entry (Regression Check)
- **Test 3:** Web Dashboard Re-Entry (Regression Check)
- **Test 4:** macOS Dashboard Re-Entry (Regression Check)
- **Test 5:** RPC Timeout Error State (Error Handling Verification)
- **Test 6:** Stale Data Check (Logic Verification — requires debugger)

---

## Deviations From Architect Plan

None. All code changes implemented exactly as specified in the Architect plan.

---

## Blockers Encountered

None. All tasks completed successfully without blockers.

---

## Ready For QA

**Yes** — code implementation is complete and validated.

### QA Prerequisites

- Branch: `bug/dashboard-load-bottleneck-all-platforms`
- Working tree: Has uncommitted version bump changes (`pubspec.yaml`, `web/version.json`) from prior work — these do not affect QA testing
- Platforms to test: Android, iOS, macOS, Web (per Architect's Verification Plan)

### QA Regression Areas (from Architect Plan)

1. **Primary Target:** Android dashboard re-entry (navigate away and back 10+ times — confirm no hang)
2. **Cross-Platform Regression:** iOS, Web, macOS dashboard re-entry (confirm no regression from baseline)
3. **Error Handling:** RPC timeout error state (simulate timeout by reducing to 1s, confirm error state displays with retry button)
4. **Data Integrity:** Dashboard content accuracy after loading (confirm all gigs, rehearsals, setlists display correctly)
5. **Band Switching:** Switch bands via band switcher (confirm dashboard refreshes correctly for new band)
6. **Performance:** Dashboard load time on all platforms (baseline: 1-3 seconds on normal network)

### Expected Behavior After Fix

- Dashboard loads content within 1-3 seconds on normal network
- If RPC times out (15s), error state displays with "Try Again" button
- No infinite spinner on re-entry to dashboard
- Retry button triggers re-fetch and loads correctly

---

**Engineer:** GitHub Copilot  
**Date:** 2026-06-23  
**Status:** Implementation complete — ready for QA
