# Engineer Report

## Feature Slug

bug/enrich-song-data-button-position-reverted

## Feature Title

Enrich Song Data Button Position Reverted

## Goal

Relocate the existing Enrich Song Data button from the fixed bottom action area into the scrollable Song Details content region, placing it directly above the metadata metrics row. Keep behavior, callbacks, and styling unchanged.

## Architect Tasks Completed

- [x] Task 1 — Located the scrollable content Column in build() where \_buildSongInfo() and \_buildMetricsRow() were adjacent.
- [x] Task 2 — Moved the existing Enrich Song Data TextButton.icon block into the content column between \_buildSongInfo() and \_buildMetricsRow().
- [x] Task 3 — Removed the Enrich Song Data button block from \_buildFixedBottomActions().
- [x] Task 4 — Preserved the existing if (!widget.isReadOnly) guard so read-only mode still hides the button.
- [x] Task 5 — Kept enrichment logic, save logic, callback behavior, and style tokens unchanged.

## Addendum (Tony Request, Mid-Session)

- The original lost commit intent included both move and center behavior (`feat(songs): move and center Enrich Song Data button above metrics row`).
- Architect plan section 14 captured the move but omitted explicit centering.
- Per Tony request, the relocated button was additionally centered in its new scrollable position using the same approach from commit `0db426c` (wrapping the `TextButton.icon` in `Center`).

## Files Created

- docs/features/bug-enrich-song-data-button-position-reverted/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/song_details_bottom_sheet.dart

## Analyzer Results

Command: flutter analyze
Result: 0 errors. 1 existing info reported in unrelated file: lib/features/setlists/setlist_detail_screen.dart:1449:32 (use_build_context_synchronously). No new analyzer issues introduced by this change.

## Test Results

Not run (not required by Architect plan).

## Verification

Manual/source verification performed:

- Confirmed Enrich Song Data now appears in the scrollable body sequence after \_buildSongInfo() and before \_buildMetricsRow().
- Confirmed Enrich Song Data button is horizontally centered in its new scrollable position above the metrics row.
- Confirmed \_buildFixedBottomActions() now contains Save/Done and Cancel/Close controls only (plus existing enrichment completion text), with no Enrich button block.
- Confirmed guard behavior remains: button only renders when !widget.isReadOnly.
- Confirmed global diff stat before report creation showed only lib/features/setlists/widgets/song_details_bottom_sheet.dart modified.

## Before/After Placement

Before: Enrich Song Data rendered in \_buildFixedBottomActions() below Save/Done in the fixed footer.
After: Enrich Song Data renders in the scrollable content area between \_buildSongInfo() and \_buildMetricsRow(), centered above BPM/Duration/Tuning/Key.

## Deviations From Architect Plan

Explicit centering addendum applied mid-session at Tony's request to correct an Architect plan gap. This aligns implementation with the original commit intent (`move and center`) and did not alter logic or scope beyond presentation placement/alignment.

## Blockers Encountered

None.

## Ready For QA

Yes.
