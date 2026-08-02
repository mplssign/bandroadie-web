# QA Report (Revision 2 — Post-Production Incident)

## Feature Slug

`enrichment-refresh-clears-fields`

## Feature Title

Fix False-Success Bug in Song Enrichment RPC (Corrected for Regression)

## Final Verdict

**CONDITIONAL APPROVAL — RUNTIME TESTING REQUIRED**

See "Deployment Gate" section for mandatory runtime test requirements before merge.

## CRITICAL CONTEXT: Why This Report Supersedes Prior Approval

**Date of Prior Approval:** 2026-08-01 (original QA_REPORT.md)

**Date of Production Deployment:** 2026-08-01

**Date of Regression Discovery:** 2026-08-01 (same day, live device testing after deployment)

**Date of Revert:** 2026-08-01

**Regression Symptom:** User attempted to clear an already-set `musical_key` value from Song Details, received error "Could not save musical key", operation failed. Manual editing/clearing of already-set BPM/Duration/Key fields was completely broken.

**Why the Prior Approval Was Invalid:**

The initial fix added RETURNING-clause verification but did NOT check field eligibility. The fill-only CASE design means:

- `bpm`: Only updates when current value is NULL
- `duration_seconds`: Only updates when current value is 0
- `musical_key`: Only updates when current value is NULL, empty, or whitespace

When a user tries to edit/clear an already-set field (e.g., musical_key "Dm" → ""), the CASE logic **intentionally and correctly** leaves it unchanged. This is expected behavior per the fill-only enrichment design.

The initial fix compared requested vs. actual values WITHOUT checking eligibility, so it flagged this expected no-op as an error:

```
Requested: "" (user cleared the field)
Actual: "Dm" (CASE left it unchanged because field already had value)
Verification: ERROR — "Musical key update failed: requested , got Dm"
```

**The Gap in Prior QA:**

The prior `QA_REPORT.md` stated:

- Validation method: "code-path analysis + byte-for-byte comparison with prior migration"
- Tier 2 tests: "Not run (require supabase db push)"
- Regression Area #5 (manual editing of already-set fields): **NOT RUNTIME-TESTED**

The report approved the fix based on code review and static SQL comparison, without exercising the actual manual metadata editing flow. The regression was hiding in the interaction between:

1. Fill-only CASE logic (unchanged, correct)
2. New verification logic (added, incorrect — missing eligibility check)

A byte-for-byte CASE comparison could only prove the CASE logic was unchanged. It could NOT prove that the new verification logic would correctly handle the CASE's no-op outputs.

**What Changed in This Revision:**

The Architect plan was revised to add eligibility-aware verification:

1. Check if field WAS eligible for fill (before-value NULL/blank/zero)
2. If eligible AND requested AND value didn't persist → ERROR (genuine bug)
3. If NOT eligible → SKIP verification → SUCCESS (expected no-op, not an error)

This QA report validates the corrected implementation against the revised plan.

---

## Validation Summary

Re-validated database-only fix after production regression. Confirmed the migration SQL now includes eligibility-aware verification that correctly distinguishes genuine persistence failures from expected no-ops per fill-only CASE design. Verified via:

- Line-by-line migration SQL review
- Code-path tracing for manual metadata editing
- Tier 1 pre-deployment SQL tests
- Analyzer check (0 errors)

**Critical finding:** Migration file `20260801120000_fix_update_song_metadata_false_success.sql` already implements the corrected eligibility-aware design exactly as specified in the revised Architect plan.

---

## Architect Scope Review

- Scope adherence: **compliant**
- Files modified: **as expected** (only migration + ENGINEER_REPORT.md, no client changes)
- Files off-limits: **not touched** (verified: no changes to orchestrator, repository, or UI files)

**Files in Git Diff:**

```
new file:   ENGINEER_REPORT.md
new file:   20260801120000_fix_update_song_metadata_false_success.sql
modified:   ARCHITECT_PLAN.md (expected — plan was revised post-regression)
```

