# Engineer Report

## Feature Slug

setlist-swipe-move-song

## Feature Title

Setlist Swipe Move/Copy Song

## Goal

Implement bidirectional swipe gestures on song cards in setlist detail screen. Swipe-left deletes song (existing behavior), swipe-right opens setlist picker to move or copy song to another setlist. Include atomic RPC-based move operation and web/macOS fallback UI with three-dot menu.

## Architect Tasks Completed

- [x] Task 1 — Bidirectional Swipe on Song Cards (completed)
- [x] Task 2 — Swipe-Right Handler (`_handleMoveOrCopySong`) (completed)
- [x] Task 3 — Move/Copy Toggle in Setlist Picker Bottom Sheet (completed)
- [x] Task 4 — Controller & Repository Methods for Move/Copy (completed)
- [x] Task 5 — Web/macOS Fallback UI (three-dot menu) (completed)
- [x] Task 6 — Prevent Move from Catalog (completed)

## Files Created

- `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql` — RPC function for atomic song move operation

## Files Modified

- `lib/features/setlists/setlist_repository.dart` — Added `moveSongBetweenSetlists` method
- `lib/features/setlists/setlist_detail_controller.dart` — Added `copySongToSetlist` and `moveSongToSetlist` methods
- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` — Extended with Move/Copy toggle and source setlist parameters
- `lib/features/setlists/setlist_detail_screen.dart` — Implemented bidirectional swipe, move/copy backgrounds, and web/macOS fallback menu

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 4 warnings (all pre-existing deprecation warnings, none introduced by this implementation)

Warnings are deprecation notices for `onReorder` and `axisAlignment` in unrelated files:

- `lib/features/setlists/new_setlist_screen.dart:984:13` (pre-existing)
- `lib/features/setlists/setlist_detail_screen.dart:2001:29` (pre-existing)
- `lib/features/setlists/setlist_detail_screen.dart:2548:23` (pre-existing)
- `lib/features/setlists/setlists_tab_content.dart:511:25` (pre-existing)

## Test Results

Not run (no automated tests exist for this feature per Architect plan)

## Verification

Manual verification steps per Architect plan:

- Confirmed bidirectional swipe structure implemented (`DismissDirection.horizontal`)
- Confirmed swipe-right background widget created (green, left-aligned)
- Confirmed setlist picker bottom sheet has Move/Copy toggle
- Confirmed toggle is hidden when source is Catalog (defaults to Copy mode)
- Confirmed web/macOS fallback UI with PopupMenuButton three-dot menu
- Confirmed repository RPC method calls `move_song_between_setlists`
- Confirmed controller methods update local state correctly

Database migration not deployed (requires Supabase deployment).

## Deviations From Architect Plan

**Icon Change:** Used `Icons.more_vert` from Material Icons instead of creating new `AppIcons.moreVertical` entry. This is consistent with Flutter/Material conventions and avoids modifying the AppIcons file which was not listed in the plan.

**Repository Method Call:** Used `repository.createSetlist()` directly in setlist_detail_screen.dart instead of creating a wrapper method in SetlistsNotifier. This is consistent with existing patterns in the same file (see line 1298-1305 for identical pattern).

Both deviations follow existing codebase patterns and avoid touching files not listed in the Architect plan.

## Blockers Encountered

**File Corruption During Implementation:** setlist_picker_bottom_sheet.dart experienced corruption during multi-line edits (duplicate field declarations, malformed structure). Resolved by careful multi_replace operations to restore correct class structure.

**Undefined Methods:** Initial implementation referenced non-existent `createSetlist` method on SetlistsNotifier. Resolved by using repository pattern consistent with existing code in the same file.

No remaining blockers.

## Post-Implementation Fixes

**SQL Migration Bug — Override Columns Missing (2026-07-13):**

The initial INSERT statement in `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql` only set `setlist_id, song_id, position`. Per the existing pattern in `addSongToSetlist` (`lib/features/setlists/setlist_repository.dart` lines 3599-3611), the override columns `bpm`, `tuning`, and `duration_seconds` must be explicitly set to `NULL` on insert — otherwise column DEFAULTs apply and silently override the song's actual catalog values.

**Fix Applied:**

```sql
INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
VALUES (p_target_setlist_id, p_song_id, v_max_position + 1, NULL, NULL, NULL);
```

Added SQL comment to document why NULL values are required. Verified `flutter analyze` still reports 0 errors after fix.

**Setlist Count Badge Update Missing (2026-07-13, post-QA):**

After QA approval and manual runtime testing, discovered that the Setlists tab count badges did not update immediately after Move/Copy operations. Users had to manually pull-to-refresh to see updated song counts.

**Root cause:**

1. `copySongToSetlist()` never called `refresh()` on the setlists provider
2. `moveSongToSetlist()` called `refresh()` but did not await it, allowing the method to return before the list was updated

**Fix Applied:**

```dart
// copySongToSetlist() — added refresh before return
if (result == null) return false;

// Refresh setlists list to update song count and duration stats
await ref.read(setlistsProvider.notifier).refresh();

return true;

// moveSongToSetlist() — changed to await refresh
await ref.read(setlistsProvider.notifier).refresh();
```

Verified `flutter analyze` still reports 0 errors. Manual retest confirmed both source and target setlist counts update correctly on Setlists tab without manual refresh.

**Same-Setlist Validation Missing (2026-07-13, post-QA):**

After the count-refresh fix, manual testing revealed that users could select the current setlist as the target for Move/Copy operations. This resulted in no-op operations that still showed success messages ("copied to Current Setlist"), which was confusing.

**Fix Applied:**

Added validation in both `_handleMoveOrCopySong()` and `_handleCopySong()` to check if `targetSetlistId == state.setlistId` after the target is resolved. If true, show an `AlertDialog` with title "Same Setlist" and message indicating the song is already in that setlist, then return early without performing the operation or showing success/error snackbars.

```dart
// Check if target is the same as current setlist
if (targetSetlistId == state.setlistId) {
  if (mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Same Setlist'),
        content: Text(
          '"$songTitle" is already in $targetSetlistName.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return false; // or return; for void methods
}
```

Verified `flutter analyze` still reports 0 errors.

## Ready For QA

**Conditional Yes** — Code implementation is complete and passes `flutter analyze` with 0 errors. Feature is ready for manual UI testing per Architect verification plan (Tier 1).

**Required before QA:**

1. Deploy database migration `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql` to Supabase
2. Verify RPC function `move_song_between_setlists` exists in production database

**Without migration deployment:** Move functionality will fail gracefully with error message "RPC function not found". Copy functionality works immediately (uses existing repository methods).
