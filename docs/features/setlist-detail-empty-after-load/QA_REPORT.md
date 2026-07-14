# QA Report

## Feature Slug

`bug/setlist-detail-empty-after-load`

## Feature Title

Setlist Detail Empty After Load (iOS)

## Final Verdict

**APPROVED**

## Validation Summary

Code-path analysis confirms all Architect tasks are correctly implemented. The controller no longer watches `selectedSetlistProvider` (eliminating vulnerability to transient provider state loss), and now receives setlist ID/name directly via public `loadSetlist()` method called by screen. Critical safety areas verified: (1) band-switch guard correctly watches `activeBandIdProvider` and clears stale state when band changes, (2) `ref.listen` for song updates is registered before any early returns ensuring Riverpod maintains the listener. Implementation matches Architect specifications exactly after two initial deviations were corrected mid-review. Manual iOS device testing per Architect verification plan Tests 1-6 is still required but cannot be performed in code review.

## Architect Scope Review

**Scope adherence:** Compliant

**Files modified:** As expected (2 files)

- `lib/features/setlists/setlist_detail_controller.dart` ✓
- `lib/features/setlists/setlist_detail_screen.dart` ✓

**Files off-limits:** Not touched

**Architectural patterns:** No changes to patterns — simplified controller build() logic by removing provider watch, added public method, no new abstractions or dependencies introduced

**Change surface:** Minimal and appropriate — changes focused on removing vulnerable dependency and adding band-switch safeguard

## Completeness Check

**All Architect tasks implemented:** Yes

**Task completion:**

- [x] **Task 1** — Structural Fix: Remove controller dependency on selectedSetlistProvider
  - Added instance variables `_setlistId`, `_setlistName`, `_loadedForBandId` (lines 293-295)
  - Replaced `build()` method: removed `ref.watch(selectedSetlistProvider)`, added `ref.watch(activeBandIdProvider)` with band change guard (lines 312-355)
  - Added public `loadSetlist(String id, String name)` method (lines 348-376)
  - Updated `loadSongs()` to read from instance variables instead of state/provider (lines 473-486, 507-608)

- [x] **Task 2** — Fix: Reset isLoading in stale band ID guard
  - Catalog branch: added `state = state.copyWith(isLoading: false)` at line 522
  - Non-Catalog branch: added `state = state.copyWith(isLoading: false)` at line 558

- [x] **Task 3** — Update screen to call loadSetlist() directly
  - Modified `SetlistDetailScreen.initState()` post-frame callback at lines 117-121

**Missing tasks:** None

**Initial deviations (corrected per Engineer report):**

1. `loadSetlist()` dedup guard initially used compound condition — corrected to match plan's simple check
2. `loadSongs()` initially introduced local `isCatalog` variable — corrected to use `state.isCatalog` as implied by plan

## Behavior Verification

**Validation method:** Code-path analysis

**Result:** Matches expected behavior

### Verified Behaviors

1. **Controller no longer watches selectedSetlistProvider**
   - Confirmed: `ref.watch(selectedSetlistProvider)` removed from `build()` (line 341 comment)
   - Screen now calls `loadSetlist()` directly with route args (lines 120-121)
   - Route args are source of truth, not transient provider state

2. **Band-switch guard prevents stale data** (NEW SAFEGUARD)
   - Confirmed: `build()` watches `activeBandIdProvider` (line 326)
   - Guard detects band change: `if (_loadedForBandId != null && _loadedForBandId != currentBandId)` (line 328)
   - Clears all state variables on band change (lines 334-338)
   - Returns empty state (line 339)
   - Includes debug logging for verification (lines 329-333)

3. **ref.listen ordering is correct** (CRITICAL)
   - Confirmed: `songUpdateBroadcasterProvider` listener registered at lines 313-317
   - Registered BEFORE any early returns (band change guard at line 328)
   - Comment explains importance: "IMPORTANT: Must be registered unconditionally... or Riverpod will tear it down" (lines 314-315)

4. **loadSetlist() dedup guard prevents redundant loads**
   - Confirmed: Simple check `if (_setlistId == id)` at line 351 (matches plan)
   - Tracks band ID at load time: `_loadedForBandId = ref.read(activeBandIdProvider)` at line 365

5. **Stale band ID guards reset isLoading** (BUG FIX)
   - Catalog branch: Confirmed reset at line 522 before early return
   - Non-Catalog branch: Confirmed reset at line 558 before early return
   - Prevents stuck spinner when band switches mid-flight

6. **loadSongs() uses state.isCatalog not local variable**
   - Confirmed: Uses `state.isCatalog` at line 507 (matches plan)

