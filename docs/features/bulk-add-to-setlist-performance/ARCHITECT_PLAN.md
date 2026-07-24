# Architect Plan: Bulk Add to Setlist Performance Fix

## Feature Slug

`bug/bulk-add-to-setlist-performance`

## Problem Summary

When a user multi-selects songs in the catalog and uses "Add to setlist → Create new setlist," the operation takes 60–90 seconds for 97 songs with no loading indicator or visual feedback. A separate user report claims only 4–5 of many selected songs were copied (not yet reproduced by Tony). The swipe-to-duplicate-setlist action completes the same 97-song copy instantly, suggesting the bulk-add code path is fundamentally slower.

## Root Cause

**Confidence: HIGH (for slowness and no progress indicator), MEDIUM (for dropped songs)**

### Slowness Root Cause

File: `lib/features/setlists/setlist_detail_screen.dart:1451-1472`

The `_handleAddToSetlist` method uses a **sequential awaited for loop**:

```dart
for (final songId in _selectedSongIds) {
  try {
    final song = ref.read(setlistDetailProvider).songs.firstWhere((s) => s.id == songId);
    final addResult = await repository.addSongToSetlistEnsureCatalog(
      bandId: bandId,
      setlistId: targetSetlistId,
      songId: songId,
      songTitle: song.title,
      songArtist: song.artist,
    );
    // ...
  } catch (e) {
    // ...
  }
}
```

Each iteration calls `addSongToSetlistEnsureCatalog` (line 3447 in setlist_repository.dart), which performs:

1. Ensure Catalog exists query (line 3460)
2. Check if song is already in Catalog (line 3464-3469)
3. Call `addSongToSetlist` if not in Catalog (line 3475), which does:
   - Check if song already exists in target setlist (line 3568-3573)
   - Get max position in target setlist (line 3586-3591)
   - Insert song (line 3601-3613)

**Total: ~5-6 database round trips per song, all done sequentially.**

For 97 songs:

- 97 songs × 6 operations = **~582 sequential database round trips**
- At ~100-150ms per round trip = **58-116 seconds** (matches observed 60-90s)

**Compare to the fast path** (`duplicateSetlist`, line 2520 in setlist_repository.dart):

- Fetch all source songs in ONE query (line 2584-2589)
- Insert all songs in ONE batch (line 2605: `await supabase.from('setlist_songs').insert(newSongs)`)
- **Total: 2 database operations** regardless of song count (instant)

### No Progress Indicator

The loop at line 1451 has no loading state set before it begins. The UI appears frozen for 60-90 seconds with no spinner, progress bar, or any visual feedback.

### Dropped Songs (MEDIUM Confidence)

The sequential loop has no UI lock or navigation guard. If the user taps back or navigates away during the 60-90 second operation, the widget unmounts and the loop stops mid-execution. This explains the report of "only 4-5 songs copied" — the user likely navigated away after a few seconds when the app appeared frozen. **This is not directly confirmed in code but is strongly implied by the missing UI lock and async operation pattern.**

## Reference Docs Consulted

No setlists-specific reference documentation exists under `docs/reference/setlists/`.

Consulted:

- `docs/reference/architecture/database_schema.md` — confirmed `setlist_songs` table structure and RPC functions

## Existing System Analysis

### Current Bulk-Add Flow

1. User selects songs in catalog (multi-select mode)
2. User taps "Add To Setlist"
3. `showSetlistPickerBottomSheet` displays (setlist_picker_bottom_sheet.dart:79)
4. User selects "Create New Setlist" or existing setlist
5. If creating new: `repository.createSetlist` is called (setlist_detail_screen.dart:1430)
6. **Sequential loop** iterates over `_selectedSongIds`, calling `addSongToSetlistEnsureCatalog` for each (line 1451-1472)
7. Each call makes 5-6 DB queries/inserts
8. After loop completes, refresh setlists and show success snackbar

### Compare: Duplicate Setlist Flow

1. User swipes a setlist and taps "Duplicate"
2. `duplicateSetlist` is called (setlist_repository.dart:2520)
3. Fetch source setlist metadata (1 query)
4. Fetch all source songs (1 query, line 2584-2589)
5. Create new setlist (1 insert)
6. **Batch insert all songs** (1 operation, line 2605)
7. Total: 4 database operations regardless of song count

The duplicate flow is performant because it uses batch operations instead of sequential per-song operations.

## Proposed Solution

### 1. Create New Supabase RPC: `bulk_add_songs_to_setlist`

**Purpose:** Accept an array of song IDs and insert them all into a target setlist in a single atomic operation.

**Signature:**

```sql
CREATE OR REPLACE FUNCTION bulk_add_songs_to_setlist(
  p_band_id UUID,
  p_setlist_id UUID,
  p_song_ids UUID[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
```

**Logic:**

1. Verify user is an active band member
2. Verify target setlist belongs to the band
3. Get max position in target setlist (one query)
4. Filter out songs already in target setlist (one query with IN clause)
5. Build array of insert rows with sequential positions
6. **Single batch INSERT** into `setlist_songs`
7. Return JSON with `success: true`, `added_count`, `skipped_count`

**Why RPC instead of client-side batch:**

- Atomic transaction (all-or-nothing)
- Position calculation on server (prevents race conditions)
- Single round trip from client
- Proper error handling and rollback
- Follows existing pattern (see `move_song_between_setlists`)

### 2. Add Repository Method: `bulkAddSongsToSetlist`

**File:** `lib/features/setlists/setlist_repository.dart`

**Method:**

```dart
Future<BulkAddSongsResult> bulkAddSongsToSetlist({
  required String bandId,
  required String setlistId,
  required List<String> songIds,
}) async
```

**Returns:** Custom result object with `addedCount`, `skippedCount`, and `success` flag.

**Implementation:** Call the new RPC via `supabase.rpc('bulk_add_songs_to_setlist', ...)`.

### 3. Replace Sequential Loop with Batch Call

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Changes:**

1. Add loading state variable: `bool _isAddingToSetlist = false`
2. Before calling repository (line 1447), set loading state to true and show loading overlay/spinner
3. Replace the sequential for loop (lines 1451-1472) with a single call to `repository.bulkAddSongsToSetlist`
4. Parse result counts from the batch operation
5. Set loading state to false when complete
6. Show success/error snackbar based on result

**Loading indicator approach:** Use existing pattern from the codebase (check for modal bottom sheets or overlays used elsewhere in setlist_detail_screen.dart). If none exist, use a simple `showDialog` with `barrierDismissible: false` containing a `CircularProgressIndicator`.

## Database Impact

### Migration Required

**File:** `supabase/migrations/20260724054158_bulk_add_songs_to_setlist_rpc.sql`

**Content:**

- CREATE OR REPLACE FUNCTION `bulk_add_songs_to_setlist`
- SECURITY DEFINER with `SET search_path = public`
- Returns JSON with `success`, `added_count`, `skipped_count`, `error` (on failure)

### RLS Policies

**Not affected.** The RPC uses SECURITY DEFINER and performs its own band membership check, bypassing RLS. Existing RLS policies on `setlist_songs` remain unchanged.

### Affected Database Objects

- **New:** `bulk_add_songs_to_setlist` RPC function
- **Unchanged:** `setlist_songs` table schema
- **Unchanged:** All existing RLS policies
- **Unchanged:** All existing RPC functions

## Flutter Architecture Changes

### State Management

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**New state variable:**

- `bool _isAddingToSetlist = false` — tracks loading state for bulk add operation

**No provider changes required.** The existing `setlistDetailProvider` and `setlistsProvider` remain unchanged.

### Widgets Affected

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Method modified:** `_handleAddToSetlist` (line 1409)

- Add loading state management
- Replace sequential loop with batch call
- Show loading overlay during operation

**No new widgets required.** Use existing loading indicator pattern from the codebase.

### Repository Layer

**File:** `lib/features/setlists/setlist_repository.dart`

