# ARCHITECT_PLAN — Demo Cold Start Stale Anon Session

> **Cycle 4 revision (2026-09-04).** Prior cycle's design synchronously called `unawaited(_reconcileOrphanedAnonymousSession())` from `_initializeAuth()` (which runs from `initState`). The reconcile's first `await` targeted `activeBandProvider.notifier.loadUserBands()`, whose synchronous prefix mutates provider state before the first real `await` — Riverpod threw `"Tried to modify a provider while the widget tree was building."`, the reconcile's own `try/catch` swallowed it, and `signOut(scope: SignOutScope.global)` never executed. This revision defers the reconcile via `WidgetsBinding.instance.addPostFrameCallback` so the mutation lands after the build phase, matching the file's existing safe pattern (`didChangeAppLifecycleState` → `refreshSession`, `_buildAuthContent` → `_checkProfileComplete`). Root cause, files-off-limits, DB impact, and out-of-scope are unchanged from the prior cycle. Revised sections: **Cycle 4 Revision Note**, **Proposed Solution**, **Files to Modify**, **Change Budget**, **Engineer Task Breakdown**, **Verification Plan**.

## Feature Slug

`bug/demo-cold-start-stale-anon-session`

## Feature Title

App hangs on a black screen with a perpetual loading spinner when the app is cold-started while a stale/orphaned anonymous demo session is persisted on the device.

## Problem Summary

On the `feature/interactive-demo-band-experience` branch, tapping "Check out the demo band" performs `supabase.auth.signInAnonymously()` and `provision_demo_session()`, which clones two template bands for the anonymous user. Supabase persists the anonymous session in device secure storage. When the app is later cold-started and the anonymous user's cloned bands are gone server-side (clone expired via `cleanup_demo_sessions_cron`, exited via `exit_demo_session` from another device, or provisioning never completed), the app hangs after the splash on a black screen with an infinite `AppProgressIndicator`. On macOS a variant produced a `signOut(scope: local)` ↔ `tokenRefreshed` restore loop.

Reproduction and expected/actual behavior are documented in the Feature Input (see `bug/demo-cold-start-stale-anon-session` bug intake).

## Root Cause

Two independent code-path failures compose into the hang; both are confirmed in code.

### Failure A — cold-start anonymous path never loads bands (confidence: HIGH)

1. [lib/features/auth/auth_state_provider.dart](lib/features/auth/auth_state_provider.dart#L54) — `AuthStateNotifier.build()` reads `Supabase.instance.client.auth.currentSession` synchronously. `Supabase.initialize()` (invoked in [lib/main.dart](lib/main.dart#L60-L77)) awaits session restore before returning, so on a cold start with a persisted anonymous session this returns non-null and the initial `AppAuthState` is `isAuthenticated == true`.
2. [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L149-L184) — `_initializeAuth()` runs in `initState`, reads `authStateProvider`, sees `isAuthenticated == true`, and calls `_checkProfileComplete()`.
3. [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L229-L237) — `_checkProfileComplete()` short-circuits when `supabase.auth.currentUser?.isAnonymous == true`: it sets `_profileComplete = true`, `_checkingProfile = false`, and **returns before invoking `_checkAndProcessPendingInvite()`**. That method (auth_gate.dart:281–366) is the only place inside AuthGate that calls `ref.read(activeBandProvider.notifier).loadUserBands()`.
4. [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart#L204-L206) — `ActiveBandNotifier.build()` returns `const ActiveBandState()`, so `userBands = const []` and `isLoading = false` remain the initial state indefinitely for cold-started anonymous sessions.
5. [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L602-L622) — `_buildAuthContent` reaches the `bandState.userBands.isEmpty` branch. The anonymous sub-branch returns a bare `AppProgressIndicator` with the comment "provisioning is still in flight." That assumption holds during a fresh demo entry (`DemoSessionService.provisionAndEnter` will complete and populate `userBands`), but **not on a cold start** — nothing is provisioning; the clone is already gone.

Result: perpetual spinner. This latent failure affects every anonymous cold start, not only the orphaned-clone case — a cold start whose clone bands still exist server-side would also hang because nothing triggers `loadUserBands()` for the restored session.

### Failure B — macOS `signOut(local)` restore loop (confidence: HIGH)

Confirmed from `gotrue-2.27.2/lib/src/gotrue_client.dart:1075` and `constants.dart:105-115` in the resolved pub cache:

- `SupabaseAuth.signOut()` defaults to `SignOutScope.local`.
- `SignOutScope.local` clears local storage and fires `AuthChangeEvent.signedOut` immediately, then makes a best-effort admin call to invalidate **only this device's** session. The refresh token remains valid server-side.
- Whenever any code path subsequently triggers a refresh — the AuthGate 5-second `_sessionSyncTimer` (auth_gate.dart:80-113), the `didChangeAppLifecycleState` post-frame `refreshSession()` (auth_gate.dart:132-145), or an in-flight token refresh scheduled by the SDK before the signOut — the refresh succeeds with the still-valid server-side refresh token. `AuthChangeEvent.tokenRefreshed`/`signedIn` fires with the restored session; `AuthStateNotifier`'s post-frame handler at auth_state_provider.dart:66-91 re-assigns `state = AppAuthState(session: data.session)`. The AuthGate sees `isAnonymous + empty bands` again and re-enters Failure A.

The previous inline patch attempts amplified this loop by calling `signOut(scope: local)` from `_checkProfileComplete` — which itself re-runs on every `signedIn`/`tokenRefreshed` because the auth-state listener at auth_gate.dart:157-179 calls it on `isAuthenticated` transitions. Every restored session re-triggered the sign-out; every sign-out was followed by a restore.

### Composed failure

Failure A produces the hang whenever a cold-started anonymous session has zero bands. Failure B is the reason naive recovery attempts (`signOut(local)` from a reactive callsite) turned the hang into an active loop instead of fixing it.

## Existing System Analysis

- `_checkProfileComplete()` early-returns for anonymous users (auth_gate.dart:229-237) because anonymous users have a pre-populated `public.users` row inserted by `provision_demo_session` (supabase/migrations/20260904120003_provision_demo_session_rpc.sql:72-83) and never need the profile-completion form. That short-circuit is correct in intent but has the side effect of skipping `_checkAndProcessPendingInvite()`, which is the only band-loading entry point in the AuthGate.
- `DemoSessionService.provisionAndEnter` (lib/features/auth/demo_session_service.dart:16-32) awaits `loadAndSelectBand(bananaId)` before returning. During a fresh demo entry that call populates `activeBandProvider.state.userBands` before AuthGate rebuilds into the empty-bands branch, so the current "isAnonymous + empty bands → spinner" branch works correctly for the fresh-entry race window. It only misbehaves on cold start, where `provisionAndEnter` never runs.
- `AuthStateNotifier`'s equality operator (auth_state_provider.dart:33-45) compares by `session?.accessToken`, so a redundant `initialSession` event with an identical token does not fire a listener notification. That is helpful — the recovery does not need to defend against redundant `initialSession` re-firings during the same build cycle.
- `loadUserBands()` (active_band_controller.dart:268-322) already handles the empty-list case cleanly, setting `userBands: const [], activeBand: null, isLoading: false` and returning without an error. This is exactly the outcome the recovery needs to consume.
- The 5-second `_sessionSyncTimer` and lifecycle-resume `refreshSession()` are useful safeguards for iPad multitasking and are unchanged by this fix. Neither loads bands; both only reconcile the auth session state, so they cannot substitute for the recovery.

## Cycle 4 Revision Note — Correctness Defect in Prior Design

**Defect (confidence: HIGH — reproduced in the widget-test harness by Engineer; see the Tier-2 rationale at [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart#L14-L25)).**

The prior cycle's design added an unconditional `unawaited(_reconcileOrphanedAnonymousSession())` inside `_initializeAuth()` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L191-L194). `_initializeAuth()` is called synchronously from `initState()` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L67), so the reconcile invocation happens while the widget tree is still building.

`_reconcileOrphanedAnonymousSession()` sets its guard flag and then reaches `await ref.read(activeBandProvider.notifier).loadUserBands()`. `loadUserBands()` at [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart#L268-L272) mutates provider state **synchronously before its first real `await`**:

```dart
Future<void> loadUserBands() async {
  state = state.copyWith(isLoading: true, clearError: true);  // synchronous prefix — mutates activeBandProvider
  try {
    final results = await Future.wait([                       // first real await
      _bandRepository.fetchUserBands(),
      _loadPersistedBandId(),
    ]);
```

That synchronous `state = state.copyWith(...)` modifies `activeBandProvider` during the still-in-progress build phase. Riverpod throws `"Tried to modify a provider while the widget tree was building."` The exception is caught by the reconcile's own `try/catch` — which only logs and returns — so `supabase.auth.signOut(scope: SignOutScope.global)` never executes. The orphaned anonymous session is not cleared and the original hang/loop persists in production. The fix silently no-ops.

**Why the file's other deferred work does not exhibit this:**

- `didChangeAppLifecycleState` schedules `refreshSession()` via `WidgetsBinding.instance.addPostFrameCallback` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L136-L145) — the mutation happens after the frame the lifecycle transition landed on.
- `_buildAuthContent` schedules `_checkProfileComplete()` via `addPostFrameCallback` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L529-L531) — same pattern.
- `_checkProfileComplete()` called **directly** from `_initializeAuth` (for real users) is safe because its first `await supabase.from('users').select(...)` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L263-L267) escapes the build phase **before** any Riverpod provider is mutated. For anonymous users, `_checkProfileComplete` short-circuits at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L237-L241) with a `setState`-only path — also safe (no provider mutation at all).

`_reconcileOrphanedAnonymousSession` has neither escape hatch: its very first `await` targets a provider whose synchronous prefix mutates state. It **must** be deferred past the build phase.

**Fix in this revision:** Wrap the invocation in `WidgetsBinding.instance.addPostFrameCallback`, matching the file's existing safe pattern at lines 136 and 529. With the deferral, when `_reconcileOrphanedAnonymousSession` runs, the build phase is complete; `loadUserBands()`'s synchronous prefix is a legal outside-build mutation; the empty-check proceeds; and `signOut(scope: SignOutScope.global)` actually executes on the orphaned path. The `try/catch` inside `_reconcileOrphanedAnonymousSession` is retained but its purpose is now correctly scoped to genuine runtime/network errors (e.g., a `SocketException` from the `signOut(global)` admin call, a `PostgrestException` inside `loadUserBands`) — **not** to mask a design flaw.

## Proposed Solution

Add a one-shot cold-start reconciliation for anonymous sessions inside the AuthGate. It is **scheduled** from `_initializeAuth()` via `WidgetsBinding.instance.addPostFrameCallback` (a single deterministic point, not reactive to auth-state changes) and **runs after the first frame** so its provider mutation happens outside the build phase. It executes at most once per AuthGate lifecycle, and uses `SignOutScope.global` for the recovery step so the refresh token is revoked server-side and cannot be restored.

Behavior:

- On cold start with a persisted **non-anonymous** session: unchanged. `_checkProfileComplete()` → `_checkAndProcessPendingInvite()` → `loadUserBands()` runs exactly as today. The post-frame callback registered in `_initializeAuth` re-checks `mounted && authState.isAuthenticated && isAnonymous` and no-ops (guard fails on `isAnonymous`).
- On cold start with a persisted **anonymous** session: after the initial frame, the post-frame callback fires. It re-checks `mounted && authState.isAuthenticated && supabase.auth.currentUser?.isAnonymous == true` and, if all pass, invokes `_reconcileOrphanedAnonymousSession`. That method sets `_anonymousReconcileAttempted = true` before its first async gap, then calls `ref.read(activeBandProvider.notifier).loadUserBands()`. Because the callback runs after the build phase, `loadUserBands()`'s synchronous prefix mutation is a legal outside-build mutation and does not throw.
  - If the anonymous user has ≥1 band, state populates and `_buildAuthContent` renders `AppShell` — this also fixes the latent happy-path cold-start hang.
  - If the anonymous user has zero bands, the recovery calls `supabase.auth.signOut(scope: SignOutScope.global)`. `gotrue_client._signOut` (verified in the pub-cache source at `gotrue-2.27.2/lib/src/gotrue_client.dart:1075-1104`) synchronously clears local storage and fires `signedOut` **before** the admin network call, so the local state transitions to unauthenticated even if the network call fails. The global scope invalidates the refresh token server-side, which is what breaks the macOS restore loop.
- The recovery is guarded by an instance-level `_anonymousReconcileAttempted` boolean set to `true` before the first async gap. It is never reset within the AuthGate's lifetime, so the recovery cannot loop. The outer `addPostFrameCallback` registration also fires exactly once (single registration in `_initializeAuth`, which is only called once from `initState`), providing a second layer of idempotency.
- **Transient UI note:** for the one frame between the initial build and the post-frame reconcile firing, `_buildAuthContent` reaches the existing "isAnonymous + empty bands → spinner" branch at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L641-L651). This is now correctly transient — the very next frame after `loadUserBands()` completes either populates bands (rebuild → `AppShell`) or, if empty, `signOut(global)` fires and the widget rebuilds to `LoginScreen`. No user-visible degradation vs. the prior cycle's (broken) direct-invocation timing; the difference is a single frame of latency before recovery starts.
- During a **fresh demo entry** (not a cold start), the anonymous session appears via `signInAnonymously()` inside `DemoSessionService.provisionAndEnter`. That flow does not depend on the recovery — it awaits `loadAndSelectBand` itself. Because the reconcile is gated on `_initializeAuth()` (only fires once, one frame after initState, when the initial session is already anonymous), it does not intercept the fresh-entry race window and cannot destroy an in-flight demo session.
- The `_buildAuthContent` "isAnonymous + empty bands → spinner" branch (auth_gate.dart:641-651) is left untouched. It remains a correct fallback state during the fresh-entry race window and during the one-frame post-frame-callback window described above.

