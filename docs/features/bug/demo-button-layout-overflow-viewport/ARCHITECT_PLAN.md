# ARCHITECT_PLAN — bug/demo-button-layout-overflow-viewport

## Feature Slug

`bug/demo-button-layout-overflow-viewport`

## Feature Title

`_buildContentCluster`'s half-height `SizedBox` intermittently overflows by 173px in tests when the demo button is visible

## Problem Summary

`LoginScreen._buildContentCluster()` reserves the top half of the available height for a cluster containing the logo + demo button + a trailing 12px spacer. In the widget-test harness (800×600, non-web target → `_kDemoBandVisible == true`), the inner `Column` inside that half-height `SizedBox` fails intermittently with `RenderFlex overflowed by 173 pixels on the bottom` at `login_screen.dart:498`. Three of four CI runs on identical source failed; one passed. Diagnosis (below) shows the intermittency is a race between the logo's async image codec and the single-frame `pump()`, and the *underlying* overflow is a real, deterministic layout defect that would also fire in the running macOS app at compact window sizes — not test-only.

## Root Cause

**Confidence: HIGH.** The math reproduces the reported 173px overflow exactly.

The logo asset `assets/images/bandroadie_logo_stacked.png` is **964 × 645** pixels (aspect ≈ 1.494:1, near 3:2). `_buildContentCluster` computes:

- `maxWidth  = constraints.maxWidth - 64`
- `logoWidth = (maxWidth * 0.9).clamp(0.0, 600.0)`

and hands that to `_buildLogo`, which renders `Image.asset(width: logoWidth, fit: BoxFit.contain)` with **no height cap**. `Image.asset` with only `width` set produces an intrinsic height of `logoWidth / aspect` **once the image codec resolves**; before it resolves, the render box reports height ≈ 0.

At the test viewport of 800×600 (`SafeArea` insets = 0, `keyboardHeight` = 0, so `availableHeight = 600`):

| Quantity | Value |
| --- | --- |
| Inner `SizedBox` budget | `600 / 2 = 300px` |
| `logoWidth` | `(800 − 64) × 0.9 = 662.4 → clamp 600` |
| Logo intrinsic height once loaded | `600 × 645 / 964 = 401.45px` |
| `SizedBox(height: 12)` × 2 | `24px` |
| `_buildDemoButton` (Material `TextButton`) | ≈ `48px` |
| Inner Column children total (button visible + logo loaded) | `401.45 + 12 + 48 + 12 = 473.45px` |
| Overflow | `473.45 − 300 = 173.45px` ≈ **173px** ✅ |

So the overflow is a **fixed, deterministic geometry defect** whenever *both* (a) the demo button is emitted and (b) the logo image codec has completed before layout. The **intermittency** is (b): `Image.asset` starts an async `ImageStream`. In a single-frame `pump()` the codec may or may not finish before layout, depending on CI CPU scheduling. When it does, the logo reports its true 401px height and the inner column overflows. When it doesn't, the logo reports ~0 height and the layout fits — which is why 1 of 4 CI runs passed.

**Is this test-only or user-facing?** The Open Question is now answerable: this is *also* user-facing. In the running app the logo image always eventually loads, so any viewport whose `availableHeight / 2` is less than `logoHeight + 72` will overflow deterministically. At a 800×600 macOS window (or the equivalent Chrome/Edge desktop size on web — though `_kDemoBandVisible` is `false` on web, so only the logo + trailing 12px would need to fit; on web the trigger threshold is lower but the base defect is the same), the overflow renders. On typical mobile portrait (e.g. 390×844), `logoWidth` shrinks to 293 and the resulting `logoHeight ≈ 196px` fits comfortably in the ~358px half-height budget — which is why the bug hasn't been visible in normal phone testing. This changes the scope: the fix must produce a viewport-safe layout, not just a viewport-safe test.

Contributing architectural factor: PR #271 added `if (_kDemoBandVisible) …` inside the pre-existing half-height `SizedBox` without reducing the logo's height allowance. The docstring on `_buildContentCluster` still describes the pre-#271 contract ("Logo occupies the upper half of `availableHeight`, centered within it"), so the +72px of new siblings share the same fixed budget with no fallback.

