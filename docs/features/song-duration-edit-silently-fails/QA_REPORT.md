# QA Report

## Feature Slug

bug/song-duration-edit-silently-fails

## QA Agent Session Date

2026-08-27

## Overall Verdict

**PASS — with pre-commit condition**

The implementation is correct, minimal, and safe to commit once the required manual authenticated-UI verification (see Pre-Commit Condition below) has been completed by Tony.

---

## Phase 1 — Workspace Verification

- Branch: `bug/song-duration-edit-silently-fails` ✓
- Working tree: clean except for expected feature files (no staged changes; all three new files are untracked) ✓

Untracked files present:
- `docs/features/song-duration-edit-silently-fails/ARCHITECT_PLAN.md`
- `docs/features/song-duration-edit-silently-fails/ENGINEER_REPORT.md`
- `supabase/migrations/20260827120000_fix_song_duration_write_once.sql`

`git diff HEAD` output: empty. No existing tracked files were modified.

---

## Phase 2 — Document Resolution

- ARCHITECT_PLAN.md: found at correct slug path ✓
- ENGINEER_REPORT.md: found at correct slug path ✓
- Feature slug in both documents: `bug/song-duration-edit-silently-fails` — exact match ✓
- Both documents refer to the same feature (duration write-once silent failure in `update_song_metadata`) ✓

---

## Phase 3 — Validation Baseline (Extracted from Architect Plan)

**Problem:** `update_song_metadata` RPC uses a fill-missing-only CASE guard on `duration_seconds`, silently returning `success: true` when the caller attempts to overwrite a non-zero value. Root cause confirmed at HIGH confidence.

**Expected behavior after fix:** Non-null `p_duration_seconds` always overwrites the stored value regardless of its current magnitude. False success eliminated: if the update does not persist, the function returns `success: false` with an explicit error.

**Files expected to change:**
- `supabase/migrations/20260827120000_fix_song_duration_write_once.sql` (new migration — only Dart-independent SQL change)
- `docs/features/song-duration-edit-silently-fails/ARCHITECT_PLAN.md` (plan document)

**Files explicitly off-limits:**
- `lib/features/setlists/setlist_detail_controller.dart`
- `lib/features/setlists/setlist_repository.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/main.dart`
- `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql`

**Database impact:** New migration replacing `update_song_metadata` function logic for `duration_seconds` only; signature unchanged; no schema or RLS changes.

**System impact:** Setlists/Catalog (affected); all other systems (unaffected).

---

## Phase 4 — Engineer Implementation Review

**Scope adherence:** 

Three untracked files only — the two plan documents and the migration. `git diff HEAD` is empty; no existing tracked files were modified. Change surface is exactly as approved.

**Off-limits files:**

| File | Touched? |
|---|---|
| `lib/features/setlists/setlist_detail_controller.dart` | No ✓ |
| `lib/features/setlists/setlist_repository.dart` | No ✓ |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | No ✓ |
| `lib/main.dart` | No ✓ |
| `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` | No ✓ |

**Migration filename:** `20260827120000_fix_song_duration_write_once.sql` — matches Architect specification exactly ✓

**Noted deviation (non-blocking):** The Supabase migration ledger recorded the applied version as `20260827053914` (UTC wall-clock at apply time) instead of `20260827120000` (filename prefix). The local file on disk is named correctly. The function content and deployment are confirmed correct. This is a ledger cosmetic discrepancy with no functional consequence.

---

## Phase 5 — Completeness Check

| Task | Status | Notes |
|---|---|---|
| Task 1 — Create migration with corrected `duration_seconds` semantics, 11-parameter signature preserved | ✓ Complete | Signature confirmed: `p_song_id, p_band_id, p_bpm, p_duration_seconds, p_tuning, p_notes, p_title, p_artist, p_youtube_links, p_lyrics, p_musical_key` |
| Task 2 — Remove `v_before_duration = 0` gate from verification logic | ✓ Complete | Verification now: `IF p_duration_seconds IS NOT NULL THEN IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN` — no eligibility gate |
| Task 3 — ACL and security model preserved | ✓ Complete | `SECURITY DEFINER`, `SET search_path = public`, `GRANT EXECUTE TO authenticated` all present |
| Task 4 — Pre-deploy and post-deploy SQL verification executed | ✓ Complete (Engineer-reported) | Tier 1 confirmed bug present pre-migration; Tier 2 confirmed corrected logic post-migration |
| Task 5 — BPM/musical_key limitation documented as separate follow-up | ✓ Complete | Neither field touched; no migration-scope broadening |

