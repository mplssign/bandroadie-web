# QA REPORT

## Feature Slug

`member-invitations-after-phone-change`

## Feature Title

Member invitations fail after a band member changes phone number

## Cycle Number

6

## Final Verdict

APPROVED

> Report-provenance note: the file previously at this path was the **Cycle 5**
> report (verdict REQUIRES CHANGES — the single `unused_catch_clause` analyzer
> blocker). Cycle 5 (5) is a lower cycle number than this pass (6), its verdict
> was REQUIRES CHANGES (not an APPROVED to preserve), and no Cycle 6 report
> existed on disk, so replacing it here is correct and is **not** overwriting a
> same-or-higher-cycle / duplicate-session artifact. The Manager holds
> `pipeline.lock`; QA did not acquire, modify, or remove it.

## Validation Summary

Independent QA **Cycle 6** of the first-link fix on
`bug/member-invitations-after-phone-change`. Branch and slugs verified: branch is
`bug/member-invitations-after-phone-change`; `ARCHITECT_PLAN.md` (Cycle 5, final
twice-reviewed), `ENGINEER_REPORT.md` (Cycle 6) and this report all carry the same slug.
The uncommitted working tree is the expected state (Engineer implementation not yet
committed — correct at this stage; nothing is committed until Manager's Release step).

Cycle 5 returned REQUIRES CHANGES for exactly one Critical `[implementation-gap]`: a
diff-added `unused_catch_clause` **warning** in
[lib/features/auth/invite_screen.dart](lib/features/auth/invite_screen.dart) —
`on FunctionsFetchException catch (e)` no longer referenced `e` after the debug cleanup.
Engineer Cycle 6 changed **only** that clause to `on FunctionsFetchException` (no
binding), leaving all other implementation, tests, server behavior, and off-limits files
untouched.

**The Cycle 5 blocker is independently confirmed resolved and no new issue was
introduced.** `flutter analyze` on all five touched Dart files is now empty at every
severity; the exact `unused_catch_clause` finding is gone; `deno check` + `deno test`
(13), the three focused suites (11), and the full `flutter test` (321) all pass; and the
scope, diff-safety, budget, and efficiency reviews are clean. Every substantive axis
already validated in Cycle 5 — the server token/no-token contract, the typed client
recovery matrix, the single auth-confirm navigation authority, security, and
DB-safety-n/a — is re-confirmed unchanged this cycle. **Verdict: APPROVED.**

All verification below is **independently rerun against the current final tree** (not
taken from the Engineer report) and is **code-path analysis + headless test execution**;
no live/on-device app or backend was launched. The runtime/on-device checks remain Tony's
owner-run punch list (below), including the edge-function deploy and the production
redirect allow-list confirmation, which QA did **not** execute.

## Architect Scope Review

- Tracked files changed (`git status`, `git diff --numstat HEAD`) are exactly the
  plan-approved targets plus feature docs:
  [lib/features/auth/auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart)
  (+22/−23), [lib/features/auth/invite_screen.dart](lib/features/auth/invite_screen.dart)
  (+138/−20), [lib/main.dart](lib/main.dart) (+2/−0),
  [supabase/functions/accept-invite/index.ts](supabase/functions/accept-invite/index.ts)
  (+48/−13), plus `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, and this `QA_REPORT.md`.
- Untracked new files are the three plan-listed creations plus the revised (still
  untracked from Cycle 3) auth-confirm test:
  `supabase/functions/accept-invite/invite_result.ts`,
  `supabase/functions/accept-invite/index.test.ts`,
  `test/features/auth/invite_screen_test.dart`,
  `test/features/auth/auth_confirm_screen_test.dart`.
- Off-limits confirmed untouched (`git status --porcelain` on those exact paths returned
  empty): `members_tab_content.dart` + test (Cycle 1, preserved), `auth_gate.dart`,
  `login_screen.dart`, `send-band-invite`, `supabase/migrations/**`,
  `pubspec.yaml`/`pubspec.lock`. **Zero dependency change.** `main.dart` carries only the
  retained Cycle 3 `invite_token` pass-through, as the plan directs.
- **Cycle 6 delta (the only source change since Cycle 5):** a one-line catch-clause edit
  in `invite_screen.dart` — `on FunctionsFetchException catch (e)` →
  `on FunctionsFetchException` (drop the unused binding). Confirmed in the diff; no other
  source/test/config line changed. No unapproved architectural changes; no chat code; no
  DB/RPC/schema change.

## Completeness Check

All eight Architect tasks remain implemented (re-verified in the current diff), and the
Cycle 5 completeness gap — the analyzer warning on task 5's output — is now **closed**:

1. Off-limits files preserved (verified above). ✓
2. `invite_result.ts` created with pure `classifyTokenInvite` + `tokenInviteResponse`,
   no remote imports. ✓
3. `index.ts` token branch rewired: queries by **token alone**
   (`select id, band_id, email, status, expires_at, bands(name)`, `.maybeSingle()`),
   classifies, calls `accept_band_invite` **only** on `eligible`, returns
   `tokenInviteResponse(...)`; the token branch **always returns early** so a provided
   token never reaches the sweep; the sweep guard is `if (!inviteToken)` with its body and
   aggregate `200` semantically unchanged. ✓
4. `index.test.ts` created; every classifier + response bucket covered (13 Deno tests). ✓
5. `_acceptInvite` reworked to the status-driven recovery matrix with
   `_handleAcceptHttpError` / `_safeLocalSignOut` / `_asMap` / `_errorCode` /
   `_errorMessage`, the `200` accepted-band guard, and typed `FunctionsHttpException` /
   `FunctionsFetchException` catches; `_sendMagicLink` redirect updated to
   `/auth/confirm?invite_token=`. The Cycle 6 fix removes the now-unused `e` binding on
   the `FunctionsFetchException` catch without changing its behavior. ✓
6. `auth_confirm_screen.dart` navigation consolidated through `_navigateToHome()`
   (web `/`→`/app`), `_handleConfirm` terminal block routed through it with the trailing
   `_loading=false` setState removed, loop `mounted` guard added. ✓
7. `invite_screen_test.dart` created (7 first-link cases). ✓
8. `auth_confirm_screen_test.dart` updated to a `NavigatorObserver` push-count
   measurement. ✓

No partial implementations; no missing edge cases the plan specified.

## Behavior Verification

Method: **code-path analysis + headless tests** (no live app). The Cycle 6 change is
**behavior-preserving**: removing the unused `e` binding from `on FunctionsFetchException`
does not alter the branch — it still catches the network exception and sets the
network-specific retry message ("Network error. Check your connection and try again.")
without signing out. Confirmed in code and by the passing `invite_screen_test` network
case. All plan-owned behavior re-confirmed against the current tree:

- **Tony's literal first-link path (causal first link).** The failing chain
  (stale/persisted `currentSession` → immediate `_acceptInvite` → `functions.invoke`
  non-2xx → `functions_client` **throws** `FunctionsHttpException`) is intercepted by the
  new `on FunctionsHttpException` catch → `_handleAcceptHttpError`, which branches on
  `error.status` (401/403/409) with best-effort `code` refinement. The generic
  `Something went wrong. Please try again.` dead-end is no longer reachable for these
  statuses — the `invite_screen_test` 401/403/409/502/network cases each assert that
  string is **absent**. ✓
- **401 recovery cannot immediately re-enter/loop.** On 401, `_safeLocalSignOut`
  (`SignOutScope.local`) clears the session, `_hasTriedAccept=false`, `_needsAuth=true`
  shows auth UI. With the local session cleared, AuthConfirm/InviteScreen can no longer
  short-circuit on a stale `currentSession`, so the accept attempt cannot immediately
  re-enter. The 401 test asserts `currentSession == null` after handling. ✓
- **Server token/no-token separation & typed contract** (`invite_result.ts` + `index.ts`,
  deno-tested): query by token; `classifyTokenInvite` → `email_mismatch` (403, generic
  body, **no target email / no PII**); `consumed`/`ineligible`/`expired`/`not_found`
  collapse to a single neutral `409 invite_unavailable`; `eligible` → RPC → `200` with
  `accepted_band_id`/`band_names`; RPC failure → `502 accept_failed`. `accept_band_invite`
  runs **only** on `eligible` (email verified) — the prior cross-account / email-wide
  sweep on a provided token is eliminated (net security improvement). Idempotency: an
  already-accepted token → `consumed` → `409`, no RPC. The `!inviteToken` sweep (called by
  AuthGate with `body:{}`) is semantically unchanged; `auth_gate.dart` is untouched. ✓
- **Typed client recovery / no false success.** `200` is treated as accepted only when
  `success == true` **and** an accepted band is present (`accepted_band_id != null ||
  band_names` non-empty); otherwise it falls to auth-UI recovery, never a false "Invite
  accepted!". `_safeLocalSignOut` swallows sign-out failure; all `setState` after `await`
  are `mounted`-guarded. ✓
- **Single auth-confirm navigation.** `_navigateToHome()` is the sole navigator (guarded
  by `_navigating`); all three `Navigator.push*` calls live inside it (invite →
  `InviteScreen(token:)`, web → `/app`, native → `AuthGate`). `_handleConfirm` and the
  `onAuthStateChange` listener both route through it, so a double-push is impossible; the
  loop `mounted` guard prevents `ref`-after-disposal. ✓
- **No chat.** Confirmed out of scope; no group-chat code appears anywhere in the diff. ✓

### `NavigatorObserver` double-push detection (re-confirmed)

`_RecordingNavigatorObserver` increments on both `didPush` **and** `didReplace`, is
attached to the same inner Navigator that receives every pushed page, and Tests A/B assert
an **absolute** `transitionCount == 2` (initial mount page + one post-auth navigation). A
double-push regresses the count to `3` and fails — this genuinely replaces the prior
`findsOneWidget`-only guard. This test is unchanged since Cycle 5 and still passes.

### Test integrity (re-confirmed)

The new tests contain no `skip:`, `solo`, `markTestSkipped`, or no-op (`expect(true …)`)
assertions (grepped). Priming uses `recoverSession(jsonStr)` (offline), `MockClient`
returns non-2xx **plain-text** bodies so `functions_client` decodes synchronously and the
status genuinely raises `FunctionsHttpException` / `FunctionsFetchException`; recovery is
asserted on `e.status`. `_drainKnownRenderOverflow` only drains known pre-existing layout
overflows / the off-limits `[AuthGate] Error checking profile` null-check — every
plan-owned behavior is gated by a strong positive assertion, so a real logic defect would
fail an assertion rather than be silently drained.

## Regression Check

Against the plan's System Impact Map. Overall regression risk **MEDIUM** (auth/invite
acceptance + auth-confirm navigation); no critical regression found in code or tests. The
Cycle 6 one-line edit is the narrowest possible change and touches only the
network-error branch's variable binding.

- **Auth / invite acceptance (affected):** first-link recovery matrix additive around the
  existing accept flow; success path shape unchanged. Risk **MEDIUM**, covered by 7 new
  headless cases.
- **Routing / auth-confirm (affected):** single navigation authority; web non-invite lands
  deterministically at `/app` (production-proven URL). Test B asserts non-invite →
  `AuthGate`, single push. Risk **LOW–MEDIUM**.
- **Supabase RPC signature / order:** `accept_band_invite(p_invite_id, p_user_id)`
  unchanged; still `SECURITY DEFINER`; called on `eligible` only. Risk **LOW**.
- **Init order / Firebase / DeepLinkService / URL strategy:** untouched. Risk **LOW**.
- **Platform parity:** change is on the shared web invite-acceptance surface + shared
  auth-confirm nav; native `bandroadie://login-callback/` and web PKCE unchanged. Native
  deep-link is owner-run (punch list). Risk **LOW** (code).
- **Controller/FocusNode disposal, setState-after-async, listener safety:** all new
  `setState` `mounted`-guarded; loop `ref.read` guarded; `_safeLocalSignOut` cannot throw
  into UI. Risk **LOW**.
- **Members-tab (Cycle 1):** preserved, its focused test still green. Risk **LOW**.

Full suite `flutter test` = **321 passed** (independently rerun) — no existing auth or
other tests regressed.

## Database Safety

Not applicable — independently re-confirmed. No `supabase/migrations/**` change, no RLS,
no RPC signature/definition change, no `.sql` file, no new/changed `SECURITY DEFINER`
function. Therefore **no Supabase branch apply-check** and **no `has_function_privilege`
check** were required or performed. The only server change is the `accept-invite` **edge
function** (TypeScript), which `deno check` type-verifies (see Analyzer/Test Results).

## Analyzer Results

Independently rerun against the current final tree (not the Engineer report):

```
flutter analyze lib/features/auth/auth_confirm_screen.dart \
  lib/features/auth/invite_screen.dart lib/main.dart \
  test/features/auth/auth_confirm_screen_test.dart \
  test/features/auth/invite_screen_test.dart
→ Analyzing 5 items...
  No issues found! (ran in 2.6s)    [exit 0]
```

**PASS — empty at every severity.** The exact Cycle 5 blocker
(`unused_catch_clause` in `invite_screen.dart`, `on FunctionsFetchException catch (e)`)
is **gone**: the clause is now `on FunctionsFetchException` with no binding, and the
`_handleAcceptHttpError(e)` call in the still-bound `on FunctionsHttpException catch (e)`
above it keeps that variable in use. `git diff --check HEAD` reports no whitespace
errors. Deno typecheck is clean:
`deno check supabase/functions/accept-invite/{index.test.ts,index.ts}` → exit 0.

## Test Results

All independently rerun against the current final tree:

- `deno test --allow-env supabase/functions/accept-invite/` → **`ok | 13 passed | 0
  failed`** (classifier + response buckets: eligible/200, RPC-fail/502, email_mismatch/
  403, not_found + consumed/ineligible/expired → 409).
- `flutter test test/features/auth/invite_screen_test.dart
  test/features/auth/auth_confirm_screen_test.dart
  test/features/members/members_tab_content_test.dart` → **`+11: All tests passed!`**
  (invite_screen +7: no-session, same-email success, 401, 403, 409, 502, network;
  auth_confirm +2: invite → `InviteScreen(token:)` single push, no-invite → `AuthGate`
  single push; members_tab +2, Cycle 1).
- `flutter test` (full suite) → **`+321: All tests passed!`** — no regressions.

## Diff Safety Review

- **No secrets / API keys** on added lines or in the new files (grepped
  `api_key|secret|password|bearer|service_role|sk_live|eyJ` on `^\+` lines → none). The
  `test-anon-key` / `publishableKey` literals live only in in-test `MockClient` values,
  not credentials; the edge function reads `SUPABASE_SERVICE_ROLE_KEY` from `Deno.env`
  (expected, pre-existing).
- **No `debugPrint`/`TODO`/`FIXME`/`console.log` added** — grep of added (`^\+`) lines
  across `lib/`, `supabase/`, `test/` returned none. The two `debugPrint('[InviteScreen]
  Response status/data …')` lines inside `_acceptInvite`, and the `debugPrint('🚀 …')` /
  `'✅ …'` lines in `auth_confirm_screen.dart`, are **pre-existing context lines** (present
  at `HEAD`, unchanged by this diff) — not introduced this cycle (see Suggestions).
- No leftover test scaffolding, accidental deletions, or unrelated churn beyond the
  cosmetic sweep-body reformatting in `index.ts` noted below.

## Change Budget Review

Independently measured (`git diff --numstat HEAD` for tracked, `wc -l` for new files) vs.
the plan's Change Budget. **All within ~1.5× → noted, no budget-based finding.** The
Cycle 6 delta itself is a single line (net ≈ 0).

| File | Actual | Budget | Ratio | Note |
|---|---|---|---|---|
| `auth_confirm_screen.dart` | +22/−23 (net −1) | −8..+8 | — | within |
| `invite_screen.dart` | +138/−20 (net +118) | +55..+90 | 1.31× | within 1.5× |
| `main.dart` | +2/−0 | 0 (retain) | — | retained Cycle 3 pass-through |
| `index.ts` | +48/−13 (net +35) | +15..+30 | 1.17× | incl. cosmetic sweep churn |
| `invite_result.ts` (new) | 97 | 70..110 | — | within |
| `index.test.ts` (new) | 140 | 90..150 | — | within |
| `invite_screen_test.dart` (new) | 485 | 220..330 | 1.47× | within 1.5× |
| `auth_confirm_screen_test.dart` | 258 (untracked total) | +25..+50 (as a mod) | — | see note |

- New public symbols: exactly the **2** exported TS functions (`classifyTokenInvite`,
  `tokenInviteResponse`; plus supporting `TokenInvite*` type aliases in the same module).
  New dependencies: **0**. New files: **3** creations + the revised (Cycle-3 untracked)
  auth-confirm test — matches plan accounting.
- `auth_confirm_screen_test.dart` was budgeted as a **modification** of an existing
  Cycle-3 untracked file (+25..+50); because that file was never committed, its full 258
  lines show as untracked. Framing mismatch only — not a bloat finding.

## Code Efficiency Review

- Independently grepped `lib/**/*.dart` for a pre-existing reusable local-signout helper:
  none. `auth_gate.dart` uses `SignOutScope.global` inline in a different context.
  `_safeLocalSignOut` has **two** call sites (401, 403) → justified, not a single-use
  wrapper.
- `_handleAcceptHttpError` encapsulates the multi-branch recovery matrix; `_asMap` is
  reused on both the success path and the error handler; `_errorCode`/`_errorMessage` are
  small but real accessors. No AI-shaped single-use `_buildX`, no new provider/notifier for
  one-widget state, no `FutureBuilder` re-fetch, no log-and-rethrow, no unused
  field/param/`copyWith`, no barrel file, no speculative flags/enum cases.
- Server logic is isolated in a pure, unit-tested module (no copy-drift).
- No bloat-level (Critical/Warning) efficiency issue. The Cycle 6 change removes code (an
  unused binding); it adds nothing.

## Manual Verification Punch List (owner-run — Tony)

These require a running app / live backend and are **owner-run**; QA did **not** attempt
them and they are **not** counted against completeness. The edge-function deploy and the
production redirect allow-list confirmation remain **owner-run/manual — NOT executed by
QA.**

1. **(Owner-run/manual — NOT executed by QA)** Deploy the edge function:
   `supabase functions deploy accept-invite`, and ship the web build. **Expected:** deploy
   succeeds; either order is safe (client status/accepted-band guards already degrade an
   old `200/accepted_count:0` to recovery, never a false success).
2. **(Owner-run/manual — NOT executed by QA; not code-verifiable)** Supabase →
   Authentication → URL Configuration: confirm Redirect URLs accept
   `https://app.bandroadie.com/auth/confirm` **with** an `invite_token` query param (add
   `https://app.bandroadie.com/auth/confirm*` if entries are exact-match). **Expected:** an
   invite magic link lands on `/auth/confirm?invite_token=…&code=…`, not the site root. (If
   it falls back, AuthGate's `body:{}` email sweep still accepts after sign-in.)
3. **Reproduce Tony's case (stale session).** In a browser already signed in as one
   account, open a fresh invite link for a **different** email. **Expected:** **no**
   `Something went wrong` dead-end; guided to sign in with the invited email; no false
   "accepted".
4. **Happy path (new invitee).** Members → Add → invite a fresh address → email form →
   request login link → open → through `/auth/confirm` → `You've joined <Band>!` → active
   member. **Expected:** exactly one acceptance, no double redirect.
5. **Same-email already signed in.** Signed in as the invited email, open the invite link.
   **Expected:** immediate acceptance, no error.
6. **Normal web login regression.** Request a non-invite magic link → open. **Expected:**
   lands at `/app` (AuthGate), no InviteScreen interposed.
7. **Mobile regression.** iOS/Android `bandroadie://login-callback/` login unchanged.
8. **Server curl contract (authenticated Bearer).** `body:{token:<foreign-email token>}`
   → `403 email_mismatch`; `body:{token:<consumed token>}` → `409 invite_unavailable`;
   `body:{}` (no token) → email sweep still accepts by email. **Expected:** deployed
   contract matches the unit-tested shape.

## Issues Found

### Critical

None. The single Cycle 5 Critical `[implementation-gap]` (`unused_catch_clause` in
`invite_screen.dart`) is independently confirmed **resolved** — `flutter analyze` on all
five touched Dart files is empty at every severity, and no issue of the same
`[implementation-gap]` category (or any other category) remains. No new Critical/Warning
was introduced by the Cycle 6 edit.

### Warnings

None.

### Suggestions

- **[code-quality]** Two **pre-existing** `debugPrint('[InviteScreen] Response
  status/data …')` lines remain inside the rewritten `_acceptInvite`. They are context
  (not diff-added) so they are not a blocker, but since `Response data` logs the full
  accept-invite payload, consider removing them in a future touch.
- **[code-quality]** `index.ts` contains cosmetic whitespace-only reformatting inside the
  off-path `!inviteToken` sweep body (a split `console.error(...)` and a rejoined
  `bandName` line). Semantically byte-equivalent; trivial to revert if strict minimality
  is desired. Non-blocking.
- **[code-quality]** `_asMap` / `_errorCode` / `_errorMessage` are fine as private
  helpers; no action needed — noted only for completeness of the efficiency review.
