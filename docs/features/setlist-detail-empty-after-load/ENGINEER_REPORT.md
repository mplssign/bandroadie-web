# Engineer Report

## Feature Slug

`bug/setlist-detail-empty-after-load`

## Feature Title

Setlist Detail Empty After Load (iOS)

## Goal

Fix iOS production bug where setlist detail screen showed zero songs after successful load (loading spinner completed, but displayed empty state). Remove controller's dependency on `selectedSetlistProvider` to prevent state loss from transient provider resets. Add band-switch safeguard to clear stale setlist data when user switches bands while screen is mounted.

## Architect Tasks Completed

- [x] Task 1 — Structural Fix: Remove controller dependency on selectedSetlistProvider
  - Added instance variables `_setlistId`, `_setlistName`, `_loadedForBandId` to track setlist state internally
  - Replaced `build()` method to remove `ref.watch(selectedSetlistProvider)` dependency
  - Added `ref.watch(activeBandIdProvider)` with band change guard to clear stale state when band switches
  - Added public `loadSetlist(String id, String name)` method for screen to initialize controller
  - Updated `loadSongs()` to read from instance variables instead of `selectedSetlistProvider`
- [x] Task 2 — Fix: Reset isLoading in stale band ID guard
  - Added `state = state.copyWith(isLoading: false)` before early return in Catalog branch stale band ID guard
  - Added `state = state.copyWith(isLoading: false)` before early return in non-Catalog branch stale band ID guard
- [x] Task 3 — Update screen to call loadSetlist() directly
  - Modified `SetlistDetailScreen.initState()` post-frame callback to call `ref.read(setlistDetailProvider.notifier).loadSetlist(widget.setlistId, widget.setlistName)` instead of `selectedSetlistProvider.select()`

## Files Created

- none

## Files Modified

- [lib/features/setlists/setlist_detail_controller.dart](lib/features/setlists/setlist_detail_controller.dart)
- [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 2 new warnings

**New warnings (vestigial state from old reactive design):**

- Line 296: `unused_field` - `_lastLoadedSetlistId` field value isn't used
- Line 297: `unused_field` - `_cachedState` field value isn't used

**Explanation:** Both fields are vestigial remnants from the old reactive design where `build()` watched `selectedSetlistProvider` and used these for state preservation. In the new design:

- `_lastLoadedSetlistId` is only set to `null` (never to an actual ID), making it inert
- `_cachedState` is set but never read (state preservation now handled by Riverpod's `state` field)

Both fields are still assigned to maintain structural similarity with the old code (band change guard clears them, state setter preserves `_cachedState`), but these assignments have no functional effect. Removing them would require deeper refactoring outside the Architect plan's scope.

**Pre-existing warnings (unchanged):**

- 4 deprecation warnings about `onReorder` and `axisAlignment` in other files (not introduced by this implementation)

## Test Results

Not run (manual testing required per Architect verification plan)

## Verification

Manual steps performed:

- Verified code compiles with `flutter analyze` (0 errors)
- Formatted both modified files with `dart format`
- Confirmed console debug logs are present:
  - `[SetlistDetail] Loading setlist: <name> (ID: <id>)` in `loadSetlist()` method
  - `[SetlistDetail] Band changed from <uuid> to <uuid>, clearing stale setlist state` in band change guard
- Reviewed all changes match Architect plan specifications
- Corrected two initial deviations to match plan exactly

## Deviations From Architect Plan

**Initial implementation contained two unintentional deviations (both since corrected):**

1. **`loadSetlist()` dedup guard** - Initial implementation used compound condition `if (_setlistId == id && _lastLoadedSetlistId == id)` instead of plan's simple `if (_setlistId == id)`. The extra check made the guard permanently inert since `_lastLoadedSetlistId` is never assigned an actual ID in the new design (only `null`).
   - **Resolution:** Reverted to match plan exactly (`if (_setlistId == id)`)

2. **Local `isCatalog` variable** - Initial implementation added `final isCatalog = setlistName == kCatalogSetlistName;` and used it instead of `state.isCatalog`. Plan's Change 1.4 said "rest of method (unchanged)".
   - **Resolution:** Reverted to use `state.isCatalog` as implied by plan

**Current state:** All code now matches ARCHITECT_PLAN.md specifications exactly. Both deviations were caught in review and corrected before final commit.

## Blockers Encountered

None

## Ready For QA

Yes

**QA must perform:**

1. Test 1: Normal Setlist Load (Regression Check) - iOS simulator/device
2. Test 2: iOS Background During Screen Mount (Race Condition) - iOS physical device
3. Test 3: Rapid Navigation (Edge Case) - iOS
4. **Test 4: Band Switch While Setlist Detail Screen Open (Critical New Test)** - iOS physical device - verify console shows band change log and no stale data displayed
5. Test 5: Catalog vs. Non-Catalog (Regression) - iOS
6. Test 6: Force-Quit Restart (Original Bug Reproduction) - iOS physical device

**Critical acceptance criteria:**

- Songs display correctly after load (no empty state with zero songs)
- Console log shows "Loading setlist" message on screen open
- Band switch while screen open triggers console log "Band changed from X to Y, clearing stale setlist state"
- No stuck loading spinner
- No stale data from previous band after band switch
