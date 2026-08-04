# Engineer Report

## Feature Slug

bug/song-card-metrics-spacing

## Feature Title

Song Card Metrics Spacing

## Goal

Improve song-card metric-row spacing so built-in tuning labels remain legible under constrained widths, while keeping changes strictly layout-only and limited to the Architect-scoped files.

This update addresses four gate-review findings before QA.

## Architect Tasks Completed

- [x] Task 1 — Updated `SongCardLayout` metric tokens in `design_tokens.dart`.
- [x] Task 2 — Refactored `song_card.dart` `_buildMetricsRow` to keep the key slot reserved for all songs.
- [x] Task 3 — Updated `reorderable_song_card.dart` `_buildMetricsRow` to keep the key slot reserved for all songs.
- [x] Task 4 — Performed narrow-width evaluation and applied `SongCardLayout.trailingColWidth` minimum-reservation strategy when width allows.
- [x] Task 5 — Verified `SongMetricsRow(` remains unreferenced outside `song_metrics_row.dart` and left that file untouched.
- [x] Task 6 — Ran `git diff --stat` and verified only planned implementation files changed.

## Files Created

- docs/features/song-card-metrics-spacing/ENGINEER_REPORT.md

## Files Modified

- lib/app/theme/design_tokens.dart
- lib/features/setlists/widgets/song_card.dart
- lib/features/setlists/widgets/reorderable_song_card.dart

## Final Token Values Chosen

In `SongCardLayout`:

- `metricsGutter`: `6.0` (was `12.0`)
- `bpmColWidth`: `76.0` (was `68.0`)
- `durationColWidth`: `60.0` (unchanged vs pre-feature baseline)
- `keyColWidth`: `56.0` (was `64.0`)
- `trailingColWidth`: unchanged at `128.0`

## Gate Issue 1: AnimatedValueText Overhead Verification

`song_card.dart` BPM/Duration render via `AnimatedValueText`, which adds:

- horizontal padding: `10 + 10 = 20px`
- border: `1px` each side normally (`2px total`), up to `2px` each side when focused (`4px total`)

Effective inner text width budget by column:

- BPM at old `58px` => `58 - 20 - 2 = 36px` normal (`34px` worst border): too small for `999 BPM`.
- BPM at new `76px` => `76 - 20 - 2 = 54px` normal (`52px` worst border): fits `999 BPM`.
- Duration at new `60px` => `60 - 20 - 2 = 38px` normal (`36px` worst border): fits `59:59`.
- Key badge slot remains `56px`; with badge horizontal padding `12 + 12`, text budget is `32px`, sufficient for documented key labels like `F#m`.

Conclusion: `58px` BPM was unsafe once `AnimatedValueText` chrome is accounted for; token increased to `76px`.

## Gate Issue 2: Key Slot Positional Consistency

Decision: **Always reserve the key slot**.

- Tony explicitly required that with-key and keyless songs be treated the same for horizontal positioning.
- The key slot and its gutter stay reserved in both live metric-row widgets, and the empty state renders `const SizedBox.shrink()` inside the reserved slot.
- This preserves identical horizontal positions for BPM, Duration, Key, and Tuning whether the key is present or not.

## Trailing Minimum-Reservation Strategy

Applied.

Details:

- Both live metric rows now compute whether there is enough row width to reserve `SongCardLayout.trailingColWidth` for tuning.
- If yes, tuning gets a fixed trailing slot of `128.0`.
- If no, tuning falls back to `Expanded` so the row still degrades gracefully without hard overflow.

## Gate Issue 3: Realistic Metrics-Row Width Verification

Re-ran width check using actual card math from live layout:

- List horizontal padding: `Spacing.pagePadding = 16` each side
- Metrics-row content inset: `contentLeftPadding = 36`, `cardHorizontalPadding = 16`
- Row width formula by screen width `W`: `(W - 32) - 36 - 16 = W - 84`

Representative phones:

- `W=375` => metrics row width `291`
- `W=390` => metrics row width `306`

With current tokens:

- Leading width for all songs = `76 + 6 + 60 + 6 + 56 + 6 = 210`

`canReserveTrailingColumn` (`leading + 128 <= rowWidth`):

- All songs @375: `210 + 128 = 338 > 291` => `false`
- All songs @390: `210 + 128 = 338 > 306` => `false`

Plain statement for review:

- With the key slot always reserved, the 128px tuning reservation does not trigger on representative phones for any song.
- That is expected and acceptable: tuning consistently falls back to `Expanded` on phones, while the fixed trailing reservation still applies on wider tablet/desktop/web layouts.
- The result keeps all four metrics horizontally aligned regardless of key presence.

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings (`No issues found!`)

## Test Results

Not run (Architect plan did not require `flutter test`; scope is layout-only and validated via analyzer + targeted layout checks).

## Verification

Manual steps performed:

- Confirmed working branch: `bug/song-card-metrics-spacing`.
- Confirmed `SongMetricsRow(` usage only appears in `song_metrics_row.dart` constructor definition.
- Verified both live widgets (`song_card.dart`, `reorderable_song_card.dart`) consume `SongCardLayout` spacing/width tokens.
- Confirmed the plain card tuning labels now use one-line ellipsis safety in both the custom-tuning and standard-tuning paths.
- Confirmation: both tuning branches in `lib/features/setlists/widgets/song_card.dart` now include `maxLines: 1`, `overflow: TextOverflow.ellipsis`, and `softWrap: false`.
- Verified `git diff --stat` scope after implementation includes only the three planned files.
- Deleted stray repo-root file `trailing`.
- Re-ran `git status --short` after cleanup to confirm no stray root artifact remains.

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes.
