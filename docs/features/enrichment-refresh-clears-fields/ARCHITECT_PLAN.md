# Architect Plan

## Feature Slug

`enrichment-refresh-clears-fields`

## Problem Summary

After enriching a song's metadata (BPM/Duration/Key) from the Song Details bottom sheet, the "Enrichment complete" screen displays the fetched values correctly, but tapping "Done" returns to Song Details with all enriched fields showing as empty. The Save button is disabled, and the data never persists—confirmed by app restart and direct database queries.

**User Impact:** Enrichment appears to work but silently fails, wasting user time and creating confusion. The feature is effectively broken.

**PRODUCTION REGRESSION (2026-08-01):** The initial fix (migration 20260801120000) was deployed to prod, caused a confirmed regression, and was reverted. User cleared an already-set `musical_key` value and got error: "Could not save musical key." The fix's verification logic flagged legitimate "field already has a value, CASE correctly left it alone" cases as errors.

## Root Cause

**Confidence Level:** HIGH (ROW_COUNT behavior confirmed, underlying NULL-parameter cause unknown, regression mechanism confirmed via live device test)

The `update_song_metadata` RPC function returns `{"success": true}` based on `ROW_COUNT > 0`, but PostgreSQL's `ROW_COUNT` counts rows **matched** by the WHERE clause, not rows **modified** by the SET clauses. When the UPDATE statement's CASE expressions evaluate to no-op assignments (e.g., `SET bpm = bpm`), the function reports success even though no data was written.

**Confirmation via direct inspection:**

```sql
-- Song "All The Small Things" (ID 00a31e48-a16d-45e3-86b9-c7e2c2cb8a3e):
SELECT id, band_id, bpm, duration_seconds, musical_key FROM songs WHERE id = '00a31e48...';
-- Result: band_id = '003be463...', bpm = NULL, duration_seconds = 167, musical_key = ''

-- CASE logic simulation confirms it WOULD update if parameters are non-null:
-- bpm: NULL → WOULD UPDATE (condition: p_bpm IS NOT NULL AND bpm IS NULL)
-- musical_key: "" → WOULD UPDATE (condition: p_musical_key IS NOT NULL AND TRIM(musical_key) = '')
-- But values remain NULL/"" after enrichment → parameters likely arrived as NULL or UPDATE was no-op

-- ROW_COUNT would still return 1 even if UPDATE is no-op:
UPDATE songs SET bpm = CASE WHEN false THEN 999 ELSE bpm END WHERE id = '<uuid>';
GET DIAGNOSTICS v_count = ROW_COUNT; -- v_count = 1 (row matched, not modified)
```

**Why the CASE conditions evaluate to no-ops:** RPC parameters (`p_bpm`, `p_musical_key`) arrive as NULL despite orchestrator passing non-null values.

**Parameter name mismatch ruled out (2026-08-01):** Direct code comparison confirms all parameter names match exactly across the chain:

- **Orchestrator** (song_enrichment_orchestrator.dart:231-237): `{'bpm': ..., 'durationSeconds': ..., 'musicalKey': ...}`
- **Repository** (setlist_repository.dart:3310-3323): `{'p_bpm': update['bpm'], 'p_duration_seconds': update['durationSeconds'], 'p_musical_key': update['musicalKey']}`
- **Function** (migration 20260801000003): `(p_bpm INTEGER, p_duration_seconds INTEGER, p_musical_key TEXT)`

**Remaining theories for NULL parameters:**

1. Supabase Dart client parameter serialization issue (e.g., Dart `int` → PostgreSQL `INTEGER` coercion failure)
2. PostgREST JSON parameter conversion edge case (e.g., Dart null vs. JSON null)
3. Database constraint or trigger silently blocking the UPDATE

**Decision:** Since the exact cause of NULL parameters cannot be diagnosed without runtime instrumentation (debugger, database logs), this fix makes the failure **visible** rather than silent. The RETURNING-clause verification will detect when values don't persist and return an error, allowing users to report the issue with actionable context. A follow-up task will investigate the underlying NULL-parameter cause.

**Evidence:**

