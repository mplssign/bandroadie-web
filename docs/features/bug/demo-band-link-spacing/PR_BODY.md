## Summary

On the login screen, the "Check out the demo band" link sat too close to the logo and too far from the Email address field. This PR repositions the login screen's content cluster so the demo link groups visually with the login form instead of the branding cluster, and applies additional fine-tuning requested by the app owner after visual testing.

## Changes

- Moved the demo band link out of the logo's layout box and placed it directly above the Email field.
- Biased the logo's position within its allotted space so the demo link sits roughly midway between its original and first-revision positions.
- Applied final pixel-level position adjustments (paint-only, via `Transform.translate`):
  - Logo: up 50px
  - "Check out the demo band" link: up 65px
  - Email field + email domain shortcuts: up 50px

All changes are confined to `_buildContentCluster()` in `lib/features/auth/login_screen.dart`. No logic, auth flow, animation, or database changes.

## Verification

- `flutter analyze` — clean
- `flutter test test/features/auth/login_screen_demo_button_test.dart` — 3/3 pass
- 20-iteration stability loop on the overflow-safety test — 20/20 pass
- No automated test can verify visual overlap (paint-only transforms don't affect layout size), so a manual check is needed — see punch list below.

## Manual Verification Punch List (for reviewer/tester)

1. **Priority check:** On a compact window size (~800×600 on macOS, or a small phone), confirm the logo and the "Check out the demo band" link do not visually overlap. Their gap shrank by 15px in the final adjustment, and this is the one spot the three independent moves could plausibly touch.
2. Run on macOS/iOS: confirm the demo link now sits closer to the Email field, farther from the logo.
3. Confirm entrance animation still plays normally and keyboard-open logo shrink still works.
4. Run on web (Chrome): confirm the demo link is still hidden (unaffected by `_kDemoBandVisible`), and note whether the logo/email field shift is expected on web too (the translate wraps are not currently gated to non-web).
5. Resize the macOS window across a range of sizes; confirm no "BOTTOM OVERFLOWED" banner appears at any point.

## Known limitation / residual note

QA approved with a non-blocking flagged risk: the four position offsets aren't gated by `_kDemoBandVisible`/`kIsWeb`, so the shift also applies on web (previously login screen was pixel-identical between cycles on web). Confirm this is the intended behavior when testing.
