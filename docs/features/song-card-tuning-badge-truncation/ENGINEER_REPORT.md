# Engineer Report

## Feature Slug

bug/song-card-tuning-badge-truncation

## Feature Title

Song Card Tuning Badge Truncation

## Goal

Implement shared, list-level metrics column widths for live reorderable song cards so BPM/Duration/Key remain stable while tuning is the only truncation concession under tight width, and apply a small independent overflow fix for `_SelectableSongCard` tuning text.

## Architect Tasks Completed

- [x] Task 1 — Introduced `SongMetricsSharedWidths` value object and new required `sharedWidths` constructor parameter on `ReorderableSongCard`.
- [x] Task 2 — Updated `ReorderableSongCard` metrics row to use shared widths, equal three-way leftover gap distribution, and zero-gap fallback where only tuning concedes.
- [x] Task 3 — Added localized helper in `setlist_detail_screen.dart` that computes shared widths from full `state.songs` and passed widths to all `ReorderableSongCard` construction paths.
- [x] Task 4 — Added matching localized shared-width helper in `new_setlist_screen.dart` and passed widths into `ReorderableSongCard`.
- [x] Task 5 — Applied `_SelectableSongCard` tuning overflow containment fix using bounded width (`Expanded`) plus `maxLines: 1`, `overflow: TextOverflow.ellipsis`, and `softWrap: false`.
- [x] Task 6 — Verified off-limits files were not edited.
- [x] Task 7 — Documented implementation details and outcomes in this report.

## Files Created

- docs/features/song-card-tuning-badge-truncation/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/reorderable_song_card.dart
- lib/features/setlists/setlist_detail_screen.dart
- lib/features/setlists/new_setlist_screen.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results

Not run (Architect plan did not require `flutter test`).

## Verification

Manual and static verification performed:

- Confirmed branch was `bug/song-card-tuning-badge-truncation`.
- Confirmed pre-edit dirty state was limited to the feature docs folder containing only `ARCHITECT_PLAN.md`.
- Confirmed `ReorderableSongCard` constructor now requires shared widths and both screen call sites pass them.
- Confirmed key column reservation is preserved by always allocating key slot width and rendering blank cell when key is absent.
- Confirmed layout policy implementation:
  - `leftover >= 0`: leftover split evenly into three inter-column gaps.
  - `leftover < 0`: all gaps collapse to zero and only tuning width is reduced.
- Confirmed `_SelectableSongCard` tuning text now has bounded width and ellipsis behavior.

## Memoization Approach (Guardrails §5 Compliance)

Shared-width computation is memoized in both screens with a local cache and staged invalidation:

1. Fast-path cache hit (no list scan):
   - If the current songs list is the same list instance (`identical`) and length is unchanged, cached `SongMetricsSharedWidths` is returned immediately.
   - This avoids rescanning/recomputing during rebuilds caused by scrolling, animation frames, or unrelated state flags when songs are unchanged.

2. Signature-path reuse (content unchanged across new list instance):
   - If list identity differs, a signature is computed from only width-relevant fields for each song: `bpm`, `durationSeconds`, `musicalKey`, and `tuning`.
   - If signature and song count match cache, previously computed widths are reused and only the cached list reference is refreshed.

3. Recompute only on relevant content change:
   - Width measurement (the expensive full-list `TextPainter` pass) only runs when the cached signature/count differ.
   - Therefore shared width calculation is not recomputed on every build; it reruns only when underlying width-driving song data changes.

This satisfies the non-optional requirement to avoid recomputing shared widths on unrelated rebuilds.

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Off-Limits Files Confirmation

No edits were made to off-limits files:

- `lib/features/setlists/widgets/song_card.dart`
- `lib/features/setlists/tuning/tuning_helpers.dart`
- `lib/features/setlists/widgets/song_metrics_row.dart`
- `lib/main.dart`

## Ready For QA

Yes

---

## Follow-Up Addendum (2026-08-04)

### Why this follow-up exists

Tony reported two regressions after initial QA:

1. 3-digit BPM values can still truncate.
2. Tuning badge should have about 2 extra characters of breathing room.

### Root-cause investigation (confirmed)

Confirmed root cause is measurement precision and width policy at exact-fit boundaries:

- Shared widths were previously treated as exact minimums (`TextPainter.width` with no margin).
- In real rendering, tiny width deltas (rounding/sub-pixel/font rasterization) can make exact-fit values clip and trigger text ellipsis in a constrained `SizedBox`.
- That single failure mode explains both symptoms:
  - BPM occasionally truncates at 3 digits.
  - Tuning appears globally too tight.

Additional investigation points requested:

- `TextPainter` parity parameters:
  - Added `textScaler: MediaQuery.textScalerOf(context)` to match runtime text scaling.
  - Added `locale: Localizations.maybeLocaleOf(context)` to match locale shaping.
  - Set `textWidthBasis: TextWidthBasis.longestLine` explicitly (no behavior change expected for single-line labels, but removes ambiguity).
  - `strutStyle` was intentionally not added because these labels do not render with a custom strut and strut affects vertical metrics more than single-line width.

- Measurement style vs render style diff:
  - Before: measurement used an independent hard-coded `TextStyle`.
  - Render path uses local `TextStyle` merged with ambient defaults.
  - After: measurement style is derived from `DefaultTextStyle.of(context).style.merge(...)` with the same explicit size/weight/height values used by metric labels, reducing drift risk.

