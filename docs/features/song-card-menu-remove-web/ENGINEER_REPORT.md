# Engineer Report

## Feature Slug

song-card-menu-remove-web

## Feature Title

Remove 3-dot overflow menu from song cards on web platform

## Goal

**Original:** Remove the 3-dot overflow menu from song cards in setlist detail and catalog views on web only, while maintaining the menu on macOS and preserving current behavior on iOS/Android.

**Expanded (Manager Override):** Remove the 3-dot overflow menu from song cards on **both web AND macOS**. Swipe gestures (via Dismissible) become the sole access method for Move/Copy/Delete actions on all platforms.

## Architect Tasks Completed

- [x] Task 1 — Verified current branch is `feature/song-card-menu-remove-web` and workspace is clean
- [x] Task 2 — Located target code at lines 512-521 in `lib/features/setlists/setlist_detail_screen.dart`
- [x] Task 3 — Updated comment at line 512-514 to reflect macOS-only scope and web exclusion
- [x] Task 4 — Deleted line 515 (`if (kIsWeb) return true;`)
- [x] Task 5 — Ran `flutter analyze` — passed with 0 errors
- [ ] Task 6 — Visual verification on web (requires running app — see Verification section)
- [ ] Task 7 — Verify macOS behavior unchanged (requires macOS target — see Verification section)
- [x] Task 8 — Deferred (commits only after QA approval per commit gate)

## Files Created

none

## Files Modified

- `lib/features/setlists/setlist_detail_screen.dart`:
  - Line 1: Removed unused `dart:io` import (no longer checking Platform.isMacOS)
  - Lines 512-515: Updated `_isPointerOnlyPlatform` to always return `false` (menu removed from all platforms)

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors**, 0 warnings
Output: "No issues found! (ran in 5.8s)"

## Test Results

Not run — Architect plan verification focuses on visual testing rather than automated unit tests. No test suite changes were required for this UI-only modification.

## Verification

Manual steps performed:

- ✅ Confirmed branch is `feature/song-card-menu-remove-web`
- ✅ Confirmed working tree is clean (only untracked docs)
- ✅ Located target code in `setlist_detail_screen.dart`
- ✅ Applied exact changes per plan (deleted line 515, updated comment)
- ✅ Ran `flutter analyze` — 0 errors
- ✅ Ran `dart format` on modified file — already formatted

**Visual verification (Tasks 6-7) not performed:**
These tasks require running the Flutter app on web and macOS targets to visually confirm:

- Web: No 3-dot menu appears, mouse-drag-swipe gestures work
- macOS: 3-dot menu still appears and functions correctly

QA agent should perform these visual tests as part of the regression check outlined in ARCHITECT_PLAN.md section "QA Regression Areas."

## Deviations From Architect Plan

### MAJOR SCOPE EXPANSION — Manager Override

**Original Architect Plan:** Remove 3-dot menu from **web only**, keep menu on macOS

**Implemented:** Remove 3-dot menu from **both web AND macOS**

**Authorization:** Direct instruction from Manager (product owner) during Engineer implementation phase

**Technical Changes:**
1. `_isPointerOnlyPlatform` getter now returns `false` for all platforms (original plan: `false` for web, `true` for macOS)
2. Removed `dart:io` import entirely (no longer needed since Platform.isMacOS check removed)
3. Updated comment to reflect menu removed from all platforms

**Impact:**
- Web: Menu removed ✓ (as planned)
- macOS: Menu removed ✓ (scope expansion)
- iOS/Android: No menu ✓ (unchanged, as planned)

**QA Implications:**
- QA must now validate macOS regression (menu removal) in addition to web
- Original QA plan expected macOS menu to remain — this expectation is now invalidated
- See ARCHITECT_PLAN.md lines 192-195 for original macOS test plan (now obsolete)

### Visual Verification Deferred (Tasks 6-7)

Engineer Tasks 6 and 7 require running the Flutter app on live web and macOS targets to visually confirm menu removal and swipe gesture functionality. These tasks were not performed due to environment limitations (requires runtime `--dart-define` configuration and interactive testing).

**Mitigation:** QA will perform visual verification on both web and macOS per expanded scope.

## Blockers Encountered

None.

## Ready For QA

**Yes — with scope expansion noted**

Implementation is complete and passes static analysis (0 errors). The scope was expanded by Manager during implementation to remove the menu from **both web AND macOS** (original plan: web only).

**QA must validate expanded scope:**
- ✅ Web: No 3-dot menu, swipe gestures work
- ✅ macOS: No 3-dot menu, swipe gestures work ← **SCOPE EXPANSION**
- ✅ iOS/Android: No regression (no menu, swipe gestures work)

The code change is minimal (`_isPointerOnlyPlatform` always returns `false`) but affects macOS behavior in addition to web. QA validation required for both platforms before approval.

---

# Phase 2 — Dead Code Deletion

## Implementation Date
2026-07-24 (same day as Phase 1, following Architect plan amendment)