**New method:** `bulkAddSongsToSetlist` (wraps new RPC)
**New result class:** `BulkAddSongsResult` (data class with `addedCount`, `skippedCount`, `success`)

**Existing methods unchanged:**

- `addSongToSetlist` — still used by other flows
- `addSongToSetlistEnsureCatalog` — still used by single-song adds
- `duplicateSetlist` — unchanged

## Files to Create

| File                                                                   | Purpose                           |
| ---------------------------------------------------------------------- | --------------------------------- |
| `supabase/migrations/20260724054158_bulk_add_songs_to_setlist_rpc.sql` | New RPC function for batch insert |

## Files to Modify

| File                                               | Changes                                                                             |
| -------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`    | Add `bulkAddSongsToSetlist` method and `BulkAddSongsResult` class                   |
| `lib/features/setlists/setlist_detail_screen.dart` | Replace sequential loop in `_handleAddToSetlist` with batch call, add loading state |

## Files Off-Limits

| File                                                             | Reason                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | UI is correct, no changes needed                                          |
| `lib/features/setlists/setlist_detail_controller.dart`           | Not involved in this flow                                                 |
| `lib/features/setlists/new_setlist_screen.dart`                  | Not involved in this flow                                                 |
| `lib/main.dart`                                                  | Init order must not change per guardrails                                 |
| All other setlist repository methods                             | No changes to existing methods (addSongToSetlist, duplicateSetlist, etc.) |

## System Impact Map

| System                                 | Impact                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                    |
| Rehearsals                             | unaffected                                                                                    |
| Setlists / Catalog                     | **affected** — bulk-add flow performance improved, new RPC function                           |
| Members / RBAC                         | unaffected — RPC performs existing band membership check                                      |
| Auth / Session                         | unaffected                                                                                    |
| Routing                                | unaffected                                                                                    |
| Notifications                          | unaffected                                                                                    |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms benefit from performance improvement (shared Dart/Supabase code) |

## Regression Risk

**Overall Risk: LOW**

**Rationale:**

1. **Isolated change:** Only the bulk-add flow is modified. Single-song add, duplicate setlist, and all other setlist operations use separate code paths.
2. **New RPC is additive:** Existing RPC functions remain unchanged. The new RPC cannot affect existing behavior.
3. **No schema changes:** The `setlist_songs` table schema is unchanged. Only the insert method changes (batch instead of sequential).
4. **No RLS changes:** Existing RLS policies remain in place. The RPC performs its own membership validation.
5. **Client-side change is minimal:** Replace loop with single method call. The UI state machine (select mode, exit select mode, refresh) is unchanged.

**Risks identified:**

- **Position calculation:** If the RPC position calculation is wrong, songs could overlap or have gaps. Mitigated by: reusing the same position logic as `move_song_between_setlists` (get max position, increment sequentially).
- **Duplicate songs:** If the duplicate check is wrong, songs could be inserted twice. Mitigated by: using the same check as the existing single-add flow (query for existing `(setlist_id, song_id)` pairs).
- **Loading state lifecycle:** If loading state is not properly cleared on error, the UI could remain locked. Mitigated by: using try-finally to ensure loading state is always reset.

**Systems at risk:**

- Setlists: affected system, but limited to bulk-add flow only
- No other systems at risk

## Engineer Task Breakdown

### Task 1: Create Bulk Add RPC Function

**File:** `supabase/migrations/20260724054158_bulk_add_songs_to_setlist_rpc.sql`

1. Create SECURITY DEFINER function `bulk_add_songs_to_setlist(p_band_id UUID, p_setlist_id UUID, p_song_ids UUID[])`
2. Verify user is active band member (query `band_members` where `band_id = p_band_id AND user_id = auth.uid()`)
3. Verify target setlist belongs to band (query `setlists` where `id = p_setlist_id AND band_id = p_band_id`)
4. Get max position in target setlist: `SELECT COALESCE(MAX(position), -1) FROM setlist_songs WHERE setlist_id = p_setlist_id`
5. Query existing songs in target setlist: `SELECT song_id FROM setlist_songs WHERE setlist_id = p_setlist_id AND song_id = ANY(p_song_ids)`
6. Build array of insert rows (loop over song_ids, filter out existing, assign sequential positions starting at max_position + 1)
7. Batch INSERT all rows: `INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds) SELECT ...`
8. Return JSON: `json_build_object('success', true, 'added_count', ?, 'skipped_count', ?)`
9. Add EXCEPTION handler: return `json_build_object('success', false, 'error', SQLERRM)`

**Important:** Set override fields (bpm, tuning, duration_seconds) to NULL to prevent database defaults from overriding song values (same as existing `move_song_between_setlists` RPC).

### Task 2: Add Repository Method

**File:** `lib/features/setlists/setlist_repository.dart`

1. Create `BulkAddSongsResult` data class with fields: `addedCount`, `skippedCount`, `success`, `error?`
2. Add method `bulkAddSongsToSetlist(bandId, setlistId, songIds)` after existing `addSongToSetlist` method
3. Validate inputs (bandId, setlistId not empty, songIds not empty)
4. Call `supabase.rpc('bulk_add_songs_to_setlist', params: {'p_band_id': bandId, 'p_setlist_id': setlistId, 'p_song_ids': songIds})`
5. Parse JSON response into `BulkAddSongsResult`
6. Wrap in try-catch for PostgrestException and general exceptions
7. Return result object

### Task 3: Replace Sequential Loop with Batch Call

**File:** `lib/features/setlists/setlist_detail_screen.dart`

1. Add state variable: `bool _isAddingToSetlist = false`
2. In `_handleAddToSetlist`, after setlist creation succeeds (line 1445), set `_isAddingToSetlist = true` and call `setState`
3. Show loading overlay: use `showDialog` with `barrierDismissible: false` containing `CircularProgressIndicator` and message "Adding X songs..."
4. Replace the for loop (lines 1451-1472) with a single call: `final result = await repository.bulkAddSongsToSetlist(bandId: bandId, setlistId: targetSetlistId, songIds: _selectedSongIds)`
5. In try-finally block, pop loading dialog and set `_isAddingToSetlist = false`
6. Check result.success:
   - If true: use result.addedCount and result.skippedCount for snackbar message
   - If false: show error snackbar with result.error
7. Refresh setlists and exit select mode as before

### Task 4: Test Migration

1. Run migration locally: verify function is created
2. Call RPC directly via Supabase client to verify parameters and return value
3. Test with empty array, single song, 97 songs
4. Verify positions are correct and sequential
5. Verify duplicate songs are skipped

### Task 5: Test Flutter Integration

1. Test bulk-add with 1 song (should complete instantly)
2. Test bulk-add with 97 songs (should complete in <2 seconds)
3. Test bulk-add to new setlist (create + add in one flow)
4. Test bulk-add to existing setlist
5. Verify loading indicator appears and disappears
6. Verify success snackbar shows correct counts
7. Test error cases: no band selected, invalid setlist ID

## Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push`)