## Database Impact

Not applicable. No migrations, no RLS changes, no new/changed RPCs, no trigger changes. `provision_demo_session`, `exit_demo_session`, `heartbeat_demo_session`, and `cleanup_demo_sessions_cron` are all left as-is — they are already applied to production per the Feature Input.

## Flutter Architecture Changes

Not applicable. No new providers, notifiers, repositories, services, or navigation routes. The recovery is a private method on the existing `_AuthGateState` and a single new instance boolean.

## Files to Create

None.

## Files to Modify

| File                                                                 | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart) | (a) Add a single `show SignOutScope` import from `package:supabase_flutter/supabase_flutter.dart` (the file currently imports the internal `supabase_client.dart` re-export which surfaces the `supabase` getter but not `SignOutScope`). (b) Add one instance field `bool _anonymousReconcileAttempted = false;` alongside the existing `_AuthGateState` fields. (c) Inside `_initializeAuth()`, after the existing `_checkProfileComplete()` / `_registerPushToken()` block, **schedule** the reconcile via `WidgetsBinding.instance.addPostFrameCallback` — matching the safe pattern already used at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L136) and [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L529). Re-check `mounted && authState.isAuthenticated && supabase.auth.currentUser?.isAnonymous == true` **inside** the callback (the auth-state field can safely close over `authState` from `_initializeAuth`, but `mounted` and the anonymous flag must be re-read at callback time because the widget could dispose or the SDK could clear the session between initState and the next frame). Do **not** call `_reconcileOrphanedAnonymousSession` synchronously from `_initializeAuth` — the reason is documented in §Cycle 4 Revision Note. (d) Add one new private method `_reconcileOrphanedAnonymousSession()` that: sets the guard flag first, then `await ref.read(activeBandProvider.notifier).loadUserBands()`, `if (!mounted) return;`, then `if (ref.read(activeBandProvider).userBands.isEmpty && supabase.auth.currentUser?.isAnonymous == true) await supabase.auth.signOut(scope: SignOutScope.global);` — all wrapped in `try`/`catch` that logs via `AuthDebugLogger.error(step: 'reconcileOrphanedAnonymousSession', message: ...)`. The `try/catch` exists only to handle genuine runtime errors (network failures on the signOut admin call, repository errors inside `loadUserBands`); it must **not** be relied on to absorb build-phase Riverpod exceptions, which are prevented by the post-frame deferral in (c). No other logic. |

