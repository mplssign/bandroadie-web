# QA REPORT

## Feature Slug

`bug/demo-cold-start-stale-anon-session`

## Feature Title

App hangs on a black screen with a perpetual loading spinner when the app is
cold-started while a stale/orphaned anonymous demo session is persisted on the
device.

## Cycle Number

7

## Final Verdict

**APPROVED**

---

## Validation Summary

Cycle 7 was a bounded revision addressing the two Cycle 6 blockers (C1, W1),
touching only `test/features/auth/auth_gate_anonymous_recovery_test.dart` and
the Engineer Report. Both blockers are **genuinely resolved**:

- **C1 (was Critical, `implementation-gap`)** — the stale top-of-file Tier-2
  rationale block was rewritten. It no longer describes the build-phase Riverpod
  "modify a provider while building" exception as a current reason for deferral;
  it correctly states that exception was **resolved** by the
  `addPostFrameCallback` deferral, that Tests D/E are now Tier-1, and that the
  only remaining Tier-2 boundary is server-side refresh-token revocation
  confirmation plus the end-to-end macOS restore-loop check.
- **W1 (was Warning, `implementation-gap`)** — Tests D and E are implemented,
  run fully offline, and pass. The Engineer made an honest attempt at the plan's
  named `setSession` priming path, documented why it is infeasible offline in
  gotrue 2.27.2 (`setSession` → `getUser` → live `GET /auth/v1/user`), and
  implemented the tests via `GoTrueClient.recoverSession` (local, no network)
  plus a `MockClient` answering the single `signOut(global)` logout call — the
  plan's named fallback. The deviation is within the plan's explicit mechanism
  latitude.

The already-validated core fix in `auth_gate.dart` was **not** modified this
cycle (numstat byte-identical to Cycle 6). No regression, no source scope creep.
Analyzer clean on the test file; 5/5 tests pass. Prior non-blocking warnings W2
(demo heartbeat carry-over in `auth_gate.dart`) and W3 (cumulative change
budget) remain non-blocking and are not newly blocked.

---

## Architect Scope Review (Cycle 7)

- Plan slug `bug/demo-cold-start-stale-anon-session` = Report slug = branch
  context (`feature/interactive-demo-band-experience`, per the plan's in-place
  rollout note). ✓
- This cycle's changes are confined to the test file + Engineer Report — within
  the plan's Task 5 scope. `auth_gate.dart` unchanged (`git diff --numstat`
  = `76 6`, identical to Cycle 6). ✓
- No source/migration/config/dependency changes introduced this cycle. ✓
- Working tree is the expected uncommitted demo-feature branch state; nothing is
  committed, which is correct for this pipeline stage (not a defect). ✓

---

## Completeness Check (Cycle 7)

| Cycle 6 blocker | Requirement                                                                                                                          | Status                                                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| C1              | Rewrite the Tier-2 rationale block so it no longer cites the (now-fixed) build-phase Riverpod exception as a current deferral reason | ✅ Done — header block lines 1–42 rewritten; states the exception is RESOLVED and scopes the real remaining Tier-2 boundary |
| W1a             | Honest attempt at the plan's `setSession` anonymous-JWT priming path                                                                 | ✅ Done — attempted, found infeasible offline (live `getUser` HTTP call in gotrue 2.27.2), failure mode documented          |
| W1b             | Add Tests D and E, or record the specific failure mode                                                                               | ✅ Done — Tests D and E added, offline, passing (Tier-1) via `recoverSession` + `MockClient`                                |

All Cycle 6 blocking items complete.

---

## Behavior Verification (Cycle 7)

Method: **code-path analysis + runtime-exercised** (the test suite was executed
locally this cycle; the anonymous-session reconcile decision logic is now run
end-to-end offline, not merely analyzed).

### C1 — rationale accuracy (CONFIRMED, code inspection)

The header block now reads that the build-phase exception "is RESOLVED —
auth_gate.dart now schedules the reconcile via
WidgetsBinding.addPostFrameCallback," and correctly identifies the offline
priming obstacle (`setSession` calls `getUser`) and its resolution
(`recoverSession`). The remaining Tier-2 scope is accurately limited to
server-side `SignOutScope.global` revocation confirmation and the end-to-end
macOS restore-loop check. No stale reference to the fixed defect remains. ✓

