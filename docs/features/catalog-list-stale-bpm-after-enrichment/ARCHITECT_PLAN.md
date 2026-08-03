# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/catalog-list-stale-bpm-after-enrichment

---

## 2. Problem Summary

After Song Details enrichment updates song metadata in the database (confirmed for American Girl, song id 625e82c1-f56c-4dfc-bba7-0148eb8dedc1), the Catalog list can keep showing stale BPM instead of the new value.

This is trust-sensitive because two app surfaces disagree: Song Details reflects updated metadata, while Catalog list appears unchanged.

---

## 3. Root Cause

Primary root cause: enrichment flows emit SongUpdateEvent with only songId and no updated metadata payload, but SetlistDetailNotifier.\_applySongUpdate only applies concrete field values from the event. A songId-only event is effectively a no-op for bpm/duration/key fields.

Secondary persistence factor: SetlistDetailNotifier.loadSetlist short-circuits when the same setlist id is re-opened (\_setlistId == id), so re-entering the same Catalog can reuse cached provider state instead of guaranteed re-fetch.

Confidence: HIGH

Confirmed in code:

- Song Details single-song enrichment broadcasts SongUpdateEvent(songId: detail.songId) without bpm/duration/key values.
- Catalog selected-song and Catalog-wide enrichment flows do the same broadcast pattern.
- \_applySongUpdate merges event fields and keeps existing values when event fields are null.
- loadSetlist returns early for same setlist id with already-cached state.

---

## 4. Reference Docs Consulted

- docs/agents/ARCHITECT.md
- docs/agents/GUARDRAILS.md
- docs/agents/OPERATING_MODEL.md
- docs/features/song-details-enrichment-blanks-fields/ARCHITECT_PLAN.md
- docs/features/song-details-enrichment-no-db-write/ARCHITECT_PLAN.md

---

## 5. Existing System Analysis

### 5.1 Exact Catalog screen backing path

Catalog detail screen is SetlistDetailScreen, and its data is driven by setlistDetailProvider (SetlistDetailNotifier + SetlistDetailState).

Flow:

1. Setlists list/tabs navigate to SetlistDetailScreen.
2. SetlistDetailScreen init calls setlistDetailProvider.notifier.loadSetlist(setlistId, setlistName).
3. For Catalog, loadSongs fetches rows via SetlistRepository.fetchSongsForSetlist.
4. Repository query joins setlist_songs to songs and maps bpm from songs.bpm via SetlistSong.fromSupabase.

Conclusion: Catalog row display path is provider-backed SetlistDetailState.songs from songs table metadata.

### 5.2 setlist_songs bpm override usage status

Confirmed in current Flutter display path: Catalog and Setlist song cards use SetlistSong.fromSupabase(songData['bpm']) from joined songs table.

No active display path was found that sources BPM from setlist_songs.bpm.

### 5.3 Why staleness occurs after enrichment

Single-song path:

1. Song Details runs orchestrator and DB write completes.
2. Song Details broadcasts SongUpdateEvent with only songId.
3. SetlistDetailNotifier listener receives event, \_applySongUpdate runs, but no bpm/duration/key value is provided to merge.
4. Provider state remains stale.

Bulk path (selected or catalog-wide):

- Same broadcaster pattern with songId-only events, same no-op merge behavior.

### 5.4 Re-entry behavior

SetlistDetailNotifier.loadSetlist returns early when \_setlistId equals requested id, so reopening the same Catalog route can reuse stale cached provider state instead of forcing a reload.

### 5.5 Repro/confirmation status

Equivalent local repro is confirmed in code with HIGH confidence:

- any enrichment that updates DB but emits songId-only event will not update provider metadata fields
- reopening same setlist id can retain stale cache due loadSetlist early return

This explains the reported production behavior for American Girl without requiring DB-layer speculation.

---

## 6. Proposed Solution

Apply the smallest client-state refresh fix in existing architecture.

### 6.1 Change set

1. Ensure post-enrichment flows trigger an actual provider re-fetch for the current setlist:
   - Song Details single-song enrichment: call setlistDetailProvider.notifier.loadSongs after successful enrichment run (or when any field result is updated).
   - Catalog selected and Catalog-wide enrichment: call setlistDetailProvider.notifier.loadSongs after orchestration completes.

2. Remove same-id short-circuit staleness on screen re-entry:
   - Adjust loadSetlist behavior so opening the same setlist id can still refresh songs (either by forcing loadSongs on same-id invocation or by adding a forceReload parameter used by screen init).

### 6.2 What must not change

- No changes to enrichment orchestration rules.
- No changes to repository SQL join fields.
- No new providers/controllers/repositories.
- No architecture refactor beyond refresh/invalidation behavior.

---

## 7. Database Impact

Database: not applicable

- Migrations: unaffected
- RLS: unaffected
- RPC signatures: unaffected
- Triggers: unaffected

Reason: this bug is in Flutter provider refresh/cache behavior after successful DB writes.

---

## 8. Flutter Architecture Changes

Affected Flutter architecture elements:

- Setlist detail provider refresh behavior after enrichment
- Setlist detail setlist-load behavior for same-id screen re-entry