- Song has valid `band_id` (not NULL, not a legacy data issue)
- CASE logic is correct and would update if parameters are non-null
- Direct database query shows `bpm: null`, `musical_key: ""` after enrichment attempt
- Orchestrator logs show `needsBpm=true, needsKey=true`, confirming fields were targeted
- User reached "Enrichment complete" screen (APIs returned values, orchestrator completed)
- `_refreshAndRebaselineMetadata` runs after "successful" RPC, queries database, finds unchanged values, overwrites local state
- Completion screen initially shows fetched API values (from `EnrichmentOrchestrationResult`), then "Done" tap shows empty fields (from database rebaseline)

## Reference Docs Consulted

None (no `docs/reference/notifications/` or similar enrichment docs exist).

## Parameter Name Verification (2026-08-01)

**Hypothesis:** PostgREST silently treats mismatched parameter names as NULL, which would fully explain "CASE logic correct but values arrive NULL."

**Method:** Direct code comparison of orchestrator → repository → function signature.

**Orchestrator** (`lib/features/songs/services/song_enrichment_orchestrator.dart:231-237`):

```dart
final updateMap = <String, dynamic>{};
if (fetchedBpm != null) updateMap['bpm'] = fetchedBpm;
if (fetchedDuration != null) updateMap['durationSeconds'] = fetchedDuration;
if (fetchedKey != null) updateMap['musicalKey'] = fetchedKey;
```

**Repository** (`lib/features/setlists/setlist_repository.dart:3310-3323`):

```dart
final result = await supabase.rpc('update_song_metadata', params: {
  'p_song_id': songId,
  'p_band_id': bandId,
  'p_bpm': update['bpm'],
  'p_duration_seconds': update['durationSeconds'],
  'p_tuning': null,
  'p_notes': null,
  'p_title': null,
  'p_artist': null,
  'p_youtube_links': null,
  'p_lyrics': null,
  'p_musical_key': update['musicalKey'],
});
```

**Function Signature** (`supabase/migrations/20260801000003_align_update_song_metadata_musical_key_blank_fill.sql:7-18`):

```sql
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
```

**Result:** All parameter names match exactly. Parameter mismatch hypothesis **ruled out**.

## Existing System Analysis

**Current Flow:**

1. User taps "Enrich Song Data" → selector sheet shows
2. Orchestrator calls external APIs (SongEnrichmentService + ExternalSongLookupService)
3. APIs return `bpm`, `duration_seconds`, `musical_key`
4. Orchestrator populates `updateMap` with non-null values
5. Repository calls `supabase.rpc('update_song_metadata', params: {...})`
6. RPC executes UPDATE with CASE logic:
   ```sql
   bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END
   ```
7. RPC checks `ROW_COUNT`, returns `{"success": true}` if >0
8. Orchestrator marks fields as `EnrichmentFieldResult.updated`
9. `_refreshAndRebaselineMetadata` queries database to rebaseline local state
10. Database still has NULL/empty values → local state is overwritten with empties
11. Completion screen shows fetched values (from orchestrator result, NOT database)
12. User taps "Done", sees empty fields in Song Details

**Why this wasn't caught earlier:**

- PR #99 (which added `_refreshAndRebaselineMetadata`) was only verified by code-path analysis, never device-tested end-to-end
- `ROW_COUNT > 0` check seemed correct but doesn't distinguish matches from modifications

**Regression Mechanism (Confirmed 2026-08-01):**

The initial fix added RETURNING-clause verification that compared _requested_ value against _final_ value, but did not check whether the field was **eligible** for the CASE branch to act on it in the first place. The CASE logic is **fill-only** by design (per migration 20260801000000):

- `bpm`: Only fills when current is NULL
- `duration_seconds`: Only fills when current is 0
- `musical_key`: Only fills when current is NULL, empty, or whitespace-only

When a user tries to clear or change an already-set value (e.g., musical_key "Dm" → NULL), the CASE logic **intentionally** leaves it unchanged (this is correct per fill-only design). But the verification only compared requested vs. actual, so it flagged this as an error:

```
Requested: "" (empty string, meaning clear)
Actual: "Dm" (unchanged because CASE saw field already had value)
Verification: ERROR - "Musical key update failed: requested , got Dm"
```

