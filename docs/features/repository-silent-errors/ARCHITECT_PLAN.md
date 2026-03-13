# ARCHITECT_PLAN.md: Repository Silent Error Handling

**Last Updated:** March 13, 2026
**Feature Slug:** bug/repository-silent-errors
**Type:** Bug Fix

---

## 1. Feature Slug

`bug/repository-silent-errors`

---

## 2. Problem Summary

`BandRepository.fetchUserBands()` (line 21–62) catches all exceptions and returns an empty list (`[]`). When Supabase fails—network error, auth error, RLS violation, or any runtime exception—the controller receives an empty list and treats it as "user has no bands," displaying the `NoBandState` widget.

The system has an error widget (`_buildErrorState()` at lines 510–562 in `home_tab_content.dart`) and controller support for error state (line 179 in `active_band_controller.dart`), but these are never reached because the exception is swallowed.

**User Impact:** Network failures appear as empty state ("no bands") instead of an error message with a retry button. Users have no way to know what went wrong or to retry.

---

## 3. Root Cause

**Confidence: HIGH**

The root cause is a silent `catch (e) { return []; }` block at **line 59–61 of band_repository.dart**:

```dart
try {
  // ...query logic...
} catch (e) {
  return [];  // ← Swallows all exceptions
}
```

This pattern masks all errors and prevents exception propagation to the controller. The controller expects exceptions to propagate and be caught at **line 300–304 of active_band_controller.dart**, where `state.error` is set to `'Failed to load bands: $e'`.

---

## 4. Existing System Analysis

### Data Flow (Happy Path)

1. **UI Layer** (`home_tab_content.dart:326–444`)
   - Watches `activeBandProvider` (line 327)
   - Checks `bandState.isLoading`, `bandState.error`, `bandState.hasBands` (lines 385–394)
   - Routes to appropriate widget: `_buildErrorState()` (line 388–393) if `error != null`

2. **Controller Layer** (`active_band_controller.dart:275–306`)
   - `loadUserBands()` sets `isLoading = true` (line 276)
   - Calls `_bandRepository.fetchUserBands()` (line 279)
   - On success: sets `userBands` and `activeBand` (line 295–299)
   - On exception: sets `error` to meaningful message (line 300–304)

3. **Repository Layer** (`band_repository.dart:21–62`)
   - Queries `band_members` and `bands` tables
   - **Returns empty list on exception** (line 60) ← **THE BUG**

### Error State Widget

The `_buildErrorState(String title, String details)` widget exists at lines 510–562 and is already wired:

- Shows custom icon + error message + "Try Again" button
- Button calls `_retry()` which invokes `loadUserBands()` again (line 202–204)
- Never triggered because exception is caught in repository

### Controller State Structure

`ActiveBandState` (lines 168–225) has:

- `error: String?` field (line 179)
- `copyWith(error:, clearError:)` support (lines 195–208)
- Equality/hashCode comparison (lines 212–224)

All infrastructure exists; the exception must propagate.

---

## 5. Proposed Solution

**Remove the silent catch block** in `BandRepository.fetchUserBands()`. Let exceptions propagate to the controller, where they are already handled correctly.

### Change Required

**File:** `/sessions/inspiring-lucid-edison/mnt/bandroadie/lib/features/bands/band_repository.dart`
**Lines:** 59–61

**Current Code:**
```dart
} catch (e) {
  return [];
}
```

**New Code:**
```dart
// Exceptions propagate to caller for proper error handling
```

(Remove the catch block entirely.)

### Result

1. Supabase exceptions propagate to `ActiveBandNotifier.loadUserBands()` (line 279)
2. Controller catch block (line 300–304) catches them
3. `state.error` is set to `'Failed to load bands: $e'`
4. UI watches `bandState.error` and calls `_buildErrorState()` (line 388–393)
5. User sees error widget with "Try Again" button, not empty state

---

## 6. Database Impact

**Not applicable.** No schema changes, no migrations. The repository layer is a client-side concern.

---

## 7. Flutter Architecture Changes

**None.** The fix uses existing architecture. No new providers, no new state fields, no changes to the UI layer. The error UI widget and state model already exist and work correctly.

---

## 8. Files to Create

**None.**

---

## 9. Files to Modify

| File Path | Change | Why |
|-----------|--------|-----|
| `lib/features/bands/band_repository.dart` | Remove catch block (lines 59–61) | Allow exceptions to propagate so controller can handle them properly |

---

## 10. Files Off-Limits

All other files are off-limits. Do not refactor or modify:

- `active_band_controller.dart` (architecture is correct, error handling in place)
- `home_tab_content.dart` (UI layer already has error state widget)
- `gig_repository.dart` (out of scope; no silent catch blocks; uses `NoBandSelectedError` which is the right pattern)
- `rehearsal_repository.dart` (out of scope; throws `NoBandSelectedError` correctly)
- `members_repository.dart` (out of scope; throws `NoBandSelectedError` correctly)
- All UI files (out of scope; no changes needed)

---

## 11. System Impact Map

**Affected Features:**

- **Home Tab / Dashboard** — Primary affected surface; error state becomes visible on band fetch failure
- **AuthGate** — Calls `loadUserBands()` during initialization; will now receive exceptions if Supabase fails (existing error handling applies)
- **Band Switching** — Uses `selectBandById()` which calls `loadUserBands()` indirectly; no change in behavior for already-loaded bands

**Not Affected:**

