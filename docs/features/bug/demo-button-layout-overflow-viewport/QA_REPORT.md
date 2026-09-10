# QA_REPORT — bug/demo-button-layout-overflow-viewport

## Feature Slug

`bug/demo-button-layout-overflow-viewport`

## Feature Title

`_buildContentCluster`'s half-height `SizedBox` intermittently overflows by 173px in tests when the demo button is visible

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

Branch `bug/demo-button-layout-overflow-viewport` is at the same commit as `main` (`d81256d`); the entire change is the uncommitted working-tree diff reviewed below. The diff touches exactly the two files the plan authorized, implements the single `Flexible(child: ...)` wrap exactly as specified, and adds the required Test C exactly per the recipe. `flutter analyze` is clean on both files. The full test file passes in a single run, and both loop-stability checks required by the plan (Test C ×20, Test B ×20) passed 20/20 with zero failures — this satisfies the plan's explicit instruction not to close out on a single green run.

## Architect Scope Review

- Files modified: `lib/features/auth/login_screen.dart`, `test/features/auth/login_screen_demo_button_test.dart` — matches the plan's "Files to Modify" table exactly. No off-limits file was touched (verified `lib/main.dart`, `lib/app/**`, `pubspec.yaml`, `analysis_options.yaml`, `supabase/**`, `database/**`, auth-flow files, and the logo asset are all absent from the diff).
- `git log main..HEAD` is empty — HEAD equals `main`, confirming the reviewed working-tree diff is the complete change; no additional committed work exists to check.
- Untracked directories (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/`, `docs/features/feature/financials-transaction-cards*/`, `docs/features/transaction-drawer-redesign/`) are leftovers from unrelated prior sessions, not part of this branch's diff — excluded from `git diff`/`git status` "modified" set, not scope creep for this review.

## Completeness Check

All 5 Engineer Task Breakdown items completed:

1. ✅ `_buildLogo(logoWidth: logoWidth)` wrapped in `Flexible(child: ...)` inside the inner `Column`; `mainAxisAlignment`, demo-button block, and trailing spacer untouched (confirmed by direct read of lines 476–525).
2. ✅ Docstring "Layout contract" bullet updated to describe the shared top-half budget and `BoxFit.contain` shrink behavior; kept to a tight 3-line rewrite.
3. ✅ Test C appended verbatim per recipe: `physicalSize`/`devicePixelRatio` set with matching `addTearDown` resets, same `ProviderScope > MaterialApp > FTheme > LoginScreen` tree as Tests A/B, `precacheImage` inside `tester.runAsync`, `pumpAndSettle()`, `expect(tester.takeException(), isNull)`. No layout-geometry assertions added, as instructed. Tests A and B bodies unmodified (confirmed by direct read).
4. ✅ `flutter analyze` on both files — "No issues found!" (re-run independently, see Analyzer Results).
5. ✅ 20-iteration loops for both Test C and Test B re-run independently by QA — 20/20 pass each (see Test Results). Not merely re-trusting the Engineer's report.

No partial implementation, no missing edge case relative to plan scope.

## Behavior Verification

Root cause per the plan: `Image.asset` with only `width` set has an unconstrained intrinsic height once the codec resolves, and the inner `Column` (default `MainAxisSize.max`, no flexible children) cannot shrink it — hence the deterministic 173px overflow at compact viewports whenever the demo button is present. The fix wraps the logo in `Flexible(fit: FlexFit.loose)` (default fit for `Flexible`), which lets `RenderImage`'s `BoxFit.contain` scale the logo down under a constrained `maxHeight` rather than reporting an unbounded intrinsic size. This addresses the root cause (unconstrained sizing), not merely the test symptom — confirmed by the Test B loop (the pre-existing, non-precached test) passing 20/20, meaning the real overflow no longer fires even in the racy/uncached path.

This was verified via **code-path analysis + independently re-run automated test loops** (single-run + two 20-iteration loops), not manual/runtime UI verification. Per plan and mode rules, the macOS/iOS/Chrome resize checks are Tony's punch list (below), not something QA attempted or can attest to at runtime.

## Regression Check

Overall risk: **LOW** (confirmed, matches plan's own assessment).

- Auth/session (`_checkExistingSession`, magic-link handlers, cooldown timer): untouched — confirmed by diff (no lines outside `_buildContentCluster`'s docstring/Column touched).
- Animation (`FadeTransition`, `ScaleTransition`, `Transform.scale`, `_logoShrinkController`): untouched — `Flexible` wraps outside these paint-time transforms per the plan; no animation code appears in the diff.
- `_buildDemoButton` / `_kDemoBandVisible` gating: untouched, and Test A (unmodified) continues to assert the button's presence on non-web target.
- Platform parity: no platform-conditional code changed; `_kDemoBandVisible = !kIsWeb` gating itself is untouched, so web/native behavior split is preserved.
- Init order: not applicable — no file outside `login_screen.dart`/test file touched.
- No `Controller`/`FocusNode` disposal, no `setState` after async gaps, and no new rebuild triggers introduced — the change is a pure widget-tree wrap with no new state.

## Database Safety

n/a — no migration, RPC, or schema file in the diff.

## Analyzer Results

```
flutter analyze lib/features/auth/login_screen.dart test/features/auth/login_screen_demo_button_test.dart
Analyzing 2 items...
No issues found! (ran in 2.8s)
```

Independently re-run by QA (not just trusting Engineer's report) — clean at every severity.

## Test Results

Independently re-run by QA, all against the current working tree:

- `flutter test test/features/auth/login_screen_demo_button_test.dart` → `+3: All tests passed!` (Test A, Test B, Test C).
- Loop stability, `--plain-name "Test C"`, 20 iterations → **20/20 PASS**, 0 failures.
- Loop stability, `--plain-name "Test B"` (the historically-failing, non-precached case), 20 iterations → **20/20 PASS**, 0 failures.

This satisfies the plan's Tier 1 items 2–4 and directly addresses the user's instruction not to accept a single green run: the loop checks were re-executed independently by QA, not taken on the Engineer's word.

## Diff Safety Review

- No secrets/API keys in the diff.
- Grep for `TODO|FIXME|debugPrint(|api[_-]?key|secret|password` across the diff → no matches.
- No leftover test scaffolding, no accidental deletions, no unrelated formatting churn — diff is limited to the exact hunks the plan specifies.

## Change Budget Review

| File | Budgeted net delta | Actual net delta | Assessment |
| --- | --- | --- | --- |
| `lib/features/auth/login_screen.dart` | +2 to +4 | 0 (4 added / 4 removed) | Under budget, not over — the `Flexible` wrap replaced the call in place and the docstring was a 3-for-3 line rewrite. No excess; not a bloat concern. |
| `test/features/auth/login_screen_demo_button_test.dart` | +40 to +60 | +36 (36 added / 0 removed) | Slightly under budget. The 0-deletion figure is expected here since this is a purely additive appended test case, not a bug-fix file — the "zero deletions on a bug fix" Warning does not apply to this file. |

Both files are within/under budget (no >1.5x or >2x excess in either direction), no new file, no new public class, no new dependency. No Change Budget or Code Efficiency concerns.

## Code Efficiency Review

- No new helper, extension, util, or private widget class introduced. `Flexible` is a built-in Flutter widget — no duplicate-helper search was warranted.
- No single-use `_buildX()` method added; existing `_buildLogo`/`_buildDemoButton` are unchanged and reused as-is.
- No new provider/notifier, no new `FutureBuilder`/`StreamBuilder`, no hand-rolled collection loop, no new field/parameter/`copyWith` entry, no barrel file, no speculative "for future use" additions.
- The docstring edit is a legitimate accuracy fix (the prior wording was stale post-#271 per the plan), not restating adjacent code.
- No findings in this section.

## Manual Verification Punch List

The plan classifies the following as owner-run checks (Tier: "Owner-run at PR-test / apply time"), not QA gate requirements. QA did not attempt these, per this mode's rules — they require a running app instance. Hand to Tony:

1. Run `flutter run -d macos`. **Expected:** the macOS app launches directly to `LoginScreen`.
2. Resize the macOS window to approximately **800 × 600** client area. **Expected:** no red-and-yellow "BOTTOM OVERFLOWED BY 173 PIXELS" banner; logo visible and scaled to fit; "Check out the demo band" text button visible directly beneath the logo; email field, domain pills, and Email Login Link button all visible below without clipping.
3. Slowly resize the window from ~800×600 down to ~600×500 and back up to ~1200×900. **Expected:** no overflow banner appears at any point; logo scales smoothly; demo button remains visible at all sizes; no jitter or animation restart on resize.
4. Run `flutter run -d ios` (or an iOS simulator such as iPhone 15). **Expected:** `LoginScreen` renders exactly as before — logo at its usual size, demo button present, no overflow banner, entrance animation plays through once (confirms the mobile-portrait path is a visual no-op).
5. Run `flutter run -d chrome` at a browser window ~800×600. **Expected:** `LoginScreen` renders with logo, email field, pills, and login button; the demo button is **not** present (web target); no overflow banner.
6. Run `flutter run -d chrome` at a browser window ~1440×900 (typical laptop). **Expected:** layout is visually identical to what shipped on `main` — no visual regression at standard desktop sizes.

## Issues Found

None.

No Critical, Warning, or Suggestion items identified in this cycle.
