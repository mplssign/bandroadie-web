# ARCHITECT_PLAN.md — Demo Button Test Stale After #271

## Feature Slug

`bug/demo-button-test-stale-after-271`

## Feature Title

login_screen_demo_button_test.dart Test A fails because it predates PR #271's web-only visibility scoping

## Problem Summary

`test/features/auth/login_screen_demo_button_test.dart` fails deterministically on every `flutter test` run. Test A pumps `LoginScreen` and asserts `expect(find.text('Check out the demo band'), findsNothing)`, but PR #271 (commits 4f49299 / d32dfc2 — "hide demo band link on web only, not all platforms") intentionally changed `_kDemoBandVisible` in [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L53) from a plain `false` to `!kIsWeb`. `flutter test` runs on the Dart VM (a non-web target), so `kIsWeb == false`, `_kDemoBandVisible == true`, the `if (_kDemoBandVisible)` branch at [lib/features/auth/login_screen.dart:502](lib/features/auth/login_screen.dart#L502) always emits the `_buildDemoButton()` subtree, and the "Check out the demo band" `Text` at [lib/features/auth/login_screen.dart:665](lib/features/auth/login_screen.dart#L665) is present. The test's assertion no longer matches the shipping product contract — it asserts the pre-#271 "hidden everywhere" behavior that PR #271 deliberately retired.

Test B (retired-easter-egg guard on `find.textContaining('tapping')` / `find.textContaining('demo mode')`) still holds — grep of `lib/` confirms no widget-rendered "Keep tapping" or "demo mode" copy survives — and remains valuable.

## Root Cause

**Confidence:** HIGH (confirmed in code, in the exact three files above).

Test A was authored during the interactive-demo-band-experience feature at a moment when `_kDemoBandVisible = false` (kill-switched pending the anonymous-user cleanup job). Its test description literally acknowledges this: `'temporarily disabled — see _kDemoBandVisible in login_screen.dart'`. PR #271 relaxed the kill switch to non-web only (so native builds can still exercise the demo path pending the web-side cleanup work), but the test file was never updated to match. There is no logic bug — only a test whose contract is now inverted for the target it runs on.

## Existing System Analysis

**Shipping behavior on each target (verified in code):**

| Target | `kIsWeb` | `_kDemoBandVisible` | "Check out the demo band" rendered? |
| --- | --- | --- | --- |
| Flutter web build (`flutter build web`) | `true` | `false` | No — the `if (_kDemoBandVisible)` block at [lib/features/auth/login_screen.dart:502](lib/features/auth/login_screen.dart#L502) is skipped. |
| Native (iOS / Android / macOS) release build | `false` | `true` | Yes — button and 12px spacer emitted. |
| `flutter test` (Dart VM / non-web) | `false` | `true` | Yes — button is in the pumped widget tree. |

**Existing test file structure** ([test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart)):

- File-level comment (lines 1–8): still accurate — describes the file's dual purpose (demo button coverage + easter-egg retirement) and the Supabase-init assertion-scope caveat. No change needed.
- `setUpAll` (lines 22–33): initializes Flutter test binding, mocks `SharedPreferences`, and calls `Supabase.initialize` with dummy URL / publishable key inside a `try/catch` so re-runs in the same process are idempotent. No change needed — the exact same setup supports the corrected Test A.
- Test A (lines 35–56): the only test whose assertion is wrong. Its description ("`is hidden on LoginScreen (temporarily disabled — see _kDemoBandVisible...)`") and its `expect(find.text('Check out the demo band'), findsNothing)` both describe the pre-#271 world.
- Test B (lines 58–79): still valid — grep confirms no `lib/` widget contains "Keep tapping" or "demo mode" copy. Retained unchanged.

**Not in play:** no `lib/` change, no DB migration, no config, no dependency, no init-order shift, no auth/routing/platform-conditional path in `main.dart`. Purely a test-file assertion swap.

## Proposed Solution

Update Test A in [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart) so it asserts the behavior PR #271 actually ships for the target under test:

- Replace the test description string to describe "visible on non-web platforms" (referencing `_kDemoBandVisible = !kIsWeb`) instead of "hidden … temporarily disabled".
- Replace the assertion `expect(find.text('Check out the demo band'), findsNothing)` with `expect(find.text('Check out the demo band'), findsOneWidget)`.
- Add one short inline comment above the assertion recording *why* this is what the non-web VM target should see (so a future reader hitting a web-mode failure has the pointer, and so nobody re-flips this back to `findsNothing` next time they revisit the file).

Test B is left byte-for-byte identical. The file-level header comment and `setUpAll` block are left byte-for-byte identical.

Web-mode coverage (`flutter test -p chrome`) is **not** wired into this repo's CI today. Adding a `!kIsWeb`-gated companion assertion or a separate chrome-only test suite is explicitly out of scope for this bug — see "Out of Scope" below.

## Database Impact

n/a

## Flutter Architecture Changes

n/a — no `lib/` change. No provider, controller, repository, routing, or widget change. Init order in `main.dart` untouched. Platform-conditional code untouched (Firebase-on-native / DeepLinkService-on-native / auth-PKCE-on-both all unchanged).

## Files to Create

n/a — the existing test file receives an edit.

## Files to Modify

| File | Change |
| --- | --- |
| [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart) | Test A only: (1) rewrite the `testWidgets` description string to state that on the non-web VM target the demo button IS present (per `_kDemoBandVisible = !kIsWeb`); (2) flip the final assertion from `findsNothing` to `findsOneWidget`; (3) add one short leading comment on the assertion explaining the target/behavior mapping. Everything else in the file (imports, `setUpAll`, Test B, header comment) stays byte-for-byte identical. |

## Files Off-Limits

| File | Reason |
| --- | --- |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) | Tony (product owner) explicitly rejected reverting `_kDemoBandVisible` back to `false`. `!kIsWeb` is the intended contract — do not touch this file, its comment block, or the `if (_kDemoBandVisible)` branch. |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) | Demo-session provisioning logic — not the source of the test failure and not in scope. |
| [lib/main.dart](lib/main.dart) | No init-order or platform-conditional change is required or permitted for this bug. |
| Any `supabase/migrations/**` file | No DB change. |
| Any `tools/` build script, `dart_defines.json`, or `.entitlements` file | No config or platform-config change. |
| `pubspec.yaml` / `pubspec.lock` | No new dependency. |
| Any other test file under `test/` | Only Test A in `login_screen_demo_button_test.dart` is stale. Do not "improve" adjacent tests opportunistically. |