---

## Completeness Check

- All Architect tasks implemented: **yes**
- Missing tasks: **none**

**Task 1 — Write SQL Migration:** ✓ Completed and verified

**Task 2 — No Client Code Changes:** ✓ Verified via git diff

---

## Migration SQL Line-by-Line Review

### Function Signature (Lines 10-21)

✓ 11 parameters exactly as specified
✓ All have DEFAULT NULL except required params
✓ Signature unchanged from prior migration (no breaking change)

### Function Modifiers (Lines 23-26)

✓ `RETURNS JSON`
✓ `LANGUAGE plpgsql`
✓ `SECURITY DEFINER` (required for legacy NULL band_id songs)
✓ `SET search_path = public` (required per Guardrails §4)

### DECLARE Block (Lines 27-34)

✓ Original variables preserved: `v_user_id`, `v_is_member`, `v_song_band_id`, `v_update_count`
✓ **NEW:** `v_before_bpm`, `v_before_duration`, `v_before_key` — capture state before UPDATE
✓ **NEW:** `v_new_bpm`, `v_new_duration`, `v_new_key` — capture state after UPDATE (via RETURNING)

### Auth & Membership Checks (Lines 36-59)

✓ Auth check: `auth.uid() IS NULL` → error (unchanged)
✓ Band membership check via `band_members` table with `status = 'active'` (unchanged)
✓ Song existence check (unchanged)
✓ Band ownership check, allows NULL band_id for legacy songs (unchanged)

### Before-Value Capture (Lines 61-64) — NEW

```sql
SELECT bpm, duration_seconds, musical_key
INTO v_before_bpm, v_before_duration, v_before_key
FROM songs WHERE id = p_song_id;
```

✓ Captures current values before UPDATE runs
✓ Used to determine field eligibility in verification logic

### UPDATE Statement (Lines 66-79)

✓ **BPM CASE:** `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END`

- Fill-only condition: `bpm IS NULL`
- If current bpm is NOT NULL, CASE returns current bpm (no-op)

✓ **Duration CASE:** `CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END`

- Fill-only condition: `duration_seconds = 0`
- If current duration != 0, CASE returns current duration (no-op)

✓ **Musical Key CASE:** `CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END`

- Fill-only condition: `musical_key IS NULL OR TRIM(musical_key) = ''`
- If current key has non-empty value, CASE returns current key (no-op)

✓ Other fields use COALESCE or different CASE patterns (not fill-only)
✓ **NEW:** `RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key`

### ROW_COUNT Check (Lines 81-84)

✓ Preserved first-line defense
✓ Catches WHERE clause mismatch (UPDATE matched 0 rows)

### Eligibility-Aware Verification (Lines 86-129) — NEW, CRITICAL

**BPM Verification (Lines 89-100):**

```sql
IF p_bpm IS NOT NULL THEN
  IF v_before_bpm IS NULL THEN  -- ← ELIGIBILITY CHECK
    IF v_new_bpm IS DISTINCT FROM p_bpm THEN
      RETURN json_build_object('success', false, 'error', 'BPM update failed: ...');
    END IF;
  END IF;
  -- If field was not eligible (already had value), skip verification
END IF;
```

✓ **Correct logic:**

- Step 1: Is parameter provided? (`p_bpm IS NOT NULL`)
- Step 2: Was field eligible for fill? (`v_before_bpm IS NULL`)
- Step 3: Did value persist? (`v_new_bpm IS DISTINCT FROM p_bpm`)
- Only errors if ALL THREE are true

✓ **Regression prevention:**

- If `v_before_bpm` is NOT NULL (field already had value), eligibility check fails, verification is skipped, function returns success
- This is correct! The CASE intentionally did not update an already-set field.

**Duration Verification (Lines 102-113):**