### W1 — Tests D and E are genuine, non-cheating (CONFIRMED, runtime-exercised)

- **Priming is genuinely offline.** `_primeAnonymousSession` hand-crafts a JWT
  with `is_anonymous: true` and a future `exp`, wraps it in session JSON, and
  calls `recoverSession`. Both tests assert `currentUser?.isAnonymous == true`
  immediately after priming — this passes with no network available, confirming
  the local-parse claim.
- **`counter == 1` genuinely proves the reconcile fired.** For an anonymous
  session, `_checkProfileComplete()` short-circuits at
  [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L239-L245)
  **without** calling `loadUserBands()`. The reconcile
  (`_reconcileOrphanedAnonymousSession`) is therefore the _only_ code path that
  can increment the fake notifier's counter for an anonymous cold start. A
  passing `counter == 1` is not incidental — it is direct evidence the reconcile
  executed.
- **Test D reaches the sign-out path.** Runtime log emitted exactly once:
  `reconcileOrphanedAnonymousSession — Orphaned anonymous session — signing out
globally to break restore loop.` `currentSession == null` after settle
  confirms `signOut(global)` cleared the local session (which gotrue does
  synchronously before the mocked admin network call). Exercises the
  orphaned-anonymous → `signOut(global)` + local-clear path. ✓
- **Test E preserves the session.** No sign-out log; `currentSession != null`
  and `isAnonymous == true` after settle. Exercises the anonymous-with-bands →
  session-preserved path. ✓
- **Deviation is within plan latitude.** The plan named `setSession` as
  "preferred" but explicitly left the choice to the Engineer ("picks whichever
  proves cleanest") and named `MockClient` as the fallback. The Engineer's
  documented finding (`setSession` → `getUser` → `GET /auth/v1/user` is a live
  round trip in gotrue 2.27.2) is a legitimate reason to use `recoverSession`,
  which meets the plan's actual stated goal (populate `currentUser` locally, no
  HTTP). The `MockClient` handles only the single `signOut(global)` logout call.
  Not a scope expansion; no source change. ✓

### Core fix — no regression (CONFIRMED)

`auth_gate.dart` numstat is byte-identical to Cycle 6. The reconcile method
([lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L299-L322))
and the `addPostFrameCallback` callsite
([lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L193-L199))
match the Cycle 6-validated implementation exactly. Real-user (non-anonymous)
cold start remains gated out by the `isAnonymous == true` guard. ✓

---

## Regression Check (Cycle 7)

| Area                                                | Assessment                                                                                                                                                           | Severity |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Core reconcile fix (`auth_gate.dart`)               | Unchanged this cycle (numstat identical to Cycle 6); method + callsite byte-for-byte as validated                                                                    | LOW      |
| Real-user cold start                                | `isAnonymous == false` guard unchanged; no new code reachable                                                                                                        | LOW      |
| Auth/session (test harness)                         | Tests use `persistSession: false` + `autoRefreshToken: false` + per-test `signOut` teardown; no cross-test session leakage observed across 5 tests                   | LOW      |
| Supabase RPC signatures / init order                | Untouched                                                                                                                                                            | LOW      |
| Platform parity                                     | Test-only change; no platform-conditional code                                                                                                                       | LOW      |
| Controller/FocusNode disposal, setState-after-async | No `auth_gate.dart` change; tests pump a single frame and assert without leaking timers (Test E deliberately keeps `isLoading:true` to avoid AppShell timer spin-up) | LOW      |

Overall regression risk this cycle: **LOW** (test-file-only change on top of an
already-validated source fix).

---

## Database Safety

Not applicable. No migrations, RLS, RPC, trigger, or edge-function changes in the
bug fix or this cycle. (An unrelated demo-feature migration is open in the editor
but is off-limits per the plan and untouched by this fix.) No `SECURITY DEFINER`
functions were added or changed by this work.

---

## Analyzer Results (Cycle 7)

**Command:** `flutter analyze test/features/auth/auth_gate_anonymous_recovery_test.dart`

```
No issues found! (ran in 2.6s)
```

