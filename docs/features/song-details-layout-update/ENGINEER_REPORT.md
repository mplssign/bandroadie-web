# Engineer Report

## Feature Slug
song-details-layout-update

## Feature Title
Update Song Details Field Layout

## Goal
Add a `musical_key` field end-to-end (DB → model → repository → controller → UI) and update the Song Details bottom sheet layout to match the approved designer mock: a 4-column metadata row (BPM / Duration / Tuning / Key), a 3-button equal-width outlined rose action row (Add Lyrics / Add YouTube / Add Notes), and an in-drawer sub-view pattern for Notes editing.

## Architect Tasks Completed
- [x] Task 1 — DB migration: add `musical_key TEXT` column to `songs` table
- [x] Task 2 — DB migration: drop and recreate `update_song_metadata` RPC with 11th parameter `p_musical_key`
- [x] Task 3 — Model: add `musicalKey` field to `Song`
- [x] Task 4 — Model: add `musicalKey` field + `clearMusicalKey` to `SetlistSong`
- [x] Task 5a — Repository: add `musical_key` to `fetchSongsForSetlist` nested join
- [x] Task 5b — Repository: add `updateSongMusicalKey` method
- [x] Task 5c — Repository: update all 8 existing `update_song_metadata` RPC call sites to pass `p_musical_key: null`
- [x] Task 6 — Controller: add `musicalKey`/`clearMusicalKey` to `SongUpdateEvent`; update `_applySongUpdate`; add `updateSongMusicalKey` method
- [x] Task 7 — AppIcons: add `noteFile = LucideIcons.fileText`
- [x] Task 8 — UI: `SongDetailsResult` + `_SongDetailsSheet` — musical key state, key picker dialog, 4-column metrics row, 3-button action row, Notes in-drawer sub-view
- [x] Task 9 — Screen: handle `result.musicalKeyChanged` in `_handleSongTap`

## Files Created
- `supabase/migrations/20260630000000_add_musical_key_to_songs.sql`
- `supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql`

## Files Modified
- `lib/features/setlists/models/song.dart` — added `musicalKey` field, constructor param, `fromSupabase` mapping
- `lib/features/setlists/models/setlist_song.dart` — added `musicalKey` field, constructor param, DATA MAPPING comment, `fromSupabase` mapping, `copyWith` param + logic
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — full rewrite of affected methods; added key constants, `SongDetailsResult.musicalKey/musicalKeyChanged`, musical key state, `_showKeyPicker()`, 4-column `_buildMetricsRow()`, `_buildAddButtonsRow()` 3-button redesign, `_buildNotesPreview()`, `_buildNotesSubView()`, `_buildNotesSection()` restructure; updated `_checkForChanges` and `_handleSave`
- `lib/features/setlists/setlist_repository.dart` — added `musical_key` to fetch join; added `updateSongMusicalKey`; updated 8 existing `update_song_metadata` call sites to pass `p_musical_key: null`
- `lib/features/setlists/setlist_detail_controller.dart` — added `musicalKey`/`clearMusicalKey` to `SongUpdateEvent`; updated `_applySongUpdate`; added `updateSongMusicalKey` controller method
- `lib/features/setlists/setlist_detail_screen.dart` — added `musicalKeyChanged` handler block in `_handleSongTap`
- `lib/app/theme/app_icons.dart` — added `noteFile = LucideIcons.fileText` under Music / Setlists section

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — `No issues found! (ran in 5.5s)` — verified twice (pre- and post-format)

## Test Results
Not run — no automated tests exist for `_SongDetailsSheet` or the song metadata update path. Manual QA per Architect Verification Plan is required.

## Verification
Manual steps performed:
- Confirmed `musical_key` fetch join field added at the correct query location (line ~612)
- Grep verified exactly 8 existing RPC call sites updated with `'p_musical_key': null` + 1 new site in `updateSongMusicalKey` using live value (9 total occurrences)
- Confirmed `SongUpdateEvent.musicalKey` is consumed by `_applySongUpdate` via `copyWith`
- Confirmed `LucideIcons.fileText` is a valid Lucide icon (used by `AppIcons.noteFile`)
- `flutter analyze` passes with 0 issues before and after `dart format`