## Existing System Analysis

- `LoginScreen.build` wraps its body in `SafeArea → LayoutBuilder → AnimatedPadding → SingleChildScrollView → ConstrainedBox(minHeight: available) → Padding(hz:32) → AnimatedBuilder → _buildContentCluster(...)`. `SingleChildScrollView` absorbs any *outer* overflow gracefully, so overflow can only surface at a **hard-height** inner container. There is exactly one such container: the `SizedBox(height: availableHeight / 2)` at `login_screen.dart:498`.
- Inside that `SizedBox`, an unadorned `Column(mainAxisAlignment: center)` — `MainAxisSize.max` by default — must fit `_buildLogo` + `if (_kDemoBandVisible) SizedBox(12) + _buildDemoButton()` + trailing `SizedBox(12)`. None of these children are flexible; all report full intrinsic height, so the Column has no way to shrink under pressure.
- `_buildLogo` wraps `Image.asset` in `FadeTransition → ScaleTransition → AnimatedBuilder → Transform.scale`. `FadeTransition`, `ScaleTransition`, and `Transform.scale` are all *paint-time* — none affect layout. Layout height comes solely from `Image.asset`'s codec-driven intrinsic size.
- `_buildDemoButton` is a Material `TextButton` (`Row(mainAxisSize: min, [Text(14), SizedBox(4), Icon(16)])`), height ≈ 48px and stable frame-to-frame — not an intermittency source.
- The two failing test cases in `test/features/auth/login_screen_demo_button_test.dart` do a single `await tester.pump()` after `pumpWidget`. Neither test asserts layout — they assert widget presence/absence — but a `RenderFlex` overflow throws a `FlutterError` that `takeException()`/`tester.binding.takeException()` surfaces as a test failure. That's the observed failure mode.

## Proposed Solution

Wrap the logo widget (returned by `_buildLogo(...)`) in `Flexible(fit: FlexFit.loose)` inside the inner `Column` at `login_screen.dart:498`. This is the single minimal change.

Consequences:

- The inner `Column` becomes: `[Flexible(_buildLogo), (SizedBox(12) + _buildDemoButton())?, SizedBox(12)]`.
- Non-flexible children (SizedBox × 2 + demo button) consume ~72px first. The `Flexible` child then receives `maxHeight = availableHeight/2 − 72` (≈ 228px at test size). `RenderImage` with an explicit `width: 600` and no explicit `height`, under a parent `maxHeight` of 228, calls `constrainSizeAndAttemptToPreserveAspectRatio(Size(600, ≈0))` on the incoming constraints. Because the loaded image has a real intrinsic aspect (964:645), `BoxFit.contain` uses that aspect to scale within the constrained box — the rendered image lands at approximately 340 × 228, preserving aspect ratio.
- If the codec has not yet resolved (test single-frame race), the image renders at ~0 height as it does today. `Flexible(fit: FlexFit.loose)` accepts min = 0, so this is fine.
- On mobile portrait, the constraint (~358px half budget vs ~196px logo) never activates; layout is visually identical to today.
- The paint-time wrappers (`FadeTransition`, `ScaleTransition`, `AnimatedBuilder`, `Transform.scale`) all remain outside/inside `Flexible` in their existing order — none affect layout, so animation behavior is unchanged.

The docstring on `_buildContentCluster` gets one accuracy update: the current wording ("Logo occupies the upper half of `availableHeight`") is stale post-#271. Amend it to reflect that the top half is now shared by logo + demo button (when visible), with the logo shrinking to fit under pressure.

Alternatives considered and rejected:

- **Compute an explicit `maxLogoHeight` and pass it into `_buildLogo`.** Correct but more invasive; requires a new parameter and reserving a hardcoded ~72px for demo-button + spacings that duplicates Material's own sizing. `Flexible` gets the same result for free.
- **Replace the `SizedBox(height: availableHeight/2)` with `Expanded` in the outer Column.** Changes the "form starts at the vertical midpoint" contract intentionally documented on `_buildContentCluster`; larger surface-area change with UX ripple. Not minimal.
- **Fix the test viewport to be tall enough not to overflow.** Treats the symptom, not the cause; the deterministic macOS-window overflow remains.
- **`precacheImage` at app startup to make single-frame tests behave.** Fixes the test race but not the real overflow at compact desktop viewports.