Clean at every severity for the file changed this cycle. `auth_gate.dart` was
not modified this cycle (its pre-existing info-level lints are unchanged and do
not block, per the "file the diff doesn't touch this cycle" rule).

---

## Test Results (Cycle 7)

**Command:** `flutter test test/features/auth/auth_gate_anonymous_recovery_test.dart --reporter=expanded`

```
00:00 +5: All tests passed!
```

- Test A — no session, notifier has bands → counter 0, LoginScreen ✓
- Test B — no session, multi-pump → counter 0, LoginScreen ✓
- Test C — no session → LoginScreen, counter 0 ✓
- Test D — anonymous primed, zero bands → counter 1, `currentSession == null`; log confirms `signOut(global)` path ✓
- Test E — anonymous primed, one band → counter 1, session preserved, still anonymous ✓

Runtime debug output independently corroborates D (sign-out log emitted once) and
E (no sign-out log).

---

## Diff Safety Review (Cycle 7)

| Check                         | Result                                                                                                                                                                                    |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Secrets / API keys            | None (grep of test file: no `apiKey`/`secret`/`service_role`/`password`). The `publishableKey: 'test-anon-key'` and hardcoded `signature` string are inert test literals, not credentials |
| `debugPrint(` in test file    | None                                                                                                                                                                                      |
| `TODO` / `FIXME` in test file | None                                                                                                                                                                                      |
| Leftover test scaffolding     | None                                                                                                                                                                                      |
| Accidental deletions          | None (test file is a new/untracked file; `auth_gate.dart` unchanged this cycle)                                                                                                           |
| Unrelated formatting churn    | None                                                                                                                                                                                      |

---

## Change Budget Review (Cycle 7)

- `auth_gate.dart`: `git diff --numstat` = `76 6`, **identical to Cycle 6** —
  zero new source lines this cycle. Still 1.69× the Cycle-6 bug-fix budget due to
  cumulative cycles 1–2 + demo-feature carry-over, not this cycle's work
  (W3, non-blocking — unchanged).
- Test file: 388 lines total (new/untracked file), 5 tests. The plan budgeted the
  existing multi-test file plus +80–140 lines for Tests D/E; the observed size is
  consistent with that. This is test code with no new `lib/` abstractions.
- Zero new files in `lib/`, zero new public classes, zero new dependencies
  (`http`/`MockClient` is an existing direct dependency), zero pubspec/migration
  changes. ✓

Within budget for this cycle.

---

## Code Efficiency Review (Cycle 7)

- No new `lib/` helpers, providers, notifiers, or abstractions.
- Cycle 7 test additions are confined to: one priming helper
  (`_primeAnonymousSession`), two constructor params on the existing fake
  notifier (`loadedBands`, `loadedIsLoading`), and Tests D/E. Engineer states a
  search for a pre-existing anonymous-priming/JWT helper found none; confirmed no
  such helper exists in `test/`.
- `recoverSession` + `MockClient` reuse SDK-provided seams rather than a bespoke
  fake HTTP layer — appropriate, not over-engineered.
- The `loadedIsLoading` flag is used to keep the rebuild on the spinner branch
  (avoiding AppShell timer spin-up) — a real, load-bearing test-determinism need,
  not gratuitous config. Acceptable.
- No AI-shaped bloat (no single-use `_buildX()`, no re-fetching `FutureBuilder`,
  no dead fields).

No Critical- or Warning-level efficiency findings this cycle.

---

## Issues Found (Cycle 7)

### Critical

None.

### Warnings

None newly raised this cycle. Carry-over non-blocking items, re-confirmed as
non-blocking (not re-blocked):

- **W2 (`out-of-scope`) — demo heartbeat additions in `auth_gate.dart`.** Demo
  feature carry-over from cycles 1–2 (`_lastDemoHeartbeatAt`, heartbeat block,
  `demo_session_service` import). Not modified this cycle. Gated to anonymous
  users, no interaction with the reconcile path. Expected on this branch;
  remains non-blocking.
- **W3 (`code-quality`) — cumulative change budget 1.69×.** Attributable to
  cumulative prior-cycle + demo-feature additions; zero new source lines this
  cycle. Remains non-blocking.

### Suggestions