No skipped requirements. No partial implementations. No missing edge-case handling.

---

## Phase 6 — Behavior Verification

**Root cause addressed:** Confirmed in code. The buggy line:

```sql
duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0
                        THEN p_duration_seconds ELSE duration_seconds END
```

is replaced with:

```sql
duration_seconds = COALESCE(p_duration_seconds, duration_seconds)
```

`COALESCE(p_duration_seconds, duration_seconds)` writes `p_duration_seconds` whenever it is non-null, regardless of the current stored value. The false-success path is also closed: the verification block no longer gates on `v_before_duration = 0`, so a COALESCE write that somehow didn't persist would return `success: false` with an explicit error message.

**Validation method:** Code-path analysis (direct SQL comparison of old migration vs. new migration) and the Engineer-reported Tier 2 post-deploy function-definition check (`pg_get_functiondef` returning `true` for the corrected COALESCE expression). The prior migration was also read in full and compared line-by-line to confirm all other field semantics are unchanged.

**This was NOT validated via runtime UI testing.** No device automation tooling is available to this agent. The end-to-end authenticated path — app sign-in → Song Details UI → edit duration from non-zero to a different non-zero value → Save → force-reload → confirm persistence — has not been exercised by any agent in this session.

---

## Pre-Commit Condition (Required — Not a Blocking Issue Against This Implementation)

The implementation is correct and the database fix is independently confirmed. However, the following manual check must be completed by **Tony** before the Manager authorizes the commit:

> **Required end-to-end authenticated-UI check:**
> 1. Sign in as a band member of Banditos / Audioglow band (the originally reported bug band).
> 2. Open the Song Details UI for a song with a non-zero current duration.
> 3. Edit the duration to a different non-zero value and tap Save.
> 4. Force-reload the app or navigate away and back to the same song.
> 5. Confirm the new duration value persists in the UI.
>
> This is the only validation that exercises the RPC's auth guard, band-membership check, and database write together in the correct call path. No SQL-only query or code-path analysis can substitute for it.

This is listed as a pre-commit condition for Tony, not a REQUIRES CHANGES verdict against the Engineer, because the fix itself is correct and the root cause is independently confirmed. Per session instructions, the Manager will authorize the commit after this check passes.

---

## Phase 7 — Regression Check

