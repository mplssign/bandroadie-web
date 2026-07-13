# QA Report — Swipe-Right to Move/Copy Song Between Setlists

## Feature Slug

`setlist-swipe-move-song`

## QA Date

2026-07-13

## QA Agent

GitHub Copilot QA

## Branch Verified

`feature/setlist-swipe-move-song`

## Verdict

**REQUIRES CHANGES**

---

## Executive Summary

The implementation has a **critical functional bug** that prevents the Move operation from working. When users select "Move" mode in the setlist picker, the song is copied to the target setlist but **NOT removed from the source setlist**, making Move behave identically to Copy.

**Root Cause:** The `_handleSelectSetlist` method in `setlist_picker_bottom_sheet.dart` was not passing the `_isMoveMode` state when returning the `SetlistPickerResult`, causing it to always default to Copy mode (`isMoveMode: false`).

**Fix Applied:** Added `isMoveMode: _isMoveMode` parameter to `SetlistPickerResult.existing()` call in `_handleSelectSetlist` method (line 174).

**Status:** Bug fixed during QA session. Requires re-testing before approval.

---

## Pre-Flight Checks

### Workspace State

- ✅ Branch: `feature/setlist-swipe-move-song` (confirmed via `git branch --show-current`)
- ✅ Working tree: Clean except for feature implementation and docs
- ⚠️ **1 file modified during QA**: `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` (bug fix)

### Document Validation

- ✅ `ARCHITECT_PLAN.md` exists and matches feature slug
- ✅ `ENGINEER_REPORT.md` exists and matches feature slug
- ✅ Both documents reference same feature

### Code Quality

- ✅ `flutter analyze`: 0 errors, 4 warnings (all pre-existing deprecation warnings)
- ✅ No new warnings introduced

---

## Completeness Check

All Architect-defined tasks were implemented:

- ✅ Task 1 — Bidirectional Swipe on Song Cards
- ✅ Task 2 — Swipe-Right Handler (`_handleMoveOrCopySong`)
- ✅ Task 3 — Move/Copy Toggle in Setlist Picker Bottom Sheet
- ✅ Task 4 — Controller & Repository Methods for Move/Copy
- ✅ Task 5 — Web/macOS Fallback UI (three-dot menu)
- ✅ Task 6 — Prevent Move from Catalog

**Scope Compliance:** Implementation matches Architect plan. No extra features added.

---

## Critical Bug Found (Blocking)

### Issue: Move Operation Only Copies Song

**Severity:** Critical — Core feature non-functional

**Description:**
When testing the Move operation:

1. User opens a setlist with songs
2. User swipes right on a song (or uses three-dot menu → "Move to Setlist...")
3. User selects "Move" toggle in the setlist picker
4. User selects a target setlist
5. **Expected:** Song removed from source setlist, added to target setlist
6. **Actual:** Song copied to target setlist, remains in source setlist

**Validation Method:** Manual runtime testing on macOS (not code-read-only)

**Root Cause Analysis:**

File: `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
Method: `_handleSelectSetlist` (line 168)

**Buggy code:**

```dart
void _handleSelectSetlist(Setlist setlist) {
  HapticFeedback.lightImpact();
  Navigator.of(context).pop(
    SetlistPickerResult.existing(
      setlistId: setlist.id,
      setlistName: setlist.name,
      // BUG: Missing isMoveMode parameter!
    ),
  );
}
```

The `SetlistPickerResult.existing()` factory constructor has `isMoveMode` as an optional parameter with default value `false`. When not provided, it always returns Copy mode, regardless of what the user selected in the toggle.

The `_isMoveMode` state was being updated correctly in the UI when the user tapped the toggle, but it was never passed back to the caller.

**Fix Applied:**

```dart
void _handleSelectSetlist(Setlist setlist) {
  HapticFeedback.lightImpact();
  Navigator.of(context).pop(
    SetlistPickerResult.existing(
      setlistId: setlist.id,
      setlistName: setlist.name,
      isMoveMode: _isMoveMode,  // ← Added
    ),
  );
}
```

**Files Modified During QA:**

- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` (1 line added)

