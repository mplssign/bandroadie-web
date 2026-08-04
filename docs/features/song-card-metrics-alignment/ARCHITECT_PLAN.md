# Architect Plan — Song Card Metrics Alignment

## 1. Feature Slug

`bug/song-card-metrics-alignment`

## 2. Problem Summary

On the setlist detail song cards, metric values do not occupy stable horizontal columns across rows.

Expected behavior is fixed, left-aligned columns in this order:

1. BPM
2. Duration
3. Key
4. Tuning

When Key is missing, its column must remain reserved (empty), and Tuning must stay in its own fixed column.

Observed behavior in code:

- Key is conditionally inserted into the `Row` only when present, so no placeholder slot exists.
- Tuning is placed in `Expanded` + `Align(centerRight)`, so it is anchored to the right edge of remaining space rather than a fixed left-aligned column.

This causes per-card horizontal drift of Key/Tuning positions.

## 3. Root Cause

Confidence: HIGH

Root cause is in `lib/features/setlists/widgets/song_card.dart` inside `_buildMetricsRow()`:

- Key is conditionally rendered with no fixed-width container or placeholder state.
- Tuning is rendered via flexible trailing layout instead of a fixed-width metric column.

BPM and Duration already use the correct fixed-width + left-aligned pattern and do not cause the bug.

## 4. Existing System Analysis

### Verified references

- `lib/features/setlists/widgets/song_card.dart`
- `lib/app/theme/design_tokens.dart`
- `lib/features/setlists/widgets/song_metrics_row.dart`

### Current metric row composition in `SongCard`

- BPM: fixed `SizedBox(width: SongCardLayout.bpmColWidth)` + `Align(centerLeft)`
- Duration: fixed `SizedBox(width: SongCardLayout.durationColWidth)` + `Align(centerLeft)`
- Key: inserted only when present; no reserved width
- Tuning: in `Expanded` with right alignment, not fixed to a stable metric column origin

### Dead-code verification: `SongMetricsRow`

Workspace search found no call sites for `SongMetricsRow` outside its own definition file. It appears currently unused. No change is required for this bug fix because the reported UI path is `SongCard` on setlist detail.

## 5. Proposed Minimal Solution

Implement only localized layout changes in `SongCard._buildMetricsRow()` to extend the existing fixed-column pattern.

### Required behavior after fix

- Four stable columns, left-to-right: BPM, Duration, Key, Tuning.
- Each column has fixed width and left-aligned content.
- Missing Key keeps an empty placeholder column; Tuning does not shift left.

### Design approach

1. Add a dedicated fixed width key column constant in `SongCardLayout` (design token).
2. Replace conditional key insertion with an always-present fixed `SizedBox` key column.
3. Render key badge inside that column only when a non-empty key exists; otherwise render an empty placeholder (`SizedBox.shrink()` or equivalent) within the reserved slot.
4. Replace `Expanded` tuning layout with fixed-width tuning column (`SongCardLayout.trailingColWidth`) and left alignment.
5. Keep existing BPM/Duration column sizes and gutter strategy unchanged.

### Column model (target)

- BPM: `SongCardLayout.bpmColWidth`
- Gutter: `SongCardLayout.metricsGutter`
- Duration: `SongCardLayout.durationColWidth`
- Gutter: `SongCardLayout.metricsGutter`
- Key: new `SongCardLayout.keyColWidth`
- Gutter: `SongCardLayout.metricsGutter`
- Tuning: `SongCardLayout.trailingColWidth`

Notes:

- Tuning text can vary (including async custom labels). Keep current badge rendering logic; only change the containing column strategy.
- Do not redesign typography, colors, badge style, interactions, or async data flow.

## 6. Database Impact

Not applicable.

No schema, RLS, RPC, migration, or Edge Function changes are required.

## 7. Flutter Architecture Impact

Localized widget-layout change only.

- State management: unaffected
- Repository/data flow: unaffected
- Controllers/providers: unaffected
- Platform-specific code: unaffected (shared widget across iOS/Android/macOS/Web)

## 8. Files to Create

None.

## 9. Files to Modify