## Change Budget

| Dimension | Expected |
| --- | --- |
| Net line delta, `test/features/auth/login_screen_demo_button_test.dart` | +2 / -2 (assertion swap + one added inline comment; description string edited in place) — realistic worst case ≤ +5 / -3 including the reworded multi-line description string. |
| New files | 0 |
| New public classes / methods / top-level functions | 0 |
| New dependencies (`pubspec.yaml`) | 0 |
| Other file changes | 0 |

QA compares actual diff against this budget. Any change outside this envelope (touching `lib/`, migrations, config, other tests, etc.) is a plan violation.

## System Impact Map

| System | Status |
| --- | --- |
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected (login-screen shipping code untouched; only its widget-test assertion changes) |
| Routing / Deep links | unaffected |
| Notifications | unaffected |
| Platform: iOS | unaffected (`_kDemoBandVisible = !kIsWeb = true` — button already visible, no runtime change) |
| Platform: Android | unaffected (same as iOS) |
| Platform: macOS | unaffected (same as iOS) |
| Platform: Web | unaffected (`_kDemoBandVisible = !kIsWeb = false` — button already hidden, no runtime change) |
| CI: `flutter test` gate | affected — Test A currently fails deterministically; after this change it passes and correctly guards the non-web contract. |

## Regression Risk

**Level:** LOW.

- Test-only edit. Zero shipping code touched.
- No effect on init order, auth/session/PKCE, routing, DB, RLS, RPCs, notifications, or any platform-conditional path.
- The alternative (reverting `_kDemoBandVisible`) is what would carry regression risk on native builds; this plan explicitly does not do that.
- Test B (easter-egg retirement guard) is retained verbatim, so we do not lose the guard against the 7-tap regression.

## Engineer Task Breakdown

Execute in order. Each task is a single atomic edit to a single file.

### Task 1 — Update Test A description and assertion