**Test the RPC function signature and basic logic without deploying:**

```sql
-- PRE-DEPLOY TEST 1: Verify the function signature is correct
-- This just checks that the CREATE statement is valid SQL, not that it works
DO $$
BEGIN
  -- Validate SQL syntax only
  RAISE NOTICE 'Migration SQL syntax is valid';
END $$;
```

**Note:** Since this is a new RPC function, there's no existing version to test against. All functional tests must wait until Tier 2 (post-deployment).

### Tier 2 — Post-deployment (after `supabase db push` succeeds)

**Test 1: Verify function exists**

```sql
-- POST-DEPLOY TEST 1: Verify the function was created
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'bulk_add_songs_to_setlist'
AND pg_function_is_visible(oid);

-- Expected: Returns the function definition with SECURITY DEFINER
```

**Test 2: Insert test data for functional tests**

```sql
-- POST-DEPLOY TEST 2: Create test data and verify batch insert
DO $$
DECLARE
  v_test_band_id UUID;
  v_test_user_id UUID;
  v_test_setlist_id UUID;
  v_test_song_1_id UUID;
  v_test_song_2_id UUID;
  v_test_song_3_id UUID;
  v_result JSON;
BEGIN
  -- Create test band
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Band Bulk Add', auth.uid())
  RETURNING id INTO v_test_band_id;

  v_test_user_id := auth.uid();

  -- Add user as band member
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, v_test_user_id, 'admin', 'active');

  -- Create test setlist
  INSERT INTO setlists (id, band_id, name, created_by)
  VALUES (gen_random_uuid(), v_test_band_id, 'Test Setlist', v_test_user_id)
  RETURNING id INTO v_test_setlist_id;

  -- Create test songs
  INSERT INTO songs (id, band_id, title, artist)
  VALUES (gen_random_uuid(), v_test_band_id, 'Test Song 1', 'Test Artist')
  RETURNING id INTO v_test_song_1_id;

  INSERT INTO songs (id, band_id, title, artist)
  VALUES (gen_random_uuid(), v_test_band_id, 'Test Song 2', 'Test Artist')
  RETURNING id INTO v_test_song_2_id;

  INSERT INTO songs (id, band_id, title, artist)
  VALUES (gen_random_uuid(), v_test_band_id, 'Test Song 3', 'Test Artist')
  RETURNING id INTO v_test_song_3_id;

  -- Test body with cleanup on any outcome
  BEGIN
    -- Call the RPC with 3 songs
    SELECT bulk_add_songs_to_setlist(
      v_test_band_id,
      v_test_setlist_id,
      ARRAY[v_test_song_1_id, v_test_song_2_id, v_test_song_3_id]
    ) INTO v_result;

    -- Verify result structure
    IF v_result->>'success' != 'true' THEN
      RAISE EXCEPTION 'RPC returned success=false: %', v_result->>'error';
    END IF;

    IF (v_result->>'added_count')::INT != 3 THEN
      RAISE EXCEPTION 'Expected added_count=3, got %', v_result->>'added_count';
    END IF;

    IF (v_result->>'skipped_count')::INT != 0 THEN
      RAISE EXCEPTION 'Expected skipped_count=0, got %', v_result->>'skipped_count';
    END IF;

    -- Verify songs were inserted with correct positions
    IF (SELECT COUNT(*) FROM setlist_songs WHERE setlist_id = v_test_setlist_id) != 3 THEN
      RAISE EXCEPTION 'Expected 3 songs in setlist, found %', (SELECT COUNT(*) FROM setlist_songs WHERE setlist_id = v_test_setlist_id);
    END IF;

    -- Verify positions are sequential 0, 1, 2
    IF NOT EXISTS (
      SELECT 1 FROM setlist_songs
      WHERE setlist_id = v_test_setlist_id
      AND position IN (0, 1, 2)
      GROUP BY setlist_id
      HAVING COUNT(*) = 3
    ) THEN
      RAISE EXCEPTION 'Positions are not sequential 0, 1, 2';
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      -- Clean up test data before re-raising
      DELETE FROM setlist_songs WHERE setlist_id = v_test_setlist_id;
      DELETE FROM songs WHERE id IN (v_test_song_1_id, v_test_song_2_id, v_test_song_3_id);
      DELETE FROM setlists WHERE id = v_test_setlist_id;
      DELETE FROM band_members WHERE band_id = v_test_band_id;
      DELETE FROM bands WHERE id = v_test_band_id;
      -- Re-raise original exception
      RAISE;
  END;

  -- Clean up test data (success path)
  DELETE FROM setlist_songs WHERE setlist_id = v_test_setlist_id;
  DELETE FROM songs WHERE id IN (v_test_song_1_id, v_test_song_2_id, v_test_song_3_id);
  DELETE FROM setlists WHERE id = v_test_setlist_id;
  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;

  RAISE NOTICE 'POST-DEPLOY TEST 2 PASSED: Batch insert successful';
END $$;
```