No new state containers; only lifecycle/refetch behavior adjustments in existing notifier/widget flows.

---

## 9. Files to Create

none

---

## 10. Files to Modify

| File                                                         | What changes                                                                                                                           |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart | After enrichment completion, trigger setlist detail data reload so Catalog list state reflects DB updates from single-song enrichment. |
| lib/features/setlists/setlist_detail_screen.dart             | After selected-song and catalog-wide enrichment orchestration, trigger setlist detail reload to refresh displayed metadata fields.     |
| lib/features/setlists/setlist_detail_controller.dart         | Update loadSetlist same-id behavior to avoid stale cached state on Catalog re-entry; ensure same-setlist open can refetch songs.       |

---

## 11. Files Off-Limits

| File                                                          | Reason                                                                               |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| lib/features/setlists/setlist_repository.dart                 | Query path already sources bpm from joined songs table and is not root cause here.   |
| lib/features/setlists/models/setlist_song.dart                | Model mapping already intentionally uses songs metadata and should remain unchanged. |
| lib/features/songs/services/song_enrichment_orchestrator.dart | DB write orchestration is not the refresh/caching failure point for this bug.        |
| supabase/migrations/\*                                        | No schema or RPC change needed.                                                      |
| supabase/functions/\*                                         | Edge functions are not involved in this stale client-state display bug.              |
| lib/main.dart                                                 | Initialization order is guarded and unrelated.                                       |

---

## 12. System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | unaffected |
| Setlists / Catalog                     | affected   |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | affected   |

Reason: shared setlists Flutter code path runs across all platforms.

---

## 13. Regression Risk

MEDIUM

Rationale:

- Changes are localized to existing setlists UI/provider files.
- Touches refresh lifecycle and same-id load behavior, which can affect perceived loading behavior.
- No DB, auth, or routing contract changes.

---

## 14. Engineer Task Breakdown

1. In song_details_bottom_sheet.dart, add post-enrichment reload call for setlistDetailProvider.notifier.loadSongs when enrichment updates at least one field.
2. In setlist_detail_screen.dart, add post-enrichment reload call in both \_handleEnrichSelectedSongs and \_handleEnrichAllCatalogSongs.
3. In setlist_detail_controller.dart, modify loadSetlist same-id early-return behavior so same setlist re-entry can refresh from repository.
4. Keep existing broadcaster behavior unless required for immediate in-screen update parity; do not introduce new global state mechanisms.
5. Run flutter analyze and verify no new analyzer errors in touched files.

---

## 15. Verification Plan

Tier 1 — Pre-deployment (must pass before any deploy)

- PRE-DEPLOY TEST 1: Static check that all enrichment entry points now invoke provider reload.
  - Song Details single-song path includes setlistDetailProvider.notifier.loadSongs call.
  - Catalog selected-song path includes setlistDetailProvider.notifier.loadSongs call.
  - Catalog-wide path includes setlistDetailProvider.notifier.loadSongs call.

- PRE-DEPLOY TEST 2: Static check that loadSetlist no longer leaves same-id re-entry stale.
  - Same setlist id path must trigger a data refresh.

- PRE-DEPLOY TEST 3: flutter analyze passes with no new errors in modified files.

Tier 2 — Post-deployment/runtime validation

- POST-DEPLOY TEST 1: Production repro row validation (Toxic Crayon, American Girl, song id 625e82c1-f56c-4dfc-bba7-0148eb8dedc1).
  1. Clear BPM, save.
  2. Song Details -> Enrich Song Data (BPM).
  3. Confirm Song Details shows BPM 114.
  4. Confirm Catalog list now shows BPM 114 without stale placeholder.

- POST-DEPLOY TEST 2: Re-entry validation.
  - Fully back out of Catalog, re-open same Catalog setlist, verify BPM remains correct and fresh.

- POST-DEPLOY TEST 3: Manual refresh validation.
  - Trigger user refresh path and verify enriched BPM remains accurate.

- POST-DEPLOY TEST 4: Bulk enrichment parity.
  - Run Catalog selected-song enrichment and Catalog-wide enrichment on songs missing BPM.
  - Confirm list reflects new BPM values after each run.

- POST-DEPLOY TEST 5: Production sanity query.
  - Confirm songs.bpm for target song is 114 and no unintended metadata fields were changed.

---

## 16. QA Regression Areas

- Primary: Song Details single-song enrichment -> Catalog list metadata consistency.
- Catalog-wide and selected-song enrichment -> list metadata refresh behavior.
- Screen re-entry for same setlist id -> no stale provider reuse.
- Manual refresh path on Catalog screen.
- Non-enrichment metadata edits (manual BPM/duration/key edits) still update list correctly.
- Cross-platform spot checks on iOS and Web minimum.

---

## 17. Rollout / Migration Strategy

- Standard client release path only.
- No migration.
- No RPC/function deploy.
- Rollout as part of next app build; verify with targeted runtime checks above.

---

## 18. Out of Scope

- Refactoring songUpdateBroadcaster architecture.
- Reworking sort logic.
- Any DB schema cleanup for vestigial setlist_songs metadata override columns.
- Any unrelated setlist caching optimizations beyond same-id stale fix.