This regression affects **all manual edits** to already-set BPM/Duration/Key fields, not just enrichment. The fix needs to distinguish:

1. **Field was eligible for fill** (current was NULL/blank/zero) **but value still didn't persist** → Real bug, should error
2. **Field was not eligible for fill** (already had value) → Expected behavior per fill-only design, should NOT error

## Proposed Solution

**Revised Fix (Corrects Regression):** Modify `update_song_metadata` RPC to capture _before_ values (via SELECT before UPDATE) in addition to _after_ values (via RETURNING). Verification logic checks:

1. Was the field **eligible** for the CASE to act? (Check BEFORE value against fill-only condition)
2. If eligible AND requested value provided → Verify AFTER value matches requested (error if not)
3. If not eligible → Skip verification (expected no-op, not an error)

**Why this approach:**

- Parameter name mismatch ruled out (confirmed via code comparison 2026-08-01)
- Underlying NULL-parameter cause cannot be diagnosed without runtime instrumentation
- Making the failure **loud** (user-visible error) instead of **silent** (fake success) allows users to report the issue with context — but only for genuine failures
- Preserves existing `ROW_COUNT` check as first-line defense
- Does not break legitimate manual edit/clear attempts that the fill-only CASE correctly no-ops

**Out of Scope (Pre-Existing Limitation, Not Being Fixed):**

Users **cannot** clear or change already-set BPM/Duration/Key values via manual Save in Song Details. The `update_song_metadata` CASE logic is fill-only by design. This limitation existed before this fix and is **not being addressed** because:

1. Enrichment fill-only design is intentional (migration 20260801000000) to prevent overwrites
2. BPM has a separate `clear_song_metadata` RPC for clearing, but manual Save doesn't call it when user clears BPM field — instead it calls `updateSongBpm(null)` which goes through `update_song_metadata` with `p_bpm: null`, which is a no-op per the CASE logic
3. Musical Key has NO separate clear RPC at all — manual clearing attempts go through `update_song_metadata` with `p_musical_key: ""`, which the CASE intentionally leaves unchanged if current is non-empty
4. Fixing this requires either:
   - Changing CASE logic to support overwrites (high risk, contradicts enrichment non-overwrite design)
   - Adding clear RPCs for all three fields and updating manual Save code path to detect clears vs. sets
   - This is a separate feature request, not part of this false-success bug fix

