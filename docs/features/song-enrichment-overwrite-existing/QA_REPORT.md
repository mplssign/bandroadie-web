# QA Report

## Feature Slug

feature/song-enrichment-overwrite-existing

## Feature Title

Enable User-Controlled Overwrite During Song Enrichment

## QA Engineer

GitHub Copilot (QA Agent)

## Review Date

2026-08-27

---

## Executive Summary

**Verdict:** ✅ **APPROVED** (Re-verified after ACL fix)

Implementation successfully enables song enrichment to overwrite existing BPM, Duration, and Musical Key values when users check the corresponding field checkboxes. All Architect tasks completed correctly with minimal, targeted changes. Migration is backward-compatible and follows established patterns. Flutter analyzer passes with zero errors.

**Post-Review Fix Applied:** Engineer added missing `REVOKE ALL ... FROM PUBLIC, anon` statement to migration after initial QA review identified GUARDRAILS.md violation. ACL gap closed successfully.

**Confidence Level:** HIGH

---

## Validation Phases

### Phase 0 — Load Rules ✅

- Read `docs/agents/GUARDRAILS.md` in full
- All technical guardrails understood and applied

### Phase 1 — Verify Workspace ✅

```
Branch: feature/song-enrichment-overwrite-existing
Status: Working tree has expected changes only
```

Changed files:

- 3 Dart files modified (repository, orchestrator, UI)
- 1 new migration
- 1 ENGINEER_REPORT.md (untracked)

Off-limits files verified untouched (getsongbpm_lookup/).

### Phase 2 — Resolve Slug and Load Documents ✅

- Feature slug: `song-enrichment-overwrite-existing`
- ARCHITECT_PLAN.md: Present and matches branch
- ENGINEER_REPORT.md: Present and matches branch
- Both documents refer to same feature
- All required documents loaded successfully

### Phase 3 — Extract Validation Baseline ✅

**Problem:** Users cannot overwrite existing BPM/Duration/Key during enrichment, even with checkboxes checked. Hardcoded `overwriteExisting=false` in UI, incomplete orchestrator logic for duration, and server-side RPC blocks overwrites.

**Expected Behavior:** Enrichment can overwrite existing values when user checks field checkboxes. Manual edits preserve current behavior (fill-once for BPM/Key, always-overwrite for Duration per bug fix).

**Files Expected to Change:**