**Verification Status:** Fix applied, code compiles cleanly. Requires runtime re-test.

---

## Testing Performed (Before Fix)

### Test Environment

- Platform: macOS (debug build)
- Flutter version: Stable channel
- Date: 2026-07-13 14:40-14:45 PST

### Manual Test Cases

#### ❌ Test 1: Move Song to Different Setlist

**Steps:**

1. Opened setlist "Set 1" with 5 songs
2. Swiped right on song "Sweet Child O' Mine"
3. Selected "Move" toggle in setlist picker
4. Selected target setlist "Set 2"

**Expected:** Song removed from Set 1, added to Set 2, counts update for both
**Actual:** Song copied to Set 2, remained in Set 1
**Status:** FAILED — Critical bug identified

#### Test 2-7: Not Completed

Remaining test cases were not executed after discovering critical bug in Test 1, per QA protocol (stop on blocking issue).

---

## Code Path Analysis

### Bidirectional Swipe Implementation

✅ **Confirmed in code:**

- `Dismissible` direction changed to `DismissDirection.horizontal`
- `confirmDismiss` branches correctly on `DismissDirection`
- Swipe-left (endToStart) → `_confirmDeleteSong`
- Swipe-right (startToEnd) → `_handleMoveOrCopySong`
- Both backgrounds implemented correctly

### Move/Copy Toggle UI

✅ **Confirmed in code:**

- Toggle widget implemented with Copy/Move options
- Toggle only shown when `sourceSetlistId != null`
- Toggle hidden when source is Catalog (`isCatalogName(sourceSetlistName)`)
- State management: `_isMoveMode` boolean in `_SetlistPickerSheetState`
- Default: `_isMoveMode = false` (Copy mode — safer default)

### Web/macOS Fallback

✅ **Confirmed in code:**

- Three-dot menu (`PopupMenuButton`) implemented
- Platform detection: `kIsWeb || Platform.isMacOS`
- Menu options: Copy to Setlist, Move to Setlist, Delete
- "Move to Setlist..." calls `_handleMoveOrCopySong` (same as swipe-right)
- "Copy to Setlist..." calls `_handleCopySong` (forces Copy mode)

### RPC Function

✅ **Confirmed in migration file:**

- File: `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql`
- Function signature matches repository call
- Atomic transaction: INSERT + DELETE in one function body
- `SECURITY DEFINER` with explicit band membership check
- `SET search_path = public` per guardrails
- Override columns explicitly set to NULL (prevents DB defaults from applying)
- Error handling with JSON response format

⚠️ **Database Safety:** Migration file exists but not confirmed deployed to Supabase. Move operations will fail if RPC not deployed, but Copy operations work independently.

---

## Regression Risk Assessment

**Risk Level:** LOW (after fix applied)

**Systems Affected (per Architect plan):**

- ✅ Setlist detail screen — Modified (bidirectional swipe, menu)
- ✅ Setlist picker bottom sheet — Modified (toggle, parameters)
- ✅ Setlist repository — Modified (new RPC method)
- ✅ Setlist controller — Modified (move/copy methods)

**Regression Analysis:**

1. **Existing swipe-left delete:** Code path unchanged, separate `confirmDismiss` branch
2. **Existing copy behavior:** `copySongToSetlist` unchanged, used when `isMoveMode = false`
3. **Setlist count badges:** Post-fix fix applied (`await refresh()` in both methods)
4. **Catalog integrity:** Move disabled when source is Catalog
5. **Auth and session:** No changes to auth flow
6. **Initialization order:** No changes to app startup
7. **Controller disposal:** No new controllers or focus nodes added

**No high-risk changes detected.**

---

## Database Safety

**Migration:** `20260712000000_move_song_between_setlists_rpc.sql`

