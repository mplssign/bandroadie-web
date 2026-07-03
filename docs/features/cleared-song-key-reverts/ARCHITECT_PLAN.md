# Architect Plan — bug/cleared-song-key-reverts

## Feature Slug

`bug/cleared-song-key-reverts`

## Problem Summary

When a user unselects a song's musical key in the key picker (PR #49) and saves, the key badge (PR #50) disappears briefly from the song card but then reappears with the original key value. The clear operation does not persist to the database. Additionally, on screen refresh, key badges render late and reappear after a seemingly random delay.

## Root Cause

**Confidence: HIGH** — Confirmed by direct code inspection.

The `update_song_metadata` RPC (migration `20260630000001_add_musical_key_to_update_song_rpc.sql`, line 61) uses:

```sql
musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END,
```

When the repository passes `p_musical_key: null` to clear the key, the SQL `CASE` expression evaluates to `musical_key = musical_key` (no change). NULL is never written to the database. The RPC is designed with "update if provided" semantics where passing `NULL` for a parameter means "don't change this field." This works for adding or changing values but fails for clearing values to NULL.

The two symptoms share a single root cause:

1. **Cleared key does not persist:** RPC does not write NULL when `p_musical_key IS NULL`.
2. **Badges reappear after refresh:** Optimistic update sets local state to `null` (badge disappears), but since the RPC does not write NULL to the DB, subsequent fetches read the old value from the database and restore it to local state (badge reappears).

### Evidence Chain

**Key picker** (`lib/features/setlists/widgets/key_picker_bottom_sheet.dart:171`):

```dart
onTap: () => Navigator.of(context).pop(isSelected ? '' : key),
```

Returns empty string `''` when user taps the selected key to unselect.

**Song details bottom sheet** (`lib/features/setlists/widgets/song_details_bottom_sheet.dart:414-439`):

```dart
Future<void> _selectKey() async {
  final result = await showKeyPickerBottomSheet(context, selectedKey: _currentMusicalKey);
  if (result == '') {
    setState(() {
      _currentMusicalKey = null;  // ← Converts '' to null
    });
    _checkForChanges();
  }
  // ...
}
```

Converts empty string to `null` in local state.

**Repository** (`lib/features/setlists/setlist_repository.dart:2197`):

```dart
'p_musical_key': musicalKey,
```

Passes `null` to the RPC when `musicalKey` is `null`.

**RPC** (`supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql:61`):

```sql
musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END,
```

When `p_musical_key IS NULL`, this becomes `musical_key = musical_key` → no update.

**Badge display** (`lib/features/setlists/widgets/song_card.dart:236-242`, `reorderable_song_card.dart:353-354`):

```dart
if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
  _buildKeyBadge(),
```

Badge is shown only when `musicalKey` is not null and not empty. Handles both `null` and empty string correctly (neither would show a badge).

**Database ground truth:** The `songs.musical_key` column retains its original value after the user attempts to clear it because the RPC skips the update when the parameter is NULL.

## Reference Docs Consulted

No reference documentation exists for songs, setlists, or metadata editing domains. The directory `docs/reference/` contains subdirectories for `architecture`, `audits`, `auth`, `banners`, `bpm`, `deployment`, `general`, `notifications`, and `ui`, but none for songs/setlists/catalog.

## Existing System Analysis

### Current Behavior (Key Clear Flow)

1. User taps song card → `showSongDetailsBottomSheet` opens
2. User taps "Key" segment → `showKeyPickerBottomSheet` opens with `selectedKey` = current value
3. User taps currently selected key → picker returns `''` (empty string)
4. Bottom sheet `_selectKey()` receives `''` → sets `_currentMusicalKey = null`
5. Bottom sheet `_handleSave()` returns `SongDetailsResult` with `musicalKey: null`, `musicalKeyChanged: true`
6. Screen handler calls `notifier.updateSongMusicalKey(song.id, null)`
7. Controller performs optimistic update: `song.copyWith(musicalKey: null, clearMusicalKey: true)` → badge disappears
8. Controller calls `_repository.updateSongMusicalKey(bandId: bandId, songId: songId, musicalKey: null)`
9. Repository calls RPC `update_song_metadata` with `p_musical_key: null` and all other params null
10. **RPC evaluates `CASE WHEN NULL IS NOT NULL ...` → false → `musical_key = musical_key` → no database write**
11. Controller's try block succeeds (RPC returns `{success: true}` because the UPDATE statement ran without error, even though it didn't change anything)
12. Controller broadcasts update with `musicalKey: null`
13. Later: any fetch from the database reads the old value → badge reappears