| File                                           | Change                                                                                                                                                                                                    |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_card.dart` | Update `_buildMetricsRow()` to enforce fixed-width, left-aligned BPM/Duration/Key/Tuning columns; reserve key slot even when missing; replace flexible right-anchored tuning placement with fixed column. |
| `lib/app/theme/design_tokens.dart`             | Add `SongCardLayout.keyColWidth` token for key column sizing.                                                                                                                                             |

## 10. Files Off-Limits

| File                                                   | Reason                                                                    |
| ------------------------------------------------------ | ------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_metrics_row.dart`  | Verified unused for this flow; do not modify or delete in this bug scope. |
| `lib/features/setlists/setlist_detail_screen.dart`     | Not needed for root-cause fix; avoid unrelated screen/controller changes. |
| `lib/features/setlists/setlist_detail_controller.dart` | No state/data defect involved.                                            |
| `lib/main.dart`                                        | Initialization order guardrail; unrelated.                                |
| `supabase/migrations/*`                                | No database behavior changes.                                             |
| `pubspec.yaml`                                         | No dependency additions needed.                                           |

## 11. Regression Risk

Level: LOW

Rationale:

- Change is isolated to visual layout composition in one widget plus one layout token.
- No business logic, persistence, navigation, or permissions paths are touched.
- Existing badge rendering logic remains intact.

Primary risk to watch:

- Long key/tuning labels could clip within fixed columns.

Mitigation:

- Preserve existing `trailingColWidth` for tuning and select `keyColWidth` to fit expected key labels (e.g., `F#m`) without introducing new behavior.

## 12. Engineer Task Breakdown

1. Add `SongCardLayout.keyColWidth` in `lib/app/theme/design_tokens.dart`.
2. Refactor `SongCard._buildMetricsRow()` in `lib/features/setlists/widgets/song_card.dart` to a four fixed-column layout:
   - Keep BPM and Duration as-is.
   - Insert an always-present fixed key column.
   - Render key badge conditionally within the reserved key slot.
   - Convert tuning placement to fixed-width, left-aligned column.
3. Ensure missing key leaves an empty key column (no left-shift of tuning).
4. Keep all non-layout behavior unchanged.

## 13. Verification Plan

1. Open a setlist with mixed songs:
   - Key present + short tuning label
   - Key missing + short tuning label
   - Key present + longer tuning label
   - Key missing + custom/async tuning label
2. Confirm BPM left edges align vertically across all cards.
3. Confirm Duration left edges align vertically across all cards.
4. Confirm Key column origin is fixed; absent keys leave empty space.
5. Confirm Tuning column origin is fixed and never shifts left when Key is absent.
6. Confirm no interaction regressions (card tap, drag handle behavior, badge rendering).

## 14. Out of Scope

- Redesigning card visuals or spacing system.
- Introducing new widgets/abstractions for metrics rows.
- Reworking or deleting `SongMetricsRow` dead code.
- Any database, backend, auth, routing, or notification changes.

## 15. Correction - Round 2 (Retargeting to Live Widget)

### Why this correction is required

The prior diagnosis targeted `SongCard` in `lib/features/setlists/widgets/song_card.dart`.
That class is not the runtime path for setlist song cards.

Codebase verification:

- `grep -Rsn "SongCard(" lib` shows no runtime instantiation of `SongCard` in setlist UI flows.
- Live setlist card rendering is through `ReorderableSongCard` in:
  - `lib/features/setlists/setlist_detail_screen.dart` (main reorder list, draggable)
  - `lib/features/setlists/setlist_detail_screen.dart` (catalog/search branch, non-draggable)
  - `lib/features/setlists/new_setlist_screen.dart`

Conclusion: changes made only in `song_card.dart` are user-invisible for this bug.

### Corrected Problem Summary (Round 2)

In `ReorderableSongCard._buildMetricsRow()`, metrics are laid out with `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween)` and no fixed-width metric columns. This causes Duration and conditionally rendered Key to drift horizontally based on sibling presence and text widths.

Tony's expected behavior (verbatim intent): BPM, Duration, and Key should be left-aligned to stable fixed column positions across all cards; Tuning stays right-edge anchored.

### Corrected Root Cause

Confidence: HIGH

Primary failure exists in `lib/features/setlists/widgets/reorderable_song_card.dart`:

- `_buildMetricsRow()` uses spacing-based distribution instead of deterministic metric columns.
- Key is conditional and does not reserve a persistent slot when absent.
- Mid-row metric positions therefore shift across cards.

Secondary diagnosis error from Round 1:

- `lib/features/setlists/widgets/song_card.dart` was modified, but that widget is currently dead code for this flow.

### Corrected Minimal Solution

Apply deterministic metric columns in `ReorderableSongCard._buildMetricsRow()` only:

1. BPM fixed-width, left-aligned.
2. Duration fixed-width, left-aligned.
3. Key fixed-width, left-aligned, always reserved (empty placeholder when missing).
4. Tuning remains right-anchored behavior (do not force into left-aligned fixed metric slot).

Reuse existing token from Round 1:

- `SongCardLayout.keyColWidth` in `lib/app/theme/design_tokens.dart` is valid and should be reused.
- No additional design token changes are required unless implementation reveals clipping that cannot be resolved by existing badge overflow behavior.

### Corrected File Boundaries

#### Files to modify (Round 2)

| File                                                       | What changes                                                                                                                                               |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Refactor `_buildMetricsRow()` to fixed left-aligned columns for BPM/Duration/Key (with reserved key slot) while preserving right-anchored tuning behavior. |

#### Files off-limits (Round 2)

