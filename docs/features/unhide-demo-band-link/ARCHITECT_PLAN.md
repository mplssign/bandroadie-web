# ARCHITECT_PLAN — Unhide the "Check out the demo band" link on the login screen

## Feature Slug

`unhide-demo-band-link`

## Feature Title

Unhide the "Check out the demo band" link on the login screen

## Problem Summary

The "Check out the demo band" link on the login screen is currently hidden on
the web target and visible on native (iOS / Android / macOS) via
`const bool _kDemoBandVisible = !kIsWeb;` at
[lib/features/auth/login_screen.dart:53](lib/features/auth/login_screen.dart#L53).
The Feature Input asks for the link to be visible on **all** platforms that use
the Flutter login screen, without any change to its interaction beyond
restoring visibility.

The comment block immediately above the const still reads:

> Temporarily disabled: anonymous demo sessions leave orphaned auth.users/
> public.users rows with no cleanup job, and anonymous sign-in has no
> visible bot/rate-limit protection (see incident review, 2026-09-08).
> Flip back to true once the account-cleanup job ships.

That comment is stale on two counts: (a) the const was already partially
re-enabled in PR #271 to `!kIsWeb` (native visible, web hidden) while the
comment was left verbatim; and (b) the cleanup and capacity-hardening work the
comment gated on has since shipped in
[supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql](supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql),
[supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql),
and [supabase/migrations/20260912130000_demo_session_capacity_hardening.sql](supabase/migrations/20260912130000_demo_session_capacity_hardening.sql).

## Root Cause

**Confidence: HIGH.** Directly confirmed from the file — a single boolean
gate at [lib/features/auth/login_screen.dart:53](lib/features/auth/login_screen.dart#L53)
is the sole visibility switch. Its only consumer is one `if` at
[lib/features/auth/login_screen.dart:544](lib/features/auth/login_screen.dart#L544)
wrapping the `_buildDemoButton()` call inside `_buildContentCluster`. Setting
the const to `true` restores the link on the web target without altering any
other code path.

The link's own behavior is entirely defined by `_buildDemoButton` and
`_enterDemo` (which calls `DemoSessionService.provisionAndEnter(ref)`) — none
of which change under this fix.

## Existing System Analysis

Prior work that established the contract this fix modifies:

- **PR #271** (docs recorded under `docs/features/bug/demo-button-test-stale-after-271/ARCHITECT_PLAN.md`): flipped `_kDemoBandVisible` from a hard `false` (initial kill switch during `interactive-demo-band-experience`) to `!kIsWeb`, so native builds could exercise the demo path while web stayed hidden pending further mitigations.
- **`bug/demo-button-test-stale-after-271`**: updated Test A in [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart) to match the `!kIsWeb` contract (assertion flipped to `findsOneWidget`, description string references `_kDemoBandVisible = !kIsWeb`).
- **`bug/demo-band-link-spacing`** and **`bug/demo-button-layout-overflow-viewport`**: the surrounding layout scaffolding in `_buildContentCluster` (nudges via `Transform.translate`, `Flexible` wrap around the logo, upper-half `SizedBox`) — none of which are affected by this change since the demo button's rendered position when visible has not moved.

Related current mitigations for the concerns raised in the stale comment:

- **Cleanup**: [supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql](supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql) added `cleanup_expired_demo_sessions()` to also delete the now-unreferenced `auth.users` row on both explicit exit and cron sweep. Combined with the ledger row's `ON DELETE CASCADE` chain from [supabase/migrations/20260904120000_demo_bands_schema.sql](supabase/migrations/20260904120000_demo_bands_schema.sql), orphan rows no longer accrue.
- **Slot reclamation**: [supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql) reduced the sliding TTL to 15 minutes; [supabase/migrations/20260912130000_demo_session_capacity_hardening.sql](supabase/migrations/20260912130000_demo_session_capacity_hardening.sql) further shortened it to 8 minutes and tightened the cron sweep to every 2 minutes.
- **Capacity ceiling**: [supabase/migrations/20260912130000_demo_session_capacity_hardening.sql](supabase/migrations/20260912130000_demo_session_capacity_hardening.sql) added a transaction-scoped `pg_advisory_xact_lock(8675309001)` around the count-then-insert admission window, so the 30-concurrent-session hard cap holds under concurrent visitors.
- **App-level per-IP throttle**: not present. Rate-limit protection for anonymous sign-in is whatever Supabase provides at the auth-layer level. See Regression Risk.

Call site of `_kDemoBandVisible` — the only one — is inside `_buildContentCluster` and is orthogonal to every other login-screen widget (logo, email field, domain pills, login button, message):

```dart
// === DEMO BUTTON — grouped with the login form ===
if (_kDemoBandVisible) ...[
  Transform.translate(
    // Cycle 3: nudge demo link up 65px per owner instruction.
    offset: const Offset(0, -65),
    child: _buildDemoButton(),
  ),
  const SizedBox(height: 12),
],
```

Test file [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart) contains three cases:

- **Test A** asserts `findsOneWidget` for `'Check out the demo band'` on the Dart VM (`kIsWeb == false`). Its description string and the inline comment above the assertion explicitly reference the `!kIsWeb` contract. The assertion continues to pass after the fix (`_kDemoBandVisible = true` also emits the button); the description string and inline comment become stale doc-drift.
- **Test B** asserts the retired easter-egg hint text is absent. Unaffected.
- **Test C** asserts no `RenderFlex` overflow at 800×600 with the button visible. Unaffected — the harness already exercises the `_kDemoBandVisible == true` path.

## Proposed Solution

Flip the single visibility gate from `!kIsWeb` to `true` and replace the stale
kill-switch comment above it with a short line reflecting the current contract
(link is publicly visible on every platform; capacity is bounded by the
30-slot / 8-min-TTL / 2-min-sweep envelope shipped in migration
20260912130000). Keep the `_kDemoBandVisible` const in place rather than
inlining `true` at the call site — it costs one line and preserves a
single-point-of-change if visibility ever needs to be toggled again for
incident response.

Refresh Test A's description string and inline comment in
[test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart)
to describe the new `_kDemoBandVisible = true` contract (the assertion itself
does not change — it already checks `findsOneWidget`). Tests B and C are
untouched.

Record the decision in [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md)
so the previously-recorded native-only demo entry (see the "Never resume an
anonymous/demo session across a relaunch" entry there) is not read as still
authoritative on platform scope. The new entry must also explicitly note that
the pre-init anonymous-session purge in [lib/main.dart](lib/main.dart#L64-L65)
remains native-only under this change (per the Feature Input's
"do not change the link's behavior beyond restoring its visibility" constraint)
— see Out of Scope.

## Database Impact

Not applicable. No migrations, no RLS/RPC changes, no trigger changes, no
Edge Function changes.

## Flutter Architecture Changes

None. No new provider, controller, notifier, repository, service, model, or
router entry. No new dependency. No init-order change. No animation
controller, cooldown timer, session-detection, or magic-link handler is
touched. The only structural touch is one boolean literal + the comment
above it.

## Files to Create

None.

## Files to Modify

| File | Change |
| --- | --- |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) | (1) Replace the 5-line "Temporarily disabled …" comment block at lines 47–52 with a 1–2 line comment stating that the link is publicly visible on every platform and pointing at the capacity envelope (migration 20260912130000). (2) At line 53, change `const bool _kDemoBandVisible = !kIsWeb;` to `const bool _kDemoBandVisible = true;`. Do not remove the const, do not inline the value at the call site, do not touch the `if (_kDemoBandVisible)` gate at line 544, do not touch `_buildDemoButton`, `_enterDemo`, or any other widget. |
| [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart) | Test A only: (1) rewrite the description string at lines 36–39 to describe the new `_kDemoBandVisible = true` contract (visible on every platform); (2) update the inline comment above the assertion at line 55 to state that the button is emitted on every target. **The assertion `expect(find.text('Check out the demo band'), findsOneWidget)` at line 56 does not change.** Test B, Test C, imports, `setUpAll`, and the file-level header comment stay byte-for-byte identical. |
| [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) | Append a new decision entry (dated 2026-09-13) recording that (a) the login-screen demo entry point is now visible on all platforms, superseding the "native-only" scoping from the prior "Never resume an anonymous/demo session across a relaunch" entry; (b) the pre-init anonymous-session purge in [lib/main.dart](lib/main.dart#L64-L65) intentionally remains native-only under this change, per the Feature Input's "do not change the link's behavior beyond restoring its visibility" constraint (see Out of Scope); (c) the security tradeoff the stale comment flagged — capacity is bounded by the 30-slot ceiling + 8-min TTL + 2-min cron sweep from migration 20260912130000 + Supabase's own auth-layer rate limiting; no app-level per-IP throttle is added under this change. Reference the Feature Input by slug (`feature/unhide-demo-band-link`). |

## Files Off-Limits

| File | Reason |
| --- | --- |
| [lib/main.dart](lib/main.dart) | The pre-init anonymous-session purge at [lib/main.dart](lib/main.dart#L64-L65) is currently gated `if (!kIsWeb)`. Widening it to web would be a behavior change to the "always start clean at the login screen on relaunch" invariant recorded in AI_DECISIONS — Feature Input scope is visibility only. Any change here is a separate feature (see Out of Scope). |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) | The link's interaction — `provisionAndEnter`, `exit`, `heartbeat`, `releaseSlotOnDetach`, both pure predicates, and `purgePersistedAnonymousSession` — is not being changed. Feature Input: "Do not change the link's behavior beyond restoring its visibility." |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart), [lib/features/auth/auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart), [lib/features/auth/splash_screen.dart](lib/features/auth/splash_screen.dart), [lib/features/auth/splash_complete_provider.dart](lib/features/auth/splash_complete_provider.dart), [lib/features/auth/auth_state_provider.dart](lib/features/auth/auth_state_provider.dart), [lib/features/auth/invite_screen.dart](lib/features/auth/invite_screen.dart) | Not affected by a paint-only visibility flip on the login screen. |
| `lib/features/auth/login_screen.dart` — all methods except the two touch points | `_checkExistingSession`, `_initAnimations`, `_initLogoShrinkAnimation`, `_initHintController`, `_enterDemo`, `_sendMagicLink`, `_handleSubmit`, `_startCooldownTimer`, `_applyDomainShortcut`, `build`, `_buildContentCluster`, `_buildLogo`, `_buildEmailField`, `_buildDomainPills`, `_buildLoginButton`, `_buildDemoButton`, `_buildMessage`, `dispose`, and both animation-controller init blocks are untouched. The `if (_kDemoBandVisible)` gate at line 544 is preserved verbatim. |
| `supabase/**`, `database/**`, `supabase/functions/**`, `supabase/migrations/**` | Not a data / RLS / RPC / Edge Function issue. |
| `pubspec.yaml`, `dart_defines.json`, `analysis_options.yaml`, `tools/**`, `scripts/**`, platform runners (`ios/**`, `macos/**`, `android/**`, `web/**`, `linux/**`, `windows/**`) | No dependency, dart-define, analyzer, tooling, or platform-runner change. |
| All other tests under `test/**` besides Test A in `login_screen_demo_button_test.dart` | Not asserting `_kDemoBandVisible` behavior. |

## Change Budget

| Metric | Expected |
| --- | --- |
| Net line delta, `lib/features/auth/login_screen.dart` | −3 to −5 (delete 5-line stale comment; add 1–2-line replacement; single-token value flip) |
| Net line delta, `test/features/auth/login_screen_demo_button_test.dart` | 0 to +1 (in-place description + inline-comment refresh; assertion unchanged) |
| Net line delta, `docs/reference/general/AI_DECISIONS.md` | +12 to +25 (single new decision entry) |
| New files | 0 |
| New public classes / methods / providers / notifiers / repositories | 0 |
| New dependencies (`pubspec.yaml`) | 0 |
| New migrations | 0 |
| New Edge Functions | 0 |

## System Impact Map

| Subsystem | Status | Notes |
| --- | --- | --- |
| Gigs | unaffected | No touchpoint. |
| Rehearsals | unaffected | No touchpoint. |
| Setlists | unaffected | No touchpoint. |
| Members | unaffected | No touchpoint. |
| Auth (native) | unaffected | Login screen renders identically on iOS / Android / macOS (`_kDemoBandVisible` was already `true` on native; still `true` after the fix). |
| Auth (web) | **affected** | The `_buildDemoButton()` widget is now emitted on web. Tapping it activates the existing `DemoSessionService.provisionAndEnter(ref)` path on web (Supabase anonymous sign-in + `provision_demo_session` RPC) — previously never exercised in production on web. |
| Login screen layout | unaffected on native | Byte-identical to today (the widget it emits is the same one native already renders). |
| Login screen layout | **affected** on web | The demo button + trailing 12px `SizedBox` are now inserted between the logo half-height `SizedBox` and the email field, per the existing `_buildContentCluster` contract. All existing layout scaffolding (`Transform.translate` nudges, `Flexible` logo wrap, upper-half `SizedBox`) already accommodates this — Test C already asserts no `RenderFlex` overflow at 800×600 with the button present. |
| Demo lifecycle (provision / exit / heartbeat / capacity ceiling / cron sweep / anonymous auth cleanup) | unaffected | All backend and service-layer behavior unchanged. |
| App init order | unaffected | No change to `main.dart`. Pre-init anonymous-session purge remains native-only. |
| Routing / deep links / notifications | unaffected | No touchpoint. |
| Platforms (iOS / Android / macOS) | unaffected | See "Auth (native)" and "Login screen layout" above. |
| Platform (web) | affected — see Regression Risk | |
| Documentation | affected | `AI_DECISIONS.md` entry noted above. |

## Regression Risk

**MEDIUM.**

Native (iOS / Android / macOS): the render tree, animation timings, layout
scaffolding, and every user-facing behavior on the login screen are
byte-identical to today. Regression risk on native is **NEGLIGIBLE**.

Web: a code path that was previously gated off in production is now
activated. The path itself
(`DemoSessionService.provisionAndEnter → signInAnonymously → provision_demo_session`)
is well-exercised on native and covered by
[test/features/auth/demo_lifecycle_predicate_test.dart](test/features/auth/demo_lifecycle_predicate_test.dart)
and [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart);
the RPC and its capacity ceiling are covered by the migration's own SQL
test-harness. But the platform-level behavior on web has never carried real
traffic, and three risk vectors deserve explicit call-out:

1. **Bot / rate-limit exposure.** The stale kill-switch comment specifically
   flagged that anonymous sign-in has no visible app-level bot/rate-limit
   protection. The capacity ceiling at migration 20260912130000 caps the blast
   radius at 30 concurrent sessions (with an 8-minute TTL and 2-minute cron
   sweep), and Supabase applies its own auth-layer rate limiting to anonymous
   sign-in, but there is no per-IP throttle in app code. Web is a lower-friction
   spam surface than native (no app-install step). This is the accepted tradeoff
   under the Feature Input; record it in AI_DECISIONS per the Files to Modify
   table so future readers do not treat it as an unnoticed regression.

2. **Cross-relaunch anonymous session on web.** The pre-init anonymous-session
   purge in [lib/main.dart](lib/main.dart#L64-L65) is currently
   `if (!kIsWeb)`, matching a code path that had never activated on web. This
   change does not touch that guard, so a web visitor who provisions a demo and
   then reloads the browser tab (or reopens it) will land back in the demo
   session for as long as its 8-minute TTL has not expired — different from the
   native contract recorded in the AI_DECISIONS entry "Never resume an
   anonymous/demo session across a relaunch". This is explicitly out of scope
   per the Feature Input's "do not change the link's behavior beyond restoring
   its visibility" constraint. If this behavior is unwanted on web, it is a
   separate feature (see Out of Scope).

3. **Test A description drift.** If Test A's description string is left
   pointing at `_kDemoBandVisible = !kIsWeb` while the shipped const is `true`,
   we recreate the exact class of drift that
   `bug/demo-button-test-stale-after-271` was filed to fix. The plan mandates
   updating the description and inline comment in the same PR to prevent that.

Auth flow, session persistence for real users, magic-link redirect, deep-link
handling, RLS, demo-session lifecycle, and every non-login-screen surface are
unchanged.

## Engineer Task Breakdown

Execute in order. Each task is atomic and can be verified statically.

1. In [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart), replace the 5-line comment block at lines 47–52 (currently starting `// Temporarily disabled: anonymous demo sessions leave orphaned auth.users/`) with a short 1–2-line comment that states the link is publicly visible on all platforms and points at the capacity envelope. Example wording (Engineer may pick equivalent wording; keep it tight):
   ```dart
   // Publicly visible on every platform. Demo capacity is bounded by the
   // 30-concurrent-session ceiling + 8-min TTL + 2-min cron sweep from
   // migration 20260912130000_demo_session_capacity_hardening.sql.
   ```
2. In the same file at line 53, change `const bool _kDemoBandVisible = !kIsWeb;` to `const bool _kDemoBandVisible = true;`. Do not remove the const. Do not inline `true` at the `if (_kDemoBandVisible)` call site at line 544. Do not touch any other line in this file. In particular, `_buildDemoButton`, `_enterDemo`, `_buildContentCluster`'s layout, and the `Transform.translate` nudges are all untouched.
3. In [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart), rewrite Test A's `testWidgets` description string at lines 36–39 to state that the button is visible on every platform (referencing `_kDemoBandVisible = true` — see `login_screen.dart`). Suggested wording (Engineer may pick equivalent wording):
   ```dart
   'Test A: "Check out the demo band" button is visible on LoginScreen on '
   'every platform (_kDemoBandVisible = true — see login_screen.dart).'
   ```
4. In the same file, replace the inline comment above the assertion at line 55 (currently `// Dart VM target: kIsWeb == false → _kDemoBandVisible == true → button is emitted.`) with:
   ```dart
   // _kDemoBandVisible == true on every target → button is emitted.
   ```
   The assertion at line 56 (`expect(find.text('Check out the demo band'), findsOneWidget);`) does **not** change. Test B, Test C, `setUpAll`, imports, and the file-level header comment do **not** change.
5. In [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md), append a new dated entry (2026-09-13) titled along the lines of "Login-screen demo entry point visible on all platforms." The entry must cover: (a) the visibility change (`_kDemoBandVisible = true`); (b) that it supersedes the "native-only" scoping asserted in the earlier "Never resume an anonymous/demo session across a relaunch" entry — but only for the visibility question; the pre-init anonymous-session purge in [lib/main.dart](lib/main.dart#L64-L65) intentionally stays gated `if (!kIsWeb)` under this change, per the Feature Input's "do not change the link's behavior beyond restoring its visibility" constraint (see this plan's Out of Scope); (c) the security tradeoff — capacity bounded by the 30-slot ceiling + 8-min TTL + 2-min cron sweep from migration 20260912130000, plus Supabase auth-layer rate limiting; no app-level per-IP throttle added under this change; (d) reference the feature slug `feature/unhide-demo-band-link`. Keep the entry proportional (a decision entry, not an essay).

## Verification Plan

QA cannot launch, build, or drive a running instance of the app. All
runtime checks are owner-run.

### Tier 1 — QA static / harness gates (mandatory before APPROVED)

1. `flutter analyze` — clean, no new warnings or errors.
2. `flutter test test/features/auth/login_screen_demo_button_test.dart` — all three tests pass. Test A's assertion `findsOneWidget` still holds (`_kDemoBandVisible = true` also emits the button on the Dart VM); Test B and Test C are unaffected.
3. `flutter test` — full suite clean. In particular, `test/features/auth/demo_lifecycle_predicate_test.dart` and `test/features/auth/auth_gate_anonymous_recovery_test.dart` must remain green (they exercise the demo-lifecycle predicates and the anonymous-recovery path, neither of which this fix touches).
4. Static diff review:
   - Confirm `const bool _kDemoBandVisible = true;` is present in [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) and the token `!kIsWeb` no longer appears on the same line.
   - Confirm the `if (_kDemoBandVisible)` gate at the call site is unchanged.
   - Confirm the file's other kIsWeb usages (the platform branch inside `_sendMagicLink` for redirect URL) are untouched.
   - Confirm Test A's description string and inline comment reference `_kDemoBandVisible = true` (no lingering `!kIsWeb` reference); the assertion is unchanged.
   - Confirm `docs/reference/general/AI_DECISIONS.md` has one new dated entry covering the four points enumerated in Task 5.
   - Confirm the diff touches only the three files listed in Files to Modify — no changes to `lib/main.dart`, `lib/features/auth/demo_session_service.dart`, any other `lib/features/auth/**` file, any migration, any Edge Function, any config file, `pubspec.yaml`, `analysis_options.yaml`, or any platform runner.

### Tier 2 — Owner-run smoke checks (Tony runs at PR-test / apply / release time)

Hand this exact punch list to Tony verbatim.

1. Run `./run.sh macos`. **Expected:** login screen renders "Check out the demo band" text button between the logo cluster and the email field, in the same position it renders today on native (no visual regression). Tap it — the demo experience provisions as it does today.
2. Run `flutter run -d ios` (or launch the current TestFlight/dev build on iPhone). **Expected:** identical to macOS above — no visual regression on iOS.
3. Run `flutter run -d chrome` (or open the current dev deploy in Chrome / Safari / Firefox). **Expected:** login screen renders "Check out the demo band" text button (previously hidden on web). Position and styling should match the native rendering (upper-half logo box, then demo button, then email field, then domain pills, then login button). Tap the button — demo provisioning should succeed and route to the cloned Banana Stand band, matching the native flow.
4. On the same Chrome session, still inside the demo band, refresh the browser tab. **Expected (documented, not a defect for this fix):** the anonymous session persists and the app re-enters the demo band; it does **not** return to the login screen. This differs from the native cold-start contract recorded in AI_DECISIONS ("Never resume an anonymous/demo session across a relaunch"). If this is unwanted on web, file a follow-up feature to extend the [lib/main.dart](lib/main.dart#L64-L65) pre-init purge to web — that work is explicitly out of scope for this feature (see Out of Scope).
5. On Chrome, provision a demo, tap "Exit Demo" from wherever it lives in the shell, and confirm you land on the login screen. **Expected:** identical to native exit behavior.
6. Optional load check (only if Tony wants signal on the web-spam surface flagged in Regression Risk item 1): from a fresh Chrome incognito window, tap the demo button ~5 times over a minute. **Expected:** either the first tap succeeds and subsequent taps reuse the same anonymous session (RPC is idempotent per `provision_demo_session()`'s `demo_sessions` unique-key on `auth_user_id`), or Supabase's own auth-layer rate limiting rejects — either is acceptable. If successive taps each mint a distinct anonymous user _and_ each get through the 30-slot ceiling, that is a signal to add app-level per-IP throttling as a follow-up.

## QA Regression Areas

- Login screen render on iOS / Android / macOS: byte-identical to today (no regression expected).
- Login screen render on web: demo button now appears; no other login-screen widget shifts (Test C's overflow assertion at 800×600 already exercises the `_kDemoBandVisible == true` layout).
- Test A assertion (`findsOneWidget` for demo button on Dart VM): still passes.
- Real-user magic-link flow: untouched (no change to `_sendMagicLink`, cooldown timer, `_checkExistingSession`, or any redirect URL).
- Demo lifecycle on native (provision / exit / heartbeat / cross-relaunch purge in `main.dart`): unchanged; native init still runs the `!kIsWeb`-gated purge exactly as today.
- Anonymous auth on web: newly reachable via the login-screen link; RPC and capacity ceiling are unchanged from the versions already exercised on native.

## Rollout Strategy

Standard PR → owner-run Tier 2 checklist → merge to `main` → auto-deploy via
existing pipelines. No feature flag, no phased rollout, no staged rollback
mechanism required (the fix is a single boolean literal — reverting the same
PR is the rollback).

If Regression Risk item 1 (bot/rate-limit exposure on web) manifests in
production, revert the PR (single-token flip back to `!kIsWeb`) as an
immediate mitigation while adding an app-level throttle in a follow-up. The
30-slot ceiling + 8-min TTL + Supabase auth-layer rate limits are the
between-the-revert-and-follow-up backstop.

## Out of Scope

- **Extending the pre-init anonymous-session purge at [lib/main.dart](lib/main.dart#L64-L65) to web.** The current `if (!kIsWeb)` guard was justified by the earlier fact that the demo entry never ran on web. This feature changes that fact, but the Feature Input explicitly says "do not change the link's behavior beyond restoring its visibility." Web visitors who refresh mid-demo will therefore resume the demo instead of landing on the login screen (see Regression Risk item 2). If this behavior is unwanted, it is a follow-up feature.
- **App-level per-IP or per-fingerprint rate limiting for anonymous demo sign-in.** Not present today; not added under this fix. See Regression Risk item 1 and the AI_DECISIONS entry Task 5 mandates.
- **Removing the `_kDemoBandVisible` const** and inlining `true` at the sole call site. Would be a mechanical cleanup but touches more lines and removes a single-point-of-change for future incident response. Deferred.
- **Any change to `_buildDemoButton`, `_enterDemo`, `DemoSessionService`, `provision_demo_session()` RPC, `exit-demo-session` Edge Function, `demo_sessions` schema, TTL, cron sweep, capacity ceiling, or advisory lock.**
- **Any layout / spacing change** — the demo button's position, size, animation, `Transform.translate` nudges, and surrounding scaffolding are preserved verbatim.
- **Revisiting the earlier AI_DECISIONS entry "Never resume an anonymous/demo session across a relaunch"** beyond the note in Task 5 recording that its "native-only" scoping is now historical for the visibility question only. The pre-init purge itself remains native-only under this change.
