# ENGINEER REPORT

## Feature Slug

`bug/demo-cold-start-stale-anon-session`

## Feature Title

App hangs on a black screen with a perpetual loading spinner when the app is
cold-started while a stale/orphaned anonymous demo session is persisted on
the device.

## Cycle Number

7

## Goal

**Cycle 7 (bounded revision).** Address the two blocking issues from the Cycle 6
QA verdict (REQUIRES CHANGES), touching only
`test/features/auth/auth_gate_anonymous_recovery_test.dart`:

- **C1 (Critical)** — rewrite the stale top-of-file Tier-2 rationale block, which
  still described the build-phase Riverpod mutation exception as the reason
  Tests D/E were deferred. That exception was resolved by the
  `addPostFrameCallback` deferral; the rationale was factually wrong.
- **W1 (Warning)** — make an honest offline implementation attempt at Tests D and
  E using the plan's `setSession` anonymous-JWT priming approach (plus the fake
  notifier override), and either add the tests or record the precise failure
  mode.

`auth_gate.dart` was **not** modified this cycle — the validated core fix is
unchanged. Cycles 1–6 history is retained below for continuity.

---

## Cycle 7 Work

### C1 — stale Tier-2 rationale rewritten (done)

The top-of-file comment block was rewritten. It now states:

- The build-phase Riverpod exception ("Tried to modify a provider while the
  widget tree was building") was **resolved** by the `addPostFrameCallback`
  deferral in `auth_gate.dart` — it no longer describes a defect that exists.
- Tests D and E are now **Tier-1** (offline). The only remaining Tier-2 boundary
  is server-side confirmation that `SignOutScope.global` revoked the refresh
  token (observable only against a real backend / second device) and the
  end-to-end macOS restore-loop check.

### W1 — Tests D and E implemented offline (done)

**Honest attempt at the plan's named `setSession` path — found infeasible, with a
specific failure mode.** The plan's premise was that
`setSession(refreshToken, accessToken:)` "populates `currentUser` locally with no
HTTP round trip." That is **not true for the resolved SDK version**
(gotrue 2.27.2). `GoTrueClient.setSession`, when given a non-expired
`accessToken`, calls `getUser(accessToken)` (gotrue_client.dart:962) — a live
`GET /auth/v1/user` HTTP round trip — to build the `User`. Offline against the
dummy `test.supabase.co` endpoint that call cannot succeed, so `setSession`
cannot prime `currentUser.isAnonymous == true` without a network.

**Working offline equivalent used instead — `recoverSession` + MockClient.** Per
the plan's explicit latitude ("Engineer picks whichever proves cleanest … the
fallback is a minimal `httpClient: MockClient(...)`"), the tests prime the
session via `GoTrueClient.recoverSession(jsonStr)`, which achieves the plan's
actual stated goal — populate `currentUser` locally with no HTTP round trip:

- `recoverSession` parses a hand-crafted session JSON locally. `User.isAnonymous`
  is read from the embedded `user.is_anonymous` field (user.dart:91), and the
  access-token JWT is decoded **without signature verification** (helper.dart
  `decodeJwtPayload`), so a hand-crafted token with a future `exp` and
  `is_anonymous: true` works. For a non-expired session it calls `_saveSession`
  and fires `tokenRefreshed` — **no network call** (gotrue_client.dart:1258–1287).
- The existing fake `activeBandProvider` override makes `loadUserBands()` a
  no-network in-memory call.
- A `MockClient` is passed to `Supabase.initialize` (the plan's documented
  fallback) answering the single offline network call the reconcile makes —
  `signOut(global)`'s admin logout — with a 204, so the local session clear
  isn't masked by an unhandled connection error. `autoRefreshToken: false` and
  `persistSession: false` keep the harness deterministic (no refresh ticker
  touching primed sessions, no cross-test storage leakage).

**Test D — anonymous session, zero bands.** Primes the anonymous session,
overrides `activeBandProvider` with an empty fake, pumps once. Asserts
`loadUserBands` was called exactly once and `currentSession == null` after the
reconcile — `signOut(global)` clears the local session synchronously (via
`_removeSession`, gotrue_client.dart:1046) **before** its network call, so the
clear is offline-observable. Deliberately does not pump further: the next frame
would build the transient authenticated-but-no-user state that renders
`NoBandShell`, whose logo SVG is a known out-of-scope missing asset.

**Test E — anonymous session, one band.** Primes the session, overrides with a
fake whose `build()` reports no bands (lightweight anonymous spinner) but whose
`loadUserBands()` resolves to one band with `isLoading: true`. The `isLoading`
flag keeps any AuthGate rebuild on the loading-spinner branch instead of
building the heavy `AppShell` (which spins up `HomeTabContent` timers/network
and would leave a pending timer), while the reconcile's `userBands.isNotEmpty`
check still sees the band. Asserts `loadUserBands` called once, the session is
preserved (`currentSession != null`), and the user is still anonymous — i.e. the
reconcile did **not** sign out.

Both tests pass reliably offline; the full file was run three times with no
flakiness (see Test Results).

---

## Source Change Summary

**File:** `lib/features/auth/auth_gate.dart`

Three additions, no deletions:

1. **Import** — `show SignOutScope` import from `package:supabase_flutter/supabase_flutter.dart`
   (the file previously imported only the internal `supabase_client.dart` re-export,
   which does not surface `SignOutScope`).

2. **Field** — `bool _anonymousReconcileAttempted = false;` added alongside the
   existing `_AuthGateState` boolean fields.

3. **Guarded call** — inside `_initializeAuth()`, after the existing
   `_checkProfileComplete()` / `_registerPushToken()` block:

   ```dart
   if (authState.isAuthenticated &&
       supabase.auth.currentUser?.isAnonymous == true) {
     unawaited(_reconcileOrphanedAnonymousSession());
   }
   ```

4. **Method** — `_reconcileOrphanedAnonymousSession()` (private, async):
   - Sets `_anonymousReconcileAttempted = true` synchronously (before the first
     `await`) to prevent re-entry.
   - `await ref.read(activeBandProvider.notifier).loadUserBands()`
   - `if (!mounted) return;`
   - If `activeBandProvider.userBands.isEmpty` AND user is still anonymous:
     `await supabase.auth.signOut(scope: SignOutScope.global)` — uses `global`
     scope to revoke the refresh token server-side, breaking the macOS
     `signOut(local)` ↔ `tokenRefreshed` restore loop (Failure B).
   - Wrapped in `try/catch` with `AuthDebugLogger.error` — no rethrow.

Net change: +35 lines.

### Cycle 4–5 revision: callsite deferral

The original synchronous `unawaited(_reconcileOrphanedAnonymousSession())` call
inside `_initializeAuth()` had a latent defect: the synchronous prefix of the
`async` method ran before the first `await`, which caused
`ref.read(activeBandProvider.notifier)` to mutate a Riverpod provider while the
widget tree was still building. Riverpod throws internally on that mutation;
the `try/catch` in `_reconcileOrphanedAnonymousSession` swallowed the exception,
and `signOut(scope: SignOutScope.global)` never executed on the orphaned path.
The fix silently no-op'd without any visible error.

The callsite was changed to:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted &&
      authState.isAuthenticated &&
      supabase.auth.currentUser?.isAnonymous == true) {
    unawaited(_reconcileOrphanedAnonymousSession());
  }
});
```

Scheduling via `addPostFrameCallback` defers the provider mutation until after
the build phase completes. The `mounted && isAuthenticated && isAnonymous` guard
is re-evaluated inside the callback so no stale-closure hazard exists.
`signOut(scope: SignOutScope.global)` now actually executes on the orphaned path.

---

## Architect Tasks Completed

| Task                                              | Status |
| ------------------------------------------------- | ------ |
| Add `show SignOutScope` import                    | ✅     |
| Add `_anonymousReconcileAttempted` field          | ✅     |
| Add guarded call in `_initializeAuth()`           | ✅     |
| Add `_reconcileOrphanedAnonymousSession()` method | ✅     |
| Tier-1 widget tests (unauthenticated guard path)  | ✅     |

---

## Files Created

| File                                                                      | Purpose             |
| ------------------------------------------------------------------------- | ------------------- |
| `test/features/auth/auth_gate_anonymous_recovery_test.dart`               | Tier-1 widget tests |
| `docs/features/bug/demo-cold-start-stale-anon-session/ENGINEER_REPORT.md` | This file           |

## Files Modified

| File                                                        | Change                                                                                                                                             |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/auth_gate.dart`                          | Source fix (cycles 1–2); callsite deferral via `addPostFrameCallback` (cycles 4–5); **not modified in cycle 7**                                    |
| `test/features/auth/auth_gate_anonymous_recovery_test.dart` | Isolation fix (cycle 3); **cycle 7:** rationale block rewritten (C1), Tests D and E added offline via `recoverSession` + `MockClient` priming (W1) |