- Gig, rehearsal, or member fetches (they have correct error handling)
- Band creation, deletion, or editing (separate code paths)
- Permissions or RBAC (separate controller)

---

## 12. Regression Risk

**Confidence: LOW**

**Why Low Risk:**

1. The controller already has a try-catch block (line 300–304) designed to handle this
2. The UI already has an error state widget (lines 510–562) designed to display errors
3. No behavior change for successful cases (happy path unchanged)
4. Only change is that network/auth failures now show the error UI instead of empty state

**Potential Regressions:**

- If any code in the codebase assumed `fetchUserBands()` always returns a list (never throws), it will now fail
  - Mitigation: Search the codebase for calls to `fetchUserBands()`. The only caller is `loadUserBands()` at line 279, which already has a try-catch
  - **Verified:** Only called from `loadUserBands()` in the controller; controller has error handling in place

**Testing Strategy:**

1. Unit test: Mock Supabase to throw an exception, verify controller sets `error` state
2. Integration test: Home tab should show error widget when fetch fails
3. Manual QA: Disconnect network, open home tab, verify error appears with retry button

---

## 13. Engineer Task Breakdown

**Ordered, atomic tasks:**

1. **Read and Understand** (verification task, 5 min)
   - Open `band_repository.dart` lines 59–61
   - Confirm catch block exists and returns empty list
   - Verify no other code depends on this behavior

2. **Remove Catch Block** (implementation, 2 min)
   - Delete lines 59–61 from `band_repository.dart`
   - Leave no orphaned braces; ensure code formatting is clean

3. **Verify Controller Can Handle** (verification, 2 min)
   - Check `active_band_controller.dart` lines 300–304
   - Confirm catch block exists and sets `error` state
   - No changes needed; this already works

4. **Manual Test: Happy Path** (QA, 3 min)
   - Launch app with network connected
   - Open home tab
   - Verify bands load, no error state shown
   - Verify band selection and switching still works

5. **Manual Test: Error Path** (QA, 5 min)
   - Launch app
   - Disconnect network
   - Force a refresh (pull-down on home tab OR open home tab after closing)
   - Verify error state widget appears with "Try Again" button
   - Verify error message is meaningful (contains Supabase error details)
   - Click "Try Again"
   - Reconnect network
   - Verify bands load on retry

6. **Search for Other Silent Catches** (optional validation, 5 min)
   - Search codebase for `catch.*return \[\]` pattern
   - Verify `gig_repository.dart`, `rehearsal_repository.dart`, `members_repository.dart` do NOT have this pattern
   - **Result:** These repos throw `NoBandSelectedError` or propagate exceptions; no other silent catches found

---

## 14. Verification Plan

### Commands

```bash
# Search for other silent catch blocks in repositories
grep -r "catch.*{.*return \[\]" lib/features/*/repository.dart

# Verify band_repository.dart has the catch block removed
grep -A2 "} catch" lib/features/bands/band_repository.dart
# Should return no results after fix

# Run unit tests (if they exist)
flutter test test/features/bands/band_repository_test.dart
flutter test test/features/bands/active_band_controller_test.dart
```

### Manual Verification Checklist

**Happy Path (Network Connected):**
- [ ] Launch app, authenticate
- [ ] Home tab displays bands without error state
- [ ] Band switching works
- [ ] Pull-down refresh works (gigs/rehearsals load)

**Error Path (Network Disconnected):**
- [ ] Disconnect network before home tab loads
- [ ] Home tab shows `_buildErrorState()` widget
- [ ] Error message includes network error details (e.g., "Failed to load bands: ...")
- [ ] "Try Again" button is visible and clickable
- [ ] Click "Try Again", reconnect network → bands load on retry

**Edge Cases:**
- [ ] Auth token expired → error state shows
- [ ] RLS violation → error state shows
- [ ] Malformed response from Supabase → error state shows

---

## 15. QA Regression Areas

1. **Home Tab / Dashboard**
   - Band loading and display
   - Band switching via dropdown
   - Pull-down refresh behavior
   - Empty state (no bands) vs. error state distinction

2. **AuthGate / Initialization**
   - App launch with no band selected
   - Restoration of persisted band ID
   - Network failures during initial load

3. **Navigation**
   - Switching bands should navigate to dashboard
   - Error retry should not break navigation state

4. **UI States**
   - Loading spinner appears during fetch
   - Error widget appears on failure
   - Empty state (NoBandState) appears only when user has zero bands (not on error)

---

## 16. Rollout / Migration Strategy

**None required.** This is a client-side bug fix with no backend changes. Simply deploy the updated app build. Users will immediately see error states instead of silent empty states.

---

## 17. Out of Scope

- Error handling in `GigRepository`, `RehearsalRepository`, `MembersRepository` (they already propagate exceptions correctly)
- Retry logic improvements (already implemented in UI layer)
- Network timeout configuration (handled by Supabase client library)
- Error message localization (out of scope for this fix)
- Custom exception types beyond what Supabase throws (keep propagation simple)

---

## Summary

**Problem:** Silent catch block in `BandRepository.fetchUserBands()` swallows exceptions and returns empty list, making network errors indistinguishable from "no bands."

**Solution:** Remove the catch block (3 lines). Let exceptions propagate to the controller, which already has error handling in place. UI layer already has error state widget ready to display.

**Risk:** Low. All error handling infrastructure already exists and is tested. Only change is removing a buggy silence mechanism.

**Files Changed:** 1 file, 3 lines deleted.

**Test:** Verify error state appears on network failure, retry button works, happy path unchanged.