- Cache/staleness check:
  - Reviewed cache logic in both screens and state update flows.
  - Song updates in controller paths create updated lists and replace state, so signature/list checks invalidate as expected.
  - No evidence that stale cache is the primary cause for the reported truncation.

### Exact fix applied

In both:

- `lib/features/setlists/setlist_detail_screen.dart`
- `lib/features/setlists/new_setlist_screen.dart`

Added two explicit width buffers:

- Global text safety margin: `4.0px`
  - Implemented in `_measureTextWidth()` as:
    - `painter.width.ceilToDouble() + 4.0`
  - Rationale: convert fractional measured width to pixel-safe integer width, then add a small guard band against paint/layout edge drift.

- Tuning-specific extra width: `16.0px`
  - Implemented as an additive bump on top of measured tuning badge width:
    - `_measureBadgeWidth(tuningText, metricStyle) + 16.0`
  - Rationale: explicit product requirement for about two extra characters of tuning room.

Net effect:

- BPM/Duration/Key receive safer non-exact shared widths.
- Tuning receives the same safety treatment plus an additional 16px beyond measured content.

### Verification performed

1. Explicit scenario checked in shared-width policy:
   - 3-digit BPM label (`999 BPM`) with long tuning label (`D Standard • C12`).
2. Confirmed by updated sizing formulas:
   - BPM now has pixel-rounded width plus 4px headroom (no exact-fit boundary).
   - Tuning now has baseline safety plus +16px additional breathing room compared with prior implementation.
3. Analyzer gate:
   - `flutter analyze` -> No issues found (0 errors).

This follow-up is an addendum to the original implementation, not a rewrite.

---

## Second Follow-Up Addendum (2026-08-04)

### Trigger

Tony reported a visual spacing bug in mixed-tuning lists: when one row has a short tuning label (for example `Drop D`) and another row has a much longer tuning label, the short-tuning row appeared to have an oversized gap between Key and Tuning.

### Root cause confirmed

In the shared-width metrics row implementation (`ReorderableSongCard`), the Tuning slot was still using:

- `Align(alignment: Alignment.centerRight, ...)`

while the slot width itself is intentionally list-shared (`shared.tuningWidth`, based on the widest tuning in the list).

That combination caused the short tuning badge to be rendered at the far right edge of its column, leaving a large empty pocket on the left side of that column that visually reads like one oversized Key→Tuning gap.

### Code change

Scoped to one behavior line in:

- `lib/features/setlists/widgets/reorderable_song_card.dart`

Change made:

- Tuning slot alignment updated from `Alignment.centerRight` to `Alignment.centerLeft`.

No gap-sizing logic was changed.

### Sizing/gap logic re-validation

Confirmed current sizing policy already matches the intended rule and did not require adjustment:

- Shared tuning width remains list-wide (`shared.tuningWidth`), derived from the widest tuning label in the list.
- When `leftover >= 0`, the three inter-column gaps are already equal (`leftover / 3`).
- When `leftover < 0`, all gaps collapse to zero and only Tuning concedes width.

Therefore this fix is alignment-only, not sizing-related.

### Related right-alignment check

Checked `_SelectableSongCard` in `setlist_detail_screen.dart`:

- It still uses right anchoring for tuning by design.
- It does not use the shared-column mechanism that drives this bug.
- It is not part of this specific regression path.

No additional change was required there for this issue.

### Concrete rendering trace

Scenario: list contains one row with long tuning `D Standard • C12` and another with short tuning `Drop D`.

After this fix:

1. The Tuning column width is still sized from the long label (`shared.tuningWidth`).
2. In the short-label row, the Tuning badge now starts at the left edge of the Tuning column (immediately after the third gap).
3. BPM→Duration, Duration→Key, and Key→Tuning are perceived as three consistent inter-column gaps.
4. Any unused horizontal slack now appears as trailing whitespace to the right side of the row, not as a concentrated pocket before the Tuning badge.

---

## Third Follow-Up Addendum (2026-08-04)

### Why this reverses the prior addendum

After mockup review, Tony confirmed the intended final behavior is for the Tuning badge to be flush-right inside its shared-width Tuning column. That means the alignment-only change from the Second Follow-Up Addendum was incorrect for product intent and is explicitly reverted.

### Final confirmed behavior (mockup-verified)

- BPM, Duration, and Key remain fixed at shared list-level positions/widths.
- Tuning remains in a shared list-level width column and is right-aligned to that column edge.
- In mixed-length tuning lists, short tuning labels will show visible empty space before their flush-right badge when another row sets a wider shared tuning column.

Tony confirmed this is expected and correct, not a bug.

### Rationale for variable gap size between different lists

The reserved Tuning region is intentionally sized to the widest tuning value within the current list scope (setlist or Catalog). Because that widest value can differ by list, the apparent empty space before a short flush-right tuning badge can differ between different setlists. This is the designed spreadsheet-style behavior.

### Code change in this follow-up

Single behavior-line revert in:

- `lib/features/setlists/widgets/reorderable_song_card.dart`

Change:

- `Alignment.centerLeft` → `Alignment.centerRight` for the Tuning slot.

No changes were made to:

- leftover distribution (`leftover / 3`)
- negative-leftover fallback behavior
- safety margins (`+4px` text safety, `+16px` tuning buffer)
- memoization/signature cache approach
- per-list width scoping

### Final status

This bug's layout behavior is now believed to be final and aligned with Tony's reviewed/approved mockup.