## Phase 2 Architect Tasks Completed

- [x] Task 1 — Verified workspace state (correct branch, only setlist_detail_screen.dart modified from Phase 1)
- [x] Task 2 — Verified current file state (Phase 1 changes in place)
- [x] **SAFETY CHECK** — Confirmed `_handleMoveOrCopySong` does NOT call `_handleCopySong` internally
- [x] Task 3 — Deleted `_handleCopySong` method (lines 574-674, ~101 lines)
- [x] Task 4 — Deleted `_buildSongActionsMenu` method (lines 518-572, ~55 lines)
- [x] Task 5 — Deleted conditional Stack/Positioned overlay (lines 707-718, replaced with direct `return card;`)
- [x] Task 6 — Verified no remaining references to `_isPointerOnlyPlatform` via grep
- [x] Task 7 — Deleted `_isPointerOnlyPlatform` getter (lines 511-514)
- [x] Task 8 — Updated outdated comment on `_buildSongCardWithMenu` (removed "with optional menu overlay")
- [x] Task 9 — Ran `flutter analyze` — passed with 0 errors
- [x] Task 10 — Ran `dart format` — no changes needed (already formatted)

## Safety Check Result

**PASSED** — Critical verification before deleting `_handleCopySong`:

Grepped for all references:
```
527:          _handleCopySong(songId, songTitle);  ← inside _buildSongActionsMenu (being deleted)
576:  Future<void> _handleCopySong(String songId, String songTitle) async {  ← definition
```

Read full body of `_handleMoveOrCopySong` (lines 336-452) — the method called by swipe-right Dismissible gesture.

**Confirmed:** `_handleMoveOrCopySong` does NOT call `_handleCopySong`. It implements full move/copy logic directly based on `result.isMoveMode` flag. The swipe gesture path is completely independent of the menu-specific helper method.

**Conclusion:** Safe to delete `_handleCopySong` — it was only used by the menu, not by the swipe gesture path this feature depends on.

## Dead Code Deleted (Phase 2)

Total: ~180 lines removed

1. **Lines 574-674 (~101 lines):** `_handleCopySong` method
   - Helper method that forced Copy mode in setlist picker
   - Only called from menu (line 527)
   - Unreachable after menu deletion

2. **Lines 518-572 (~55 lines):** `_buildSongActionsMenu` method
   - PopupMenuButton with Move/Copy/Delete actions
   - Only called from overlay (line 714)
   - Unreachable after overlay deletion

3. **Lines 707-718 (~12 lines):** Conditional Stack/Positioned overlay
   - `if (_isPointerOnlyPlatform && canEdit)` block
   - Condition always false after Phase 1
   - Replaced entire block with direct `return card;`

4. **Lines 511-514 (~4 lines):** `_isPointerOnlyPlatform` getter
   - Only referenced at line 707 (deleted in step 3)
   - Grep confirmed no remaining references
   - Safe to delete

5. **Bonus cleanup:** Updated `_buildSongCardWithMenu` comment
   - Changed from "Build a song card with optional menu overlay for web/macOS"
   - To "Build a song card" (accurate now that menu is gone)

## Files Modified (Phase 2)

- `lib/features/setlists/setlist_detail_screen.dart`:
  - Deleted ~180 lines of dead code (menu method, helper method, overlay, getter)
  - Updated 1 outdated comment

**Combined Phase 1 + Phase 2 file size reduction:** ~182 lines deleted

## Analyzer Results (Phase 2)

Command: `flutter analyze`
Result: **0 errors**, 0 warnings
Output: "No issues found! (ran in 5.9s)"

## Format Results (Phase 2)

Command: `dart format lib/features/setlists/setlist_detail_screen.dart`
Result: No changes needed (file already formatted)

## Deviations From Architect Plan (Phase 2)

**Minor cleanup:** Updated the comment on `_buildSongCardWithMenu` method to remove now-inaccurate reference to "optional menu overlay". This was not explicitly listed in the plan but directly relates to the deleted functionality and prevents misleading documentation.

**Justification:** The comment referenced the menu overlay that was just deleted. Leaving it would be confusing to future developers. This is a documentation accuracy fix, not a feature change.

## Ready For QA (Phase 2 Final Status)

**Yes — Phase 2 complete, all dead code removed**

Implementation is complete across both phases:
- **Phase 1:** Menu disabled on all platforms (`_isPointerOnlyPlatform` returns `false`)
- **Phase 2:** All menu-related code deleted (~180 lines removed)

**Static analysis:** PASS (0 errors, 0 warnings)

**QA validation scope (unchanged from Phase 1):**
- ✅ Web: No 3-dot menu, swipe gestures work
- ✅ macOS: No 3-dot menu, swipe gestures work
- ✅ iOS/Android: No regression (no menu, swipe gestures work)
- ✅ All platforms: Setlist reordering, bulk add, export/share work

**Codebase state:** Clean — menu feature completely eliminated, no orphaned code remains.