### Critical Safety Verifications

Per QA request, special attention paid to:

✓ **Band-switch guard (`activeBandIdProvider` watch in `build()`)**

- Location: Lines 326-347
- Correctly implemented with all required state clears
- Protects against stale data when user switches bands while screen is mounted but hidden

✓ **`ref.listen` ordering**

- Location: Lines 313-317
- Registered BEFORE any early returns
- Ensures Riverpod doesn't tear down listener on build() early exits

## Regression Check

**Risk level:** LOW-MEDIUM

**Rationale:**

- Single architectural change (remove provider watch, add public method)
- Changes focused on one screen/controller pair
- No database, RPC, RLS, auth, or routing modifications
- Simplifies architecture by removing complex dependency
- New band-switch safeguard adds protection, not risk
- Other screens that write to `selectedSetlistProvider` unchanged
- SetlistDetailScreen is pushed route (can be safely popped), not IndexedStack child

**Systems reviewed:**

| System                   | Status      | Notes                                                          |
| ------------------------ | ----------- | -------------------------------------------------------------- |
| Setlist loading          | ✓ Improved  | Simplified to direct method call, no provider watch            |
| Setlist state management | ✓ Improved  | Reduced complexity, eliminated transient dependency            |
| Band switching           | ✓ Protected | New safeguard clears stale state when band changes             |
| Auth / Session           | ✓ Unchanged | No modifications, immune to lifecycle issues now               |
| Routing                  | ✓ Unchanged | Screen still pushed via Navigator.push                         |
| selectedSetlistProvider  | ✓ Unchanged | Still updated by screen (write), no longer watched (read)      |
| Other setlist screens    | ✓ Unchanged | new_setlist_screen, setlists_tab_content unaffected            |
| Gigs / Rehearsals        | ✓ Unchanged | No interaction with setlist detail controller                  |
| Repository layer         | ✓ Unchanged | No modifications to SetlistRepository or SpecialItemRepository |

**Regressions found:** None (code-level analysis)

**Edge cases protected:**

1. **Band switch while screen mounted but hidden** — Band-switch guard in `build()` detects this and clears stale state with debug log
2. **Provider state loss during iOS lifecycle transitions** — Controller no longer depends on provider, reads from route args instead
3. **Rapid navigation** — Dedup guard in `loadSetlist()` prevents redundant loads if screen rebuilds
4. **Stale band ID during async load** — Both Catalog and non-Catalog branches now reset `isLoading` before early return

**Manual testing required (Architect verification plan):**

Cannot be performed in code review, requires iOS device:

1. Test 1: Normal Setlist Load (Regression Check)
2. Test 2: iOS Background During Screen Mount (Race Condition)
3. Test 3: Rapid Navigation (Edge Case)
4. **Test 4: Band Switch While Setlist Detail Screen Open** (Critical — new safeguard)
5. Test 5: Catalog vs. Non-Catalog (Regression)
6. Test 6: Force-Quit Restart (Original Bug Reproduction)

**Acceptance criteria for manual testing:**

- Songs display correctly after load (no empty state with zero songs)
- Console log shows "Loading setlist" message on screen open
- Band switch while screen open triggers console log "Band changed from X to Y, clearing stale setlist state"
- No stuck loading spinner
- No stale data from previous band after band switch

## Database Safety

**Not applicable** — Client-side state management fix only. No migrations, RPC functions, RLS policies, triggers, or schema changes.

## Analyzer Results

Command: `flutter analyze`

Result: **0 errors** / **2 new warnings** / **4 pre-existing warnings**

### New Warnings (Expected)

```
warning • The value of the field '_lastLoadedSetlistId' isn't used.
         lib/features/setlists/setlist_detail_controller.dart:296:11 • unused_field

warning • The value of the field '_cachedState' isn't used.
         lib/features/setlists/setlist_detail_controller.dart:297:23 • unused_field
```

**Explanation (per Engineer report):** Both fields are vestigial from the old reactive design where `build()` watched `selectedSetlistProvider` and used these for state preservation. In the new design:

