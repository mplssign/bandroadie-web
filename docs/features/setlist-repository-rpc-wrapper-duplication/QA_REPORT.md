# QA Report

## Feature Slug

`setlist-repository-rpc-wrapper-duplication`

## Feature Title

Consolidate duplicated updateSong*Override/clearSong*Override RPC wrappers in setlist_repository.dart

## Cycle Number

4

## Final Verdict

APPROVED

## Validation Summary

Independent cumulative cycle-4 QA reviewed the committed cycle-3 refactor and the uncommitted cycle-4 correction. The correction addresses Tony's failed manual test at the rendering boundary: cleared tuning already reaches both controller collections as `null`, but `ReorderableSongCard` previously passed that null to `tuningShortLabel`, whose historical fallback is `Standard`.

The same keyed card now renders no tuning badge for null or blank tuning while preserving the tuning column's reserved width. Focused and full automated checks pass. Verification was code-path analysis and widget testing only; no app, simulator, device, browser, or production service was launched.

Regression risk: **MEDIUM** cumulatively because cycle 3 consolidates 11 metadata mutation methods. The cycle-4 UI correction itself is **LOW** risk.

## Architect Scope Review

- Branch, plan, Engineer report, and report path match `setlist-repository-rpc-wrapper-duplication`; the Engineer report is cycle 4.
- The committed cycle-3 implementation remains limited to the planned repository/controller refactor plus feature documentation.
- The cycle-4 implementation is limited to `reorderable_song_card.dart`, one focused widget test, and the Engineer report, as authorized by the corrective instruction following Tony's failed test.
- `git diff HEAD` is empty for `setlist_repository.dart`, `setlist_detail_controller.dart`, and `supabase/`; cycle 4 changes no repository, RPC, fallback, RLS, or database behavior.
- No unrelated source, configuration, dependency, platform, auth, routing, or initialization change was found.

## Completeness Check

Cycle 3 remains complete: both private helpers exist, all 11 public wrappers retain their signatures and special-case behavior, and `debugFetchSongsRaw`/`debugSmokeTest` remain absent.

Cycle 4 is complete. The active production card checks null and trimmed blank tuning before building the badge, keeps the tuning `SizedBox`, and has a focused regression test that updates the same keyed card from `standard_e` to null.

## Behavior Verification

Code-path analysis confirmed the failed behavior and correction:

- Song Details routes null/empty tuning through `clearSongTuning`.
- `clearSongTuning` optimistically rebuilds the song without tuning, then calls `clearSongTuningOverride` and broadcasts `SongUpdateEvent(clearTuning: true)` after persistence.
- `_applySongUpdate` independently rebuilds cross-setlist copies without tuning when `clearTuning` is true.
- `_syncSongStateWith` updates both `state.songs` and song entries in `state.items`, the collection used by non-Catalog setlists.
- `SetlistSong.tuning` remains null through the model path. Persistence and state synchronization were not the defect.
- `tuningShortLabel(null)` returns `Standard`; the old unconditional `_buildTuningBadge()` therefore rendered the stale-looking badge from correct null state.
- The new `hasTuning` guard suppresses null and whitespace-only values. Non-empty values still use the unchanged `_buildTuningBadge()` path.
- The focused widget test first finds the populated `Standard` badge, then repumps the same keyed card with null tuning and confirms the badge is absent.

The tuning slot's `SizedBox(width: tuningWidth)` remains in the row and only its child becomes `SizedBox.shrink()`. BPM, duration, key, gaps, row height, and tuning-column geometry are unchanged.

Cumulative cycle-3 review reconfirmed the complete RPC parameter maps and direct fallback maps, RPC-first versus direct-first ordering, PGRST202/42883 and 42501 handling, eight-wrapper PGRST203 conversion, raw PGRST203 passthrough for title/artist, tuning normalization and RPC-only enum mapping, and YouTube/Lyrics payload-check asymmetry.

## Regression Check

