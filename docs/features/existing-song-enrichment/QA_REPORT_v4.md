# QA Report (v4)

## Feature Slug

existing-song-enrichment

## Final Verdict

**NEEDS SCOPE DECISION FROM TONY**

## What I Reviewed (Ground Truth)

I independently ran:

- `git branch --show-current`
- `git status --short`
- `git diff --name-status`
- `git diff` for the relevant files
- `flutter analyze`

Current branch at review time: `feature/enrichment-selector-info-rows`

Tracked modified files in working tree:

- `lib/features/setlists/setlist_detail_screen.dart`
- `lib/features/setlists/setlist_repository.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/features/songs/song_enrichment_service.dart`

Also present as untracked (relevant to enrichment flow):

- `lib/features/songs/services/song_enrichment_orchestrator.dart`
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
- `lib/features/songs/widgets/enrichment_results_overlay.dart`
- `lib/features/songs/widgets/enrichment_progress_overlay.dart`

## Scope Check Against ARCHITECT_PLAN.md

Architect plan for `existing-song-enrichment` expects modifications to these core files:

- `lib/features/setlists/setlist_detail_screen.dart`
- `lib/features/setlists/setlist_repository.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/features/songs/song_enrichment_service.dart`

and new orchestration/selector/results/progress files under `lib/features/songs/...`.

So at a file-list level, the working tree includes the expected enrichment file set.

However, one file (`setlist_detail_screen.dart`) now contains **mixed scope**: enrichment logic + separate catalog-toolbar UX consolidation work already documented under `feature/catalog-toolbar-buttons`.

## File-by-File Findings

### 1) lib/features/setlists/setlist_detail_screen.dart

### What this diff concretely does

In-scope enrichment logic present:

- Adds enrichment handlers:
  - `_handleEnrichSelectedSongs()`
  - `_handleEnrichAllCatalogSongs(...)`
- Wires selector sheet + orchestrator + results overlay + progress/spinner UI.
- Broadcasts `SongUpdateEvent` after updated fields.

Additional UI changes not part of existing-song-enrichment plan:

- Reorders Catalog top action row to `Add`, `Search`, `Sort`, `Enrich`.
- Renames/changes labels (`Add to Setlist` -> `Add`, bottom action -> `Move to setlist`).
- Removes bottom-bar enrich entry pattern in favor of top-row consolidated enrich behavior.

### In-scope verdict for this file

**Partially in-scope, partially out-of-scope** for `existing-song-enrichment`.

- In-scope: enrichment handlers/orchestration wiring.
- Out-of-scope relative to `existing-song-enrichment` architect plan: toolbar copy/order consolidation and bottom-bar label redesign.
- Those out-of-scope hunks align with separately documented `feature/catalog-toolbar-buttons` work.

### 2) lib/features/setlists/setlist_repository.dart

### What this diff does

- Adds `enrichSongs({ bandId, updates })` batch RPC wrapper around `update_song_metadata`.
- Passes all RPC parameters explicitly with enrichment fields populated and others null.
- Returns per-song success map.

### Relationship to existing-song-enrichment scope

**In-scope and required** by `ARCHITECT_PLAN.md` for batch enrichment writes.

### Relation to enrichment-selector-info-rows

No meaningful relation. This is data-write infrastructure, not selector presentation.

### 3) lib/features/songs/song_enrichment_service.dart

### What this diff does

- Adds:
  - `EnrichmentSongInput`
  - `SongEnrichmentBatchResult`
  - `enrichBatch(...)` (sequential lookup loop with progress callback)

### Relationship to existing-song-enrichment scope

**In-scope** per architect task list (service extension).

### Is this legacy vs active? (relationship to song_enrichment_orchestrator.dart)

- `SongEnrichmentService` is **active, not legacy**.
- It is used by:
  - Existing Phase 1 review flow (`song_enrichment_review_sheet.dart`) via `lookup(...)`.
  - New `SongEnrichmentOrchestrator` via `lookup(...)`.
- The new `enrichBatch(...)` method currently appears unused in call sites, but the service itself is still foundational and not superseded.

### Relation to enrichment-selector-info-rows

No direct relation. Selector-info-rows is UI presentation in selector widget.

### 4) lib/features/setlists/widgets/song_details_bottom_sheet.dart (previously QA re-checked)

- Adds single-song enrichment entry point (`Enrich Song Data`) and handler.
- Converts widget to `ConsumerStatefulWidget` to access providers.
- Uses orchestrator flow and broadcasts updates on successful field updates.

**Assessment:** In-scope for existing-song-enrichment and consistent with prior QA v3 targeted approval.

### 5) lib/features/songs/services/song_enrichment_orchestrator.dart (previously QA re-checked)

- Coordinates fetch -> provider lookups -> RPC updates -> per-field result mapping.
- Preserves partial success behavior (one provider failure does not discard successful fields from the other).

**Assessment:** In-scope for existing-song-enrichment and consistent with prior QA v3 targeted approval.

## Reconciled Commit Recommendation

Because `setlist_detail_screen.dart` contains mixed feature work, I do **not** recommend a naive file-level single commit without hunk selection.

### Include in existing-song-enrichment commit

- `lib/features/setlists/setlist_repository.dart`
- `lib/features/songs/song_enrichment_service.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/features/songs/services/song_enrichment_orchestrator.dart`
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
- `lib/features/songs/widgets/enrichment_results_overlay.dart`
- `lib/features/songs/widgets/enrichment_progress_overlay.dart`
- Enrichment-specific hunks inside `lib/features/setlists/setlist_detail_screen.dart` only (handlers/wiring/progress/results/broadcast logic)

### Exclude/defer to other feature commit(s)

- Toolbar consolidation/copy/order hunks in `lib/features/setlists/setlist_detail_screen.dart` that match `feature/catalog-toolbar-buttons`.
- Selector row visual treatment/action-layout tweaks that match `feature/enrichment-selector-info-rows` if they are intended as a separate PR/feature.

## Why Verdict Is “NEEDS SCOPE DECISION FROM TONY”

The commit boundary cannot be resolved safely at pure file level because one key file is cross-contaminated with at least two feature tracks:

- existing-song-enrichment behavior wiring
- catalog-toolbar-buttons UX consolidation

Tony should choose one of these paths before commit:

1. **Single combined scope**: explicitly approve bundling existing-song-enrichment + catalog-toolbar-buttons together.
2. **Strict split scope**: split `setlist_detail_screen.dart` by hunks into separate commits.

## flutter analyze Result

Command run: `flutter analyze`

Result:

- 0 errors
- 1 info
  - `use_build_context_synchronously` at `lib/features/setlists/setlist_detail_screen.dart:1449`

No analyzer errors block commit, but the info lint remains present.

## Final QA Position

**NEEDS SCOPE DECISION FROM TONY** before final commit assembly.

Core enrichment infrastructure changes are largely in-scope, but `setlist_detail_screen.dart` requires explicit scope handling due to mixed-feature hunks.
