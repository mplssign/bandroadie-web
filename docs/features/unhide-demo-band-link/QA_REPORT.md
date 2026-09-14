# QA Report

## Feature Slug

`unhide-demo-band-link`

## Feature Title

Unhide the "Check out the demo band" link on the login screen

## Cycle Number

1

## Final Verdict

APPROVED

## Validation Summary

The uncommitted implementation matches the Architect plan. The visibility gate is
now enabled on every Flutter target, its existing call site and behavior remain
unchanged, Test A's stale platform wording is corrected, and DECISION-007 records
the required scope and security tradeoff. Static analysis and all required tests
pass. No application runtime, simulator, emulator, browser, or live backend was
launched; the plan correctly classifies those checks as owner-run.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all use `unhide-demo-band-link`.
- The tracked implementation diff modifies exactly the three authorized files:
  `lib/features/auth/login_screen.dart`,
  `test/features/auth/login_screen_demo_button_test.dart`, and
  `docs/reference/general/AI_DECISIONS.md`.
- The feature plan and Engineer/QA reports are expected pipeline artifacts under
  `docs/features/unhide-demo-band-link/`; they are not application implementation.
- No off-limits source, migration, Edge Function, config, dependency, platform
  runner, or unrelated test file changed.
- No architectural changes, new dependencies, public APIs, providers, helpers,
  widgets, or database objects were introduced.

## Completeness Check

All five Architect tasks are complete:

1. The stale kill-switch comment was replaced with the current capacity envelope.
2. `_kDemoBandVisible` remains a const and is set to `true`.
3. Test A's description states the all-platform contract.
4. Test A's inline comment is current and its `findsOneWidget` assertion is unchanged.
5. DECISION-007 covers all-platform visibility, the intentionally native-only
   pre-init purge, the 30-slot/8-minute/2-minute controls, Supabase auth-layer rate
   limiting, the lack of an app-level per-IP throttle, and the feature slug.

No plan-specified edge case or documentation requirement is missing.

## Behavior Verification

Code-path analysis confirmed `const bool _kDemoBandVisible = true;` feeds the
unchanged `if (_kDemoBandVisible)` gate, which still renders the existing
`_buildDemoButton()` without changing `_enterDemo`, layout transforms, or spacing.
The unrelated `_sendMagicLink` `kIsWeb` branch remains present and untouched.

The widget harness exercised the visible-button and constrained-layout paths on the
Dart VM. This was not runtime verification on a native device or web browser, so
cross-platform visual placement and live demo provisioning remain in the owner-run
punch list below.

## Regression Check

Overall regression risk: **MEDIUM**, matching the Architect plan because anonymous
demo provisioning becomes newly reachable from the production web login screen.

| System | Risk | Result |
| --- | --- | --- |
| Auth (web) | MEDIUM | Existing demo provisioning becomes reachable; service/RPC code is unchanged and full tests pass. |
| Login layout (web) | MEDIUM | Existing button subtree is newly emitted; the 800x600 overflow harness passes, with browser visuals owner-run. |
| Auth and login layout (native) | LOW | The flag evaluated true before and after; render behavior is unchanged. |
| Demo lifecycle and anonymous recovery | LOW | No implementation touch; full lifecycle/recovery coverage remains green. |
| App init order and real-user auth | LOW | `lib/main.dart`, session purge, magic-link flow, and redirect behavior are untouched. |
| Gigs, rehearsals, setlists, members | LOW | No touchpoint. |
| Routing, deep links, notifications | LOW | No touchpoint. |
| Platform runners and configuration | LOW | No touchpoint. |
| Documentation | LOW | One scoped decision entry was appended as required. |

Controller/FocusNode disposal, async `setState` guards, rebuild frequency, RPC
signatures, and initialization order are unchanged by the diff.

## Database Safety

Not applicable. The diff contains no migration, SQL, RLS, RPC, trigger, grant,
Edge Function, or client RPC signature change. No preview database was needed or
used.

## Analyzer Results