**Rationale for leaving manual edit limitation out of scope:** The regression was caused by this fix incorrectly flagging expected no-ops as errors. Removing that false-error restores pre-fix behavior: manual clearing/editing of already-set fields silently no-ops (Save button enabled, but value doesn't change). This is the same behavior users had before 2026-08-01, so it's not a new regression from this fix — it's a pre-existing limitation that was **masked** by the lack of verification, and is now **exposed** but not worsened.

**Follow-Up Task Required (Separate Issue):** After this fix deploys and users report errors on genuine enrichment failures (not false-errors from manual edits):

1. Add database-side logging to capture RPC parameters at runtime (CREATE TEMP TABLE to log p_bpm, p_duration_seconds, p_musical_key values)
2. Or add Dart-side logging to capture `update` map contents before `.rpc()` call
3. Identify whether parameters are NULL on Dart side (serialization issue) or database side (PostgREST issue)
4. File targeted fix based on logs

**Alternative considered and rejected:**

- Adding a BEFORE UPDATE trigger to track changes: Too heavy, adds complexity
- Changing orchestrator to verify database state after RPC: Requires retry logic, more client changes
- Removing `ROW_COUNT` check entirely: Loses protection against WHERE clause mismatches
- Guessing at the NULL-parameter cause without evidence: Risk of fixing the wrong thing

## Database Impact

**Affected:**

- **Migrations:** One new migration to replace `update_song_metadata` function
- **RPC Functions:** `update_song_metadata` signature unchanged, implementation modified to add RETURNING and value verification
- **RLS Policies:** Unaffected (no RLS changes required)
- **Triggers:** Unaffected (no triggers on `songs` table)

**Not Applicable:**

- Tables, constraints, indexes: No schema changes

## Flutter Architecture Changes

**Unaffected:**

- No client code changes required
- Orchestrator logic remains unchanged
- Repository RPC call remains unchanged
- UI refresh flow remains unchanged

The fix is entirely database-side. If the RPC starts returning `success=false` when values don't persist (genuine enrichment failures only, not expected no-ops), the existing error handling in `SetlistRepository.enrichSongs()` will log the error and mark fields as `error` instead of `updated`, and the completion screen will reflect the failure.

## Files to Create

**New Migration:**

- `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql`
  - Drop existing `update_song_metadata` function
  - Recreate with RETURNING clause and eligibility-aware value verification
  - Add explicit checks that returned values match input parameters for BPM, duration, and musical key, BUT only when field was eligible for fill
  - Preserve all existing parameter validation (auth, band membership, etc.)

## Files to Modify

None (client code unchanged).

## Files Off-Limits

- `lib/features/songs/services/song_enrichment_orchestrator.dart` — No changes to orchestrator logic
- `lib/features/setlists/setlist_repository.dart` — No changes to repository RPC call
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — No changes to refresh logic
- All other client files — Fix is database-only

## System Impact Map

| System                           | Impact     | Reason                                                   |
| -------------------------------- | ---------- | -------------------------------------------------------- |
| Gigs                             | unaffected | No gig-related code touched                              |
| Rehearsals                       | unaffected | No rehearsal-related code touched                        |
| Setlists / Catalog               | affected   | Enrichment is a setlist/catalog feature — fix repairs it |
| Members / RBAC                   | unaffected | No RBAC logic changes (RPC still checks band membership) |
| Auth / Session                   | unaffected | No auth flow changes (`auth.uid()` usage unchanged)      |
| Routing                          | unaffected | No route changes                                         |
| Notifications                    | unaffected | No notification code touched                             |
| Platform (iOS/Android/Web/macOS) | affected   | Bug affects all platforms (shared RPC), fix repairs all  |

## Regression Risk

**Level:** HIGH → DEMONSTRATED

**Rationale:**

- **PRODUCTION INCIDENT CONFIRMED (2026-08-01):** Initial fix caused regression where manual clearing of already-set musical_key errored with "Could not save musical key"
- Initial fix was deployed to prod, tested on live device, caused user-visible error, and was reverted
- Changes a core RPC function used by **all metadata updates** across all platforms, not just enrichment
- RPC is called from:
  - Single-song enrichment (Song Details "Enrich Song Data")
  - Bulk catalog enrichment
  - Manual metadata editing (BPM, Duration, Key, Tuning, Notes, Title, Artist, YouTube, Lyrics)
- Verification logic must correctly distinguish eligible-but-failed from not-eligible-expected-no-op, or it will flag all manual edits to already-set fields as errors

**Mitigation:**

- Tier 1 tests verify existing RPC behavior with non-null parameters
- Tier 2 tests verify new false-success detection with no-op CASE conditions
- **NEW:** Tier 2 tests verify that already-set field updates do NOT error (regression prevention)
- **QA MUST INCLUDE RUNTIME TESTING** (not just code review) of:
  - Manual edit operations: Change BPM/Duration/Key on song with pre-existing values
  - Manual clear operations: Clear BPM/Duration/Key on song with pre-existing values
  - Songs with mixed states (some NULL, some filled)
- **Previous QA gap:** PR that deployed 20260801120000 was approved based on code-path analysis and migration diff only, did not runtime-test manual metadata editing (QA Regression Area #5), which is exactly where the regression occurred

## Engineer Task Breakdown

### Task 1: Write SQL Migration

Create `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql`:

1. Drop existing `update_song_metadata` function (all overloads)
2. Recreate function with:
   - Same signature (11 parameters: p_song_id, p_band_id, p_bpm, p_duration_seconds, p_tuning, p_notes, p_title, p_artist, p_youtube_links, p_lyrics, p_musical_key)
   - Same SECURITY DEFINER, SET search_path = public
   - Same auth checks (auth.uid() IS NULL → error)
   - Same band membership check
   - Same song existence and ownership checks
   - **NEW:** Add DECLARE variables for before values:
     ```sql
     v_before_bpm INTEGER;
     v_before_duration INTEGER;
     v_before_key TEXT;
     v_new_bpm INTEGER;
     v_new_duration INTEGER;
     v_new_key TEXT;
     ```
   - **NEW:** SELECT before values before UPDATE:
     ```sql
     SELECT bpm, duration_seconds, musical_key
     INTO v_before_bpm, v_before_duration, v_before_key
     FROM songs WHERE id = p_song_id;
     ```
   - Same UPDATE statement with CASE logic (UNCHANGED)
   - **NEW:** Add `RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key` after UPDATE
   - **NEW:** After `ROW_COUNT` check, add eligibility-aware verification:
     ```sql
     -- BPM verification (only error if field was eligible for fill but didn't persist)
     IF p_bpm IS NOT NULL THEN
       -- Field is eligible if before value was NULL
       IF v_before_bpm IS NULL THEN
         -- Field was eligible, check if it updated
         IF v_new_bpm IS DISTINCT FROM p_bpm THEN
           RETURN json_build_object('success', false, 'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL'));
         END IF;
       END IF;
       -- If field was not eligible (already had value), skip verification (expected no-op)
     END IF;
     ```
     (Repeat pattern for duration_seconds with eligibility condition `v_before_duration = 0`, and musical_key with eligibility condition `v_before_key IS NULL OR TRIM(v_before_key) = ''`)
   - Use `IS DISTINCT FROM` to handle NULL comparisons correctly
   - Return error message with both requested and actual values for debugging
3. Add GRANT EXECUTE to authenticated
4. Add updated COMMENT explaining the fix and eligibility-aware verification

### Task 2: No Client Code Changes

Verification only — confirm no client changes needed.

## Verification Plan

### Tier 1 — Pre-Deployment (Before supabase db push)

**Test existing RPC behavior (no migration applied yet):**

```sql
-- PRE-DEPLOY TEST 1: Verify old function still exists with correct signature
SELECT pg_get_function_identity_arguments(oid)
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pronamespace = 'public'::regnamespace;
-- EXPECT: Returns parameter list with 11 params
```

```sql
-- PRE-DEPLOY TEST 2: Verify ROW_COUNT behavior on no-op UPDATE (documents current bug)
DO $$
DECLARE
  v_test_id UUID;
  v_count INTEGER;
BEGIN
  SELECT id INTO v_test_id FROM songs WHERE bpm IS NULL LIMIT 1;
  IF v_test_id IS NULL THEN
    RAISE EXCEPTION 'No test song found with NULL bpm';
  END IF;

  UPDATE songs SET bpm = CASE WHEN false THEN 999 ELSE bpm END WHERE id = v_test_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count != 1 THEN
    RAISE EXCEPTION 'Expected ROW_COUNT=1, got %', v_count;
  END IF;

  RAISE NOTICE 'PRE-DEPLOY TEST 2 PASS: ROW_COUNT=1 even on no-op UPDATE';
END $$;
```

### Tier 2 — Post-Deployment (After supabase db push)

**Test new function with value verification:**

```sql
-- POST-DEPLOY TEST 1: Verify new function exists and has RETURNING logic
SELECT pg_get_functiondef(oid) LIKE '%RETURNING%'
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pronamespace = 'public'::regnamespace;
-- EXPECT: true (function contains RETURNING clause)
```

```sql
-- POST-DEPLOY TEST 2: Test successful enrichment (BPM update on eligible/blank field)
DO $$
DECLARE
  v_test_id UUID;
  v_band_id UUID;
  v_result JSON;
BEGIN
  SELECT s.id, s.band_id INTO v_test_id, v_band_id
  FROM songs s
  WHERE s.bpm IS NULL AND s.band_id IS NOT NULL
  LIMIT 1;

  IF v_test_id IS NULL THEN
    RAISE EXCEPTION 'No test song found';
  END IF;

  v_result := update_song_metadata(
    p_song_id := v_test_id,
    p_band_id := v_band_id,
    p_bpm := 120,
    p_duration_seconds := NULL,
    p_tuning := NULL,
    p_notes := NULL,
    p_title := NULL,
    p_artist := NULL,
    p_youtube_links := NULL,
    p_lyrics := NULL,
    p_musical_key := NULL
  );

  IF v_result->>'success' != 'true' THEN
    RAISE EXCEPTION 'Expected success, got: %', v_result;
  END IF;

  PERFORM 1 FROM songs WHERE id = v_test_id AND bpm = 120;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BPM was not updated in database';
  END IF;

  UPDATE songs SET bpm = NULL WHERE id = v_test_id;

  RAISE NOTICE 'POST-DEPLOY TEST 2 PASS: BPM update succeeded and persisted on eligible field';
END $$;
```

```sql
-- POST-DEPLOY TEST 3: Regression prevention — already-set fields must NOT error on edit/clear
DO $$
DECLARE
  v_test_id UUID;
  v_band_id UUID;
  v_current_bpm INTEGER;
  v_current_key TEXT;
  v_result JSON;
BEGIN
  SELECT s.id, s.band_id, s.bpm, s.musical_key INTO v_test_id, v_band_id, v_current_bpm, v_current_key
  FROM songs s
  WHERE s.bpm IS NOT NULL
    AND s.musical_key IS NOT NULL
    AND TRIM(s.musical_key) != ''
    AND s.band_id IS NOT NULL
  LIMIT 1;

  IF v_test_id IS NULL THEN
    RAISE EXCEPTION 'No test song found with both BPM and musical_key set';
  END IF;

  -- Case A: attempt to change an already-set BPM to a different value
  v_result := update_song_metadata(
    p_song_id := v_test_id,
    p_band_id := v_band_id,
    p_bpm := 999,
    p_duration_seconds := NULL,
    p_tuning := NULL,
    p_notes := NULL,
    p_title := NULL,
    p_artist := NULL,
    p_youtube_links := NULL,
    p_lyrics := NULL,
    p_musical_key := NULL
  );

  IF v_result->>'success' != 'true' THEN
    RAISE EXCEPTION 'Expected success (not eligible, expected silent no-op), got error: %', v_result;
  END IF;

  PERFORM 1 FROM songs WHERE id = v_test_id AND bpm = v_current_bpm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BPM changed unexpectedly — fill-only CASE should have left it alone';
  END IF;

  -- Case B: attempt to clear an already-set musical_key
  v_result := update_song_metadata(
    p_song_id := v_test_id,
    p_band_id := v_band_id,
    p_bpm := NULL,
    p_duration_seconds := NULL,
    p_tuning := NULL,
    p_notes := NULL,
    p_title := NULL,
    p_artist := NULL,
    p_youtube_links := NULL,
    p_lyrics := NULL,
    p_musical_key := ''
  );

  IF v_result->>'success' != 'true' THEN
    RAISE EXCEPTION 'Expected success (not eligible, expected silent no-op), got error: %', v_result;
  END IF;

  PERFORM 1 FROM songs WHERE id = v_test_id AND musical_key = v_current_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'musical_key changed unexpectedly — fill-only CASE should have left it alone';
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 3 PASS: already-set fields correctly silently no-op, no error (regression fixed)';
END $$;
```

```sql
-- POST-DEPLOY TEST 4: Production verification - check "All The Small Things"
SELECT
  id,
  title,
  bpm,
  musical_key,
  updated_at
FROM songs
WHERE id = '00a31e48-a16d-45e3-86b9-c7e2c2cb8a3e';
-- Manual review: Ensure no unexpected changes to production data
```

## QA Regression Areas

**CRITICAL REQUIREMENT:** All regression areas must include **runtime testing on a real device**, not just code review. The initial fix was approved based on code-path analysis and migration diff alone, and the regression was only caught during live device testing after prod deployment.

**Primary Testing (Enrichment):**

1. Single-song enrichment from Song Details bottom sheet:
   - Song with all fields empty (NULL bpm, empty key, 0 duration) → Enrich all three → Verify "Enrich Song Data" completes, tap "Done", verify Song Details shows persisted values, tap Save, verify no errors
   - Song with some fields filled (e.g., BPM set, Key empty) → Enrich missing fields only → Verify existing BPM unchanged, new Key persists, tap Save, verify no errors
   - Song with all fields filled → Attempt enrichment → Verify "unchanged" status or skip, no overwrites, no errors

2. Bulk catalog enrichment (if accessible):
   - Enrich multiple songs with mixed states (some empty, some partial, some full)
   - Verify completion screen shows accurate counts (enriched vs. unchanged vs. errors)
   - Verify all enriched songs persist changes after closing enrichment flow

3. Enrichment error handling:
   - Song in catalog with NULL band_id (legacy data) → Verify enrichment works (RPC is SECURITY DEFINER for this reason)
   - User without active band membership (if testable) → Verify enrichment fails with clear error

4. Enrichment refresh behavior:
   - After enrichment completes, tap "Done" → Verify Song Details fields show enriched values
   - Close and reopen Song Details → Verify values still present (not stale cache)
   - Restart app → Verify values persist across sessions

**Regression-Critical Testing (Manual Editing):**

**NOTE:** This is QA Regression Area #5, which was NOT runtime-tested in the initial fix, leading to the production regression.

5. Manual metadata editing on songs WITH EXISTING VALUES — MUST RUNTIME TEST, not just code review:
   - Song with BPM already set (e.g., 120) → change to 140 → Save → **Expected: silent no-op, BPM stays 120, NO error shown**
   - Song with musical_key already set (e.g., "Dm") → change to "Em" → Save → **Expected: silent no-op, key stays "Dm", NO error shown**
   - Song with duration already set (e.g., 180s) → change to 200 → Save → **Expected: silent no-op, duration stays 180, NO error shown**

6. Manual metadata clearing on songs WITH EXISTING VALUES — MUST RUNTIME TEST, not just code review. **THIS IS THE EXACT CASE THAT REGRESSED IN PROD:**
   - Song with BPM already set → clear it → Save → **Expected: silent no-op, BPM stays set, NO error shown**
   - Song with musical_key already set → clear it → Save → **Expected: silent no-op, key stays set, NO error shown**

7. Manual metadata editing on songs WITH EMPTY VALUES:
   - Song with BPM NULL → set to 120 → Save → **Expected: BPM persists as 120, no errors**
   - Song with musical_key NULL/empty → set to "Dm" → Save → **Expected: key persists as "Dm", no errors**
   - Song with duration 0 → set to 180 → Save → **Expected: duration persists as 180, no errors**

**Secondary Testing (Other Metadata):**

8. Song creation flow:
   - Add new song from Catalog → set BPM/Duration/Key → Save → verify persists
   - Import from Spotify → verify imported metadata persists

9. Other manual metadata fields (should be unaffected, verify no regressions):
   - Edit Title/Artist → verify persists
   - Edit Tuning → verify persists
   - Edit Notes → verify persists
   - Edit YouTube links → verify persists
   - Edit Lyrics → verify persists

## Rollout / Migration Strategy

**Deployment:**

1. Run `supabase db push` to apply migration
2. Verify with Tier 2 post-deploy tests
3. No client app update required (fix is server-side only)
4. Monitor Sentry/logs for any new RPC errors after deployment

**Rollback Plan:**
If new verification logic causes false negatives (legitimate updates incorrectly rejected):

1. Identify problematic edge case from error logs
2. Create hotfix migration to relax verification condition
3. Or revert to previous function version (loses bug fix, but restores working enrichment for successful cases)

**Follow-up (tracked separately):** Diagnosing the underlying NULL-parameter cause requires runtime instrumentation (Dart-side logging or DB-side parameter logging), not feasible pre-deployment. This is out of scope for this fix — see "Follow-Up Task Required" section above.

**User Communication:**

- This is a partial fix: enrichment failures that were previously silent will now surface as a visible error instead of appearing to succeed
- Enrichment may still fail to persist values for some songs until the underlying NULL-parameter cause (tracked as a follow-up) is found and fixed
- Tony should be told this converts the bug from "silent data loss" to "loud, reportable failure" — not a full resolution

## Out of Scope

- Fixing enrichment for songs that already had failed enrichments (historical data) — user can re-run enrichment after fix deploys
- Improving enrichment accuracy or adding new data sources — this is a correctness fix only
- Adding enrichment for other fields (tempo, album, etc.) — scope is BPM/Duration/Key only
- Optimizing enrichment performance — no performance changes in this fix
