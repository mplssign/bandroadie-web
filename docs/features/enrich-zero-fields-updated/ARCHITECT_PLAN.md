# ARCHITECT_PLAN.md

## 0. Changelog (v5)

**Root cause correction (Tony's device test reproduced the issue, independent evidence confirmed):**

The v4 root cause diagnosis was incorrect. The migration (`20260801000003...`) is confirmed live in production and functioning correctly via independent SQL verification. The actual root cause for the device test failure was:

- This branch was created before `bug/song-details-save-clears-enriched-fields` merged to `main` (commit 72a8ab2).
- `_refreshAndRebaselineMetadata` and `_didCurrentSongMetadataUpdate` methods did not exist in this branch's `song_details_bottom_sheet.dart`.
- When Tony tested enrichment on device, the results overlay showed "Updated" correctly, but the form didn't refresh because the rebaseline mechanism was missing from the build.
- The migration was working, but the UI refresh mechanism wasn't present to reflect the changes.

**Resolution:**

- Merged `origin/main` into this branch (fast-forward merge, no conflicts).
- Verified both methods (`_refreshAndRebaselineMetadata`, `_didCurrentSongMetadataUpdate`) are now present.
- Traced the full enrichment path end-to-end: orchestrator detects blank key → RPC called → migration fills it → RPC returns success → orchestrator marks as `updated` → `_didCurrentSongMetadataUpdate` returns true → `_refreshAndRebaselineMetadata` fetches new value and updates form.
- All v4 scope additions related to "merging hazard" and "value-level verification" are now moot — the merge resolved the issue without requiring new code.
- Migration deployment sequencing is still critical: this migration must remain live before any future changes to this area.

**Scope changes:**

- Removed: v4 scope additions (post-RPC value verification, post-enrichment confirmation message, deployment gates).
- Retained: All v3 scope (client normalization, migration for blank key handling, observability improvements).

## 0. Changelog (v4)

**New regression discovered via live device testing (iOS/macOS):**

After single-song enrichment from Song Details, the results overlay correctly shows "Updated" status for enriched fields, but dismissing the overlay reveals the form still displays pre-enrichment values (old BPM/Duration/Key). Save button remains disabled. No visible confirmation that data was persisted.

**Root cause confirmed:**

The interaction between:

1. Main's `_refreshAndRebaselineMetadata` fix (from `bug/song-details-save-clears-enriched-fields`, commit 72a8ab2, already merged to main)
2. This branch's broadened orchestrator predicates (`_isMissingBpm`, `_isMissingDuration`, `_isMissingKey`)
3. Current main RPC fill conditions (which don't yet have this branch's musical_key alignment migration)

Creates a scenario where:

- Orchestrator classifies field as needing enrichment (new predicates: `bpm <= 0`, `key blank/whitespace`)
- Provider returns value, RPC is called
- RPC doesn't update DB (main's fill condition: `bpm IS NULL`, `musical_key IS NOT NULL` without blank guard)
- But RPC returns `success: true` (PostgreSQL ROW_COUNT reflects row match, not value change)
- Orchestrator marks field as `EnrichmentFieldResult.updated`
- Main's `_refreshAndRebaselineMetadata` runs, fetches DB → gets unchanged value
- Local form state is set to old value, even though results overlay showed "Updated"

This is a **merging hazard**: when this branch merges to main, the existing fix will break for songs with blank musical_key (and any future `bpm = 0` edge cases, though none exist per evidence).

**Scope additions:**

1. Ensure this branch's migration deploys BEFORE merge to main, so RPC alignment is live when orchestrator predicates broaden.
2. Add explicit value-level verification in orchestrator: after RPC success, confirm DB field actually changed (not just ROW_COUNT > 0).
3. Add minimal post-enrichment user confirmation: brief inline message confirming data saved (not just disabled Save button).

## 0. Changelog (v3)

