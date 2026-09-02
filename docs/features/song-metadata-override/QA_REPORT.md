# QA REPORT: `song-metadata-override`

**Feature Slug:** song-metadata-override  
**Feature Title:** Song key/tempo manual changes overwritten by web enrichment  
**Cycle Number:** 2  
**Branch:** bug/song-metadata-override  
**QA Date:** 2026-09-02  

---

## Final Verdict

**APPROVED**

All Architect tasks are complete, all plan-approved files match the implementation, off-limits files are untouched, `flutter analyze` passes with 0 issues, and the sole C1 blocker (DB grant verification for `update_song_metadata` and `clear_song_metadata`) is resolved by Manager-provided live-DB results from `supabase db query --linked`.

---

## C1 Blocker Resolution

The only `REQUIRES CHANGES` finding from Cycle 1 was inability to run `has_function_privilege` against a live DB (Docker unavailable locally). The Manager has now supplied results from the remote project via `supabase db query --linked`:

| Function | `auth_exec` | `anon_exec` | Expected |
|---|---|---|---|
| `update_song_metadata` | `true` | `false` | auth=TRUE, anon=FALSE ✓ |
| `clear_song_metadata` | `true` | `false` | auth=TRUE, anon=FALSE ✓ |

T1-5 and T1-6 from the Architect verification plan: **PASS**. No other changes were made between C1 and C2; the implementation is identical. The migration uses `CREATE OR REPLACE FUNCTION` (preserves OID-based grants) plus explicit idempotent REVOKE/GRANT re-assertion, which is consistent with the correct live-DB state.

---

## Regression Risk

**MEDIUM** (per Architect plan, upheld). The `update_song_metadata` RPC semantic change for `p_allow_enrich_overwrite=FALSE` is a deliberate fix. All other callers pass `p_bpm=NULL` / `p_musical_key=NULL`, so the new always-write path is unreachable for them. Runtime verification (T2-1 through T2-7) remains pending deployment.

---

## Validation Summary

| Check | Result |
|---|---|
| Branch is `bug/song-metadata-override` | PASS |
| Working tree matches expected state (uncommitted; only plan-approved files) | PASS |
| Slugs in plan, report, and branch all match | PASS |
| All 5 Architect tasks complete | PASS |
| Off-limits files untouched | PASS |
| `flutter analyze` — 0 errors, 0 new warnings | PASS |
| Flutter test run | NOT RUN (plan does not require; no coverage for changed area) |
| DB grant verification — `has_function_privilege` for both RPCs (T1-5, T1-6) | PASS (live DB via `supabase db query --linked`) |
| No secrets, debug artifacts, or unrelated churn | PASS |
| No out-of-scope changes | PASS |

---

## Architect Scope Review

Plan slug `song-metadata-override`, report slug `song-metadata-override`, branch `bug/song-metadata-override` — all consistent.

All files to create and modify in the plan are present in the diff. All files declared off-limits show no diff hunk:
- `enrichment_selector_bottom_sheet.dart` — not touched ✓
- `updateSongBpmOverride` / `updateSongMusicalKey` — not touched ✓
- `enrichSongs` (the RPC call site) — not touched ✓
- `SetlistSong` model — not touched ✓
- `main.dart`, auth, routing, Firebase — not touched ✓

No unapproved architectural changes. No unrelated formatting churn beyond `dart format` normalization on the two Dart files that needed it (expected; not substantive).

---

## Completeness Check

All 5 tasks complete per diff evidence:

