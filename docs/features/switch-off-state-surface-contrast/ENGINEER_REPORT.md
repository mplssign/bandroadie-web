# ENGINEER_REPORT — Switch OFF-state Surface Contrast

## Feature Slug
`switch-off-state-surface-contrast`

## Feature Title
OFF-state toggle switch track blends into the surrounding surface — nearly invisible when off

## Cycle Number
1

## Goal
Raise `AppColors.switchTrackOff` from Tailwind Zinc 600 (`#52525B`) to Zinc 500 (`#71717A`) so every switch OFF-state track clears WCAG 2.1 SC 1.4.11 (3:1) against every dark surface in the app. Simultaneously close the event editor drawer gap where `buildEventEditorTheme()` had no `switchStyle` override, leaving those switches on a near-invisible Forui default.

## Architect Tasks Completed

| Task | Status |
|------|--------|
| 1 — Update `AppColors.switchTrackOff` hex + comments in `design_tokens.dart` | ✅ Done |
| 2 — Add `switchStyle` `.copyWith(...)` to `buildEventEditorTheme()` + add `design_tokens.dart` import | ✅ Done |
| 3 — Add one new `testWidgets` case in `app_switch_test.dart` asserting OFF-state resolves to `AppColors.switchTrackOff` under `buildEventEditorTheme` | ✅ Done |
| 4 — Local verification (`flutter analyze`, `flutter test`) | ✅ Done |

## Files Created
None.

## Files Modified

| File | Change summary |
|------|----------------|
| `lib/app/theme/design_tokens.dart` | Hex `Color(0xFF52525B)` → `Color(0xFF71717A)`; inline comment `zinc-600` → `zinc-500`; doc comment updated to WCAG note |
| `lib/app/theme/event_editor_theme.dart` | Added `import 'design_tokens.dart';`; changed terminal `return FThemeData(...)` to chain `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))` mirroring app-level override exactly |
| `test/components/ui/app_switch_test.dart` | Added `import 'event_editor_theme.dart';`; inserted one new `testWidgets` case immediately after the existing `'off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme'` case |

## Analyzer Results
```
flutter analyze lib/app/theme/design_tokens.dart lib/app/theme/event_editor_theme.dart test/components/ui/app_switch_test.dart
Analyzing 3 items...
No issues found! (ran in 1.4s)
```
**Result: 0 errors, 0 warnings, 0 info.**

## Test Results
```
flutter test test/components/ui/app_switch_test.dart
00:02 +10: All tests passed!
```
**Result: 10/10 tests passed** (9 existing + 1 new).

## Code Efficiency / Bloat Check

- Searched `lib/` for an existing helper that resolves `FTheme.of(context).switchStyle` before testing — none found; inlined directly in the test as done by the existing OFF-state test case.
- No new helper, extension, util, or private widget class added.
- No new providers, controllers, or models.
- `dart format` run on all 3 changed files — 0 changes (already formatted).
- `dart fix --dry-run` reviewed; no suggestions apply inside the 3 changed files.
- No `debugPrint`, `TODO`, or `FIXME` left in the diff.
- No AI-shaped patterns: no unused imports, no dead code, no redundant wrapping, no single-use `_build*` methods.

## Tier 1 Grep Gate Results

| Gate | Command | Result |
|------|---------|--------|
| 1a — `switchTrackOff` contains new hex | `grep -n "switchTrackOff" lib/app/theme/design_tokens.dart` | Line 159: `Color(0xFF71717A)` — ✅ PASS |
| 1b — old hex absent from `design_tokens.dart` | `grep -n "0xFF52525B" lib/app/theme/design_tokens.dart` | (no output) — ✅ PASS |
| 2a — `switchStyle` present in `event_editor_theme.dart` | `grep -n "switchStyle" lib/app/theme/event_editor_theme.dart` | Line 41 — ✅ PASS |
| 2b — `AppColors` tokens referenced in `event_editor_theme.dart` | `grep -n "AppColors.switchTrackOff\|AppColors.primarySoft" lib/app/theme/event_editor_theme.dart` | Lines 43, 46 — ✅ PASS |
| 3 — no hardcoded switch hex in `lib/features` | `grep -rn "0xFF52525B\|0xFF71717A" lib/features` | One pre-existing match — see Deviations |

## Verification
- `flutter analyze` on all 3 changed files: No issues found.
- `flutter test test/components/ui/app_switch_test.dart`: 10/10 pass.
- Diff reviewed: exactly 3 files touched, net ~+30 lines, no unintended changes.

## Deviations From Plan

**Grep Gate 3 — one pre-existing `0xFF71717A` match in `lib/features`:**
`lib/features/events/widgets/event_editor_drawer.dart:3164` contains `TextStyle(fontSize: 14, color: Color(0xFF71717A))` — a hardcoded text-style color predating this cycle. The same hex is also `kEdMutedForegroundFaint` in `event_editor_theme.dart`. Neither usage relates to switch styling and neither was introduced or modified by this cycle. The plan's gate was written before knowing `kEdMutedForegroundFaint` already used this value. The `event_editor_drawer.dart` file is on the plan's Files Off-Limits list and was not touched. QA note: this is a pre-existing inline-vs-named-constant inconsistency in a file outside scope; it does not affect the switch contrast fix.

**Intentional drawer ON-state hue shift (called out by plan):**
`buildEventEditorTheme()` previously had no `switchStyle` override, so the drawer's ON-state track resolved to `primary` (`#fb2c5a`). After this change it resolves to `AppColors.primarySoft` (`#FB7185`) — a small shift toward the softer app-wide rose, matching the rest of the app per PR #239's stated intent. This is explicitly noted as intentional in the plan's Regression Risk section.

## Blockers Encountered
None.

## Ready For QA
Yes
