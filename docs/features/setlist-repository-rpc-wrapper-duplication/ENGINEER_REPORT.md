# ENGINEER_REPORT

## Feature Slug

`setlist-repository-rpc-wrapper-duplication`

## Feature Title

Consolidate duplicated updateSong*Override/clearSong*Override RPC wrappers in setlist_repository.dart

## Cycle Number

4

## Goal

Correct Tony's failed manual PR test by ensuring a song card stops displaying a tuning badge after Song Details clears the persisted tuning, while preserving the Cycle 3 metadata helper refactor and all RPC/fallback behavior.

## Architect Tasks Completed

1. Traced Song Details tuning clear through `clearSongTuning`, the optimistic `songs`/`items` synchronization, and the `SongUpdateEvent(clearTuning: true)` listener.
2. Confirmed both state paths produce a `SetlistSong` with `tuning == null`; persistence and provider synchronization were already correct.
3. Corrected `ReorderableSongCard` so a null or blank reactive tuning value keeps its reserved layout slot but renders no badge.
4. Added a focused widget regression test that updates the same keyed stateful card from `standard_e` to a cleared tuning and verifies the `Standard` badge disappears.
5. Left `setlist_repository.dart`, its metadata helpers, and every RPC/fallback path unchanged.

## Files Created

- `test/features/setlists/widgets/reorderable_song_card_test.dart`

## Files Modified

- `lib/features/setlists/widgets/reorderable_song_card.dart`: conditionally renders the tuning badge only for a non-empty tuning.
- `docs/features/setlist-repository-rpc-wrapper-duplication/ENGINEER_REPORT.md`: updated for cumulative Cycle 4.

## Analyzer Results

- `flutter analyze lib/features/setlists/widgets/reorderable_song_card.dart`: passed, no issues immediately after the implementation edit.
- `flutter analyze lib/features/setlists/widgets/reorderable_song_card.dart test/features/setlists/widgets/reorderable_song_card_test.dart`: passed, no issues after formatting.
- `dart fix --dry-run`: nothing to fix.

## Test Results

- Focused `reorderable_song_card_test.dart`: passed, 1 test, 0 failures.
- Full `flutter test` was not run; Cycle 4 changes have direct focused widget coverage.

## Code Efficiency/Bloat Check

- Searched `lib/` for an existing song-card test harness or equivalent helper; none exists. Existing tests use local `_pump` helpers with the same `AppTheme`/`FTheme` setup, which the focused test follows.
- Added no production helper, provider, model, dependency, configuration, logging, or public API.
- `reorderable_song_card.dart` is 520 lines, above the 400-line feature-widget target, because it was already 518 lines and this correction adds only the two-line local visibility condition; splitting it is unrelated to the QA finding.
- The fix replaces unconditional badge rendering with conditional rendering; it does not layer state or another synchronization mechanism over the existing flow.
- No `TODO`, `FIXME`, or `debugPrint` was added.

## Verification

- Verified `clearSongTuning` optimistically clears both `state.songs` and `state.items`, then broadcasts `SongUpdateEvent(clearTuning: true)` after persistence.
- Verified `_applySongUpdate` also converts `clearTuning` into a model with `tuning == null` and synchronizes both lists.
- Verified the production setlist screen uses `ReorderableSongCard`; the older `SongCard` has no production call sites and was not changed.
- Pumped the same keyed `ReorderableSongCard` first with `standard_e`, then with a cleared model; the focused test confirms `Standard` changes from one match to zero matches.
- Ran scoped formatting on both Cycle 4 Dart files.
- Runtime device verification was not performed; Tony should repeat the failed Song Details clear-tuning step on the PR build.

## Deviations From Plan

The original refactor plan marked all UI files off-limits because it expected runtime-equivalent repository behavior. Tony's failed manual test demonstrated a user-visible issue outside those files. Per the Cycle 4 corrective instruction, the change is narrowly limited to the active song-card rendering path plus its focused regression test; the original repository and controller refactor files are unchanged.

## Blockers Encountered

None.

## Ready For QA

Yes.