1. **Migration `20260902120000`** — `ADD COLUMN IF NOT EXISTS bpm_manual_override BOOLEAN NOT NULL DEFAULT FALSE` and `musical_key_manual_override` with COMMENT on both. Matches plan verbatim. ✓  
2. **Migration `20260902120001`** — `CREATE OR REPLACE FUNCTION update_song_metadata` (12-param, same signature) with DECLARE additions (`v_before_bpm_override`, `v_before_key_override`, `v_bpm_write_eligible`, `v_key_write_eligible`), extended BEFORE SELECT, eligibility computation before UPDATE, correct UPDATE SET clause, eligibility-aware verification section, idempotent REVOKE/GRANT. `CREATE OR REPLACE FUNCTION clear_song_metadata` (6-param, same signature) with override-flag resets in UPDATE SET, idempotent REVOKE/GRANT. Both match plan. ✓  
3. **`Song` model** — `bpmManualOverride` and `musicalKeyManualOverride` fields added with `= false` defaults in constructor and `json['bpm_manual_override'] as bool? ?? false` parsing. Matches plan. ✓  
4. **`setlist_repository.dart` / `fetchSongsForBand`** — `bpm_manual_override, musical_key_manual_override` appended to the column select. Only this query touched; `SetlistSong` queries unmodified. ✓  
5. **`song_enrichment_orchestrator.dart`** — Override guards added at **both** occurrences: pre-filter `where` closure (line ~125) and per-song early-exit check inside the loop (line ~151). Both `needsBpm` and `needsKey` updated at each site. Matches plan. ✓

---

## Behavior Verification

*Method: code-path analysis. Runtime-exercised verification not performed (no live DB, no device test).*

**Bug 1 fix (enrichment overwrites user-set values):**  
- `v_key_write_eligible` / `v_bpm_write_eligible` gate the UPDATE when `p_allow_enrich_overwrite=TRUE`: write proceeds only if `NOT COALESCE(v_before_bpm_override, FALSE)` is TRUE. Flag-set songs receive a no-op UPDATE and a `{success: true}` return. Code-path analysis confirms correct behavior.  
- Orchestrator guards `!song.bpmManualOverride` / `!song.musicalKeyManualOverride` short-circuit enrichment client-side before the RPC is even called, so locked songs report `EnrichmentFieldResult.unchanged` instead of `updated`. Confirmed at both orchestrator sites.

**Bug 2 fix (manual edits of existing BPM/key silently dropped):**  
- Old path: `bpm = CASE WHEN p_bpm IS NOT NULL AND (p_allow_enrich_overwrite OR bpm IS NULL) THEN p_bpm ELSE bpm END` — evaluates FALSE when `p_allow_enrich_overwrite=FALSE` and `bpm IS NOT NULL`.  
- New path: `v_bpm_write_eligible := p_bpm IS NOT NULL AND (NOT p_allow_enrich_overwrite OR ...)` — evaluates TRUE for any non-NULL `p_bpm` on the manual-edit path. Correct.

**Edge case — musical_key empty string:** Previous migration included `OR TRIM(musical_key) = ''` in the enrichment condition. New migration omits this. This is safe: songs with `musical_key=''` have `musical_key_manual_override=FALSE` (default), so enrichment writes to them via `NOT COALESCE(FALSE, FALSE) = TRUE`. Manual edits to empty-string keys also succeed via the always-write path. No regression.

**Flag lifecycle confirmed by code-path analysis:**  
- Manual edit (`p_allow_enrich_overwrite=FALSE`) with non-NULL BPM/key → flag set TRUE ✓  
- Enrichment → flag never set (only the write is conditional; flag-set branch requires `NOT p_allow_enrich_overwrite`) ✓  
- `clear_song_metadata(p_clear_bpm=TRUE)` → `bpm=NULL`, `bpm_manual_override=FALSE` ✓

---

## Regression Check

| Regression Area | Risk | Finding |
|---|---|---|
| Manual BPM/key edit (existing value) | HIGH — was broken | Fixed by Bug 2 path change. Code-path verified. |
| Manual BPM/key edit (null value) | LOW | `v_bpm_write_eligible = TRUE` for any non-NULL `p_bpm` with `p_allow_enrich_overwrite=FALSE`. No regression. |
| Enrichment (unlocked songs) | MEDIUM | `bpm_manual_override=FALSE` for all existing songs. Flag check = FALSE → write eligible. No disruption at deploy time. |
| Enrichment (locked songs — new state) | MEDIUM | Correctly skipped at both orchestrator and RPC level. Verified by code-path. |
| `clear_song_metadata` | LOW | New flag columns added to UPDATE; no existing fields changed. |
| Duration/tuning write path | LOW | Unchanged — `COALESCE(p_duration_seconds, duration_seconds)` / `COALESCE(p_tuning, tuning)`. No flags for these fields. ✓ |
| `upsertExternalSong` | LOW | Does not use `update_song_metadata`; unaffected. ✓ |
| Songs with NULL band_id (legacy) | LOW | `SECURITY DEFINER SET search_path = public` unchanged on both RPCs. ✓ |
| Auth/session/routing | NONE | Not touched. ✓ |
| Platform parity (iOS/Android/macOS/Web) | LOW | No platform-conditional code. All platforms use same Flutter + Supabase RPC path. ✓ |
| Controller/FocusNode disposal | NONE | No new widgets, controllers, or FocusNodes. ✓ |
| setState after async gaps | NONE | No widget state changes. ✓ |
| Init order | NONE | `main.dart` not touched. ✓ |

