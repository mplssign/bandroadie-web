# Engineer Report

## Feature Slug

`bug/cleared-song-key-reverts`

## Feature Title

Fix: Song musical key clears do not persist to database

## Goal

Modify the `update_song_metadata` RPC to accept empty string as a sentinel value for clearing the `musical_key` field to NULL, and update the song details bottom sheet to flow empty string through to the repository instead of converting to null. This fixes the bug where clearing a song's musical key in the key picker causes the badge to disappear briefly but then reappear with the original value after refresh.

## Architect Tasks Completed

- [x] Task 1 — Create migration file with updated RPC logic ✓
- [x] Task 2 — Modify bottom sheet `_selectKey()` to set `_currentMusicalKey = ''` instead of `null` ✓
- [x] Task 3 — Remove defensive conversion in `_handleSave()` that converts empty string to null ✓

## Scope Amendments (Manager-approved)

After initial implementation, two issues were identified during verification (directive 3). These were reported as blockers but have since been approved by the Manager as required scope amendments. Both amendments are in the already-approved file (`song_details_bottom_sheet.dart`) and neither changes the architecture.

### Amendment 1: Key Segment Display Logic (line ~1019)

**Issue:** The null-coalescing operator `value: _currentMusicalKey ?? '—'` only provides the fallback when `_currentMusicalKey` is `null`. When `_currentMusicalKey = ''` (empty string after clearing), it displays an empty string instead of "—".

**Fix Applied:**
```dart
value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
    ? '—'
    : _currentMusicalKey!,
```

**Why:** The empty-string-sentinel solution requires the UI to render empty string as "unset" (the "—" placeholder). Without this fix, clearing a key would show a blank Key segment value instead of the expected placeholder.

### Amendment 2: Change Detection Logic (line ~304)

**Issue:** Direct inequality comparison `_currentMusicalKey != _originalMusicalKey` treats `''` and `null` as different values. This causes a semantic no-op (original `null` → current `''`) to register as a change and trigger unnecessary database writes.

**Fix Applied:**
```dart
final musicalKeyChanged =
    (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');
```

**Why:** Normalizes `null` and empty string as equivalent "no key" states. This ensures:
- Original `"C#"` → current `''` registers as a change (clear saves) ✓
- Original `null` → current `''` registers as no change (no spurious save) ✓

**Save Payload Verification:** The change detection fix does not affect the save payload. When `_currentMusicalKey = ''` (after clearing), the `SongDetailsResult` still contains `musicalKey: ''` (the sentinel), not `null`. The RPC correctly converts this to `NULL` in the database.

## Files Created

- `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql`

## Files Modified

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

## RPC Field-by-Field Comparison

Compared current RPC definition (`supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql`) against plan's version:

**Matching fields (no discrepancies):**

- `bpm`: `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END` ✓
- `duration_seconds`: `COALESCE(p_duration_seconds, duration_seconds)` ✓
- `tuning`: `COALESCE(p_tuning, tuning)` ✓
- `notes`: `CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END` ✓
- `title`: `COALESCE(p_title, title)` ✓
- `artist`: `COALESCE(p_artist, artist)` ✓
- `youtube_links`: `CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END` ✓
- `lyrics`: `CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END` ✓

**Changed field (per plan):**

- `musical_key`:
  - Current: `CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END`
  - Plan: `CASE WHEN p_musical_key = '' THEN NULL WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END`
  - Status: Updated in migration ✓

**COMMENT field:**

- Current: `'Update song metadata including musical key. BPM only updates when currently NULL. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.'`
- Plan: Adds `'Pass empty string for p_musical_key to clear.'` after "including musical key."
- Status: Updated in migration ✓

**SECURITY DEFINER, GRANT, and other function metadata:** All match exactly ✓

## Verification Results (Post-Amendment)

After implementing the two Manager-approved scope amendments, verified that the empty-string-sentinel solution now behaves correctly.

### Fix 1 Verification: Key Segment Display ✓

**Code location:** `song_details_bottom_sheet.dart:1019` (now ~1017-1021 after amendments)

**Before:**
```dart
value: _currentMusicalKey ?? '—',
```

**After:**
```dart
value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
    ? '—'
    : _currentMusicalKey!,
```

**Result:** Both `null` and empty string `''` now render as "—" placeholder. ✓

### Fix 2 Verification: Change Detection ✓

**Code location:** `song_details_bottom_sheet.dart:304` (now ~304-305 after amendments)

**Before:**
```dart
final musicalKeyChanged = _currentMusicalKey != _originalMusicalKey;
```

**After:**
```dart
final musicalKeyChanged =
    (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');
```

**Test cases:**
- Original `"C#"` → current `''` → `true` (change detected) ✓
- Original `null` → current `''` → `false` (no change) ✓
- Original `null` → current `"Dm"` → `true` (change detected) ✓

**Result:** Null and empty string are now normalized as equivalent "no key" states. ✓

### Save Payload Verification ✓

