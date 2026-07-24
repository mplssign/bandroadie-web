# Architect Plan — Move Song Between Setlists Failure

## Feature Slug

`bug/move-song-between-setlists-failure`

## Problem Summary

The "Move" action from setlist song swipe-right menu fails with error "duplicate key value violates unique constraint \"setlist_songs_setlist_id_position_key\"" for all song/target combinations, while "Copy" succeeds reliably. Both operations INSERT into `setlist_songs`, but Move performs a delete-then-insert sequence via the `move_song_between_setlists` RPC, while Copy performs only an INSERT.

## Root Cause

**Confidence: CONFIRMED**

The failure occurs during the **DELETE phase** of the Move operation, not during INSERT. The AFTER DELETE trigger `reorder_setlist_positions_on_delete` (function `reorder_setlist_positions`) fires on the source setlist and causes a transient unique constraint violation:

```sql
BEGIN
  WITH ordered_songs AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) as new_position
    FROM public.setlist_songs
    WHERE setlist_id = COALESCE(NEW.setlist_id, OLD.setlist_id)
  )
  UPDATE public.setlist_songs
  SET position = ordered_songs.new_position
  FROM ordered_songs
  WHERE public.setlist_songs.id = ordered_songs.id;
  RETURN COALESCE(NEW, OLD);
END;
```

**Why this causes failure:**

1. **1-indexed vs 0-indexed mismatch:** `ROW_NUMBER()` starts at 1, but app data is 0-indexed (confirmed by single-song setlist having `position = 0`)

2. **NOT DEFERRABLE constraint:** The unique constraint `setlist_songs_setlist_id_position_key (setlist_id, position)` is NOT DEFERRABLE, meaning Postgres checks uniqueness after each individual row update within the multi-row UPDATE statement