**Regression risk: MEDIUM** (consistent with Architect's assessment)

| System | Check | Result |
|---|---|---|
| Setlists / Catalog | Duration write from zero → non-zero | Still works: `COALESCE(non-null, 0)` = `non-null` ✓ |
| Setlists / Catalog | Duration write from non-zero → non-zero | Now works (bug fix) ✓ |
| Setlists / Catalog | Duration not provided (NULL) | Preserved: `COALESCE(NULL, duration_seconds)` = existing value ✓ |
| BPM field | Fill-missing-only behavior | Unchanged: `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL` identical to prior migration ✓ |
| Tuning field | Always-overwrite behavior | Unchanged: `COALESCE(p_tuning, tuning)` identical to prior migration ✓ |
| Musical key field | Fill-missing-only behavior | Unchanged: `CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '')` identical ✓ |
| Notes / Title / Artist / YouTube / Lyrics | All field behaviors | Unchanged: verified line-by-line against prior migration ✓ |
| Auth / Session | `auth.uid()` check | Unchanged ✓ |
| Band membership check | `band_members` query | Unchanged ✓ |
| Song band ownership check | `v_song_band_id != p_band_id` | Unchanged ✓ |
| Initialization order | Untouched | Not applicable — no Dart changes ✓ |
| Controller / FocusNode disposal | Untouched | Not applicable — no Dart changes ✓ |

No regressions identified.

---

## Phase 8 — Database Safety

- **Migration matches Architect plan:** ✓ — function body corrects `duration_seconds` semantics; all other fields, signature, and security model unchanged
- **RLS impact:** None — this is a SECURITY DEFINER function change; no RLS policies added, modified, or removed
- **Privilege escalation:** None
- **Cascade / destructive behavior:** None — function returns JSON success/failure; no cascades
- **RPC signature:** Unchanged (11 parameters); PostgREST overload ambiguity risk is zero
- **Migration content matches claimed behavior:** Confirmed by direct code read

**ACL safety:**

The new migration includes `GRANT EXECUTE ON FUNCTION update_song_metadata TO authenticated` but no `REVOKE`. This is consistent with the established pattern in this codebase:

- `20260822120005_revoke_anon_batch_6_song_metadata.sql` contains the full `REVOKE ALL ON FUNCTION update_song_metadata(...) FROM PUBLIC, anon` for the exact 11-parameter signature now in use. This migration runs before the new one in chronological order.
- `CREATE OR REPLACE FUNCTION` preserves existing grants; the REVOKE from `20260822120005` is still in effect after the replacement.
- The prior migration (`20260811120001`) followed the same pattern (GRANT only, no REVOKE in the same file) and was accepted.

Effective ACL after new migration: `PUBLIC` and `anon` have no EXECUTE (from `20260822120005`, preserved); `authenticated` has EXECUTE (from GRANT in new migration). ✓

---

## Phase 9 — Analyzer Results

Command run: `flutter analyze`

```
8 issues found. (ran in 4.3s)
```

- 0 errors ✓
- 8 pre-existing info/warning items — identical to Engineer's reported count:
  - `reorderable_song_card.dart:187` — `sized_box_for_whitespace` (info)
  - `song_card.dart:113` — `sized_box_for_whitespace` (info)
  - `main.dart:62,88` — `deprecated_member_use` for `anonKey` (info, ×2)
  - `test/components/ui/app_text_field_test.dart:312,416,438` — `unused_local_variable` (warning, ×3)
  - `test/components/ui/app_text_form_field_test.dart:326` — `unused_local_variable` (warning, ×1)
- None of these are in files touched by this implementation ✓
- No new issues introduced ✓

Tests: Not run. No Dart files were modified. The Architect plan does not require Flutter tests. The Engineer report confirms no relevant test coverage exists for server-side RPC logic.

---

## Phase 10 — Diff Safety Review

| Check | Result |
|---|---|
| Secrets or API keys | None ✓ |
| Environment variables outside approved scope | None ✓ |
| Debug artifacts (print statements, TODO hacks, temp flags) | None ✓ |
| Test scaffolding in production code | None ✓ |
| Accidental file deletions | None ✓ |

---

## Bloat Check (GUARDRAILS §7a)

The Engineer correctly identified and removed bloat relative to the prior migration:

- `v_before_duration INTEGER` removed from DECLARE — no longer needed ✓
- `SELECT` narrowed from `bpm, duration_seconds, musical_key` to `bpm, musical_key` — `duration_seconds` no longer needs a before-snapshot ✓
- Three-level nested `IF p_duration_seconds … IF v_before_duration = 0 … IF v_new_duration IS DISTINCT FROM` flattened to two levels — the outer `= 0` guard was the bug and is correctly removed ✓
- Added `COMMENT ON FUNCTION` — appropriate documentation; not bloat ✓

No dead code, unused declarations, redundant comments, or unnecessary abstractions in the migration.

---

## Summary

| Area | Verdict |
|---|---|
| Scope adherence | PASS |
| Off-limits files | PASS |
| Completeness | PASS |
| Behavior verification | PASS (code-path analysis + function-definition diff; no runtime UI test) |
| Regression check | PASS — MEDIUM risk, no regressions identified |
| Database safety | PASS |
| ACL / security model | PASS |
| Analyzer | PASS — 0 errors, 8 pre-existing items, no new issues |
| Bloat / code efficiency | PASS |
| Diff safety | PASS |

**Overall: PASS — with required pre-commit manual UI check by Tony (see Pre-Commit Condition section).**