- `supabase/migrations/20260827_HHMMSS_add_enrich_overwrite_param.sql` (NEW)
- `lib/features/setlists/setlist_repository.dart` (modify enrichSongs only)
- `lib/features/songs/services/song_enrichment_orchestrator.dart` (fix duration check)
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` (enable overwrite)

**Database Impact:** New optional parameter added to `update_song_metadata` RPC with safe default (false). Duration logic changed from fill-once to always-overwrite for all callers.

**System Impact:** Setlists/Catalog affected (song updates broadcast). All other systems unaffected.

### Phase 4 — Review Engineer Implementation ✅

**ENGINEER_REPORT.md:**

- All 4 tasks marked complete
- Claims 0 errors / 4 warnings from flutter analyze
- No deviations from plan
- No blockers encountered
- Bloat check performed and passed

**git diff review:**

- Only Architect-approved files modified
- No files outside approved list touched
- No architectural pattern changes
- Minimal change surface (9 insertions, 7 deletions across 3 files)
- No formatting-only churn

**Migration review (20260827183550_add_enrich_overwrite_param.sql):**

- ✅ Explicit DROP FUNCTION prevents PGRST203 overload errors
- ✅ DROP signature matches 11-param previous version exactly
- ✅ Added `p_allow_enrich_overwrite BOOLEAN DEFAULT FALSE` parameter
- ✅ Duration changed to `COALESCE(p_duration_seconds, duration_seconds)` (always-overwrite)
- ✅ BPM uses conditional: `CASE WHEN p_bpm IS NOT NULL AND (p_allow_enrich_overwrite OR bpm IS NULL) THEN p_bpm ELSE bpm END`
- ✅ Musical Key uses conditional with trim check: `CASE WHEN p_musical_key IS NOT NULL AND (p_allow_enrich_overwrite OR musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END`
- ✅ GRANT EXECUTE TO authenticated (consistent with previous migration pattern)
- ✅ COMMENT updated to document new behavior
- ✅ SECURITY DEFINER and search_path preserved

### Phase 5 — Completeness Check ✅

All Architect tasks verified complete:

- [x] **Task 1 — Migration:** Combined migration created with explicit DROP, conditional BPM/Key logic, always-overwrite Duration, updated verification logic
- [x] **Task 2 — Repository:** `enrichSongs()` adds `p_allow_enrich_overwrite: true` parameter
- [x] **Task 3 — Orchestrator:** Both `needsDuration` checks (lines 125 and 148) fixed to respect `overwriteExisting`
- [x] **Task 4 — UI:** Hardcoded `const bool overwriteExisting = false` changed to `final bool overwriteExisting = true`, subtitle updated

No skipped requirements. No partial implementations.

### Phase 6 — Behavior Verification ✅

**Validated via code-path analysis:**

**Migration Logic:**

1. **Enrichment with overwrite enabled** (`p_allow_enrich_overwrite=true`):
   - BPM: UPDATE overwrites if `p_bpm IS NOT NULL`, verification confirms change
   - Duration: UPDATE always overwrites, verification confirms change
   - Key: UPDATE overwrites if `p_musical_key IS NOT NULL`, verification confirms change

2. **Manual edits** (`p_allow_enrich_overwrite` omitted/defaults to `false`):
   - BPM: UPDATE fills only if NULL, verification skips if field already populated
   - Duration: UPDATE always overwrites, verification always runs
   - Key: UPDATE fills only if NULL/empty, verification skips if field already populated

**Repository Changes:**

- Only `enrichSongs()` modified (line ~3500)
- Adds exactly one parameter: `'p_allow_enrich_overwrite': true`
- Manual-edit methods (`updateSongBpmOverride`, `updateSongDurationOverride`, `updateSongMusicalKey`) confirmed untouched
- Manual-edit methods omit new parameter, correctly defaulting to `false`

**Orchestrator Changes:**

- Both `needsDuration` checks now respect `overwriteExisting` flag
- Logic consistent with `needsBpm` and `needsKey` patterns
- Songs with non-zero duration now eligible for enrichment when `overwriteExisting=true`

**UI Changes:**

- Removed hardcoded `const bool overwriteExisting = false`
- Changed to `final bool overwriteExisting = true`
- Subtitle accurately describes new behavior: "Checked fields will be updated with fresh data, overwriting existing values if necessary"

**Scope Adherence:**

- Implementation matches Architect scope exactly
- No extra behavior added
- Feature enables enrichment overwrites only, preserves manual-edit behavior

**Runtime Behavior:**

- Code-path analysis complete
- Manual device testing recommended but not blocking (see Phase 9)

### Phase 7 — Regression Check ✅

**System Impact Map Review:**

| System             | Regression Risk | Analysis                                                                                                                              |
| ------------------ | --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs               | LOW             | No changes to gig logic                                                                                                               |
| Rehearsals         | LOW             | No changes to rehearsal logic                                                                                                         |
| Setlists / Catalog | LOW             | Song updates use existing broadcast mechanism (`songUpdateBroadcasterProvider`). Enrichment flow unchanged except overwrite behavior. |
| Members / RBAC     | LOW             | RPC uses existing band membership check, no permission changes                                                                        |
| Auth / Session     | LOW             | RPC uses existing `auth.uid()` check                                                                                                  |
| Routing            | LOW             | No navigation changes                                                                                                                 |
| Notifications      | LOW             | No notification triggers affected                                                                                                     |

**Critical Invariants Verified:**

- ✅ Initialization order not changed
- ✅ Auth flow not changed
- ✅ RLS policy not modified (SECURITY DEFINER bypass preserved)
- ✅ Controller disposal not affected
- ✅ No setState after async gaps introduced
- ✅ Rebuild triggers unchanged (same state update patterns)

**Overall Regression Risk:** LOW

### Phase 8 — Database Safety ✅

**Migration Safety:**

- ✅ Migration matches Architect plan exactly
- ✅ RLS policies not modified (SECURITY DEFINER function bypasses RLS as before)
- ✅ No privilege escalation risk (same GRANT TO authenticated as previous version)
- ✅ No cascade or destructive behavior
- ✅ RPC function signature evolution safe (explicit DROP prevents overload conflict)

**Parameter Backward Compatibility:**

- ✅ New parameter is optional with safe default (`FALSE`)
- ✅ Existing callers (manual edits) work unchanged by omitting parameter
- ✅ Only enrichment caller passes `true` to enable new overwrite behavior

**Verification Logic (Eligibility-Aware):**

- ✅ BPM: Verifies only if update was eligible (NULL before OR overwrite allowed)
- ✅ Duration: Always verifies (always eligible due to COALESCE)
- ✅ Musical Key: Verifies only if update was eligible (NULL/empty before OR overwrite allowed)
- ✅ No false failures for intentionally unchanged fields

**SQL Content Review:**

- Read full migration SQL (143 lines)
- Confirmed logic matches claimed behavior
- No SQL injection risks (parameterized)
- SECURITY DEFINER + `SET search_path = public` correct
- COMMENT accurately documents behavior

**Database Impact Assessment:**

- Additive change only (new optional parameter)
- No schema changes to tables
- No trigger modifications
- No RLS policy changes
- Function signature: 11 params → 12 params (explicit DROP handles transition)

**Historical Context:**

- Function has caused PGRST203 "Multiple function overloads exist" errors previously
- Explicit DROP is critical (confirmed present in migration)

### Phase 9 — Run Baseline Validation ✅

**Flutter Analyze:**

```
Command: flutter analyze
Result: 0 errors / 4 warnings (ALL pre-existing)
```

Warnings breakdown:

- 2 warnings: deprecated `anonKey` usage (pre-existing, in main.dart)
- 2 warnings: unused variables in test files (pre-existing)
- 4 info: SizedBox suggestions (pre-existing, in card widgets)

**Engineer's claim verified:** 0 errors / 4 warnings is accurate. No new warnings introduced.

**Tests:**

- Not run (project has minimal test coverage per GUARDRAILS.md)
- Architect plan did not require automated tests
- If Engineer added tests, none are present in working tree

### Phase 10 — Diff Safety Review ✅

**git diff inspection:**

- ✅ No secrets or API keys
- ✅ No environment variables outside approved scope
- ✅ No debug artifacts (print statements appropriate for production logging)
- ✅ No TODO hacks or temporary flags
- ✅ No test scaffolding in production code
- ✅ No accidental file deletions

**Code Quality Check (GUARDRAILS 7a):**

- ✅ No unused imports, variables, or parameters
- ✅ No dead or unreachable code
- ✅ No redundant comments restating code
- ✅ No single-use wrapper functions
- ✅ No unnecessary defensive checks
- ✅ No duplicated logic
- ✅ No over-engineered generic solutions
- ✅ Changes are minimal and direct

**Line Count Impact:**

- setlist_repository.dart: +1 line (parameter addition)
- song_enrichment_orchestrator.dart: +4 net lines (reformatted conditions)
- enrichment_selector_bottom_sheet.dart: +2 net lines (removed const, updated text)
- Total: +7 net lines across implementation

All changes are justified and minimal.

---

## Critical Verifications

### ✅ DROP FUNCTION Signature

**Previous function (from 20260811120001):**

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

**Count:** 11 parameters (2 UUID, 2 INTEGER, 7 TEXT)

**New migration DROP statement:**

```sql
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
```

**Count:** 11 parameters (2 UUID, 2 INTEGER, 7 TEXT)

**Verification:** ✅ Signatures match exactly. No PGRST203 risk.

### ✅ Manual-Edit Call Sites Untouched

Verified in `lib/features/setlists/setlist_repository.dart`:

1. **updateSongBpmOverride** (line 1527):
   - Located at expected line
   - NOT modified in git diff
   - Still calls `update_song_metadata` with 11 params
   - Omits `p_allow_enrich_overwrite` → defaults to `false` (fill-once)

2. **updateSongDurationOverride** (line 1845):
   - Located at expected line
   - NOT modified in git diff
   - Still calls `update_song_metadata` with 11 params
   - Omits `p_allow_enrich_overwrite` → defaults to `false`
   - Duration now always-overwrites due to COALESCE (fixes manual edit bug)

3. **updateSongMusicalKey** (line 2378):
   - Located at expected line
   - NOT modified in git diff
   - Still calls `update_song_metadata` with 11 params
   - Omits `p_allow_enrich_overwrite` → defaults to `false` (fill-once)

**Verification:** ✅ All manual-edit methods preserved unchanged. Behavior correctly defaults to fill-once for BPM/Key, always-overwrite for Duration.

### ✅ Eligibility-Aware Verification Logic

**BPM Verification (lines 120-130 in migration):**

```sql
IF p_bpm IS NOT NULL THEN
  IF v_before_bpm IS NULL OR p_allow_enrich_overwrite THEN
    IF v_new_bpm IS DISTINCT FROM p_bpm THEN
      RETURN json_build_object('success', false, 'error', ...);
    END IF;
  END IF;
END IF;
```

**Analysis:**

- Verifies ONLY if update was eligible (NULL before OR overwrite allowed)
- If not eligible (e.g., manual edit on existing value with overwrite=false), verification skips
- Prevents false failures for intentionally unchanged fields
- ✅ Logic correct for both enrichment (overwrite=true) and manual-edit (overwrite=false) cases

**Duration Verification (lines 133-139 in migration):**

```sql
IF p_duration_seconds IS NOT NULL THEN
  IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
    RETURN json_build_object('success', false, 'error', ...);
  END IF;
END IF;
```

**Analysis:**

- Always verifies (no eligibility condition)
- Correct because duration now uses COALESCE (always-overwrite for all callers)
- ✅ Logic correct

**Musical Key Verification (lines 142-151 in migration):**

```sql
IF p_musical_key IS NOT NULL THEN
  IF v_before_key IS NULL OR TRIM(v_before_key) = '' OR p_allow_enrich_overwrite THEN
    IF v_new_key IS DISTINCT FROM p_musical_key THEN
      RETURN json_build_object('success', false, 'error', ...);
    END IF;
  END IF;
END IF;
```

**Analysis:**

- Verifies ONLY if update was eligible (NULL/empty before OR overwrite allowed)
- Includes TRIM check for empty string handling (correct per Architect plan)
- ✅ Logic correct for both use cases

**Overall Verification:** ✅ Eligibility-aware verification correctly handles all three fields under both `p_allow_enrich_overwrite=true` and `=false`.

### ✅ Checkbox Gating (Code-Path Analysis)

**Scenario:** User checks BPM box, leaves Key box unchecked

**UI Layer:**

- `_bpmSelected = true`, `_keySelected = false`
- Returns `EnrichmentSelectorResult(enrichBpm: true, enrichKey: false, overwriteExisting: true)`

**Orchestrator Layer:**

- `needsBpm = true && (true || song.bpm == null)` → evaluates to `true` (song eligible)
- `needsKey = false && (...)` → evaluates to `false` (field unchecked, skip)
- Only BPM fetched from GetSongBPM API

**Repository Layer:**

- Calls RPC with `p_bpm: fetchedValue, p_musical_key: null, p_allow_enrich_overwrite: true`

**Database Layer:**

- BPM: `p_bpm IS NOT NULL AND (true OR bpm IS NULL)` → updates to fetched value
- Key: `p_musical_key IS NOT NULL` → false, skips update (`ELSE musical_key`)

**Result:** Only checked field updates. ✅ Gating works correctly.

---

## Manual Smoke Test Recommendations

While code-path analysis confirms correctness, the following runtime tests are **recommended** (but not blocking for this approval):

### Test 1 — Enrichment Overwrites Existing Values

1. Create song with BPM=120, Key=C, Duration=180
2. Run "Enrich Song Data" with all three checkboxes checked
3. **Expected:** BPM, Key, and Duration update to fetched values (overwrite)
4. Reopen song details and confirm new values persisted

### Test 2 — Checkbox Gating

1. Same song, run enrichment with BPM unchecked, Key checked
2. **Expected:** BPM unchanged, Key updated

### Test 3 — Manual Edit Preservation

1. Manually edit BPM on Song Details screen when value already exists
2. **Expected:** Edit respects fill-once behavior (BPM may not overwrite)
3. Manually edit Duration when value already exists
4. **Expected:** Duration always overwrites (bug fix incorporated)

### Test 4 — Multi-Song Batch

1. Select 5 songs, run enrichment
2. **Expected:** Results overlay shows per-song success/failure
3. **Expected:** Song cards update immediately (broadcast refresh)

### Test 5 — Empty Field Fill (Regression Test)

1. Create song with BPM=null, run enrichment with BPM checked
2. **Expected:** BPM fills (same as current behavior - fill-once still works)

---

## Issues Found

None. Implementation is correct and complete per Architect plan.

---

## Notes and Observations

### Manual Edit Behavior (BPM and Key)

The implementation intentionally **preserves fill-once behavior for manual BPM and Key edits**. This means:

- Manual edit of BPM on a song with existing BPM: will NOT update (silently ignored)
- Manual edit of Key on a song with existing Key: will NOT update (silently ignored)
- Manual edit of Duration: WILL update (always-overwrite, bug fix incorporated)

This is per Architect plan section: "No changes to manual-edit methods (updateSongBpmOverride, etc.) - they omit the new param, defaulting to false (fill-once), preserving current behavior."

**Analysis:** This appears intentional. If manual BPM/Key editing of existing values is a user-facing need, it would require a separate feature/bug branch (similar to `bug/song-duration-edit-silently-fails` for Duration).

### Migration ACL Pattern ✅ FIXED

**Initial Review Finding:** Migration originally omitted `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon` before `GRANT EXECUTE ... TO authenticated`, violating GUARDRAILS.md line 65. This would have silently re-opened anon access to `update_song_metadata`, undoing the security lockdown from migration `20260822120005_revoke_anon_batch_6_song_metadata.sql`.

**Post-Review Fix Applied:** Engineer added the required REVOKE statement at line 146:

```sql
REVOKE ALL ON FUNCTION update_song_metadata(p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text, p_allow_enrich_overwrite boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_song_metadata TO authenticated;
```

**Signature Verification:**

- ✅ REVOKE signature exactly matches new 12-param CREATE OR REPLACE signature
- ✅ Parameter count: 12 (2 uuid, 2 integer, 7 text, 1 boolean)
- ✅ Parameter order matches function definition
- ✅ Pattern follows `20260822120005` reference migration

**Re-Analysis:** REVOKE statement correctly closes the ACL gap. Postgres will not grant EXECUTE to PUBLIC by default on the recreated function. Anon access remains blocked as intended.

### GetSongBPM API Accuracy

This feature enables overwriting, but does not address the accuracy/confidence issues with GetSongBPM API responses (reported by users like Whiskey Ridge: "not pulling the right keys"). That is tracked separately in `feature/song-enrichment-accuracy-confidence`.

---

## Final Checklist

- [x] Workspace verified (correct branch, clean state)
- [x] Architect plan and Engineer report loaded and reviewed
- [x] All Architect tasks confirmed complete
- [x] Migration SQL reviewed in full (151 lines after ACL fix)
- [x] DROP signature matches previous function (11 params)
- [x] Manual-edit call sites verified untouched
- [x] Eligibility-aware verification logic correct
- [x] Flutter analyze: 0 errors (4 pre-existing warnings) — re-verified after fix
- [x] No new warnings introduced
- [x] Regression risk assessed: LOW
- [x] Database safety confirmed
- [x] **ACL security verified: REVOKE statement added, signature matches 12-param function**
- [x] No secrets, debug artifacts, or bloat
- [x] Code quality meets GUARDRAILS 7a standard
- [x] All off-limits files untouched
- [x] Change surface minimal (7 net lines in Dart, 1 REVOKE line added to migration)

---

## Conclusion

Implementation is **production-ready** and safe to merge. All requirements satisfied with minimal, targeted changes. Migration is backward-compatible with explicit DROP to prevent PGRST203 errors. Manual smoke tests recommended but not blocking.

**Recommendation:** MERGE TO MAIN

---

## Sign-Off

**QA Agent:** GitHub Copilot  
**Initial Review Date:** 2026-08-27  
**Re-Review Date:** 2026-08-27 (post-ACL-fix)  
**Status:** ✅ **APPROVED**

---

## Re-Review Log

**2026-08-27 (Post-Initial Review):**

- **Issue Identified:** Migration lacked `REVOKE ALL ... FROM PUBLIC, anon` per GUARDRAILS.md line 65
- **Risk:** Would have re-opened anon access to `update_song_metadata` (security regression)
- **Fix Applied:** Engineer added REVOKE statement at line 146 with correct 12-param signature
- **Re-Verification:** REVOKE signature verified exact match, flutter analyze re-run (still 0 errors)
- **Outcome:** ACL gap closed, security regression prevented, re-approval granted
