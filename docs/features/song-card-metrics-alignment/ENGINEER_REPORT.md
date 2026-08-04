# Engineer Report

## Feature Slug

bug/song-card-metrics-alignment

## Feature Title

Song Card Metrics Alignment

## Goal

Refactor SongCard metrics layout so BPM, Duration, Key, and Tuning render as fixed, left-aligned columns. Keep the Key column reserved even when no key exists, and keep Tuning in a stable fixed column.

## Architect Tasks Completed

- [x] Task 1 — Added `SongCardLayout.keyColWidth` in `lib/app/theme/design_tokens.dart`.
- [x] Task 2 — Refactored `SongCard._buildMetricsRow()` in `lib/features/setlists/widgets/song_card.dart` to four fixed columns.
- [x] Task 3 — Ensured missing key leaves an empty reserved key column.
- [x] Task 4 — Kept non-layout behavior unchanged.

## Files Created

- docs/features/song-card-metrics-alignment/ENGINEER_REPORT.md

## Files Modified

- lib/app/theme/design_tokens.dart
- lib/features/setlists/widgets/song_card.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 new warnings

## Test Results

Not run (not required by Architect plan)

## Verification

Manual steps performed:

- Verified code path in `SongCard._buildMetricsRow()` now renders fixed-width columns in order BPM, Duration, Key, Tuning.
- Verified key column is always present and uses an empty placeholder when key is null/empty.
- Verified tuning column uses fixed width and left alignment instead of flexible right anchoring.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

---

## Addendum — 2026-08-03 (QA Critical #2 Overflow Safety)

### Reason for Revision

QA correctly identified that Key and Tuning badge labels could wrap/clip in fixed-width columns because their `Text` widgets did not enforce single-line overflow behavior.

### What Changed

- Updated `lib/features/setlists/widgets/song_card.dart` only.
- Added `maxLines: 1` and `overflow: TextOverflow.ellipsis` to:
  - Key badge text in `_buildKeyBadge()`
  - Tuning badge text in `_buildTuningBadge()` custom-tuning `FutureBuilder` branch
  - Tuning badge text in `_buildTuningBadge()` preset branch

### Scope Confirmation

- No changes to column widths, colors, spacing, padding, or interaction logic.
- No additional files touched for behavior changes.
- `lib/app/theme/design_tokens.dart` was not modified in this revision.

### Expected Outcome

- Key/Tuning badges now remain single-line within fixed columns and truncate cleanly instead of wrapping to a second line.

---

## Round 2 — Corrected Live Widget Path

### Summary

Round 1 edits were correctly reverted from the dead `song_card.dart` path, and the live setlist card layout was updated in `reorderable_song_card.dart` instead. The reusable `SongCardLayout.keyColWidth` token remained in `design_tokens.dart` and was reused by the corrected implementation.

### What Changed

- Restored `lib/features/setlists/widgets/song_card.dart` from `origin/main` so the dead widget no longer carries the incorrect layout change.
- Updated `lib/features/setlists/widgets/reorderable_song_card.dart` so `_buildMetricsRow()` now uses stable columns for BPM, Duration, and Key, with the Key slot always reserved even when the song has no key.
- Kept Tuning right-anchored in the live widget instead of converting it into a fixed left-aligned column.
- Added `maxLines: 1` and `overflow: TextOverflow.ellipsis` to the Key and Tuning badge text in the live widget for overflow safety.

### Files Modified This Round

- lib/app/theme/design_tokens.dart
- lib/features/setlists/widgets/reorderable_song_card.dart

### Verification

Manual steps performed:

- Confirmed `git diff -- lib/features/setlists/widgets/song_card.dart` shows no changes after the revert.
- Confirmed `SongCardLayout.keyColWidth` still exists in `lib/app/theme/design_tokens.dart`.
- Confirmed `setlist_detail_screen.dart` and `new_setlist_screen.dart` only instantiate `ReorderableSongCard` and do not need changes.
- Ran `flutter analyze` and confirmed 0 errors.

### Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 new warnings

### Ready For QA

Yes

---

## Round 3 — Tuning Width Budget

### Summary

Implemented the Round 3 width-budget correction in the live widget path (`ReorderableSongCard`) so Tuning now uses a deterministic reserved width slot, while BPM, Duration, and Key remain stable left-aligned columns with unchanged key-slot reservation behavior.

### Token Changes

Updated `lib/app/theme/design_tokens.dart` `SongCardLayout` values:

- `bpmColWidth`: `90.0 -> 56.0`
- `durationColWidth`: `80.0 -> 54.0`
- `keyColWidth`: unchanged at `64.0`
- `trailingColWidth`: `100.0 -> 128.0`

### `_buildMetricsRow()` Refactor

Updated `lib/features/setlists/widgets/reorderable_song_card.dart`:

- Replaced the Tuning `Expanded` leftover-space slot with a deterministic `SizedBox(width: SongCardLayout.trailingColWidth)`.
- Kept Tuning content right-aligned inside the reserved trailing slot.
- Preserved deterministic left-aligned BPM/Duration/Key columns and preserved the existing reserved Key slot when Key is missing.

### Round 3 Correction Note (Same Round)

- Corrected Tuning column alignment in `lib/features/setlists/widgets/reorderable_song_card.dart` `_buildMetricsRow()` from `Alignment.centerLeft` to `Alignment.centerRight` per the original requirement.
- BPM, Duration, and Key remain `Alignment.centerLeft`.

### Approved Deviation (Manager-Reviewed)

Deviation from the written Round 3 task list was applied exactly as pre-approved:

- Added `maxLines: 1` + `overflow: TextOverflow.ellipsis` (plus `softWrap: false`) to BPM and Duration `Text` widgets in:
  - `_buildBpmValue()`
  - `_buildDurationValue()`

Justification:

- The schema has no `CHECK` constraint on `bpm` (plain `INTEGER`), and Round 3 intentionally shrinks BPM/Duration width budgets. This overflow guard is a defensive safety net so edge-case values truncate cleanly rather than overflow if encountered on-device.
- In normal values, this does not change visual behavior.

### Files Modified This Round

- lib/app/theme/design_tokens.dart
- lib/features/setlists/widgets/reorderable_song_card.dart

### Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings (`No issues found!`)

### Ready For QA

Yes (diff left uncommitted for QA)

---

## Round 4 — Restore Right-Edge Tuning + BPM Safety Margin

### Summary

Applied the Round 4 correction in the live widget path to fix both Round 3 regressions:

- **BPM clipping regression:** increased the BPM column width so values no longer clip (for example, `160 BPM`).
- **Tuning anchor regression:** restored Tuning to a flexible trailing region so it remains right-edge anchored on wider screens.

### What Changed

1. Updated metric width tokens in `lib/app/theme/design_tokens.dart`:

- `bpmColWidth`: `56.0 -> 68.0`
- `durationColWidth`: `54.0 -> 60.0`
- `keyColWidth`: unchanged at `64.0`
- `trailingColWidth`: unchanged at `128.0` (intentionally retained for out-of-scope dead code references)

2. Updated `_buildMetricsRow()` in `lib/features/setlists/widgets/reorderable_song_card.dart`:

- Replaced Tuning fixed slot
  - from: `SizedBox(width: SongCardLayout.trailingColWidth, child: Align(alignment: Alignment.centerRight, child: _buildTuningBadge()))`
  - to: `Expanded(child: Align(alignment: Alignment.centerRight, child: _buildTuningBadge()))`
- BPM, Duration, and Key columns remain fixed-width `SizedBox` + `Align(alignment: Alignment.centerLeft)`.
- Key reserved-slot-when-missing behavior remains unchanged.
- Existing `maxLines: 1` + `TextOverflow.ellipsis` safety net remains intact on all four metric text/badge text widgets.

### Exact Diff (Round 4)

```diff
diff --git a/lib/app/theme/design_tokens.dart b/lib/app/theme/design_tokens.dart
@@ class SongCardLayout
-  static const double bpmColWidth = 56.0;
+  static const double bpmColWidth = 68.0;

-  static const double durationColWidth = 54.0;
+  static const double durationColWidth = 60.0;

diff --git a/lib/features/setlists/widgets/reorderable_song_card.dart b/lib/features/setlists/widgets/reorderable_song_card.dart
@@ Widget _buildMetricsRow()
-          SizedBox(
-            width: SongCardLayout.trailingColWidth,
-            child: Align(
-              alignment: Alignment.centerRight,
-              child: _buildTuningBadge(),
-            ),
+          Expanded(
+            child: Align(
+              alignment: Alignment.centerRight,
+              child: _buildTuningBadge(),
+            ),
        ),
```

### Analyzer Results

Command: `flutter analyze`  
Result: 0 errors / 0 warnings (`No issues found!`)

### Ready For QA

Yes (all Round 4 changes left uncommitted)