## Deviations From Architect Plan

### 1. Notes sub-view uses back-nav row, not "Done" TextButton (superseded by user clarification)
The Architect plan (Task 8g) specified a "Done" TextButton inline approach. The user clarification supersedes this: Notes tapping switches the entire scroll-area content to an in-drawer sub-view (`_buildNotesSubView()`) with a left-chevron + "Back" text button at the top-left. Returning from Notes restores the main view (`_isEditingNotes = false`). The Save/Cancel footer remains visible in both views.

### 2. Metrics row gap changed from 12px to 8px
The 3-column row used `SizedBox(width: 12)` between columns. The 4-column row uses `SizedBox(width: 8)` to accommodate the 4th column at narrow widths (≤375pt). This is a layout-only adjustment not explicitly specified in the plan; the plan says "Expanded handles it" and this is the minimal change to make that work comfortably.

### 3. Button text uses `AppTextStyles.footnote` instead of explicit 12pt
The Architect plan specified "12pt, FontWeight.w600" for button labels. `AppTextStyles.footnote` is the project's 12pt text style, so this is equivalent — avoids hardcoding font sizes outside the design token system.

### 4. 8 RPC call sites updated (plan said 7)
The Architect plan listed 7 call sites. Code inspection found a 8th at line ~3988 (Spotify BPM enrichment path). All 8 were updated.

### 5. `SongUpdateEvent` and `_applySongUpdate` extended
The Architect plan did not explicitly mention extending `SongUpdateEvent`, but `updateSongMusicalKey` "following the exact same structure as `updateSongNotes`" requires broadcasting to the event system. Both `SongUpdateEvent` and `_applySongUpdate` are in the listed file `setlist_detail_controller.dart` and were extended minimally: added `musicalKey` field, `clearMusicalKey` flag, and corresponding `copyWith` in `_applySongUpdate`.

## Notes Sub-View Implementation Approach
The Notes button (`+ Add Notes` / `Edit Notes`) in the 3-button action row sets `_isEditingNotes = true` via `setState`. The main `build()` method switches the scroll area's Column children: when `_isEditingNotes = true`, only `_buildNotesSubView()` is shown; when `false`, the normal content stack is shown. The sub-view contains:
1. A `GestureDetector` row: `AppIcons.back` (chevronLeft) + "Back" text, tapping sets `_isEditingNotes = false`
2. The "Notes" label
3. The existing `_notesController` TextField (minLines: 8, same logic, no controller change)

This matches the user's clarification: "within the same bottom sheet — no new modal or sheet is pushed" with "a back navigation row at the top-left: a left chevron icon + 'Back' text button." The `_notesController` listener still drives `_checkForChanges`, so the Save button activates when notes are edited in the sub-view.

## Known Risks and Follow-Up Items
1. **Deploy order constraint**: The two SQL migrations must be applied (`supabase db push`) before the Dart client ships. Partial deployment leaves the app unable to save any song metadata. Do not merge the client PR without confirming migrations are live.
2. **Tier 2 verification**: All post-deploy SQL tests (Architect Verification Plan §Tier 2) and QA regression checklist (15 items) are deferred to manual QA.
3. **Musical key clearing**: The current implementation does not provide a "Clear" option in the key picker. Once a key is set, the user cannot reset it to null via the picker. The Architect plan notes this as optional (`clearMusicalKey` parameter is available in the code path). A "Clear" option can be added to `_showKeyPicker()` as a future enhancement without further schema or RPC changes.
4. **`_kMajorKeys` / `_kMinorKeys` are file-level `const`** (not class members). This is valid Dart and avoids re-allocating the arrays per widget build, but they are not `static const` inside a class since `_SongDetailsSheet` is private and the constants are file-private.

## Ready For QA
Yes — implementation is complete, `flutter analyze` passes with 0 issues. Migrations must be applied before device testing begins.