## Files Off-Limits

| File                                                                                                                                                                           | Why                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/main.dart](lib/main.dart)                                                                                                                                                 | Init order is fixed and unchanged.                                                                                                                                  |
| [lib/features/auth/auth_state_provider.dart](lib/features/auth/auth_state_provider.dart)                                                                                       | The notifier already reacts to `signedOut` correctly; adding logic here would spread the recovery across two files and re-introduce the reactive-loop failure mode. |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart)                                                                                     | Fresh demo entry works — the bug is exclusively cold-start recovery.                                                                                                |
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart)                                                                               | `loadUserBands()` and `ActiveBandState` already model empty-bands correctly.                                                                                        |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart)                                                                                                     | After recovery signOut, the AuthGate lands on LoginScreen via the existing `!authState.isAuthenticated` path — no change needed.                                    |
| [lib/features/shell/no_band_shell.dart](lib/features/shell/no_band_shell.dart), [lib/features/legal/privacy_policy_screen.dart](lib/features/legal/privacy_policy_screen.dart) | Both reference the missing `bandroadie_logo_rose_tag.svg` — see "Out of Scope".                                                                                     |
| `supabase/migrations/**`, `supabase/functions/**`                                                                                                                              | No DB or edge-function changes.                                                                                                                                     |
| `lib/features/shell/app_shell.dart`, `lib/features/home/**`, `lib/features/setlists/**`, `lib/features/calendar/**`, `lib/features/contacts/**`, `lib/features/members/**`     | Not in the failure path.                                                                                                                                            |

