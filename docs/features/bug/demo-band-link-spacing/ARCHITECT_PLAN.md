# ARCHITECT_PLAN — bug/demo-band-link-spacing

## Feature Slug

`bug/demo-band-link-spacing`

## Feature Title

"Check out the demo band" link sits too close to the logo on the login screen; should be positioned lower, closer to the Email field

## Problem Summary

On the login screen (non-web only, per `_kDemoBandVisible = !kIsWeb`), the "Check out the demo band" text button visibly sits directly beneath the logo (~12px gap) while there is a large empty gap between it and the "Email address" label/field below. The intended visual grouping is the reverse: the demo link belongs with the login form (small gap to the email field), not with the branding cluster (large gap from the logo). This is a pure spacing/positioning defect in `_buildContentCluster` — no logic, no data, no auth-flow interaction.

## Root Cause

**Confidence: HIGH.** The layout math reproduces the observed spacing exactly.

`_buildContentCluster` in [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L487-L525) builds the top half of the screen as:

```dart
SizedBox(
  height: availableHeight / 2,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Flexible(child: _buildLogo(logoWidth: logoWidth)),
      if (_kDemoBandVisible) ...[
        const SizedBox(height: 12),
        _buildDemoButton(),
      ],
      const SizedBox(height: 12),
    ],
  ),
),
```

The inner `Column` uses `mainAxisAlignment: MainAxisAlignment.center`, so the four children `[Flexible(logo), 12, demoButton, 12]` are treated as a single stack and centered as a unit inside the fixed `availableHeight / 2` budget. On a typical mobile portrait target (e.g. iPhone 15, viewport ≈ 390 × 800 after `SafeArea`), the numbers work out as:

| Quantity                                         | Value                                                                                                           |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Upper-half budget                                | `800 / 2 = 400px`                                                                                               |
| `logoWidth`                                      | `(390 − 64) × 0.9 = 293.4px`                                                                                    |
| Logo intrinsic height (aspect 964:645)           | `293 × 645 / 964 ≈ 196px`                                                                                       |
| Inner Column content (logo + 12 + demo + 12)     | `196 + 12 + 30 + 12 = 250px`                                                                                    |
| Slack space (400 − 250)                          | `150px`, split by `MainAxisAlignment.center` → **75px above the logo**, **75px below the trailing 12px spacer** |
| Rendered gap between logo bottom and demo button | `12px`                                                                                                          |
| Rendered gap between demo button and email field | `12 (trailing spacer) + 75 (bottom slack) = 87px`                                                               |

That 12px-vs-87px asymmetry is exactly the reported symptom: the demo link visually sticks to the logo above and floats far from the email field below. The gap is not a bug in the spacer sizes (both are 12px); it is a bug in **where the slack space lands** because the inner Column centers the whole cluster instead of anchoring the demo button toward the email field.

Note that PR #278 (merged in `07ff1aa`) wrapped the logo in `Flexible(...)` so that at compact viewports where the logo + demo button + spacers would exceed the `availableHeight / 2` budget, `BoxFit.contain` shrinks the logo instead of a `RenderFlex` overflow firing. That fix addresses a _different_ failure mode (compact-viewport overflow) and is orthogonal to this bug (mobile-portrait visual grouping). The overflow-safety Flexible wrap can be preserved verbatim in the proposed fix.

## Existing System Analysis

