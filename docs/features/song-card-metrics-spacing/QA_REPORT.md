# QA Report

## Feature Slug

bug/song-card-metrics-spacing

## Feature Title

Song Card Metrics Spacing

## Final Verdict

**APPROVED**

## Validation Summary

I verified the branch is `bug/song-card-metrics-spacing`, reviewed the actual `git diff main` against the live code, and checked the implemented layout changes in `song_card.dart`, `reorderable_song_card.dart`, and `design_tokens.dart`. `flutter analyze` completed with 0 errors. I also confirmed `SongMetricsRow(` remains unreferenced outside its own file and noted the engineer-report/code discrepancy around the trailing-reservation section for audit trail purposes.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected
- Files off-limits: not touched

## Completeness Check

- All Architect tasks implemented: yes
- Missing tasks: none

## Behavior Verification

- Validation method: code-path analysis only
- Result: matches expected

## Regression Check

- Risk level: LOW
- Systems reviewed: song-card rendering, reorderable song-card rendering, shared song-card layout tokens, tuning label overflow behavior, BPM/Duration edit surfaces, key-slot alignment, dead-code usage of `song_metrics_row.dart`
- Regressions found: none

## Database Safety

Not applicable

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors

## Test Results

Not run

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none
- Unrelated changes: none

## Audit Notes

- The engineer report's "Trailing Minimum-Reservation Strategy" section is stale relative to the final code. Tony's later manual simplification removed the width-conditional `canReserveTrailingColumn` / fixed `128px` trailing-reservation branch from both live song-card widgets.
- The final implementation now renders tuning inside `Expanded` in both `song_card.dart` and `reorderable_song_card.dart`, right-aligned and growing leftward as needed. That matches the live code and does not change the approved layout-only scope.# QA Report

## Feature Slug

bug/song-card-metrics-spacing

## Feature Title

Song Card Metrics Spacing

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

I reviewed the Architect plan, Guardrails, Engineer report, current branch state, and the working-tree diff against `main`, then inspected the live implementations in `design_tokens.dart`, `song_card.dart`, and `reorderable_song_card.dart`. I also ran `flutter analyze` and performed code-path width-budget analysis for the metric row, plus ad hoc non-repo text-width probes to characterize the remaining tuning-risk severity. Runtime/device rendering was not exercised in this QA pass, so alignment and legibility conclusions are confirmed in code and layout math, not by manual device testing.

## Architect Scope Review

- Scope adherence: violated
- Files modified: as expected for implementation scope (`lib/app/theme/design_tokens.dart`, `lib/features/setlists/widgets/song_card.dart`, `lib/features/setlists/widgets/reorderable_song_card.dart`)
- Files off-limits: not touched in code; `lib/features/setlists/widgets/song_metrics_row.dart` remains untouched and unreferenced outside its own constructor definition

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks:

1. Architect task 4 is not satisfied at typical narrow mobile widths because the `trailingColWidth = 128` reservation path cannot activate once the always-reserved key slot and tightened tokens still consume `210px` before tuning. On representative phone row widths documented by the Engineer (`291px` at 375-wide screens, `306px` at 390-wide screens), both live widgets fall back to `Expanded`, leaving only `81px` to `96px` total for the tuning badge.
2. Architect verification requirement in sections 15 and 16 for built-in tuning labels, including capo-suffixed labels, to remain fully legible under typical narrow widths is not met with the current layout budget.

## Behavior Verification

- Validation method: code-path analysis
- Result: deviations noted below

Confirmed in code:

- The branch is `bug/song-card-metrics-spacing`.
- Both live card widgets now use a deterministic four-slot row: BPM, Duration, reserved Key slot, then Tuning.
- The key slot remains reserved when `musicalKey` is absent, so horizontal positions do not shift between songs with and without a key.
- `song_card.dart` now applies `maxLines: 1`, `overflow: TextOverflow.ellipsis`, and `softWrap: false` to both tuning text branches: the custom-tuning `FutureBuilder` path and the standard-tuning path.
- `reorderable_song_card.dart` also applies one-line ellipsis protection to its tuning text.
- The reorder-card tuning picker flow, BPM/Duration display paths, and non-layout control flow were not materially changed in the diff.