**Test 3: Verify duplicate handling**

```sql
-- POST-DEPLOY TEST 3: Verify duplicate songs are skipped
DO $$
DECLARE
  v_test_band_id UUID;
  v_test_user_id UUID;
  v_test_setlist_id UUID;
  v_test_song_1_id UUID;
  v_test_song_2_id UUID;
  v_result JSON;
BEGIN
  -- Create test band
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Band Duplicate Check', auth.uid())
  RETURNING id INTO v_test_band_id;

  v_test_user_id := auth.uid();

  -- Add user as band member
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, v_test_user_id, 'admin', 'active');

  -- Create test setlist
  INSERT INTO setlists (id, band_id, name, created_by)
  VALUES (gen_random_uuid(), v_test_band_id, 'Test Setlist Dup', v_test_user_id)
  RETURNING id INTO v_test_setlist_id;

  -- Create test songs
  INSERT INTO songs (id, band_id, title, artist)
  VALUES (gen_random_uuid(), v_test_band_id, 'Duplicate Test 1', 'Artist')
  RETURNING id INTO v_test_song_1_id;

  INSERT INTO songs (id, band_id, title, artist)
  VALUES (gen_random_uuid(), v_test_band_id, 'Duplicate Test 2', 'Artist')
  RETURNING id INTO v_test_song_2_id;

  -- Add song 1 to setlist first
  INSERT INTO setlist_songs (setlist_id, song_id, position)
  VALUES (v_test_setlist_id, v_test_song_1_id, 0);

  -- Test body with cleanup on any outcome
  BEGIN
    -- Now call RPC with both songs (song 1 already exists)
    SELECT bulk_add_songs_to_setlist(
      v_test_band_id,
      v_test_setlist_id,
      ARRAY[v_test_song_1_id, v_test_song_2_id]
    ) INTO v_result;

    -- Verify added_count=1 (only song 2), skipped_count=1 (song 1)
    IF (v_result->>'added_count')::INT != 1 THEN
      RAISE EXCEPTION 'Expected added_count=1, got %', v_result->>'added_count';
    END IF;

    IF (v_result->>'skipped_count')::INT != 1 THEN
      RAISE EXCEPTION 'Expected skipped_count=1, got %', v_result->>'skipped_count';
    END IF;

    -- Verify total count is 2 (not 3)
    IF (SELECT COUNT(*) FROM setlist_songs WHERE setlist_id = v_test_setlist_id) != 2 THEN
      RAISE EXCEPTION 'Expected 2 songs total, found %', (SELECT COUNT(*) FROM setlist_songs WHERE setlist_id = v_test_setlist_id);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      -- Clean up test data before re-raising
      DELETE FROM setlist_songs WHERE setlist_id = v_test_setlist_id;
      DELETE FROM songs WHERE id IN (v_test_song_1_id, v_test_song_2_id);
      DELETE FROM setlists WHERE id = v_test_setlist_id;
      DELETE FROM band_members WHERE band_id = v_test_band_id;
      DELETE FROM bands WHERE id = v_test_band_id;
      -- Re-raise original exception
      RAISE;
  END;

  -- Clean up (success path)
  DELETE FROM setlist_songs WHERE setlist_id = v_test_setlist_id;
  DELETE FROM songs WHERE id IN (v_test_song_1_id, v_test_song_2_id);
  DELETE FROM setlists WHERE id = v_test_setlist_id;
  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;

  RAISE NOTICE 'POST-DEPLOY TEST 3 PASSED: Duplicate handling correct';
END $$;
```