| File                                                  | Reason                                                                                                                      |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_card.dart`        | Confirmed dead for this user-visible flow; do not implement bug fix here. Revert prior incorrect edits to keep diff scoped. |
| `lib/features/setlists/widgets/song_metrics_row.dart` | Confirmed dead/unused for this flow; explicitly out of scope.                                                               |
| `lib/features/setlists/setlist_detail_screen.dart`    | Instantiation path is already correct; no flow change needed for alignment fix.                                             |
| `lib/features/setlists/new_setlist_screen.dart`       | Consumer path only; no direct fix needed if metrics row is corrected in `ReorderableSongCard`.                              |

### Decision on Existing Dirty Changes

`song_card.dart` currently has uncommitted changes from the incorrect pass. Because this widget is not on the active rendering path, those edits are out-of-scope for this bug and must be reverted to keep the fix user-visible and minimal.

Required revert command for Engineer:

`git checkout origin/main -- lib/features/setlists/widgets/song_card.dart`

Keep `lib/app/theme/design_tokens.dart` `keyColWidth` addition, because it is reused by the corrected `ReorderableSongCard` implementation.

### Regression Risk (Round 2)

Level: LOW

Rationale:

- Single-widget layout adjustment in active render path.
- No state, repository, controller, or backend changes.
- Reserved key slot reduces cross-card jitter risk.

Primary risk to validate:

- Right-anchored tuning behavior must remain visually consistent while middle columns become deterministic.

### Corrected Engineer Task Breakdown (Round 2)

1. Revert incorrect dead-widget edits first:
   - `git checkout origin/main -- lib/features/setlists/widgets/song_card.dart`
2. Confirm `SongCardLayout.keyColWidth` remains available in `lib/app/theme/design_tokens.dart` and unchanged unless strictly required.
3. Update `lib/features/setlists/widgets/reorderable_song_card.dart` `_buildMetricsRow()`:
   - Implement fixed-width, left-aligned BPM column.
   - Implement fixed-width, left-aligned Duration column.
   - Implement fixed-width, left-aligned Key column with always-reserved slot and empty placeholder when key is missing.
   - Preserve tuning right-edge anchored behavior.
4. Verify no usage/path changes are introduced in callers (`setlist_detail_screen.dart`, `new_setlist_screen.dart`).
5. Run analyzer and provide updated `ENGINEER_REPORT.md` noting the retarget and `song_card.dart` revert.

### QA Regression Focus (Round 2)

1. Mixed key presence list: cards with/without key must keep BPM/Duration/Key column starts aligned across rows.
2. Tuning must remain right-edge anchored in both draggable and non-draggable song-card contexts.
3. Catalog/search branch and setlist detail branch must show identical metric alignment behavior.
4. No regressions in drag affordance or card interactions.

### Out of Scope (Round 2)

- Deleting dead widgets (`SongCard`, `SongMetricsRow`).
- Refactoring setlist screens.
- Any design-system expansion beyond reusing existing `keyColWidth`.
- Any backend/database/auth changes.

### Follow-up Recommendation (separate future ticket)

Create a cleanup ticket to remove or formally deprecate confirmed dead widgets (`SongCard`, `SongMetricsRow`) after usage audit across branches.

## 16. Correction - Round 3 (Tuning Width Budget)

### Why this correction is required

Round 2 fixed the live widget path and made the key slot stable, but Tony’s device still shows the tuning badge label clipping when a preset tuning includes a capo suffix.

The remaining failure is not the label formatter. `tuningShortLabel()` already emits the correct value, including capo suffixes like `Standard • C3` and the longest realistic preset form `D Standard • C12`.

The failure is the width budget in the live metrics row:

- `BPM` and `Duration` reserve more width than their actual rendered content needs.
- `Key` is already tight and must stay unchanged.
- `Tuning` is still starved by the leftover row width, so the badge text gets ellipsized mid-string on real devices.

### Corrected Root Cause

Confidence: HIGH

Primary failure is in `lib/features/setlists/widgets/reorderable_song_card.dart` plus the width tokens it consumes from `lib/app/theme/design_tokens.dart`:

- The live row still does not reserve enough deterministic width for the tuning badge.
- The current `bpmColWidth = 90` and `durationColWidth = 80` are larger than needed for the longest realistic values those columns render.
- On a 390px-wide device, the usable content row is about `390 - 36 - 16 = 338px` after the existing left content inset and right padding. The current fixed columns consume too much of that budget before tuning is laid out.

### Pixel / Character Budget

The target tuning label to protect is `D Standard • C12`.

- Base preset label: up to 10 characters for the longest fixed presets in the short-label map.
- Capo suffix: up to 6 more visible characters, including the bullet and spaces.
- Badge padding: `12px` left + `12px` right = `24px` total.
- Font: `AppFontSizes.subhead` at `FontWeight.w600`.

That means the tuning column needs a reserved slot of roughly `128px` total to keep the badge from truncating on the reported device class.

To make room for that without shrinking the key column, reclaim width from the siblings that are oversized relative to their real content:

- `999 BPM` fits in a much narrower column than 90px.
- `99:59` fits in a much narrower column than 80px.

### Proposed Width Strategy

Use a deterministic reserved tuning slot instead of a pure leftover-width `Expanded`.

Concrete token changes:

- `SongCardLayout.bpmColWidth`: `90px -> 56px`
- `SongCardLayout.durationColWidth`: `80px -> 54px`
- `SongCardLayout.keyColWidth`: stay at `64px`
- `SongCardLayout.trailingColWidth`: `100px -> 128px`

Why these values:

- `56 + 12 + 54 + 12 + 64 + 12 + 128 = 338px`, which matches the usable content width budget on a 390px device with the current left inset and right padding.
- The BPM and Duration columns remain wide enough for their longest realistic strings, while the tuning badge gains a fixed slot large enough for the longest preset-plus-capo label.
- The key column stays unchanged because Tony explicitly said not to shrink it.

### Files to Modify for Round 3

| File                                                       | What changes                                                                                                                                                                       |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/design_tokens.dart`                         | Update the live song-card metric widths so the tuning slot is explicitly budgeted at 128px and BPM/Duration are reduced to their realistic minimum safe widths.                    |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Replace the tuning leftover-width treatment with a deterministic reserved tuning column sized from `SongCardLayout.trailingColWidth`, while keeping BPM/Duration/Key left-aligned. |

### Files Explicitly Off-Limits for Round 3

| File                                                  | Reason                                                     |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| `lib/features/setlists/widgets/song_card.dart`        | Dead for this flow and already out of scope since Round 2. |
| `lib/features/setlists/widgets/song_metrics_row.dart` | Not on the live rendering path.                            |
| `lib/features/setlists/setlist_detail_screen.dart`    | Caller wiring is already correct.                          |
| `lib/features/setlists/new_setlist_screen.dart`       | Caller wiring is already correct.                          |
| `lib/main.dart`                                       | Initialization order guardrail; unrelated.                 |
| `supabase/migrations/*`                               | No backend or persistence change is required.              |