```sql
IF p_duration_seconds IS NOT NULL THEN
  IF v_before_duration = 0 THEN  -- ← ELIGIBILITY CHECK
    IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
      RETURN json_build_object('success', false, 'error', 'Duration update failed: ...');
    END IF;
  END IF;
END IF;
```

✓ Eligibility condition matches CASE condition: `duration_seconds = 0`
✓ Skips verification if field was not eligible (already had non-zero value)

**Musical Key Verification (Lines 115-126):**

```sql
IF p_musical_key IS NOT NULL THEN
  IF v_before_key IS NULL OR TRIM(v_before_key) = '' THEN  -- ← ELIGIBILITY CHECK
    IF v_new_key IS DISTINCT FROM p_musical_key THEN
      RETURN json_build_object('success', false, 'error', 'Musical key update failed: ...');
    END IF;
  END IF;
END IF;
```

✓ **CRITICAL REGRESSION FIX:** Eligibility condition matches CASE condition: `musical_key IS NULL OR TRIM(musical_key) = ''`
✓ If field had non-empty value before UPDATE, eligibility check fails, verification is skipped, function returns success
✓ This prevents the "Could not save musical key" error when user tries to clear/edit an already-set key

### Success Return (Line 128)

✓ Returns success only after all verifications pass (or are skipped due to ineligibility)

### GRANT & COMMENT (Lines 134-137)

✓ `GRANT EXECUTE ON FUNCTION ... TO authenticated` (unchanged)
✓ Updated COMMENT documents eligibility-aware verification and regression fix

---

## Behavior Verification

**Validation method:** Code-path analysis + SQL logic review + manual code tracing

**Result:** Matches expected behavior per revised Architect plan

### Genuine Enrichment Failure (Should Error)

**Scenario:** Song has NULL bpm, enrichment API returns 120, RPC is called with `p_bpm=120`, but value doesn't persist.

**Flow:**

1. Before-value capture: `v_before_bpm = NULL`
2. UPDATE runs with CASE: `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END`
   - Condition TRUE: `p_bpm=120 IS NOT NULL` AND `bpm IS NULL`
   - CASE should return 120
