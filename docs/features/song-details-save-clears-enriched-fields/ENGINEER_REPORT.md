# Engineer Report

## Feature Slug

bug/song-details-save-clears-enriched-fields

## Feature Title

Song Details Save Clears Enriched Fields

## Goal

Prevent stale Song Details local metadata state from being interpreted as intentional clears after async enrichment updates. Ensure local editable values and change-detection baselines are re-synced immediately after successful enrichment so Save only persists deliberate user edits.

## Architect Tasks Completed

- [x] Task 1 — Added local baseline state variables for BPM and duration in Song Details state.
- [x] Task 2 — Initialized BPM/duration baselines in `initState` alongside existing local fields.
- [x] Task 3 — Extracted changed-field comparison logic into `_computeChangeFlags()` and reused it in `_checkForChanges` and `_handleSave`.
- [x] Task 4 — Added post-enrichment refresh/rebaseline flow in `_handleEnrichSong` for current song when enrichment reports updated metadata.
- [x] Task 5 — Kept existing UI structure unchanged.
- [x] Task 6 — Ran static analysis and performed targeted manual/code-path validation.

## Files Created

- docs/features/song-details-save-clears-enriched-fields/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/song_details_bottom_sheet.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 1 info warning.
Warning listed:

- `use_build_context_synchronously` at `lib/features/setlists/setlist_detail_screen.dart:1449` (pre-existing, out of scope)

No new warnings remain in `song_details_bottom_sheet.dart` from this implementation.

## Test Results

Not run (not required by Architect plan).

## Verification

Manual/code-path steps performed:

- Verified change detection now compares BPM/duration against local maintained baselines (`_originalBpm`, `_originalDurationSeconds`) through shared helper logic.
- Verified `_handleSave` consumes the same helper output used by `_checkForChanges`, preventing divergence.
- Verified enrichment flow now checks per-song enrichment outcomes and only re-fetches song metadata when at least one metadata field was updated for current song.
- Verified refresh updates both editable values and baselines for BPM/duration/key in one `setState`, then recomputes `_hasChanges` immediately.
- Verified async mounted guard after refresh to keep context usage safe.

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes
