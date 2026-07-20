# QA Report

## Feature Slug

bug/invite-link-opens-browser-not-app

## Feature Title

Invite Link Opens Browser, Not App

## Final Verdict

**APPROVED**

## Validation Summary

Re-validated implementation against the Architect plan via code-path analysis, `git diff main`, and a fresh `flutter analyze` run.
Confirmed both previously reported critical issues are now fixed: duplicate invite acceptance race and duplicate runtime invite-route stacking in auth-param invite redirects.
No new regressions were found in the touched auth/deep-link paths during static review.
End-to-end Universal Links/App Links behavior still requires post-ship device/simulator validation.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected
- Files off-limits: not touched

## Completeness Check

- All Architect tasks implemented: yes
- Missing tasks: none

## Behavior Verification

- Validation method: code-path analysis
- Result: matches expected

Re-verification details:

- `InviteScreen._handleInvite()` now guards the direct post-session call with `!_hasTriedAccept` before `_acceptInvite(token)`, matching the listener guard and closing the race where auth session becomes available during the 500ms delay.
- `DeepLinkService._handleInviteLink()` now returns immediately after `_handleAuthCallback()` when invite auth params exist, so runtime forwarding only happens for invite links without auth params.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Auth/Session, Routing, iOS Universal Links assets/config, Android App Links config, web hosting rewrites/headers
- Regressions found: none in reviewed code paths

## Database Safety

Not applicable

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors

## Test Results

Not run

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: none found

## Issues Found

None

### Suggestions (optional)

1. Consider a future UX hardening for runtime bare invite links when an invite screen is already visible (for example, replace/update current invite route instead of stacking another). This is a residual edge case and not a blocker for this fix.
2. Add a targeted widget/integration test (or service-level test harness) for invite links carrying `token + code`, covering both cold-start and runtime-resume sequencing.

## Requested Checks Coverage

1. `_forwardToInviteRoute()` API correctness: Confirmed for Flutter 3.44.6. In framework source (`packages/flutter/lib/src/widgets/binding.dart`), `handlePushRoute(String route)` exists and dispatches to `didPushRouteInformation`; annotations are `@protected` and `@visibleForTesting`, so suppression is required. Suppression is narrowly scoped to the single call site.
2. `_handleInviteLink()` + invite auth params double-processing risk: Resolved. Auth-param invite links now process auth and return, without runtime route forwarding.
3. AASA + identifiers + header shadowing:
   - AASA is valid JSON and includes `appID: 6SR6X9W8A8.com.bandroadie.app` with invite/auth paths.
   - `ios/Runner.xcodeproj/project.pbxproj` contains `DEVELOPMENT_TEAM = 6SR6X9W8A8` and `PRODUCT_BUNDLE_IDENTIFIER = com.bandroadie.app`.
   - `web/vercel.json` catch-all rewrite excludes `.well-known` (`/((?!api/|.well-known/).*)`), so the AASA header rule is not shadowed by SPA rewrite.
4. Cold-start behavior: Correctly left intact. `DeepLinkService` only forwards invite route for `source == 'runtime'`, so cold start continues to rely on Flutter initial route handling via `main.dart` `onGenerateRoute`.
5. Auth deep-link regression sweep: Auth callback parsing/exchange code path remains intact; no new auth-path regressions found in static review.

## Manual Verification Requirement

QA cannot fully verify this fix end-to-end from static code inspection alone.
After web assets deploy and new mobile builds ship, manual verification on real iOS and Android devices (or simulators with proper Universal Links/App Links setup) is required before final release sign-off.
