# Engineer Report

## Feature Slug

`enrichment-refresh-clears-fields`

## Feature Title

Fix False-Success Bug in Song Metadata Enrichment

## Goal

Fix the `update_song_metadata` RPC function to detect and report genuine enrichment failures (when eligible fields don't persist) while NOT erroring on expected no-ops from the fill-only CASE design (when fields already have values). This corrects a production regression where the initial fix incorrectly flagged legitimate manual edits/clears of already-set fields as errors.

## Production History Context

**CRITICAL NOTE:** This is the SECOND implementation of this fix. The initial version (deployed 2026-08-01) was reverted after causing a confirmed production regression where users attempting to clear already-set musical_key values received "Could not save musical key" errors. The Architect plan was revised with eligibility-aware verification logic, and this report covers the corrected implementation.

## Architect Tasks Completed

- [x] Task 1 — Write SQL Migration (verified existing file matches revised plan)
- [x] Task 2 — No Client Code Changes (confirmed)

## Files Created

None (migration file already exists and matches revised plan specifications)

## Files Modified

None required

**Critical Finding:** The migration file `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql` was reviewed line-by-line against the revised Architect plan Task 1 specifications and **already implements the corrected design exactly**:

- ✅ Captures before-values via `v_before_bpm`, `v_before_duration`, `v_before_key`
- ✅ SELECT before UPDATE to populate before-value variables
- ✅ Eligibility-aware verification that checks:
  1. Field was eligible for fill (via before-value condition match)
  2. Requested parameter was provided (NOT NULL)
  3. Actual value (via RETURNING) doesn't match requested
- ✅ Only errors when all three conditions are true (genuine persistence failure)
- ✅ Silently succeeds when field was not eligible (expected no-op per fill-only CASE design)
- ✅ Uses `IS DISTINCT FROM` for NULL-safe comparisons
- ✅ Detailed error messages with requested vs. actual values
- ✅ Preserves ROW_COUNT check as first-line defense
- ✅ Preserves SECURITY DEFINER and auth/band membership/ownership checks

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 1 info-level warning (pre-existing, unrelated to this implementation)

```
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to
       not use the 'BuildContext', or guard the use with a 'mounted' check •
       lib/features/setlists/setlist_detail_screen.dart:1449:32 •
       use_build_context_synchronously
```

This warning is pre-existing and not introduced by this implementation (no Dart files were modified).

## Test Results

### Tier 1 Pre-Deployment Tests (Run Against Current Database)

**Test 1: Verify Function Signature**

```sql
-- Verified function exists with 11 parameters
SELECT pg_get_function_identity_arguments(oid)
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pronamespace = 'public'::regnamespace;
```

**Result:** ✅ PASS
**Output:** `p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text`

**Test 2: Verify ROW_COUNT Behavior on No-Op UPDATE**

```sql
-- Documents current bug: ROW_COUNT=1 even when CASE evaluates to no-op
DO $$
DECLARE
  v_test_id UUID;
  v_count INTEGER;
BEGIN
  SELECT id INTO v_test_id FROM songs WHERE bpm IS NULL LIMIT 1;
  UPDATE songs SET bpm = CASE WHEN false THEN 999 ELSE bpm END WHERE id = v_test_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count != 1 THEN RAISE EXCEPTION 'Expected ROW_COUNT=1, got %', v_count; END IF;
  RAISE NOTICE 'PRE-DEPLOY TEST 2 PASS: ROW_COUNT=1 even on no-op UPDATE';
END $$;
```

**Result:** ✅ PASS
**Output:** Notice raised successfully, confirming ROW_COUNT=1 even when UPDATE is a no-op (row matched but not modified). This documents the bug behavior that the migration will fix

## Verification

### Manual Steps Performed:

1. ✅ Read full Architect plan (`ARCHITECT_PLAN.md`)
2. ✅ Read full Engineer protocol (`docs/agents/ENGINEER.md`)
3. ✅ Read full Guardrails (`docs/agents/GUARDRAILS.md`)
4. ✅ Verified git branch: `bug/enrichment-refresh-clears-fields`
5. ✅ Verified working tree contains only feature-related files (no unrelated changes)
6. ✅ Compared migration file line-by-line against Architect plan Task 1 specifications
7. ✅ Executed Tier 1 pre-deployment tests against current database state
8. ✅ Ran `flutter analyze` (0 errors, 1 pre-existing unrelated warning)

### Migration File Line-by-Line Verification:

**Function Signature (Lines 10-21):**

- ✅ 11 parameters exactly as specified: `p_song_id`, `p_band_id`, `p_bpm`, `p_duration_seconds`, `p_tuning`, `p_notes`, `p_title`, `p_artist`, `p_youtube_links`, `p_lyrics`, `p_musical_key`
- ✅ All have DEFAULT NULL except required params

**Function Modifiers (Lines 23-26):**

- ✅ `RETURNS JSON`
- ✅ `LANGUAGE plpgsql`
- ✅ `SECURITY DEFINER` (required for legacy NULL band_id songs)
- ✅ `SET search_path = public` (required per Guardrails)

**DECLARE Block (Lines 27-34):**

- ✅ `v_user_id UUID`
- ✅ `v_is_member BOOLEAN`
- ✅ `v_song_band_id UUID`
- ✅ `v_update_count INTEGER`
- ✅ **NEW:** `v_before_bpm INTEGER` (captures before-value for eligibility check)
- ✅ **NEW:** `v_before_duration INTEGER` (captures before-value for eligibility check)
- ✅ **NEW:** `v_before_key TEXT` (captures before-value for eligibility check)
- ✅ **NEW:** `v_new_bpm INTEGER` (captures after-value via RETURNING)
- ✅ **NEW:** `v_new_duration INTEGER` (captures after-value via RETURNING)
- ✅ **NEW:** `v_new_key TEXT` (captures after-value via RETURNING)

**Auth & Membership Checks (Lines 36-59):**

- ✅ Auth check: `auth.uid() IS NULL` → error
- ✅ Band membership check via `band_members` table with `status = 'active'`
- ✅ Song existence check
- ✅ Band ownership check (allows NULL band_id for legacy songs)

**NEW: Before-Value Capture (Lines 61-64):**

```sql
SELECT bpm, duration_seconds, musical_key
INTO v_before_bpm, v_before_duration, v_before_key
FROM songs WHERE id = p_song_id;
```

✅ Matches plan exactly

**UPDATE Statement (Lines 66-79):**

- ✅ BPM: `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END` (fill-only)
- ✅ Duration: `CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END` (fill-only)
- ✅ Musical Key: `CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END` (fill-only)
- ✅ Other fields use COALESCE or CASE with NULL check (overwrite if provided)
- ✅ **NEW:** `RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key`

**ROW_COUNT Check (Lines 81-84):**

```sql
GET DIAGNOSTICS v_update_count = ROW_COUNT;
IF v_update_count = 0 THEN
  RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
END IF;
```

✅ Preserves existing first-line defense

**NEW: Eligibility-Aware Verification (Lines 86-129):**

**BPM Verification (Lines 89-100):**

```sql
IF p_bpm IS NOT NULL THEN
  IF v_before_bpm IS NULL THEN  -- Check eligibility: field was NULL
    IF v_new_bpm IS DISTINCT FROM p_bpm THEN  -- Check persistence
      RETURN json_build_object('success', false, 'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL'));
    END IF;
  END IF;
  -- If field was not eligible (already had value), skip verification
END IF;
```

✅ Correct: Only errors if field WAS eligible (NULL) but value didn't persist
✅ Silently succeeds if field was not eligible (already had value) — prevents regression

**Duration Verification (Lines 102-113):**

```sql
IF p_duration_seconds IS NOT NULL THEN
  IF v_before_duration = 0 THEN  -- Check eligibility: field was 0
    IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
      RETURN json_build_object('success', false, 'error', 'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL'));
    END IF;
  END IF;
  -- If field was not eligible (already had value != 0), skip verification
END IF;
```

✅ Correct: Only errors if field WAS eligible (= 0) but value didn't persist
✅ Silently succeeds if field was not eligible (already had non-zero value)

**Musical Key Verification (Lines 115-126):**

```sql
IF p_musical_key IS NOT NULL THEN
  IF v_before_key IS NULL OR TRIM(v_before_key) = '' THEN  -- Check eligibility: field was NULL/empty/whitespace
    IF v_new_key IS DISTINCT FROM p_musical_key THEN
      RETURN json_build_object('success', false, 'error', 'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL'));
    END IF;
  END IF;
  -- If field was not eligible (already had non-empty value), skip verification
END IF;
```

✅ Correct: Only errors if field WAS eligible (NULL/empty/whitespace) but value didn't persist
✅ **REGRESSION FIX:** Silently succeeds if field was not eligible (already had non-empty value) — this is the critical fix that prevents the "Could not save musical key" error when user tries to clear/edit an already-set field

**Success Return (Line 128):**

```sql
RETURN json_build_object('success', true);
```

✅ Returns success only after all verifications pass

**GRANT & COMMENT (Lines 134-137):**

- ✅ `GRANT EXECUTE ON FUNCTION ... TO authenticated`
- ✅ Updated COMMENT documents eligibility-aware verification and regression fix

## Deviations From Architect Plan

**None.** The migration file was already present and matches the revised Architect plan specifications exactly. No code changes were required or performed.

## Regression Prevention Analysis

The initial fix caused a production regression because it did NOT check field eligibility before erroring. This corrected version adds three-step verification:

1. **Is parameter provided?** (`p_bpm IS NOT NULL`)
2. **Was field eligible for fill?** (`v_before_bpm IS NULL`)
3. **Did value persist?** (`v_new_bpm IS DISTINCT FROM p_bpm`)

Only if ALL THREE are true does it return an error. This means:

- ✅ Enrichment on eligible blank fields that fail to persist → ERROR (catches genuine bug)
- ✅ Manual edit attempt on already-set field → SUCCESS (expected no-op per fill-only design, no false error)
- ✅ Manual clear attempt on already-set field → SUCCESS (expected no-op per fill-only design, no false error)

**Regression Test Coverage (Per Architect Plan QA Section):**

- Tier 2 POST-DEPLOY TEST 3 explicitly covers the regression case: attempts to change/clear already-set BPM and musical_key values, verifies function returns success and values remain unchanged (expected behavior per fill-only CASE design)

## Blockers Encountered

None

## Ready For QA

**Yes, with critical caveat:**

The migration file is ready for deployment. However, per the Architect plan:

**QA MUST INCLUDE RUNTIME TESTING on a real device, not just code review.** The initial fix was approved based on code-path analysis only, and the regression was only caught during live device testing after production deployment.

**Critical Regression Areas (Per Architect Plan Section "QA Regression Areas"):**

**QA Regression Area #5 (Caused Previous Regression):**

- Manual editing of already-set BPM/Duration/Key fields
- Manual clearing of already-set BPM/Duration/Key fields
- **Expected behavior:** Silent no-op, NO error shown, values remain unchanged (fill-only CASE design)
- **This MUST be runtime-tested**, not just code-reviewed

**QA Testing Requirements:**

1. Single-song enrichment from Song Details (all field state combinations)
2. Bulk catalog enrichment (mixed states)
3. Enrichment error handling (legacy songs, auth failures)
4. Enrichment refresh behavior (completion screen → Song Details → app restart)
5. **CRITICAL:** Manual metadata editing on songs WITH EXISTING VALUES (Area #5 regression prevention)
6. **CRITICAL:** Manual metadata clearing on songs WITH EXISTING VALUES (Area #5 regression prevention)
7. Manual metadata editing on songs WITH EMPTY VALUES
8. Song creation flow
9. Other manual metadata fields (Title, Artist, Tuning, Notes, YouTube, Lyrics)

See Architect Plan "QA Regression Areas" section for detailed test cases.

## Follow-Up Required (Out of Scope for This Fix)

Per Architect plan, this fix converts silent data loss into a loud, reportable failure for genuine enrichment bugs. However, the ROOT CAUSE (why enrichment parameters arrive as NULL at the database despite orchestrator passing non-null values) remains undiagnosed. After this fix deploys:

1. Monitor for genuine enrichment errors (users report "BPM update failed" or "Musical key update failed")
2. If errors occur, add runtime instrumentation:
   - Dart-side: Log `update` map contents before `.rpc()` call
   - DB-side: Create temp table to log RPC parameters at entry
3. Identify whether parameters are NULL on Dart side (serialization issue) or database side (PostgREST issue)
4. File targeted fix based on logs

## Pre-Existing Limitation (Not Being Fixed)

Users CANNOT clear or change already-set BPM/Duration/Key values via manual Save in Song Details. The fill-only CASE logic is intentional (prevents enrichment overwrites). This limitation existed before this fix and is NOT being addressed because:

1. It's the correct behavior per enrichment non-overwrite design (migration 20260801000000)
2. Fixing it requires either changing CASE logic (high risk) or adding separate clear RPCs + updating manual Save code path
3. This is a separate feature request, not part of the false-success bug fix

**Rationale for leaving it out of scope:** The regression was caused by this fix incorrectly flagging expected no-ops as errors. The corrected version removes that false-error and restores pre-fix behavior: manual clearing/editing of already-set fields silently no-ops. This is the SAME behavior users had before 2026-08-01, so it's not a new regression from this fix.

---

## Deployment Readiness Checklist

- [x] Migration file matches revised Architect plan specifications
- [x] Tier 1 pre-deployment tests pass
- [x] Flutter analyze: 0 errors, no new warnings
- [x] No client code changes required (database-only fix)
- [x] Regression prevention logic verified (eligibility-aware verification)
- [x] ENGINEER_REPORT.md created and confirmed on disk
- [ ] **QA runtime testing on real device** (required before merge — see QA Regression Areas above)
- [ ] Tier 2 post-deployment tests (after `supabase db push`)

**Next Steps:**

1. QA performs runtime testing per regression areas (especially Area #5)
2. If QA passes, deploy migration via `supabase db push`
3. Run Tier 2 post-deployment tests (see Architect plan Verification Plan)
4. Monitor production for genuine enrichment errors (indicates underlying NULL-parameter issue needs follow-up)

---

**Report Generated:** 2026-08-01  
**Engineer:** AI (GitHub Copilot - Claude Sonnet 4.5)  
**Feature Branch:** `bug/enrichment-refresh-clears-fields`  
**Migration File:** `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql`
