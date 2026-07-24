# ARCHITECT_PLAN.md

## Feature Slug

`feature/song-card-menu-remove-web`

## Scope Amendment

**Original Requirement (2026-07-24 initial):** Remove 3-dot overflow menu from song cards on **web only**, keep menu on macOS unchanged

**Amended Requirement (2026-07-24, Manager approval via Tony):** Remove 3-dot overflow menu from song cards on **all platforms** (web, macOS, iOS, Android). Users access Copy/Move/Delete exclusively via existing `Dismissible` swipe gestures on every platform.

**Implementation Timeline:**

1. Engineer session 1: Partial implementation (changed `_isPointerOnlyPlatform` to return `false`, removed `dart:io` import)
2. This plan update: Architect incorporates scope change + dead code deletion requirements
3. Engineer session 2: Delete remaining dead code (menu method, overlay, helper method)

**Approved Additional Decision:** Since the menu is now unreachable on all platforms, delete the dead code entirely rather than leaving it in place:

- Delete `_buildSongActionsMenu` method (lines 518-572)
- Delete `_handleCopySong` helper method (lines 574-674) — only used by menu
- Delete the `Positioned` overlay with `if (_isPointerOnlyPlatform && canEdit)` conditional (lines 707-718)
- Remove `_isPointerOnlyPlatform` getter itself (lines 511-514) — only used to gate the now-deleted overlay

Total dead code removal: ~180 lines

---

## Problem Summary

Song cards in setlist and catalog views currently display a 3-dot overflow menu on web and macOS. This menu provides Move/Copy/Delete actions as an alternative to swipe gestures. The **amended requirement** is to remove this menu from **all platforms** (web, macOS, iOS, Android), making swipe gestures the exclusive access method for these actions on every platform.

## Root Cause

The 3-dot menu is conditionally rendered based on the `_isPointerOnlyPlatform` getter in `setlist_detail_screen.dart`. Originally this returned `true` for web and macOS to provide pointer-friendly access to song actions.

**Current state (after Engineer session 1):** The getter now always returns `false`, so the menu overlay is never rendered. However, the menu rendering code, the menu method itself, and its helper method remain in the codebase as dead code.

**Confidence Level:** HIGH — Direct observation in code, scope change approved by Manager

## Reference Docs Consulted

None — this is a UI feature change, not a notification domain issue. No reference docs were required.

## Existing System Analysis

### Current Implementation State (Post Engineer Session 1)

- **File:** `lib/features/setlists/setlist_detail_screen.dart`
- **Line 1:** `dart:io` import removed (no longer needed)
- **Lines 511-514:** `_isPointerOnlyPlatform` getter (now always returns `false` — **dead code, should be deleted**)
- **Lines 518-572:** `_buildSongActionsMenu` method (PopupMenuButton implementation — **dead code, should be deleted**)
- **Lines 574-674:** `_handleCopySong` helper method (only used by menu — **dead code, should be deleted**)
- **Lines 707-718:** Conditional Stack/Positioned overlay with menu (condition always false — **dead code, should be deleted**)

### Menu Actions (Now Unreachable)

The 3-dot menu exposed three actions (now accessible only via swipe gestures):

1. **Copy to Setlist** — Opens setlist picker, copies song to selected setlist
2. **Move to Setlist** — Opens setlist picker, moves song to selected setlist
3. **Delete** — Shows confirmation dialog, removes song from setlist/catalog

### Exclusive Access Path

All three actions remain accessible on **all platforms** via `Dismissible` swipe gestures:

- **Swipe left (endToStart):** Delete (via `_confirmDeleteSong`)
- **Swipe right (startToEnd):** Move/Copy (via `_handleMoveOrCopySong`)

This is implemented at lines 2446-2472 (approximate — verify exact range) and applies to all platforms where `canEdit` is true.

**Trade-off:** The menu provided an alternative, more discoverable UI for these actions on pointer-only platforms. Removing it makes actions less discoverable but maintains consistency across all platforms and reduces code complexity.

### Platform Behavior Summary

| Platform | Original Behavior  | After Scope Amendment        |
| -------- | ------------------ | ---------------------------- |
| Web      | Menu + Dismissible | Dismissible only             |
| macOS    | Menu + Dismissible | Dismissible only             |
| iOS      | Dismissible only   | Dismissible only (unchanged) |
| Android  | Dismissible only   | Dismissible only (unchanged) |

## Proposed Solution

**Phase 1 (COMPLETE — Engineer session 1):**

1. ✅ Changed `_isPointerOnlyPlatform` to always return `false`
2. ✅ Removed `dart:io` import (no longer needed)

