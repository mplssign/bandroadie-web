# Architect Plan — feature/song-enrichment-confidence-display

## 1. Feature Slug

`feature/song-enrichment-confidence-display`

Type: feature
Branch: `feature/song-enrichment-confidence-display`
Docs path: `docs/features/song-enrichment-confidence-display/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

Phase A and Phase B already shipped the backend matching and scoring work, and the live `getsongbpm_lookup` response now includes additive numeric confidence fields: `bpmConfidence` and `keyConfidence` (nullable ints, 0–95). The Flutter client currently drops those values in `SongEnrichmentService` and never threads them into `SongEnrichmentDetail`, so the enrichment results overlay only shows the badge status (`Updated`, `Not found`, `Unchanged`, `Error`) without per-field confidence percentages. The bug is not in the backend contract; it is in the Flutter client failing to consume the already-deployed response.

---

## 3. Root Cause

| Root cause                                                                                                                                                                                                                                                 | Confidence |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `SongEnrichmentResult` in `lib/features/songs/song_enrichment_service.dart` declares only `bpm`, `musicalKey`, and `confidence`, so new additive response fields are silently dropped.                                                                     | HIGH       |
| `SongEnrichmentDetail` in `lib/features/songs/services/song_enrichment_orchestrator.dart` already declares `enrichedBpm` / `enrichedKey`, but `enrichSongs()` never populates them and never carries the confidence values through the orchestration path. | HIGH       |
| `enrichment_results_overlay.dart` renders only status badges and never reads any underlying field values or confidence metadata.                                                                                                                           | HIGH       |

---

## 4. Reference Docs Consulted

No `docs/reference/notifications` docs apply to this Flutter-only Phase C. The relevant consultation was the shipped feature plan and live response contract already verified in production:

- `docs/features/song-enrichment-accuracy-confidence/ARCHITECT_PLAN.md`
- `docs/features/song-enrichment-confidence-scoring/ARCHITECT_PLAN.md`
- The live `getsongbpm_lookup` response contract confirmed against the deployed function: `bpmConfidence`, `keyConfidence`, `matchTitle`, `versionType` are additive and `confidence` remains `'medium' | 'none'`.

---

## 5. Existing System Analysis

Current behavior in the Flutter layer:

1. `SongEnrichmentService.lookup()` invokes `getsongbpm_lookup` and parses only `bpm`, `musicalKey`, and `confidence`.
2. `SongEnrichmentOrchestrator.enrichSongs()` calls `SongEnrichmentService.lookup()` for BPM/key, but never stores the numeric field confidence and never populates `enrichedBpm` / `enrichedKey` into the per-song `SongEnrichmentDetail` object.
3. The results overlay only receives `EnrichmentFieldResult` enum values and displays badge text; it never reads the raw returned values or confidence percentages.
4. The single new-song review sheet reads `SongEnrichmentService.lookup()` directly, but it also never shows confidence metadata and is intentionally a stretch-only UI improvement for this phase.

This is a client-side consumption gap, not a backend or store-layer bug. The server contract is already live and no `supabase/**` changes are required for this phase.

---

## 6. Proposed Solution

Implement only the Flutter consumption layer required for Phase C:

- Extend `SongEnrichmentResult` to parse `bpmConfidence` and `keyConfidence` as nullable ints.
- Thread those values through `SongEnrichmentDetail` in `song_enrichment_orchestrator.dart`.
- Populate the already-declared `enrichedBpm` and `enrichedKey` fields when a value is returned; retain the existing `EnrichmentFieldResult` status logic without changing its classification semantics.
- Update the results overlay to display a per-field `NN%` next to BPM and Key when the field is available and confidence is non-null.
- Keep the current status badge text and logic unchanged (`Updated`, `Not found`, `Unchanged`, `Error`).
- Treat the review sheet as stretch-only; if the implementation is minimal and clear, optionally show the same confidence indicator there without widening scope.

Important constraints:

- No provider changes.
- No repository changes beyond reading the additive response fields.
- No routing/init-order changes.
- No edge-function or Supabase changes.
- No new state classes, no new repositories, no new orchestrator abstraction.
- `matchTitle` and `versionType` remain optional UI material and are not required in this phase unless they clearly fit the existing card design without extra complexity.

---

## 7. Database Impact

`Database: not applicable.`

- No migrations required.
- No schema changes.
- No RLS changes.
- No RPC changes.
- No triggers or function deploys in this phase.

---

## 8. Flutter Architecture Changes

- `lib/features/songs/song_enrichment_service.dart`: parse `bpmConfidence` and `keyConfidence` from the live response into `SongEnrichmentResult`.
- `lib/features/songs/services/song_enrichment_orchestrator.dart`: populate `enrichedBpm`, `enrichedKey`, and the corresponding confidence fields on each `SongEnrichmentDetail` instance; keep the existing status enum flow intact.
- `lib/features/songs/widgets/enrichment_results_overlay.dart`: display per-field confidence percentages for BPM and Key only when non-null; keep the badge text and result logic the same.
- Optional stretch: `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` surfaces the confidence indicator for the single new-song review flow.

---

## 9. Files to Create

none

---

## 10. Files to Modify

| File                                                              | What changes                                                                                                                             |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/songs/song_enrichment_service.dart`                 | Parse `bpmConfidence` / `keyConfidence` into `SongEnrichmentResult` and preserve existing null-safe behavior.                            |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`   | Fill `enrichedBpm`, `enrichedKey`, and the confidence fields on `SongEnrichmentDetail`, fixing the pre-existing object-construction gap. |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`      | Show `NN%` for BPM and Key when available, hidden when `null`; keep all existing status badge semantics unchanged.                       |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | Stretch-only update to show confidence in the single new-song review flow if the diff remains minimal.                                   |

---

## 11. Files Off-Limits

| File                                            | Reason                                              |
| ----------------------------------------------- | --------------------------------------------------- |
| `supabase/**`                                   | No edge-function, DB, or RLS change in this phase.  |
| `lib/features/setlists/setlist_repository.dart` | Separate write-path ownership; not part of Phase C. |
| `lib/main.dart`                                 | Init order must not change.                         |
| Any migration or schema file                    | Phase C is Flutter-only and read-side only.         |

---

## 12. System Impact Map

| System                                 | Impact                                       |
| -------------------------------------- | -------------------------------------------- |
| Gigs                                   | unaffected                                   |
| Rehearsals                             | unaffected                                   |
| Setlists / Catalog                     | affected (results display and enrichment UX) |
| Members / RBAC                         | unaffected                                   |
| Auth / Session                         | unaffected                                   |
| Routing                                | unaffected                                   |
| Notifications                          | unaffected                                   |
| Platform (iOS / Android / Web / macOS) | affected (presentation-only UI on all)       |
| Supabase Edge Functions                | unaffected (contract already shipped)        |
| Database (schema/RLS/RPC)              | unaffected                                   |

---

## 13. Regression Risk

**Overall: LOW.**

This phase is presentation-only and does not alter submission logic, write-path RPCs, auth, routing, or database behavior. The main risk is in the UI formatting or a mismatch between the new confidence fields and the existing status badges, which is contained by keeping the success/failure classification and badge logic unchanged while only adding a secondary percentage display when data exists.

---

## 14. Engineer Task Breakdown

1. Update `SongEnrichmentResult` to include nullable `bpmConfidence` and `keyConfidence` fields and parse them from the live response without changing `confidence` semantics.
2. In `SongEnrichmentOrchestrator.enrichSongs()`, set `enrichedBpm`, `enrichedKey`, and the per-field confidence values on `SongEnrichmentDetail`, fixing the existing unpopulated-object gap.
3. In `enrichment_results_overlay.dart`, render a per-field `NN%` indicator next to BPM and Key when the value is present, hidden when `null`.
4. Optionally, in the single new-song review sheet, show the same percentage for the user’s review flow with minimal, localized UI changes.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before any release build):

- `-- PRE-DEPLOY TEST 1:` Verify `SongEnrichmentService.lookup()` reads the additive response fields and returns them in the model without throwing when `bpmConfidence` and `keyConfidence` are present or null.
- `-- PRE-DEPLOY TEST 2:` Verify `SongEnrichmentOrchestrator.enrichSongs()` populates `enrichedBpm` and `enrichedKey` on the detail object for a successful lookup and does not change the legacy status classification logic.
- `-- PRE-DEPLOY TEST 3:` Verify the overlay hides the `%` when confidence is null and displays a number only when data exists, without altering the badge text or field result semantics.

### Tier 2 — Post-deployment (after the app has shipped the Flutter change):

- `-- POST-DEPLOY TEST 1:` Load a live song that has a valid BPM/key enrichment result and confirm the overlay shows a positive percentage next to BPM and/or Key as appropriate.
- `-- POST-DEPLOY TEST 2:` Load a song with no match or with a null confidence value and confirm no extra `%` is shown while the existing `Not found` badge remains unchanged.
- `-- POST-DEPLOY TEST 3:` Confirm the single new-song review sheet (if updated) still behaves the same for save/cancel flows while the confidence indicator is present only when the lookup produced a value.

---

## 16. QA Regression Areas

- Confirm `Updated` / `Not found` / `Unchanged` / `Error` badge logic still matches the pre-existing behavior exactly.
- Confirm BPM and Key confidence percentages appear only when a value exists and are hidden when `null`.
- Confirm all enrichments still use the same successful write path and no RPC behavior changed.
- Confirm the single new-song review flow remains non-blocking and does not regress save/cancel behavior if the stretch update is implemented.

---

## 17. Rollout / Migration Strategy

No database migration or edge-function deployment is required. This is a forward-compatible Flutter UX update that consumes backend fields already shipped and live in production. Rollout is a normal app release, with no server or schema coordination required.

---

## 18. Out of Scope

- Any change to `supabase/**`.
- Any change to the enrichment write RPC or `SetlistRepository.enrichSongs()` path.
- Any change to the matching logic, version filtering, or scoring in the backend.
- Any change to init order or runtime config.
- Any unrelated UI cleanup or refactor in the review sheet or overlay.

---

## Final Status

This feature is intentionally narrow: it consumes already-deployed backend confidence data and exposes it in the Flutter UI without changing the underlying data contract, success classification, or server behavior. The issue is a client-side omission and the fix is to thread the numeric values through the existing model and overlay, keeping the diff small and safe.