## Database Impact

n/a

## Flutter Architecture Changes

Layout-only change to one widget in `LoginScreen`. No new provider, controller, repository, service, model, or router entry. No init-order effect. No platform-conditional code touched — `_kDemoBandVisible` gating is not modified.

## Files to Create

n/a

## Files to Modify

| File | Change |
| --- | --- |
| `lib/features/auth/login_screen.dart` | In `_buildContentCluster()` at the inner `Column` child of the `SizedBox(height: availableHeight/2)` (currently line ~498–506), wrap the `_buildLogo(logoWidth: logoWidth)` call in `Flexible(child: _buildLogo(logoWidth: logoWidth))`. Amend the `_buildContentCluster` docstring so the "Layout contract" bullets reflect that the top-half budget is shared by logo + demo button (when `_kDemoBandVisible`), and the logo shrinks via `BoxFit.contain` when the demo button consumes part of that budget. No other lines change. |
| `test/features/auth/login_screen_demo_button_test.dart` | Append one new test case: `'Test C: content cluster fits within 800×600 without RenderFlex overflow'`. It must (a) call `tester.view.physicalSize = const Size(800, 600)` and `tester.view.devicePixelRatio = 1.0`, with `addTearDown(tester.view.resetPhysicalSize)` and `addTearDown(tester.view.resetDevicePixelRatio)`; (b) `pumpWidget` the same `ProviderScope > MaterialApp > FTheme > LoginScreen` tree used by Tests A & B; (c) call `await precacheImage(const AssetImage('assets/images/bandroadie_logo_stacked.png'), tester.element(find.byType(LoginScreen)))` inside `tester.runAsync(...)` so the logo codec is guaranteed complete before layout is measured — this converts the intermittent test into a deterministic worst-case test; (d) do a `pumpAndSettle()` so all animation-driven state stabilises; (e) assert `expect(tester.takeException(), isNull)`. No layout-geometry assertions beyond "no thrown exception" — the guarantee we want is "does not overflow". |

## Files Off-Limits

| File | Reason |
| --- | --- |
| `lib/main.dart`, `lib/app/**` | Init order and app-wide theme are out of scope; the fix is a single-widget layout change. |
| `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` | No new dependency or lint change is required or justified. |
| `supabase/**`, `database/**`, `lib/features/auth/demo_session_service.dart`, `lib/features/auth/auth_gate.dart`, `lib/features/auth/auth_confirm_screen.dart` | Not a data / RLS / auth-flow issue; only login-screen widget geometry. |
| `assets/images/bandroadie_logo_stacked.png` | Not an asset defect. The fix must tolerate the existing 964×645 asset (and any other reasonable aspect the design team might swap in later). |
| `lib/features/auth/login_screen.dart` outside `_buildContentCluster` (animations, cooldown timer, magic-link handlers, `_checkExistingSession`, `_buildLogo` internals, `_buildEmailField`, `_buildDomainPills`, `_buildLoginButton`, `_buildMessage`, `_buildDemoButton`) | These are unrelated to the overflow. Do not "improve" them, retheme them, or reformat them. |
| `test/features/auth/login_screen_demo_button_test.dart` — existing Test A and Test B bodies | Do not change their assertions, setup, or naming; only append Test C below them. |
| Any file in `lib/features/**` other than `login_screen.dart` | Cross-feature scope creep. |

## Change Budget

| File | Expected net line delta |
| --- | --- |
| `lib/features/auth/login_screen.dart` | +2 to +4 lines (1 `Flexible(child: … )` wrap; docstring wording update) |
| `test/features/auth/login_screen_demo_button_test.dart` | +40 to +60 lines (one new `testWidgets` block) |

- Expected new files: 0
- Expected new public classes / methods: 0
- Expected new dependencies: 0

## System Impact Map