- **S1 (`code-quality`, carry-over) — 1 pre-existing info lint at
  [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L649)**
  (`avoid_redundant_argument_values`, `type: ProgressIndicatorType.circular`).
  Info-level, in demo-feature code, not touched this cycle. Non-blocking.

---

## Verdict Rationale

All APPROVED criteria are met: plan match, both Cycle 6 blockers (C1, W1)
genuinely resolved, no regression to the validated core fix, no source scope
creep, DB safety n/a, analyzer clean on the changed file, all required tests
pass, no secrets/debug artifacts, no Critical-level bloat. The remaining Tier-2
on-device verification (plan §Verification Plan Tier 2, items 1–5 — orphaned iOS
cold start, macOS loop check, valid anonymous happy path, real-user regression
checks) is a real-backend concern that is **out of scope for offline QA** and
must still be performed on-device before this branch merges to `main`; it does
not block this APPROVED verdict.

---

---

# QA REPORT (Cycle 6 — superseded)

## Feature Slug

`bug/demo-cold-start-stale-anon-session`

## Feature Title

App hangs on a black screen with a perpetual loading spinner when the app is
cold-started while a stale/orphaned anonymous demo session is persisted on the
device.

## Cycle Number

6

## Final Verdict

**REQUIRES CHANGES**

---

## Validation Summary

The core bug fix in `auth_gate.dart` is **correctly implemented**: the
`addPostFrameCallback` deferral resolves the Cycle 4 build-phase Riverpod
mutation defect, the reconcile method is structurally sound, and real-user cold
starts are completely unaffected. All three Tier-1 widget tests pass.

Two issues block APPROVED status:

1. **Critical (implementation-gap)** — Task 5 (test file extension) is
   partially complete. The plan explicitly required updating the Tier-2
   rationale block to reflect that the build-phase Riverpod exception no longer
   occurs. The test file was left untouched in cycles 4–6; the rationale block
   still describes the pre-deferral defect as the reason for Tier-2 deferral,
   which is now factually incorrect and contradicts the fix.

2. **Warning (implementation-gap)** — The plan required attempting the `setSession`
   anonymous-JWT priming path (and the mock-HTTP fallback) before deferring
   Tests D and E to Tier-2. No attempt is documented; the rationale records only
   the old build-phase reason, not any "specific failure mode" of the new priming
   approaches as the plan required.

---

## Architect Scope Review

- Plan slug: `bug/demo-cold-start-stale-anon-session` ✓
- Report slug: `bug/demo-cold-start-stale-anon-session` ✓
- Branch: `feature/interactive-demo-band-experience` ✓ (matches plan's rollout
  note — fix ships in-place on the demo feature branch)
- Cycle 4 Revision Note: present in plan, callsite deferral is the subject of
  this validation ✓
- Plan and report slugs match each other and the branch context ✓

---

## Completeness Check

| Task | Plan Requirement                                                          | Status                                                 |
| ---- | ------------------------------------------------------------------------- | ------------------------------------------------------ |
| 1    | `show SignOutScope` import                                                | ✅ present at auth_gate.dart:11                        |
| 2    | `bool _anonymousReconcileAttempted = false;` field                        | ✅ present at auth_gate.dart:51                        |
| 3    | Replace direct `unawaited(...)` with `addPostFrameCallback` wrapper       | ✅ auth_gate.dart:192–199                              |
| 4    | `_reconcileOrphanedAnonymousSession()` private method                     | ✅ auth_gate.dart:299–326                              |
| 5a   | Update Tier-2 rationale block (no longer describes build-phase exception) | ❌ NOT DONE — rationale is unchanged from prior cycles |
| 5b   | Attempt Tests D and E via `setSession` (or mock HTTP) and document result | ❌ NOT DONE — no attempt documented                    |
| 6    | `flutter analyze` clean                                                   | ✅ (see Analyzer Results)                              |

Tasks 1–4 and 6: **complete**.  
Task 5 (partial): rationale not updated, priming not attempted, Tests D/E not
added. Plan's escape clause ("if neither priming approach proves feasible after
honest effort, record the specific failure mode") was not exercised.

---

## Behavior Verification

Method: **code-path analysis** (no runtime execution of the anonymous
cold-start path; that remains Tier-2 on-device).