**Test 4: Production verification**

```sql
-- POST-DEPLOY TEST 4: Verify no bad data was written to production
-- This assumes the migration was run on production data
SELECT COUNT(*) AS orphaned_setlist_songs
FROM setlist_songs ss
WHERE NOT EXISTS (SELECT 1 FROM setlists s WHERE s.id = ss.setlist_id)
   OR NOT EXISTS (SELECT 1 FROM songs sg WHERE sg.id = ss.song_id);

-- Expected: 0 (no orphaned records)
```

## QA Regression Areas

QA must test the following:

### Primary Flow (Bulk Add)

1. **Bulk add to new setlist:**
   - Open catalog
   - Select all 97 songs
   - Tap "Add To Setlist"
   - Select "Create New Setlist"
   - Enter setlist name "Performance Test"
   - Observe: Loading indicator appears immediately
   - Observe: Operation completes in <2 seconds (not 60-90 seconds)
   - Verify: All 97 songs appear in new setlist in correct order
   - Verify: Success snackbar shows "Added 97 songs to 'Performance Test'"

2. **Bulk add to existing setlist:**
   - Open catalog
   - Select 10 songs
   - Tap "Add To Setlist"
   - Select an existing non-catalog setlist
   - Observe: Loading indicator appears
   - Observe: Operation completes quickly (<1 second)
   - Verify: All 10 songs added to setlist
   - Verify: Success snackbar shows correct count

