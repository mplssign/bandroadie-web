## Summary

Fixes an intermittent `RenderFlex overflowed by 173 pixels on the bottom` in `LoginScreen._buildContentCluster()`. The logo image has no height cap, so once its asset codec resolves it reports its true intrinsic height (aspect ≈ 3:2); combined with the demo button (visible on non-web targets per #271) and spacers, the inner `Column` can need ~473px inside a 300px half-height budget at compact viewports (e.g. an 800×600 window). The failure was intermittent in tests only because a single-frame `pump()` races the async image codec — the underlying overflow is real and would also occur in the running app at compact window sizes, not just in tests.

## Root Cause

`Image.asset(width: logoWidth, fit: BoxFit.contain)` inside `_buildLogo` has no `height`/`maxHeight` constraint, and the inner `Column` (default `MainAxisSize.max`) has no flexible children to absorb the resulting oversized intrinsic height.

## Fix

Wrap the logo in `Flexible(child: _buildLogo(...))` inside the inner `Column`. This caps the logo's `maxHeight` at whatever space remains after the demo button and spacers, letting `BoxFit.contain` scale it down proportionally. No behavior change on mobile portrait viewports, where the constraint never binds.

## Testing

- `flutter analyze` — clean on both changed files.
- `flutter test test/features/auth/login_screen_demo_button_test.dart` — all 3 tests pass (added Test C, which pre-caches the logo image for a deterministic worst-case check).
- Loop-stability (per the bug report's explicit "don't trust a single green run" instruction), independently re-run by QA: Test C ×20 → 20/20 pass; Test B (the historically-racy case) ×20 → 20/20 pass.

## Scope

Only two files touched: `lib/features/auth/login_screen.dart` (layout wrap + docstring accuracy update) and `test/features/auth/login_screen_demo_button_test.dart` (new regression test). No auth, session, animation, routing, or database changes.

## Manual verification still needed (owner-run, not part of this PR's automated gate)

1. `flutter run -d macos`, resize window to ~800×600 — no overflow banner, logo scales, demo button visible.
2. Resize window between ~600×500 and ~1200×900 — no overflow at any size, smooth scaling.
3. `flutter run -d ios` — visual no-op, renders as before.
4. `flutter run -d chrome` at ~800×600 and ~1440×900 — no demo button (web target), no visual regression.
