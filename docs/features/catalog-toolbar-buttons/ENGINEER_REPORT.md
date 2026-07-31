# Engineer Report

## Feature Slug

feature/catalog-toolbar-buttons

## Feature Title

Catalog Toolbar Buttons

## Goal

Apply the Catalog-only toolbar consolidation described in Architect Section 14: relabel/reorder top actions, keep top enrich visible in Select mode with count-aware label, remove bottom enrich entry point, and rename bottom primary action copy.

## Architect Tasks Completed

- [x] Task 1 — Updated Catalog top toolbar labels to `+ Add` and `Enrich`.
- [x] Task 2 — Reordered Catalog top toolbar actions to `+ Add`, `Search`, `Sort`, `Enrich`.
- [x] Task 3 — Added dynamic top enrich label logic using `_isSelectMode` and `_selectedSongIds.length` (`Enrich` vs `Enrich (N)`).
- [x] Task 4 — Kept top enrich button visible in Catalog Select mode and position-stable.
- [x] Task 5 — Removed separate bottom-bar enrich button from Select mode actions.
- [x] Task 6 — Renamed bottom primary button copy to `Move to setlist` / `Move to setlist (N)`.
- [x] Task 7 — Preserved non-Catalog behavior by scoping label/order changes to `state.isCatalog` branch only.

## Files Created

- docs/features/catalog-toolbar-buttons/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/setlist_detail_screen.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 1 info-level lint.

Info detail:

- `use_build_context_synchronously` at `lib/features/setlists/setlist_detail_screen.dart:1443` (pre-existing section from unrelated in-progress enrichment work; not introduced by this toolbar patch).

## Test Results

Not run (Architect plan requires `flutter analyze`; no test command required in Section 14 scope).

## Verification

Manual verification performed in code:

- Confirmed Catalog action row order is encoded as `+ Add`, `Search`, `Sort`, `Enrich` in the `state.isCatalog` branch.
- Confirmed top enrich label computes `Enrich` when no selection and `Enrich (N)` when Select mode has selected songs.
- Confirmed top enrich remains in toolbar and is not gated by bottom bar visibility.
- Confirmed Select mode bottom row no longer renders a separate enrich button.
- Confirmed bottom primary action label logic now renders `Move to setlist` and `Move to setlist (N)`.
- Confirmed non-Catalog branch keeps prior labels/order (`Add to Setlist`, tuning toggle, search).

## Deviations From Architect Plan

- Workspace cleanliness guardrail in `docs/agents/ENGINEER.md` Phase 1 expects a clean tree, but this session intentionally proceeded on a dirty tree per explicit user instruction because pre-existing unrelated uncommitted work overlaps the target file.

## Blockers Encountered

None.

## Diff Provenance (Critical For Gate)

The working tree already contained unrelated uncommitted enrichment work before this session.

Hunks authored in this session (Catalog toolbar buttons scope):

- `lib/features/setlists/setlist_detail_screen.dart` in `_buildActionButtonsRow(...)`:
  - Added `selectedCount` / `enrichLabel` computation.
  - Implemented Catalog-only order and labels (`+ Add`, `Search`, `Sort`, `Enrich`).
  - Routed top enrich tap to selected-song enrichment when in Select mode with selection; otherwise catalog-wide enrichment.
  - Preserved non-Catalog branch behavior.
- `lib/features/setlists/setlist_detail_screen.dart` in `_buildSelectModeBottomActions()`:
  - Updated button label logic to `Move to setlist` / `Move to setlist (N)`.
  - Removed separate bottom enrich action block and related spacing.
  - Updated comments to reflect remaining single primary action.

Pre-existing unrelated hunks (not authored in this session):

- Earlier import additions and enrichment service/orchestrator integrations in `lib/features/setlists/setlist_detail_screen.dart`.
- Entire enrichment handler additions (`_handleEnrichSelectedSongs`, `_handleEnrichAllCatalogSongs`) and other existing-song-enrichment changes in the same file.
- Modifications in `lib/features/setlists/setlist_repository.dart`.
- Modifications in `lib/features/setlists/widgets/song_details_bottom_sheet.dart`.
- Modifications in `lib/features/songs/song_enrichment_service.dart`.

## Ready For QA

Yes.