When a key is cleared:
1. `_currentMusicalKey` is set to `''` (line ~427)
2. Change detection sees original `"C#"` vs current `''` as changed (line ~304)
3. `_handleSave()` returns `musicalKey: _currentMusicalKey` which is `''` (line ~485)
4. Controller passes `musicalKey: ''` to repository
5. Repository passes `p_musical_key: ''` to RPC
6. RPC converts `''` to `NULL` via `CASE WHEN p_musical_key = '' THEN NULL`

**Result:** Empty string sentinel flows through correctly and is converted to NULL in the database. ✓

## Analyzer Results

Command: `flutter analyze`

**Result:** 0 errors in project code ✓

Note: All errors reported by `flutter analyze` (13,079 issues) are in external Firebase/Firestore dependencies (`build/ios/SourcePackages/checkouts/flutterfire/`) and are not related to this implementation. Project code analysis is clean.

## Test Results

Not run (no automated tests for this feature)

## Manual Verification

None performed (requires deployment to test full integration)

## Deviations From Architect Plan

The Architect plan specified three tasks:
1. Create migration file ✓
2. Modify `_selectKey()` to set `_currentMusicalKey = ''` ✓
3. Remove defensive conversion in `_handleSave()` ✓

After completing these tasks, verification revealed two additional changes required in the same file to support the empty-string-sentinel pattern. These were initially reported as blockers but were approved by the Manager as scope amendments:

1. **Key segment display logic** (line ~1019) — Updated to render empty string as "—"
2. **Change detection logic** (line ~304) — Updated to treat null and empty string as equivalent

Both amendments are in `song_details_bottom_sheet.dart` (already listed in the plan's "Files to Modify") and do not change the architecture or add new files. They are localized fixes required for the empty-string-sentinel solution to behave correctly.

## Ready For QA

**Yes** — Implementation is complete, including Manager-approved scope amendments.

All code changes are syntactically correct, pass `flutter analyze`, and follow the empty-string-sentinel pattern consistently throughout the bottom sheet. The changes are ready for integration testing via the Architect's verification plan.

## Complete Git Diff

```diff
diff --git a/lib/features/setlists/widgets/song_details_bottom_sheet.dart b/lib/features/setlists/widgets/song_details_bottom_sheet.dart
index 81f5f5f..654dd57 100644
--- a/lib/features/setlists/widgets/song_details_bottom_sheet.dart
+++ b/lib/features/setlists/widgets/song_details_bottom_sheet.dart
@@ -301,7 +301,8 @@ class _SongDetailsSheetState extends State<_SongDetailsSheet>
       _originalYoutubeLinks,
     );
     final lyricsChanged = _currentLyrics != _originalLyrics;
-    final musicalKeyChanged = _currentMusicalKey != _originalMusicalKey;
+    final musicalKeyChanged =
+        (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');
 
     final anyChanged = titleChanged ||
         artistChanged ||
@@ -424,7 +425,7 @@ class _SongDetailsSheetState extends State<_SongDetailsSheet>
       // Empty string means unselect (tap on already-selected key)
       HapticFeedback.selectionClick();
       setState(() {
-        _currentMusicalKey = null;
+        _currentMusicalKey = '';
       });
       _checkForChanges();
     } else if (result != null && result != _currentMusicalKey) {
@@ -472,12 +473,6 @@ class _SongDetailsSheetState extends State<_SongDetailsSheet>
     );
     debugPrint('[SongDetails] _hasChanges state: $_hasChanges');
 
-    // Treat empty string as null when saving musical key
-    final musicalKeyToSave =
-        (_currentMusicalKey != null && _currentMusicalKey!.isEmpty)
-            ? null
-            : _currentMusicalKey;
-
     final result = SongDetailsResult(
       title: titleChanged ? newTitle : null,
       artist: artistChanged ? newArtist : null,
@@ -488,7 +483,7 @@ class _SongDetailsSheetState extends State<_SongDetailsSheet>
           _currentDurationSeconds, // Always include so handler can check durationChanged flag
       youtubeLinks: youtubeLinksChanged ? _youtubeLinks : null,
       lyrics: lyricsChanged ? _currentLyrics : null,
-      musicalKey: musicalKeyChanged ? musicalKeyToSave : null,
+      musicalKey: musicalKeyChanged ? _currentMusicalKey : null,
       hasChanges: _hasChanges,
       titleChanged: titleChanged,
       artistChanged: artistChanged,
@@ -1021,7 +1016,9 @@ class _SongDetailsSheetState extends State<_SongDetailsSheet>
         ),
         SegmentData(
           label: 'Key',
-          value: _currentMusicalKey ?? '—',
+          value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
+              ? '—'
+              : _currentMusicalKey!,
           onTap: widget.isReadOnly ? null : _selectKey,
         ),
       ],
```

## Migration File Content

New file: `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql`

The migration drops and recreates the `update_song_metadata` function with updated `musical_key` assignment logic:

- Added: `WHEN p_musical_key = '' THEN NULL` clause to convert empty string to NULL
- Updated: COMMENT to document the empty string clearing behavior

All other fields, security settings (SECURITY DEFINER, SET search_path), and grants remain unchanged from the current version.