## Change Budget

- `lib/features/auth/auth_gate.dart`: net **+35 to +45 lines** (one import, one bool field, one `addPostFrameCallback` block from `_initializeAuth` [~5 lines], one private async method [~25 lines] with try/catch and two debug-logger calls). The deferral wrapper adds ~4 lines vs. the prior cycle's direct-invocation form; the reconcile method body itself is unchanged.
- Existing test file [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart) already exists from prior cycle: current 3 unauthenticated-guard tests remain; add up to 2 additional Tier-1 tests for the reconcile decision logic (see Verification Plan). Net additional **+80 to +140 lines** on top of the existing file.
- **Zero** new files in `lib/`.
- **Zero** new public classes or public methods.
- **Zero** new dependencies.
- **Zero** changes to `pubspec.yaml`, migrations, RPCs, edge functions, or platform config.

## System Impact Map

| Area          | Status                                                                                                                                                                                  |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth          | **Affected** — new cold-start reconciliation for anonymous sessions. Real-user cold start untouched.                                                                                    |
| Routing       | **Affected** — orphan case now correctly routes to LoginScreen instead of hanging. Non-orphan cases unchanged.                                                                          |
| Setlists      | Unaffected.                                                                                                                                                                             |
| Gigs          | Unaffected.                                                                                                                                                                             |
| Rehearsals    | Unaffected.                                                                                                                                                                             |
| Members       | Unaffected.                                                                                                                                                                             |
| Notifications | Unaffected.                                                                                                                                                                             |
| Platforms     | **All** — iOS, macOS, Android, and web all persist the anonymous session via the same secure-storage layer, so all four benefit. No platform-conditional code is introduced or altered. |

## Regression Risk

**MEDIUM.** The change touches the auth gate at initState, which runs on every cold start. Mitigations:

- The new recovery is gated behind `authState.isAuthenticated && supabase.auth.currentUser?.isAnonymous == true`. A real returning non-anonymous user cannot reach any new code — their path is byte-for-byte identical to today's.
- `loadUserBands()` for a non-empty band list is the exact same call the normal flow already makes via `_checkAndProcessPendingInvite`; there is no new query shape or repository call.
- The recovery is one-shot and guarded (both by `addPostFrameCallback`'s single-fire registration and by the internal `_anonymousReconcileAttempted` flag), so it cannot produce the reactive loop that previous inline attempts produced.
- The `addPostFrameCallback` scheduling pattern is already used twice in the same file ([lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L136) and [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L529)) with the same `mounted` re-check idiom, so the approach is not novel to this file.
- Using `SignOutScope.global` instead of `SignOutScope.local` closes the macOS restore-loop mechanism at the SDK level (server-side refresh-token revocation).

## Engineer Task Breakdown

Prior cycle's Tasks 1, 2, 4, 5, 6 are already merged into the working tree (verified in code review — see `_anonymousReconcileAttempted` field at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L51), `SignOutScope` import at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L11), and existing test file at [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart)). Task 3 (the `_initializeAuth` invocation) is the only source change that must be revised; Task 5 (the test file) is extended with newly-achievable Tier-1 coverage.

1. **(already done — verify only)** In [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L11), `import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;` is present. No change needed.
2. **(already done — verify only)** In `_AuthGateState`, `bool _anonymousReconcileAttempted = false;` is present at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L51). No change needed.
3. **(REVISED — this is the correctness fix)** In `_initializeAuth()`, **replace** the current direct invocation at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L191-L194):
   ```dart
   if (authState.isAuthenticated &&
       supabase.auth.currentUser?.isAnonymous == true) {
     unawaited(_reconcileOrphanedAnonymousSession());
   }
   ```
   with the post-frame-scheduled form:
   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) {
     if (mounted &&
         authState.isAuthenticated &&
         supabase.auth.currentUser?.isAnonymous == true) {
       unawaited(_reconcileOrphanedAnonymousSession());
     }
   });
   ```
   Notes for the reviewer/self-check:
   - `authState` is captured from the enclosing `_initializeAuth` closure. It cannot have transitioned between initState and the first post-frame callback because no Riverpod listener has fired yet.
   - `mounted` and `supabase.auth.currentUser?.isAnonymous` are re-read at callback time as defense against widget disposal or session invalidation between initState and the next frame.
   - This form matches the safe pattern already used at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L136-L145) (lifecycle-resume `refreshSession`) and [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L529-L531) (`_checkProfileComplete` from `_buildAuthContent`).
   - Do **not** wrap `_checkProfileComplete()` at [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L188) in `addPostFrameCallback`; it is already safe when called directly (see §Cycle 4 Revision Note).
4. **(already done — verify only)** The private method `_reconcileOrphanedAnonymousSession()` implementation exists and is unchanged by this revision:
   ```dart
   Future<void> _reconcileOrphanedAnonymousSession() async {
     if (_anonymousReconcileAttempted) return;
     _anonymousReconcileAttempted = true;
     try {
       await ref.read(activeBandProvider.notifier).loadUserBands();
       if (!mounted) return;
       final hasBands =
           ref.read(activeBandProvider).userBands.isNotEmpty;
       final stillAnonymous =
           supabase.auth.currentUser?.isAnonymous == true;
       if (!hasBands && stillAnonymous) {
         AuthDebugLogger.error(
           step: 'reconcileOrphanedAnonymousSession',
           message:
               'Orphaned anonymous session — signing out globally to break restore loop.',
         );
         await supabase.auth.signOut(scope: SignOutScope.global);
       }
     } catch (e) {
       AuthDebugLogger.error(
         step: 'reconcileOrphanedAnonymousSession',
         message: 'Reconcile failed: $e',
       );
     }
   }
   ```
5. **(EXTENDED — new Tier-1 coverage now achievable)** In [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart), keep the existing three tests (A/B/C — unauthenticated-guard checks). Update the top-of-file Tier-2 rationale block to reflect that the "modify provider during build" exception no longer occurs (the deferral fixes it). Then add the two new tests described in §Verification Plan Tier 1, using either `Supabase.instance.client.auth.setSession` with a hand-crafted anonymous JWT payload (preferred — simpler) or, if `setSession` cannot reliably produce `isAnonymous == true` offline, a minimal mock `httpClient` passed to `Supabase.initialize` (fallback). If **neither** priming path proves feasible after honest effort, leave the two anonymous scenarios in Tier-2 with an updated rationale block stating precisely which priming attempt failed and why — do **not** ship half-working tests.
6. **(already done — verify only)** Run `flutter analyze` locally and confirm zero new warnings/errors introduced in [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart). Do not modify unrelated files to satisfy the linter.

That is the entire implementation for this revision. Do not add helpers, do not refactor `_checkProfileComplete`, do not touch `_buildAuthContent`, do not touch the `_sessionSyncTimer`, do not touch the missing-SVG asset issue (see Out of Scope).

## Verification Plan

### Tier 1 — pre-deploy widget tests (extend existing [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart))

**What the deferral changes for offline testability.** Prior cycle's synchronous invocation caused Riverpod to throw `"Tried to modify a provider while the widget tree was building."` at the moment the reconcile awaited `loadUserBands()`, which Engineer confirmed in the widget-test harness (see the Tier-2 rationale block at [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart#L14-L25)). With the post-frame deferral, a widget test can `pumpAndSettle` past the callback without the exception firing. That unblocks two pieces of the reconcile that were previously offline-infeasible:

- **Poppable now:** `ref.read(activeBandProvider.notifier).loadUserBands()` is invoked from inside the reconcile → the `_FakeActiveBandNotifier._counter` used in the existing test file records the call.
- **Poppable now:** The empty-check decision (`ref.read(activeBandProvider).userBands.isEmpty`) reads the caller-controlled state produced by `_FakeActiveBandNotifier.loadUserBands()`, so the `!hasBands` branch is deterministically driven.

**Still infeasible offline (remain Tier-2):**

- **Real `signInAnonymously()`** — a live HTTP round trip to `POST /auth/v1/signup` on the real Supabase project. There is no in-process seam to produce a genuine anonymous JWT/refresh-token pair.
- **Real `signOut(scope: SignOutScope.global)` admin endpoint** — a live HTTP call to `POST /auth/v1/logout?scope=global`. Its purpose (server-side refresh-token revocation) is only observable against a real backend; a widget test can only observe the local-storage clear side effect (which happens **before** the network call per `gotrue_client.dart:1075-1104`).

**Priming approach for the two new tests.** To drive the reconcile with `currentUser?.isAnonymous == true` without a real network call, the recommended path is `Supabase.instance.client.auth.setSession` with a hand-crafted JWT payload whose `is_anonymous` claim is `true`. `GoTrueClient.setSession` parses the JWT locally to populate `currentUser` — no HTTP round trip. If this proves unreliable (e.g., the SDK version rejects an unsigned or malformed JWT), the fallback is a minimal `httpClient: MockClient(...)` passed to `Supabase.initialize` in `setUpAll` with a single canned response for `POST /auth/v1/signup` (returns a body with `user.is_anonymous = true`) and a canned 204 for `POST /auth/v1/logout?scope=global`. Engineer picks whichever proves cleanest; if **neither** works after honest effort, keep the two anonymous scenarios in Tier-2 and record the specific failure mode in the test file's rationale block.

**Existing tests to retain (unchanged behavior after the deferral):**

- **Test A — no session with bands available, guard blocks loadUserBands.** With no primed session and `_FakeActiveBandNotifier([band1])` overriding `activeBandProvider`, pump the AuthGate. Assert the guard (`authState.isAuthenticated`) prevents the reconcile from firing: `_LoadCounter.count == 0`. LoginScreen renders.
- **Test B — no session, multi-pump, counter stays 0.** Same as A but pump multiple frames to confirm the post-frame callback (now present) does not somehow schedule the reconcile when `isAuthenticated == false`.
- **Test C — no session → LoginScreen.** Confirms the unauthenticated branch renders `LoginScreen` and the reconcile counter is 0.

**New tests to add (offline-achievable via the post-frame deferral + session priming):**

- **Test D — Anonymous session, empty bands override → reconcile calls loadUserBands and initiates signOut.** Prime the anonymous session in `setUp` via `setSession` (or mock HTTP fallback). Override `activeBandProvider` with `_FakeActiveBandNotifier([])`. Pump the AuthGate and `pumpAndSettle`. Assert:
  - `_LoadCounter.count == 1` — the reconcile invoked `loadUserBands` exactly once.
  - `Supabase.instance.client.auth.currentSession == null` after settle — even though the offline `signOut(global)` admin HTTP call fails, `gotrue_client._signOut` synchronously clears local storage **before** the network call, so `currentSession` transitions to `null` regardless. This is the observable signal that the reconcile reached the signOut path.
  - Optional (only if `AuthDebugLogger` exposes a test hook): the `'Orphaned anonymous session'` log line was emitted exactly once.
- **Test E — Anonymous session, one-band override → reconcile calls loadUserBands but does NOT initiate signOut.** Same priming as Test D. Override `activeBandProvider` with `_FakeActiveBandNotifier([band1])`. Pump and settle. Assert:
  - `_LoadCounter.count == 1`.
  - `Supabase.instance.client.auth.currentSession != null` after settle — the session is preserved because `hasBands == true` short-circuits the signOut.
  - `Supabase.instance.client.auth.currentUser?.isAnonymous == true` — still anonymous, not signed out.

**Explicit boundary — what remains Tier-2 for these scenarios:**

- Server-side confirmation that `SignOutScope.global` revoked the refresh token (only observable via the real Supabase admin API or by attempting to restore the session from another device — inherently a real-backend concern).
- The macOS restore-loop check (verifying no `tokenRefreshed`/`signedIn` fires after the recovery signOut) — Test D asserts local-state clear, but the loop originates from a live server-side refresh-token remaining valid, so end-to-end verification of the fix requires a real Supabase backend.

Never call `provision_demo_session` or any network RPC in Tier 1. `flutter test` must pass offline.

### Tier 2 — on-device manual verification (post-deploy of the branch build)

Each device test requires cleaning up the anonymous user between runs — either via the Supabase dashboard (delete the `auth.users` row for the test anonymous user) or by tapping **Exit Demo** from the app menu before repro.

1. **Orphaned iOS cold start.** On "Tonys iPhone", enter the demo. Force-quit the app. In Supabase, DELETE the `demo_sessions` row and the anonymous `auth.users` row for that visitor (this simulates the cron sweep). Relaunch. **Pass:** LoginScreen appears within a few seconds; no infinite spinner. Check debug logs for exactly one `reconcileOrphanedAnonymousSession — Orphaned anonymous session` line. No subsequent `onAuthStateChange:signedIn` or `tokenRefreshed` events after the recovery.
2. **Orphaned macOS cold start (loop check).** Repeat #1 on macOS. **Pass:** LoginScreen appears; the debug log shows exactly one `signedOut` event with no subsequent `tokenRefreshed`/`signedIn`. Explicitly a **fail** if any `onAuthStateChange:tokenRefreshed` or `signedIn` fires after the recovery signOut.
3. **Valid anonymous cold start (happy path).** On iOS, enter the demo. Force-quit the app without any server-side cleanup. Relaunch. **Pass:** AppShell loads with "The Banana Stand" (or Modal Nodes) selected as the active band. No LoginScreen.
4. **Real-user cold-start regression check.** Log in as a real (non-anonymous) BandRoadie user with at least one band. Force-quit the app. Relaunch. **Pass:** AppShell loads with the user's previously active band selected. No LoginScreen, no NoBandShell. Debug log shows no `reconcileOrphanedAnonymousSession` line at all. This is the mandatory regression check the Feature Input calls out.
5. **Real-user with zero bands regression check.** Log in as a real user, delete their only band membership (Supabase dashboard). Force-quit. Relaunch. **Pass:** NoBandShell renders (or, if the missing-SVG issue tracked separately makes NoBandShell crash on render, log that separately — see Out of Scope). No spinner hang, no `reconcileOrphanedAnonymousSession` line.

### Idempotency check

The recovery's `signOut(scope: SignOutScope.global)` invalidates the refresh token server-side. Confirm on macOS Tier 2 #2 that immediately after the recovery, killing the app and relaunching does **not** re-enter a `tokenRefreshed → signedIn → hang` cycle — instead the LoginScreen appears cleanly because there is no valid refresh token to restore.

## QA Regression Areas

QA should verify, in addition to the specific Tier 2 checks above:

- Magic-link login on iOS, macOS, Android, and web — full round trip. Cold-start recovery must not affect the `pkce`/`detectSessionInUri` handshake.
- Deep-link handling on iOS/macOS via `DeepLinkService` for a fresh magic link tapped from Mail. Recovery does not run for these (initial session is null; the deep link brings the user into a real, non-anonymous session).
- Fresh demo entry from LoginScreen: tap "Check Out the Demo Band" and confirm the Banana Stand loads. This exercises the fresh-entry race window that the plan explicitly preserves.
- Exit Demo from the app menu. `DemoSessionService.exit` calls `signOut()` (currently default scope) — that path is untouched by this fix; the plan does **not** change `Exit Demo` behavior. If QA observes any Exit-Demo regression, that is a separate defect.

## Rollout Strategy

Single commit on the existing `feature/interactive-demo-band-experience` branch. **Do not** cut a new branch off `main` and do not rebase — per the Feature Input, this bug only exists in this branch's uncommitted working tree, and a fresh branch off `main` would not contain the demo feature at all. Work continues in-place. When Engineer commits, the diff will span only [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart) and the new test file, on top of the existing demo-feature working-tree changes. No separate PR; this fix ships with the same PR as the demo feature.

## Out of Scope

- **Missing SVG assets (`bandroadie_logo_optimized.svg`, `bandroadie_logo_rose_tag.svg`).** Confirmed both are absent from disk. `bandroadie_logo_rose_tag.svg` is referenced by [lib/features/shell/no_band_shell.dart](lib/features/shell/no_band_shell.dart#L483) and [lib/features/legal/privacy_policy_screen.dart](lib/features/legal/privacy_policy_screen.dart#L30). `bandroadie_logo_optimized.svg` is referenced by the `BandRoadieLogo` default and `AnimatedBandRoadieLogo` in [lib/shared/widgets/animated_logo.dart](lib/shared/widgets/animated_logo.dart#L23-L39). Neither surface is in the flow of this bug: the recovery lands users at LoginScreen, which uses `assets/images/bandroadie_logo_stacked.png` (present on disk) via `login_screen.dart:536`. Bundling an asset restore into this fix would expand scope beyond the root cause and risk touching unrelated screens. Rationale for tracking separately: the missing SVGs pre-exist on this branch and affect a distinct set of screens (NoBandShell, Privacy) reachable through independent flows that are not implicated in the cold-start hang. File a follow-up as `bug/missing-logo-svg-assets` and address before merge of this branch to `main`.
- **`DemoSessionService.exit` sign-out scope.** Exit Demo currently uses default (local) scope. Changing it would be a distinct behavior change with its own review; the current bug is exclusively about cold-start recovery. Track as a separate hardening ticket if desired.
- **`_sessionSyncTimer` and lifecycle-resume `refreshSession`.** Left as-is. They protect iPad multitasking and cannot cause the described hang given the recovery fix.
- **Anonymous-session heartbeat and demo cleanup cron.** Unchanged; the RPC and cron logic already correctly delete orphaned anonymous rows — that is exactly the cleanup that produces the "orphaned session" state this bug recovers from.
- **Any RLS or RPC changes.** None needed. `loadUserBands()`'s underlying `band_members` query already returns empty cleanly for orphaned anonymous users under the existing RLS policies; the recovery consumes that empty result correctly.