| System | Status |
| --- | --- |
| Auth (magic link, PKCE, session) | Unaffected — no logic change; only layout of the login screen surface. |
| Gigs / Rehearsals / Setlists / Members / Financials | Unaffected. |
| Routing / Deep links | Unaffected. |
| Notifications | Unaffected. |
| Init order (`WidgetsFlutterBinding` → URL strategy → orientation lock → `AppVersionService` → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp` [native] → `DeepLinkService` → `runApp`) | Unaffected. |
| Platform parity (iOS / Android / macOS / web) | All platforms render `LoginScreen`; on mobile portrait the fix is a no-op (constraint never binds); on macOS at compact window sizes and on any short-viewport surface the logo now shrinks via `BoxFit.contain` instead of overflowing. Web layout matches today (still no demo button); web at short viewports also benefits from the same `Flexible` (logo + trailing 12px) if that path ever binds. |
| Demo-band visibility gating (`_kDemoBandVisible = !kIsWeb`, per #271 and the temporary comment in `login_screen.dart:47–50`) | Unaffected — this fix does not change when the button renders. |

## Regression Risk

**LOW.** The change is a single widget-tree wrap that constrains a currently-unconstrained image. It cannot alter auth behavior, session behavior, routing, or animation timing — the paint-time transforms nested inside the image and the entrance animation intervals are untouched. The only visible behavior change is that at compact viewports where the logo would today overflow (or would in the running macOS 800×600 case), it instead scales down via `BoxFit.contain`, which is Flutter's standard aspect-preserving behavior.

## Engineer Task Breakdown

1. In `lib/features/auth/login_screen.dart`, inside `_buildContentCluster()`, wrap the `_buildLogo(logoWidth: logoWidth)` call in the inner `Column` (child of `SizedBox(height: availableHeight / 2)`) with `Flexible(child: _buildLogo(logoWidth: logoWidth))`. Change nothing else about that Column, its `mainAxisAlignment: MainAxisAlignment.center`, or the demo-button / trailing-spacer children.
2. In the same file, update the doc-comment block above `_buildContentCluster` so its "Layout contract" bullets acknowledge the demo button now shares the top-half budget when `_kDemoBandVisible`, and note that the logo shrinks via `BoxFit.contain` under pressure. Keep the comment tight (≤3 short lines of change).
3. In `test/features/auth/login_screen_demo_button_test.dart`, append a third `testWidgets` case named `'Test C: content cluster fits within 800×600 without RenderFlex overflow (button visible)'`. Follow the exact recipe in "Files to Modify" above — set `tester.view.physicalSize`, register the two `addTearDown` resets, pump the same widget tree as Tests A/B, use `tester.runAsync` to await `precacheImage` on the stacked-logo `AssetImage`, then `pumpAndSettle()`, then assert `expect(tester.takeException(), isNull)`. Do not add layout-geometry assertions.
4. Run `flutter analyze`. Fix any warnings introduced by the two-file change; do not touch pre-existing warnings.
5. Run `flutter test test/features/auth/login_screen_demo_button_test.dart` locally in a 10-iteration loop to confirm all three tests are deterministic under the fix. If Test C ever fails in that loop, stop and report — do not merge on a single green run (see the original Feature Input warning).

## Verification Plan

### Tier 1 — Pre-deploy, mechanically executable without a running app (QA gate)

1. `flutter analyze` — no new warnings/errors introduced by the diff. QA compares the analyzer output against a baseline run on the branch parent commit if needed.
2. `flutter test test/features/auth/login_screen_demo_button_test.dart` — all three tests pass.
3. Loop stability: `for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" || echo "FAILED run $i"; done` — Test C must pass 20 / 20. This directly answers the "3 of 4 CI runs failed" repro from the Feature Input: with the codec pre-cached via `precacheImage`, the test no longer races, so any failure would indicate the layout fix itself is wrong.
4. Loop stability for the historically-failing case: same 20-iteration loop against `--plain-name "Test B"` — must pass 20 / 20. This proves the underlying overflow (which was surfacing under Test B) is fixed even in a test that does NOT pre-cache the image.
5. Static diff check: the diff against `origin/main` touches only `lib/features/auth/login_screen.dart` and `test/features/auth/login_screen_demo_button_test.dart`. Any other file in the diff is out of budget → fail.
6. Line-delta check: `login_screen.dart` net +2 to +4; test file net +40 to +60. Outside these bounds → warn.

Tier 1 tests are safe against the "never call the function being replaced" rule because Test C is *added*, not replacing anything: the pre-existing Tests A and B are untouched and remain the ambient regression guarantee.

### Tier 2 — Post-deploy

n/a. There is no database change, no RPC change, no edge function change, no schema/migration to verify against production.

### Owner-run at PR-test / apply time (Tony's punch list — QA hands this to Tony verbatim; QA does not attempt these)

QA cannot launch the app in this pipeline. Tony runs the following at PR-test time; the results are recorded on the PR before merge, not gated by QA.

1. `flutter run -d macos` — the macOS app launches to `LoginScreen`.
2. Resize the macOS window so the client area is approximately **800 × 600** (any tool: green-button double-click a compact preset, or drag the corner while watching Window → Zoom info). Verify: no red-and-yellow "BOTTOM OVERFLOWED BY 173 PIXELS" banner; logo is visible and scaled to fit; "Check out the demo band" text button visible directly beneath the logo; email field, domain pills, and Email Login Link button all visible below without clipping.
3. Slowly resize the window from ~800×600 down to ~600×500 and back up to ~1200×900. Verify: at no point does an overflow banner appear; logo scales smoothly; demo button remains visible at all sizes; no jitter or animation restart on resize.
4. `flutter run -d ios` (or an iOS simulator such as iPhone 15). Verify: `LoginScreen` renders exactly as before — logo at its usual size, demo button present, no overflow banner, entrance animation plays through once. This confirms the mobile-portrait path is a visual no-op.
5. `flutter run -d chrome` at a browser window ~800×600. Verify: `LoginScreen` renders with the logo, email field, pills, and login button; the demo button is **not** present (web target); no overflow banner.
6. `flutter run -d chrome` at a browser window ~1440×900 (typical laptop). Verify: layout looks identical to what shipped on `origin/main` — no visual regression at standard desktop sizes.

## QA Regression Areas

- LoginScreen visual layout across viewport sizes: mobile portrait, macOS default window, macOS compact window, web wide, web compact. (QA validates via Tier 1 + hands Tony the punch list; QA does not run the app.)
- Demo button rendering and tap wiring — `_buildDemoButton` and `_enterDemo` are not touched; existing Test A guarantees the button is emitted on non-web targets.
- Login entrance animation — no animation code is touched; all `FadeTransition` / `ScaleTransition` / `SlideTransition` / interval calculations remain. The `Flexible` wrap sits outside the paint-time transforms, so `Transform.scale` for `_logoShrinkScale` still applies correctly.
- Keyboard-open behavior — `keyboardHeight` handling and `_logoShrinkController` are unchanged.
- `_checkExistingSession` + `_sessionDetected` short-circuit — untouched.
- Cooldown timer + magic-link send — untouched.

## Rollout Strategy

Standard: merge PR to `main` and ship in the next release train. No feature flag needed, no migration to sequence, no coordinated cross-service change, no user data touched. Rollback is a straight revert of the merge commit and requires no cleanup.

## Out of Scope

- Redesigning `_buildContentCluster` to be fundamentally viewport-adaptive beyond the `Flexible` wrap (e.g. adopting a `CustomMultiChildLayout`, restructuring around a `Column(Expanded(top), Expanded(bottom))` model, or introducing a viewport-breakpoint-driven layout).
- Revisiting the `_kDemoBandVisible = !kIsWeb` gating or the account-cleanup incident referenced in the temporary comment at `login_screen.dart:47–50`. This plan honors the current gating verbatim.
- Precaching `bandroadie_logo_stacked.png` at app startup. The test uses `precacheImage` locally for determinism; production behavior is unchanged.
- Swapping the logo asset for a different aspect ratio. The fix must work with the current 964×645 asset and any future variant.
- Any change to animations, cooldown timer, magic-link flow, session detection, Supabase config, deep-link handling, or theme tokens.
- `test/features/auth/auth_gate_anonymous_recovery_test.dart` or any other auth test — scope creep.
- Renaming, reformatting, or reordering unrelated code in `login_screen.dart`.
