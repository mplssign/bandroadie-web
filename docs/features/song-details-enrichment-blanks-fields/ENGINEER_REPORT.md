# Engineer Report

## Feature Slug

bug/song-details-enrichment-blanks-fields

## Feature Title

Song Details Enrichment Blanks Fields — Fix

## Goal

Fix bug where Song Details enrichment can blank out BPM/Duration/Key fields and disable Save button by implementing selective post-enrichment merge instead of wholesale field replacement from DB snapshot.

## Architect Tasks Completed

- [x] Task 1 — Capture current song's `SongEnrichmentDetail` from `result.details` after orchestrator returns
- [x] Task 2 — Replace full `_refreshAndRebaselineMetadata` logic with selective apply rules (only apply fields with `updated` status)
- [x] Task 3 — Recompute `_hasChanges` after selective merge
- [x] Task 4 — Keep `_justEnriched` assignment behavior after enrichment completion
- [x] Task 5 — Ensure no changes made outside allowed file

## Files Created

- none

## Files Modified

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 1 info (pre-existing in unrelated file `setlist_detail_screen.dart`)

## Test Results

Not run (Architect plan did not require test execution)

## Verification

Manual steps performed:

- Confirmed `_refreshAndRebaselineMetadata()` now accepts `SongEnrichmentDetail` parameter
- Confirmed selective field merge logic only applies fields where `EnrichmentFieldResult.updated`
- Confirmed `_hasChanges` is recomputed after selective merge
- Confirmed `_justEnriched` behavior preserved
- Confirmed call site in `_handleEnrichSong()` now passes current song's detail via new helper `_findCurrentSongDetail()`
- Confirmed no files outside the allowed list were modified

## Changes Summary

1. Added helper method `_findCurrentSongDetail()` to extract current song's `SongEnrichmentDetail` from orchestration result
2. Modified `_refreshAndRebaselineMetadata()` signature to accept `SongEnrichmentDetail detail` parameter
3. Replaced wholesale field assignment with selective merge logic:
   - BPM: only applied if `detail.bpmResult == EnrichmentFieldResult.updated`
   - Duration: only applied if `detail.durationResult == EnrichmentFieldResult.updated`
   - Musical Key: only applied if `detail.keyResult == EnrichmentFieldResult.updated`
4. Updated call site in `_handleEnrichSong()` to retrieve detail and pass to `_refreshAndRebaselineMetadata()`
5. Preserved existing `_hasChanges` recomputation and `_justEnriched` flag behavior

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

---

## Implementation Notes

The fix addresses the root cause identified in the Architect plan: Song Details was performing a wholesale overwrite of all three metadata fields (`_currentBpm`, `_currentDurationSeconds`, `_currentMusicalKey`) from a DB snapshot whenever _any_ field was enriched, causing previously-visible values to be replaced with blanks if the DB contained null/0/empty for those fields.

The new implementation:

- Only overwrites fields that were actually updated during enrichment (`EnrichmentFieldResult.updated`)
- Preserves local values for fields with other statuses (`unchanged`, `notFound`, `error`, `notRequested`)
- Maintains the rebaseline behavior (setting `_original*` equal to `_current*`) only for fields that were actually enriched
- Keeps `_hasChanges` computation accurate after selective merge
- Preserves existing UX behavior with `_justEnriched` flag

This ensures the user never sees a misleading blank state, and the Save button remains correctly enabled/disabled based on actual field changes.
