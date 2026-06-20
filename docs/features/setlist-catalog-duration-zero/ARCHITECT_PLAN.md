# Architect Plan

## Feature Slug

`bug/setlist-catalog-duration-zero`

## Problem Summary

Duration totals display `0h 00m` on both setlist detail screens and catalog screen, despite songs having valid duration values. This is a regression — duration totals were displaying correctly in previous builds.

The symptom manifests in the detail screen header where metadata is shown (e.g., "24 songs • 0h 00m" instead of "24 songs • 1h 39m").

## Root Cause

**DIAGNOSIS CONFIDENCE: HIGH**

The root cause has been traced through code-path analysis and git history:

1. **Commit `153df46`** (March 23, 2026) changed the `fetchSetlistsForBand` repository query from `setlist_songs(count)` to `setlist_songs(item_type)` to enable counting songs, pauses, and set breaks separately.

2. This change removed the duration data that was being aggregated from the nested query, causing setlist cards in the list view to show `0h 00m`.

3. **Commit `b2d8e86`** (March 24, 2026 — "fix: read song duration from songs table join in setlist card total") fixed the setlist **card** duration display by adding `song:songs(duration_seconds), setlist_special_items(duration_minutes, duration_seconds)` to the nested select in `fetchSetlistsForBand`, allowing the repository to manually compute `totalDurationSeconds` and override the `total_duration` field.

4. **However**, the detail screen uses different code paths:
   - **Catalog detail**: Uses `SetlistDetailState.totalDuration` getter, which folds over `state.songs` and sums `song.duration`
   - **Non-Catalog setlist detail**: Uses `SetlistDetailState.totalDuration` getter, which folds over `state.items` and sums `item.durationSeconds`

5. Both `state.songs` and `state.items` are populated by queries (`fetchSongsForSetlist` and `fetchSetlistItems`) that **already include** `songs(duration_seconds)` in their nested selects — so the queries are correct.

6. The display bug suggests that songs in the database have `NULL` or `0` values for `duration_seconds`, OR there is a data loading issue where duration values are not being propagated correctly into the `SetlistSong` model.

7. **Verified via code inspection**: The `SetlistSong.fromSupabase` factory (line 100 of `setlist_song.dart`) reads `songData['duration_seconds'] as int? ?? 0`, which means NULL values from the database default to 0, resulting in a computed total of 0 seconds.

**Root cause**: Songs in the production database have `NULL` or `0` values in the `songs.duration_seconds` column, causing all duration calculations to sum to 0.

**Why this is a regression**: Songs added in earlier builds may have had duration data populated correctly, but recent songs or a schema change may have resulted in NULL/0 values. Alternatively, a migration may have inadvertently cleared existing duration data.

## Reference Docs Consulted

None applicable. No `docs/reference/setlists/` or `docs/reference/duration/` directories exist. Analysis was performed via codebase inspection and git history review.

## Existing System Analysis

### Current Data Flow (Setlist Detail)

**For Catalog:**

1. `SetlistDetailController.loadSongs()` calls `_repository.fetchSongsForSetlist()`
2. Repository query:
   ```sql
   SELECT song_id, position,
          songs!inner(id, title, artist, bpm, duration_seconds, tuning, ...)
   FROM setlist_songs
   WHERE setlist_id = ? ORDER BY position
   ```
3. Parsed into `List<SetlistSong>` via `SetlistSong.fromSupabase(json)`, where `durationSeconds = songData['duration_seconds'] as int? ?? 0`
4. Stored in `state.songs`
5. UI calls `state.formattedDuration` → `state.totalDuration` → folds `songs` and sums `song.duration` → `Duration(seconds: durationSeconds)`

**For Non-Catalog setlists:**

1. `SetlistDetailController.loadSongs()` calls `_specialItemRepo.fetchSetlistItems()`
2. Repository query:
   ```sql
   SELECT id, song_id, special_item_id, item_type, position,
          songs(id, title, artist, bpm, duration_seconds, ...),
          setlist_special_items(id, type, duration_minutes, duration_seconds, ...)
   FROM setlist_songs
   WHERE setlist_id = ? ORDER BY position
   ```
3. Parsed into `List<SetlistItem>` containing `SetlistSong` objects
4. Stored in `state.items` (and also extracted into `state.songs`)
5. UI calls `state.formattedDuration` → `state.totalDuration` → folds `items` and sums `item.durationSeconds` → `song?.durationSeconds ?? 0` or `specialItem?.totalDurationSeconds ?? 0`

**Both paths rely on `songs.duration_seconds` column containing valid data.**

### Current Behavior

- **Expected**: Duration totals reflect the sum of all song durations (e.g., "1h 39m")
- **Actual**: Duration totals show "0h 00m"
- **Confirmed**: Queries are correct, data parsing is correct, display logic is correct
- **Therefore**: The database column `songs.duration_seconds` contains NULL or 0 values

### Identified Gap

There is **no database migration or data validation** ensuring that `songs.duration_seconds` is populated when songs are created or imported. The column may be nullable, and the application may not enforce duration entry.

Additionally, there is **no diagnostic logging** to confirm whether duration values are being read correctly from the database or whether NULL values are being returned.

## Proposed Solution

This is a **diagnostic and data validation task**, not a code fix. The queries and display logic are correct.

### Phase 1: Diagnostic Verification (Required Before Fix)

**Task 1.1**: Run the following SQL query against the production database to confirm the root cause:

```sql
-- Check how many songs have NULL or 0 duration
SELECT
  COUNT(*) AS total_songs,
  COUNT(CASE WHEN duration_seconds IS NULL THEN 1 END) AS null_duration,
  COUNT(CASE WHEN duration_seconds = 0 THEN 1 END) AS zero_duration,
  COUNT(CASE WHEN duration_seconds > 0 THEN 1 END) AS valid_duration
FROM songs;
```

**Expected result if root cause is confirmed**: `null_duration` or `zero_duration` will be > 0.

**Task 1.2**: If NULL/0 durations are found, identify affected songs:

```sql
-- Find songs with missing duration
SELECT id, title, artist, created_at, duration_seconds
FROM songs
WHERE duration_seconds IS NULL OR duration_seconds = 0
ORDER BY created_at DESC
LIMIT 20;
```

**Task 1.3**: Check if the column is nullable in the schema:

```sql
-- Check songs table schema
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND column_name = 'duration_seconds';
```

### Phase 2: Data Backfill (If Root Cause Confirmed)

If the diagnostic confirms NULL/0 duration values, the solution is **data correction**, not code changes.

**Option A: Manual Data Entry** (small number of songs)

Use the existing inline edit feature in the setlist detail screen to manually enter duration for each song with missing data.

**Option B: Bulk Update SQL** (large number of songs)

If a significant number of songs are affected, a migration script can populate default duration values:

```sql
-- Set a default duration of 3 minutes (180 seconds) for songs with NULL/0 duration
-- This is a safe placeholder — users can edit inline afterward
UPDATE songs
SET duration_seconds = 180
WHERE duration_seconds IS NULL OR duration_seconds = 0;
```

**Option C: Schema Constraint** (prevent future occurrences)

Add a NOT NULL constraint with a default value to prevent future songs from having NULL duration:

```sql
-- Migration: Make duration_seconds NOT NULL with default
ALTER TABLE songs
ALTER COLUMN duration_seconds SET DEFAULT 180;

UPDATE songs
SET duration_seconds = 180
WHERE duration_seconds IS NULL OR duration_seconds = 0;

ALTER TABLE songs
ALTER COLUMN duration_seconds SET NOT NULL;
```

### Phase 3: Application Enhancement (Optional — Future Work)

If the root cause is that songs are being added without duration:

1. **Update song creation forms** to require duration entry
2. **Add validation** in `SetlistRepository.addSongToSetlistEnsureCatalog()` to reject songs with NULL/0 duration
3. **Add diagnostic logging** in `SetlistSong.fromSupabase()` to warn when NULL durations are encountered

**This phase is OUT OF SCOPE for this bug fix.** The immediate fix is data correction.

## Database Impact

**Not applicable** — no schema changes required for the minimal fix (diagnostic + manual data entry).

**If schema constraint is added** (Option C above):

- **Migration required**: Yes — new migration file to add NOT NULL constraint
- **RLS policies**: Not affected — no policy changes
- **RPC functions**: Not affected — no function signature changes
- **Triggers**: Not affected

## Flutter Architecture Changes

**None**. All queries, parsing logic, and display logic are correct. This is a data issue, not a code issue.

## Files to Create

**None** (for diagnostic/manual fix).

**If migration is required** (Option C):

| File                                                             | Purpose                                                               |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| `supabase/migrations/20260621000000_songs_duration_not_null.sql` | Add NOT NULL constraint and default value to `songs.duration_seconds` |

## Files to Modify

**None** (for diagnostic/manual fix).

**If enhanced logging is desired** (out of scope):

| File                                             | Change                                                   |
| ------------------------------------------------ | -------------------------------------------------------- |
| `lib/features/setlists/models/setlist_song.dart` | Add `debugPrint` warning when `duration_seconds` is NULL |

## Files Off-Limits

All files are off-limits for this bug fix, as the root cause is data, not code.

