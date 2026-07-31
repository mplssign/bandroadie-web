# Engineer Report

## Feature Slug

existing-song-enrichment

## Feature Title

Phase 2.1 — Existing Song Data Enrichment (Single, Multi-Select, Catalog-Wide Entry Points)

## Goal

Add enrichment actions at three entry points (single song details sheet, multi-select toolbar, catalog-wide action button) that allow users to backfill BPM, Duration, and Musical Key for existing catalog songs using GetSongBPM and iTunes/MusicBrainz APIs. Includes RPC migration to fix non-overwrite behavior for musical_key and duration_seconds fields.

## Architect Tasks Completed

- [x] Task 1 — RPC Migration: Fix musical_key and duration_seconds non-overwrite behavior
- [x] Task 2 — SongEnrichmentService: Add enrichBatch() method with progress callback
- [x] Task 3 — SongEnrichmentOrchestrator: Create full coordination service
- [x] Task 4 — EnrichmentSelectorBottomSheet: Create field selection UI
- [x] Task 5 — EnrichmentResultsOverlay: Create results summary UI
- [x] Task 6 — EnrichmentProgressOverlay: Create progress indicator for catalog-wide enrichment
- [x] Task 7 — Wire single-song entry point in song details sheet
- [x] Task 8 — Wire multi-select entry point in catalog toolbar
- [x] Task 9 — Wire catalog-wide entry point as action button
- [x] Task 10 — SetlistRepository: Add enrichSongs() batch update method
- [x] Task 11 — Manual verification and report creation

## Files Created

- supabase/migrations/20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql
- sql/tests/pre_deploy_tests.sql
- sql/tests/post_deploy_tests.sql
- lib/features/songs/services/song_enrichment_orchestrator.dart
- lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart
- lib/features/songs/widgets/enrichment_results_overlay.dart
- lib/features/songs/widgets/enrichment_progress_overlay.dart

## Files Modified

- lib/features/songs/song_enrichment_service.dart (added enrichBatch method and EnrichmentSongInput/SongEnrichmentBatchResult classes)
- lib/features/setlists/setlist_repository.dart (added enrichSongs batch update method at line ~3275)
- lib/features/setlists/widgets/song_details_bottom_sheet.dart (added "Enrich Song Data" button and \_handleEnrichSong handler, converted to ConsumerStatefulWidget)
- lib/features/setlists/setlist_detail_screen.dart (added "Enrich X Songs" multi-select button and "Enrich All" catalog action button with handlers \_handleEnrichSelectedSongs and \_handleEnrichAllCatalogSongs)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 1 info warning

Info warning:

- `use_build_context_synchronously` in setlist_detail_screen.dart line 1443 (expected when using BuildContext after async gap, acceptable for this use case)

## Test Results

Not run — manual end-to-end testing required per §15 of ARCHITECT_PLAN.md. Automated test infrastructure exists but no tests were added as part of this phase per the plan.

## Verification

Manual steps performed (per ENGINEER.md protocol):

1. ✅ RPC migration applied successfully via `supabase db push --linked`
2. ✅ All infrastructure files created (orchestrator, selector, results/progress overlays)
3. ✅ All entry point wiring completed (song details, multi-select, catalog-wide)
4. ✅ Repository batch update method added
5. ✅ flutter analyze run - 0 errors confirmed
6. ✅ ENGINEER_REPORT.md created and verified on disk

End-to-end testing deferred to QA per plan §15 requirements:

- Single-song enrichment via details sheet
- Multi-select enrichment (3-5 songs)
- Catalog-wide enrichment (20-30 songs with progress overlay)
- Database verification of non-overwrite behavior

## Deviations From Architect Plan

One minor adjustment during implementation:

- SetlistRepository.enrichSongs() method signature changed from accepting typed EnrichmentUpdate class to accepting Map<String, Map<String, dynamic>> to avoid circular dependency between features/setlists and features/songs. This maintains clean separation of concerns while preserving full functionality.

All other tasks completed exactly as specified in §14 (Engineer Task Breakdown) and §7.1 (RPC Migration). Implementation follows the three-layer pattern (SongEnrichmentService → SongEnrichmentOrchestrator → UI entry points) and respects the non-overwrite semantics (NULL sentinel for musical_key, 0 sentinel for duration_seconds).

## Blockers Encountered

None.

## Ready For QA

Yes. All code compiles with 0 errors, all tasks complete, migration applied, and manual verification performed. QA should execute §15 test scenarios to verify:

1. Single-song enrichment flow
2. Multi-select enrichment (3-5 songs)
3. Catalog-wide enrichment (20-30 songs)
4. Non-overwrite behavior validation (both musical_key NULL sentinel and duration_seconds 0 sentinel)
5. Progress overlay display for 50+ song batches
6. GetSongBPM API integration and rate limit handling
7. iTunes/MusicBrainz fallback for duration enrichment