### Regression Risk

Level: LOW

Rationale:

- The change remains a localized metrics-row layout adjustment.
- No state, repository, backend, routing, or auth code changes are involved.
- The only visible risk is over-tightening BPM/Duration too far, which is why Tony’s on-device check is still required.

### Engineer Task Breakdown

1. Update `SongCardLayout` widths in `lib/app/theme/design_tokens.dart` to the proposed budget:
   - `bpmColWidth = 56`
   - `durationColWidth = 54`
   - `trailingColWidth = 128`
2. Refactor `ReorderableSongCard._buildMetricsRow()` so tuning uses the reserved trailing width instead of a pure `Expanded` leftover slot.
3. Keep the BPM, Duration, and Key columns left-aligned and deterministic.
4. Keep the key column width unchanged and keep the existing single-line ellipsis behavior on badge text.
5. Confirm the live path only; do not touch dead widgets or unrelated screens.

### Verification Plan

1. Check a song with `Standard • C3` or `D Standard • C12` tuning on a real device.
2. Confirm the tuning badge no longer truncates mid-string.
3. Confirm BPM and Duration still fit on one line with no clipping.
4. Confirm key alignment and reserved key space remain unchanged.

## 17. Correction - Round 4 (Restore Flexible Tuning, Add Real BPM Margin)

### Why this correction is required

Round 3 over-corrected in two directions:

- `bpmColWidth = 56` is too tight for the live typography. Tony's latest screenshot shows visible clipping (`160 BP…`), which means the column now has effectively no cross-platform rendering margin.
- Replacing tuning's `Expanded(child: Align(alignment: Alignment.centerRight, ...))` with a fixed `SizedBox(width: SongCardLayout.trailingColWidth)` regressed the original right-edge anchoring behavior. On wider cards, the tuning badge now stops at the edge of the fixed slot instead of continuing to the card's right edge, leaving empty space to its right and reducing room for longer tuning labels/capo suffixes on its left.

### Corrected Root Cause

Confidence: HIGH

The remaining defects are both in the Round 3 layout strategy used by `lib/features/setlists/widgets/reorderable_song_card.dart` and the width tokens it consumes from `lib/app/theme/design_tokens.dart`:

- **BPM clipping:** the Round 3 width budget was set to the approximate raw text width of the longest common BPM string instead of the rendered text width plus safety margin. `formatBpm()` can emit values like `999 BPM`, and even `160 BPM` is clipping at 56px in the live font/style.
- **Tuning regression:** tuning was moved from a flexible trailing region to a hard fixed-width slot. That change solved one narrow-device truncation case by taking width away from siblings, but it removed the behavior Tony actually wants: tuning should keep growing toward, and anchoring to, the card's right edge whenever the card is wider.

### Corrected Layout Direction

Use fixed deterministic columns only for the metrics that need stable starts:

1. BPM: fixed width, left-aligned.
2. Duration: fixed width, left-aligned.
3. Key: fixed width, left-aligned, always reserved.
4. Tuning: revert to `Expanded(child: Align(alignment: Alignment.centerRight, child: _buildTuningBadge()))`.

This keeps BPM/Duration/Key aligned across rows while restoring Tuning's flexible trailing behavior. The existing `maxLines: 1` and `TextOverflow.ellipsis` on the tuning badge text remain the fallback for genuinely narrow layouts or unusually long custom tuning labels.

### Corrected Width Values

Update only the fixed columns that still need explicit budgets:

- `SongCardLayout.bpmColWidth`: `56 -> 68`
- `SongCardLayout.durationColWidth`: `54 -> 60`
- `SongCardLayout.keyColWidth`: keep `64`

Reasoning:

- `formatBpm()` has no upper bound, so the width target should protect at least `999 BPM`, not just `160 BPM`.
- At `AppFontSizes.subhead` (`14px`) and `FontWeight.w600`, `999 BPM` needs materially more than 56px once real glyph widths and platform text-rendering variance are accounted for. `68px` adds a usable guard band instead of relying on ellipsis as the normal path.
- `formattedDuration` also has no hard minutes cap. A realistic safe budget should cover at least a three-digit-minute string such as `999:59` with margin. `60px` is still compact, but meaningfully safer than 54px.
- These values remain much smaller than the original Round 2-era `90/80`, so reverting Tuning to `Expanded` still leaves substantially more flexible width for tuning than the pre-Round-3 layout.