- Setlist card tuning display: **LOW**. Populated and cleared transitions are covered by the focused widget test; blank suppression is confirmed in code.
- Setlist controller/broadcast/model synchronization: **LOW**. Read-only analysis confirms no cycle-4 changes and both local and broadcast clear paths still produce null tuning in both collections.
- Metadata repository and legacy `NULL band_id` RLS fallback: **MEDIUM** cumulatively. Cycle-3 contracts remain intact in code; cycle 4 has no diff in these files.
- Layout and rebuild behavior: **LOW**. The same keyed stateful card is exercised, and the reserved tuning slot dimensions are unchanged.
- Gigs, rehearsals, Catalog sorting, members, auth/session, routing, notifications, deep links, Firebase/init order, FocusNode/controller disposal, async mounted checks, and platform parity: **LOW**. No controlling code changed.

## Database Safety

Not applicable. Neither the committed cumulative diff nor cycle-4 working diff changes `supabase/`, migrations, RPC signatures, grants, RLS, or SECURITY DEFINER functions. No database branch or privilege probe was required.

## Analyzer Results

`flutter analyze`: **PASS**. No issues found at any severity.

## Test Results

- Focused `reorderable_song_card_test.dart`: **PASS**, 1 test, 0 failures.
- Full `flutter test`: **PASS**, 297 tests, 0 failures.

## Diff Safety Review

- `git diff --check HEAD`: clean.
- No secret, API key, `TODO`, `FIXME`, `debugPrint`, scaffold, migration, or accidental deletion was added by cycle 4.
- The test file is intentionally untracked at QA time and is expected pipeline state, not a defect.
- No repository, controller, RPC, or Supabase hunk exists in cycle 4.

## Change Budget Review

Cycle 3 remains within the Architect budget: `setlist_repository.dart` is net -505 lines and `setlist_detail_controller.dart` is net -13 lines, with exactly two private helpers and no new public API or dependency.

Cycle 4 adds 4 and removes 1 line in `reorderable_song_card.dart`, plus one 61-line widget test. This is narrowly proportional to the corrective instruction. The production file is 520 lines, above the general 400-line widget target; the Engineer report gives the required justification that it was already 518 lines and splitting it is unrelated to this fix.

## Code Efficiency Review

No production helper, provider, field, parameter, class, dependency, or wrapper was added. Independent search found no existing `ReorderableSongCard` test or equivalent production visibility helper. The local boolean is used once to mirror the existing key-slot visibility pattern and avoids changing the shared tuning label fallback used by other surfaces.

## Manual Verification Punch List

Owner-run only. Build PR #285 on a real iOS device or Simulator, log in, and open a setlist containing a song with a populated tuning.

1. Confirm the song card shows its populated tuning badge, then open Song Details. **Expected:** the card and Song Details show the same tuning.
2. Clear tuning in Song Details and save. **Expected:** save succeeds, Song Details shows tuning unset, and the card's tuning badge disappears immediately without displaying `Standard`.
3. Reopen Song Details for the same song. **Expected:** tuning remains unset and the card still has no tuning badge.
4. Navigate away and back or pull to refresh. **Expected:** tuning remains unset and no tuning badge appears after data reload.
5. In Song Details, set tuning to Half-Step Down and save. **Expected:** the card shows `Half-Step` immediately and still shows it after reload.
6. Clear that tuning using the card's tuning control, if available on this setlist. **Expected:** the badge disappears and remains absent after reload.
7. Repeat the clear on a second setlist containing the same song. **Expected:** every open/listened setlist copy loses the tuning badge after the broadcast update.
8. During all steps, inspect BPM, duration, and musical-key columns on neighboring cards. **Expected:** values remain aligned; the missing tuning badge does not shift or resize other metric columns.
9. Watch for snackbars, red overlays, unexpected reloads, or save failures. **Expected:** none.

The PGRST202/42883 fallback path remains static-analysis-only because exercising it would require removing an RPC. It must not be tested against production.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.

No findings in categories `root-cause-diagnosis`, `implementation-gap`, `regression`, `database-safety`, `code-quality`, or `out-of-scope`.