| File                                                   | Reason                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`        | Queries are already correct                                         |
| `lib/features/setlists/setlist_detail_controller.dart` | Duration calculation logic is already correct                       |
| `lib/features/setlists/setlist_detail_screen.dart`     | Display logic is already correct                                    |
| `lib/features/setlists/models/setlist_song.dart`       | Parsing logic is already correct (NULL → 0 fallback is appropriate) |
| `lib/main.dart`                                        | No init order changes                                               |

## System Impact Map

| System                                 | Impact                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                      |
| Rehearsals                             | unaffected                                                                      |
| Setlists / Catalog                     | **affected** — duration display will show correct values once data is corrected |
| Members / RBAC                         | unaffected                                                                      |
| Auth / Session                         | unaffected                                                                      |
| Routing                                | unaffected                                                                      |
| Notifications                          | unaffected                                                                      |
| Platform (iOS / Android / Web / macOS) | unaffected (behavior is platform-agnostic)                                      |

## Regression Risk

**LOW**

- No code changes
- Data correction only
- If schema constraint is added, existing data is backfilled before constraint is applied (no risk of constraint violation)
- Duration display will change from "0h 00m" to correct values (expected, not a regression)

## Engineer Task Breakdown

**Task 1**: Run diagnostic SQL queries (Phase 1, Tasks 1.1-1.3 above) and report findings

**Task 2**: If NULL/0 durations are confirmed, choose fix approach (A, B, or C) and document decision in ENGINEER_REPORT.md

**Task 3**: Execute chosen fix:

- **Option A**: Use inline edit UI to manually update songs
- **Option B**: Run bulk UPDATE SQL script
- **Option C**: Create migration file, test locally, apply to production

**Task 4**: Verify fix by loading setlist detail and catalog screens — duration should display correctly

**Task 5**: Run `flutter analyze` (should pass with 0 errors — no code changes)

**Task 6**: Document the fix in ENGINEER_REPORT.md with:

- Diagnostic query results
- Number of songs affected
- Fix approach used
- Before/after screenshots or logs

## Verification Plan

### Manual Verification

**Step 1: Reproduce the bug**

1. Open BandRoadie and navigate to any setlist detail screen
2. Observe the header metadata line (e.g., "24 songs • 0h 00m")
3. Confirm duration shows "0h 00m" instead of expected total

**Step 2: Run diagnostic queries**

Execute Phase 1 SQL queries against the production database and document results.

**Step 3: Apply fix**

Execute chosen fix approach (A, B, or C).

**Step 4: Verify fix**

1. Reload setlist detail screen (pull to refresh or restart app)
2. Observe duration header — should now show correct total (e.g., "1h 39m")
3. Repeat for Catalog screen
4. Verify individual song durations are displayed correctly in song cards

**Step 5: Spot check**

Open 3-5 different setlists and confirm duration totals are reasonable (non-zero if setlist contains songs).

### SQL Verification (Post-Fix)

```sql
-- Confirm no songs have NULL or 0 duration (if constraint was added)
SELECT COUNT(*)
FROM songs
WHERE duration_seconds IS NULL OR duration_seconds = 0;
-- Expected: 0

-- Spot check: verify duration values look reasonable
SELECT title, artist, duration_seconds
FROM songs
ORDER BY created_at DESC
LIMIT 10;
-- Expected: All duration_seconds > 0
```

## QA Regression Areas

**Primary validation:**

1. **Setlist detail duration display** — shows correct total duration
2. **Catalog duration display** — shows correct total duration
3. **Setlist card duration** (list view) — verify cards also show correct duration (should already be fixed by commit `b2d8e86`, but confirm)
4. **Inline song duration edit** — verify editing a song's duration updates the total immediately

**Secondary validation:**

1. **Share setlist text** — verify exported text includes correct duration in header
2. **Print setlist** — verify PDF includes correct duration metadata
3. **Add new song** — verify new songs can be created with valid duration
4. **Bulk entry** — verify songs added via bulk entry have correct duration

**Regression check:**

1. **Song count** — verify song/pause/set break counts are still correct (unaffected by duration fix)
2. **Special items** — verify pauses and set breaks contribute correct duration to total
3. **Empty setlist** — verify empty setlist shows "0m" (not "0h 00m") per existing format logic

## Rollout / Migration Strategy

**If Option A or B (manual/bulk SQL update):**

1. Run SQL in production during low-traffic window
2. No app deployment required
3. Users will see corrected duration on next app open

**If Option C (schema constraint migration):**

1. Create migration file in `supabase/migrations/`
2. Test migration locally: `supabase db reset`
3. Deploy to staging first: `supabase db push --db-url <staging>`
4. Verify staging setlists show correct duration
5. Deploy to production: `supabase db push` (runs migration automatically)
6. Verify production setlists show correct duration

**Rollback plan:**

If migration causes issues, drop the NOT NULL constraint:

```sql
ALTER TABLE songs
ALTER COLUMN duration_seconds DROP NOT NULL;
```

## Out of Scope

The following are explicitly **out of scope** for this bug fix:

1. **Enhanced song creation forms** — requiring duration entry in UI (future feature)
2. **BPM enrichment integration** — auto-populating duration from external APIs (separate feature)
3. **Duration validation in repository** — rejecting songs with invalid duration (future enhancement)
4. **Historical duration tracking** — storing duration edits over time (not required)
5. **Duration display format changes** — the existing "Xh Ym" format is correct

These may be addressed in future work but are not required to fix the immediate bug.

---

**READY FOR ENGINEER**

This plan provides a clear diagnostic path and three fix options (manual, bulk SQL, or migration). The Engineer should start with Task 1 (diagnostic queries) to confirm root cause before proceeding with the fix.
