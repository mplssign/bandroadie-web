# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/song-details-enrichment-blanks-fields`

---

## 2. Problem Summary

Running **Enrich Song Data** from Song Details can return the user to a state where BPM/Duration/Key appear blank and the Save button is disabled, which looks like data loss even when persistent data is likely unchanged.

This is a trust-sensitive bug because the UI can present an erased-looking form with no obvious recovery path besides leaving and reopening.

---

## 3. Root Cause

**Primary root cause (client state handling): HIGH confidence (confirmed in code)**

Song Details does **not** apply enrichment results through the Catalog review flow. It invokes the orchestrator directly and then, when any field is reported `updated`, performs a **full three-field rebaseline** from DB (`bpm`, `duration_seconds`, `musical_key`) in one step:

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
  - `_handleEnrichSong()` calls `SongEnrichmentOrchestrator.enrichSongs()` directly
  - then calls `_refreshAndRebaselineMetadata()` when `_didCurrentSongMetadataUpdate(result)` is true
- `_refreshAndRebaselineMetadata()` always assigns all three local fields from DB snapshot:
  - `_currentBpm = refreshedBpm`
  - `_currentDurationSeconds = refreshedDurationSeconds`
  - `_currentMusicalKey = refreshedMusicalKey`
  - and also overwrites `_original*` with those same values

This is a wholesale replacement from DB snapshot, not a selective per-field merge based on which field(s) were actually enriched.

If the snapshot contains null/0/empty for any of these fields, previously-visible values are replaced with blanks.

**Save-disabled symptom linkage: HIGH confidence (confirmed in code)**

After rebaseline, current and original are set equal, so `_computeChangeFlags().anyChanged` becomes false and Save is disabled by design. Therefore disabled Save in the blanked state is a direct consequence of the same rebaseline behavior, not a separate independent bug.

**Working hypothesis from input (“wholesale from enrichment result including nulls”): REFUTED (HIGH confidence)**

The code does **not** repopulate form fields directly from the orchestrator payload including nulls. It repopulates from a DB re-read (`songs` table). The bug mechanism is still wholesale replacement, but source is DB snapshot, not result object.

---

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- Prior related plans for historical context:
  - `docs/features/song-details-save-disabled-after-enrichment/ARCHITECT_PLAN.md`
  - `docs/features/enrichment-refresh-clears-fields/ARCHITECT_PLAN.md`

---

## 5. Existing System Analysis

### 5.1 Confirmed Song Details call path (single-song enrichment)

1. User taps **Enrich Song Data** in Song Details.
2. `showEnrichmentSelectorBottomSheet(...)` opens.
3. `SongEnrichmentOrchestrator.enrichSongs(...)` is called directly from Song Details.
4. If `_didCurrentSongMetadataUpdate(result)` is true, Song Details executes `_refreshAndRebaselineMetadata(bandId)`.
5. Song Details then shows `showEnrichmentResultsOverlay(...)`.

Notably, Song Details does **not** route through `song_enrichment_review_sheet.dart`.

### 5.2 Confirmed Catalog flow (comparison)

Catalog/select-mode enrichment (`setlist_detail_screen.dart`) also calls the orchestrator directly, but it does not perform Song Details local form rebaseline; it shows progress/spinner and broadcasts update events.

`song_enrichment_review_sheet.dart` is used by the external-song lookup/add flow (`song_lookup_overlay.dart`), not by Song Details enrichment.

### 5.3 Why user sees blanks + disabled Save

- Blanks: caused by full local overwrite from DB snapshot in `_refreshAndRebaselineMetadata()` rather than selective merge.
- Save disabled: caused by rebaseline setting `_current* == _original*`, producing `anyChanged == false`.

### 5.4 Loading-indicator gap

Single-song Song Details enrichment does not show spinner/progress. Catalog/multi-song flows do. This is a minor UX gap and separate from the root data-state issue.

---

## 6. Proposed Solution (Minimal)

Implement **selective post-enrichment merge** in Song Details instead of full three-field replacement.

### 6.1 What changes

In `song_details_bottom_sheet.dart`:

1. Replace `_refreshAndRebaselineMetadata(String bandId)` with a detail-aware variant that accepts the current song's `SongEnrichmentDetail` (or equivalent field-result context).
2. Re-read DB once, but only apply values for fields where current-song result is `EnrichmentFieldResult.updated`.
3. Preserve existing local values for fields not updated (`unchanged`, `notFound`, `error`, `notRequested`).
4. Rebaseline `_original*` only for fields actually updated.
5. Keep existing `_justEnriched` UX behavior intact.

### 6.2 What must not change

