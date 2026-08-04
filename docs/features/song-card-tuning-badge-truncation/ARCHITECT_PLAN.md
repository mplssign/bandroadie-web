# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/song-card-tuning-badge-truncation

## 2. Branch and Workspace Check

Executed first in this session:

- `git status --short --branch`
- `git branch --show-current`

Observed state:

- Branch is `bug/song-card-tuning-badge-truncation`
- Dirty state is only this plan path (untracked feature docs directory containing only `ARCHITECT_PLAN.md`)
- No unrelated modified/staged files

Result: safe to continue Architect work.

## 3. Manager Scope Corrections — Verified in Live Code

### 3.1 `SongCard` is dead code for this bug

Verification command:

- `grep -RIn "SongCard(" lib | grep -v "ReorderableSongCard(" | grep -v "_SelectableSongCard("`

Observed result:

- Only declaration found: `lib/features/setlists/widgets/song_card.dart:32`
- No instantiation sites anywhere in app code

Architect decision:

- `song_card.dart` is out of scope for this bug.
- It is explicitly off-limits (do not edit, do not delete).

### 3.2 `_SelectableSongCard` is a third live metrics-row implementation

Verified in `lib/features/setlists/setlist_detail_screen.dart`:

- Live call site in Catalog Select Mode around line ~2520
- Widget declaration around line ~2850
- Private `_buildMetricsRow()` around line ~3012

Current behavior in that row:

- `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween)`
- Tuning label rendered as raw `Text(shortLabel)` inside a `Container`
- No `maxLines`, no `overflow`, no `softWrap: false`, no width bounding wrapper

Risk:

- Layout overflow is possible under long tuning labels.

Architect decision:

- Keep `_SelectableSongCard` in scope with a small isolated fix for graceful truncation only.

## 4. Problem Summary

The live four-column card (`ReorderableSongCard`) currently uses fixed widths (`SongCardLayout.bpmColWidth`, `durationColWidth`, `keyColWidth`) plus fixed gutters. This causes two user-visible problems:

1. Key truncation risk when the key badge intrinsic width exceeds the hard slot.
2. Wasted space from over-reserved columns on many rows.

Manager-corrected target behavior is spreadsheet-style shared columns across the whole list, not per-row intrinsic independence.

## 5. Root Cause

Root cause confidence: HIGH.

Confirmed causes in live code:

1. `ReorderableSongCard` metrics row in `lib/features/setlists/widgets/reorderable_song_card.dart` hard-codes fixed column widths and fixed gutters.
2. Width policy is local to the card and not derived from list-wide song content.
3. `_SelectableSongCard` tuning text has no overflow containment path.

## 6. Final Design (Supersedes Prior Revision)

### 6.1 Shared column model for live four-column card (`ReorderableSongCard`)

Target columns:

- BPM
- Duration
- Key
- Tuning

Design requirement:

- Compute column widths once per rendered list from the widest intrinsic value in the full song list (`state.songs`), not from visible viewport rows.

Why full list (not visible subset):

- Prevents column shifts while scrolling.
- Maintains stable vertical alignment across all rows in a list session.

### 6.2 Where computation happens

Compute shared widths where list cards are built and full `state.songs` is already available:

1. `lib/features/setlists/setlist_detail_screen.dart`
2. `lib/features/setlists/new_setlist_screen.dart`

Both pass the same shared width object into each `ReorderableSongCard` instance they construct.

### 6.3 `ReorderableSongCard` API change

Add constructor input for shared widths, e.g.:

- `final SongMetricsSharedWidths sharedWidths;`

`SongMetricsSharedWidths` fields:

- `bpmWidth`
- `durationWidth`
- `keyWidth`
- `tuningWidth`

This can live alongside `ReorderableSongCard` (same file) to avoid unnecessary new architecture.

### 6.4 Runtime row layout policy (using shared widths)

Given:

- `colSum = bpm + duration + key + tuning`
- `available = constraints.maxWidth`
- `leftover = available - colSum`

If `leftover >= 0`:

- `gap1 = gap2 = gap3 = leftover / 3`
- Values stay left-justified inside each column cell.

If `leftover < 0`:

- Collapse all gaps to zero.
- Preserve BPM, Duration, Key widths.
- Tuning gets remaining width only: `available - (bpm + duration + key)`.
- Tuning text truncates with ellipsis.

This directly matches the established policy: only tuning concedes.

### 6.5 Key reservation policy under shared columns

Decision: reserve Key column width even when an individual row has no key.

Reasoning:

1. In shared-column mode, column boundaries are list-wide; blank key cells are expected spreadsheet behavior.
2. Reserving key space preserves consistent alignment of the Tuning column across keyed and non-keyed rows.
3. This restores the original rationale, now correctly at list scope instead of per-row hard-coded scope.

### 6.6 Independent fix for `_SelectableSongCard`

Do not apply shared-column mechanism here.

Small fix only:

1. Constrain the tuning slot using `Expanded` or `Flexible` within the metrics `Row`.
2. Keep right anchoring for the badge.
3. Add tuning text overflow settings:

- `maxLines: 1`
- `overflow: TextOverflow.ellipsis`
- `softWrap: false`

Outcome:

- Graceful truncation replaces overflow risk.

## 7. Width Math (Measured and Honest)

Measurement source:

- CoreText measurement of `assets/fonts/DMSans-SemiBold.ttf` at 14px
- Key/Tuning badge horizontal padding included as `+24`