---

## Analyzer Results

**`test/features/auth/auth_gate_anonymous_recovery_test.dart`** (Cycle 7)

```
No issues found!
```

Analyzer clean at every severity after the Cycle 7 changes (`dart fix --dry-run`
reported no suggested fixes for the file).

**`lib/features/auth/auth_gate.dart`** — not modified this cycle; unchanged from
Cycle 6 (13 pre-existing `info`-level lints, zero errors/warnings).

---

## Test Results

```
flutter test test/features/auth/auth_gate_anonymous_recovery_test.dart
00:00 +5: All tests passed!
```

Run three consecutive times (Cycle 7) — `+5` every time, no flakiness.

```
Test A — no session, notifier has bands → guard blocks (counter 0)
Test B — no session, multi-pump → counter 0
Test C — no session → LoginScreen, counter 0
Test D — anonymous primed, zero bands → counter 1, currentSession null (signed out)
Test E — anonymous primed, one band → counter 1, session preserved, still anonymous
```

Debug output confirms the reconcile ran end-to-end: Test D logged
`reconcileOrphanedAnonymousSession — Orphaned anonymous session — signing out
globally`; Test E produced no sign-out log (session preserved).

---

## Test Coverage & Limitations

### Tier-1 Tests (this file, fully offline) — 5 tests, all passing

| ID  | Scenario                               | Assertion                                              |
| --- | -------------------------------------- | ------------------------------------------------------ |
| A   | No session, notifier has bands         | `loadUserBands` counter = 0; LoginScreen rendered      |
| B   | No session, empty bands, 3 pump cycles | counter stays 0 across all pumps; LoginScreen rendered |
| C   | No session, empty bands, 1 pump        | counter = 0; LoginScreen rendered                      |
| D   | Anonymous session primed, zero bands   | counter = 1; `currentSession == null` (signed out)     |
| E   | Anonymous session primed, one band     | counter = 1; session preserved; still anonymous        |

A–C target the `isAuthenticated == false` guard; D–E (new this cycle) prime a
genuine anonymous session offline via `recoverSession` and exercise the
reconcile decision end-to-end (loadUserBands invocation + the sign-out /
no-sign-out branch).

### Isolation fix (cycle 3)

**Root cause of in-suite failure:** ForUI's `FTheme`/`FScaffold` leaves
rendering frame state between widget tests that shrinks the effective
`LayoutBuilder` height constraint to ~300 logical px in the third test run.
The `LoginScreen` `_buildContentCluster` column then overflows by 173 px
(content ~473 px vs. constrained 300 px). The fix is two lines per test:

```dart
tester.view.physicalSize = const Size(2400, 3600); // 800×1200 logical @ DPR 3
addTearDown(tester.view.resetPhysicalSize);
```

A `tearDown(() async { try { await Supabase.instance.client.auth.signOut(); } catch (_) {} })` is also added at the `main()` level to prevent Supabase singleton auth-state leakage between tests (per Manager requirement; belt-and-suspenders alongside the view reset).

### Tier-2 — remaining on-device manual verification (narrowed this cycle)

With Tests D and E now offline (Cycle 7), the only items that remain Tier-2 are
the genuinely server-side / real-backend concerns — these cannot be observed
offline by any priming technique:

| Scenario                                                                | Reason still Tier-2                                                                                                                                                                                                                                      |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `signOut(scope: global)` actually revoked the refresh token server-side | The revocation is a real admin HTTP effect on the Supabase backend. Test D asserts the **local** session clear that `signOut` performs before its network call; the server-side revocation is only observable against a real project or a second device. |
| macOS `signOut(local)` ↔ `tokenRefreshed` restore loop is broken        | The loop originates from a still-valid server-side refresh token, so end-to-end confirmation requires a real backend and a real cold start.                                                                                                              |

---

## Verification (manual steps performed)

**Cycle 7:**

1. Read gotrue 2.27.2 source to confirm `setSession(accessToken:)` calls
   `getUser` (network) and that `recoverSession` + non-expired JWT is fully
   offline; confirmed `signOut` clears the local session before its network call
   and `Base64Url.decodeToString` normalizes JWT padding.
2. Confirmed `http` is a direct dependency (`http: ^1.6.0`) — `MockClient`
   imported without a `depend_on_referenced_packages` lint.
