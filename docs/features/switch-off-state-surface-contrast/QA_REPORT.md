# QA REPORT — Switch OFF-state Surface Contrast

## Feature Slug
`switch-off-state-surface-contrast`

## Feature Title
OFF-state toggle switch track blends into the surrounding surface — nearly invisible when off

## Cycle Number
1

## Final Verdict
**APPROVED**

---

## Validation Summary

All plan requirements satisfied. Analyzer clean (0 issues). All 10 tests pass, including the new `buildEventEditorTheme` case. All Tier 1 grep gates pass. Contrast math independently verified. Scope exactly matches plan. No debug artifacts. No off-limits files touched. APPROVED.

---

## Architect Scope Review

**Slug match:** `switch-off-state-surface-contrast` — matches branch `bug/switch-off-state-surface-contrast`, `ARCHITECT_PLAN.md`, and `ENGINEER_REPORT.md`. ✅

**Modified files (from `git diff --name-only HEAD`):**
| File | Expected? |
|------|-----------|
| `lib/app/theme/design_tokens.dart` | ✅ Plan File 1 |
| `lib/app/theme/event_editor_theme.dart` | ✅ Plan File 2 |
| `test/components/ui/app_switch_test.dart` | ✅ Plan File 3 |

**Off-limits files — confirmed untouched (code-path analysis + git diff):**
- `lib/app/theme/app_theme.dart` ✅
- `lib/components/ui/app_switch.dart` ✅
- `lib/app/theme/brand_colors.dart` ✅
- All 12 feature switch files ✅
- `lib/main.dart` ✅
- `supabase/**` ✅
- `pubspec.yaml` / `pubspec.lock` ✅

No scope creep. No unrelated formatting churn.

---

## Completeness Check

| Architect Task | Status |
|----------------|--------|
| 1 — `AppColors.switchTrackOff`: `0xFF52525B` → `0xFF71717A`; inline comment `zinc-600` → `zinc-500`; doc comment updated with WCAG note | ✅ Confirmed in diff |
| 2 — `buildEventEditorTheme()`: `import 'design_tokens.dart';` added; `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))` chained, mirroring app-level override exactly | ✅ Confirmed in diff |
| 3 — One new `testWidgets` case in `app_switch_test.dart`: pumps `AppSwitch` under `FTheme(data: buildEventEditorTheme())`, asserts `switchStyle.trackColor.resolve(<FVariant>{}) == AppColors.switchTrackOff` | ✅ Confirmed in diff; case at index +8 in test output |
| 4 — `flutter analyze` + `flutter test` run by Engineer | ✅ Confirmed re-run independently (see Analyzer/Test Results) |

All tasks complete, no partial implementations or missing edge cases.

---

## Behavior Verification

*Method: code-path analysis of diff + static grep; UI not exercised at runtime.*

**Change 1 (`design_tokens.dart`):**
- `AppColors.switchTrackOff` is the sole token the app-level `FSwitchStyleDelta` references for the OFF-track base color (via `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` in `app_theme.dart` — file off-limits, confirmed unchanged).
- Changing the const value from `Color(0xFF52525B)` to `Color(0xFF71717A)` automatically propagates to all switches under the app-level FTheme without any call-site change. Confirmed by code-path analysis.
- `AppColors.primarySoft` (ON-state token, `Color(0xFFFB7185)`) is **unchanged** — ON-state elsewhere is unaffected. ✅
- `borderStrong` and `textDisabled` (both `0xFF52525B` in `brand_colors.dart`) are separate named tokens in a separate file; not touched. ✅

**Change 2 (`event_editor_theme.dart`):**
- `buildEventEditorTheme()` previously returned `FThemeData(colors: colors, touch: true)` with no `switchStyle` field; Forui resolves to its own `colors.secondary` (`#141417`) for the OFF track — contrast ~1.16:1 against `kEdSurface` (`#0C0C0E`), essentially invisible.
- The added `.copyWith(switchStyle: ...)` uses the exact same delta shape as the app-level override: `base(AppColors.switchTrackOff)` for unselected, `match({FSwitchVariant.selected}, AppColors.primarySoft)` for selected, `all(Colors.white)` for thumb.
- **Disabled variants** are not explicitly overridden (no `FSwitchVariant.disabled` delta) — consistent with the app-level pattern. ✅
- **Intentional ON-state shift in the drawer:** The drawer's ON track previously resolved to the `FThemeData.colors.primary` value (`#fb2c5a`) because there was no `switchStyle` override. It now resolves to `AppColors.primarySoft` (`#FB7185`). This shift is explicitly called out in the plan and `ENGINEER_REPORT.md` as intentional — it unifies drawer behavior with the rest of the app per PR #239's stated intent. Not a regression. ✅