Overall regression risk: **MEDIUM** (consistent with Architect assessment; driven by the `update_song_metadata` semantic change and enrichment skip logic).

---

## Database Safety

### Schema Change
`ADD COLUMN IF NOT EXISTS` with `NOT NULL DEFAULT FALSE` — safe, non-destructive. All existing rows default to `FALSE`. Enrichment behavior unchanged at deploy time. No indexes required per plan. ✓

### RPC Signatures
- `update_song_metadata`: 12-param signature unchanged (verified against `20260827183550`). `CREATE OR REPLACE` without DROP — no PGRST203 risk. ✓  
- `clear_song_metadata`: 6-param signature unchanged (verified against `20260822120005` and `20260811120002`). ✓  

### REVOKE/GRANT Statements
Both RPCs include:
```sql
REVOKE ALL ON FUNCTION <fn>(positional types) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION <fn>(positional types) TO authenticated;
```
These match the signatures used in previous migrations. Idempotent re-assertion is the correct pattern.

### Grant Verification — PASS

Verified against the live remote DB via `supabase db query --linked` (Manager-provided, Cycle 2):

| Function | `authenticated` EXECUTE | `anon` EXECUTE | Result |
|---|---|---|---|
| `update_song_metadata` | `true` | `false` | ✓ PASS (T1-5) |
| `clear_song_metadata` | `true` | `false` | ✓ PASS (T1-6) |

The migration uses `CREATE OR REPLACE FUNCTION`, which preserves the existing OID-based grants in PostgreSQL. The idempotent REVOKE/GRANT statements in the migration additionally re-assert this state explicitly. Grant state is correct.

No self-referencing RLS, no privilege escalation, no destructive cascades. RPC signatures match all client call sites confirmed in existing code.

---

## Analyzer Results

```
Analyzing bandroadie...
No issues found! (ran in 4.3s)
```
Independently verified. 0 errors, 0 new warnings.

---

## Test Results

No tests run. The Architect plan does not require it, and the Engineer confirms no existing coverage for this area. Runtime Tier 2 tests (T2-1 through T2-7) are a post-deploy QA responsibility and require a live Supabase instance.

---

## Diff Safety Review

- No secrets or API keys ✓  
- No debug artifacts (`print`, `debugPrint` additions, etc.) ✓  
- No leftover test scaffolding ✓  
- No accidental deletions ✓  
- No unrelated churn beyond `dart format` normalization ✓  
- No unapproved files modified ✓  

---

## Code Efficiency Review

- No dead code or unused imports introduced ✓  
- No single-call-site wrappers or unnecessary abstractions ✓  
- `COALESCE(v_before_bpm_override, FALSE)` in SQL: defensive only; the row-not-found guard earlier in the function makes the NULL case unreachable, but this COALESCE is specified by the plan and consistent with SQL defensive practice — not a bloat concern ✓  
- Both `needsBpm`/`needsKey` sites in the orchestrator updated inline — no helper extracted for a two-line change ✓  
- All three Dart changes are minimal, direct edits matching the plan's exact before/after specification ✓  

---

## Issues Found

### Critical

None.

---

### Warnings

None.

---

### Suggestions

None.

---

## C1 Issue Closure

**C1 — database-safety — DB grant verification (resolved)**  
Previously REQUIRED CHANGES in Cycle 1 because `has_function_privilege` checks (T1-5, T1-6) could not be run without a local DB instance. The Manager ran both queries against the remote project via `supabase db query --linked` and supplied the results. Both functions return `auth_exec=true, anon_exec=false`. This is the required result per the Architect plan. **Issue closed.**