- `_lastLoadedSetlistId` is only set to `null` (never assigned actual ID), making it inert
- `_cachedState` is set but never read (state preservation now handled by Riverpod's `state` field)

Both are still assigned to maintain structural similarity (band change guard clears them, state setter preserves `_cachedState`), but assignments have no functional effect. Removing them would require deeper refactoring outside Architect plan scope.

**Assessment:** Acceptable. Fields could be removed in future cleanup but do not affect functionality or safety.

### Pre-existing Warnings (Unchanged)

```
info • 'onReorder' is deprecated... lib/features/setlists/new_setlist_screen.dart:984:13
info • 'axisAlignment' is deprecated... lib/features/setlists/setlist_detail_screen.dart:2112:29
info • 'onReorder' is deprecated... lib/features/setlists/setlist_detail_screen.dart:2568:23
info • 'onReorder' is deprecated... lib/features/setlists/setlists_tab_content.dart:511:25
```

**Assessment:** Pre-existing deprecation warnings in other files, not introduced by this work.

## Test Results

**Not run** — Manual testing required per Architect verification plan. No automated tests exist for setlist_detail (per Architect: "Not covered by existing test suite").

## Diff Safety Review

**Secrets:** None found ✓

**API keys / tokens / passwords:** None found ✓

**Debug artifacts:**

- Only `debugPrint` statements found (appropriate, wrapped in `if (kDebugMode)` guards)
- No bare `print()` statements
- No TODO, FIXME, HACK comments
- No test scaffolding in production code

**Unrelated changes:** None ✓

**Formatting churn:** None ✓

**Accidental deletions:** None ✓

**Git diff search results:**

```bash
git diff | grep -iE "(api[_-]?key|secret|password|token|print\(|TODO|FIXME|HACK)"
```

All matches were `debugPrint(` statements with proper guards.

## Issues Found

### Critical (must fix before commit)

None

### Warnings (should fix)

None — The two unused field warnings are vestigial remnants explained by Engineer and do not affect functionality.

### Suggestions (optional)

1. **Future cleanup:** Remove `_lastLoadedSetlistId` and `_cachedState` fields in future refactor since they're no longer used. Not required for this fix but would eliminate analyzer warnings.

2. **Test coverage:** Consider adding widget tests for SetlistDetailScreen in future to validate:
   - Initial load triggers `loadSetlist()` call
   - Band switch clears state (can be tested with ProviderScope override)
   - Stale band ID guard resets `isLoading`

   Note: These are suggestions for future work, not blockers for this fix.

## Code Quality Notes

**Positive aspects:**

- Clear debug logging added for troubleshooting (band change, setlist load)
- Comprehensive comments explaining critical behavior (ref.listen ordering, band-switch guard purpose)
- Defensive programming (null checks before reading instance variables)
- Proper use of `if (kDebugMode)` guards around debug statements
- Minimal, focused changes that don't touch unrelated code
- Good separation of concerns (screen owns navigation, controller owns data)

**Architecture improvements:**

- Removed complex provider watch dependency that caused transient failures
- Simplified controller build() logic (reactive → imperative initialization)
- Added explicit band-switch safeguard (defense in depth)
- Route args now source of truth (more stable than provider state)

## Verification Confidence

**Code-level verification: HIGH**

- All Architect tasks completed correctly
- Critical safety areas (band-switch guard, ref.listen ordering) verified
- No scope violations, secrets, or unsafe patterns
- Clean analyzer results (0 errors)
- Implementation matches specifications exactly after corrections

**Runtime verification: PENDING**

- Manual iOS device testing per Architect verification plan required
- Tests 1-6 must be performed to validate behavior at runtime
- Particularly Test 4 (band switch while screen open) to verify new safeguard

**Recommendation:** Approved for commit based on code review. Manual iOS testing should be performed before App Store release to validate runtime behavior, especially the new band-switch guard.

## QA Agent Notes

This implementation successfully addresses the root cause identified in the Architect plan: transient loss of `selectedSetlistProvider` state causing the controller to discard loaded songs. By removing the controller's dependency on that provider and reading from route args instead, the architecture is now immune to provider lifecycle issues on iOS.

The addition of the band-switch guard (`activeBandIdProvider` watch in `build()`) is a critical safety improvement not present in the old design. Since SetlistDetailScreen is a pushed route (not part of IndexedStack), it remains mounted when users switch bands via the band switcher. Without this guard, stale setlist data from the previous band would persist. The new guard detects this scenario and clears state, preventing data corruption.

The Engineer correctly identified and fixed two initial deviations during implementation:

1. Compound condition in `loadSetlist()` dedup guard (corrected to simple check)
2. Local `isCatalog` variable in `loadSongs()` (corrected to use `state.isCatalog`)

Both corrections demonstrate proper attention to Architect specifications.

The two unused field warnings (`_lastLoadedSetlistId`, `_cachedState`) are acceptable technical debt from the architectural transition. They don't affect functionality and can be removed in future cleanup.

---

**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Review Date:** 2026-07-13  
**Git Branch:** `bug/setlist-detail-empty-after-load`  
**Commit Status:** Clean (2 modified files, 1 untracked report file)