### Why Badge Reappears

The "reappear" symptom occurs because:

- The optimistic update immediately sets local state to `null` (badge disappears)
- The RPC does not write `NULL` to the database (old value persists)
- Any subsequent data fetch (e.g., navigating away and back, pull-to-refresh, or broadcast-triggered refetch) reads the old value from the database
- Local state is updated from the fetched data → badge reappears

This is **not** a caching bug or a deferred-fetch bug. It is a database write failure masked by a successful RPC return status.

### Why the RPC Returns Success

The RPC executes:

```sql
UPDATE songs
SET musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END, ...
WHERE id = p_song_id;
```

Even when `p_musical_key IS NULL`, the UPDATE statement runs successfully (it writes `musical_key = musical_key`, which is a no-op but not a SQL error). PostgreSQL returns `ROW_COUNT = 1`, the RPC sees a successful update, and returns `{success: true}`. The client has no way to detect that the field was not actually changed.

## Proposed Solution

Use **empty string `''` as a sentinel value** to signal "clear this field to NULL." Update the RPC to convert empty string to NULL before writing. This is the standard pattern for clearing optional text fields in an "update if provided" RPC signature.

### Changes Required

1. **Do NOT convert `''` to `null` in the bottom sheet.** Let the empty string flow through to the repository and RPC.
2. **Update the RPC** to detect empty string for `p_musical_key` and convert it to NULL before writing:

```sql
musical_key = CASE
  WHEN p_musical_key = '' THEN NULL
  WHEN p_musical_key IS NOT NULL THEN p_musical_key
  ELSE musical_key
END
```

This preserves the existing "update if provided" semantics:

- Pass a key string (e.g., `"C#"`) → write that key
- Pass `''` (empty string) → write NULL (clear the field)
- Pass `NULL` (or omit the parameter) → no change

### Why This Solution

**Alternatives considered:**

**Option A:** Change the RPC to always write the parameter value, including NULL.

- **Rejected:** This breaks the "update if provided" pattern used by all other fields in the RPC. The repository calls this RPC with one field set and all others NULL. If NULL means "write NULL," then calling `updateSongMusicalKey` would unintentionally clear all other fields.

**Option B:** Add a separate boolean parameter `p_clear_musical_key` to signal a clear.

- **Rejected:** Adds complexity; the sentinel pattern is simpler and more consistent with Supabase conventions.

**Option C:** Create a separate `clear_song_musical_key` RPC.

- **Rejected:** Unnecessary proliferation of RPCs for what is semantically a single update operation.

**Option D:** Use a sentinel UUID or magic string (e.g., `"__CLEAR__"`).

- **Rejected:** Empty string is the natural sentinel for text fields and requires no special handling in the client.

**Chosen solution (empty string sentinel) is the standard pattern** because:

- Empty string is already invalid as a musical key value (keys are like `"C"`, `"F#m"`, never empty)
- The badge display logic already treats empty string correctly (`musicalKey != null && musicalKey.isNotEmpty`)
- No changes required to the model, controller, repository, or broadcast logic
- Minimal surface area: one conditional removed in the bottom sheet, one clause added to the RPC

## Database Impact

**Migration Required:** Yes  
**Migration Naming:** `YYYYMMDDHHMMSS_fix_musical_key_clear_in_update_song_rpc.sql` (timestamp format)

**RLS Policies:** Not affected

**RPC Changes:**

- Function: `update_song_metadata`
- Action: `DROP FUNCTION IF EXISTS` existing 11-parameter signature, then `CREATE OR REPLACE FUNCTION` with updated `musical_key` assignment logic
- No signature change (parameters remain the same)
- SECURITY DEFINER status preserved
- GRANT preserved

**Triggers:** Not affected

**Migration Content:**

```sql
-- Drop existing 11-parameter signature
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL,
  p_musical_key TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_song_band_id UUID;
  v_update_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  SELECT band_id INTO v_song_band_id FROM songs WHERE id = p_song_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Song not found');
  END IF;

  IF v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id THEN
    RETURN json_build_object('success', false, 'error', 'Song belongs to a different band');
  END IF;

  UPDATE songs
  SET
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,
    musical_key = CASE
      WHEN p_musical_key = '' THEN NULL
      WHEN p_musical_key IS NOT NULL THEN p_musical_key
      ELSE musical_key
    END,
    updated_at = NOW()
  WHERE id = p_song_id;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata including musical key. Pass empty string for p_musical_key to clear. BPM only updates when currently NULL. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
```

