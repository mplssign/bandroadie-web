# Architect Plan — Swipe-Right to Move/Copy Song Between Setlists

## Feature Slug

`feature/setlist-swipe-move-song`

## Problem Summary

Users can currently swipe LEFT on song cards in setlist detail view to delete songs, but there is no swipe gesture to move or copy a song to a different setlist. To move a song today, a user must: (1) delete it from the current setlist, (2) navigate to another setlist or the Catalog, (3) find the song, and (4) add it. This is cumbersome for reorganizing setlists or building new setlists from existing ones.

The requested feature adds swipe RIGHT on song cards to trigger the existing setlist picker bottom sheet (`setlist_picker_bottom_sheet.dart`), extended with a Move/Copy toggle. **Move** removes the song from the current setlist and adds it to the target setlist via atomic RPC. **Copy** adds the song to the target setlist while leaving it in the current setlist (existing add behavior).

On pointer-only platforms (web, macOS), swipe gestures are not ergonomic. A visible fallback action (icon button on song card or context menu) is required so the feature is fully accessible without touch.

## Root Cause

**Confidence: HIGH — Confirmed by code inspection**

This is a new feature, not a bug. The current implementation intentionally supports only LEFT swipe (delete) on song cards, as seen in `setlist_detail_screen.dart`:

```dart
Dismissible(
  direction: canEdit ? DismissDirection.endToStart : DismissDirection.none,
  ...
)
```

`DismissDirection.endToStart` restricts swipe to LEFT only. Setlist cards (in `swipeable_setlist_card.dart`) demonstrate the pattern for bidirectional swipe:

```dart
swipeDirection = DismissDirection.horizontal; // Allow both directions
background: _buildDuplicateBackground(), // Shown when swiping right
secondaryBackground: _buildDeleteBackground(), // Shown when swiping left
```

Two UIs exist for adding songs to setlists:

1. **`add_to_setlist_overlay.dart`** — Full-screen category picker (Cover, Original, Bulk, Set Break, Pause). Used when adding _new_ content to a setlist via the "+ Add to Setlist" button.
2. **`setlist_picker_bottom_sheet.dart`** — Bottom sheet that lists existing setlists for selection. Used when moving/copying _existing_ songs from Catalog to a target setlist.

For swipe-right on song cards, the user needs to pick a _target setlist_, not a content type. Therefore, **`setlist_picker_bottom_sheet.dart`** is the correct UI to reuse and extend with a Move/Copy toggle.

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — setlist_songs table schema, position ordering, RPC functions
- `docs/agents/GUARDRAILS.md` — code change discipline, file size targets, data integrity rules
- `docs/agents/OPERATING_MODEL.md` — unidirectional data flow, Riverpod state management pattern
- `.github/copilot-instructions.md` — BandRoadie architecture, feature-first structure, setlist ordering rules

No domain-specific reference docs exist for setlist UI patterns. Relevant implementation patterns were extracted from existing code.

## Existing System Analysis

### Current Swipe Behavior on Song Cards

Song cards in `setlist_detail_screen.dart` are wrapped in `Dismissible` widgets with:

- **Direction:** `DismissDirection.endToStart` (LEFT swipe only)
- **Action:** Delete (after confirmation dialog)
- **Background:** Red with "Delete" label and trash icon
- **Confirm dismiss:** `_confirmDeleteSong` shows dialog, calls `notifier.deleteSong(songId)`, always returns `false` (state update removes item from tree)

Song cards do NOT currently support swipe RIGHT. There is no context menu, long-press handler, or visible action button for Move/Copy on pointer-only platforms.

### Bidirectional Swipe Pattern (Setlist Cards)

`swipeable_setlist_card.dart` implements LEFT/RIGHT swipe on setlist cards:

- **LEFT (endToStart):** Delete — red background, trash icon
- **RIGHT (startToEnd):** Duplicate — green background, copy icon
- **Direction:** `DismissDirection.horizontal` (both directions enabled)
- **Haptic feedback:** Medium impact at 30% threshold, heavy impact on confirm
- **Confirm dismiss:** Always returns `false` (state management handles removal)

This pattern is proven and can be adapted for song cards.

### Setlist Picker Bottom Sheet Flow

`setlist_picker_bottom_sheet.dart` is a bottom sheet modal that shows:

1. **List of existing setlists** (excluding Catalog)
2. **"Create New Setlist" option** with inline name input

The sheet is invoked from `setlist_detail_screen.dart` in the Catalog view when user selects songs and taps "Add To Setlist" button (line ~1015: `showSetlistPickerBottomSheet`). It returns a `SetlistPickerResult` with either an existing setlist ID or a new setlist name.

**Current behavior is always Copy:** Adding a song to a setlist never removes it from the source. This is correct for Catalog → Setlist (Catalog is the source of truth). But when moving from Setlist A → Setlist B, the user may want to **Move** (remove from A) or **Copy** (keep in both).

**Dark-mode fix:** PR #56 (commit `769ccdb`, 2026-07-10) fixed `setlist_picker_bottom_sheet.dart` to use `context.colors.surface` instead of hardcoded color, resolving duplicate rendering in dark mode.