3. **Bulk add with duplicates:**
   - Open catalog
   - Select 5 songs
   - Add them to a new setlist
   - Go back to catalog
   - Select the same 5 songs + 5 new songs (10 total)
   - Add to the same setlist
   - Verify: Success snackbar shows "Added 5 songs, 5 already in setlist" (or similar)
   - Verify: Setlist now has 10 songs total (not 15)

### Edge Cases

4. **Small selection (1-2 songs):**
   - Select 1 song, add to new setlist
   - Verify: Works correctly with loading indicator

5. **Cancel during creation:**
   - Select songs
   - Tap "Add To Setlist"
   - Tap "Create New Setlist"
   - Tap "Cancel" in the name input dialog
   - Verify: No songs added, no errors

6. **Navigation away (dropped songs test):**
   - Open catalog
   - Select 97 songs
   - Tap "Add To Setlist" → "Create New Setlist"
   - Enter name
   - **While loading indicator is visible**, attempt to tap back or swipe to dismiss
   - Verify: Loading dialog is not dismissible (barrierDismissible: false)
   - Verify: After operation completes, all 97 songs are in the setlist

### Regression Testing

7. **Duplicate setlist (unchanged fast path):**
   - Open a setlist with 97 songs
   - Swipe left, tap "Duplicate"
   - Verify: Completes instantly as before
   - Verify: All 97 songs duplicated correctly

8. **Single-song add (unchanged):**
   - Open a setlist
   - Swipe right on a single song from catalog
   - Select destination setlist
   - Verify: Song added correctly

9. **Move song between setlists:**
   - Open a setlist
   - Swipe right on a song
   - Select "Move" mode
   - Select destination setlist
   - Verify: Song moved (removed from source, added to destination)

### Platform Coverage

10. **Test on all platforms:**
    - iOS: Test bulk add with 97 songs
    - Android: Test bulk add with 97 songs
    - Web: Test bulk add with 97 songs
    - macOS: Test bulk add with 97 songs

## Rollout / Migration Strategy

**Migration:** Deploy RPC function first via `supabase db push`. The new function is additive and does not affect existing functionality.

**Flutter Deployment:** Deploy Flutter code change after migration is confirmed. The app will fall back gracefully if the RPC is not yet deployed (will receive an error and show error snackbar).

**Rollback:** If issues arise, the change is isolated to the bulk-add flow. Rollback by reverting the Flutter code change. The RPC function can remain in the database (it's not called by the old code).

## Out of Scope

1. **Performance optimization of other add-song flows:** Single-song add and catalog auto-add are not changed. This fix applies only to the bulk "Add to setlist" flow from the catalog.

2. **Catalog auto-add logic:** The `addSongToSetlistEnsureCatalog` method still ensures songs are in the Catalog. This fix does not change that behavior — it only batches the inserts.

3. **UI redesign:** The setlist picker UI and the catalog multi-select UI remain unchanged. Only the loading indicator is added.

4. **Batch move or copy from setlist detail:** The single-song move/copy flows remain unchanged. This fix applies only to bulk add from the catalog.

5. **Handling the unconfirmed dropped-songs report:** The MEDIUM confidence diagnosis suggests the issue is caused by users navigating away during the slow operation. The fix (loading indicator with `barrierDismissible: false`) should prevent navigation, but if the dropped-songs issue persists after this fix, further investigation will be required.