- Open [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart).
- In the `testWidgets` block currently labelled `'Test A: "Check out the demo band" button is hidden on LoginScreen (temporarily disabled — see _kDemoBandVisible in login_screen.dart)'`:
  - Rewrite the description string to describe the current intentional contract for this suite's target. Suggested wording (adopt verbatim unless a shorter phrasing reads better):
    `'Test A: "Check out the demo band" button is visible on LoginScreen on non-web platforms (`_kDemoBandVisible = !kIsWeb` — see login_screen.dart; `flutter test` runs on the Dart VM, so this target must render the button)'`.
  - Immediately above the final `expect(...)` line, add one short comment (single line, ≤100 chars) recording the mapping — suggested wording:
    `// Dart VM target: kIsWeb == false → _kDemoBandVisible == true → button is emitted.`
  - Change the assertion from
    `expect(find.text('Check out the demo band'), findsNothing);`
    to
    `expect(find.text('Check out the demo band'), findsOneWidget);`.
- Do NOT touch: the `import` block, `setUpAll`, the widget pump body (`await tester.pumpWidget(...)` and `await tester.pump()`), Test B, or the file-level header comment.

### Task 2 — Verify statically and write ENGINEER_REPORT

- Run `flutter analyze` — must be clean (0 errors, 0 warnings introduced by this change).
- Run `flutter test test/features/auth/login_screen_demo_button_test.dart` — Test A and Test B must both pass.
- Run the full `flutter test` suite once and confirm no other test regressed as a side effect (there should be none — this change is scoped to one file).
- Produce `docs/features/bug/demo-button-test-stale-after-271/ENGINEER_REPORT.md` summarising the diff, listing the analyze / test outputs, and confirming budget compliance.

## Verification Plan

### Tier 1 — Pre-merge, mechanically executable (this is QA's actual gate)

QA runs, in order, and requires all four to be green before APPROVED:

1. **Static analysis**
   - Command: `flutter analyze test/features/auth/login_screen_demo_button_test.dart`
   - Expect: `No issues found!` (or unchanged vs. `main` if pre-existing noise exists elsewhere — but this specific file must be clean).

2. **Targeted test — the exact test the bug report cited**
   - Command: `flutter test test/features/auth/login_screen_demo_button_test.dart`
   - Expect: 2 tests, both pass. Specifically:
     - Test A ("… visible on LoginScreen on non-web platforms …") passes with the button found once.
     - Test B ("retired 7-tap easter-egg hint text is not present") passes unchanged.

3. **Full test suite regression sweep**
   - Command: `flutter test`
   - Expect: no test that passed on `origin/main` (at `ccc91c6`) newly fails on this branch. Test A itself moves from failing → passing.

4. **Diff / budget compliance**
   - Command: `git diff main -- test/features/auth/login_screen_demo_button_test.dart`
   - Expect: only Test A's description string, the one new inline comment, and the final `expect` argument change. Zero changes elsewhere in the file, zero changes outside this file. Net line delta within the Change Budget above.
   - Command: `git diff --stat main` — expect a single file listed (`test/features/auth/login_screen_demo_button_test.dart`) plus the four docs under `docs/features/bug/demo-button-test-stale-after-271/`.

### Tier 2 — Post-deploy / owner-run checks (Tony, not QA)

n/a. This change ships zero runtime behavior. There is nothing for Tony to manually walk through on device or in a browser — the shipping product behaves identically before and after this merge on every platform. Tony's only PR-time task is a visual review of the diff against the plan.

## QA Regression Areas

- **Login screen visual behavior on any platform:** unaffected. Confirm by inspection of the diff that no `lib/` file changed.
- **CI test gate:** confirm that `flutter test` transitions from red (Test A failing) on `main` to fully green on this branch.
- **Other tests that pump `LoginScreen`:** grep for `LoginScreen(` under `test/` — none other exist besides this file; no ripple risk.
- **`kIsWeb`-conditional test infrastructure:** none exists in this repo today; nothing to regress there.

## Rollout Strategy

Standard PR merge to `main`. No feature flag, no phased rollout, no migration, no cache bust, no post-deploy step, no user-facing announcement. The change is invisible to users on every platform.

## Out of Scope

- **Adding a web-target companion test.** Running the assertion inverted under `flutter test -p chrome` (asserting `findsNothing` on the web target) would be nice-to-have coverage, but this repo's CI does not run chrome-mode tests, and adding chrome-mode CI is its own infrastructure change. Defer to a separate ticket if desired.
- **Reverting `_kDemoBandVisible` to `false`.** Explicitly rejected by Tony per Manager confirmation. Do not touch [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart).
- **Refactoring the demo-button visibility contract** (e.g. moving it behind a dart-define, provider, or remote-config flag). Not requested; not required to make CI green.
- **Any other stale test.** If Engineer notices additional tests that look stale, that is a separate diagnosis — do not fold it into this PR.