- Resolved the §3 Scope Decision Gate with runtime evidence from production-like data:
  - No rows with `bpm = 0` were found.
  - Rows with missing key used blank/whitespace `musical_key`, not `NULL`.
  - `duration_seconds` sentinel behavior remains `0` as already handled by RPC.
- Narrowed database change scope from potential BPM+key RPC alignment to key-only RPC alignment.
- Confirmed BPM RPC fill condition (`bpm IS NULL`) should remain unchanged.
- Kept defensive client-side missing-value normalization (`bpm null/<=0`, key null/blank, duration <=0`) because it is harmless and matches UI semantics.
- Retained value-level verification requirement: DB field changes must be proven, not inferred from RPC `success: true`.

## 0. Changelog (v2)

- Revised DB-impact analysis to account for actual RPC fill conditions in `update_song_metadata` (`bpm IS NULL`, `musical_key IS NULL`, `duration_seconds = 0`).
- Added mandatory evidence gate to classify real production sentinel values for BPM/key (`NULL` vs `0`/blank) on representative songs before final implementation scope is locked.
- Introduced conditional implementation scope:
  - Client-only fix path if sentinel values are truly `NULL`.
  - Coordinated client + RPC migration path if sentinel values are `0`/blank for BPM/key.
- Added explicit verification requirement that RPC `success: true` must correlate with an actual DB value change for the targeted field(s), not just row-match success.

## 1. Feature Slug

`bug/enrich-zero-fields-updated`

---

## 2. Problem Summary

**Primary issue (catalog-wide and single-song):**

Existing-song enrichment reports `0 of 36 songs enriched` from both entry points (catalog-wide and per-song), while also reporting `19 songs not recognized`. That means 17 songs were neither counted as enriched nor counted as provider not recognized, and no write-success feedback reached the user.

Code-path review shows enrichment wiring is active in both entry points and both call the same orchestrator (`SongEnrichmentOrchestrator.enrichSongs`). The failure is therefore likely in shared orchestration eligibility logic and/or result classification, not in UI wiring.

**Secondary issue (merging hazard with main):**

Main has a `_refreshAndRebaselineMetadata` fix (commit 72a8ab2, merged) that refreshes Song Details form state after enrichment by fetching from DB. This assumes `EnrichmentFieldResult.updated` means the database was actually changed. When this branch's broadened predicates merge to main WITHOUT the RPC alignment migration deployed first, the form will refresh to stale DB values for songs with blank musical_key, creating user-visible regression where enrichment appears successful but form doesn't update.

---

## 3. Root Cause

### Primary diagnosed cause (code-level):

The orchestrator treats some placeholder values as "already filled" and skips update attempts:

- BPM is only considered missing when `song.bpm == null`
- Key is only considered missing when `song.musicalKey == null`
- Duration is considered missing only when `song.durationSeconds == 0`

But UI semantics already treat additional placeholder states as missing (for example BPM `<= 0`, key empty string/whitespace). This can produce songs that visibly look missing to users but are skipped as unchanged by orchestration.

### Additional diagnosed mismatch (client vs RPC fill semantics):

The current RPC `update_song_metadata` applies stricter fill conditions than the proposed client normalization:

- BPM updates only when current `bpm IS NULL`.
- Musical key updates only when current `musical_key IS NULL`.
- Duration updates when current `duration_seconds = 0`.

Runtime evidence resolved this as a mixed case:

- BPM sentinel in real data is `NULL` (not `0`), so existing RPC BPM fill condition is already aligned.
- Musical key sentinel in real data is blank/whitespace (not `NULL`), so existing RPC key fill condition is not aligned.

This means only musical key can still hit `success: true` without a value change when the current value is blank/whitespace and the RPC gate remains `musical_key IS NULL`.

### Tertiary diagnosed cause (merging hazard with main's refresh fix):

Main's `_refreshAndRebaselineMetadata` method (added in `bug/song-details-save-clears-enriched-fields`) fetches DB values after enrichment to update local form state. It relies on `_didCurrentSongMetadataUpdate(result)` which checks for `EnrichmentFieldResult.updated`.

When this branch's broadened predicates classify a field as "missing" (e.g., blank musical_key), but the RPC doesn't update it (because main's RPC still has `musical_key IS NULL` guard without blank handling), the RPC still returns `success: true` (PostgreSQL ROW_COUNT reflects row match, not column value change). Orchestrator marks as `updated`, but DB value is unchanged. The refresh then fetches the old value, and the form displays stale data even though the results overlay showed "Updated".

**Critical deployment sequencing:** This branch's migration (`20260801000003_align_update_song_metadata_musical_key_blank_fill.sql`) MUST deploy before this branch merges to main. Otherwise, the merge will break the existing refresh fix.

### Secondary diagnosed cause (user-visible observability gap):

The results summary header only shows:

- enriched count
- not recognized count
- error count

It does not show unchanged/skipped count. This makes outcomes like `0 enriched, 19 not recognized, 17 unchanged` appear like unexplained write failures.

### Confidence

`HIGH` (updated from `MEDIUM` in v4)

Reason: code-path diagnosis is supported, runtime sentinel evidence gate is resolved with concrete SQL findings, **and the merging hazard with main's `_refreshAndRebaselineMetadata` fix is reproducible via live device testing (iOS/macOS).**

### Scope Decision Gate (resolved in v3, updated in v4)

Runtime evidence outcome:

- BPM: `NULL` sentinel only in real data (no `bpm = 0` rows found).
- Duration: `0` sentinel (already aligned with current RPC).
- Musical key: blank/whitespace sentinel in real data (misaligned with current RPC `musical_key IS NULL`).

Required fix scope:

- Client-side eligibility normalization and observability updates: required.
- RPC migration: required for musical key fill condition only.
- RPC BPM condition: unchanged.
- **New (v4):** Single-song enrichment form refresh compatibility: required (ensure main's `_refreshAndRebaselineMetadata` works correctly after merge).
- **New (v4):** Post-enrichment user feedback: minimal inline confirmation for single-song entry point.
- **New (v4):** Deployment sequencing: migration MUST deploy before branch merge to prevent breaking main's refresh fix.

---

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/features/existing-song-enrichment/ARCHITECT_PLAN.md`
- `docs/features/existing-song-enrichment/ENGINEER_REPORT.md`
- `docs/features/existing-song-enrichment/QA_REPORT_v5.md`
- **New (v4):** Main branch commit 72a8ab2 (merge of `bug/song-details-save-clears-enriched-fields` fix)

Code inspected:

- `lib/features/songs/services/song_enrichment_orchestrator.dart`
- `lib/features/songs/song_enrichment_service.dart`
- `lib/features/setlists/setlist_repository.dart`
- `lib/features/setlists/setlist_detail_screen.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/features/songs/widgets/enrichment_results_overlay.dart`
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
- `lib/features/setlists/models/song.dart`
- `supabase/functions/getsongbpm_lookup/index.ts`
- `supabase/migrations/20260801000002_redeploy_musical_key_duration_fill_missing.sql`
- **New (v4):** `origin/main:lib/features/setlists/widgets/song_details_bottom_sheet.dart` (inspected `_didCurrentSongMetadataUpdate` and `_refreshAndRebaselineMetadata` methods)
- **New (v4):** `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` (current main RPC behavior)

---

## 5. Existing System Analysis

Shared flow for both failing entry points:

1. UI entry point calls `SongEnrichmentOrchestrator.enrichSongs(...)`.
2. Orchestrator fetches band songs from repository.
3. For each song, orchestrator computes `needsBpm`, `needsDuration`, `needsKey`.
4. If needed, it calls:
   - `SongEnrichmentService.lookup(...)` for BPM/key
   - `ExternalSongLookupService.searchExternalSongs(...)` for duration
5. If any fields resolved, it calls `SetlistRepository.enrichSongs(...)`, which invokes RPC `update_song_metadata` with explicit params.
6. Orchestrator maps per-field status (`updated`, `notFound`, `unchanged`, `error`) and builds summary counts.
7. Results overlay displays enriched + not recognized + errors (unchanged is omitted from the summary header).

Important code observations:

- RPC wrapper is shared by both entry points, explaining identical behavior.
- RPC path already passes all parameters explicitly and handles `success=false`.
- If RPC were the dominant failure mode, summary should typically include error counts; Tony reported only not-recognized in summary.

---

## 6. Proposed Solution

The §15 evidence gate is resolved and implementation scope is now fixed (mixed outcome with merging-hazard mitigation).

Implement a coordinated, minimal fix:

1. Normalize missing-value detection in orchestrator:
   - BPM missing when `null` OR `<= 0`
   - Key missing when `null` OR empty/whitespace
   - Duration missing when `<= 0`
2. Improve results summary visibility so users can distinguish:
   - provider misses (`not recognized`)
   - unchanged/skipped
   - RPC/network errors
3. Add one new Supabase migration to align only the musical key fill condition in `update_song_metadata` with real sentinel usage (blank/whitespace).
4. Keep RPC BPM fill condition unchanged (`bpm IS NULL`), because runtime evidence shows no BPM `0` sentinel mismatch.
5. **New (v4):** Add post-RPC value-level verification in orchestrator: after RPC returns success, fetch the actual DB field values and confirm they changed. If not, reclassify result as `unchanged` instead of `updated`. This prevents false-positive "Updated" status when RPC doesn't actually persist due to fill-condition mismatch.
6. **New (v4):** For single-song entry point in Song Details, add minimal post-enrichment confirmation: brief inline success message (e.g., "✓ Song data updated") displayed when actual DB changes are confirmed, so user knows data is saved (not just a disabled Save button with no feedback).
7. **New (v4):** Critical deployment sequencing: Ensure migration `20260801000003_align_update_song_metadata_musical_key_blank_fill.sql` deploys to production BEFORE this branch merges to main, to avoid breaking main's `_refreshAndRebaselineMetadata` fix (added in commit 72a8ab2).

Also add targeted debug telemetry in orchestration/repository for a short-term diagnostic window (guarded by debug mode), so future regressions can be triaged quickly without ambiguity.

What must not change:

- Entry-point wiring and UX flow (selector -> process -> results overlay)
- Fill-missing-only product intent (must remain non-overwrite); migration scope is key-only.
- Provider contracts (`getsongbpm_lookup`, iTunes/MusicBrainz)
- **New (v4):** Main's `_refreshAndRebaselineMetadata` signature or call site (must remain compatible when this branch merges)

---

## 7. Database Impact

- Migrations: `required` (one new migration).
  - Scope: align `update_song_metadata` musical key fill condition for blank/whitespace sentinels.
  - BPM fill condition remains `bpm IS NULL` (unchanged).
- RLS policies: `unaffected`.
- RPC signatures: `unaffected`.
- RPC fill logic: `affected` (musical key CASE branch only; BPM CASE branch unchanged).
- Trigger logic: `unaffected`.

Critical note: because `CASE ... ELSE <column>` can return row-count success without changing target fields, verification must assert value-level change correlation (not success flag alone).

---

## 8. Flutter Architecture Changes

- State management: unchanged (`Notifier`/providers remain as-is).
- Repository layer: minimal logging/diagnostics update only.
- Service layer: unchanged provider interfaces.
- Orchestration layer: missing-value normalization logic update.
- Widgets: results summary text update to include unchanged/skipped count.

---

## 9. Files to Create

- none

---

## 10. Files to Modify

| File                                                                                        | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`                             | Replace strict null-only checks with normalized missing checks (BPM `null/<=0`, key `null/blank`, duration `<=0`), add concise debug diagnostics for eligibility/result mapping, **and add post-RPC value-level verification** (v4): after RPC success, fetch actual DB field values to confirm they changed; if not, reclassify as `unchanged` instead of `updated`.                                                                                      |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`                                | Add unchanged/skipped summary line so totals are explainable to users during enrichment completion.                                                                                                                                                                                                                                                                                                                                                        |
| `lib/features/setlists/setlist_repository.dart`                                             | Add debug-level logging around enrichment RPC call inputs/outcomes to distinguish provider miss vs write failure when troubleshooting.                                                                                                                                                                                                                                                                                                                     |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`                              | **New (v4):** Add minimal post-enrichment confirmation for single-song entry point: brief inline success message (e.g., "✓ Song data updated") displayed when `_didCurrentSongMetadataUpdate` returns true AND actual DB changes are confirmed, giving user visible feedback that enrichment persisted (not just a disabled Save button).                                                                                                                  |
| `supabase/migrations/<new_timestamp>_align_update_song_metadata_musical_key_blank_fill.sql` | Add a key-only RPC behavior migration: update only the `musical_key` CASE branch in `update_song_metadata` to fill when current key is `NULL`, empty string, or whitespace-only, while preserving non-overwrite intent and function signature; do not modify BPM CASE logic. **Critical (v4):** This migration MUST deploy to production BEFORE this branch merges to main, to avoid breaking main's `_refreshAndRebaselineMetadata` fix (commit 72a8ab2). |

---

## 11. Files Off-Limits

| File                                            | Reason                                                                                                      |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                 | Initialization order is guarded and unrelated to this bug.                                                  |
| `supabase/functions/getsongbpm_lookup/index.ts` | No code evidence of this edge function causing the cross-entrypoint zero-write symptom; keep scope focused. |

Boundary note:

- Exactly one new migration file under `supabase/migrations/**` is in-scope.
- That migration may update only the `musical_key` fill condition in `update_song_metadata`.
- The `bpm` CASE branch is explicitly off-limits.

---

## 12. System Impact Map

| System                                 | Impact                          |
| -------------------------------------- | ------------------------------- |
| Gigs                                   | unaffected                      |
| Rehearsals                             | unaffected                      |
| Setlists / Catalog                     | affected                        |
| Members / RBAC                         | unaffected                      |
| Auth / Session                         | unaffected                      |
| Routing                                | unaffected                      |
| Notifications                          | unaffected                      |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter logic) |

---

## 13. Regression Risk

`MEDIUM` (updated from `LOW-MEDIUM` in v4)

Rationale:

- Changes are localized to enrichment orchestration and summary UI.
- No auth, init-order, or routing changes; only one tightly scoped RPC behavior migration (musical key fill condition).
- **New (v4):** Identified merging hazard with main's `_refreshAndRebaselineMetadata` fix: if migration doesn't deploy before merge, single-song enrichment form refresh will break for songs with blank musical_key.
- Risk mitigated by:
  - Mandatory migration-first deployment sequencing
  - Post-RPC value-level verification to prevent false-positive "updated" status
  - Strict checks (`<=0`, blank key only) and targeted verification on mixed datasets
- Risk elevated to MEDIUM due to deployment coordination requirement and potential UX regression if sequencing is not followed.

---

## 14. Engineer Task Breakdown

1. Record the resolved sentinel evidence in the engineer report:
   - BPM sentinel is `NULL` only (no `0` evidence).
   - Musical key sentinel includes blank/whitespace.
   - Duration sentinel includes `0` (already RPC-aligned).
2. Lock implementation to mixed scope:
   - Client-side normalization required.
   - RPC migration required for key only.
   - BPM RPC condition unchanged.
   - **New (v4):** Merging-hazard mitigation required (value-level verification + deployment sequencing).
3. Add local helper predicates in orchestrator for field-missing detection:
   - `_isMissingBpm(int? bpm)`
   - `_isMissingDuration(int durationSeconds)`
   - `_isMissingKey(String? musicalKey)`
4. Replace all `needsBpm/needsDuration/needsKey` computations to use these predicates consistently (including pre-filter and per-song loop).
5. Add debug prints (kDebugMode) in orchestrator to log per-song eligibility and updateMap composition.
6. Add debug prints (kDebugMode) in repository enrichment RPC wrapper to log songId, non-null param keys, and RPC `success/error` payload.
7. Update results overlay summary to include unchanged/skipped count next to not-recognized/errors.
8. **New (v4):** Add post-RPC value-level verification in orchestrator:
   - After RPC returns `success: true`, fetch actual DB field values for the song (`bpm`, `duration_seconds`, `musical_key`).
   - Compare fetched values with values that were sent to RPC.
   - If a field was sent to RPC but DB value didn't change, reclassify that field's result from `updated` to `unchanged`.
   - This prevents false-positive "Updated" status that would break main's `_refreshAndRebaselineMetadata` fix.
9. **New (v4):** Add minimal post-enrichment confirmation in Song Details bottom sheet:
   - After `showEnrichmentResultsOverlay` returns, check if `_didCurrentSongMetadataUpdate(result)` is true.
   - If true AND at least one field was actually persisted (verified by the orchestrator's value-level check), show brief inline success message: "✓ Song data updated" (or similar).
   - Use a simple SnackBar or inline text confirmation, not a modal.
   - This gives user visible feedback beyond just a disabled Save button.
10. Add one new migration that updates only RPC musical key fill condition to match accepted unset sentinels from evidence (no signature change; BPM branch unchanged).
11. **New (v4):** Migration deployment gate:
    - Migration `20260801000003_align_update_song_metadata_musical_key_blank_fill.sql` MUST be deployed to production BEFORE this branch merges to main.
    - Add explicit deployment verification step in engineer report: confirm migration is live in production.
    - Reason: Prevents breaking main's `_refreshAndRebaselineMetadata` fix when this branch's broadened predicates merge.
12. Keep all existing wiring and callbacks unchanged (do not modify main's `_refreshAndRebaselineMetadata` or `_didCurrentSongMetadataUpdate` methods).
13. Run `flutter analyze` and verify zero errors.
14. Produce `ENGINEER_REPORT.md` with:
    - sentinel evidence outcome and resolved mixed scope
    - before/after behavior notes for the 36-song scenario
    - explicit value-level proof that RPC `success: true` corresponded to changed field values for updated rows
    - **New (v4):** Confirmation that migration deployed to production before branch merge

---

## 15. Verification Plan

This bug needs runtime evidence attached and preserved for implementation/QA traceability.

### Runtime Evidence Gate (must be captured by Tony and attached before Engineer proceeds)

Capture from a debug build while reproducing both entry points (catalog-wide and single-song):

1. Full console logs containing these tags:
   - `[SongEnrichmentOrchestrator]`
   - `[SetlistRepository]`
   - `[SongEnrichmentService]`
   - `[ExternalSongLookup]`
2. Results overlay screenshot showing:
   - enriched count
   - not recognized count
   - error count (if shown)
   - at least 6 detail rows (mix of outcomes)
3. Pre-run and post-run SQL snapshots for the exact 36 song IDs tested:

```sql
SELECT id, title, artist, bpm, duration_seconds, musical_key, updated_at
FROM songs
WHERE id = ANY(:song_ids)
ORDER BY title;
```

4. For 3 representative songs (one reported not recognized, one expected match, one unchanged-looking), capture raw values of `bpm`, `duration_seconds`, `musical_key` before and after run.
5. Required sentinel classification check (new):
   - For each of the 3 representative songs, explicitly classify pre-run `bpm` and `musical_key` sentinel as one of:
     - `NULL`
     - `0` (BPM only)
     - blank/whitespace (key only)
     - populated value
   - Use this classification to confirm the resolved mixed scope and ensure post-fix validation uses the same baseline.

How to capture logs cleanly:

- Run app in debug mode.
- Start reproduction.
- Copy console output from the first line containing `[SongEnrichmentOrchestrator] Enriching` through the line where results overlay appears.
- Do this once for catalog-wide and once for per-song entry.

### Tier 1 — Pre-deployment validation

- Validate provider lookups alone using existing app debug logs (no SQL migration calls).
- Confirm orchestrator eligibility classification on representative songs before any code changes.
- Use resolved evidence to document and execute mixed scope:
  - Client normalization for BPM/key/duration.
  - Key-only RPC migration.

### Tier 2 — Post-deployment (after fix is merged to branch)

- Re-run 36-song enrichment and verify non-zero enriched count when provider returns values and normalized missing fields exist.
- Verify summary now explains totals (enriched + not recognized + unchanged + errors).
- Verify per-song entrypoint and catalog-wide entrypoint produce consistent, correct outcomes for the same song.
- Verify value-level write correlation:
  - For songs marked updated, confirm pre/post SQL snapshots show targeted field value change.
  - For songs not changed, confirm either provider miss or sentinel gate explains no-change.
  - Specifically for key-only migration scope, confirm `musical_key` changes from blank/whitespace to populated value where enrichment reports key update.
  - Do not accept RPC `success: true` alone as proof of enrichment success.
- **New (v4):** Single-song Song Details enrichment flow verification:
  - Open Song Details for a song with blank `musical_key`.
  - Enrich (assuming provider returns a key value).
  - Verify results overlay shows "Updated" for Key field.
  - Verify after dismissing overlay, the form now shows the enriched key value (not the old blank value).
  - Verify post-enrichment confirmation message appears (e.g., "✓ Song data updated").
  - Verify Save button remains disabled (no unsaved changes).

---

## 16. QA Regression Areas

- Catalog-wide enrichment on mixed data (`null`, `0`, blank key, already-filled).
- Single-song enrichment from Song Details for a song with BPM `0` and/or blank key.
- **New (v4):** Single-song enrichment form state refresh after dismissing results overlay (verify form shows enriched values, not stale values).
- **New (v4):** Post-enrichment user confirmation message visibility and correctness.
- Results overlay summary correctness (totals reconcile with details).
- No regression in non-catalog setlist actions.
- No regression in manual metadata edit flows (BPM/key/duration edits).
- **New (v4):** No regression when this branch merges to main: confirm main's `_refreshAndRebaselineMetadata` fix still works correctly with the new orchestrator predicates (requires migration deployed first).

---

## 17. Rollout / Migration Strategy

- **Critical (v4):** Migration-first deployment sequence:
  1. **Deploy migration `20260801000003_align_update_song_metadata_musical_key_blank_fill.sql` to production FIRST.**
  2. Verify migration is live in production (check Supabase migrations table).
  3. THEN merge this branch to main.
  4. Reason: Prevents breaking main's `_refreshAndRebaselineMetadata` fix when broadened orchestrator predicates merge.

- Mixed-scope rollout:
  1. Use captured runtime evidence as baseline (BPM `NULL` only, key blank/whitespace present).
  2. Apply Flutter-side normalization + observability updates + value-level verification.
  3. Deploy one key-only migration for RPC `musical_key` fill-condition alignment (see critical sequencing above).
  4. QA validate both entry points with value-level evidence-backed outcomes, including direct verification of `musical_key` field changes where updates are reported.
  5. **New (v4):** QA validate single-song enrichment form state refresh works correctly.

---

## 18. Out of Scope

- Changing provider matching heuristics in `getsongbpm_lookup`.
- Adding retry/backoff/rate-limit handling enhancements.
- Reworking enrichment UX flow or adding per-song review mode.
- Any Supabase schema/RLS changes unrelated to `update_song_metadata` fill-condition alignment.