The BPM/Duration ellipsis behavior added in Round 3 should remain in place as defense-in-depth, but it is no longer the primary sizing strategy.

### Decision on `trailingColWidth`

Do **not** remove `SongCardLayout.trailingColWidth` in Round 4.

Decision: leave it in `design_tokens.dart` unchanged as a legacy token for now, even though the live `ReorderableSongCard` path will no longer consume it after Tuning returns to `Expanded`.

Why:

- `lib/features/setlists/widgets/song_metrics_row.dart` still references `trailingColWidth`.
- That widget is already out of scope and not on the live rendering path for this bug.
- Removing or repurposing the token now would force a third file into the implementation surface for no user-visible benefit.

Document it as temporarily unused in the live path rather than expanding this correction into dead-code cleanup.

### Files to Modify for Round 4

| File                                                       | What changes                                                                                                                                         |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Restore Tuning to `Expanded` + right-aligned layout, keep BPM/Duration/Key deterministic, and preserve the existing single-line ellipsis safeguards. |
| `lib/app/theme/design_tokens.dart`                         | Increase `bpmColWidth` and `durationColWidth` to the corrected values; leave `keyColWidth` and `trailingColWidth` unchanged.                         |

### Files Explicitly Off-Limits for Round 4

| File                                                  | Reason                                                                                 |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_card.dart`        | Dead for this flow; still not part of the user-visible fix.                            |
| `lib/features/setlists/widgets/song_metrics_row.dart` | Out-of-scope dead/unused path; do not widen Round 4 just to delete `trailingColWidth`. |
| `lib/features/setlists/setlist_detail_screen.dart`    | Caller wiring is already correct.                                                      |
| `lib/features/setlists/new_setlist_screen.dart`       | Caller wiring is already correct.                                                      |
| `lib/main.dart`                                       | Initialization order guardrail; unrelated.                                             |
| `supabase/migrations/*`                               | No backend or persistence change is required.                                          |

### Regression Risk

Level: LOW

Rationale:

- The change remains a localized row-layout correction in the live widget plus two token adjustments.
- No business logic, persistence, routing, provider, or backend paths are touched.
- Reverting Tuning to `Expanded` restores the original wide-screen behavior instead of introducing a new layout model.

Primary visual risks to verify:

- BPM and Duration must stop clipping on Tony's device.
- Tuning must again reach the card's right edge on wider screens while still ellipsizing cleanly on narrow layouts.

### Engineer Task Breakdown

1. In `lib/app/theme/design_tokens.dart`, update only the live fixed-column budgets:
   - `bpmColWidth = 68`
   - `durationColWidth = 60`
   - leave `keyColWidth = 64`
   - leave `trailingColWidth` unchanged
2. In `lib/features/setlists/widgets/reorderable_song_card.dart`, change the tuning slot back to:
   - `Expanded(child: Align(alignment: Alignment.centerRight, child: _buildTuningBadge()))`
3. Keep BPM, Duration, and Key in fixed left-aligned columns with the reserved Key placeholder behavior intact.
4. Keep the current `maxLines: 1` and `TextOverflow.ellipsis` behavior on BPM, Duration, Key, and Tuning text.
5. Do not touch dead widgets, screen wiring, controller logic, or any non-layout behavior.

### Verification Plan

1. Tony performs the final on-device/on-screen check; that visual confirmation cannot be delegated to static code review.
2. On Tony's screenshot/device class, confirm `160 BPM` and other common BPM values render without clipping.
3. Confirm longer values such as `999 BPM` and long durations still have visible safety margin before ellipsis is ever needed.
4. Confirm the Tuning badge again reaches the card's right edge on wide screens.
5. Confirm longer preset labels with capo suffixes still get the maximum remaining space and only ellipsize when the row is genuinely too narrow.

### Final Confirmation

Tony’s on-device check is still required.

This cannot be fully verified in the editor alone because the failure is dependent on the actual rendered device width and font metrics.