3. `flutter analyze test/features/auth/auth_gate_anonymous_recovery_test.dart`
   → No issues found.
4. `flutter test test/features/auth/auth_gate_anonymous_recovery_test.dart`
   → 5/5 passed; ran 3× for determinism, `+5` each time.
5. `dart fix --dry-run` → no suggested fixes for the file.
6. `dart format` applied to the test file; re-ran tests → still 5/5.

**Earlier cycles:**

1. Confirmed `flutter analyze lib/features/auth/auth_gate.dart` — 13 pre-existing
   `info` lints, zero errors/warnings.
2. Confirmed `flutter analyze test/features/auth/auth_gate_anonymous_recovery_test.dart`
   — no issues.
3. `flutter test test/features/auth/auth_gate_anonymous_recovery_test.dart` → 3/3 passed.
4. Per-test (`--plain-name "Test A"`, `"Test B"`, `"Test C"`) → each 1/1 passed.
5. `dart format` applied to test file; re-ran tests → still 3/3.

---

## Deviations From Plan

**Cycle 7 — priming mechanism.** The plan named `setSession` (with a mock-HTTP
fallback) as the recommended offline priming path and explicitly left the choice
to the Engineer ("picks whichever proves cleanest"). `setSession` proved
infeasible offline in the resolved SDK version — it calls `getUser` (a network
round trip) — so priming uses `GoTrueClient.recoverSession` instead, which meets
the plan's actual stated goal (populate `currentUser` locally, no HTTP). The
plan's documented `MockClient` fallback is used for the single reconcile
network call (`signOut(global)`'s logout). This is within the plan's stated
latitude, not a scope expansion; no source/`auth_gate.dart` change was made.

**Earlier cycles.** The `physicalSize` test setup is an implementation detail of
making the tests reliable, not a scope change.

---

## Blockers Encountered

**Cycle 7:** Two offline-rendering hazards surfaced while building Tests D/E,
both resolved within the test file (no `auth_gate.dart` change):

- Test E initially rendered `AppShell` after the reconcile populated bands,
  leaving a pending `HomeTabContent` timer that failed the test. Resolved by
  having the fake's post-load state carry `isLoading: true`, keeping AuthGate on
  its loading-spinner branch while still exposing non-empty `userBands` to the
  reconcile.
- Test D must not pump past the reconcile's frame: the subsequent transient
  authenticated-but-no-user frame renders `NoBandShell` (out-of-scope missing
  logo SVG). Resolved by asserting after a single pump (the local session clear
  is already observable then).

**Cycle 3:** The in-suite Test C failure was a `RenderFlex` overflow (173 px)
caused by ForUI frame-state leakage shrinking the `LayoutBuilder` height to 300 px
in the third widget test of any sequence rendering `FTheme`+`LoginScreen`. Resolved
by per-test `tester.view.physicalSize` reset.

**Cycles 4–5:** The synchronous `unawaited(...)` callsite in `_initializeAuth()`
mutated `activeBandProvider` during the build phase; Riverpod's internal throw was
swallowed by the `try/catch`, causing `signOut(global)` to silently no-op. Fixed by
deferring the call via `addPostFrameCallback` with a re-evaluated
`mounted && isAuthenticated && isAnonymous` guard.

---

## Code Efficiency / Bloat Check

- No new helpers, extensions, or utilities added to `lib/`.
- No new providers or notifiers.
- Cycle 7 additions are confined to the test file: one priming helper
  (`_primeAnonymousSession`), two constructor params on the existing fake
  notifier (`loadedBands`, `loadedIsLoading`), and the two new tests. Searched
  `test/` for an existing anonymous-session priming helper or JWT builder before
  writing one — none exists.
- `MockClient`/`recoverSession` reuse SDK-provided seams; no bespoke fake HTTP
  layer or session builder abstraction was introduced.
- `tester.view.physicalSize` and `addTearDown` are standard Flutter test idioms;
  no abstraction created for a two-line setup.
- Net line growth is entirely in the test file; no `lib/` file changed this
  cycle.

---

## Ready For QA

Yes — C1 (rationale rewritten) and W1 (Tests D and E implemented offline and
passing) are both complete; analyzer clean, 5/5 tests passing deterministically.
The `setSession`-vs-`recoverSession` finding is documented above for Architect
visibility, but it did not force a Tier-2 deferral (D/E are now Tier-1), so no
Architect sign-off is pending on that account.