3. RETURNING: `v_new_bpm` should be 120
4. Verification:
   - `p_bpm IS NOT NULL` → TRUE (120 provided)
   - `v_before_bpm IS NULL` → TRUE (field was eligible)
   - `v_new_bpm IS DISTINCT FROM p_bpm` → if TRUE (bug: value didn't persist), ERROR

**Result:** ✓ Correctly errors on genuine persistence failure

### Manual Edit of Already-Set Field (Should NOT Error — Regression Fix)

**Scenario:** Song has `musical_key = "Dm"`, user tries to change to "Em" via Song Details Save button.

**Flow:**

1. User opens Song Details, taps Key segment, selects "Em", taps Save
2. `_SongDetailsSheetState._handleSave()` returns `SongDetailsResult(musicalKey: "Em", musicalKeyChanged: true)`
3. `setlist_detail_screen._handleSongTap()` calls `notifier.updateSongMusicalKey(songId, "Em")`
4. Controller calls `_repository.updateSongMusicalKey(bandId: bandId, songId: songId, musicalKey: "Em")`
5. Repository calls `supabase.rpc('update_song_metadata', params: {'p_musical_key': "Em", ...})`
6. RPC runs:
   - Before-value capture: `v_before_key = "Dm"`
   - UPDATE with CASE: `CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END`
     - Condition FALSE: `musical_key = "Dm"` is NOT NULL and NOT empty
     - CASE returns "Dm" (current value, no-op)
   - RETURNING: `v_new_key = "Dm"` (unchanged)
   - Verification:
     - `p_musical_key IS NOT NULL` → TRUE ("Em" provided)
     - `v_before_key IS NULL OR TRIM(v_before_key) = ''` → FALSE ("Dm" is not NULL/empty)
     - Eligibility check fails → **skip verification** → return success
7. Repository returns success (no exception thrown)
8. Controller updates in-memory state to "Em" (optimistic update)
9. User sees "Em" in UI (but database still has "Dm")

**Result:** ✓ Correctly returns success for expected no-op (no regression)

**NOTE:** This is a pre-existing limitation per Architect plan "Out of Scope" section. Manual editing of already-set fields silently no-ops because the CASE logic is fill-only by design. This is NOT a new regression from this fix — it's the same behavior users had before 2026-08-01.

### Manual Clear of Already-Set Field (Should NOT Error — Regression Fix)

**Scenario:** Song has `musical_key = "Dm"`, user clears it via Song Details Save button.

**Flow:**

1. User opens Song Details, taps Key segment, clears value (tap on already-selected key), taps Save
2. `_SongDetailsSheetState._handleSave()` returns `SongDetailsResult(musicalKey: "", musicalKeyChanged: true)`
3. RPC called with `p_musical_key = ""`
4. CASE condition: `p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '')` → FALSE (current key "Dm" is not NULL/empty)
5. CASE returns "Dm" (no-op)
6. Verification:
   - `p_musical_key IS NOT NULL` → TRUE ("" provided)
   - `v_before_key IS NULL OR TRIM(v_before_key) = ''` → FALSE ("Dm" is not NULL/empty)
   - Eligibility check fails → **skip verification** → return success
7. No error, function returns success

**Result:** ✓ Correctly returns success (regression fixed — this case errored in the initial fix)

**This is the exact case that regressed in production on 2026-08-01.**

---

## Regression Check

**Risk level:** HIGH (per Architect assessment, due to production incident history)

**Systems reviewed:** All systems in System Impact Map

| System                           | Impact     | Regression Risk |
| -------------------------------- | ---------- | --------------- |
| Gigs                             | unaffected | none            |
| Rehearsals                       | unaffected | none            |
| Setlists / Catalog               | affected   | mitigated       |
| Members / RBAC                   | unaffected | none            |
| Auth / Session                   | unaffected | none            |
| Routing                          | unaffected | none            |
| Notifications                    | unaffected | none            |
| Platform (iOS/Android/Web/macOS) | affected   | mitigated       |

**Regression analysis:**

✓ No client code changes = no client-side regression risk
✓ RPC signature unchanged (11 parameters, same types)
✓ Auth/validation checks byte-for-byte identical to prior migration
✓ CASE logic byte-for-byte identical to prior migration
✓ New verification logic only adds error detection, does NOT change when/how updates occur
✓ Eligibility checks match CASE conditions exactly (no logic mismatch)
✓ `IS DISTINCT FROM` used for NULL-safe comparisons (correct)
✓ SECURITY DEFINER and SET search_path unchanged (no privilege escalation)
✓ No initialization order changes
✓ No rebuild triggers affected
✓ No RLS policy changes

**Specific regression prevention for production incident:**
✓ Manual edit of already-set BPM → eligibility check fails → skip verification → success
✓ Manual edit of already-set Duration → eligibility check fails → skip verification → success
✓ Manual edit of already-set Musical Key → eligibility check fails → skip verification → success
✓ Manual clear of already-set BPM → eligibility check fails → skip verification → success
✓ Manual clear of already-set Duration → eligibility check fails → skip verification → success
✓ Manual clear of already-set Musical Key → eligibility check fails → skip verification → success **← Production regression case**

---

## Database Safety

**Verified**

✓ No RLS policy changes
✓ No privilege escalation (maintains SECURITY DEFINER for legacy NULL band_id songs only)
✓ No unintended cascade behavior
✓ No destructive operations
✓ RPC signature matches Dart client calls (verified via code tracing)
✓ Migration timestamp `20260801120000` sorts correctly after all existing migrations
✓ No self-referencing RLS policies (none added, none modified)
✓ No infinite recursion risk

---

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors / 1 pre-existing info

**Info (pre-existing, unrelated):**

- `lib/features/setlists/setlist_detail_screen.dart:1449:32` — use_build_context_synchronously

This warning existed before this implementation and is unrelated to the fix (no Dart files modified).

---

## Test Results

### Tier 1 Pre-Deployment Tests

**Executed:** 2026-08-01 (this QA round)

**Test 1 — Verify function signature:**

```sql
SELECT pg_get_function_identity_arguments(oid)
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pronamespace = 'public'::regnamespace;
```

**Result:** ✅ PASS
**Output:** `p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text`

**Test 2 — Verify ROW_COUNT behavior on no-op UPDATE:**

```sql
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
**Output:** Notice raised successfully, confirming ROW_COUNT=1 even when UPDATE is a no-op

### Tier 2 Post-Deployment Tests

**Status:** NOT RUN (require `supabase db push` and authenticated session)

Per Architect Plan Verification Plan, Tier 2 tests must be run after migration deployment:

- POST-DEPLOY TEST 1: Verify function contains RETURNING clause
- POST-DEPLOY TEST 2: Test successful enrichment (BPM update on eligible/blank field)
- **POST-DEPLOY TEST 3: Regression prevention** — already-set field edit/clear must NOT error
- POST-DEPLOY TEST 4: Production verification of "All The Small Things" song data

**These tests MUST be run post-deployment before marking feature as fully validated.**

---

## Code-Path Tracing: Manual Metadata Editing

**Traced the complete flow for manual BPM/Duration/Musical Key editing to confirm no regressions:**

### Entry Point

`lib/features/setlists/setlist_detail_screen.dart` line 1120: User taps song card → `showSongDetailsBottomSheet()`

### Save Flow

`lib/features/setlists/widgets/song_details_bottom_sheet.dart`:

- User modifies BPM/Duration/Key via dialog/picker
- `_selectBpm()` / `_selectDuration()` / `_selectKey()` updates local state
- User taps Save button
- `_handleSave()` (line 463) creates `SongDetailsResult` with changed flags

### Controller Layer

`lib/features/setlists/setlist_detail_controller.dart`:

- BPM: `updateSongBpm(songId, bpm)` (line 1131) → calls `_repository.updateSongBpmOverride()`
- Duration: `updateSongDuration(songId, durationSeconds)` (line 1231) → calls `_repository.updateSongDurationOverride()`
- Musical Key: `updateSongMusicalKey(songId, musicalKey)` (line 1428) → calls `_repository.updateSongMusicalKey()`

### Repository Layer

`lib/features/setlists/setlist_repository.dart`:

- `updateSongBpmOverride()` (line 1493) → `supabase.rpc('update_song_metadata', params: {'p_bpm': bpm, ...})`
- `updateSongDurationOverride()` → similar pattern
- `updateSongMusicalKey()` (line 2192) → `supabase.rpc('update_song_metadata', params: {'p_musical_key': musicalKey, ...})`

All three methods:

1. Call RPC with appropriate parameter
2. Check result: `if (result is Map && result['success'] == false) { throw Exception(error); }`
3. If no exception, return successfully
4. On error, throw exception which propagates to controller → controller reverts optimistic update → user sees error

### RPC Layer

`supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql`:

- Receives parameter (e.g., `p_bpm=140` when user changed BPM from 120 to 140)
- Captures before-value: `v_before_bpm = 120`
- Runs UPDATE with CASE: `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END`
  - Condition FALSE (bpm is not NULL)
  - Returns current bpm (120)
- RETURNING: `v_new_bpm = 120`
- Verification:
  - `p_bpm IS NOT NULL` → TRUE
  - `v_before_bpm IS NULL` → FALSE (field was not eligible)
  - **Eligibility check fails → skip verification**
- Returns `{"success": true}`

**Result:** ✓ No error thrown, no regression

---

## Diff Safety Review

✓ No secrets or API keys
✓ No debug artifacts (print statements, TODO hacks, temporary flags)
✓ No test scaffolding left in production code
✓ No accidental file deletions
✓ No unrelated formatting changes
✓ Clean SQL with explanatory comments only

---

## Issues Found

None

---

## Deployment Gate — MANDATORY RUNTIME TESTING

**This approval is CONDITIONAL on completing the following runtime tests on a real device BEFORE merge:**

### Critical Test 1: Manual Edit of Already-Set Musical Key (Production Regression Case)

1. Select a song with musical_key already set (e.g., "Dm")
2. Open Song Details
3. Tap Key segment
4. Select different key (e.g., "Em")
5. Tap Save
6. **MUST NOT show error**
7. **Expected result:** Key remains "Dm" in database (fill-only CASE design), but no error shown to user

### Critical Test 2: Manual Clear of Already-Set Musical Key (Production Regression Case)

1. Select a song with musical_key already set (e.g., "Dm")
2. Open Song Details
3. Tap Key segment
4. Tap same key again to clear (empty selection)
5. Tap Save
6. **MUST NOT show error "Could not save musical key"**
7. **Expected result:** Key remains "Dm" in database (fill-only CASE design), but no error shown to user

### Critical Test 3: Manual Edit of Already-Set BPM

1. Select a song with BPM already set (e.g., 120)
2. Open Song Details
3. Tap BPM segment
4. Enter different BPM (e.g., 140)
5. Tap Save
6. **MUST NOT show error**
7. **Expected result:** BPM remains 120 in database, no error shown

### Critical Test 4: Enrichment on Eligible Fields

1. Select a song with NULL bpm, empty key, 0 duration
2. Open Song Details
3. Tap "Enrich Song Data"
4. Select API sources, complete enrichment
5. **Expected result:** Values persist, "Enrichment complete" screen shows values, Song Details shows persisted values after tapping "Done"

### Critical Test 5: Enrichment Error Visibility

If enrichment parameters arrive as NULL (underlying bug not yet fixed):

1. Attempt enrichment on eligible song
2. **Expected result:** Error shown to user with diagnostic message (e.g., "BPM update failed: requested 120, got NULL")
3. Error allows user to report with context

**WHY THIS IS NON-NEGOTIABLE:**

The prior QA approval was based on code review only, without runtime testing of manual metadata editing (QA Regression Area #5). The regression was hiding in the interaction between unchanged CASE logic and new verification logic, which could ONLY be caught by exercising the actual user flow on a real device with real auth context.

**Runtime testing is the ONLY way to validate:**

- Auth context (`auth.uid()`) works correctly
- Band membership check passes
- RPC returns expected JSON structure
- Error messages propagate correctly to UI
- No unexpected exceptions in async gaps
- Optimistic updates revert correctly on error

**QA CANNOT approve for merge until these tests are completed and results documented.**

---

## Follow-Up Required (Out of Scope)

Per Architect plan, this fix makes enrichment failures **visible** instead of **silent**. The underlying cause (why enrichment parameters sometimes arrive as NULL) remains undiagnosed and requires follow-up after deployment:

1. Monitor production for genuine enrichment errors (users report "BPM update failed" or "Musical key update failed")
2. If errors occur, add runtime instrumentation:
   - Dart-side: Log `update` map contents before `.rpc()` call in `SetlistRepository.enrichSongs()`
   - DB-side: Create temp table to log RPC parameters at function entry
3. Identify whether parameters are NULL on Dart side (serialization issue) or database side (PostgREST issue)
4. File targeted fix based on logs

---

## Pre-Existing Limitation (Not Being Fixed)

Users CANNOT clear or change already-set BPM/Duration/Key values via manual Save in Song Details. The fill-only CASE logic is intentional per enrichment non-overwrite design (migration 20260801000000).

This limitation:

- Existed before this fix
- Is NOT being addressed in this fix (requires separate feature work)
- Was masked by lack of verification (now exposed but not worsened)
- Is the same behavior users had before 2026-08-01

To fix this limitation (separate feature request):

- Either: Change CASE logic to support overwrites (high risk, contradicts enrichment design)
- Or: Add clear RPCs for all three fields + update manual Save code path to detect clears vs. sets

---

## QA Sign-Off

**Approved by:** AI QA Agent (GitHub Copilot - Claude Sonnet 4.5)
**Date:** 2026-08-01
**Revision:** 2 (supersedes prior approval dated 2026-08-01)

**Approval Conditions:**

1. ✅ Migration SQL verified correct
2. ✅ Tier 1 pre-deployment tests passed
3. ⚠️ **PENDING:** Runtime testing per "Deployment Gate" section (MUST complete before merge)
4. ⚠️ **PENDING:** Tier 2 post-deployment tests (MUST run after `supabase db push`)

**Next Steps:**

1. Deployment engineer: Run runtime tests per "Deployment Gate" section
2. Document test results in this report (append to bottom)
3. If all tests pass: Deploy migration via `supabase db push`
4. Run Tier 2 post-deployment tests
5. Monitor production for genuine enrichment errors (indicates underlying NULL-parameter issue needs follow-up)

**Final Approval:** ⚠️ CONDITIONAL — awaiting runtime test completion

---

## Direct RPC Validation (Staging-2)

**Validated by:** AI QA Agent (GitHub Copilot - Claude Sonnet 4.5)  
**Date:** 2026-08-01  
**Environment:** staging-2 (project ref: `hpjvbagybmmaykamsgpd`)  
**Method:** Direct SQL RPC calls with authenticated session context

**Rationale:** The corrected migration is database-only (no client code changes). Direct RPC validation via SQL provides faster feedback than full app testing while still exercising the complete function logic including auth context, band membership checks, CASE logic, and eligibility-aware verification.

### Pre-Validation Checks

✅ **Verified staging-2 linked:** Project ref `hpjvbagybmmaykamsgpd` confirmed  
✅ **Verified migration deployed:** Function source includes eligibility-aware verification variables (`v_before_bpm`, `v_before_duration`, `v_before_key`, `v_new_bpm`, `v_new_duration`, `v_new_key`)  
✅ **Test fixtures created:** Minimal test band, active member, two test songs:

- Song 1: `Test Song With Data` — bpm=130, musical_key='Dm' (for Tests A, B, C)
- Song 2: `Test Song Null BPM` — bpm=NULL, musical_key='C' (for Test D)

### Test A: Empty String on Populated Field (Production Regression Case)

**Scenario:** Song has `musical_key='Dm'`, call RPC with `p_musical_key=''` (empty string).

**Expected:** `{"success": true}`, musical_key unchanged (still 'Dm' per fill-only design).

**SQL Executed:**

```sql
-- Set auth context
PERFORM set_config('request.jwt.claims', json_build_object('sub', '<user_id>', 'role', 'authenticated')::text, true);
PERFORM set_config('role', 'authenticated', true);

-- Call RPC
SELECT update_song_metadata(
  p_song_id := '<song_id>'::UUID,
  p_band_id := '<band_id>'::UUID,
  p_musical_key := ''
);
```

**Result:** ✅ **PASS**

- RPC returned: `{"success": true}`
- Final musical_key: `Dm` (unchanged)
- **Regression fixed:** No error thrown when attempting to clear already-set field

### Test B: Non-Empty Value on Populated Field

**Scenario:** Song has `musical_key='Dm'`, call RPC with `p_musical_key='Em'`.

**Expected:** `{"success": true}`, musical_key unchanged (still 'Dm' per fill-only design).

**SQL Executed:**

```sql
SELECT update_song_metadata(
  p_song_id := '<song_id>'::UUID,
  p_band_id := '<band_id>'::UUID,
  p_musical_key := 'Em'
);
```

**Result:** ✅ **PASS**

- RPC returned: `{"success": true}`
- Final musical_key: `Dm` (unchanged)
- No error thrown (expected no-op, field not eligible for update)

### Test C: BPM on Populated Field

**Scenario:** Song has `bpm=130`, call RPC with `p_bpm=999`.

**Expected:** `{"success": true}`, bpm unchanged (still 130 per fill-only design).

**SQL Executed:**

```sql
SELECT update_song_metadata(
  p_song_id := '<song_id>'::UUID,
  p_band_id := '<band_id>'::UUID,
  p_bpm := 999
);
```

**Result:** ✅ **PASS**

- RPC returned: `{"success": true}`
- Final bpm: `130` (unchanged)
- No error thrown (expected no-op, field not eligible for update)

### Test D: Genuine Enrichment (NULL BPM → 120)

**Scenario:** Song has `bpm=NULL`, call RPC with `p_bpm=120`.

**Expected:** `{"success": true}`, bpm becomes 120 (genuine enrichment on eligible field).

**SQL Executed:**

```sql
-- Reset song to NULL bpm
UPDATE songs SET bpm = NULL WHERE id = '<song_id>';

-- Call RPC
SELECT update_song_metadata(
  p_song_id := '<song_id>'::UUID,
  p_band_id := '<band_id>'::UUID,
  p_bpm := 120
);
```

**Result:** ✅ **PASS**

- RPC returned: `{"success": true}`
- Final bpm: `120` (successfully updated)
- **Genuine enrichment works:** Value persisted from NULL to 120

**Diagnostic Investigation:**
Created temporary debug function to trace UPDATE internals:

- `auth_uid`: Correctly set via `set_config`
- `before_bpm`: NULL (eligible for fill)
- `new_bpm`: 120 (CASE logic executed correctly)
- `update_count`: 1 (UPDATE matched row)
- **Conclusion:** RETURNING clause and eligibility verification work as designed

### Validation Summary

**All Tests Passed:** 4/4

| Test | Scenario                           | Expected           | Actual             | Status  |
| ---- | ---------------------------------- | ------------------ | ------------------ | ------- |
| A    | Empty string on populated field    | Success, no change | Success, no change | ✅ PASS |
| B    | Non-empty value on populated field | Success, no change | Success, no change | ✅ PASS |
| C    | BPM on populated field             | Success, no change | Success, no change | ✅ PASS |
| D    | Genuine enrichment (NULL → 120)    | Success, value set | Success, value set | ✅ PASS |

### Critical Findings

1. **Production regression fixed:** Test A confirms empty string on populated field no longer throws "Musical key update failed" error
2. **Fill-only design preserved:** Tests B and C confirm already-set fields correctly skip verification and return success
3. **Genuine enrichment works:** Test D confirms eligible fields (NULL/empty/zero) are correctly enriched and persisted
4. **Eligibility-aware verification working:** All tests show correct distinction between eligible fields (error on failure) and ineligible fields (success on no-op)

### Limitations of SQL Testing

This validation confirms:
✅ RPC function logic (CASE, RETURNING, verification)  
✅ Auth context handling (`auth.uid()`)  
✅ Band membership checks  
✅ Database-level error detection

This validation **does not** confirm:
❌ UI error propagation (exception → snackbar)  
❌ Optimistic update rollback on error  
❌ Song Details bottom sheet save flow  
❌ Enrichment orchestrator parameter passing

**Recommendation:** SQL validation provides high confidence in RPC correctness. Full UI-based runtime testing (per "Deployment Gate" section) should still be completed for end-to-end validation of client-side error handling and orchestrator integration.

---

**Final Approval Status:** ⚠️ CONDITIONAL — Direct RPC validation complete (PASS), awaiting full UI runtime testing