- `_buildContentCluster` is the only widget-tree branch that positions the demo button. The button widget itself (`_buildDemoButton()` at [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L666-L691)) is a `FadeTransition(opacity: _buttonOpacity, child: TextButton(...))`. It has no intrinsic notion of "where it belongs" — its position is 100% determined by where it is placed in the parent tree. Moving it up or down in the tree does not affect its animation (paint-time only) or its tap handler.
- The outer `Column` in `_buildContentCluster` uses `mainAxisSize: MainAxisSize.min` and is wrapped in `SingleChildScrollView` + `ConstrainedBox(minHeight: available)`, so growing the outer Column by a few dozen pixels cannot produce a `RenderFlex` overflow — it produces (at worst) scroll.
- The Flexible-wrapped logo introduced by PR #278 satisfies the overflow constraint at compact viewports as long as the logo is a child of a bounded-height container. If the logo is left as the sole child of the existing `SizedBox(height: availableHeight / 2)`, PR #278's guarantee stays intact and is strictly stronger (no sibling widgets contend for the same budget).
- Test C in [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart#L85-L118) locks in "no `RenderFlex` overflow at 800×600 with the demo button visible." That invariant remains true after the proposed fix — see Verification Plan.
- Test A in [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart#L35-L58) asserts that `find.text('Check out the demo band')` finds exactly one widget on non-web targets. Preserved verbatim — the button is still emitted, only its position in the tree changes.
- Web behavior (`_kDemoBandVisible == false`) removes the entire demo block. Post-fix, the outer Column on web still contains: upper-half `SizedBox` (logo only) → `_buildEmailField()` → ... . No visible change on web.
- Keyboard-open logo shrink (`_logoShrinkController` / `_logoShrinkScale`) is a `Transform.scale` inside `_buildLogo` — paint-only, unaffected by tree position changes.

## Proposed Solution

Move the demo button (and one 12px spacer) out of the upper-half `SizedBox`'s inner `Column` and into the outer `Column`, placed immediately above `_buildEmailField()`. The upper-half `SizedBox`'s inner `Column` simplifies to a single-child `[Flexible(_buildLogo(...))]`.

Consequences:

- The upper-half `SizedBox` still occupies `availableHeight / 2`; the logo is centered within it. On mobile portrait, the ~150px of slack that previously split into "75px above logo / 87px below demo button" now falls entirely **below the logo** (~104px between logo bottom and the boundary of the upper-half box). The demo button, now sitting immediately below that boundary in the outer Column, is 12px above the email label. Net visual outcome:
  - Gap between logo bottom and demo button: **~104px** (was ~12px)
  - Gap between demo button and "Email address" label: **~12px** (was ~87px)
  - This is precisely what the Feature Input asks for.
- PR #278's Flexible wrap is preserved verbatim. The upper-half `SizedBox` now contains a single Flexible child; `BoxFit.contain` still scales the logo down under a constrained `maxHeight`, so the 800×600 no-overflow test (Test C) continues to hold — strictly more robustly than before, because there are no non-flexible siblings competing for the 300px budget.
- The outer `Column` grows by ≈ 42px (demo button ≈ 30px + one new 12px spacer) when the demo button is visible. This growth cannot overflow: the outer Column is inside `SingleChildScrollView`, which converts vertical overflow into scroll. There is no `RenderFlex` in the outer path.
- On web (`_kDemoBandVisible == false`), the `if (_kDemoBandVisible) ...[...]` block is a no-op in both the old and new location. Web layout is byte-identical to today.
- Animation timing is preserved: the demo button still uses `_buttonOpacity` from `_animController`; the interval (0.55–0.90) is unchanged. Moving the widget in the tree does not affect the animation controller or intervals.
- Keyboard-shrink behavior is preserved: `_logoShrinkScale` is a `Transform.scale` inside `_buildLogo`, not tied to tree position.

The doc comment on `_buildContentCluster` needs a small accuracy update to reflect the new contract: logo alone occupies the upper half; demo button (when visible) groups with the form.

Alternatives considered and rejected:

- **Change the inner Column's `mainAxisAlignment` to `MainAxisAlignment.spaceBetween` (or `end`) so the demo button pins to the bottom of the upper-half `SizedBox`.** Would achieve the same visual outcome for the demo button, but on non-web it also displaces the logo (moves it to the top of the upper half instead of the middle), which is a change the Feature Input did not request. And on web, `spaceBetween` with a single child (logo only) degrades to top-anchored, silently regressing web logo position. Would require a conditional alignment on `_kDemoBandVisible`, adding branching without benefit.
- **Increase the spacer between the logo and the demo button (e.g. `SizedBox(height: 60)`) and decrease the trailing spacer to `SizedBox(height: 0)`.** Does not help: the inner Column still has `mainAxisAlignment: center`, so any change in child sizes just shifts where the slack goes; the demo button still floats up with the logo.
- **Reduce `availableHeight / 2` to a smaller fraction (e.g. `* 0.4`)** to squeeze the upper half so the whole cluster falls closer to the email field. Alters the "form starts at the vertical midpoint" contract documented on `_buildContentCluster`; larger surface-area change with knock-on effect on mobile portrait _and_ iPad _and_ macOS at all viewport sizes. Not minimal.
- **Move the demo button _below_ the email field entirely (e.g. beneath the login button).** Changes the user-visible information hierarchy — demo band access would land below the primary CTA, which is a product/UX call the Feature Input didn't authorize. Also degrades demo discoverability. Rejected.

## Database Impact

n/a

## Flutter Architecture Changes

Layout-only change to a single widget method (`_buildContentCluster`) in `LoginScreen`. No new provider, controller, repository, service, model, or router entry. No init-order effect. No platform-conditional code path is added or removed (`_kDemoBandVisible = !kIsWeb` is respected as-is). No animation controller, cooldown timer, session-detection, or magic-link handler is touched.

## Files to Create

n/a

## Files to Modify

| File                                  | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart` | In `_buildContentCluster()`, inside the `SizedBox(height: availableHeight / 2) → Column(mainAxisAlignment: MainAxisAlignment.center)` at line ~497–510: (1) delete the `if (_kDemoBandVisible) ...[const SizedBox(height: 12), _buildDemoButton()],` block; (2) delete the trailing `const SizedBox(height: 12),` child. The inner Column ends as `children: [Flexible(child: _buildLogo(logoWidth: logoWidth))]`. Then in the outer Column, insert immediately before `_buildEmailField()`: `if (_kDemoBandVisible) ...[_buildDemoButton(), const SizedBox(height: 12)],`. Update the `Layout contract:` doc comment above `_buildContentCluster` (line ~479–486): the current "Logo + demo button (when `_kDemoBandVisible`) share the upper half..." bullet is now stale — replace it with two bullets describing that the logo alone occupies the upper half (shrinking via `BoxFit.contain` under pressure), and the demo button (when `_kDemoBandVisible`) sits directly above the email field so it groups with the login form. Update the section comment `// === LOGO + DEMO BUTTON — upper half, button equidistant between logo and email ===` (line ~495) to `// === LOGO — upper half, centered ===` and add a `// === DEMO BUTTON — grouped with the login form ===` marker above the moved block. No other lines change in this file. |

## Files Off-Limits

| File                                                                                                                                                                                                                                                                       | Reason                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/features/auth/login_screen_demo_button_test.dart`                                                                                                                                                                                                                    | Test A (button emitted on non-web) and Test C (no RenderFlex overflow at 800×600 with button visible) both continue to pass unchanged under the proposed fix — Test A finds the button by text regardless of tree position, and Test C's invariant is strengthened (single Flexible child in the upper half). No new test is justified: this is a visual-alignment adjustment, not a runtime invariant, and Tony validates the visual outcome at PR-test time via the owner-run punch list. Do not add, delete, or modify assertions in this file. |
| `lib/features/auth/login_screen.dart` outside `_buildContentCluster` (animations, cooldown timer, magic-link handlers, `_checkExistingSession`, `_buildLogo` internals, `_buildEmailField`, `_buildDomainPills`, `_buildLoginButton`, `_buildMessage`, `_buildDemoButton`) | Not implicated in the spacing defect. Do not reformat, retheme, restructure, or "improve" them.                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `lib/main.dart`, `lib/app/**`                                                                                                                                                                                                                                              | Init order, theme, URL strategy, and all app-wide infrastructure are out of scope.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `lib/features/auth/demo_session_service.dart`, `lib/features/auth/auth_gate.dart`, `lib/features/auth/auth_confirm_screen.dart`                                                                                                                                            | Not a data / auth-flow / session issue; only login-screen widget geometry.                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`                                                                                                                                                                                                                    | No new dependency or lint change is required or justified.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `supabase/**`, `database/**`                                                                                                                                                                                                                                               | No DB / RLS / RPC change.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `assets/images/**`                                                                                                                                                                                                                                                         | Not an asset defect.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Every other file in `lib/features/**`                                                                                                                                                                                                                                      | Cross-feature scope creep.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

## Change Budget

| File                                  | Expected net line delta                                                                                                                   |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart` | −1 to +2 lines net (five lines removed from inner Column, four lines added to outer Column, two–three doc/section-comment lines adjusted) |

- Expected new files: **0**
- Expected new public classes / methods: **0**
- Expected new dependencies: **0**
- Expected new tests: **0** (see rationale in Files Off-Limits)

## System Impact Map

| System                                                                                                                                                                                                             | Status                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth (magic link, PKCE, session, deep links)                                                                                                                                                                       | Unaffected — no logic change; only widget-tree position of one existing button.                                                                                                                                                                   |
| Gigs / Rehearsals / Setlists / Members / Financials                                                                                                                                                                | Unaffected.                                                                                                                                                                                                                                       |
| Routing / Deep links / `DeepLinkService`                                                                                                                                                                           | Unaffected.                                                                                                                                                                                                                                       |
| Notifications                                                                                                                                                                                                      | Unaffected.                                                                                                                                                                                                                                       |
| Init order (`WidgetsFlutterBinding` → URL strategy → orientation lock → `AppVersionService` → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp` [native] → `DeepLinkService` → `runApp`) | Unaffected.                                                                                                                                                                                                                                       |
| Platform parity                                                                                                                                                                                                    | iOS / Android / macOS: visible spacing change on the login screen (this is the fix). Web: unaffected — `_kDemoBandVisible == false` means the moved block is a no-op in either tree location; the outer Column on web is byte-identical to today. |
| Demo-band visibility gating (`_kDemoBandVisible = !kIsWeb`, per the temporary comment at [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L47-L52))                                       | Unaffected — the gating expression, its threshold, and the temporary account-cleanup note remain verbatim.                                                                                                                                        |
| PR #278's overflow safety (Flexible wrap on logo)                                                                                                                                                                  | Preserved; strengthened (single Flexible child in the upper-half budget instead of Flexible + spacers + demo button).                                                                                                                             |

## Regression Risk

**LOW.** The change is a widget-tree re-parent of one existing button (plus one 12px SizedBox), inside a scroll-view-hosted outer Column. It cannot alter auth behavior, session behavior, routing, animation timing, keyboard behavior, or overflow safety — the animation intervals are shared with the login button and untouched, the demo button's tap handler (`_enterDemo`) is untouched, and the paint-time transforms nested inside the logo are untouched. The one visible behavior change is the intended one: the demo link now sits closer to the email field and farther from the logo on iOS / Android / macOS. Web is byte-identical.

## Engineer Task Breakdown

1. Open `lib/features/auth/login_screen.dart`. Locate `_buildContentCluster()` (starting at ~line 487). Inside the outer `Column`'s first child — the `SizedBox(height: availableHeight / 2)` containing an inner `Column(mainAxisAlignment: MainAxisAlignment.center)` — modify the `children:` list to leave exactly one child: `Flexible(child: _buildLogo(logoWidth: logoWidth))`. Delete the `if (_kDemoBandVisible) ...[const SizedBox(height: 12), _buildDemoButton()]` block and the trailing `const SizedBox(height: 12)`.
2. In the same outer `Column`, immediately after the closing `),` of that `SizedBox` and immediately before `_buildEmailField()`, insert:
   ```dart
   if (_kDemoBandVisible) ...[
     _buildDemoButton(),
     const SizedBox(height: 12),
   ],
   ```
   Do not add a leading spacer before the demo button — the slack space below the centered logo inside the upper-half `SizedBox` provides the visible gap.
3. Update the section comment above the `SizedBox(height: availableHeight / 2)` from `// === LOGO + DEMO BUTTON — upper half, button equidistant between logo and email ===` to `// === LOGO — upper half, centered ===`. Add a new `// === DEMO BUTTON — grouped with the login form ===` marker immediately above the `if (_kDemoBandVisible) ...[...]` block you inserted in Task 2.
4. Update the `Layout contract:` doc comment above `_buildContentCluster` (currently: `///   - Logo + demo button (when [_kDemoBandVisible]) share the upper half of / [availableHeight], centered within it; the logo shrinks via / BoxFit.contain when the demo button consumes part of that budget.`) to reflect the new contract. Suggested wording, keep it tight:
   ```
   ///   - Logo occupies the upper half of [availableHeight], centered within
   ///     it, and shrinks via `BoxFit.contain` if its intrinsic height would
   ///     exceed the budget (PR #278 overflow safety).
   ///   - Demo button (when [_kDemoBandVisible]) sits directly above the
   ///     email field so it groups visually with the login form, not the
   ///     branding cluster above.
   ```
   Do not touch the other bullets in that doc comment (`Logo width is 90% of the email field width.`, `Form elements start at the midpoint of the available screen height.`).
5. Run `flutter analyze` on the modified file. Fix any warnings introduced by the diff (there should be none — the change is purely structural). Do not touch pre-existing warnings.
6. Run `flutter test test/features/auth/login_screen_demo_button_test.dart`. All three existing tests (A, B, C) must pass. If Test C fails, stop and report — the overflow safety is not working as expected under the refactor.

## Verification Plan

### Tier 1 — Pre-deploy, mechanically executable without a running app (QA gate)

1. **Diff scope check.** `git diff origin/main` touches exactly one file: `lib/features/auth/login_screen.dart`. Any other file in the diff → fail.
2. **Line-delta check.** Net delta for `lib/features/auth/login_screen.dart` is between −1 and +2 lines. Outside that band → warn (a deviation of >3 lines suggests the Engineer restructured beyond the plan).
3. **Analyzer.** `flutter analyze` completes with no new warnings or errors on the modified file, compared to a baseline analyzer run on the branch parent (`07ff1aab`).
4. **Test suite for this file.** `flutter test test/features/auth/login_screen_demo_button_test.dart` — Tests A, B, and C all pass. Test C is the key regression signal: it is PR #278's overflow-safety test at 800×600 with the demo button visible, and this refactor preserves (in fact simplifies) the mechanism that makes it pass. Any failure here means either (a) the Engineer accidentally broke the Flexible wrap on the logo, or (b) removed the `SizedBox(height: availableHeight / 2)` bound. Both are red flags.
5. **Loop stability check for Test C.** `for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" || echo "FAILED run $i"; done` — 20/20 must pass. This directly validates that the overflow-safety invariant from PR #278 remains deterministic under the new tree structure.
6. **Structural spot-check on the diff (static read).** In the modified `_buildContentCluster`, the inner Column inside `SizedBox(height: availableHeight / 2)` has exactly one child: `Flexible(child: _buildLogo(logoWidth: logoWidth))`. The outer Column contains `if (_kDemoBandVisible) ...[_buildDemoButton(), const SizedBox(height: 12)]` between the upper-half `SizedBox` and `_buildEmailField()`. No other layout blocks (email, pills, login button, message, trailing spacer) are moved or resized.

Tier 1 checks never call, replace, or exercise the function being edited via a running app; they operate entirely on static analysis and the headless `flutter_test` harness.

### Tier 2 — Post-deploy

n/a. No database change, no RPC change, no edge function change, no schema/migration to verify against production.

### Owner-run at PR-test / apply time (Tony's punch list — QA hands this to Tony verbatim; QA does not attempt these)

QA cannot launch the app in this pipeline. Tony runs the following at PR-test time to visually confirm the fix; the results are recorded on the PR before merge, not gated by QA.

1. `flutter run -d macos` — the macOS app launches to `LoginScreen` (sign out first if you land on the app shell).
2. Observe the login screen at the default window size (~1200 × 900). **Expected:** the "Check out the demo band" text button sits with a visibly larger gap between it and the logo above (roughly half the height of the logo), and a small gap (~12px, one line of text) between it and the "Email address" label below. Compare against the pre-fix behavior on `main` if available — the demo link should have clearly moved down toward the email field.
3. `flutter run -d ios` (or launch an iOS simulator such as iPhone 15). **Expected:** same visual grouping as macOS — demo link separated from logo, adjacent to email field. Entrance animation still plays through once at start.
4. `flutter run -d chrome` at any window size. **Expected:** the "Check out the demo band" link is **not** visible (web target, `_kDemoBandVisible == false`). Logo, email, pills, and login button lay out exactly as they did before this PR — this is the byte-identical web check.
5. On macOS, tap into the email field to raise the keyboard / focus indicator. **Expected:** the logo shrinks to 75% smoothly (existing behavior); the demo link stays put relative to the email field (does not detach from the form group). Blur the email field. **Expected:** logo returns to full size smoothly.
6. Resize the macOS window to a compact size (~800 × 600 client area). **Expected:** no red-and-yellow "BOTTOM OVERFLOWED BY N PIXELS" banner appears at any point during the resize. Logo scales down to fit; demo link and email field remain visible and appropriately spaced. This is the PR #278 overflow-safety visual check.
7. Optional but recommended: `flutter run -d android` on a physical device or emulator (Pixel 6 or similar). **Expected:** demo link position matches the iOS/macOS observation from step 2.

## QA Regression Areas

- LoginScreen visual layout across viewport sizes: mobile portrait, macOS default window, macOS compact window (~800×600), web wide, web compact. QA validates Tier 1 + hands Tony the punch list; QA does not launch the app.
- Demo button rendering and tap wiring — `_buildDemoButton` and `_enterDemo` are not touched; existing Test A guarantees the button is emitted on non-web targets.
- Login entrance animation — no animation code is touched; all `FadeTransition` / `ScaleTransition` / `SlideTransition` / interval calculations remain. The demo button still animates on the shared `_buttonOpacity` curve; its tree-position change is invisible to the animation controller.
- Keyboard-open behavior — `_logoShrinkController` / `_logoShrinkScale` / `keyboardHeight` handling are unchanged.
- Overflow safety at 800×600 with demo visible — PR #278's Test C invariant is preserved (in fact strengthened: single Flexible child in the upper-half budget).
- Web layout parity — `_kDemoBandVisible == false` means the outer Column on web is byte-identical to today.
- `_checkExistingSession` / `_sessionDetected` short-circuit, cooldown timer, magic-link `signInWithOtp` handlers — untouched.

## Rollout Strategy

Standard: merge PR to `main` and ship in the next release train. No feature flag needed, no migration to sequence, no coordinated cross-service change, no user data touched. Rollback is a straight revert of the merge commit and requires no cleanup — the demo button reverts to its pre-fix visual position, no state is orphaned.

## Out of Scope

- Redesigning `_buildContentCluster`, the `availableHeight / 2` split, or the "form starts at the vertical midpoint" contract. This plan preserves both.
- Revisiting the `_kDemoBandVisible = !kIsWeb` gating or the account-cleanup incident referenced in the temporary comment at [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L47-L52). Honored verbatim.
- Touching PR #278's overflow-safety `Flexible` wrap on the logo. Preserved as-is; it now has a strictly easier job (sole child of the upper-half budget).
- Changing the 12px spacer sizes, the login button spacing, the domain pills spacing, or the trailing 40px spacer. Only the demo button and one of its adjacent 12px spacers move.
- Precaching the logo asset at app startup or altering `assets/images/bandroadie_logo_stacked.png`.
- Any change to animations, cooldown timer, magic-link flow, session detection, Supabase config, deep-link handling, or theme tokens.
- Adding new tests. The bug is a visual-alignment concern; the runtime invariants that matter (button emitted on non-web, no overflow at 800×600) are already covered by Tests A and C, which continue to pass. Tony validates the visual outcome via the owner-run punch list.
- Renaming, reformatting, or reordering any other code in `login_screen.dart`.