3. **Transient collision scenario:**
   - Starting positions: `[0, 1, 2, 3]`
   - Delete position `2` → remaining: `[0, 1, 3]`
   - Trigger computes: `ROW_NUMBER()` → `[1, 2, 3]` (1-indexed)
   - UPDATE attempts: `position 0→1`, `position 1→2`, `position 3→3`
   - When Postgres updates `position 0→1`, position `1` still exists (hasn't been updated to `2` yet)
   - **DUPLICATE KEY ERROR on (setlist_id, position=1)**

4. **Evidence from real data:** "My Awesome Setlist" (31 songs) has positions `[0, 1, 4, 5, 6, ..., 32]` — positions 2 and 3 are missing. This proves the trigger fails intermittently, leaving gaps that shouldn't exist if the trigger's "keep positions sequential" logic actually worked reliably.

**Why Copy works:** Copy never deletes from the source setlist, so the trigger never fires.

**Why Move fails:** Move deletes from source, trigger fires, causes collision during the DELETE phase before INSERT is even attempted.

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — confirmed setlist_songs schema and RPC inventory
- Direct SQL queries on production database (provided by Tony) — confirmed trigger source, constraint properties, and data gaps

## Existing System Analysis

### Current Behavior (Move Operation)

1. **Client**: `SetlistDetailScreen._handleMoveOrCopyAction` (line 426-430) calls `SetlistDetailController.moveSongToSetlist`
2. **Controller**: `moveSongToSetlist` (line 973-978) calls `SetlistRepository.moveSongBetweenSetlists`
3. **Repository**: `moveSongBetweenSetlists` (line 3784-3792) invokes RPC `move_song_between_setlists`
4. **RPC**:
   - Validates user is band member (line 23-34)
   - Validates setlists belong to band (line 36-72)
   - Checks song not already in target (line 74-84)
   - Calculates max position in target (line 86-89)
   - **DELETE** from source setlist (line 91-95)
     - **Triggers `reorder_setlist_positions_on_delete` — FAILS HERE with duplicate key error**
     - Also triggers `trigger_setlist_stats_on_delete`, `update_setlist_duration_on_delete` (harmless)
   - **INSERT** never reached due to DELETE failure
5. **Repository**: Returns boolean based on RPC response `success` field
6. **Screen**: Shows "Failed to move song" if false (line 447)

### Affected Delete Operations (Beyond Move)

This trigger fires on **ANY** delete from `setlist_songs`:

1. **`deleteSongFromSetlist`** (setlist_repository.dart:792)
   - Called via RPC `delete_song_from_setlist` or direct DELETE fallback (line 834-838)
   - Used when user swipes left to remove song from non-catalog setlist
2. **`deleteSongFromCatalog`** (setlist_repository.dart:861)
   - Deletes from ALL setlist_songs for this song across all setlists
   - Used when user deletes song from Catalog view
3. **Special item deletion** (special_item_repository.dart:200)
   - Direct DELETE from setlist_songs for set breaks/pauses
4. **Cascade deletes**
   - When setlist is deleted (deletes all setlist_songs via FK)
   - When special_item is deleted (cascades to setlist_songs)

**All of these operations are exposed to the same collision bug.**

### Database Constraints Verified

- `setlist_songs_setlist_id_position_key`: UNIQUE (setlist_id, position), **NOT DEFERRABLE** ← root cause
- Trigger `reorder_setlist_positions_on_delete`: fires AFTER DELETE on setlist_songs
- Position values in app: 0-indexed (confirmed via query)
- Trigger uses `ROW_NUMBER()`: 1-indexed (starts at 1)
- Real data has gaps: positions 2, 3 missing from 31-song setlist ← proves trigger fails intermittently

## Proposed Solution

**Two-part database migration:**

### Part 1: Make unique constraint deferrable

```sql
-- Drop existing NOT DEFERRABLE constraint
ALTER TABLE public.setlist_songs
  DROP CONSTRAINT setlist_songs_setlist_id_position_key;

-- Recreate as DEFERRABLE INITIALLY DEFERRED
ALTER TABLE public.setlist_songs
  ADD CONSTRAINT setlist_songs_setlist_id_position_key
  UNIQUE (setlist_id, position)
  DEFERRABLE INITIALLY DEFERRED;
```

**Why:** Allows all UPDATE rows to complete before checking uniqueness, preventing transient collisions.

### Part 2: Replace wholesale renumbering with surgical decrement

```sql
CREATE OR REPLACE FUNCTION public.reorder_setlist_positions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Instead of renumbering everything with ROW_NUMBER(),
  -- just decrement positions greater than the deleted position
  UPDATE public.setlist_songs
  SET position = position - 1
  WHERE setlist_id = OLD.setlist_id
    AND position > OLD.position;

  RETURN OLD;
END;
$$;
```

**Why surgical approach is better:**

- Only mutates rows after deleted position (minimal disruption)
- No 1-indexed vs 0-indexed mismatch (no ROW_NUMBER())
- Faster execution (fewer rows updated)
- Preserves app's 0-indexed convention
- Lower risk of unintended side effects

**Combined fix rationale:**

- DEFERRABLE constraint prevents collision even if multiple rows compete for same position during UPDATE
- Surgical decrement reduces likelihood of collision in the first place by minimizing row mutations
- Keeps trigger in place (safer than removing it entirely, in case other code relies on it)

## Database Impact

**Affected**

- Migration: New migration required to:
  1. Alter constraint from NOT DEFERRABLE to DEFERRABLE INITIALLY DEFERRED
  2. Drop and recreate `reorder_setlist_positions` function with surgical logic
- Constraint: `setlist_songs_setlist_id_position_key` — made deferrable
- Trigger: `reorder_setlist_positions_on_delete` — unchanged (still AFTER DELETE)
- Function: `reorder_setlist_positions` — rewritten with surgical decrement

**Unaffected**

- RLS policies: no changes
- RPC `move_song_between_setlists`: no changes (fix is in trigger/constraint layer)
- Other RPCs: no changes
- Table schema: no new columns, no data type changes
- Other triggers: no changes (stats/duration triggers remain unchanged)

## Flutter Architecture Changes

**Unaffected** — no Dart code changes required. This is a pure database-layer fix.

## Files to Create

None

## Files to Modify

| File                                                                          | What changes                                                                                                                                    |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<timestamp>_fix_setlist_positions_trigger_collision.sql` | Create new migration with two parts: (1) ALTER TABLE to make constraint DEFERRABLE, (2) CREATE OR REPLACE FUNCTION for surgical decrement logic |

## Files Off-Limits

| File                     | Reason                                                          |
| ------------------------ | --------------------------------------------------------------- |
| `lib/**/*.dart`          | No Flutter code changes needed — database-only fix              |
| Existing migration files | Never modify existing migrations — create new migration instead |

**Migration policy:** required  
**Edge function deploy:** not required  
**New dependencies:** not allowed  
**New files:** none (only one migration file)

## System Impact Map

| System                                 | Impact                                                               |
| -------------------------------------- | -------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                           |
| Rehearsals                             | unaffected                                                           |
| Setlists / Catalog                     | **affected** — move operation fixed; delete operations more reliable |
| Members / RBAC                         | unaffected                                                           |
| Auth / Session                         | unaffected                                                           |
| Routing                                | unaffected                                                           |
| Notifications                          | unaffected                                                           |
| Platform (iOS / Android / Web / macOS) | unaffected — server-side fix only                                    |

## Regression Risk

**Level: MEDIUM**

**Rationale:**

- **Higher risk than initially thought:** Trigger fires on EVERY delete from `setlist_songs`, not just Move operation
- Affects: regular song deletion, catalog deletion, special item deletion, cascade deletes
- Constraint change (NOT DEFERRABLE → DEFERRABLE) is well-understood but affects transaction behavior
- Trigger rewrite changes from "renumber all" to "decrement some" — different logic path
- Real production data has gaps, suggesting current trigger already fails unpredictably — fix may surface hidden bugs
- **However:** DEFERRABLE constraint is a standard pattern for preventing this exact class of bug, and surgical approach is simpler/faster than wholesale renumbering

**Risk mitigation:**

- Constraint being INITIALLY DEFERRED means it still enforces uniqueness, just at different timing
- Surgical decrement is conceptually simpler than ROW_NUMBER() renumbering
- Comprehensive pre/post-deploy tests verify both constraint enforcement and trigger behavior
- Test coverage includes all affected deletion paths (not just Move)

## Engineer Task Breakdown

1. Create new migration file: `<timestamp>_fix_setlist_positions_trigger_collision.sql`
2. Add comment block explaining root cause and fix strategy
3. Write Part 1: DROP CONSTRAINT and ADD CONSTRAINT with DEFERRABLE
4. Write Part 2: CREATE OR REPLACE FUNCTION with surgical decrement logic
5. Verify migration compiles locally with `supabase db reset`
6. Run all Tier 1 (pre-deploy) tests
7. Deploy migration to staging with `supabase db push`
8. Run all Tier 2 (post-deploy) tests in staging
9. Test all affected deletion operations in staging app (Move, Delete from setlist, Delete from Catalog, Delete special item)
10. Deploy to production
11. Monitor runtime logs for 48 hours

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1: Verify current constraint is NOT DEFERRABLE
SELECT conname, condeferrable, condeferred
FROM pg_constraint
WHERE conrelid = 'public.setlist_songs'::regclass
  AND conname = 'setlist_songs_setlist_id_position_key';
-- Expected: condeferrable=false, condeferred=false

-- PRE-DEPLOY TEST 2: Verify trigger exists and uses ROW_NUMBER()
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'reorder_setlist_positions'
  AND pronamespace = 'public'::regnamespace;
-- Expected: function source contains "ROW_NUMBER()"

-- PRE-DEPLOY TEST 3: Verify trigger is attached to setlist_songs
SELECT tgname, tgtype, tgfoid::regproc
FROM pg_trigger
WHERE tgrelid = 'public.setlist_songs'::regclass
  AND tgname = 'reorder_setlist_positions_on_delete';
-- Expected: returns 1 row with tgfoid = 'reorder_setlist_positions'

-- PRE-DEPLOY TEST 4: Document existing position gaps (before fix)
SELECT setlist_id,
       COUNT(*) as song_count,
       MIN(position) as min_pos,
       MAX(position) as max_pos,
       MAX(position) - COUNT(*) + 1 as expected_gap_indicator
FROM setlist_songs
GROUP BY setlist_id
HAVING MAX(position) - COUNT(*) + 1 > 0
ORDER BY expected_gap_indicator DESC
LIMIT 10;
-- Expected: returns setlists with position gaps (documents current broken state)
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Verify constraint is now DEFERRABLE
SELECT conname, condeferrable, condeferred
FROM pg_constraint
WHERE conrelid = 'public.setlist_songs'::regclass
  AND conname = 'setlist_songs_setlist_id_position_key';
-- Expected: condeferrable=true, condeferred=true

-- POST-DEPLOY TEST 2: Verify trigger function uses surgical decrement (not ROW_NUMBER)
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'reorder_setlist_positions'
  AND pronamespace = 'public'::regnamespace;
-- Expected: function source contains "position = position - 1" and "position > OLD.position"
-- Expected: NO "ROW_NUMBER()" in function source

-- POST-DEPLOY TEST 3: End-to-end move operation test
DO $$
DECLARE
  v_band_id UUID;
  v_user_id UUID := auth.uid();
  v_source_setlist_id UUID;
  v_target_setlist_id UUID;
  v_song_1_id UUID;
  v_song_2_id UUID;
  v_song_3_id UUID;
  v_song_4_id UUID;
  v_result JSON;
BEGIN
  -- Find test band where current user is a member
  SELECT band_id INTO v_band_id
  FROM band_members
  WHERE user_id = v_user_id
    AND status = 'active'
  LIMIT 1;

  IF v_band_id IS NULL THEN
    RAISE EXCEPTION 'No active band membership found for current user';
  END IF;

  -- Create test setlists
  INSERT INTO setlists (band_id, name, setlist_type)
  VALUES (v_band_id, 'TEST SOURCE (auto-cleanup)', 'regular')
  RETURNING id INTO v_source_setlist_id;

  INSERT INTO setlists (band_id, name, setlist_type)
  VALUES (v_band_id, 'TEST TARGET (auto-cleanup)', 'regular')
  RETURNING id INTO v_target_setlist_id;

  -- Create 4 distinct test songs
  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST SONG 1', 'TEST ARTIST')
  RETURNING id INTO v_song_1_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST SONG 2', 'TEST ARTIST')
  RETURNING id INTO v_song_2_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST SONG 3', 'TEST ARTIST')
  RETURNING id INTO v_song_3_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST SONG 4', 'TEST ARTIST')
  RETURNING id INTO v_song_4_id;

  -- Populate source setlist with 4 songs to create collision scenario
  INSERT INTO setlist_songs (setlist_id, song_id, position)
  VALUES
    (v_source_setlist_id, v_song_1_id, 0),
    (v_source_setlist_id, v_song_2_id, 1),
    (v_source_setlist_id, v_song_3_id, 2),
    (v_source_setlist_id, v_song_4_id, 3);

  -- Call move RPC on position 2 (song 3) — this is where collision occurred before fix
  v_result := move_song_between_setlists(
    v_source_setlist_id,
    v_target_setlist_id,
    v_song_3_id,
    v_band_id
  );

  -- Verify success
  IF (v_result->>'success')::boolean != true THEN
    RAISE EXCEPTION 'Move RPC failed: %', v_result->>'error';
  END IF;

  -- Verify remaining positions in source are sequential with no gaps
  PERFORM 1
  FROM (
    SELECT position, ROW_NUMBER() OVER (ORDER BY position) - 1 as expected_position
    FROM setlist_songs
    WHERE setlist_id = v_source_setlist_id
  ) t
  WHERE position != expected_position;

  IF FOUND THEN
    RAISE EXCEPTION 'Positions in source setlist have gaps after move';
  END IF;

  -- Cleanup
  DELETE FROM setlist_songs WHERE setlist_id IN (v_source_setlist_id, v_target_setlist_id);
  DELETE FROM setlists WHERE id IN (v_source_setlist_id, v_target_setlist_id);
  DELETE FROM songs WHERE id IN (v_song_1_id, v_song_2_id, v_song_3_id, v_song_4_id);

  RAISE NOTICE 'POST-DEPLOY TEST 3 PASSED: Move operation succeeded with proper position renumbering';
END $$;

-- POST-DEPLOY TEST 4: Test direct delete from setlist (not via move)
DO $$
DECLARE
  v_band_id UUID;
  v_user_id UUID := auth.uid();
  v_setlist_id UUID;
  v_song_1_id UUID;
  v_song_2_id UUID;
  v_song_3_id UUID;
  v_song_4_id UUID;
BEGIN
  -- Find test band
  SELECT band_id INTO v_band_id
  FROM band_members
  WHERE user_id = v_user_id
    AND status = 'active'
  LIMIT 1;

  IF v_band_id IS NULL THEN
    RAISE EXCEPTION 'No active band membership found';
  END IF;

  -- Create test setlist
  INSERT INTO setlists (band_id, name, setlist_type)
  VALUES (v_band_id, 'TEST DELETE (auto-cleanup)', 'regular')
  RETURNING id INTO v_setlist_id;

  -- Create 4 distinct test songs
  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST DELETE SONG 1', 'TEST ARTIST')
  RETURNING id INTO v_song_1_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST DELETE SONG 2', 'TEST ARTIST')
  RETURNING id INTO v_song_2_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST DELETE SONG 3', 'TEST ARTIST')
  RETURNING id INTO v_song_3_id;

  INSERT INTO songs (band_id, title, artist)
  VALUES (v_band_id, 'TEST DELETE SONG 4', 'TEST ARTIST')
  RETURNING id INTO v_song_4_id;

  -- Add 4 songs at positions [0, 1, 2, 3]
  INSERT INTO setlist_songs (setlist_id, song_id, position)
  VALUES
    (v_setlist_id, v_song_1_id, 0),
    (v_setlist_id, v_song_2_id, 1),
    (v_setlist_id, v_song_3_id, 2),
    (v_setlist_id, v_song_4_id, 3);

  -- Delete middle position (should trigger reordering)
  DELETE FROM setlist_songs
  WHERE setlist_id = v_setlist_id
    AND position = 1;

  -- Verify remaining positions are sequential [0, 1, 2] (not [0, 2, 3])
  PERFORM 1
  FROM (
    SELECT position, ROW_NUMBER() OVER (ORDER BY position) - 1 as expected
    FROM setlist_songs
    WHERE setlist_id = v_setlist_id
  ) t
  WHERE position != expected;

  IF FOUND THEN
    RAISE EXCEPTION 'Direct delete did not properly renumber positions';
  END IF;

  -- Cleanup
  DELETE FROM setlist_songs WHERE setlist_id = v_setlist_id;
  DELETE FROM setlists WHERE id = v_setlist_id;
  DELETE FROM songs WHERE id IN (v_song_1_id, v_song_2_id, v_song_3_id, v_song_4_id);

  RAISE NOTICE 'POST-DEPLOY TEST 4 PASSED: Direct delete properly renumbered positions';
END $$;
```

## QA Regression Areas

QA must test **all deletion paths**, not just Move:

### Primary Test (Move Operation)

1. Open setlist with at least 3 songs
2. Swipe song card at position 1 (middle position) to the right
3. Choose "Move" and select an existing setlist as target
4. Verify: success message "Song moved to [target]" appears
5. Verify: song is removed from source setlist
6. Verify: remaining songs have sequential positions starting at 0 (no gaps)
7. Verify: song appears in target setlist at end of list

### Secondary Tests (Other Deletion Paths)

1. **Delete song from setlist** (not Move, just Remove):
   - Open setlist with 4+ songs
   - Swipe left on song at position 2 (middle)
   - Choose "Remove from Setlist"
   - Verify: song removed
   - Verify: remaining songs have sequential positions with no gaps

2. **Delete song from Catalog** (cascades to all setlists):
   - Add same song to 2 different setlists
   - Open Catalog view
   - Swipe left on song, choose "Delete from Catalog"
   - Verify: song removed from Catalog
   - Verify: song removed from both setlists
   - Verify: both setlists maintain sequential positions

3. **Delete special item** (set break/pause):
   - Open setlist with songs before and after a set break
   - Delete the set break
   - Verify: set break removed
   - Verify: songs maintain sequential positions

4. **Copy operation** (should still work):
   - Swipe right, choose "Copy"
   - Verify: song duplicated into target (remains in source)

5. **Position integrity after multiple operations**:
   - Perform sequence: Move song A, Delete song B, Move song C
   - Verify: all affected setlists maintain sequential 0-indexed positions throughout

### Platform Coverage

- iOS (primary platform for bug report)
- Android
- Web
- macOS (if applicable)

## Rollout / Migration Strategy

1. Deploy migration to staging
2. Run POST-DEPLOY tests 1-4 in staging psql console
3. **Test all deletion paths in staging app** (Move, Remove, Delete from Catalog, Delete special item)
4. Monitor staging logs for any constraint violations or trigger errors
5. Deploy to production during low-traffic window
6. Monitor production logs for 48 hours for:
   - Constraint violation errors (should be zero)
   - Trigger execution failures (should be zero)
   - Gap formation in position sequences (should be zero)

## Out of Scope

- Backfilling existing position gaps in production data (can be done separately if needed)
- Removing the trigger entirely (too risky without full app audit to confirm it's unused)
- Changing RPC `move_song_between_setlists` logic (not needed — fix is at trigger/constraint layer)
- Switching to 1-indexed positions app-wide (would require massive Dart refactor)
- Making all unique constraints DEFERRABLE (only fixing this specific high-risk one)