## Flutter Architecture Changes

**State:** Not affected (model already handles NULL correctly)

**Widgets:**

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:414-439` — Remove the conversion of `''` to `null` in `_selectKey()` method

**Repositories:** Not affected (already passes the value through)

**Controllers:** Not affected (optimistic update already handles both NULL and empty string via `clearMusicalKey` flag)

**Models:** Not affected (`SetlistSong.copyWith` already has `clearMusicalKey` parameter that handles both NULL and empty string)

**Providers/Broadcasters:** Not affected (broadcast already passes the value through)

## Files to Create

None

## Files to Modify

| File                                                                              | What Changes                                                                                                                                          |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`                    | Remove lines 423-429 in `_selectKey()` method that convert `''` to `null`. Replace with: `setState(() { _currentMusicalKey = ''; });`                 |
| `supabase/migrations/YYYYMMDDHHMMSS_fix_musical_key_clear_in_update_song_rpc.sql` | New migration file. DROP and recreate `update_song_metadata` function with updated `musical_key` assignment logic that converts empty string to NULL. |

## Files Off-Limits

| File                                                         | Reason                                                                                                                              |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_card.dart`               | Badge display logic (`musicalKey != null && isNotEmpty`) is correct and shipped QA-approved in PR #50. No changes needed.           |
| `lib/features/setlists/widgets/reorderable_song_card.dart`   | Badge display logic is correct. No changes needed.                                                                                  |
| `lib/features/setlists/setlist_repository.dart`              | Already passes `musicalKey` parameter through unchanged. No modifications needed.                                                   |
| `lib/features/setlists/setlist_detail_controller.dart`       | Optimistic update and broadcast logic already handle NULL and empty string correctly via `clearMusicalKey` flag. No changes needed. |
| `lib/features/setlists/models/setlist_song.dart`             | Model already supports clearing via `clearMusicalKey` parameter in `copyWith`. No changes needed.                                   |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart` | Picker correctly returns `''` when user taps selected key to unselect. No changes needed.                                           |
| `lib/main.dart`                                              | Init order must not change (Guardrail #1).                                                                                          |

## System Impact Map

| System                                 | Impact                                                                      |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                  |
| Rehearsals                             | unaffected                                                                  |
| Setlists / Catalog                     | **affected** — song key clearing now persists correctly across all setlists |
| Members / RBAC                         | unaffected                                                                  |
| Auth / Session                         | unaffected                                                                  |
| Routing                                | unaffected                                                                  |
| Notifications                          | unaffected                                                                  |
| Platform (iOS / Android / Web / macOS) | affected — all platforms benefit from fix                                   |

## Regression Risk

**Level: LOW**

**Rationale:**

- Single RPC modified (narrow surface area)
- Change is additive: adds one condition to handle empty string, does not alter existing NULL or non-NULL behavior
- No other fields in the RPC are affected
- No changes to client-side update logic (repository, controller, model, broadcast)
- No new abstractions introduced
- No initialization order, auth, or session changes
- Empty string is already an invalid musical key value, so no risk of data corruption
- Badge display logic already handles empty string correctly (no visual regression)

**Blast radius:**

- One RPC function
- One UI widget (bottom sheet — removes 7 lines of defensive conversion logic)
- Affects only song musical key clearing, not any other metadata fields
- No shared code paths with other features

## Engineer Task Breakdown

Execute in order. Do not skip. Each task is atomic and must complete before the next.

### Task 1: Create Migration File

Create `supabase/migrations/YYYYMMDDHHMMSS_fix_musical_key_clear_in_update_song_rpc.sql` with the complete DROP/CREATE script provided in the "Database Impact" section above. Use current UTC timestamp in `YYYYMMDDHHMMSS` format for the filename prefix.

### Task 2: Modify Bottom Sheet

In `lib/features/setlists/widgets/song_details_bottom_sheet.dart`, locate the `_selectKey()` method (lines 414-439). Replace the block:

```dart
if (result == '') {
  // Empty string means unselect (tap on already-selected key)
  HapticFeedback.selectionClick();
  setState(() {
    _currentMusicalKey = null;
  });
  _checkForChanges();
}
```

With:

```dart
if (result == '') {
  // Empty string means unselect (tap on already-selected key)
  HapticFeedback.selectionClick();
  setState(() {
    _currentMusicalKey = '';
  });
  _checkForChanges();
}
```

Change: line 427 from `_currentMusicalKey = null;` to `_currentMusicalKey = '';`

### Task 3: Remove Redundant Defensive Check (Optional Cleanup)

In the same file, locate `_handleSave()` method (lines 441-505). The defensive conversion at lines 475-479:

```dart
final musicalKeyToSave =
    (_currentMusicalKey != null && _currentMusicalKey!.isEmpty)
        ? null
        : _currentMusicalKey;
```

Is now redundant (since `_currentMusicalKey` is never set to empty string in the new code flow — wait, that's wrong. Actually, after Task 2, `_currentMusicalKey` IS set to empty string when clearing, so this defensive check would convert it back to null. **This defensive check must be removed.**

Replace lines 475-479 with:

```dart
final musicalKeyToSave = _currentMusicalKey;
```

And update line 491 from:

```dart
musicalKey: musicalKeyChanged ? musicalKeyToSave : null,
```

To:

```dart
musicalKey: musicalKeyChanged ? _currentMusicalKey : null,
```

(Simplification: just use `_currentMusicalKey` directly, no intermediate variable needed.)

**Revised Task 3:** In `_handleSave()`, remove lines 475-479 (the `musicalKeyToSave` defensive conversion). On line 491, change `musicalKeyToSave` to `_currentMusicalKey`. This ensures empty string flows through to the save handler and repository unchanged.

### Task 4: Run Flutter Analyze

Execute `flutter analyze` from project root. Verify 0 errors, 0 warnings.

### Task 5: Generate Git Diff

Execute `git diff` and save output to verify changes match plan exactly:

- One new migration file (CREATE only, no changes to existing files)
- Bottom sheet: one line changed (null → ''), defensive conversion block removed

## Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push`)

These tests verify the RPC logic in isolation without deploying the migration. They test the empty string → NULL conversion behavior by calling a test version of the function.

**PRE-DEPLOY TEST 1:** Verify empty string converts to NULL

```sql
-- Create temporary test function with new logic (does not replace production function)
CREATE OR REPLACE FUNCTION test_musical_key_clear(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN CASE
    WHEN p_key = '' THEN NULL
    WHEN p_key IS NOT NULL THEN p_key
    ELSE 'NO_CHANGE'
  END;
END;
$$;

-- Test empty string → NULL
DO $$
DECLARE
  v_result TEXT;
BEGIN
  v_result := test_musical_key_clear('');
  IF v_result IS NOT NULL THEN
    RAISE EXCEPTION 'Test failed: empty string did not convert to NULL (got %)', v_result;
  END IF;
  RAISE NOTICE 'PRE-DEPLOY TEST 1 PASSED: empty string converts to NULL';
END;
$$;

-- Test non-empty string → unchanged
DO $$
DECLARE
  v_result TEXT;
BEGIN
  v_result := test_musical_key_clear('C#');
  IF v_result != 'C#' THEN
    RAISE EXCEPTION 'Test failed: non-empty string changed (expected C#, got %)', v_result;
  END IF;
  RAISE NOTICE 'PRE-DEPLOY TEST 1 PASSED: non-empty string preserved';
END;
$$;

-- Test NULL → NO_CHANGE sentinel
DO $$
DECLARE
  v_result TEXT;
BEGIN
  v_result := test_musical_key_clear(NULL);
  IF v_result != 'NO_CHANGE' THEN
    RAISE EXCEPTION 'Test failed: NULL did not preserve existing value (got %)', v_result;
  END IF;
  RAISE NOTICE 'PRE-DEPLOY TEST 1 PASSED: NULL preserves existing value';
END;
$$;

-- Cleanup
DROP FUNCTION test_musical_key_clear(TEXT);
```

### Tier 2 — Post-deployment (after `supabase db push`)

These tests verify the full integration after the migration is applied.

**POST-DEPLOY TEST 1:** Verify function exists with updated logic

```sql
-- Verify function was replaced
SELECT pg_get_functiondef('update_song_metadata(uuid,uuid,integer,integer,text,text,text,text,text,text,text)'::regprocedure);

-- Verify function definition contains the new CASE logic for musical_key
DO $$
DECLARE
  v_function_def TEXT;
BEGIN
  v_function_def := pg_get_functiondef('update_song_metadata(uuid,uuid,integer,integer,text,text,text,text,text,text,text)'::regprocedure);

  IF v_function_def NOT LIKE '%WHEN p_musical_key = '''' THEN NULL%' THEN
    RAISE EXCEPTION 'Function does not contain expected empty string check';
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 1 PASSED: Function contains updated musical_key logic';
END;
$$;
```

**POST-DEPLOY TEST 2:** Integration test — clear musical key via RPC

```sql
-- Insert test song (will auto-rollback at end of transaction)
DO $$
DECLARE
  v_test_song_id UUID;
  v_test_band_id UUID;
  v_result JSON;
  v_key_after_set TEXT;
  v_key_after_clear TEXT;
BEGIN
  -- Get a test band (assumes active membership exists; adjust band_id if needed)
  -- Or create a temporary band for this test
  SELECT id INTO v_test_band_id FROM bands LIMIT 1;
  IF v_test_band_id IS NULL THEN
    RAISE EXCEPTION 'No test band found. Cannot run integration test.';
  END IF;

  -- Create test song
  INSERT INTO songs (title, artist, band_id, musical_key)
  VALUES ('Test Song Clear Key', 'Test Artist', v_test_band_id, 'F#')
  RETURNING id INTO v_test_song_id;

  -- Verify initial key is set
  SELECT musical_key INTO v_key_after_set FROM songs WHERE id = v_test_song_id;
  IF v_key_after_set != 'F#' THEN
    RAISE EXCEPTION 'Test setup failed: initial key not set (expected F#, got %)', v_key_after_set;
  END IF;

  -- Call RPC with empty string to clear
  v_result := update_song_metadata(
    p_song_id := v_test_song_id,
    p_band_id := v_test_band_id,
    p_bpm := NULL,
    p_duration_seconds := NULL,
    p_tuning := NULL,
    p_notes := NULL,
    p_title := NULL,
    p_artist := NULL,
    p_youtube_links := NULL,
    p_lyrics := NULL,
    p_musical_key := ''  -- Empty string to clear
  );

  IF (v_result->>'success')::boolean != true THEN
    RAISE EXCEPTION 'RPC failed: %', v_result->>'error';
  END IF;

  -- Verify key is now NULL
  SELECT musical_key INTO v_key_after_clear FROM songs WHERE id = v_test_song_id;
  IF v_key_after_clear IS NOT NULL THEN
    RAISE EXCEPTION 'Test failed: musical_key not cleared (expected NULL, got %)', v_key_after_clear;
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 2 PASSED: musical_key cleared to NULL via empty string';

  -- Rollback to clean up test data
  RAISE EXCEPTION 'Test passed, rolling back test data';
END;
$$;
```

**POST-DEPLOY TEST 3:** Verify other fields not affected

```sql
-- Verify other fields still use their original update logic
DO $$
DECLARE
  v_test_song_id UUID;
  v_test_band_id UUID;
  v_result JSON;
  v_notes_after TEXT;
BEGIN
  SELECT id INTO v_test_band_id FROM bands LIMIT 1;
  IF v_test_band_id IS NULL THEN
    RAISE EXCEPTION 'No test band found';
  END IF;

  INSERT INTO songs (title, artist, band_id, notes)
  VALUES ('Test Other Fields', 'Test Artist', v_test_band_id, 'Original notes')
  RETURNING id INTO v_test_song_id;

  -- Call RPC with p_notes = NULL (should NOT change notes)
  v_result := update_song_metadata(
    p_song_id := v_test_song_id,
    p_band_id := v_test_band_id,
    p_bpm := NULL,
    p_duration_seconds := NULL,
    p_tuning := NULL,
    p_notes := NULL,  -- NULL should preserve existing notes
    p_title := NULL,
    p_artist := NULL,
    p_youtube_links := NULL,
    p_lyrics := NULL,
    p_musical_key := NULL
  );

  SELECT notes INTO v_notes_after FROM songs WHERE id = v_test_song_id;
  IF v_notes_after != 'Original notes' THEN
    RAISE EXCEPTION 'Test failed: notes changed when NULL passed (expected "Original notes", got %)', v_notes_after;
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 3 PASSED: NULL parameter still preserves existing field values';

  RAISE EXCEPTION 'Test passed, rolling back';
END;
$$;
```

## QA Regression Areas

QA must specifically test the following:

### Primary — Song Key Clearing (Bug Fix Validation)

1. **Clear key and verify persistence:**
   - Open a setlist containing a song with a key set (amber badge visible on card)
   - Tap the song card to open song details
   - Tap the "Key" segment in the metrics row
   - Tap the currently selected key (e.g., "C#") to unselect it
   - Observe: key picker closes, "Key" segment value changes from "C#" to "—"
   - Tap "Save"
   - Observe: bottom sheet closes, amber key badge on song card disappears
   - **Wait 2-3 seconds** (do not interact)
   - Verify: badge remains gone (does not reappear)
   - Navigate to home screen, then back to the setlist
   - Verify: badge still gone
   - Reopen song details → Verify: "Key" segment shows "—" (not the old key)

2. **Pull-to-refresh after clear:**
   - Repeat step 1 (clear a key and save)
   - After badge disappears, pull down to refresh the setlist
   - Verify: badge does not reappear after refresh completes

3. **Key badge behavior on different song cards:**
   - Verify cleared key stays cleared on both `song_card.dart` (non-reorderable) and `reorderable_song_card.dart` (edit mode)
   - Test on iOS physical device (as per original bug report)
   - Test on Android and Web to confirm cross-platform fix

4. **Re-set key after clearing:**
   - Clear a song's key (badge disappears)
   - Immediately reopen song details
   - Set a new key (e.g., "Dm")
   - Save and verify badge appears with new key
   - Reopen details → verify new key persists

5. **Legacy songs with NULL band_id:**
   - Identify a legacy song (NULL band_id) if available in test environment
   - Clear its key and verify SECURITY DEFINER logic allows the update

### Secondary — Regression Tests (Other Metadata)

6. **Other metadata fields unaffected:**
   - Edit and save: Title, Artist, BPM, Duration, Tuning, Notes, YouTube links, Lyrics
   - Verify each persists correctly across save/refresh cycles
   - Verify passing NULL for a field (not editing it) does NOT clear that field

7. **Key picker selection (non-clear):**
   - Select a NEW key (not currently selected) → Verify it saves and badge appears
   - Change from one key to another (e.g., "C" to "G") → Verify change persists
   - Select same key twice in a row → Verify no-op (no change, badge remains)

8. **Badge rendering timing:**
   - Open a setlist with multiple songs (some with keys, some without)
   - Verify badges appear immediately, not after a delay
   - Verify no "flicker" behavior (badge appearing, disappearing, reappearing)

### Edge Cases

9. **Rapid save/cancel cycles:**
   - Open song details → clear key → cancel (discard changes)
   - Verify badge remains (clear was discarded)
   - Open again → clear key → save → immediately reopen
   - Verify "Key" segment shows "—" (clear was saved)

10. **Multiple setlists sharing same song:**
    - Clear key on song in Setlist A
    - Navigate to Setlist B containing the same song
    - Verify badge is also gone in Setlist B (global change)

## Rollout / Migration Strategy

**Deployment order:**

1. Merge PR to main (after QA APPROVED)
2. Run `supabase db push` to apply migration in production (replaces RPC)
3. Deploy Flutter web build via `./tools/deploy_web.sh`
4. Native app users receive updated RPC behavior immediately (no app update required)

**Rollback plan:**  
If the RPC behavior is incorrect, rollback requires a new migration that restores the original `musical_key` assignment logic (without empty string handling). The original logic is preserved in migration `20260630000001_add_musical_key_to_update_song_rpc.sql`.

**Migration is non-breaking:**

- No schema changes (column type, constraints unchanged)
- No data changes (migration only updates function definition)
- Existing NULL and non-empty-string values unaffected
- Client code compatible with both old and new RPC (empty string was never used before this fix)

## Out of Scope

- Fixing the "late badge rendering" symptom is not a separate issue. It is a direct consequence of the root cause (database write failure) and will be resolved by this fix.
- No changes to badge styling, positioning, or animation.
- No changes to key picker UI or available key options.
- No changes to other metadata fields (BPM, Duration, Tuning, Notes, Lyrics, YouTube links).
- No changes to setlist reordering, search, or filtering behavior.
- No refactoring of `setlist_repository.dart` (2,400 lines) or `setlist_detail_screen.dart` (2,800 lines) — changes are minimal and localized.
- No introduction of separate `clear_song_metadata` RPC or additional boolean flags.
- No performance optimization (this is a correctness fix, not a performance fix).