### Repository Operations

`setlist_repository.dart` provides:

- `addSongToSetlist(setlistId, songId)` — Adds song at end (max position + 1), returns setlist_song ID
- `deleteSongFromSetlist(bandId, setlistId, songId)` — Removes from setlist_songs table (not from Catalog)
- `deleteSongFromCatalog(bandId, songId)` — Removes from songs table (cascades to all setlists)
- `reorderSongs(setlistId, songIdsInOrder)` — Uses `reorder_setlist_songs` RPC for atomic position updates

**Move operation must be atomic** per GUARDRAILS.md #6 ("All data writes must be atomic"). The client-side approach of calling `addSongToSetlist` then `deleteSongFromSetlist` violates this rule — if delete fails, the song exists in both setlists (partial failure). A new `SECURITY DEFINER` RPC `move_song_between_setlists` will perform insert + delete as one transaction.

**Position integrity:** Adding to target setlist places the song at the end. Removing from source setlist leaves a gap in position sequence, but the UI always queries `ORDER BY position ASC` so display order is correct.

### Platform Detection

The codebase uses `kIsWeb` from `package:flutter/foundation.dart` to detect web platform. Desktop platforms (macOS, Windows, Linux) are detected via `Platform.isMacOS` from `dart:io` (guarded by `!kIsWeb` to avoid compilation errors on web).

Touch gestures are available on mobile (iOS, Android) and partially on trackpad (macOS with gestures enabled). Web browsers do not reliably support swipe gestures with mouse-only input. A fallback UI is required for pointer-only platforms.

## Proposed Solution

### 1. Add Bidirectional Swipe to Song Cards

Modify the `Dismissible` wrapper around `ReorderableSongCard` in `setlist_detail_screen.dart` to support both LEFT and RIGHT swipe:

- **LEFT (endToStart):** Delete — existing behavior unchanged
- **RIGHT (startToEnd):** Move/Copy to another setlist — new behavior

Change `direction` from `DismissDirection.endToStart` to `DismissDirection.horizontal`.

Add a second background widget for swipe RIGHT (similar to setlist cards):

- Green/rose background with "Move/Copy" label and arrow icon
- Aligned to left (revealed when swiping right)

Update `confirmDismiss` to branch on `DismissDirection`:

- `DismissDirection.endToStart` → Call `_confirmDeleteSong` (existing)
- `DismissDirection.startToEnd` → Call new `_handleMoveOrCopySong` method

### 2. Extend Setlist Picker Bottom Sheet with Move/Copy Toggle

The setlist picker bottom sheet (`setlist_picker_bottom_sheet.dart`) is the correct UI to reuse. Extend `showSetlistPickerBottomSheet` function signature to accept optional source setlist context:

```dart
Future<SetlistPickerResult?> showSetlistPickerBottomSheet(
  BuildContext context, {
  int? selectedSongCount,
  String? sourceSetlistId,        // NEW: if provided, show Move/Copy toggle
  String? sourceSetlistName,      // NEW: for display context
})
```

When `sourceSetlistId` is non-null, render a Move/Copy toggle (segmented button or switch) in the bottom sheet header (below the "Adding N songs" subtitle). Default to **Copy** to preserve existing add behavior.

The toggle allows the user to choose:

- **Copy mode:** Add song to target setlist, leave in source (existing behavior)
- **Move mode:** Add song to target setlist via atomic RPC, remove from source (new behavior)

If the source setlist is Catalog (`isCatalogName(sourceSetlistName)`), hide or disable the Move option — songs cannot be moved out of Catalog.

Return the Move/Copy mode selection in `SetlistPickerResult` (add `isMoveMode` boolean field).

After the user selects a target setlist, invoke the appropriate repository operation:

- **Copy mode:** `addSongToSetlist(targetSetlistId, songId)` (existing behavior)
- **Move mode:** `moveSongBetweenSetlists(sourceSetlistId, targetSetlistId, songId, bandId)` (new RPC-backed atomic operation)

### 3. Add Controller Method for Atomic Move Operation

Add a new method to `SetlistDetailNotifier` in `setlist_detail_controller.dart` that calls the RPC-backed repository method:

```dart
Future<bool> moveSongToSetlist({
  required String songId,
  required String targetSetlistId,
  required String sourceSetlistId,
}) async {
  try {
    final success = await _repository.moveSongBetweenSetlists(
      sourceSetlistId: sourceSetlistId,
      targetSetlistId: targetSetlistId,
      songId: songId,
      bandId: state.bandId,
    );

    if (!success) return false;

    // Update local state - remove song from current setlist
    state = state.copyWith(
      songs: state.songs.where((s) => s.id != songId).toList(),
      items: state.items.where((item) => item.song?.id != songId).toList(),
    );

    return true;
  } catch (e) {
    debugPrint('[SetlistDetail] Move failed: $e');
    return false;
  }
}
```