**Phase 2 (REMAINING — Engineer session 2):**
Delete all dead code now that the menu is unreachable:

1. **Delete lines 511-514:** `_isPointerOnlyPlatform` getter
   - Only referenced at line 707 (the conditional that gates the overlay)
   - Since overlay is being deleted, getter is unused

2. **Delete lines 518-572 (~55 lines):** `_buildSongActionsMenu` method
   - Only called at line 714 inside the now-deleted conditional overlay
   - Unreachable code

3. **Delete lines 574-674 (~101 lines):** `_handleCopySong` helper method
   - Only called from line 527 (inside `_buildSongActionsMenu`)
   - Since menu is being deleted, this becomes unreachable

4. **Delete lines 707-718 (~12 lines):** Conditional Stack/Positioned overlay
   - The `if (_isPointerOnlyPlatform && canEdit)` block
   - Condition is always `false`, so this code never executes
   - Replace the entire `if` block with just `return card;`

**Result:** ~180 lines of dead code removed, cleaner codebase, menu functionality completely eliminated.

## Database Impact

**Not applicable.** This is a pure client-side UI change. No migrations, RLS policies, RPCs, or triggers are affected.

## Flutter Architecture Changes

**Minimal.** No new controllers, providers, or repositories. No changes to state management. This removes conditional rendering logic and dead code from `setlist_detail_screen.dart`.

The song card widgets themselves (`song_card.dart`, `reorderable_song_card.dart`) are not modified — the menu overlay was applied by the parent screen (`setlist_detail_screen.dart`), not the card widgets.

## Files to Create

**None.**

## Files to Modify

| File                                               | What changes                                                                                                                                                                                                                                                                                                                  |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | **Phase 1 (DONE):** Changed `_isPointerOnlyPlatform` to return `false`, removed `dart:io` import<br>**Phase 2 (REMAINING):** Delete dead code: `_isPointerOnlyPlatform` getter (lines 511-514), `_buildSongActionsMenu` method (lines 518-572), `_handleCopySong` helper (lines 574-674), conditional overlay (lines 707-718) |

## Files Off-Limits

