# ARCHITECT_PLAN — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Problem Summary

On native platforms (iOS, Android, macOS) the demo entry point creates an
anonymous Supabase session. `supabase_flutter` persists that session to local
storage exactly like a real-user session, so on the next cold start it is
restored and the app auto-routes straight back into the Demo Band, skipping the
login screen — for as long as the underlying `demo_sessions` slot has not yet
been reclaimed by the existing TTL + cron mechanism shipped in #289.

This auto-resume is correct and wanted for authenticated **real** users. It is
**not** wanted for the anonymous demo flow: a demo entry should always start
clean at the login screen on relaunch, regardless of how much TTL remains.

## Root Cause

**Confidence: HIGH** (confirmed in code.)

Auth routing has no notion of "anonymous restored session vs. real restored
session." Two facts combine:

1. `AppAuthState.isAuthenticated` is defined purely as `session != null`
   ([lib/features/auth/auth_state_provider.dart](lib/features/auth/auth_state_provider.dart#L19)),
   with no anonymous branch.
2. `AuthGate.build()` and `_buildAuthContent()` route solely on
   `isAuthenticated`
   ([lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L440-L487)).
   A restored anonymous session therefore satisfies every gate and lands in
   `AppShell` on the Demo Band.

`AuthStateNotifier.build()` seeds state directly from
`Supabase.instance.client.auth.currentSession`
([auth_state_provider.dart](lib/features/auth/auth_state_provider.dart#L53)),
which is already populated from local storage by the time
`Supabase.initialize()` (in `main.dart`) has awaited. On native, `main.dart`
does nothing between session restore and `runApp()` to distinguish an anonymous
restored session from a real one, so it survives the relaunch.

The only existing anonymous-specific branch,
`_reconcileOrphanedAnonymousSession()`
([auth_gate.dart](lib/features/auth/auth_gate.dart#L303-L328)), signs an
anonymous user out globally on cold start **only if their demo band no longer
exists** — i.e. only *after* the slot was already reclaimed. It never fires
while the demo session is still live, which is exactly the window this feature
targets.

## Existing System Analysis

Cold-start auth path, native (confirmed by reading the code):

1. `main.dart` → `Supabase.initialize()` awaits; local storage session (incl. a
   restored anonymous demo session) is recovered into `currentSession`. A
   `FormatException` retry path already exists that signs out and re-initializes
   on corrupt session data
   ([main.dart](lib/main.dart#L60-L88)).
2. `runApp()` → first widget build → `AuthStateNotifier.build()` reads
   `currentSession` and returns `AppAuthState(session: restored)`.
   `isAuthenticated == true` for the anonymous session.
3. `AuthGate` shows the splash (native: `_showSplash = !kIsWeb`) stacked over
   `_buildAuthContent()`. Because `isAuthenticated == true`, the underlying
   content is *not* `LoginScreen`; it proceeds through the profile gate
   (anonymous → treated complete,
   [auth_gate.dart](lib/features/auth/auth_gate.dart#L236-L245)) and into
   `AppShell` once bands load.

Load-bearing safeguards that **read the Supabase client session as ground
truth** and will actively *resurrect* any session the provider layer tries to
drop — these are why a provider/widget-only fix is fragile:

- The `build()` safeguard: if the provider says "no session" but
  `supabase.auth.currentSession != null`, it force-refreshes back to the client
  session ([auth_gate.dart](lib/features/auth/auth_gate.dart#L457-L485)).
- `_startSessionSyncTimer()` every 5 s does the same via `forceRefresh()`
  ([auth_gate.dart](lib/features/auth/auth_gate.dart#L79-L118)).
- `refreshSession()` / `forceRefresh()` re-seed state from `currentSession`
  with no anonymous awareness
  ([auth_state_provider.dart](lib/features/auth/auth_state_provider.dart#L104-L155)).
- The `onAuthStateChange` listener replays `initialSession` with the restored
  session to new subscribers
  ([auth_state_provider.dart](lib/features/auth/auth_state_provider.dart#L83-L86)).

Consequence: any fix that leaves `supabase.auth.currentSession` non-null while
trying to route the anonymous user to login would be immediately undone by the
`build()` safeguard on the very first frame. The only robust, low-blast-radius
fix is to make `currentSession` itself `null` **before** the app's auth
machinery ever reads it — i.e. a cold-start purge in `main.dart`, ahead of
`runApp()`.

Demo lifecycle facts confirmed:

- Demo entry is native-only: `_kDemoBandVisible = !kIsWeb`
  ([login_screen.dart](lib/features/auth/login_screen.dart#L53)). Web never
  calls `signInAnonymously()`, so a restored anonymous session can only exist on
  native. A cold-start purge is therefore inert on web with no platform gate
  required.
- A **fresh** in-run demo session is created by
  `DemoSessionService.provisionAndEnter()`
  ([demo_session_service.dart](lib/features/auth/demo_session_service.dart#L16-L37))
  only *after* the app is running and the user taps the demo button — it never
  passes through `main.dart`'s startup path. This cleanly separates "restored at
  cold start" (purge) from "created during this run" (keep).
- `signOut(scope: SignOutScope.local)` in gotrue clears the in-memory session
  and persisted local storage **before** attempting the ignorable network
  revoke, so it removes the session even offline. This is the guarantee that
  login is presented regardless of connectivity.

## Proposed Solution

Add a **cold-start purge of a restored anonymous demo session** in `main.dart`,
immediately after `Supabase.initialize()` (and its existing `FormatException`
retry) and before `Firebase.initializeApp()`.

Behavior:

- After Supabase init, read `currentSession`. If it is a restored anonymous
  session, perform a **local** sign-out (`SignOutScope.local`), bounded by a
  short timeout so a slow/offline network revoke cannot delay startup. Because
  gotrue clears local + persisted storage before the network part, this makes
  `currentSession == null` before `runApp()`.
- The gate condition is expressed via a new pure predicate on
  `DemoSessionService` (mirroring #289's `shouldReleaseDemoOnLifecycle` testable
  seam) so the "restored anonymous only; never real users; never no-session"
  decision is headlessly unit-testable.

With `currentSession == null` at startup, **every** existing auth path —
`AuthStateNotifier.build()`, the `build()` safeguard, the 5 s sync timer,
`refreshSession`/`forceRefresh`, the `initialSession` replay — agrees "no
session" and routes to `LoginScreen` with **zero** special-casing anywhere in
the provider/widget layer. `isAuthenticated == session != null` is left
literally unchanged, so real-user persistence is preserved exactly.

### Decision: local sign-out only (no cold-start server release)

**Explicitly decided:** cold-start handling performs a **local sign-out only**;
it does **not** call the `exit-demo-session` edge function to release/delete the
server-side demo slot.

Rationale:
- The primary requirement — "demo never resumes on relaunch" — is fully and
  instantly satisfied by the local sign-out, with **no network dependency** and
  no added startup latency in the common case. This honors the Manager's stated
  preference that the fix "does not depend on exit-time network completion": a
  pure local clear depends on no network at all.
- Server-side slot/row reclamation is **already owned** by #289's 8-minute TTL +
  2-minute cron sweep (off-limits) and by the existing best-effort `detached`
  release. Adding a second cold-start release would be a redundant, overlapping
  reclamation mechanism whose only benefit is freeing a slot a few minutes
  earlier — not required by this feature, and it would put a network call
  (plus timeout/ordering complexity) on the startup path.
- **Failure behavior (login guaranteed):** `signOut(scope: SignOutScope.local)`
  removes the persisted session from local storage client-side *before* the
  ignorable network revoke, so even fully offline `currentSession` becomes
  `null` and the app routes to login. The now-orphaned server-side slot is
  reclaimed by the unchanged #289 TTL + cron backstop; if a later authenticated
  cold start ever observes an anonymous session whose band is already gone, the
  existing `_reconcileOrphanedAnonymousSession()` global sign-out still applies.
  If the bounded `signOut` call itself throws, `main.dart` swallows it and still
  proceeds to `runApp()`; the worst case for that one launch is the pre-fix
  behavior, backstopped by TTL — no crash, no regression for real users.

## Database Impact

**Not applicable.** No migration, RLS policy, RPC, trigger, grant, or edge
function change. #289's advisory lock, 8-minute TTL, 2-minute cron, migration,
grants, and capacity math are untouched and off-limits.

## Flutter Architecture Changes

No new provider, controller, repository, or state-management pattern. One new
pure static predicate is added to the existing `DemoSessionService` (a testable
seam, matching the established #289 pattern). `AppAuthState`, `AuthStateNotifier`,
`AuthGate`, and `isAuthenticated` semantics are unchanged.

**Init-order change (explicit, logged decision required).** A new step is
inserted into the fixed app initialization order documented in
[RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md#L7-L20):

```
6.  Supabase.initialize()
6.5 Purge restored anonymous demo session (local sign-out)   ← NEW
7.  Firebase.initializeApp()   (native only)
8.  DeepLinkService setup
9.  runApp()
```

Per the init-order guardrail, this is not silent: the Engineer must record it as
a new `AI_DECISIONS.md` entry (`DECISION-006`) and update the init-order list in
`RUNTIME_CONFIG.md` as part of implementation (exact content specified in the
Task Breakdown). No other step is reordered; the new step sits between existing
steps 6 and 7 only.

## Files to Create

**None** (the predicate's unit test is added to the existing
`test/features/auth/demo_lifecycle_predicate_test.dart`, which already houses the
sibling `DemoSessionService` predicate tests).

## Files to Modify

| File | Change |
| --- | --- |
| [lib/main.dart](lib/main.dart) | Add `import 'features/auth/demo_session_service.dart';`. After the `Supabase.initialize()` try/catch block and before the Firebase init block, add the cold-start purge: read `currentSession`, and if `DemoSessionService.shouldPurgeRestoredAnonymousSession(...)` is true, `await` `signOut(scope: SignOutScope.local)` inside try/catch with a short (~2 s) `.timeout(...)`. |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) | Add one pure static predicate `shouldPurgeRestoredAnonymousSession({required bool hasSession, required bool isAnonymous}) => hasSession && isAnonymous;` with a doc comment stating restored-anonymous-only intent. Do **not** modify any existing method (`provisionAndEnter`, `exit`, `heartbeat`, `releaseSlotOnDetach`, `shouldReleaseDemoOnLifecycle`). |
| [test/features/auth/demo_lifecycle_predicate_test.dart](test/features/auth/demo_lifecycle_predicate_test.dart) | Add a new `group('shouldPurgeRestoredAnonymousSession', ...)` with the truth-table cases (see Verification Plan). |
| [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) | Append `DECISION-006` documenting the init-order insertion and the local-sign-out-only choice (content in Task Breakdown). |
| [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) | Insert step `6.5` into the init-order block. |

## Files Off-Limits

| File / Area | Why |
| --- | --- |
| `supabase/migrations/**`, `supabase/functions/exit-demo-session/**`, `provision_demo_session`, `heartbeat_demo_session`, `cleanup_demo_sessions` cron, advisory lock `8675309001`, 8-min TTL, 2-min cron, grants, capacity math | Shipped and authoritative in #289 (DECISION-005). This feature changes only relaunch-resume behavior, not TTL/capacity/reclamation. |
| `lib/features/auth/auth_state_provider.dart` | `isAuthenticated == session != null` must stay unchanged; the fix works by nulling `currentSession` upstream, not by re-defining auth semantics (which would break the live demo flow and real-user persistence). |
| `AuthGate` routing, safeguards, sync timer, `_reconcileOrphanedAnonymousSession()` | Left intact as an unchanged safety net; the purge makes the restored-anonymous case unreachable at cold start, but the reconcile backstop stays for any residual edge case. |
| `lib/features/auth/login_screen.dart` (`_kDemoBandVisible`, `_enterDemo`) | Demo entry/gating and fresh-session creation are unchanged. |
| `lib/features/shell/app_shell.dart` (`Exit Demo`) | The in-app exit path already works; not touched. |

## Change Budget

- `lib/main.dart`: net **+~12** lines (one import + the guarded purge block).
- `lib/features/auth/demo_session_service.dart`: net **+~10** lines (one pure
  static method + doc comment).
- `test/features/auth/demo_lifecycle_predicate_test.dart`: net **+~30** lines
  (one new `group`).
- `docs/reference/general/AI_DECISIONS.md`: net **+~30** lines (DECISION-006).
- `docs/reference/general/RUNTIME_CONFIG.md`: net **+~2** lines (step 6.5).
- New files: **0**.
- New public classes/methods: **1** (the static predicate).
- New dependencies: **0**.

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Auth | **Affected** | Cold start now purges a restored anonymous session before `runApp()`. Real-user (non-anonymous) restore is unaffected. |
| Routing | **Affected (indirect)** | With `currentSession == null`, existing routing lands on `LoginScreen`. No routing code changes. |
| Init order | **Affected** | New step 6.5 (logged decision + RUNTIME_CONFIG update). |
| Setlists / Gigs / Rehearsals / Members / Notifications | **Unaffected** | No touchpoints. |
| Platforms | **Native (iOS/Android/macOS): affected** by the purge. **Web: unaffected** — `_kDemoBandVisible == false` on web means no anonymous session ever exists, so the purge is inert; no `!kIsWeb` gate needed. |
| DB / RLS / RPC | **Unaffected** | No DB change. |

## Regression Risk

**MEDIUM.** The touched surfaces (init order + auth session handling) are
high-sensitivity, but the actual behavioral change is tightly gated to a
*restored anonymous* session and is a superset of the pre-existing
`FormatException` "sign out and continue" pattern already present at the same
point in `main.dart`. Real users, web, and the live in-run demo flow are
provably unaffected because the gate is `hasSession && isAnonymous` and fresh
demo sessions are created after startup. Primary residual risk is startup
latency in the rare offline-demo-relaunch case, bounded by the `.timeout`.

## Engineer Task Breakdown

1. **`DemoSessionService` predicate.** In
   [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart),
   add a pure static method next to `shouldReleaseDemoOnLifecycle`:
   ```dart
   /// Pure predicate (testable seam): a session that must be purged at cold
   /// start is a *restored* anonymous demo session — one already in storage
   /// when the app launches. Fresh in-run demo sessions never reach this path
   /// (they are created after startup via the demo button). Real users
   /// (non-anonymous) and the no-session case are never purged, so persistent
   /// real-user sessions are preserved exactly.
   static bool shouldPurgeRestoredAnonymousSession({
     required bool hasSession,
     required bool isAnonymous,
   }) =>
       hasSession && isAnonymous;
   ```
   Do not alter any existing method.

2. **`main.dart` cold-start purge.** Add
   `import 'features/auth/demo_session_service.dart';` to the imports. Then,
   immediately after the `Supabase.initialize()` try/catch block (the one with
   the `FormatException` retry) and **before** the `// Initialize Firebase`
   block, insert:
   ```dart
   // Never resume an anonymous/demo session across a relaunch. A restored
   // anonymous session is purged locally so cold start always lands on login;
   // fresh in-run demo sessions (created after startup) are unaffected. Real
   // users are non-anonymous and skip this entirely. Bounded so a slow/offline
   // network revoke can't delay startup — gotrue clears local storage before
   // the network part, so login is guaranteed even on timeout.
   final restoredSession = Supabase.instance.client.auth.currentSession;
   if (DemoSessionService.shouldPurgeRestoredAnonymousSession(
     hasSession: restoredSession != null,
     isAnonymous: restoredSession?.user.isAnonymous == true,
   )) {
     try {
       await Supabase.instance.client.auth
           .signOut(scope: SignOutScope.local)
           .timeout(const Duration(seconds: 2), onTimeout: () {});
     } catch (e) {
       debugPrint('[Main] Anonymous demo session purge failed: $e');
     }
   }
   ```
   (`SignOutScope` is already available via the existing unprefixed
   `package:supabase_flutter/supabase_flutter.dart` import.)

3. **Predicate unit test.** In
   [test/features/auth/demo_lifecycle_predicate_test.dart](test/features/auth/demo_lifecycle_predicate_test.dart),
   add a second `group('shouldPurgeRestoredAnonymousSession', ...)` (see
   Verification Plan for the exact cases).

4. **Log the init-order decision.** Append `DECISION-006` to
   [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md)
   — Feature `feature/demo-session-no-relaunch-resume`, Status Active — recording:
   (a) the new init-order step 6.5 (purge restored anonymous demo session via
   local sign-out, after `Supabase.initialize()`, before `Firebase.initializeApp()`);
   (b) the decision that cold-start handling is **local sign-out only**, with
   server-side slot reclamation left to #289's untouched TTL+cron; (c) the
   login-guaranteed failure behavior; (d) a one-line rollback (revert `main.dart`,
   the predicate, the test, and the two doc edits — no DB to unwind).

5. **Update RUNTIME_CONFIG.** Insert step `6.5 Purge restored anonymous demo
   session (local sign-out) ← native-only effect` into the init-order block in
   [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md#L15-L20),
   between `6. Supabase.initialize()` and `7. Firebase.initializeApp()`.

## Verification Plan

This is a client-only change with **no database function** involved, so the
Tier-1/Tier-2 "never call the function being replaced" distinction does not
apply. QA's mechanically-executable gate is static analysis + the headless test
harness; the actual relaunch behavior requires a running app and is therefore an
owner-run (Tony) punch list, not a QA gate.

### Tier 1 — QA gate (headless, no running app)

1. `flutter analyze` — **0 new errors/warnings** in `lib/main.dart` and
   `lib/features/auth/demo_session_service.dart`.
2. `flutter test test/features/auth/demo_lifecycle_predicate_test.dart` — the new
   `shouldPurgeRestoredAnonymousSession` group passes:
   - `hasSession: true, isAnonymous: true` → `true` (restored demo → purge).
   - `hasSession: true, isAnonymous: false` → `false` (real user → never purge —
     guards real-user persistence).
   - `hasSession: false, isAnonymous: false` → `false` (no session → no-op).
   - `hasSession: false, isAnonymous: true` → `false` (defensive: no session
     dominates).
3. `flutter test` (full suite) — no new failures. Confirm the existing
   `test/features/auth/demo_lifecycle_predicate_test.dart` and
   `test/features/auth/auth_gate_anonymous_recovery_test.dart` still pass
   (reconcile backstop unchanged). Note: pre-existing unrelated failures in
   `test/features/auth/login_screen_demo_button_test.dart` are documented in
   prior reports and are out of scope — confirm via `git diff --stat main -- test/`
   that this branch introduces zero changes there.
4. Static review: confirm `main.dart` inserts the purge **between** the Supabase
   init block and the Firebase block (init-order step 6.5), that the only auth
   semantics change is `currentSession` nulling (no edit to `isAuthenticated`),
   and that `RUNTIME_CONFIG.md` + `AI_DECISIONS.md` were updated to match.

### Tier 2 — DB apply-check

**n/a** — no migration.

### Owner-run punch list (Tony — requires a running app; QA cannot execute)

Run each on a **native** build (repeat on macOS and at least one of iOS/Android):

1. From the login screen, tap "Check out the demo band" → confirm you land in
   the Demo Band. **Expected:** demo loads normally (fresh in-run session
   unaffected).
2. Fully quit the app (macOS: Cmd-Q; iOS/Android: swipe-kill from app switcher)
   **within the TTL window** (well under 8 minutes). Reopen the app.
   **Expected:** the app presents the **login screen** — it does **not** resume
   into the Demo Band.
3. Repeat step 2 but reopen with the device in **airplane mode / no network**.
   **Expected:** still the login screen (local sign-out clears storage offline).
4. Real-user regression: sign in as a normal (non-anonymous) account, quit, and
   reopen. **Expected:** the app resumes directly into the account with **no**
   login prompt (persistent real-user session preserved exactly).
5. Web smoke (any browser): confirm no demo button is present and normal
   real-user session resume across a page reload is unchanged.

## QA Regression Areas

- **Real-user session persistence** (highest priority): a non-anonymous user must
  still auto-resume on relaunch — covered by predicate case #2 and punch-list #4.
- **Live in-run demo flow**: tapping the demo button and using the Demo Band in
  the same run must be unaffected — punch-list #1.
- **Anonymous reconcile backstop**: `auth_gate_anonymous_recovery_test.dart`
  must still pass; `_reconcileOrphanedAnonymousSession()` is unchanged.
- **Startup robustness**: `main.dart` must reach `runApp()` even if the purge
  throws or times out (offline) — verified by static review of the try/catch +
  timeout.
- **Init order**: RUNTIME_CONFIG + AI_DECISIONS reflect the new step 6.5.

## Rollout Strategy

Standard single-PR rollout on `feature/demo-session-no-relaunch-resume`. No
migration, no feature flag, no phased deploy. Rollback is a straight revert of
`main.dart`, the predicate, the test group, and the two doc edits — nothing to
unwind server-side (no DB change).

## Out of Scope

- Any change to #289's TTL, cron, advisory lock, capacity math, migration,
  grants, or the `exit-demo-session` edge function.
- Adding a cold-start **server-side** demo-slot release (explicitly rejected
  above; reclamation stays with #289's TTL+cron).
- The uncommitted `didRequestAppExit()` desktop graceful-exit experiment from
  `bug/demo-capacity-check-race-and-leak` — not adopted; a cold-start purge is
  more robust and covers force-kill/background on all native platforms, which an
  exit-time hook cannot.
- Removing or refactoring `_reconcileOrphanedAnonymousSession()` or the auth
  safeguards/sync timer — left intact as backstops.
- Any web demo entry point (does not exist; not being added).