The RPC `move_song_between_setlists` handles both insert and delete as a single atomic transaction. If the RPC fails, no partial state occurs — the operation is all-or-nothing.

The copy operation already exists via `addSongToSetlist` — no new method needed.

### 4. Provide Fallback for Web/macOS (Pointer-Only Platforms)

Swipe gestures are not ergonomic or discoverable on web/macOS with mouse/trackpad. Add a visible action button to song cards that opens a context menu with "Move to Setlist" and "Copy to Setlist" options.

**Implementation approach:**

1. Detect platform via `kIsWeb || Platform.isMacOS`
2. If pointer-only, show a three-dot menu icon (⋯) on the right side of the song card (next to delete icon)
3. Tapping the menu icon shows `PopupMenuButton` with:
   - "Move to Setlist…"
   - "Copy to Setlist…"
   - Divider
   - "Delete" (alternative to swipe-left)
4. Selecting "Move to Setlist…" or "Copy to Setlist…" opens the setlist picker bottom sheet with Move/Copy mode pre-selected

This ensures feature parity across all platforms without relying on swipe gestures.

### 5. Prevent Move from Catalog

The Catalog is the source of truth for songs. Moving a song "out of" the Catalog makes no semantic sense (songs in other setlists are references, not moves). When the current setlist is the Catalog, disable the Move option:

- If `state.isCatalog == true`, swipe-right shows "Copy to Setlist" only (no toggle)
- The Move/Copy toggle is hidden or Move option is disabled

This matches the existing pattern for setlist cards: Catalog setlist cards cannot be deleted (only duplicated).

## Database Impact

**Migration required.** A new `SECURITY DEFINER` RPC function is required to perform atomic move operations:

### New RPC: `move_song_between_setlists`

**Purpose:** Atomically move a song from source setlist to target setlist (insert into target + delete from source) in one transaction.

**Signature:**

```sql
move_song_between_setlists(
  p_source_setlist_id UUID,
  p_target_setlist_id UUID,
  p_song_id UUID,
  p_band_id UUID
) RETURNS JSON
```

**Behavior:**

- Verify user is active member of band (RLS enforcement)
- Verify source and target setlists belong to band
- Get max position in target setlist
- Insert into `setlist_songs` (target setlist, next position)
- Delete from `setlist_songs` (source setlist)
- Return JSON: `{"success": true, "moved_count": 1}` or `{"success": false, "error": "..."}`

**Transaction safety:** All operations wrapped in plpgsql function body (implicit transaction). If any step fails, entire operation rolls back.

**RLS bypass:** `SECURITY DEFINER` with explicit band membership check (follows `update_song_metadata` pattern).

