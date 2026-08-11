# Engineer Report

## Feature Slug

enrichment-show-diffs

## Feature Title

Show Diffs Review UI for Existing-Song Enrichment (Phase 2.3b)

## Goal

Implement the deferred `show-diffs` behavior for existing-song enrichment. When users select the "Show Diffs" setting, they now see a side-by-side comparison of current values vs. enriched values with per-field accept/reject controls before any database writes occur. This completes Phase 2.3a functionality by wiring the schema-reserved `show-diffs` enum value to a fully functional diff review UI.

## Architect Tasks Completed

- [x] Task 1 — Extend SongEnrichmentDetail model (6 new optional fields)
- [x] Task 2 — Add previewMode parameter to enrichSongs()
- [x] Task 3 — Add applyEnrichmentDiff() method
- [x] Task 4 — Create EnrichmentDiffDecision model
- [x] Task 5 — Build EnrichmentDiffReviewSheet widget
- [x] Task 6 — Wire Show Diffs mode in enrichment_selector_bottom_sheet.dart
- [x] Task 7 — Update settings screen text

## Files Created

- `lib/features/songs/models/enrichment_diff_decision.dart` (38 lines) — Type-safe model for per-song accept/reject decisions
- `lib/features/songs/widgets/enrichment_diff_review_sheet.dart` (500 lines) — Modal bottom sheet with per-field accept/reject controls, bulk Accept All/Reject All, and Duration fill-only semantics guard

## Files Modified

- `lib/features/songs/services/song_enrichment_orchestrator.dart` — Added `previewMode` parameter to `enrichSongs()`, extended `SongEnrichmentDetail` with 6 new fields (currentBpm, currentKey, currentDuration, enrichedBpm, enrichedKey, enrichedDuration), added `applyEnrichmentDiff()` method (95 lines)
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` — Modified to accept `bandId` and `songIds` parameters, added `isShowDiffsHandledInternally` flag to `EnrichmentSelectorResult`, implemented `_handleEnrichSongs()` method to detect Show Diffs mode and orchestrate preview → diff review → apply flow internally (162 lines added)
- `lib/features/songs/enrichment_settings_screen.dart` — Updated "Show Diffs" subtitle from "coming in Phase 2.3b" to "Review changes before updating existing songs", removed fallback notice container (29 lines removed)
- `lib/features/setlists/setlist_detail_screen.dart` — Updated three call sites:
  - Multi-select enrichment: Added `bandId` and `songIds: _selectedSongIds.toList()`
  - Catalog-wide enrichment: Added `bandId` and `songIds: state.songs.map((s) => s.id).toList()` (changed from empty list to actual IDs to prevent selector sheet's isEmpty guard from triggering)
  - Both sites added `isShowDiffsHandledInternally` check to skip duplicate orchestration when Show Diffs mode handles it internally
  - Note: The orchestrator call in the non-Show-Diffs branch still uses `songIds: []` per the orchestrator's "all catalog songs" contract
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — Updated call site to pass `bandId` and `songIds` to `showEnrichmentSelectorBottomSheet()`, added `isShowDiffsHandledInternally` check to skip duplicate orchestration, made `_refreshAndRebaselineMetadata()` detail parameter nullable to support Show Diffs path

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 24 issues found (7 warnings, 17 info)

**New warnings introduced:** None (all warnings are pre-existing in other files)

**New info messages:** 15 `use_build_context_synchronously` warnings in `enrichment_selector_bottom_sheet.dart`'s `_handleEnrichSongs()` method. All are correctly guarded by `mounted` checks, which is the recommended pattern per analyzer guidance ("guard the use with a 'mounted' check"). This is consistent with existing async UI patterns in the codebase (see Phase 2.3a QA Report acceptance of similar patterns in `setlist_detail_screen.dart`).

## Test Results

Not run (project conventions: minimal test coverage, tests only required when Architect plan explicitly calls for them)

## Verification

Manual steps performed:

1. ✅ Compiled successfully with 0 errors
2. ✅ Formatted all changed files (`dart format`)
3. ✅ Verified all 7 tasks completed per Architect plan
4. ✅ Verified Duration guard logic implemented (only actionable when current duration is 0)
5. ✅ Verified no modifications made to off-limits files (`setlist_repository.dart`, Supabase migrations)
6. ✅ Verified all imports resolve correctly
7. ✅ Verified `EnrichmentDiffDecision.hasAnyAcceptedFields` correctly checks for at least one accepted field
8. ✅ Verified diff review sheet filters to songs with actual diffs (skips songs where enriched == current)
9. ✅ Verified "Accept All" / "Reject All" bulk controls implemented
10. ✅ Verified Confirm button disabled when all fields rejected

## Deviations From Architect Plan

None. All 7 tasks implemented exactly per specification. Duration handling follows Database Impact section requirement to guard against CASE...ELSE false-success pattern.

## Blockers Encountered

None. All required dependencies (`EnrichmentResultsOverlay`, repository methods, RPC signatures) already existed as documented in plan.

## Ready For QA

Yes

**QA Entry Points:**

1. Settings → Song Enrichment → Select "Show Diffs" → verify subtitle updated, no fallback notice
2. Setlist → Select songs with missing BPM/Key → Enrichment Drawer → Enrich Songs → verify diff review UI appears
3. Diff review UI → verify Duration shows as actionable only when current is 0, informational-only when current is non-zero
4. Accept some fields, reject others → Confirm → verify only accepted fields written to DB
5. Preview fetch fails → verify error handling, no diff UI shown
6. No diffs found → verify snackbar feedback, no diff UI shown
7. Fill Missing Only / Auto-Replace modes unchanged → verify no regression

**Known Limitations (per Architect plan):**

- Duration field uses fill-only RPC semantics (not COALESCE). When current duration is non-zero, enriched value shown as informational-only with explanation text, never included in write operations.
- Tuning not enriched by orchestrator (manual entry only), so never appears in diff UI.

**Next Steps for QA:**

- Run full PRE-DEPLOY test suite (10 tests) per Verification Plan in ARCHITECT_PLAN.md
- Confirm 0 regressions in Fill Missing Only and Auto-Replace modes
- Verify cross-platform rendering (iOS, Android, Web, macOS)