Reference row widths (current card geometry):

- At 375 screen width: `291` (`375 - 84`)
- At 390 screen width: `306` (`390 - 84`)

### 7.1 Representative realistic list (shared columns from full list)

Representative list used (includes confirmed production example):

1. `177 BPM` / `4:23` / `F#m` / `B Standard`
2. `132 BPM` / `3:58` / `G` / `Drop D`
3. `95 BPM` / `5:12` / `A` / `D Standard`

Computed shared column widths:

- BPM max: `54.22`
- Duration max: `29.13`
- Key max (badge): `56.44`
- Tuning max (badge): `99.50`

Shared sum:

- `239.30`

Fit math:

- 375: leftover `291 - 239.30 = 51.70`; each gap `17.23`
- 390: leftover `306 - 239.30 = 66.70`; each gap `22.23`

Result:

- Fully fits with healthy spacing; no truncation.

### 7.2 True worst-case combination (shared columns)

Specified worst-case values:

- BPM: `999 BPM`
- Duration: `59:59`
- Key: `G#m`
- Tuning: `D Standard • C12`

Computed widths:

- BPM: `59.47`
- Duration: `37.67`
- Key badge: `59.55`
- Tuning badge: `134.84`

Shared sum:

- `291.53`

Fit math:

- 375: overflow `0.53` (cannot fit even with zero gaps)
  - gaps collapse to `0`
  - tuning available: `291 - (59.47 + 37.67 + 59.55) = 134.31`
  - tuning truncation required: `134.84 - 134.31 = 0.53`
- 390: leftover `306 - 291.53 = 14.47`; each gap `4.82`

Result:

- 390 fits.
- 375 requires minimal tuning-only truncation (sub-pixel-level by measurement).

## 8. Files to Modify

1. `lib/features/setlists/widgets/reorderable_song_card.dart`

- Add shared-width constructor parameter/value object.
- Replace fixed `SongCardLayout` column constants usage in metrics row with external shared widths.
- Implement gap distribution and zero-gap fallback logic.
- Keep tuning as truncation concession path.

2. `lib/features/setlists/setlist_detail_screen.dart`

- Add a localized helper to compute shared widths from full `state.songs`.
- Compute once per list build path and pass into every `ReorderableSongCard`.
- Add small `_SelectableSongCard` overflow containment fix (Flexible/Expanded + tuning ellipsis settings).

3. `lib/features/setlists/new_setlist_screen.dart`

- Add corresponding localized helper to compute shared widths from full `state.songs`.
- Pass computed widths into every `ReorderableSongCard` in this screen.

## 9. Files Off-Limits

1. `lib/features/setlists/widgets/song_card.dart`

- Dead code for this bug (verified no instantiations).
- Do not modify and do not delete.

2. `lib/features/setlists/tuning/tuning_helpers.dart`

- Explicitly frozen by scope.

3. `lib/features/setlists/widgets/song_metrics_row.dart`

- Dead/unused widget path for this bug.

4. `lib/main.dart`

- Guardrails: initialization order unchanged.

## 10. Database / Backend Impact

Not applicable.

- Migrations: none
- RLS: none
- RPC: none
- Edge functions: none

## 11. Regression Risk

MEDIUM.

Rationale:

- UI-only change, but it affects two active list-building screens and one live private card variant.
- Shared-width computation and forwarding adds cross-widget contract risk.
- Worst-case edge handling must preserve the exact truncation policy.

## 12. Engineer Task Breakdown (Ordered)

1. Introduce shared-width value object + constructor parameter in `ReorderableSongCard`.
2. Update `ReorderableSongCard` metrics row to use shared widths, equal-gap distribution, and zero-gap fallback with tuning-only truncation.
3. In `setlist_detail_screen.dart`, add a small helper that computes shared widths from full `state.songs` and pass widths into all `ReorderableSongCard` call sites.
4. In `new_setlist_screen.dart`, add matching shared-width computation and pass-through.
5. Apply `_SelectableSongCard` tuning overflow containment fix (Flexible/Expanded + ellipsis settings).
6. Verify no edits were made to off-limits files.
7. Document measured/final outcomes in `ENGINEER_REPORT.md`.

## 13. Verification Plan

### Pre-implementation checks

1. Confirm branch and dirty state are limited to feature docs before code edits.
2. Confirm `SongCard` remains dead code in current repo state.
3. Confirm `_SelectableSongCard` is live in Catalog Select Mode.

### Post-implementation checks

1. `ReorderableSongCard` alignment stability:

- Scroll long lists and confirm column boundaries stay fixed across rows.

2. Representative list fit at 375 and 390:

- No key truncation.
- Even leftover gap distribution across three inter-column spaces.

3. Worst-case check:

- 390 fits.
- 375 collapses gaps and only tuning truncates.

4. Key-absent rows:

- Key column remains reserved (blank cell), preserving list-wide boundaries.

5. `_SelectableSongCard`:

- No RenderFlex overflow with long tuning.
- Tuning truncates gracefully with ellipsis.

## 14. Out of Scope

1. Deleting dead `SongCard` code.
2. Refactoring oversized `setlist_detail_screen.dart` beyond minimal localized helper edits.
3. Any changes to tuning naming/capo formatting logic.
4. Backend, database, auth, or routing changes.

## 15. Manager Gate Request

This is the final Architect revision and is ready for Manager gate approval.

If approved, it is ready for Engineer handoff.

No Engineer handoff is performed in this Architect step.