### Priority 1 — Deferral resolves the build-phase mutation defect (CONFIRMED)

`_initializeAuth()` is called from `initState`. In the prior cycle design,
`unawaited(_reconcileOrphanedAnonymousSession())` ran synchronously inside
`_initializeAuth`; the reconcile's first `await` targeted
`activeBandProvider.notifier.loadUserBands()`, whose synchronous prefix
(`state = state.copyWith(isLoading: true)`) mutated provider state during the
still-building frame. Riverpod's internal assertion fired; the reconcile's
`try/catch` swallowed it; `signOut(global)` never executed.

The Cycle 4/6 fix (auth_gate.dart:192–199):

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted &&
      authState.isAuthenticated &&
      supabase.auth.currentUser?.isAnonymous == true) {
    unawaited(_reconcileOrphanedAnonymousSession());
  }
});
```

schedules the reconcile for **after** the current build phase. When the callback
fires, `loadUserBands()`'s synchronous prefix executes outside any frame build;
Riverpod's assertion cannot fire. The `try/catch` is now correctly scoped to
genuine runtime errors (network, repository). **The previously-diagnosed
"swallowed exception" defect is resolved by this deferral.** ✓ (code-path
analysis)

The pattern matches two existing safe usages in the same file:

- Lifecycle-resume `refreshSession()` at auth_gate.dart:136–145
- `_checkProfileComplete()` from `_buildAuthContent` at auth_gate.dart:529–531

### Priority 2 — Real (non-anonymous) users unaffected (CONFIRMED)

The `addPostFrameCallback` guard re-evaluates `authState.isAuthenticated &&
supabase.auth.currentUser?.isAnonymous == true` at callback time. For any
non-anonymous session `isAnonymous == false`; the callback body no-ops. No new
code executes for real-user cold starts. The `_checkProfileComplete()` →
`_checkAndProcessPendingInvite()` → `loadUserBands()` path for real users is
byte-for-byte identical to HEAD. ✓ (code-path analysis)

### Priority 3 — One-shot guard, no loop (CONFIRMED)

Two independent guarantees:

- `addPostFrameCallback` registers once (in `_initializeAuth`, called once from
  `initState`); no re-registration path exists.
- `_anonymousReconcileAttempted = true` (auth_gate.dart:301) is set
  synchronously before the first `await`, preventing re-entry if
  `_reconcileOrphanedAnonymousSession` were ever called again.

The `listenManual` auth-state listener (auth_gate.dart:163–178) calls
`_checkProfileComplete()` on `isAuthenticated` transitions, not
`_reconcileOrphanedAnonymousSession`. After the recovery `signOut(global)`,
`isAuthenticated` transitions to `false`; the listener sets state but does not
schedule another reconcile. No loop possible. ✓ (code-path analysis)

`SignOutScope.global` revokes the refresh token server-side, which is the
mechanism that broke the macOS `signOut(local)` ↔ `tokenRefreshed` restore
loop. The `_sessionSyncTimer`'s `refreshSession()` call after a global sign-out
will find no valid refresh token to restore; the loop cannot re-establish.
✓ (code-path analysis; end-to-end macOS loop check remains Tier-2 on-device)

### Priority 4 — Scope discipline (CONFIRMED WITH EXCEPTION)

Only `auth_gate.dart` and the new test file are changed for the bug fix.
Off-limits files (`auth_state_provider.dart`, `demo_session_service.dart`,
`main.dart`, `login_screen.dart` for the fix's purposes) were not modified by
the bug fix. No DB/RLS/RPC/migration/config/dependency changes. The
`DemoSessionService.provisionAndEnter` fresh-demo-entry happy path is not
intercepted — the reconcile fires from `_initializeAuth` (one-time,
post-frame), which is after `provisionAndEnter`'s `loadAndSelectBand` has
already populated `userBands`. ✓

**Exception:** auth_gate.dart also contains demo-feature additions
(`_lastDemoHeartbeatAt`, heartbeat timer block, `import 'demo_session_service.dart'`)
not described in the bug fix plan. See Issues Found §3.

### Priority 5 — Tier-1/Tier-2 test split (ACCEPTABLE WITH CAVEAT)

**Tier-1 (offline, widget tests) — 3 tests all pass.** These cover only the
`isAuthenticated == false` guard. They correctly confirm the reconcile path is
completely bypassed for every unauthenticated cold start regardless of band
state. This is the most important safety check: confirming no regression for
users without a persisted session.

**Tier-2 (on-device manual) — the actual anonymous-session reconcile paths.**
The plan identified that Tests D and E became _partially_ offline-achievable
after the `addPostFrameCallback` fix: `loadUserBands()` invocation
(fake-notifier counter) and the `!hasBands` decision branch are no longer
blocked by the build-phase exception. The network-dependent aspects
(`signInAnonymously` for priming, `signOut(global)` admin revocation for
server-side assertion) remain Tier-2. The plan required attempting anonymous
session priming via `setSession` with a hand-crafted anonymous JWT (or a mock
HTTP client) before falling back, and recording the specific failure mode if
neither worked. This was not attempted and not documented (see Issues Found §1
and §2). Whether this split is ultimately acceptable depends on the Engineer
providing either Tests D/E or a documented priming-failure rationale per the
plan's fallback clause.

---

## Regression Check

| Area                                                    | Assessment                                                                                                                                                                                           | Severity                                |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| Real-user cold start                                    | `isAnonymous == false` guard blocks all new code — byte-for-byte identical to HEAD path                                                                                                              | LOW                                     |
| Magic-link / PKCE login flow                            | Recovery fires only for already-persisted anonymous sessions; `detectSessionInUri` / PKCE handshake is not on the anonymous cold-start path                                                          | LOW                                     |
| Fresh demo entry race window                            | Reconcile fires once in `_initializeAuth`, ~1 frame after `initState`. `provisionAndEnter` awaits `loadAndSelectBand` before returning; bands are populated before the reconcile's `!hasBands` check | LOW                                     |
| macOS restore-loop                                      | `SignOutScope.global` revokes server-side refresh token; the `_sessionSyncTimer` `refreshSession()` cannot restore a globally revoked session                                                        | LOW (on-device Tier-2 confirm required) |
| `_sessionSyncTimer` / lifecycle-resume `refreshSession` | Timer and lifecycle handlers unchanged; heartbeat runs every 60s for anonymous users only (demo feature addition)                                                                                    | LOW                                     |
| iOS / Android / Web                                     | All platforms share the same anonymous-session persistence layer; fix applies uniformly. No platform-conditional code introduced in the reconcile                                                    | LOW                                     |

Overall regression risk: **MEDIUM** (per plan's assessment — cold start path
touched). Mitigations confirmed in code reduce observed risk to LOW across all
checked areas.

---

## Database Safety

Not applicable. No migrations, RLS changes, RPC changes, triggers, or edge
function changes in the bug fix. Confirmed: `supabase/migrations/**` and
`supabase/functions/**` are off-limits and untouched by the bug fix.

---

## Analyzer Results

**Command:** `flutter analyze lib/features/auth/auth_gate.dart test/features/auth/auth_gate_anonymous_recovery_test.dart`

**Outcome:** 13 issues found — all `info` level. Zero `error`, zero `warning`.

**Pre-existing vs new:**

- HEAD baseline has **12** info lints in `auth_gate.dart` (confirmed via stash).
- Working tree has **13** — one new lint introduced.

| Lint                                   | Location           | Source                                                         |
| -------------------------------------- | ------------------ | -------------------------------------------------------------- |
| `prefer_const_constructors` (×8)       | Various            | Pre-existing in HEAD                                           |
| `avoid_redundant_argument_values` (×3) | Various            | Pre-existing in HEAD (3 of 4)                                  |
| `avoid_redundant_argument_values`      | auth_gate.dart:649 | **NEW** — added by `_buildAuthContent` anonymous spinner block |

The new lint at line 649 is `type: ProgressIndicatorType.circular` in the
newly added spinner; `ProgressIndicatorType.circular` is the default value. This
is `info` level only and is in demo-feature code, not the reconcile method.

Test file: **No issues found** ✓

---

## Test Results

**Command:** `flutter test test/features/auth/auth_gate_anonymous_recovery_test.dart --reporter=expanded`

```
00:00 +1: Test A: no session with bands available — reconcile guard blocks loadUserBands
00:00 +2: Test B: no session — loadUserBands counter stays 0 across multiple pump cycles
00:00 +3: Test C: unauthenticated cold start does not invoke recovery
00:00 +3: All tests passed!
```

All 3 Tier-1 tests pass independently and collectively. ✓

---

## Diff Safety Review

| Check                           | Result                                                            |
| ------------------------------- | ----------------------------------------------------------------- |
| Secrets / API keys              | None found                                                        |
| `debugPrint(` in added lines    | None found                                                        |
| `TODO` / `FIXME` in added lines | None found                                                        |
| Leftover test scaffolding       | None                                                              |
| Accidental deletions            | None — only the `NoBandShell` branch wrapped in `else` (expected) |
| Unrelated formatting churn      | None                                                              |

---

## Change Budget Review

**Plan budget:** auth_gate.dart +35 to +45 lines, 0 deletions (Cycle 6 additions only).

**Actual diff:**

```
76      6       lib/features/auth/auth_gate.dart
```

**Explanation of excess:** The diff is cumulative across cycles 1–6 against
HEAD (which has none of the bug fix work committed). The Engineer Report
correctly describes Cycle 6 as +35 lines (the `addPostFrameCallback` block
+7 and the reconcile method +26 and the field +1 and import +1). The remaining
~41 net lines are from cycles 1–2 (the `_checkProfileComplete` anonymous guard
+9, the `_buildAuthContent` spinner +24/-6, the `demo_session_service` import
+1, the `_lastDemoHeartbeatAt` field +1, and the heartbeat block +11).

76 vs 45 = **1.69× budget** → Within the >1.5× Warning threshold; the excess is
attributable to prior-cycle and demo-feature additions, not Cycle 6 scope
creep. **Warning** per arithmetic rule.

---

## Code Efficiency Review

- No new helpers, extensions, utilities, barrel files, or abstractions.
- No new providers or notifiers.
- `_anonymousReconcileAttempted` is an instance boolean; no `copyWith` or
  state class entry needed.
- The `addPostFrameCallback` wrapper is idiomatic Flutter; no abstraction
  created for a two-line setup.
- The heartbeat block is an inline 60-second debounce via
  `_lastDemoHeartbeatAt`; acceptable for a single call site.
- `tester.view.physicalSize` reset in tests is standard Flutter test idiom.
- No single-use `_buildX()` methods; no `FutureBuilder`/`StreamBuilder` that
  re-fetches what a provider supplies.
- Searched `lib/` for a pre-existing equivalent of `_reconcileOrphanedAnonymousSession`: no match found.

---

## Issues Found

### Critical

#### Issue C1 — Task 5 incomplete: Tier-2 rationale block is stale

**Category:** `implementation-gap`

The plan (Task 5) explicitly required:

> "Update the top-of-file Tier-2 rationale block to reflect that the 'modify
> provider during build' exception no longer occurs (the deferral fixes it)."

The test file's rationale block (lines 14–25) still reads:

> "In the widget-test harness that call executes while the initial widget-tree
> build is still in progress (initState → unawaited async function →
> synchronous prefix runs before the first real await), causing Riverpod to
> throw 'Tried to modify a provider while the widget tree was building.' There
> is no DI seam to inject a post-frame yield; auth_gate.dart is off-limits…"

This description of the build-phase exception is the defect that Cycle 4/6
**fixes**. After the `addPostFrameCallback` deferral, the reconcile no longer
runs during the build phase; the exception no longer fires. The rationale is
factually wrong: it implies the defect still exists in the current code. The
test file was left "untouched cycles 4–6" per the Engineer Report, which
confirms the required update was skipped.

**Required fix:** Update the rationale to state that (a) the build-phase
exception was fixed by the deferral, (b) the remaining Tier-2 barrier is
network-dependency only (real `signInAnonymously`, real `signOut(global)` admin
revoke), and either (c) add Tests D and E using `setSession` + fake notifier as
the plan specifies, OR (d) record the specific priming failure mode that
prevented (c).

---

### Warnings

#### Issue W1 — Tests D and E not attempted via plan-specified priming approach

**Category:** `implementation-gap`

The plan provided two offline-achievable priming approaches for Tests D and E
and stated: "If neither proves feasible after honest effort, keep the two
anonymous scenarios in Tier-2 and record the specific failure mode."

The Engineer Report states Tests D/E are deferred because they "require real
Supabase network calls." This is partially true for `signOut(global)`'s
server-side revocation, but the plan specifically explained:

- `setSession` with a hand-crafted JWT (whose `is_anonymous` claim is `true`)
  populates `currentUser` locally with no HTTP round trip.
- With the fake notifier override, `loadUserBands()` makes no network call.
- The observable outcome of `signOut(global)` locally (session cleared before
  the network call) is detectable offline.

No `setSession` attempt is documented. The test file's rationale cites only
the build-phase exception (now resolved) — not any failure from attempting the
new priming paths. The plan's fallback "record the specific failure mode"
requirement is unfulfilled.

**Required fix:** Either attempt `setSession` with an anonymous JWT to prime
Tests D and E, OR update the test file's rationale to document precisely which
priming attempt was made and why it failed, per the plan's fallback clause.

#### Issue W2 — Out-of-scope code in auth_gate.dart (demo heartbeat additions)

**Category:** `out-of-scope`

The diff includes additions to `auth_gate.dart` that are not described in the
bug fix plan:

- `import 'demo_session_service.dart';` (line 17)
- `DateTime? _lastDemoHeartbeatAt;` (field)
- Heartbeat timer block inside `_startSessionSyncTimer()` (11 lines)

The plan explicitly states: "Out of Scope: Anonymous-session heartbeat and demo
cleanup cron. Unchanged." These additions are demo-feature code; they do not
interfere with the cold-start recovery logic. The heartbeat fires only for
anonymous users every 60 seconds, is gated on `actualSession?.user.isAnonymous
== true`, and has no interaction with the reconcile path.

**Assessment:** No functional regression to the bug fix or to real-user paths.
Classified as Warning rather than blocking because the additions are scoped to
the demo feature branch and are consistent with the broader feature's
requirements. Manager should confirm whether these were intentionally
included with this cycle's diff or are carry-over from demo-feature cycles 1–2.

#### Issue W3 — Change budget exceeded by 1.69×

**Category:** `code-quality`

Actual diff is +76, -6 against the plan's budget of +35 to +45 lines for the
bug fix's Cycle 6 additions. As noted in Change Budget Review, the excess is
attributable to cumulative prior-cycle additions (cycles 1–2) and demo-feature
code — not Cycle 6 scope creep. The 1.69× ratio falls in the >1.5× Warning
band per the arithmetic rule. No single Cycle 6 addition exceeds budget.

---

### Suggestions

#### Issue S1 — 1 new info lint introduced (avoid_redundant_argument_values)

**Category:** `code-quality`

`auth_gate.dart:649`: `type: ProgressIndicatorType.circular` in the newly added
`_buildAuthContent` anonymous spinner block is the default value and triggers
`avoid_redundant_argument_values`. HEAD has 12 info lints; the working tree has 13. The Engineer Report claims all 13 are pre-existing — this is incorrect;
the 13th is new. The lint is `info` level only and is in demo-feature code.
**Suggestion:** Remove the `type:` argument or note it explicitly if intentional.

---

## Tier-2 Deferral Assessment (requested)

**Is the Tier-1 / Tier-2 split acceptable?** Conditionally, given a corrected
rationale. The 3 Tier-1 tests verify the unauthenticated guard path (the most
critical safety property: no regression for real users). The remaining
anonymous-session scenarios are correctly deferred for the network-dependent
aspects (real `signInAnonymously`, real `signOut(global)` token revocation,
macOS restore-loop end-to-end). This is an honest reflection of the offline
test harness's limits.

However, the plan identified that the `loadUserBands` invocation count and the
`!hasBands` decision branch became offline-testable after the deferral fix. The
rationale block must be updated to reflect this accurately — the current block
cites a now-fixed defect as the barrier, which is misleading. If `setSession`
priming is also infeasible (which is possible if the GoTrue SDK version validates
the JWT online), that must be documented specifically.

The Tier-2 on-device tests (plan §Verification Plan Tier 2, items 1–5) remain
required pre-merge and are not blocked by this QA cycle's finding.
