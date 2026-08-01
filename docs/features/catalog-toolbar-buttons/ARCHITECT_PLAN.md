# Architect Plan — Catalog Toolbar Buttons

## 1. Feature Slug

`feature/catalog-toolbar-buttons`

## 2. Problem Summary

Catalog currently exposes two enrichment entry points at once:

- Top toolbar: `Enrich All`
- Select-mode bottom bar: `Enrich Songs`

This duplicates user intent and creates label/order inconsistency across the same screen. The requested behavior is Catalog-only UI consolidation: keep one enrichment control in the top toolbar, make it selection-count aware while Select mode is active, reorder toolbar buttons, and rename copy for both top and bottom controls.

## 3. Root Cause

Confidence: HIGH

Direct code inspection in [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart) shows:

- Top toolbar action row (`_buildActionButtonsRow`) currently orders controls as `Sort`, `Enrich All`, `Add to Setlist`, `Search`.
- Select-mode bottom actions (`_buildSelectModeBottomActions`) currently include a separate enrich button plus an add button (`Add To Setlist` / `Add N to Setlist`).
- Catalog scoping already exists via `state.isCatalog`, but copy/order logic does not match requested UX.

## 4. Reference Docs Consulted

- [docs/agents/GUARDRAILS.md](docs/agents/GUARDRAILS.md)
- [docs/agents/OPERATING_MODEL.md](docs/agents/OPERATING_MODEL.md)
- [docs/agents/ARCHITECT.md](docs/agents/ARCHITECT.md)
- [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart)

## 5. Existing System Analysis

- Top toolbar remains rendered regardless of Select mode; Select mode adds a sticky bottom bar, it does not replace header actions.
- Catalog-only top-toolbar enrich action currently calls `_handleEnrichAllCatalogSongs(state)` and is labeled `Enrich All`.
- Select-mode enrich action currently calls `_handleEnrichSelectedSongs()` and is a separate button in bottom actions.
- Bottom primary action currently uses add semantics/copy: `Add To Setlist` and `Add N to Setlist`.

## 6. Proposed Solution

Implement a Catalog-only UI consolidation in `setlist_detail_screen.dart`:

1. Rename top toolbar labels:

- `Enrich All` -> `Enrich`
- `Add to Setlist` -> `+ Add`

2. Reorder Catalog toolbar controls to:

- `+ Add`
- `Search`
- `Sort`
- `Enrich`

3. Keep top-toolbar `Enrich` always present in Catalog and same position whether Select mode is active or inactive.

4. Make top-toolbar `Enrich` count-aware only during Select mode:

- Select mode + 0 selected: `Enrich`
- Select mode + N selected: `Enrich (N)`

5. Consolidate enrichment entry points by removing the separate Select-mode bottom `Enrich Songs` button entirely.

6. Rename/select-count behavior for remaining bottom action:

- `Add to setlist` -> `Move to setlist`
- 0 selected: `Move to setlist`
- N selected: `Move to setlist (N)`

7. Preserve existing behavior for non-Catalog setlists (no label/order changes outside Catalog).

## 7. Database Impact

Not applicable. No migration, RPC, RLS, trigger, or schema changes.

## 8. Flutter Architecture Changes

- State management remains in existing `SetlistDetailScreen` local state (`_isSelectMode`, `_selectedSongIds`) and existing handlers.
- No new providers/controllers/repositories.
- No new dependencies.

Given the file is already oversized, this plan intentionally avoids adding new architectural layers and instead applies targeted in-place UI edits that reduce bottom-bar complexity.

## 9. Files to Create

None.

## 10. Files to Modify

| File                                                                                                 | What changes                                                                                                                                                                  |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart) | Catalog toolbar labels/order, dynamic top `Enrich` label in Select mode, remove Select-mode bottom enrich button, rename bottom add action to dynamic `Move to setlist` label |

## 11. Files Off-Limits

