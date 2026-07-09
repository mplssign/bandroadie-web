# QA Report

## Feature Slug

`bug/cross-band-blockout-visibility`

## Feature Title

Cross-Band Block-Out Visibility (Issue 1: Cache Invalidation)

## Final Verdict

**APPROVED**

## Validation Summary

The implementation correctly addresses Issue 1 (calendar cache invalidation for propagated block-outs) as specified in the Architect plan. The new `invalidateCacheForBand()` helper safely clears cache entries for specific bands without affecting other bands, and is properly called after One Calendar propagation. Code-path analysis confirms correct behavior for all specified test scenarios. No regressions to existing single-band functionality.

## Architect Scope Review

- **Scope adherence:** Compliant — Only Issue 1 (cache invalidation) was implemented as instructed
- **Files modified:** As expected — Only `calendar_controller.dart` and `event_editor_drawer.dart` modified (plus ARCHITECT_PLAN.md documentation)
- **Files off-limits:** Not touched — No changes to `events_repository.dart`, `auto_conflict_blocking_service.dart`, or database migrations (Issues 2 and 3 are out of scope per instructions)

## Completeness Check

- **All Architect tasks implemented:** Yes
  - ✅ Task 1: Added `invalidateCacheForBand()` helper method to `CalendarNotifier`
  - ✅ Task 2: Called `invalidateCacheForBand()` for each band in `otherBandIds` after One Calendar propagation
- **Missing tasks:** None

## Behavior Verification

- **Validation method:** Code-path analysis (runtime testing requires manual verification per Architect plan)
- **Result:** Matches expected behavior

### Code-Path Analysis Results

**Test 1 (Same-tab band switching):**

- ✅ Block-out creation triggers propagation to other bands (database writes)
- ✅ `invalidateCacheForBand()` called for each band in `otherBandIds`
- ✅ Cache entries removed using correct key format (`$bandId-$year-$month`)
- ✅ Switching to another band's calendar triggers `getCachedMonth()`, finds null/stale cache, loads fresh data from DB
- **Expected result:** Block-out appears immediately when switching bands in same tab

**Test 3 (One Calendar disabled):**

- ✅ `getBandIdsToApplyBlockOut()` returns only current band when One Calendar is disabled
- ✅ `otherBandIds` list is empty (current band filtered out)
- ✅ Propagation loop doesn't execute (empty list)
- ✅ Cache invalidation guard `if (otherBandIds.isNotEmpty)` is false, no cross-band invalidation
- ✅ Only `invalidateAndRefresh(bandId: widget.bandId)` runs for current band
- **Expected result:** No propagation, no cross-band cache invalidation

**Test 4 (Cache expiration):**

- ✅ Cache TTL is 5 minutes (`MonthData.isStale` checks `inMinutes > 5`)
- ✅ `getCachedMonth()` returns null if cache exists but `isStale` is true
- ✅ Stale cache forces fresh load regardless of manual invalidation
- **Expected result:** Block-outs appear correctly whether cache was manually invalidated or naturally expired

**Test 2 (Cross-tab sync):**

- Expected limitation: Won't work without page reload (Riverpod state not shared across tabs)
- Out of scope per Architect plan — not a failure condition

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:**
  - Calendar display and navigation
  - Block-out creation and propagation
  - One Calendar preferences
  - Cache management
  - Single-band vs multi-band behavior
- **Regressions found:** None

### Detailed Regression Analysis

**Calendar cache integrity:**

- ✅ Cache key format unchanged (`$bandId-$year-$month`)
- ✅ Existing `invalidateAndRefresh()` method untouched
- ✅ New helper method uses identical key filtering logic
- ✅ Cache operations are synchronous in-memory operations (no external dependencies, no error risk)

**Single-band user behavior:**

- ✅ Users with One Calendar disabled: `otherBandIds` is empty, new code path doesn't execute
- ✅ Users with only 1 band: `otherBandIds` is empty, no cross-band operations
- ✅ Existing cache invalidation (`invalidateAndRefresh`) still called for current band in all cases

**One Calendar propagation:**

- ✅ Propagation logic unchanged (only cache invalidation added)
- ✅ Database writes unchanged
- ✅ Error handling unchanged (nested try-catch preserved)

**Engineer's documented deviation:**