**New test case (correctness):**
- The test pumps `AppSwitch(value: false)` under `FTheme(data: buildEventEditorTheme())` and resolves `FTheme.of(element).switchStyle.trackColor.resolve(<FVariant>{})`. An empty variant set resolves to the base (unselected) color, which must equal `AppColors.switchTrackOff`. The assertion is symbolic (not a hardcoded hex), so it will catch any future drift of either value. ✅
- The existing two symbolic assertions (OFF and ON under `AppTheme.foruiTheme`) survive the value change without edit — they test the token name, not the hex. ✅

---

## Regression Check

| System | Risk | Assessment (code-path analysis) |
|--------|------|---------------------------------|
| Settings (`_LightModeToggle`) | LOW | OFF track now `#71717A` — 4.11:1 vs `#09090B`. Visually more visible. No logic change. |
| Notifications settings | LOW | OFF track `#71717A` — 3.66:1 vs `#18181B`. Passes WCAG. No logic change. |
| Print Options bottom sheet | LOW | Same — 4 toggles, `#18181B` surface. ✅ |
| Gig Pay bottom sheet | LOW | Same — 1 toggle. ✅ |
| Add Financial Entry bottom sheet | LOW | Same — 3 toggles. ✅ |
| One Calendar Settings | LOW | Same — 2 toggles. ✅ |
| Members → Role Management | LOW | OFF track vs `#09090B`. ✅ |
| Contacts → Band Member Edit Drawer | LOW | OFF track vs `#18181B`. ✅ |
| Events → Editor drawer | LOW | Drawer now gets `switchStyle` for the first time. OFF: `#71717A` vs `#0C0C0E` = 4.04:1. ON: shifts to `#FB7185` (intentional unification). No call-site change in `event_editor_drawer.dart`. |
| Auth / session | NONE | No touch. |
| Riverpod state / band isolation | NONE | No touch. |
| Supabase RPCs / migrations | NONE | No touch. |
| Platform parity (iOS/Android/macOS/Web) | NONE | Pure Flutter theme constant — behavior identical across all platforms. |
| init order (`main.dart`) | NONE | No touch. |
| Controller/FocusNode disposal | NONE | No new controllers or FocusNodes. |

No regressions identified.

---

## Database Safety

**n/a** — No migrations, RLS policies, RPCs, triggers, or edge functions. Pure client-side Flutter change.

---

## Analyzer Results

Command: `flutter analyze lib/app/theme/design_tokens.dart lib/app/theme/event_editor_theme.dart test/components/ui/app_switch_test.dart`

```
Analyzing 3 items...
No issues found! (ran in 0.8s)
```

**Result: 0 errors, 0 warnings, 0 info in any of the 3 touched files.** ✅

(Pre-existing `undefined_lint` in `analysis_options.yaml` is untouched and unrelated; not in the diff.)

---

## Test Results

Command: `flutter test test/components/ui/app_switch_test.dart --reporter=expanded`

```
+0: AppSwitch renders without errors
+1: AppSwitch reflects value state
+2: AppSwitch calls onChanged callback
+3: AppSwitch activeColor applies StyleDelta
+4: AppSwitch activeTrackColor applies StyleDelta
+5: AppSwitch disables when onChanged is null
+6: AppSwitch renders under AppTheme.foruiTheme with distinct on-state track and thumb colors
+7: AppSwitch off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme
+8: AppSwitch off-state track resolves to AppColors.switchTrackOff under buildEventEditorTheme  ← NEW
+9: AppSwitch renders label and toggles when label is tapped when leadingLabel is true
+10: All tests passed!
```

**Result: 10/10 pass** (9 pre-existing + 1 new). ✅

---

## Diff Safety Review

