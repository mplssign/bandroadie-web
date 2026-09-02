# ENGINEER REPORT: `song-metadata-override`

**Feature Slug:** song-metadata-override  
**Feature Title:** Song key/tempo manual changes overwritten by web enrichment  
**Cycle Number:** 1  
**Branch:** bug/song-metadata-override  

---

## Goal

Fix two compounding bugs in the song metadata write path:

- **Bug 1 (primary):** Enrichment unconditionally overwrites user-set BPM and musical key values.
- **Bug 2 (secondary, regression):** Manual edits to BPM/key silently fail when the song already has a value (fill-missing-only semantics were applied to what should be an always-write path).

---

## Architect Tasks Completed

All 5 tasks completed in order:

1. Migration: add `bpm_manual_override` / `musical_key_manual_override` columns to `songs`.
2. Migration: rewrite `update_song_metadata` (flag-aware write logic + Bug 2 fix) and `clear_song_metadata` (reset flags on field clear).
3. Flutter: `Song` model gains two boolean fields with defaults and `fromSupabase` parsing.
4. Flutter: `fetchSongsForBand` column select extended with the two new columns.
5. Flutter: orchestrator `needsBpm` / `needsKey` filter guards added at both occurrences (pre-filter and per-song early-exit check).

---

## Files Created

| File | Purpose |
|---|---|
| `supabase/migrations/20260902120000_add_manual_override_flags.sql` | ADD two boolean columns to `songs` |
| `supabase/migrations/20260902120001_fix_update_song_metadata_manual_override.sql` | Rewrite `update_song_metadata` and `clear_song_metadata` with flag awareness |

---

## Files Modified

| File | Change |
|---|---|
| `lib/features/setlists/models/song.dart` | Added `bpmManualOverride`, `musicalKeyManualOverride` fields + constructor defaults + `fromSupabase` parsing |
| `lib/features/setlists/setlist_repository.dart` | Added `bpm_manual_override, musical_key_manual_override` to `fetchSongsForBand` column select |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | Added `!song.bpmManualOverride` / `!song.musicalKeyManualOverride` guards to both `needsBpm`/`needsKey` sites (pre-filter and per-song loop) |

---

## Analyzer Results

```
Analyzing bandroadie...
No issues found! (ran in 5.8s)
```

Zero errors, zero new warnings.

---

## Test Results

No tests run — the plan does not require it and there is no existing coverage for the changed area. Tier 2 verification tests described in the plan require a live Supabase instance and are a QA responsibility.

---

## Code Efficiency / Bloat Check

- No unused imports, variables, or parameters introduced.
- No dead or unreachable code added.
- No wrapper abstractions — all changes are direct, inline modifications.
- No defensive null-checks beyond what the plan specifies (`COALESCE(v_before_bpm_override, FALSE)` is required because the BEFORE snapshot SELECT uses `INTO` which could leave the variable NULL if the row is not found — though the function already guards for that case earlier; the COALESCE is consistent with the plan and defensive in the SQL sense only).
- `enrichment_selector_bottom_sheet.dart` and all `setlist_songs` code untouched per plan.
- `updateSongBpmOverride` / `updateSongMusicalKey` repository methods untouched — they already omit `p_allow_enrich_overwrite` (defaults to FALSE), which now means always-write + set flag; no code change needed.

---

## Verification (Manual Steps Performed)

- Confirmed branch is `bug/song-metadata-override` with a clean tree (only untracked docs/ files).
- Read the full ARCHITECT_PLAN.md before writing a single line of code.
- Confirmed existing `update_song_metadata` 12-param signature in migration `20260827183550`; new migration uses `CREATE OR REPLACE FUNCTION` with the identical signature — no DROP needed, no PGRST203 risk.
- Confirmed existing `clear_song_metadata` 6-param signature; new migration preserves it identically.
- Confirmed both occurrences of `needsBpm`/`needsKey` in the orchestrator were updated (pre-filter `where` closure at line ~127 and per-song loop at line ~153).
- `flutter analyze` → 0 issues before and after `dart format`.
- `dart format` — 2 of 3 changed files required reformatting; all now clean.

---

## Deviations From Plan

None. All implementation matches the plan exactly, including:
- DECLARE section additions (`v_before_bpm_override`, `v_before_key_override`, `v_bpm_write_eligible`, `v_key_write_eligible`).
- Extended BEFORE snapshot SELECT to include the two new flag columns.
- Eligibility computed before UPDATE using the plan's boolean expressions.
- UPDATE SET clause uses `v_bpm_write_eligible`/`v_key_write_eligible` for write gating.
- Verification section uses `v_bpm_write_eligible`/`v_key_write_eligible` (not the old `v_before_bpm IS NULL` pattern).
- REVOKE/GRANT re-asserted idempotently for both functions.

---

## Blockers Encountered

None.

---

## Ready For QA

**Yes.**

Tier 1 verification queries (read-only schema/grant checks) and Tier 2 transaction-wrapped RPC tests from the plan are ready to run against the deployed migration.
