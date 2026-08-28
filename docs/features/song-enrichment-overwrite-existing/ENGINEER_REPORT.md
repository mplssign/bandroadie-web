# Engineer Report

## Feature Slug

feature/song-enrichment-overwrite-existing

## Feature Title

Enable User-Controlled Overwrite During Song Enrichment

## Goal

Allow users to overwrite existing BPM, Duration, and Musical Key values during song enrichment when the corresponding field checkboxes are checked. Remove the hardcoded `overwriteExisting = false` constraint in the UI, fix the orchestrator's duration check to respect the `overwriteExisting` flag, and add a server-side parameter to enable enrichment-specific overwrites while preserving fill-once behavior for manual edits.

## Architect Tasks Completed

- [x] Task 1 — Create combined migration adding `p_allow_enrich_overwrite` parameter
  - Added explicit DROP FUNCTION to prevent PGRST203 overload errors
  - Changed duration_seconds from fill-once (CASE) to always-overwrite (COALESCE)
  - Modified BPM and Key logic to check new overwrite flag
  - Updated verification logic for duration to check unconditionally
  - Status: Complete
- [x] Task 2 — Modify `enrichSongs()` in setlist_repository.dart
  - Added `'p_allow_enrich_overwrite': true` to RPC params
  - Status: Complete
- [x] Task 3 — Fix orchestrator duration check (2 occurrences)
  - Updated both needsDuration checks at lines 125 and 147
  - Status: Complete
- [x] Task 4 — Update UI to enable overwriting
  - Removed hardcoded `const bool overwriteExisting = false`
  - Changed to `final bool overwriteExisting = true`
  - Updated subtitle text to reflect new behavior
  - Status: Complete

## Files Created

- `supabase/migrations/20260827183550_add_enrich_overwrite_param.sql`

## Files Modified

- `lib/features/setlists/setlist_repository.dart` — Added p_allow_enrich_overwrite param to enrichSongs() RPC call
- `lib/features/songs/services/song_enrichment_orchestrator.dart` — Fixed needsDuration logic to respect overwriteExisting (2 locations)
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` — Removed hardcoded false, updated subtitle text

## Analyzer Results

Command: `flutter analyze`  
Result: 0 errors / 4 warnings

All warnings are pre-existing (unused variables in test files, deprecated anonKey usage, SizedBox suggestions) — no new warnings introduced by this implementation.

## Test Results

Not run (project has minimal test coverage per GUARDRAILS.md)

## Code Efficiency / Bloat Check

Reviewed all changes in git diff. Confirmed:

- ✅ No unused imports, variables, or parameters added
- ✅ No dead or unreachable code introduced
- ✅ No redundant comments that restate the code
- ✅ No single-use wrapper functions or abstractions
- ✅ No unnecessary defensive checks or try-catch blocks
- ✅ No duplicated logic — reused existing patterns
- ✅ All changes are minimal, direct modifications to implement the feature

The implementation is the most direct path to satisfy the Architect plan with no extraneous code.

## Verification

Manual verification performed:

- ✅ Confirmed git status shows clean branch with only expected changes
- ✅ Reviewed migration SQL — correct parameter addition, DROP prevents overload errors, duration changed to COALESCE, BPM/Key conditionally check overwrite flag
- ✅ Verified repository change adds exactly one param to enrichSongs() RPC call
- ✅ Verified orchestrator fixes both needsDuration occurrences with same logic pattern
- ✅ Verified UI removes hardcoded false and updates user-facing text accurately
- ✅ Confirmed dart format applied successfully (1 file reformatted)

## Deviations From Architect Plan

Post-implementation fix (QA/Manager review):

- Added `REVOKE ALL ON FUNCTION update_song_metadata(...) FROM PUBLIC, anon;` before GRANT in migration
- Reason: DROP+CREATE undoes the ACL lockdown from 20260822120005_revoke_anon_batch_6_song_metadata.sql
- Per GUARDRAILS.md §4: PostgreSQL grants EXECUTE to PUBLIC by default; every CREATE FUNCTION must pair explicit REVOKE with GRANT
- Pattern matches 20260822120005 with updated 12-param signature

All other implementation matches the plan exactly:

- Single combined migration with explicit DROP
- Duration fix incorporated (COALESCE for all callers)
- Repository adds p_allow_enrich_overwrite: true
- Orchestrator fixes both duration checks
- UI enables overwriting with updated subtitle
- Manual-edit call sites unchanged (not listed in plan, correctly omitted)
- getsongbpm_lookup/ directory not touched (off-limits per plan)

## Blockers Encountered

None

## Ready For QA

Yes

All Architect tasks completed successfully. Flutter analyze passes with 0 errors. Changes follow existing patterns and introduce no bloat. Implementation is minimal, targeted, and complete per the plan.
