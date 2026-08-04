# Engineer Report

## Feature Slug

feature/song-key-tuning-none-option

## Feature Title

Song Key + Tuning None Option

## Goal

Implement reliable clear-to-unset behavior for musical key and tuning across setlist surfaces. Add explicit None picker options, route clears through dedicated clear RPC methods, and keep unset tuning visually distinct from Standard.

## Architect Tasks Completed

- [x] Task 1 - Created migration to extend clear_song_metadata with p_clear_musical_key and musical_key NULL clear branch.
- [x] Task 2 - Added clearSongTuningOverride in repository with clear_song_metadata RPC call and direct-update fallback.
- [x] Task 3 - Added clearSongMusicalKeyOverride in repository with clear_song_metadata RPC call and direct-update fallback.
- [x] Task 4 - Added clearSongTuning and clearSongMusicalKey controller methods with optimistic update, rollback, and broadcaster updates.
- [x] Task 5 - Updated setlist_detail_screen save routing for tuning/key clear vs set behavior.
- [x] Task 6 - Updated key picker with explicit None option above Major while preserving tap-selected-key toggle clear.
- [x] Task 7 - Updated tuning picker with explicit None option above grouped options and clear signal return with Save enabled.
- [x] Task 8 - Updated reorderable song card tuning callback flow to support clear signal from picker.
- [x] Task 9 - Updated Song Details tuning state init/comparison/display so unset remains unset and displays as em dash.
- [x] Task 10 - Verified plan-targeted picker call paths (song details, reorderable card, enrichment key picker behavior via shared key picker update).

## Files Created

- supabase/migrations/20260803153000_add_clear_musical_key_to_clear_song_metadata.sql
- docs/features/song-key-tuning-none-option/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/key_picker_bottom_sheet.dart
- lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
- lib/features/setlists/widgets/song_details_bottom_sheet.dart
- lib/features/setlists/widgets/reorderable_song_card.dart
- lib/features/setlists/setlist_detail_screen.dart
- lib/features/setlists/setlist_detail_controller.dart
- lib/features/setlists/setlist_repository.dart

## Analyzer Results

Command: flutter analyze
Result: 0 errors / 0 warnings

## Test Results

Not run (Architect plan required flutter analyze; no explicit test command required)

## Verification

Manual steps performed:

- Read required agent/rules/plan docs in full before implementation.
- Verified branch is feature/song-key-tuning-none-option.
- Verified clean working tree before edits via git status.
- Formatted changed Dart files only using dart format.
- Ran flutter analyze and confirmed no issues.
- Generated git diff for complete change inspection.

## Full Git Diff Summary

Changed tracked files (git diff --stat):

- lib/features/setlists/setlist_detail_controller.dart | 154 insertions/deletions delta (+)
- lib/features/setlists/setlist_detail_screen.dart | 26 insertions/deletions delta
- lib/features/setlists/setlist_repository.dart | 152 insertions/deletions delta (+)
- lib/features/setlists/widgets/key_picker_bottom_sheet.dart | 18 insertions/deletions delta
- lib/features/setlists/widgets/reorderable_song_card.dart | 14 insertions/deletions delta
- lib/features/setlists/widgets/song_details_bottom_sheet.dart | 32 insertions/deletions delta
- lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart | 13 insertions/deletions delta

Untracked new file included in implementation:

- supabase/migrations/20260803153000_add_clear_musical_key_to_clear_song_metadata.sql (81 lines)

Aggregate tracked diff totals:

- 7 files changed
- 368 insertions(+)
- 41 deletions(-)

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

## Addendum - 2026-08-03 QA Follow-up

- Updated the Song Details tuning metric tile in lib/features/setlists/widgets/song_details_bottom_sheet.dart to always render tuning via tuningShortLabel(\_currentTuning).
- Removed the local base-tuning lookup in \_buildMetricsRow because it was only supporting the verbose picker-label branch and was no longer needed.
- Expected display behavior after this fix: compact tuning labels remain consistent with the rest of the app, including capo suffixes such as Standard • C3.

## Addendum - 2026-08-03 QA Follow-up (Final call-site parity)

- Fixed the missed tuning clear routing in lib/features/setlists/new_setlist_screen.dart by matching the approved pattern used in lib/features/setlists/setlist_detail_screen.dart.
- Updated ReorderableSongCard onTuningChanged handler to call clearSongTuning(song.id) when tuning.isEmpty, and updateSongTuning(song.id, tuning) otherwise.
- Re-searched all updateSongTuning( and updateSongMusicalKey( call sites in lib/features/setlists and confirmed this was the last direct bypass of clear routing.