- No changes to orchestrator field-eligibility rules.
- No changes to Catalog/external-song review flow behavior.
- No changes to RPC signatures, migrations, or RLS.
- No refactor of state architecture beyond this localized merge fix.

---

## 7. Database Impact

**Database: not applicable**

- Migrations: unaffected
- RLS: unaffected
- RPC signatures: unaffected
- Triggers: unaffected

Expected issue scope is pure Flutter client form state in Song Details.

---

## 8. Flutter Architecture Changes

- Local to `SongDetailsBottomSheet` state handling.
- No provider/repository architecture changes.
- No new dependencies.

---

## 9. Files to Create

- none

---

## 10. Files to Modify

| File                                                           | What changes                                                                                                                                |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Replace full rebaseline with selective field merge based on per-field enrichment outcomes for current song; keep `_justEnriched` semantics. |

---

## 11. Files Off-Limits

| File                                                              | Reason                                                                                         |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | Separate external-song add/review flow; not in Song Details enrichment call path.              |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`   | Root issue is local Song Details merge behavior; orchestrator logic unchanged for minimal fix. |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`      | Not root cause of field blanking; avoid unrelated UX churn in this bug fix.                    |
| `lib/features/setlists/setlist_repository.dart`                   | No repository contract issue required for this fix.                                            |
| `supabase/migrations/*`                                           | No DB/RPC schema change needed for this client-state bug.                                      |

---

## 12. System Impact Map

| System                                 | Impact                                         |
| -------------------------------------- | ---------------------------------------------- |
| Gigs                                   | unaffected                                     |
| Rehearsals                             | unaffected                                     |
| Setlists / Catalog                     | affected (Song Details metadata UX/state path) |
| Members / RBAC                         | unaffected                                     |
| Auth / Session                         | unaffected                                     |
| Routing                                | unaffected                                     |
| Notifications                          | unaffected                                     |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter code path)            |

**Cross-platform assessment:**

- Confidence: **HIGH** that bug path is cross-platform-capable (no iOS-conditional code; shared widget/orchestrator path).
- Confidence: **MEDIUM** that user-visible repro currently occurs on every platform without runtime verification.

---

## 13. Regression Risk

**MEDIUM**

Reason:

- Touches only one widget file and only post-enrichment local merge logic.
- But affects trust-sensitive metadata display and Save enablement behavior.

---

## 14. Engineer Task Breakdown

1. In `song_details_bottom_sheet.dart`, capture the current song's `SongEnrichmentDetail` from `result.details` after orchestrator returns.
2. Replace full `_refreshAndRebaselineMetadata` logic with selective apply rules:
   - `updated` => read DB value and apply to `_current*` and `_original*` for that field.
   - other statuses => do not overwrite that field.
3. Recompute `_hasChanges` after selective merge.
4. Keep `_justEnriched` assignment behavior after enrichment completion.
5. Ensure no changes are made outside allowed file.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (no DB changes required)

1. Static code-path validation:
   - Confirm Song Details still calls orchestrator directly.
   - Confirm no invocation of `song_enrichment_review_sheet.dart` from Song Details path.
2. Unit-level reasoning check:
   - For each field status (`updated`, `notFound`, `unchanged`, `error`, `notRequested`), verify selective merge behavior does not clear untouched local values.

### Tier 2 — Post-deployment/runtime validation

1. Repro case (iOS): existing song with known BPM/Duration/Key values, run Enrich Song Data.
   - Expected: unchanged fields remain visible; only actually-enriched fields change.
2. Save-state check:
   - Expected: Save is not left in a misleading blank state.
   - If no field updated, state should remain unchanged and non-destructive.
3. Cross-platform spot check:
   - Web and Android at minimum on same scenario to validate shared-path behavior.
4. DB sanity check (targeted row):
   - Query specific song row (e.g., title `American Girl`, artist `Tom Petty`, scoped by band) before/after enrichment attempt to confirm no unintended nulling.

---

## 16. QA Regression Areas

1. Song Details single-song enrichment with pre-filled metadata (primary scenario).
2. Case where enrichment updates only one of three fields.
3. Case where enrichment returns not found for selected fields.
4. Save/Done/Cancel state after enrichment completion.
5. Catalog bulk enrichment flow regression guard (ensure unchanged behavior).

---

## 17. Rollout / Migration Strategy

- Standard app release path.
- No migration or edge-function deploy required.

---

## 18. Out of Scope

- Redesigning enrichment UX across all flows.
- Orchestrator algorithm changes.
- RPC/database semantic changes.
- Broader loading/progress UX standardization beyond this bug.
