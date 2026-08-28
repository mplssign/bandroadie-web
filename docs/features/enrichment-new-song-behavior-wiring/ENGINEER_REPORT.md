# Engineer Report

## Feature Slug

feature/enrichment-new-song-behavior-wiring

## Feature Title

Enrichment New Song Behavior Wiring

## Goal

Wire the existing `EnrichmentSettings.newSongBehavior` (`ask` / `auto` / `off`) into both new-song add flows so behavior matches band Settings, while preserving existing Ask behavior as the default path.

## Architect Tasks Completed

- [x] Task 1 — Converted `OriginalSongScreen` / `_OriginalSongScreenState` in `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` from `StatefulWidget` / `State` to `ConsumerStatefulWidget` / `ConsumerState`, with `flutter_riverpod` import added and no constructor/API changes.
- [x] Task 2 — In `original_song_screen.dart._handleSubmit()`, fetched `newSongBehavior` once per submit call using `ref.read(enrichmentSettingsProvider.future)` and branched the new-song path: `ask` unchanged (confirm dialog), `auto` direct enrichment call, `off` no enrichment (`bpm`/`musicalKey` null).
- [x] Task 3 — In `lib/features/setlists/widgets/song_lookup_overlay.dart._handleExternalSongTap()`, added the same three-way branch on `newSongBehavior`; `auto` uses inline `SongEnrichmentService(Supabase.instance.client).lookup(...)`, `off` skips enrichment and writes null `bpm`/`musicalKey`.
- [x] Task 4 — Ran `flutter analyze`; no errors and warning count remains at the existing project baseline.

## Files Created

- docs/features/enrichment-new-song-behavior-wiring/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart
- lib/features/setlists/widgets/song_lookup_overlay.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 8 issues (existing baseline retained)

Baseline output summary:

- 4 info-level issues
- 4 warning-level issues

## Test Results

Manual live validation completed by user (not automated QA).

## Code Efficiency / Bloat Check

Confirmed no dead branches or duplicate behavior wiring were introduced. The change reuses existing settings/provider infrastructure and existing enrichment services/dialogs/sheets instead of adding new abstractions.

## Verification

Live manual testing was performed by the user on branch `feature/enrichment-new-song-behavior-wiring` across both add-song flows:

- Original song entry flow (`OriginalSongScreen`)
- External search tap flow (`SongLookupOverlay`)

Validated behavior per setting value:

- Ask:
  - Original song still shows the existing "Enrich Song? Skip/Add" dialog.
  - External search tap still shows the existing review sheet with pre-fetched values.
  - Behavior confirmed unchanged from prior/default flow.
- Auto:
  - External search tap saves with BPM/Key auto-filled.
  - No dialog is shown.
- Off:
  - Song saves with no BPM/Key/duration enrichment values written.
  - No lookup call and no dialog.

## Deviations From Architect Plan

- Applied a corrective async-safety guard in `song_lookup_overlay.dart._handleExternalSongTap()` beyond the initial wiring scope:
  - Added `if (!mounted) return;` after awaiting `enrichmentSettingsProvider.future`.
  - Added `if (!mounted) return;` after awaiting the `auto` lookup call.
  - Removed the context workaround/suppression pattern so lifecycle safety is enforced directly via mounted checks.

This correction prevents `setState() called after dispose()` when users back out during async lookup gaps.

## Blockers Encountered

None.

## Ready For QA

Yes — settings wiring is implemented for both flows, Ask behavior is preserved, async lifecycle guards are in place, live manual validation is complete for Ask/Auto/Off, and analyzer remains at baseline with 0 errors.