Deviation from expected behavior:

- On typical phone widths, the tuning reservation branch is unreachable, so both live widgets rely on the fallback `Expanded` tuning slot for all songs. After the shared leading columns consume `210px`, only `81px` to `96px` remains for the full tuning badge. With `12px` horizontal padding on each side of the badge, the effective text room is roughly `57px` to `72px`. That is not enough to confidently satisfy the Architect requirement that built-in tuning labels and capo-suffixed labels remain fully legible on typical narrow mobile widths.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Setlists / Catalog song-card rendering, shared song-card layout tokens, reorder-card tuning interaction surface, dead `song_metrics_row.dart` surface
- Regressions found:

1. The original tuning-legibility bug is only partially mitigated. Consistent alignment is improved, but the primary mobile-width tuning constraint remains for both live card surfaces.

Detailed regression notes:

- BPM values: code-path review supports the Engineer's `76px` BPM correction as the intended fix for the previously unsafe `68px` width. I did not reproduce this on device, but the column was explicitly widened and no new BPM overflow behavior was introduced in the diff.
- Duration values: the `60px` duration column is unchanged and the display path is unchanged.
- Key badge: slot reservation behavior is correctly implemented in both live widgets and should keep alignment stable between keyed and keyless songs.
- Tuning labels still at risk on phone widths because both cards share the same fallback slot:

1. High risk: `Standard • C3`, `Half-Step`, `Half-Step • C3`, `Full-Step`, `Full-Step • C3`, `Nashville`, `Nashville • C3`, `D Standard`, `D Standard • C3`, `B Standard`, `B Standard • C3`
2. Medium risk: `Standard`, `Drop D • C3`, `Open G • C3`, `DADGAD • C3`, and other capo-suffixed built-in labels
3. Lower but still non-zero risk: shortest built-ins like `Drop D`, `Open G`, `DADGAD` may remain visually tight depending on actual device width and font metrics

- Custom tuning names: confirmed to ellipsize gracefully instead of wrapping or clipping in `song_card.dart` and `reorderable_song_card.dart`.
- Surface consistency: both live widgets now share the same layout strategy and therefore the same residual tuning-width risk.
- Non-layout functionality: no code evidence of regressions to BPM/Duration edit interactions or tuning picker behavior, but this was not runtime-tested.

## Database Safety

Not applicable

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors

## Test Results

Not run

Note: I ran ad hoc temporary Flutter text-measurement probes outside the repo to characterize label-length severity, but those were not repository tests and do not replace runtime/device validation.

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: none found in the reviewed implementation files; current working tree also includes the feature-doc directory for Architect/Engineer/QA reports

## Issues Found

### Critical (must fix before commit)

1. The mobile-width tuning legibility requirement is still not met in both live card widgets. Because `leadingColsWidth` is `210px`, `SongCardLayout.trailingColWidth` never applies at realistic phone row widths (`291px` to `306px`), so tuning falls back to an `Expanded` slot that is too narrow to reliably keep built-in tuning labels and capo-suffixed labels fully legible. This fails the Architect's explicit requirement in sections 6, 15, and 16.

### Warnings (should fix)

1. Runtime/device validation for the Architect's post-implementation layout checks was not present in the Engineer report and was not completed in this QA pass, so the current severity judgment is based on code-path analysis and width budget rather than visual confirmation.

### Suggestions (optional)

1. Rework the phone-width layout budget so the tuning badge gets a guaranteed readable minimum on narrow cards, or reduce badge chrome/padding enough that the fallback path still preserves common built-in labels with capo suffixes.