- The Engineer moved cache invalidation inside the outer try-catch block (not outside as Architect plan initially suggested)
- **Assessment:** This is a safe and correct deviation
- **Rationale:**
  - If propagation fails entirely (outer catch), cache invalidation is correctly skipped (no data was written)
  - If propagation succeeds partially (inner catches), cache invalidation still runs (correct behavior)
  - `otherBandIds` is in scope inside the try block
  - Cleaner code structure with proper error handling

## Database Safety

**Not applicable** — No database schema changes, migrations, or RPC modifications in this implementation.

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors

**Warnings:** 4 pre-existing deprecation warnings in unrelated setlist files (not introduced by this implementation):

- `lib/features/setlists/new_setlist_screen.dart:984:13` — deprecated `onReorder` usage
- `lib/features/setlists/setlist_detail_screen.dart:1716:29` — deprecated `axisAlignment` usage
- `lib/features/setlists/setlist_detail_screen.dart:2295:23` — deprecated `onReorder` usage
- `lib/features/setlists/setlists_tab_content.dart:511:25` — deprecated `onReorder` usage

## Test Results

**Not run** — Manual testing required per Architect plan Manual Tests 1, 3, and 4. Automated unit tests are not applicable for this cache invalidation feature (requires runtime state verification across band switches).

## Diff Safety Review

- **Secrets:** None found
- **Debug artifacts:** None found (existing debugPrint statements are intentional and appropriate)
- **Unrelated changes:** None — Only targeted changes to add cache invalidation logic
- **File modifications:** Clean — No formatting churn, no opportunistic refactoring

## Issues Found

None

---

## Implementation Quality Notes

### Strengths

1. **Minimal change surface** — Only added necessary code, no unnecessary refactoring
2. **Consistent patterns** — New helper method mirrors existing `invalidateAndRefresh()` implementation
3. **Safe error handling** — Cache invalidation wrapped in propagation try-catch, properly scoped
4. **Guard clauses** — Checks `otherBandIds.isNotEmpty` before executing loop
5. **Clear documentation** — Method comment explains purpose and usage context

### Code Review Observations

1. **Cache key filtering:** Uses `startsWith('$bandId-')` which correctly matches format `'$bandId-$year-$month'`
2. **No concurrency issues:** Collects keys to remove into a list before removing them (avoids concurrent modification)
3. **No null safety issues:** Guard clause prevents empty list iteration
4. **Scope safety:** `otherBandIds` is declared and populated in the same try block where it's used

---

## Manual Testing Recommendations

Before deploying to production, perform these manual tests:

**Test 1 (Same-tab band switching):**

1. Enable One Calendar (Settings → One Calendar → ON, Mode: All bands)
2. Navigate to Band A's calendar
3. Create a block-out for a future date (e.g., 3 days from now)
4. Observe success message and drawer closes
5. Switch to Band B's calendar (band switcher at top)
6. **Verify:** Block-out appears on Band B's calendar immediately (no page reload)
7. Switch to Band C's calendar
8. **Verify:** Block-out appears on Band C's calendar immediately

**Test 3 (One Calendar disabled):**

1. Settings → One Calendar → OFF
2. Navigate to Band A's calendar
3. Create a block-out
4. Switch to Band B's calendar
5. **Verify:** Block-out does NOT appear on Band B (no propagation)

**Test 4 (Cache persistence):**

1. Enable One Calendar
2. Create a block-out in Band A
3. Switch to Band B immediately
4. **Verify:** Block-out appears (cache invalidated)
5. Wait 6+ minutes (cache TTL)
6. Switch to Band A, then back to Band B
7. **Verify:** Block-out still appears (cache expired, fresh load)

**Expected limitation (Test 2):**

- Cross-tab sync requires manual page reload (Cmd+R) — this is documented expected behavior

---

## Next Steps

### For Issue 1 (This Implementation)

1. ✅ **QA Review:** APPROVED
2. **Manual Testing:** Perform Tests 1, 3, and 4 above before deployment
3. **Deploy:** Push to production web after manual verification
4. **Monitor:** Check for any unexpected cache behavior or performance issues

### For Issue 2 (Gig Auto-Conflict-Blocking)

- **Status:** Not implemented — requires investigation per Architect plan Phase 10
- **Next:** Runtime debugging to determine why gigs don't trigger auto-conflict blocks

### For Issue 3 (Historical Backfill)

- **Status:** Not implemented — awaiting Tony's decision on scope
- **Next:** Tony to review backfill options (A, B, C, or D) per Architect plan Phase 11

---

**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-07-09  
**Review Duration:** Complete code-path analysis performed  
**Status:** APPROVED — ready for manual verification and deployment
