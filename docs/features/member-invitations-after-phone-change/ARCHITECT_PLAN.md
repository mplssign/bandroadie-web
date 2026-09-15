# ARCHITECT PLAN

## Feature Slug

`member-invitations-after-phone-change`

## Feature Title

Member invitations fail after a band member changes phone number

## Problem Summary

Cumulative bug. Cycle 1 committed a Members-tab entry-point fix (`f2c9116`, preserved).
Cycle 3 proposed routing invite-login through `/auth/confirm`; two reviews found it
correct-but-insufficient (it never runs on Tony's literal first-link failure). Cycle 4
diagnosed the true first-link defect. This is **Cycle 5**: the proposed corrected
solution was reviewed twice (Corrected-Solution Reviews A and B), both returning
`CORRECT WITH REQUIRED CHANGES`. This plan folds every controlling refinement in.

Tony's reported failure: an invitee clicked the **original** invite email link and the
browser **immediately** showed InviteScreen's generic `Something went wrong. Please try
again.` with a `Go to App` button — no email-entry form, no second link. The Cycle 3
changes touch only `_sendMagicLink` (runs only with no session) and the `/auth/confirm`
handoff (runs only on a second magic-link return), so they cannot fix the first-link
path. This cycle fixes the first-link path directly (client + server) and hardens the
unauthenticated handoff.

## Root Cause (Confidence: HIGH — confirmed in code + dependency source)

The first-link failure is a **thrown-error handling defect**, not a phone/identity issue.

1. The invite email points at `https://app.bandroadie.com/invite?token=...`
   ([send-band-invite/index.ts](supabase/functions/send-band-invite/index.ts) →
   `APP_URL + /invite?token=`). First click lands on
   [invite_screen.dart](lib/features/auth/invite_screen.dart).
2. `_handleInvite` waits 500 ms then reads `currentSession`
   ([invite_screen.dart](lib/features/auth/invite_screen.dart#L102)). If a **persisted
   stale/expired session** exists, it is non-null → immediate `_acceptInvite(token)`,
   skipping the email form (matches Tony's symptom).
3. `_acceptInvite` calls `functions.invoke('accept-invite', body:{token})`. On a stale
   JWT the function's `supabaseUser.auth.getUser()` fails → **HTTP 401**
   ([accept-invite/index.ts](supabase/functions/accept-invite/index.ts#L60)).
4. `functions_client` **2.7.1** `invoke()` **throws** `FunctionsHttpException(status,
   details, reasonPhrase)` on any non-2xx (confirmed at
   `~/.pub-cache/hosted/pub.dev/functions_client-2.7.1/lib/src/functions_client.dart:265`).
   The dead `if (response.status != 200)` branch at
   [invite_screen.dart](lib/features/auth/invite_screen.dart#L140) is never reached; every
   401/403/409/500/network failure falls into the generic `catch` → `_error = 'Something
   went wrong. Please try again.'` ([invite_screen.dart](lib/features/auth/invite_screen.dart#L223)).
   That is the exact dead-end Tony saw.

Two adjacent confirmed defects on the same path:

- **`accepted_count == 0` false success / over-broad fallback.** On 200,
  `_acceptInvite` treats `success == true` as accepted regardless of whether a band was
  actually joined. On the server,
  [accept-invite/index.ts](supabase/functions/accept-invite/index.ts#L119) falls back to
  the **email-wide sweep** whenever a provided token does not match
  (`if (!inviteToken || invitations.length === 0)`). A valid session under a **different
  email** clicking a targeted token therefore silently accepts that account's *unrelated*
  pending invites (a cross-account accept) or returns `{success:true, accepted_count:0}`
  → the client shows a false "Invite accepted!". This is both a correctness and a
  **security** defect (a provided token must never trigger the email-wide sweep).

- **Per-invite RPC failure is swallowed.** The sweep loop `continue`s past
  `accept_band_invite` RPC errors and still returns `{success:true, accepted_count:0}`
  when **all** RPCs fail — indistinguishable from "nothing to accept."

`functions_client` is pinned to `2.7.1` and `supabase_flutter` re-exports its exception
types (`supabase.dart` → `export 'package:gotrue/gotrue.dart'` plus the functions_client
export), so `FunctionsHttpException`/`FunctionsFetchException`/`SignOutScope` are all
importable through the existing `package:supabase_flutter/supabase_flutter.dart` import
(`SignOutScope` is already used this way in
[auth_gate.dart](lib/features/auth/auth_gate.dart#L11)).

## Existing System Analysis

- **band_invitations statuses** (confirmed): `pending`, `sent`, `accepted`, `declined`,
  `expired`, `error`; columns include `email`, `status`, `token`, `expires_at`,
  `band_id`, `intended_role` (model:
  [band_invitation.dart](lib/app/models/band_invitation.dart#L8); send-band-invite sets
  `sent`/`error`; accept sets `accepted`). `accept_band_invite`
  ([20260717085528_add_intended_role_to_invitations.sql](supabase/migrations/20260717085528_add_intended_role_to_invitations.sql))
  is `SECURITY DEFINER`, locks the row `FOR UPDATE`, returns idempotently for `accepted`,
  and raises for non-`pending/sent` — unchanged this cycle.
- **Cycle 1 (committed `f2c9116`, preserve):** only
  [members_tab_content.dart](lib/features/members/members_tab_content.dart) + its test.
- **Cycle 3 (uncommitted, exact diffs read):**
  - [invite_screen.dart](lib/features/auth/invite_screen.dart): **only** `_sendMagicLink`
    redirect `/invite?token=` → `/auth/confirm?invite_token=`. `_acceptInvite` is
    **unchanged** — fix #1 is entirely new work. The `kPendingInviteTokenKey`
    SharedPreferences write is **pre-existing legacy** (not Cycle 3), so it is out of
    scope, not "stale experimental behavior" to strip.
  - [main.dart](lib/main.dart#L227): `invite_token` query pass-through to
    `AuthConfirmScreen(inviteToken:)`. Correct — retain.
  - [auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart): added
    `inviteToken` field + invite-branch in **both** `_navigateToHome()` (web non-invite →
    `/`) **and** the `_handleConfirm` terminal block (web non-invite → `/app`). This
    created **two navigation authorities** and the double-push bug (below).
  - [auth_confirm_screen_test.dart](test/features/auth/auth_confirm_screen_test.dart)
    (untracked): handoff Tests A/B using a `MockClient`. Uses `findsOneWidget` for the
    single-push assertion — which cannot detect a double push.
- **AuthGate sweep (off-limits, relevant):**
  [auth_gate.dart](lib/features/auth/auth_gate.dart#L333) `_checkAndProcessPendingInvite`
  calls `accept-invite` with `body:{}` (email-based, **no token**), wrapped in try/catch
  that degrades to `loadUserBands()`. It never reads `kPendingInviteTokenKey`. This is the
  graceful net if a redirect param is ever stripped, and its no-token semantics **must
  stay stable**.
- **`PendingInviteHelper.acceptInvite`**
  ([invite_screen.dart](lib/features/auth/invite_screen.dart#L543)) has the same dead
  branch but **no callers** (confirmed) — dead code, leave untouched.
- **Double-push mechanism (fix #4):** on a successful confirm the `onAuthStateChange`
  listener fires `signedIn` → `if (_loading && !_navigating) _navigateToHome()` (pushes
  `InviteScreen`, sets `_navigating`), while `_handleConfirm`'s terminal block pushes
  `InviteScreen` **again** without checking `_navigating`. Two instances, two
  `_acceptInvite` attempts; the second returns `invite_unavailable` (now consumed) and,
  under fix #1, would overwrite the first success. `_handleConfirm` also `ref.read`s
  `authStateProvider` in a loop across `await`s with no per-iteration `mounted` guard →
  ref-after-disposal if the listener already navigated.
- **Normal login redirect** ([login_screen.dart](lib/features/auth/login_screen.dart#L373))
  is plain `/auth/confirm`, proven in production. Local allow-list
  ([config.toml](supabase/config.toml)) lists `/auth/confirm` without a query string;
  production allow-list acceptance of `/auth/confirm` **with** `invite_token` is not
  code-verifiable — owner-run gate (fix #6).
- **Offline auth test pattern (confirmed):**
  [auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart)
  primes a session with `GoTrueClient.recoverSession(jsonStr)` (no network) and drives
  `signOut`/functions via `MockClient`. This is the proven harness to reuse.
- **Deno test feasibility (confirmed):** `deno` is installed and a precedent pure-function
  Deno test exists at
  [getsongbpm_lookup/index.test.ts](supabase/functions/getsongbpm_lookup/index.test.ts)
  (`Deno.test` + `assertEquals`, `deno test --allow-env`).

## Proposed Solution

Fix the first-link path on client and server, define a **precise token-specific
response contract** (no single ambiguous `200/accepted_count:0` bucket), consolidate the
auth-confirm navigation to a single authority, and lock the contract with mechanically
runnable tests.

### 1. Server — token-specific accept contract (fix #1 core + #2 + #3)

Extract the risk-bearing decision + status mapping into a **pure module**
`supabase/functions/accept-invite/invite_result.ts` (imported by both `index.ts` and the
Deno test — single source, no copy-drift), and rewire only the **token branch** of
`index.ts` to use it. The **no-token AuthGate sweep is left exactly as-is.**

`invite_result.ts` exports:

- `classifyTokenInvite(row, authEmail, now)` → discriminated result:
  - `row == null` → `{ kind:'not_found' }`
  - `row.email.toLowerCase() !== authEmail.toLowerCase()` → `{ kind:'email_mismatch' }`
  - `row.status === 'accepted'` → `{ kind:'unavailable', reason:'consumed' }`
  - `row.status ∉ {pending,sent}` (declined/expired/revoked/error) →
    `{ kind:'unavailable', reason:'ineligible' }`
  - `row.expires_at && new Date(row.expires_at) < now` →
    `{ kind:'unavailable', reason:'expired' }`
  - else → `{ kind:'eligible', invite: row }`
- `tokenInviteResponse(classification, { rpcFailed })` → `{ status, body }`:

  | Outcome | HTTP | body.code | Notes |
  |---|---|---|---|
  | eligible + RPC ok | `200` | — | `{ success:true, accepted_count:1, band_names:[name], accepted_band_id, accepted_band_ids:[id] }` |
  | eligible + RPC failed | `502` | `accept_failed` | distinct targeted failure (fix #3) |
  | email_mismatch | `403` | `email_mismatch` | generic text, **never echoes the target email** |
  | not_found / unavailable(any reason) | `409` | `invite_unavailable` | single neutral bucket; not_found and consumed indistinguishable |

  Existing `401` (auth) and `500` (env/fetch error) are unchanged.

`index.ts` token branch becomes IO-only: query by **token alone** (admin client)
selecting `id, band_id, email, status, expires_at, bands(name)` with `.maybeSingle()`;
on query error → `500`; else `classifyTokenInvite(...)`; if `eligible`, call
`accept_band_invite` RPC and set `rpcFailed = !!rpcError`; return
`tokenInviteResponse(...)`. **A provided token never falls through to the email sweep**
(fix #2). The old `if (!inviteToken || invitations.length === 0)` guard becomes
`if (!inviteToken)` because the token branch always returns early; the sweep block + its
aggregate `200` response stay byte-equivalent for the `!inviteToken` path (preserving
AuthGate semantics — the narrow, justified answer to fix #3's sweep clause).

**Security / enumeration (assessed):** the query already used the admin client for the
token lookup; dropping the email filter from the *query* but re-checking email in the
*classifier* means the row is read regardless of email, yet the only email-specific
signal returned is `403 email_mismatch` — with **no PII / no target email in the body**
— and it requires the caller to already hold a **live high-entropy token** for another
address (tokens come from `generate_invite_token()`; not guessable/enumerable).
`not_found` and `unavailable` collapse to an identical `409`, so existence of a consumed
invite is not disclosed. Crucially, `accept_band_invite` is now called **only** on
`eligible` (email matches), eliminating the prior cross-account accept — a net security
improvement. **Idempotency:** an already-accepted token classifies as
`unavailable/consumed` → `409`, RPC not called; concurrent eligible requests are
serialized by the RPC's `FOR UPDATE` + `accepted`→`RETURN`, so identical input yields
identical output.

### 2. Client — `_acceptInvite` recovery matrix (fix #1 + #2)

Replace the dead `status != 200` check and catch-all with **status-driven** typed
handling (status is always set on `FunctionsHttpException`; the JSON `code`/`error` body
is best-effort refinement). Recovery matrix:

| Server result | Client action |
|---|---|
| `401` | `_safeLocalSignOut()` → reset `_hasTriedAccept=false` → `mounted` check → `_needsAuth=true` (auth UI) with "session expired, sign in with your invited email". No generic error. |
| `403` / code `email_mismatch` | `_safeLocalSignOut()` (so AuthConfirmScreen won't short-circuit on the stale `currentSession` and loop) → reset `_hasTriedAccept=false` → auth UI with "This invite was sent to a different email — sign in with that address." |
| `409` / code `invite_unavailable` | **No sign-out.** Neutral terminal message ("This invite is no longer available."). Keeps `Go to App`. |
| `502` / any other non-2xx (incl. `500`) | **No sign-out, no auth UI.** Actionable server-failure/retry message ("We couldn't finish accepting your invite. Please try again."). Never the generic dead-end. |
| `FunctionsFetchException` | Network message ("Network error. Check your connection and try again."). No sign-out. |
| final `catch` | true last-resort generic — now only unexpected client-side errors. |
| `200` | Accepted **only** when `success == true` **and** an accepted band is present (`accepted_band_id` non-empty **or** `band_names` non-empty). Otherwise (defensive; unreachable for the token path under the new contract) → auth-UI recovery, never false "Invite accepted!". |

Private helpers: `_safeLocalSignOut()` wraps
`auth.signOut(scope: SignOutScope.local)` in its own try/catch (guards sign-out failure);
`_asMap(details)` accepts `e.details` as a `Map` **or** a JSON `String` (functions_client
yields a decoded `Map` for `application/json` and a raw `String` otherwise) and returns
`code`/`error`. `SignOutScope.local` is the gotrue **default** (confirmed
`gotrue-2.27.2/lib/src/gotrue_client.dart:1075`); we pass it explicitly for intent and
future-proofing.

**Accepted tradeoff (documented):** a `401` triggers a *local* sign-out even if the
session were still locally valid (e.g. transient auth-service outage or clock skew making
the JWT look expired to the server). This is acceptable because recovery is a single
magic link, the user is already in the accept-invite flow, and *not* signing out would
leave AuthConfirmScreen looping on the stale `currentSession`.

### 3. Auth-confirm — single navigation authority (fix #4)

Make `_navigateToHome()` the **sole** post-auth navigator (it already carries the
`if (_navigating) return; _navigating = true;` guard):

- Change its web-non-invite destination from `/` to **`/app`** to match the
  production-proven canonical destination the current `_handleConfirm` terminal block
  uses. (Both `/` and `/app` route to `AuthGate` on the app host per
  [main.dart](lib/main.dart#L215); `/app` is the proven URL.)
- Replace `_handleConfirm`'s terminal invite/web/native if-else with a single
  `if (!mounted) return; _navigateToHome();`, and drop the now-dead trailing
  `setState(() { _loading = false; })` after it (the screen is being removed).
- Add `if (!mounted) return;` at the top of each iteration of the auth-state-sync
  `while` loop (before `ref.read(authStateProvider)`) to eliminate ref-after-disposal.

Result: exactly one navigation, single-shot via `_navigating`; **normal web login lands
deterministically at `/app`** (equivalent to today and intentional — the listener no
longer races it to `/`); invite-login → one `InviteScreen(token:)`; native → `AuthGate`.
Retain the Cycle 3 `inviteToken` field, `main.dart` pass-through, and `_sendMagicLink`
redirect as-is.

### 4. Retain / revise / off-limits for the uncommitted Cycle 3 tree

- **Retain unchanged:** `main.dart` invite_token pass-through; `_sendMagicLink` redirect
  to `/auth/confirm?invite_token=`; `AuthConfirmScreen.inviteToken` field.
- **Revise:** `_acceptInvite` (new — fix #1/#2); `auth_confirm_screen.dart` navigation
  consolidation (fix #4); `auth_confirm_screen_test.dart` single-push measurement
  (fix #5).
- **No stale experimental behavior remains:** the consolidation removes the divergent
  second navigation authority; no Cycle-3 experimental code other than the retained
  handoff exists. The `kPendingInviteTokenKey` write is pre-existing legacy (not this
  bug's scaffolding) and is left untouched to avoid scope creep.

## Database Impact

Not applicable. No migration, RLS policy, RPC, trigger, or schema change.
`accept_band_invite` (SECURITY DEFINER) is unchanged. No new `SECURITY DEFINER` function,
so no `REVOKE/GRANT` or `has_function_privilege` verification is required. The only server
change is the `accept-invite` **edge function** (TS).

## Flutter Architecture Changes

- No new providers, controllers, repositories, screens, or public Dart classes. New
  **private** helpers only (`_handleAcceptHttpError`, `_safeLocalSignOut`, `_asMap`/
  `_errorCode`/`_errorMessage` in `_InviteScreenState`).
- Init order, Firebase, `DeepLinkService`, URL strategy, platform-conditional wiring:
  untouched. **Platform parity:** the change is on the shared web invite-acceptance
  surface; native login/deep-link (`bandroadie://login-callback/`) and web PKCE flows are
  unchanged. `_sendMagicLink`'s redirect only ever targets the web host, as today.
- **Async/mounted:** every `setState` after an `await` is `mounted`-guarded; the sync
  loop's `ref.read` is now guarded; `_safeLocalSignOut` cannot throw into the UI.

## Files to Create

- `supabase/functions/accept-invite/invite_result.ts` — pure `classifyTokenInvite` +
  `tokenInviteResponse` (exported; imported by `index.ts` and the Deno test).
- `supabase/functions/accept-invite/index.test.ts` — `deno test` coverage of the token
  contract (all buckets + status/code mapping).
- [test/features/auth/invite_screen_test.dart](test/features/auth/invite_screen_test.dart)
  — first-link path coverage (7 cases).

## Files to Modify

- [supabase/functions/accept-invite/index.ts](supabase/functions/accept-invite/index.ts)
  — rewire the token branch to `classifyTokenInvite` + RPC-on-eligible +
  `tokenInviteResponse`; leave the `!inviteToken` sweep + aggregate response unchanged.
- [lib/features/auth/invite_screen.dart](lib/features/auth/invite_screen.dart) — rewrite
  `_acceptInvite` error/accept handling + add the private helpers (fix #1/#2). Keep
  `_sendMagicLink` as-is.
- [lib/features/auth/auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart)
  — consolidate navigation through `_navigateToHome()` (`/`→`/app`), route the
  `_handleConfirm` terminal block through it, add loop `mounted` guards (fix #4).
- [test/features/auth/auth_confirm_screen_test.dart](test/features/auth/auth_confirm_screen_test.dart)
  — replace the `findsOneWidget` single-push assertion with a `NavigatorObserver`
  push-count delta measurement (fix #5).

## Files Off-Limits

- [members_tab_content.dart](lib/features/members/members_tab_content.dart) + its test —
  committed Cycle 1; preserve.
- [send-band-invite/index.ts](supabase/functions/send-band-invite/index.ts) — the
  `/invite?token=` landing is correct.
- [auth_gate.dart](lib/features/auth/auth_gate.dart) — its `body:{}` email sweep is
  try/catch-guarded; do not touch (no-token semantics must stay stable).
- `PendingInviteHelper` in [invite_screen.dart](lib/features/auth/invite_screen.dart#L519)
  — dead code, no callers; and the `kPendingInviteTokenKey` write — pre-existing legacy.
- [login_screen.dart](lib/features/auth/login_screen.dart) — normal login redirect
  unchanged.
- [main.dart](lib/main.dart) — keep the existing uncommitted `invite_token` pass-through;
  no further change.
- `supabase/migrations/**`, `accept_band_invite` RPC — n/a.

## Change Budget

Measured against the actual diff (lowballing produces false warnings).

- `supabase/functions/accept-invite/index.ts`: net ≈ **+15 to +30** (token branch
  rewired; sweep block unchanged).
- `supabase/functions/accept-invite/invite_result.ts`: **new ≈ 70–110** lines.
- `supabase/functions/accept-invite/index.test.ts`: **new ≈ 90–150** lines.
- `lib/features/auth/invite_screen.dart`: net ≈ **+55 to +90** (`_acceptInvite` rewrite +
  private helpers).
- `lib/features/auth/auth_confirm_screen.dart`: net ≈ **−8 to +8** (consolidation removes
  the duplicate terminal nav block; adds loop guards).
- `test/features/auth/invite_screen_test.dart`: **new ≈ 220–330** lines (7 cases +
  offline harness).
- `test/features/auth/auth_confirm_screen_test.dart`: net ≈ **+25 to +50**
  (NavigatorObserver measurement).
- `lib/main.dart`: **0** (retain).
- Expected new files: **3**. New public symbols: **2** exported TS functions
  (`classifyTokenInvite`, `tokenInviteResponse`) + private Dart helpers. New
  dependencies: **0**.

## System Impact Map

- Gigs / Rehearsals / Setlists / Notifications: unaffected.
- Members: affected — invite acceptance; Cycle 1 entry-point fix preserved.
- Auth: affected — invite-accept error handling + auth-confirm navigation.
- Routing: affected — auth-confirm single navigation authority (web → `/app`).
- Platforms: web invite-acceptance surface affected; native login/deep-link and web PKCE
  flows unchanged.

## Regression Risk

**MEDIUM.** Touches auth/invite acceptance and the auth-confirm navigation, but reuses
existing screens and the proven PKCE path, adds no init-order/DB/platform wiring, and the
server change narrows an over-broad fallback (a net security improvement) with the
risk-bearing logic isolated in a unit-tested pure module. The navigation change
consolidates two authorities into one and preserves the proven `/app` destination.

## Engineer Task Breakdown (ordered, atomic)

1. Do **not** modify `members_tab_content.dart`/its test, `send-band-invite`,
   `auth_gate.dart`, `login_screen.dart`, `PendingInviteHelper`, `main.dart`, or any
   migration/RPC.
2. Create `supabase/functions/accept-invite/invite_result.ts` with `classifyTokenInvite`
   and `tokenInviteResponse` per §1 (pure, no remote imports).
3. In `accept-invite/index.ts`: `import { classifyTokenInvite, tokenInviteResponse } from
   "./invite_result.ts";`. Rewire the `if (inviteToken)` branch to query by token alone
   (`select id, band_id, email, status, expires_at, bands(name)`, `.maybeSingle()`),
   classify, call `accept_band_invite` only when `eligible`, and return
   `tokenInviteResponse(classification, { rpcFailed })`. Change the sweep guard to
   `if (!inviteToken)`; leave the sweep body and its aggregate `200` response unchanged.
4. Create `supabase/functions/accept-invite/index.test.ts` importing from
   `./invite_result.ts` and `assertEquals`; cover every bucket (§ Verification Tier 1).
5. In `invite_screen.dart` `_acceptInvite`: implement the status-driven recovery matrix
   (§2) with `on FunctionsHttpException` / `on FunctionsFetchException` / final `catch`,
   the `200` accepted-band guard, and the `_handleAcceptHttpError`/`_safeLocalSignOut`/
   `_asMap` helpers. Reuse the existing `package:supabase_flutter/supabase_flutter.dart`
   import for `FunctionsHttpException`, `FunctionsFetchException`, `SignOutScope`. Leave
   `_sendMagicLink` unchanged.
6. In `auth_confirm_screen.dart`: change `_navigateToHome()` web dest `/`→`/app`; replace
   `_handleConfirm`'s terminal nav block with `if (!mounted) return; _navigateToHome();`
   (remove the trailing `_loading=false` setState); add `if (!mounted) return;` before
   `ref.read` inside the sync `while` loop. Do not alter the early existing-session/
   fragment `_navigateToHome()` calls beyond the shared dest change.
7. Create `test/features/auth/invite_screen_test.dart` (§ Verification Tier 1).
8. Update `auth_confirm_screen_test.dart` to measure single-push via `NavigatorObserver`
   (§ Verification Tier 1).

## Verification Plan

### Tier 1 — mechanically runnable, no running app (QA gate)

1. `flutter analyze` — no new issues in touched Dart files.
2. `flutter test test/features/members/members_tab_content_test.dart` — Cycle 1 green.
3. **New** `flutter test test/features/auth/invite_screen_test.dart`, offline
   `MockClient` + `recoverSession(jsonStr)` priming (mirroring
   [auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart)),
   `activeBandProvider` overridden with a fake notifier for the success case, and the
   `_drainKnownRenderOverflow` pattern for the known auth-UI overflow. **Determinism:**
   the `MockClient` returns bodies as **plain text (no `application/json` header)** so
   functions_client decodes synchronously (`utf8.decode`) and never routes through its
   JSON background isolate — recovery is asserted on `e.status`, so it holds whether
   `e.details` is a `Map` or `String`. Cases:
   - **No session** → email-entry auth UI, not an error.
   - **Valid same-email** (primed) + accept-invite `200 {success:true,
     accepted_band_id, band_names:[…]}` → success state ("You've joined …").
   - **Stale/401** (primed) + accept-invite `401` → `invoke` throws real
     `FunctionsHttpException` → auth UI shown, `currentSession == null` (local sign-out
     happened), and `Something went wrong. Please try again.` **absent**.
   - **Wrong-email/403** (primed) + `403 {code:'email_mismatch'}` → auth UI recovery,
     `currentSession == null`, **no** false success, **no** generic error.
   - **Unavailable/409** (primed) + `409 {code:'invite_unavailable'}` → neutral terminal
     message, `currentSession` **still present** (no sign-out), no auth UI, no generic.
   - **RPC failure/502** (primed) + `502 {code:'accept_failed'}` → actionable retry
     message, `currentSession` still present, no auth UI, not generic.
   - **Network** → handler throws → `FunctionsFetchException` → network message, not
     generic.
4. **New** `deno test --allow-env supabase/functions/accept-invite/` — asserts
   `classifyTokenInvite` (eligible / email_mismatch / consumed / ineligible / expired /
   not_found) **and** `tokenInviteResponse` status+code for **target success (200)**,
   **target RPC failure (502 accept_failed)**, **email_mismatch (403)**, and
   **invite_unavailable (409, every reason and not_found)**. This is the strongest
   *mechanical* server-contract coverage; it never calls a live RPC/DB. Deno is installed
   with precedent
   ([getsongbpm_lookup/index.test.ts](supabase/functions/getsongbpm_lookup/index.test.ts)).
   *If the QA environment lacks `deno`,* fall back to static review of `invite_result.ts`
   + the `index.ts` wiring and rely on the client harness (case 3) — justified because the
   pure functions are the risk-bearing logic and the classifier/response are a single
   imported source (no copy-drift).
5. **New/updated** `flutter test test/features/auth/auth_confirm_screen_test.dart` — a
   recording `NavigatorObserver` captures `didPush` count; capture `baseline` after the
   first `pump()`, then after draining a successful invite confirm assert
   `pushCount - baseline == 1` (single-shot; a double-push regresses to `2`). Keep the
   destination checks (`find.byType(InviteScreen)` + `inviteScreen.token`) as secondary,
   and Test B (no-invite → `AuthGate`, single push). **This replaces the
   `findsOneWidget`-only guard, which cannot detect a double push.**
6. **Static review** of `accept-invite/index.ts`: the `!inviteToken` sweep block +
   aggregate `200` are byte-equivalent to before; a provided token never reaches the
   sweep; `accept_band_invite` is called only on `eligible`.
7. **No-token sweep + idempotency (static):** confirm the AuthGate `body:{}` path is
   unchanged and re-invoking a token whose invite is already `accepted` classifies as
   `unavailable/consumed` → `409` with no RPC call (idempotent, deterministic).

No migration/RPC change → **no DB apply-check** and **no `has_function_privilege` check**
required.

### Tier 2 — owner-run by Tony (require a running app / live backend; hand over verbatim)

1. **Deploy** `accept-invite` after merge (`supabase functions deploy accept-invite`).
   The web build carries the client fixes. Deploy order is safe either way: pre-deploy,
   the client's status + accepted-band guards already degrade the old
   `200/accepted_count:0` to recovery instead of a false success.
2. **Production redirect allow-list (fix #6).** Supabase → Authentication → URL
   Configuration: confirm Redirect URLs accept `https://app.bandroadie.com/auth/confirm`
   **with** an `invite_token` query parameter (add `https://app.bandroadie.com/auth/confirm*`
   if entries are exact-match). Expected: invite magic link lands on
   `/auth/confirm?invite_token=…&code=…`, not the site root. (If it falls back, AuthGate's
   email sweep still accepts after sign-in.)
3. **Reproduce Tony's case (stale session).** In a browser with an existing signed-in
   session, open a fresh invite link for a **different** email. Expected: **no**
   `Something went wrong` dead-end; guided to sign in with the invited email (no false
   "accepted").
4. **Happy path (new invitee).** Members → Add → invite a fresh address → email form →
   request login link → open → through `/auth/confirm` → "You've joined <Band>!" →
   active member. Expected: exactly one acceptance, no double redirect.
5. **Same-email already signed in.** Signed in as the invited email, open the invite link
   → immediate acceptance, no error.
6. **Normal web login regression.** Request a non-invite magic link → open → lands at
   `/app` (AuthGate), no InviteScreen interposed.
7. **Mobile regression.** iOS/Android `bandroadie://login-callback/` login unchanged.
8. **Server curl contract (authenticated Bearer):** `body:{token:<foreign-email token>}`
   → `403 email_mismatch`; `body:{token:<consumed token>}` → `409 invite_unavailable`;
   `body:{}` (no token) → the email sweep still accepts by email. Confirms the deployed
   contract matches the unit-tested shape.

## QA Regression Areas

- Invite acceptance error handling/recovery (first-link path) and the token contract.
- `accept-invite` targeted-token vs email-sweep separation.
- Auth-confirm single-navigation + web `/app` destination.
- Members-tab invite entry points (Cycle 1).
- Normal web magic-link login and native deep-link login.

## Rollout Strategy

Standard PR on `bug/member-invitations-after-phone-change`. Merge → deploy the
`accept-invite` edge function → ship the web build. No feature flag, no migration, no
staged rollout. Confirm Tier 2 items 1–2 at/around release.

## Out of Scope

- Group chat.
- Refactoring `AuthGate`, `PendingInviteHelper`, the InviteScreen hierarchy, or the
  legacy `kPendingInviteTokenKey` storage.
- Repointing the invite email in `send-band-invite`.
- Phone-number account merge / identity migration — the defect is session-handling.
- Email deliverability / Resend configuration.