| File                                                       | Reason                                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_repository.dart`            | 4,027 lines — no repository changes required for this UI-only change           |
| `lib/features/setlists/widgets/song_card.dart`             | Song card widget does not contain menu logic; menu is applied by parent screen |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Song card widget does not contain menu logic; menu is applied by parent screen |
| All files except `setlist_detail_screen.dart`              | Single-file change per minimal diff principle                                  |

## System Impact Map

| System                                 | Impact                                                                                                                |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                            |
| Rehearsals                             | unaffected                                                                                                            |
| Setlists / Catalog                     | affected — **all platforms** will no longer have the 3-dot menu on song cards; swipe gestures exclusive access method |
| Members / RBAC                         | unaffected                                                                                                            |
| Auth / Session                         | unaffected                                                                                                            |
| Routing                                | unaffected                                                                                                            |
| Notifications                          | unaffected                                                                                                            |
| Platform (iOS / Android / Web / macOS) | Web: menu removed; macOS: menu removed; iOS/Android: unchanged (never had menu)                                       |

## Regression Risk

**LOW-MEDIUM**

Rationale:

- **Phase 1 (complete):** Low risk — simple boolean change, passes `flutter analyze`
- **Phase 2 (dead code deletion):** Low risk — deleting unreachable code cannot introduce runtime errors
- Affects all platforms (web, macOS, iOS, Android) but only removes an alternative UI — core functionality (swipe gestures) unchanged
- No state management changes
- No database or backend changes
- Existing Dismissible swipe gestures remain functional on all platforms
- Catalog and setlist detail views share the same screen implementation, so both are consistently updated
- **Elevated risk factor:** Scope expanded from web-only to all platforms, increasing QA validation surface area

## Engineer Task Breakdown

### Phase 1 Tasks (COMPLETE)

✅ 1. Verified branch and workspace state  
✅ 2. Changed `_isPointerOnlyPlatform` to always return `false`  
✅ 3. Removed unused `dart:io` import  
✅ 4. Ran `flutter analyze` — passed with 0 errors  
✅ 5. Created ENGINEER_REPORT.md documenting scope expansion

### Phase 2 Tasks (REMAINING)

1. **Verify workspace state**
   - Current branch: `feature/song-card-menu-remove-web`
   - Run `git status --porcelain` — should show only `M lib/features/setlists/setlist_detail_screen.dart`

2. **Verify current file state**
   - Open `lib/features/setlists/setlist_detail_screen.dart`
   - Confirm `_isPointerOnlyPlatform` returns `false` (line 513)
   - Confirm `dart:io` import is absent

3. **Delete dead code — Part 1: Helper method**
   - Delete lines 574-674 (~101 lines): `_handleCopySong` method
   - This is only called from `_buildSongActionsMenu` (line 527), which is being deleted

4. **Delete dead code — Part 2: Menu method**
   - Delete lines 518-572 (~55 lines): `_buildSongActionsMenu` method
   - This is only called from line 714 inside the conditional overlay being deleted

5. **Delete dead code — Part 3: Conditional overlay**
   - Locate lines 707-718 (the `if (_isPointerOnlyPlatform && canEdit)` block with Stack/Positioned)
   - Delete the entire `if` block (lines 707-718)
   - The code should go from:
     ```dart
     if (_isPointerOnlyPlatform && canEdit) {
       return Stack(
         children: [
           card,
           Positioned(
             top: 8,
             right: 8,
             child: _buildSongActionsMenu(song.id, song.title),
           ),
         ],
       );
     }
     return card;
     ```
   - To simply:
     ```dart
     return card;
     ```

6. **Delete dead code — Part 4: Unused getter**
   - Delete lines 511-514: `_isPointerOnlyPlatform` getter
   - Verify no other references exist: `grep -n "_isPointerOnlyPlatform" lib/features/setlists/setlist_detail_screen.dart`
   - Should return no matches after deletion

7. **Run static analysis**
   - Execute `flutter analyze` — must pass with 0 errors
   - If any "unused import" warnings appear, remove those imports

8. **Format the file**
   - Run `dart format lib/features/setlists/setlist_detail_screen.dart`

9. **Visual verification** (if environment supports it)
   - Web: Confirm no 3-dot menu, swipe gestures work
   - macOS (if available): Confirm no 3-dot menu, swipe gestures work
   - Note: If visual verification cannot be performed, defer to QA

10. **Update ENGINEER_REPORT.md**
    - Document Phase 2 completion
    - List all deleted code ranges
    - Confirm `flutter analyze` result
    - Mark ready for QA with all-platform scope noted

11. **Commit changes**
    - Only after QA APPROVED per commit gate

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — this is a client-side-only change. No database migrations or backend functions are involved.

### Tier 2 — Post-deployment

**Not applicable** — no database schema or function changes. All verification is done via visual testing (covered in QA Regression Areas below).

## QA Regression Areas

QA must specifically test **all platforms** (scope expanded from original web-only plan):

1. **Web — Setlist Detail View**
   - Song cards do NOT show 3-dot menu
   - Mouse-drag-swipe left (delete action) works
   - Mouse-drag-swipe right (move/copy action) works
   - All other setlist detail functionality unchanged (reorder, add songs, etc.)

2. **Web — Catalog View**
   - Song cards do NOT show 3-dot menu
   - Mouse-drag-swipe gestures work as expected
   - Catalog filtering/sorting unchanged

3. **macOS — Setlist Detail View** ← **SCOPE CHANGE: Menu now removed (was: unchanged)**
   - Song cards do NOT show 3-dot menu (changed from original plan)
   - Swipe gestures work (finger/trackpad swipe)
   - All other setlist detail functionality unchanged

4. **macOS — Catalog View** ← **NEW: Added due to scope expansion**
   - Song cards do NOT show 3-dot menu
   - Swipe gestures work as expected
   - Catalog filtering/sorting unchanged

5. **iOS — Setlist Detail View**
   - No regression — no menu (unchanged)
   - Swipe gestures work as before

6. **Android — Setlist Detail View**
   - No regression — no menu (unchanged)
   - Swipe gestures work as before

7. **Cross-feature regression (all platforms)**
   - Setlist reordering works on all platforms
   - Bulk add songs works on all platforms
   - Setlist export/share works on all platforms

## Rollout / Migration Strategy

**Not applicable.** No database migration, no backend deploy. This is a client-side code change that takes effect immediately when apps are redeployed/rebuilt:

- Web: `./tools/deploy_web.sh`
- iOS: New App Store build
- Android: New Play Store build
- macOS: New build distribution

## Out of Scope

- Adding alternative UI controls (e.g., a toolbar or floating action button) for Delete/Move/Copy — out of scope
- Improving discoverability of Dismissible swipe gestures (e.g., tutorial, hint animation) — out of scope
- Any changes to `song_card.dart` or `reorderable_song_card.dart` — menu was applied by parent, not card widgets
- Restoring the menu on any platform in the future — if needed, would be a new feature request