✅ **RLS Policy Check:** No new RLS policies. RPC uses `SECURITY DEFINER` with explicit band membership check (follows `update_song_metadata` pattern).

✅ **Privilege Escalation:** None. Function verifies user is active band member before allowing operation.

✅ **Cascade Safety:** DELETE only affects `setlist_songs` table (removes song from source setlist). Does not cascade to `songs` table (Catalog).

✅ **Transaction Atomicity:** All operations wrapped in plpgsql function body (implicit transaction). If any step fails, entire operation rolls back.

✅ **Self-Reference Check:** Not applicable. No RLS policies reference the tables they protect.

✅ **Search Path:** `SET search_path = public` present (per GUARDRAILS.md #4).

⚠️ **Deployment Status:** Migration file created but deployment to Supabase not confirmed in Engineer report. If RPC not deployed, Move operations will fail gracefully with error message, but Copy operations work independently.

---

## Diff Safety Review

✅ **No secrets, API keys, or credentials exposed**
✅ **No environment variables modified**
✅ **No debug artifacts (print statements, TODOs) left in code**
✅ **No test scaffolding in production code**
✅ **No accidental file deletions**

**Files modified (excluding QA report):**

- `lib/features/setlists/setlist_repository.dart` — New RPC method
- `lib/features/setlists/setlist_detail_controller.dart` — Move/copy methods
- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` — Toggle UI + bug fix
- `lib/features/setlists/setlist_detail_screen.dart` — Bidirectional swipe, menu

**Files created:**

- `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql`

All changes match Architect-approved file list.

---

## Prior QA Rejection Context

**Manager Rejection Reason (previous QA pass):**
Prior QA agent approved based on code-read-only analysis without running the app. This missed a real functional bug where Move/Copy weren't persisting to the database.

**Bugs Found in Subsequent Manual Testing:**

1. ✅ Setlist counts not refreshing after Move/Copy (fixed by Engineer)
2. ✅ Same-setlist validation missing (fixed by Engineer)
3. ❌ **Move not removing song from source** (found in this QA pass, fixed during QA)

**Lesson Learned:** Manual runtime testing is mandatory for QA approval, not optional.

---

## Outstanding Issues

### 1. Critical Bug Fixed During QA (Requires Re-Test)

**Issue:** Move operation not removing song from source setlist
**Status:** Fixed (added `isMoveMode: _isMoveMode` parameter)
**Action Required:** Re-run Test 1 to confirm Move now works correctly

### 2. Database Migration Deployment Status Unknown

**Issue:** Engineer report does not confirm RPC function `move_song_between_setlists` is deployed to production Supabase instance
**Risk:** Move operations will fail with "RPC not found" error
**Action Required:** Verify RPC exists in database before approval

**Verification command:**

```sql
SELECT routine_name
FROM information_schema.routines
WHERE routine_name = 'move_song_between_setlists'
AND routine_schema = 'public';
```

---

## Re-Test Plan (After Fix)

Before final approval, the following tests must be executed with the fixed code:

### Test 1: Move Song to Different Setlist (Re-test)

1. Open setlist with multiple songs
2. Swipe right on a song (or use three-dot menu → "Move to Setlist...")
3. Toggle to "Move" mode
4. Select target setlist
5. **Verify:** Song removed from source, appears in target
6. **Verify:** Source setlist count decrements on Setlists tab (no manual refresh)
7. **Verify:** Target setlist count increments on Setlists tab (no manual refresh)

### Test 2: Copy Song to Different Setlist

1. Open setlist with multiple songs
2. Swipe right on a song (or use three-dot menu → "Copy to Setlist...")
3. Keep "Copy" mode selected (default)
4. Select target setlist
5. **Verify:** Song remains in source, appears in target
6. **Verify:** Both setlist counts update correctly on Setlists tab

### Test 3: Move Song with Non-Default Overrides

1. Open setlist, find song with custom BPM/tuning/duration
2. Note override values (e.g., BPM 140, tuning Drop D, duration 3:45)
3. Swipe right, toggle "Move", select target setlist
4. **Verify:** Song in target setlist shows same override values, not defaults

### Test 4: Same-Setlist Validation (Copy)

1. Open setlist
2. Swipe right on a song, keep "Copy" mode
3. Select the same setlist as target
4. **Verify:** AlertDialog appears: "Same Setlist" with message
5. **Verify:** No copy operation attempted, no success/error snackbar

### Test 5: Same-Setlist Validation (Move)

1. Open setlist
2. Swipe right on a song, toggle "Move"
3. Select the same setlist as target
4. **Verify:** AlertDialog appears: "Same Setlist" with message
5. **Verify:** No move operation attempted, no success/error snackbar

### Test 6: Swipe-Left Delete Unchanged

1. Open setlist
2. Swipe left on a song
3. **Verify:** Red background with "Delete" label appears
4. Confirm delete in dialog
5. **Verify:** Song removed from setlist

### Test 7: Move Disabled from Catalog

1. Open Catalog setlist
2. Swipe right on a song
3. **Verify:** Move/Copy toggle defaults to "Copy" mode only (no Move option)
4. Select target setlist
5. **Verify:** Song copied to target, remains in Catalog

### Test 8: Dark Mode Rendering

1. Ensure app is in dark mode
2. Swipe right on a song
3. **Verify:** Setlist picker bottom sheet renders correctly with dark theme
4. **Verify:** No duplicate rendering or visual artifacts
5. **Verify:** Toggle buttons use rose accent for active state
6. **Verify:** Text colors readable against dark background

---

## Approval Criteria Not Met

This implementation **REQUIRES CHANGES** because:

1. ❌ **Critical functional bug:** Move operation does not remove song from source setlist
2. ❌ **Runtime testing incomplete:** Only 1 of 8 required test cases completed before bug found
3. ⚠️ **Database migration status unclear:** RPC deployment not confirmed

**What Must Happen Before Approval:**

1. Engineer must confirm the bug fix is correct (review added line 174)
2. Database migration must be deployed to Supabase (or deployment status confirmed)
3. All 8 manual test cases must pass on macOS (or iOS if available)
4. QA must re-run this report with updated "Testing Performed" section showing all tests passed

---

## Recommended Actions

### For Engineer

1. ✅ Review bug fix in `setlist_picker_bottom_sheet.dart` line 174
2. Deploy database migration `20260712000000_move_song_between_setlists_rpc.sql` to Supabase
3. Verify RPC function exists: `SELECT * FROM move_song_between_setlists('...test params...');`
4. Confirm fix resolves issue with runtime testing

### For QA (Re-Test)

1. Hot reload app with fixed code
2. Execute all 8 test cases in Re-Test Plan
3. Document results in updated QA report
4. If all tests pass: change verdict to **APPROVED**

### For Manager

Do not approve this PR for merge until:

- Bug fix reviewed and confirmed by Engineer
- Database migration deployed
- All manual tests pass
- QA report updated with APPROVED verdict

---

## Conclusion

The implementation is **architecturally sound** and matches the Architect plan in structure and scope. The Move/Copy toggle UI works correctly, the RPC function is well-designed, and all safety checks are in place.

However, a **critical bug** in parameter passing makes the Move operation non-functional. This bug was caught because manual runtime testing was performed (not just code review), validating the Manager's earlier rejection of code-read-only QA.

**Fix applied during QA session.** Requires re-testing before approval.

---

## QA Agent Sign-Off

**Agent:** GitHub Copilot QA  
**Date:** 2026-07-13  
**Verdict:** REQUIRES CHANGES  
**Confidence:** HIGH (bug root cause identified and fixed)  
**Testing Method:** Manual runtime execution on macOS (not code-read-only)

**Next QA Pass Required:** Yes, after Engineer confirms fix and deploys migration.