| File                                                                                                                         | Reason                                                  |
| ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart)                               | No data-access change required for this UI-only scope   |
| [lib/features/songs/song_enrichment_service.dart](lib/features/songs/song_enrichment_service.dart)                           | Enrichment backend/client orchestration is out of scope |
| [lib/features/setlists/widgets/song_details_bottom_sheet.dart](lib/features/setlists/widgets/song_details_bottom_sheet.dart) | No song-detail-sheet behavior change requested          |
| [supabase/migrations](supabase/migrations)                                                                                   | No database work in scope                               |

## 12. System Impact Map

| System                                 | Impact                                                |
| -------------------------------------- | ----------------------------------------------------- |
| Gigs                                   | unaffected                                            |
| Rehearsals                             | unaffected                                            |
| Setlists / Catalog                     | affected (Catalog detail toolbar/select actions only) |
| Members / RBAC                         | unaffected                                            |
| Auth / Session                         | unaffected                                            |
| Routing                                | unaffected                                            |
| Notifications                          | unaffected                                            |
| Platform (iOS / Android / Web / macOS) | affected (same UI semantics across platforms)         |

## 13. Regression Risk

LOW to MEDIUM.

Rationale:

- Scope is UI copy/order/consolidation in one screen.
- Existing handlers are reused; no backend/data path changes.
- Risk centers on wrong catalog gating or accidentally changing non-catalog action layout.

## 14. Engineer Task Breakdown

1. Update top toolbar label strings for Catalog actions:

- `Add to Setlist` -> `+ Add`
- `Enrich All` -> `Enrich`

2. Reorder top toolbar widgets for Catalog path to `+ Add`, `Search`, `Sort`, `Enrich`.

3. Add computed top-toolbar enrich label logic:

- Use `_isSelectMode` and `_selectedSongIds.length` to produce `Enrich` vs `Enrich (N)`.

4. Keep top-toolbar enrich button visible/position-stable in Select mode (do not condition it on bottom bar state).

5. Remove bottom-bar enrich button and related spacing/layout cleanup.

6. Rename bottom-bar remaining primary button text logic to:

- `Move to setlist`
- `Move to setlist (N)`

7. Validate non-catalog behavior is unchanged.

## 15. Verification Plan

### A. Catalog Toolbar Behavior

1. Open Catalog (not regular setlist) and verify top toolbar order is exactly:

- `+ Add`
- `Search`
- `Sort`
- `Enrich`

2. Verify labels in normal mode:

- `+ Add` displays as requested.
- `Enrich` displays as requested.

3. Enter Select mode with zero selection:

- Top toolbar remains visible.
- Top enrich label remains `Enrich`.

4. Select multiple songs (example 1, then 12):

- Top enrich label changes to `Enrich (1)` then `Enrich (12)`.

### B. Select-Mode Bottom Bar

1. Enter Select mode in Catalog and verify no separate bottom `Enrich Songs` button exists.

2. Verify remaining primary button label:

- 0 selected: `Move to setlist`
- N selected: `Move to setlist (N)`

3. Verify button action still opens setlist picker flow as before (copy/move behavior unchanged unless separately implemented).

### C. Non-Catalog Guard

1. Open a regular setlist and confirm this feature does not apply:

- No catalog-only reorder/copy changes leak into non-catalog UI.

### D. Platform Pass

1. Smoke-check on web, iOS, Android, macOS:

- Toolbar labels/order consistent.
- Select mode transitions do not hide toolbar.
- Count-aware labels render correctly.

## 16. Out of Scope

- Any enrichment orchestration logic change (`SongEnrichmentOrchestrator`, services, repository calls).
- Any backend/RPC/database changes.
- Any non-catalog setlist UX redesign.
- Any RBAC/permission model changes.

## 17. Working Tree Constraint Note

Current working tree already contains unrelated uncommitted `existing-song-enrichment` edits in [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart), which overlaps this feature's edit zone. Engineer execution must use strict hunk-scoped staging and review to ensure this feature's eventual diff includes only `feature/catalog-toolbar-buttons` changes.