- **Secrets / API keys:** None. ✅
- **`debugPrint`:** Absent from diff (grep confirmed). ✅
- **`TODO` / `FIXME`:** Absent from diff (grep confirmed). ✅
- **Leftover test scaffolding:** None. ✅
- **Accidental deletions:** None — only 3 lines deleted total (old hex + old comment in `design_tokens.dart`; old `return` statement in `event_editor_theme.dart`). All intentional. ✅
- **Unrelated churn:** None. ✅
- **Zero-deleted-lines on the bug fix:** The fix correctly deletes 3 lines (1 hex line + 1 comment line in `design_tokens.dart`; 1 plain return line in `event_editor_theme.dart`). Not zero deletions. ✅

---

## Change Budget Review

**`git diff --numstat HEAD`:**
```
2       2       lib/app/theme/design_tokens.dart
15      1       lib/app/theme/event_editor_theme.dart
24      0       test/components/ui/app_switch_test.dart
```

| File | Plan budget | Actual added | Actual deleted | Net |
|------|-------------|-------------|----------------|-----|
| `design_tokens.dart` | ~0 net | 2 | 2 | 0 |
| `event_editor_theme.dart` | +12–14 lines | 15 | 1 | +14 |
| `app_switch_test.dart` | +15–22 lines | 24 | 0 | +24 |
| **Total** | **~+30 net** | **41** | **3** | **+38** |

- `design_tokens.dart`: On budget. ✅
- `event_editor_theme.dart`: 15 added vs +14 upper bound — 1 line is the new `import` line, which the plan explicitly anticipated ("Add the `import 'design_tokens.dart';` line if not already present"). Effectively on budget. ✅
- `app_switch_test.dart`: +24 vs +22 upper bound = 1.09× over bound. Within the 1.5× threshold → noted, not a finding. 1 extra line is the new `import 'event_editor_theme.dart';` line. The test body itself is ~23 lines including blank line separator — consistent with the plan's description.
- **Total net ~+38 vs plan's ~+30 = 1.27× — within 1.5×.** ✅

No new files, no new public classes/methods/params, no new dependencies. ✅

---

## Code Efficiency Review

- No new helpers, extensions, utils, or private widget classes. ✅
- No new providers, controllers, or models. ✅
- No `FutureBuilder`/`StreamBuilder` re-fetching. ✅
- No single-use `_buildX()` methods or wrapper abstractions. ✅
- No config/flags/enum cases added "for future use." ✅
- No comments restating the line below. The updated doc comment on `switchTrackOff` adds meaningful WCAG context not inferrable from the value alone. ✅
- Grep for pre-existing equivalent of the new test helper: none found — the test correctly inlines `FTheme.of(element).switchStyle` exactly as the existing OFF-state test does. No abstraction warranted for two uses. ✅

---

## Issues Found

**No Critical issues.**
**No Warnings.**
**No Suggestions.**

The only notable item — one `0xFF71717A` hit in `lib/features/events/widgets/event_editor_drawer.dart:3164` (a hardcoded text-style color, `kEdMutedForegroundFaint`) — is pre-existing, was documented by the Engineer, is on the plan's off-limits list, and was not introduced or modified by this diff. Not a finding.

---

## Contrast Sanity-Check

Independent WCAG 2.1 SC 1.4.11 luminance calculation for `#71717A` (Zinc 500, `AppColors.switchTrackOff`):

| Surface | Plan ratio | Independently calculated | Passes 3:1? |
|---------|-----------|--------------------------|-------------|
| `#09090B` (background) | ~4.08:1 | **~4.11:1** | ✅ |
| `#0C0C0E` (kEdSurface) | ~3.98:1 | **~4.04:1** | ✅ |
| `#18181B` (surface) | ~3.59:1 | **~3.66:1** | ✅ |

*Method: direct sRGB → linear luminance calculation per WCAG 2.1 formula (IEC 61966-2-1). Minor variance vs plan values explained by rounding in intermediate steps. All three surfaces clear 3:1 with margin.*

The darkest surface (`#18181B`) has the smallest ratio (~3.66:1), still 22% above the 3:1 threshold.

---

## Final Verdict

**APPROVED**

The implementation exactly matches the Architect plan across all three tasks, touches zero off-limits files, introduces no regressions, passes analyzer (0 issues) and all 10 tests, clears all Tier 1 grep gates, and the contrast claims are independently verified by luminance math. No database artifacts. No debug residue. Change budget within 1.5× on all files.