**Search path:** `SET search_path = public` (per GUARDRAILS.md #4).

### Tables Affected

- `setlist_songs` — INSERT (target) + DELETE (source), no schema changes

### RLS Policies

- No policy changes — RPC uses `SECURITY DEFINER` with explicit membership check

### Migration File

- `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql`

## Flutter Architecture Changes

### State Management (Riverpod)

- **Controller:** `SetlistDetailNotifier` gains new `moveSongToSetlist` method
- **State:** `SetlistDetailState` unchanged (existing song list is updated after move)
- **No new providers required**

### Widgets Modified

1. `setlist_detail_screen.dart` — Update `Dismissible` direction, add swipe-right background, add `_handleMoveOrCopySong` method
2. `setlist_picker_bottom_sheet.dart` — Add optional source setlist parameters, add Move/Copy toggle widget in header
3. `reorderable_song_card.dart` — Add optional three-dot menu icon for web/macOS fallback (if using PopupMenuButton directly on card)

### Widgets Created

**Option A (Preferred):** No new widget files — toggle is a simple `SegmentedButton` or `Row` with two `GestureDetector` chips inline in the bottom sheet header.

**Option B (If toggle is complex):** Create `lib/features/setlists/widgets/move_copy_toggle.dart` for a reusable toggle widget. Justified only if the toggle requires significant state management or animation.

**Recommendation:** Inline the toggle in `setlist_picker_bottom_sheet.dart` as a simple stateful widget nested in the header. No new file needed unless toggle complexity exceeds ~50 lines.

## Files to Create

### Required

- **`supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql`** — Creates `move_song_between_setlists` RPC function (`SECURITY DEFINER`, `SET search_path = public`). Performs atomic insert-into-target + delete-from-source transaction. Returns JSON with success/error.

### Optional

- **`lib/features/setlists/widgets/move_copy_toggle.dart`** — Only if toggle implementation exceeds 50 lines. Reusable toggle widget (rose accent for active state, gray for inactive, smooth transition). Prefer inlining in `setlist_picker_bottom_sheet.dart` header.

## Files to Modify

| File                                                             | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`               | 1. Change Dismissible direction from `endToStart` to `horizontal` for song cards (3 locations: lines ~2094, ~2158, ~2223). 2. Add swipe-right background widget (green/rose, left-aligned, "Move/Copy" label + arrow icon). 3. Add `_handleMoveOrCopySong(songId, songTitle)` method that opens setlist picker bottom sheet with source setlist context. 4. Add platform detection for web/macOS and conditionally render three-dot menu icon on song cards. 5. Add `PopupMenuButton` or context menu handler for "Move to Setlist" / "Copy to Setlist" options. |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | 1. Add optional `sourceSetlistId` and `sourceSetlistName` parameters to `showSetlistPickerBottomSheet` function. 2. Add Move/Copy toggle widget in header (below title, above setlist list) — only shown when `sourceSetlistId != null`. 3. Track toggle state (Move/Copy) in `_SetlistPickerSheetState`. 4. Pass Move/Copy mode in returned `SetlistPickerResult` (add `isMoveMode` boolean field). 5. Hide Move option if source setlist is Catalog. 6. Preserve theme-aware colors (no dark-mode regression from PR #56 commit `769ccdb`).                    |
| `lib/features/setlists/setlist_detail_controller.dart`           | 1. Add `moveSongToSetlist` method that calls new RPC `move_song_between_setlists` via repository. 2. Update local state after move to remove song from current setlist's song list. 3. Add `copySongToSetlist` method (wrapper around existing `addSongToSetlist`) for clarity.                                                                                                                                                                                                                                                                                  |
| `lib/features/setlists/setlist_repository.dart`                  | 1. Add `moveSongBetweenSetlists` method that calls new RPC `move_song_between_setlists` with error handling. 2. Return success boolean. 3. Log RPC response for debugging. 4. Handle RPC not found error (fallback to error message — do not attempt client-side fallback, atomicity is required).                                                                                                                                                                                                                                                               |

## Files Off-Limits

| File                                                            | Reason                                                                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                 | Initialization order must not change — no init logic affected by this feature                                                        |
| `lib/features/setlists/widgets/song_card.dart`                  | This is the basic read-only song card — all interactive behavior is in `reorderable_song_card.dart` and parent `Dismissible` wrapper |
| `lib/features/setlists/widgets/swipeable_setlist_card.dart`     | Setlist card swipe behavior is unrelated — do not cross-contaminate                                                                  |
| `lib/features/setlists/widgets/add_to_setlist/*.dart`           | Category overlay sub-screens (original_song_screen, bulk_entry_screen, etc.) are unaffected by this feature                          |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` | Tuning picker is unrelated — do not cross-contaminate                                                                                |

## System Impact Map

| System                                 | Impact                                                                                                                                  |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **unaffected** — gig setlists are read-only references, not modified by this feature                                                    |
| Rehearsals                             | **unaffected** — rehearsal setlists are read-only references, not modified by this feature                                              |
| Setlists / Catalog                     | **affected** — core feature modifies setlist song membership and ordering                                                               |
| Members / RBAC                         | **unaffected** — no permission changes, existing RLS policies govern setlist mutations                                                  |
| Auth / Session                         | **unaffected** — no auth flow changes                                                                                                   |
| Routing                                | **unaffected** — no new routes, overlay is modal over existing screen                                                                   |
| Notifications                          | **unaffected** — setlist changes do not trigger push notifications                                                                      |
| Platform (iOS / Android / Web / macOS) | **affected** — swipe gestures available on touch platforms (iOS, Android), fallback UI required for pointer-only platforms (web, macOS) |

## Regression Risk

**MEDIUM**

### Risk Factors:

1. **Bidirectional swipe on song cards** — Gesture conflict potential. The existing swipe-left (delete) must remain reliable. Accidental swipe-right triggering move/copy could confuse users if not clearly signaled (haptic feedback, visual background).
2. **Dismissible widget state management** — Always returning `false` from `confirmDismiss` is critical (state update removes item). Returning `true` would cause "dismissed Dismissible still in tree" error. This pattern is proven in `swipeable_setlist_card.dart` but must be replicated carefully.
3. **Setlist picker bottom sheet modification** — The bottom sheet was recently fixed for dark-mode rendering (PR #56, commit `769ccdb`, 2026-07-10, modified `setlist_picker_bottom_sheet.dart` to use `context.colors.surface`). Adding a Move/Copy toggle must preserve theme-aware colors (`context.colors.background`, `context.colors.border`, `context.colors.surface`). Any regression in bottom sheet rendering affects all setlist selection flows, not just this feature.
4. **Atomic move operation via RPC** — The RPC must correctly handle insert + delete as one transaction. If the RPC is not deployed or fails, the move operation must fail gracefully with a clear error message (no partial state).
5. **Position ordering integrity** — Moving a song removes it from source setlist (creates a gap in position sequence) and adds it to target setlist (at end). The UI always queries `ORDER BY position ASC` so display order is correct. If reordering is triggered during move, there is potential for race conditions if multiple users are editing the same setlist concurrently.

### Mitigation:

- Use `DismissDirection.horizontal` with distinct backgrounds (red for left, green/rose for right) to avoid gesture ambiguity.
- Always return `false` from `confirmDismiss` for both directions — state management handles removal.
- Reuse existing theme-aware color tokens (`context.colors.*`) from PR #56 pattern (commit `769ccdb`).
- Deploy RPC migration before code deployment — verify RPC exists in production before releasing app build.
- Test position integrity after move — verify `ORDER BY position ASC` displays correct sequence in both source and target setlists.
- Platform-gate the three-dot menu icon — only render on `kIsWeb || Platform.isMacOS`.

### Regression Test Areas:

- Swipe-left to delete (existing behavior must remain unchanged)
- Swipe-right on setlist cards (existing duplicate behavior must not be affected)
- Setlist picker bottom sheet dark mode rendering (no visual regression from PR #56 commit `769ccdb`)
- Drag-to-reorder on song cards (must not conflict with swipe gestures or menu icon)
- Tap-to-edit BPM/Duration/Tuning (must not conflict with menu icon on web/macOS)

## Engineer Task Breakdown

### Task 1: Add Bidirectional Swipe to Song Cards

**File:** `lib/features/setlists/setlist_detail_screen.dart`

1. Locate all three `Dismissible` wrappers around song cards (lines ~2094, ~2158, ~2223).
2. Change `direction: canEdit ? DismissDirection.endToStart : DismissDirection.none` to `direction: canEdit ? DismissDirection.horizontal : DismissDirection.none`.
3. Add a `_buildMoveOrCopyBackground()` method that returns a green/rose Container aligned left with "Move/Copy" label and arrow icon (mirror pattern from `swipeable_setlist_card.dart`).
4. Set `background: _buildMoveOrCopyBackground()` in all three Dismissible widgets (existing `secondaryBackground` is the red delete background).
5. Update `confirmDismiss` callback to branch on `DismissDirection`:
   ```dart
   confirmDismiss: (direction) {
     if (direction == DismissDirection.endToStart) {
       return _confirmDeleteSong(song.id, song.title);
     } else {
       return _handleMoveOrCopySong(song.id, song.title);
     }
   }
   ```
6. Implement `_handleMoveOrCopySong(String songId, String songTitle)` method (see Task 2).
7. Add haptic feedback in `_handleMoveOrCopySong` (`HapticFeedback.mediumImpact()` on swipe threshold).

**Verification:**

- Swipe LEFT on song card → red background, delete confirmation dialog (existing behavior).
- Swipe RIGHT on song card → green/rose background, opens setlist picker bottom sheet with Move/Copy toggle.
- Both gestures coexist without conflict.

### Task 2: Implement Move/Copy Song Handler in Detail Screen

**File:** `lib/features/setlists/setlist_detail_screen.dart`

1. Add `_handleMoveOrCopySong(String songId, String songTitle)` method that:
   - Reads current setlist ID and name from `ref.read(setlistDetailProvider)`.
   - Opens setlist picker bottom sheet via `showSetlistPickerBottomSheet` with `sourceSetlistId` and `sourceSetlistName` parameters.
   - Receives `SetlistPickerResult` with `isMoveMode` boolean.
   - Returns `false` immediately (do not wait for result — Dismissible should not remove item from tree).
2. Handle result from bottom sheet:
   - If result is null (cancelled), do nothing.
   - If result has `createNew == true`, create new setlist first (existing pattern).
   - If `isMoveMode == true`: Call `ref.read(setlistDetailProvider.notifier).moveSongToSetlist(songId, targetSetlistId, sourceSetlistId)`.
   - If `isMoveMode == false`: Call `ref.read(setlistDetailProvider.notifier).copySongToSetlist(songId, targetSetlistId)`.
3. Show success snackbar with song title and target setlist name.
4. Show error snackbar if operation fails.
5. Add `_handleCopySong(String songId, String songTitle)` method (similar but forces Copy mode for web/macOS menu).

**Verification:**

- Swipe RIGHT on song card → bottom sheet opens with Move/Copy toggle.
- Select Move mode, choose target setlist → song removed from current setlist, added to target.
- Select Copy mode, choose target setlist → song remains in current setlist, added to target.

### Task 3: Extend Setlist Picker Bottom Sheet with Move/Copy Toggle

**File:** `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`

1. Add optional parameters to `showSetlistPickerBottomSheet` function:
   ```dart
   String? sourceSetlistId,
   String? sourceSetlistName,
   ```
2. Pass these parameters to `_SetlistPickerSheet` widget.
3. Add `isMoveMode` field to `SetlistPickerResult` class:
   ```dart
   final bool isMoveMode;
   ```
4. In `_SetlistPickerSheetState`, add:
   - `bool _isMoveMode = false;` state variable (default to Copy).
   - If `widget.sourceSetlistId != null`, render a Move/Copy toggle in the header (below subtitle "Adding N songs").
5. Implement toggle UI:
   - Use `SegmentedButton` with two options: "Copy" and "Move".
   - Rose accent for selected option, gray for unselected.
   - Label: "Copy" and "Move" (keep concise — subtitle already explains context).
6. If source setlist is Catalog (`isCatalogName(sourceSetlistName)`), hide the Move option or disable it (only Copy available).
7. When user selects a setlist or creates a new one, return `SetlistPickerResult` with `isMoveMode` value.
8. Ensure all theme-aware colors use `context.colors.*` tokens (preserve PR #56 fix from commit `769ccdb`).

**Verification:**

- Open bottom sheet from swipe-right → toggle is visible, defaults to Copy.
- Toggle between Copy and Move → rose accent follows selection.
- Source setlist is Catalog → Move option is hidden/disabled.
- Dark mode → bottom sheet renders correctly (no white-on-white or black-on-black).

### Task 4: Add Controller and Repository Methods for Move/Copy

**File:** `lib/features/setlists/setlist_repository.dart`

1. Add `moveSongBetweenSetlists` method:

   ```dart
   Future<bool> moveSongBetweenSetlists({
     required String sourceSetlistId,
     required String targetSetlistId,
     required String songId,
     required String bandId,
   }) async {
     try {
       final response = await supabase.rpc(
         'move_song_between_setlists',
         params: {
           'p_source_setlist_id': sourceSetlistId,
           'p_target_setlist_id': targetSetlistId,
           'p_song_id': songId,
           'p_band_id': bandId,
         },
       );

       if (response is Map && response['success'] == true) {
         debugPrint('[SetlistRepository] ✓ Moved song via RPC');
         return true;
       }

       debugPrint('[SetlistRepository] Move RPC failed: ${response['error']}');
       return false;
     } on PostgrestException catch (e) {
       if (e.code == 'PGRST202' || e.code == '42883') {
         debugPrint('[SetlistRepository] move_song_between_setlists RPC not found');
         throw Exception('Move operation requires database migration');
       }
       debugPrint('[SetlistRepository] Error moving song: $e');
       rethrow;
     }
   }
   ```

**File:** `lib/features/setlists/setlist_detail_controller.dart`

1. Add `copySongToSetlist` method:
   ```dart
   Future<bool> copySongToSetlist({
     required String songId,
     required String targetSetlistId,
   }) async {
     final result = await _repository.addSongToSetlist(
       setlistId: targetSetlistId,
       songId: songId,
     );
     return result != null;
   }
   ```
2. Add `moveSongToSetlist` method:

   ```dart
   Future<bool> moveSongToSetlist({
     required String songId,
     required String targetSetlistId,
     required String sourceSetlistId,
   }) async {
     try {
       final success = await _repository.moveSongBetweenSetlists(
         sourceSetlistId: sourceSetlistId,
         targetSetlistId: targetSetlistId,
         songId: songId,
         bandId: state.bandId,
       );

       if (!success) return false;

       // Update local state - remove from current setlist
       state = state.copyWith(
         songs: state.songs.where((s) => s.id != songId).toList(),
         items: state.items.where((item) => item.song?.id != songId).toList(),
       );

       return true;
     } catch (e) {
       debugPrint('[SetlistDetail] Move failed: $e');
       return false;
     }
   }
   ```

**Verification:**

- Call `copySongToSetlist` → song added to target, remains in source.
- Call `moveSongToSetlist` → RPC called, song added to target, removed from source, local state updates.
- If RPC not found → exception thrown, error snackbar shown.

### Task 5: Add Web/macOS Fallback UI

**File:** `lib/features/setlists/setlist_detail_screen.dart` or `lib/features/setlists/widgets/reorderable_song_card.dart`

1. Detect platform via `kIsWeb || (!kIsWeb && Platform.isMacOS)`.
2. If pointer-only platform, add a three-dot menu icon (⋯) to the song card:
   - Position: Right side, next to delete icon (or replace delete icon in menu).
   - Icon: `AppIcons.moreVertical` or similar.
3. Wrap icon in `PopupMenuButton<String>` with menu items:
   ```dart
   PopupMenuButton<String>(
     icon: Icon(AppIcons.moreVertical, color: context.colors.textSecondary),
     onSelected: (value) {
       if (value == 'move') {
         _handleMoveOrCopySong(song.id, song.title);
       } else if (value == 'copy') {
         _handleCopySong(song.id, song.title);
       } else if (value == 'delete') {
         _handleDelete(song.id, song.title);
       }
     },
     itemBuilder: (context) => [
       PopupMenuItem(value: 'copy', child: Text('Copy to Setlist…')),
       PopupMenuItem(value: 'move', child: Text('Move to Setlist…')),
       PopupMenuItemDivider(),
       PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
     ],
   )
   ```
4. Implement `_handleCopySong` method (similar to `_handleMoveOrCopySong` but forces Copy mode).
5. Ensure menu icon does not interfere with tap-to-edit BPM/Duration/Tuning behavior (menu should be on far right, outside editable regions).

**Verification:**

- On web: Three-dot menu visible on song cards.
- Tap menu → options shown: "Copy to Setlist…", "Move to Setlist…", "Delete".
- Select "Move to Setlist…" → bottom sheet opens with Move mode pre-selected.
- Select "Copy to Setlist…" → bottom sheet opens with Copy mode pre-selected.
- On iOS/Android: Menu icon not visible (swipe gestures available instead).

### Task 6: Prevent Move from Catalog

**File:** `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`

1. Check if `isCatalogName(widget.sourceSetlistName)` in `_SetlistPickerSheetState`.
2. If true, hide the "Move" option in the toggle or disable it (show tooltip: "Cannot move songs out of Catalog").
3. Default to "Copy" mode if Catalog is source.

**Verification:**

- Swipe RIGHT on song in Catalog → bottom sheet opens with only "Copy" option (Move hidden/disabled).
- Swipe RIGHT on song in non-Catalog setlist → bottom sheet opens with both Copy and Move options.

## Verification Plan

### Tier 1 — Pre-Deployment (Manual UI Testing)

All tests are manual because this is a pure Flutter UI feature with no database schema changes.

1. **Swipe-left delete (existing behavior unchanged):**
   - Open a non-Catalog setlist with at least 3 songs.
   - Swipe LEFT on a song card → red background with "Delete" label appears.
   - Release swipe → confirmation dialog appears.
   - Confirm delete → song removed from setlist, snackbar shown.
   - **Expected:** Existing delete behavior works identically to before this feature.

2. **Swipe-right move/copy (new behavior):**
   - Open a non-Catalog setlist with at least 3 songs.
   - Swipe RIGHT on a song card → green/rose background with "Move/Copy" label appears.
   - Release swipe → setlist picker bottom sheet opens with Move/Copy toggle visible.
   - **Expected:** Swipe-right triggers bottom sheet without deleting song.

3. **Move/Copy toggle (default to Copy):**
   - Trigger swipe-right on a song.
   - Bottom sheet opens → Move/Copy toggle is visible, "Copy" is selected by default.
   - **Expected:** Toggle defaults to Copy mode.

4. **Copy mode (song remains in source):**
   - Swipe-right on a song, keep Copy mode selected.
   - Select a target setlist → confirm.
   - **Expected:** Song is added to target setlist, remains in source setlist, success snackbar shown.
   - Verify in target setlist: Song is present at the end of the list.
   - Verify in source setlist: Song is still present.

5. **Move mode (song removed from source):**
   - Swipe-right on a song, toggle to Move mode.
   - Select a target setlist → confirm.
   - **Expected:** Song is added to target setlist, removed from source setlist, success snackbar shown.
   - Verify in target setlist: Song is present at the end of the list.
   - Verify in source setlist: Song is no longer present.

6. **Move from Catalog is disabled:**
   - Open the Catalog setlist.
   - Swipe-right on a song → bottom sheet opens.
   - **Expected:** Move option is hidden/disabled, only Copy is available.

7. **Web/macOS fallback UI:**
   - Open the app on Chrome or Safari (web).
   - Open a non-Catalog setlist.
   - **Expected:** Three-dot menu icon is visible on song cards (far right).
   - Tap menu icon → options shown: "Copy to Setlist…", "Move to Setlist…", "Delete".
   - Select "Move to Setlist…" → bottom sheet opens with Move mode pre-selected.
   - Select "Copy to Setlist…" → bottom sheet opens with Copy mode pre-selected.

8. **Dark mode regression check:**
   - Enable dark mode in app settings.
   - Trigger swipe-right → bottom sheet opens.
   - **Expected:** Bottom sheet background is dark (`context.colors.surface`), text is white, no white-on-white or black-on-black rendering.

9. **Gesture coexistence:**
   - Swipe LEFT halfway → red delete background appears.
   - Swipe RIGHT halfway → green/rose move/copy background appears.
   - **Expected:** Both gestures trigger correctly without conflict or double-firing.

10. **Position ordering integrity:**
    - Move a song from setlist A (3 songs) to setlist B (5 songs).
    - Verify setlist A: 2 songs remain, displayed in correct order.
    - Verify setlist B: 6 songs total, moved song appears at the end, all songs displayed in correct order.
    - **Expected:** `ORDER BY position ASC` displays correct sequence, no gaps or duplicates.

### Tier 2 — Post-Deployment (Production Validation)

No database deployment required. Tier 2 validation is immediate after code merge and web build deployment.

1. **Deployed web build (bandroadie.com):**
   - Open `https://bandroadie.com` in incognito.
   - Log in via magic link.
   - Navigate to any non-Catalog setlist.
   - Verify swipe-right on mobile (if available) or three-dot menu on desktop works correctly.
   - **Expected:** Feature is accessible and functional in production.

2. **iOS TestFlight build:**
   - Install via TestFlight.
   - Open a non-Catalog setlist.
   - Swipe-right on a song → verify bottom sheet opens with toggle.
   - Move a song → verify it is removed from source and added to target.
   - **Expected:** Touch gestures work correctly on iOS.

3. **Android build:**
   - Install via internal testing track.
   - Open a non-Catalog setlist.
   - Swipe-right on a song → verify bottom sheet opens with toggle.
   - Move a song → verify it is removed from source and added to target.
   - **Expected:** Touch gestures work correctly on Android.

4. **macOS build:**
   - Build and run locally via `flutter run -d macos`.
   - Open a non-Catalog setlist.
   - Verify three-dot menu icon is visible on song cards.
   - Tap menu → select "Move to Setlist…" → verify bottom sheet opens.
   - **Expected:** Pointer-only fallback works correctly on macOS.

## QA Regression Areas

QA must specifically test:

1. **Swipe-left delete (existing behavior):**
   - Verify swipe-left on song cards still triggers delete confirmation dialog.
   - Verify delete removes song from setlist correctly.
   - Verify delete from Catalog removes song from all setlists.

2. **Swipe-right duplicate on setlist cards (existing behavior):**
   - Verify swipe-right on setlist cards (in Setlists tab) still triggers duplicate action.
   - Verify duplicate creates a new setlist with correct song list.
   - This must not be affected by song card swipe changes.

3. **Setlist picker bottom sheet (existing flows):**
   - Verify "Add To Setlist" button from Catalog still works (select songs, tap button, bottom sheet opens, select target).
   - Verify dark mode rendering is correct (no regression from PR #56 commit `769ccdb`).
   - Verify bottom sheet can be dismissed by tapping outside.

4. **Drag-to-reorder song cards (existing behavior):**
   - Verify long-press and drag on song cards still reorders correctly.
   - Verify reorder updates position in database and persists after refresh.
   - Verify reorder does not conflict with swipe gestures.

5. **Tap-to-edit BPM/Duration/Tuning (existing behavior):**
   - Verify tapping BPM, Duration, or Tuning fields on song cards opens inline editor.
   - Verify edits save correctly and broadcast to other open setlists.
   - Verify tap-to-edit does not conflict with three-dot menu icon on web/macOS.

6. **Catalog protection (existing behavior):**
   - Verify Catalog setlist cannot be deleted (swipe-left on setlist card shows snackbar).
   - Verify songs in Catalog can be deleted (removes from Catalog and all setlists).
   - Verify Move option is hidden/disabled when source is Catalog.

7. **Cross-platform consistency:**
   - Verify feature works on iOS, Android, web, macOS.
   - Verify web/macOS fallback UI (three-dot menu) is functional and discoverable.
   - Verify touch gestures (swipe) work on iOS/Android but not required on web/macOS.

8. **Position ordering integrity:**
   - Verify moving a song does not create duplicate positions or gaps in display order.
   - Verify copying a song adds it to the end of the target setlist.
   - Verify reordering songs after a move works correctly (positions are normalized).

## Rollout / Migration Strategy

**Migration required before code deployment.**

### Pre-Deployment (Database)

1. **Deploy migration** `20260712000000_move_song_between_setlists_rpc.sql` to production via `supabase db push`.
2. **Verify RPC exists:**
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'move_song_between_setlists';
   ```
3. **Test RPC manually** with known source/target setlist IDs and song ID (use band admin account):
   ```sql
   SELECT * FROM move_song_between_setlists(
     'source-setlist-uuid'::UUID,
     'target-setlist-uuid'::UUID,
     'song-uuid'::UUID,
     'band-uuid'::UUID
   );
   ```
   Expected result: `{"success": true, "moved_count": 1}`

### Post-Migration (Code Deployment)

1. Merge feature branch to `main` after QA approval and migration deployed.
2. Deploy web build via `./tools/deploy_web.sh` → Vercel deploys to `bandroadie.com`.
3. Build and release iOS/Android via standard release process (TestFlight, Google Play internal testing).
4. Monitor for user feedback on swipe gesture discoverability and web/macOS fallback UI usability.
5. Monitor Supabase logs for RPC errors or failures.

### Rollback Plan

- **Code rollback:** Revert to previous build (feature disabled).
- **Database rollback:** RPC can remain deployed (backward compatible — unused unless feature is active). If removal is required:
  ```sql
  DROP FUNCTION IF EXISTS move_song_between_setlists(UUID, UUID, UUID, UUID);
  ```

## Out of Scope

Explicitly excluded from this feature:

1. **Batch move/copy multiple songs at once** — User must swipe-right on each song individually. Batch selection is a separate feature (requires checkbox selection mode).
2. **Undo/redo for move operations** — Move is permanent. User must manually move song back if they change their mind.
3. **Reorder songs in target setlist during move** — Moved/copied songs are always added at the end of the target setlist. Reordering must be done manually after the move.
4. **Conflict resolution if song already exists in target setlist** — If song is already in target, the existing `addSongToSetlist` method returns the existing `setlist_song` ID (no duplicate inserted). This is correct behavior — no UI warning or error is needed.
5. **Keyboard shortcuts for web/macOS** — The three-dot menu is the only fallback. Keyboard shortcuts (e.g., Ctrl+X to move) are not implemented.
6. **Animation for song card removal/addition** — Song cards appear/disappear instantly after move. Smooth slide-out/slide-in animation is a polish enhancement (out of scope for MVP).
7. **Move/Copy from song detail overlay** — This feature only works in setlist detail view. The song detail overlay (tap on song card) does not gain Move/Copy buttons.

---

**End of Architect Plan**