- `flutter analyze`: **PASS** — `No issues found!`
- This full-repository result includes every file in the implementation diff and
  is empty at all analyzer severities.

## Test Results

- `test/features/auth/login_screen_demo_button_test.dart`: **PASS** — 5 passed,
  0 failed.
- Full Flutter test suite: **PASS** — 322 passed, 0 failed.
- The full run includes the plan-named demo lifecycle and anonymous recovery areas.

## Diff Safety Review

- `git diff --check`: clean.
- No `TODO`, `FIXME`, or `debugPrint(` marker appears in the diff.
- No secret, API key, credential, or production token was introduced.
- No accidental deletion, test scaffolding, unrelated formatting churn, binary,
  generated file, or out-of-scope implementation was found.

## Change Budget Review

| File | Actual | Planned | Assessment |
| --- | ---: | ---: | --- |
| `lib/features/auth/login_screen.dart` | +3 / -5, net -2 | net -3 to -5 | Within the plan's small-change intent; the existing comment had four lines rather than the budget's stated five. |
| `test/features/auth/login_screen_demo_button_test.dart` | +2 / -3, net -1 | net 0 to +1 | Smaller wording replacement; no behavior or assertion change. |
| `docs/reference/general/AI_DECISIONS.md` | +21 / -0 | +12 to +25 | Within budget. |

Total tracked implementation delta is +26 / -8 (net +18). There are zero new
implementation files, dependencies, migrations, Edge Functions, or public symbols.
No file exceeds the 1.5x warning threshold or 2x critical threshold.

## Code Efficiency Review

No new code symbol was added, so no equivalent-helper search was applicable. The
change preserves the existing single visibility gate and adds no wrapper,
single-use builder, state owner, fetch path, dead field, future flag, or redundant
exception handling. `login_screen.dart` remains above its size target, but the
Engineer report supplies the required justification and this change reduces it by
two net lines while the plan forbids structural work in that file.

## Manual Verification Punch List

1. Run `./run.sh macos`. **Expected:** login screen renders "Check out the demo band" text button between the logo cluster and the email field, in the same position it renders today on native (no visual regression). Tap it — the demo experience provisions as it does today.
2. Run `flutter run -d ios` (or launch the current TestFlight/dev build on iPhone). **Expected:** identical to macOS above — no visual regression on iOS.
3. Run `flutter run -d chrome` (or open the current dev deploy in Chrome / Safari / Firefox). **Expected:** login screen renders "Check out the demo band" text button (previously hidden on web). Position and styling should match the native rendering (upper-half logo box, then demo button, then email field, then domain pills, then login button). Tap the button — demo provisioning should succeed and route to the cloned Banana Stand band, matching the native flow.
4. On the same Chrome session, still inside the demo band, refresh the browser tab. **Expected (documented, not a defect for this fix):** the anonymous session persists and the app re-enters the demo band; it does **not** return to the login screen. This differs from the native cold-start contract recorded in AI_DECISIONS ("Never resume an anonymous/demo session across a relaunch"). If this is unwanted on web, file a follow-up feature to extend the [lib/main.dart](lib/main.dart#L64-L65) pre-init purge to web — that work is explicitly out of scope for this feature (see Out of Scope).
5. On Chrome, provision a demo, tap "Exit Demo" from wherever it lives in the shell, and confirm you land on the login screen. **Expected:** identical to native exit behavior.
6. Optional load check (only if Tony wants signal on the web-spam surface flagged in Regression Risk item 1): from a fresh Chrome incognito window, tap the demo button ~5 times over a minute. **Expected:** either the first tap succeeds and subsequent taps reuse the same anonymous session (RPC is idempotent per `provision_demo_session()`'s `demo_sessions` unique-key on `auth_user_id`), or Supabase's own auth-layer rate limiting rejects — either is acceptable. If successive taps each mint a distinct anonymous user _and_ each get through the 30-slot ceiling, that is a signal to add app-level per-IP throttling as a follow-up.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.