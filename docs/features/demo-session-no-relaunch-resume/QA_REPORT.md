# QA_REPORT — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Cycle Number

1

## Final Verdict

**APPROVED**

---

## Validation Summary

The implementation matches the Architect plan exactly. A cold-start purge of a
restored anonymous demo session was added to `main.dart` at init step 6.5 —
after the `Supabase.initialize()` try/catch (`FormatException` retry) and before
`Firebase.initializeApp()` — gated by a new pure static predicate
`DemoSessionService.shouldPurgeRestoredAnonymousSession({hasSession, isAnonymous})
=> hasSession && isAnonymous`. Only the 5 plan-listed files were touched; no
off-limits #289 surface was modified. `isAuthenticated == session != null` is
literally unchanged. Analyzer is clean at every severity on all changed files;
the focused predicate + anonymous-recovery tests (12) and the full suite (292)
all pass.

The core safety guarantee was verified by **code-path analysis of the resolved
gotrue 2.27.2 and supabase_flutter 2.17.2 sources** (not runtime): the local
sign-out nulls the in-memory session synchronously before any await, so the
success, timeout, and catch paths all leave `currentSession == null`. The actual
relaunch/resume behavior requires a running app and is an **owner-run** check
(Tony) per the plan — it is correctly *not* a QA gate and is transcribed as a
Manual Verification Punch List below. This report distinguishes clearly between
headless static/executable checks (performed by QA) and on-device relaunch
verification (owner-run, not performed by QA).

**No blocking issues.** Two non-blocking budget observations and one non-blocking
diff-safety note are recorded below with full rationale.

---

## Architect Scope Review

**Pass.** `git diff HEAD --stat` shows exactly the 5 plan-listed files, 167
insertions, 0 deletions:

| File | Plan-listed | In diff |
| --- | --- | --- |
| `lib/main.dart` | Yes | +24 |
| `lib/features/auth/demo_session_service.dart` | Yes | +12 |
| `test/features/auth/demo_lifecycle_predicate_test.dart` | Yes | +43 |
| `docs/reference/general/AI_DECISIONS.md` | Yes | +87 |
| `docs/reference/general/RUNTIME_CONFIG.md` | Yes | +1 |

Off-limits #289 surfaces confirmed **untouched** (grep of `git diff --name-only`
for `migrations|functions|auth_state_provider|auth_gate|login_screen|app_shell`
returns nothing):

- `supabase/migrations/**`, `supabase/functions/exit-demo-session/**`, TTL/cron/
  advisory-lock/grants — not in diff.
- `lib/features/auth/auth_state_provider.dart` — not in diff;
  `bool get isAuthenticated => session != null;` (line 19) verified unchanged.
- `AuthGate` routing/safeguards/sync timer/`_reconcileOrphanedAnonymousSession()`
  — not in diff (reconcile backstop preserved; verified still passing, see Tests).
- `login_screen.dart`, `app_shell.dart` — not in diff.

No unapproved architectural change, no unrelated formatting churn, no whitespace
errors (`git diff --check` clean).

---

## Completeness Check

**Pass — all 5 Architect tasks complete.**

1. **Predicate** — `shouldPurgeRestoredAnonymousSession` added next to
   `shouldReleaseDemoOnLifecycle` with the restored-anonymous-only doc comment;
   no existing method (`provisionAndEnter`, `exit`, `heartbeat`,
   `releaseSlotOnDetach`, `shouldReleaseDemoOnLifecycle`) altered. Verified in
   diff.
2. **`main.dart` purge** — import added; guarded purge block placed **between**
   the Supabase-init block and the `// Initialize Firebase` block (init step
   6.5), reads `currentSession`, gates on the predicate, bounded `~2 s .timeout`
   local sign-out inside try/catch. Verified by reading `lib/main.dart` in
   context.
3. **Unit test** — new `group('shouldPurgeRestoredAnonymousSession', ...)` with
   the full 4-case truth table added; the existing
   `shouldReleaseDemoOnLifecycle` group is intact.
4. **DECISION-006** — appended (Feature slug, Status Active) covering all four
   mandated sub-topics: (a) init-order step 6.5, (b) local-sign-out-only,
   (c) login-guaranteed failure behavior, (d) one-line rollback.
5. **RUNTIME_CONFIG** — step `6.5 Purge restored anonymous demo session (local
   sign-out) ← native-only effect` inserted between steps 6 and 7.

No partial implementation, no missing edge case the plan specified.

---

## Behavior Verification

**Method: code-path / source analysis of resolved package sources. NOT
runtime-exercised** (relaunch behavior is owner-run — see Punch List).

### gotrue `signOut()` default scope + local-before-network ordering

- Resolved versions (from `pubspec.lock`): **gotrue 2.27.2**,
  **supabase_flutter 2.17.2**.
- `gotrue-2.27.2/lib/src/gotrue_client.dart`:
  `Future<void> signOut({SignOutScope scope = SignOutScope.local}) => _signOut(...)`.
  The default scope **is** `SignOutScope.local` — confirmed from source.
- `_signOut()` executes, in order: `_removeSession()` (sets
  `_currentSession = null` — **synchronous, before any await**), removes the
  code-verifier from storage, `notifyAllSubscribers(AuthChangeEvent.signedOut)`,
  and **only then** `await admin.signOut(...)` (the ignorable network revoke,
  which swallows 401/403/404).
- supabase_flutter 2.17.2 `supabase_auth.dart` listens on `onAuthStateChange`
  and, on `AuthChangeEvent.signedOut`, calls
  `await _localStorage.removePersistedSession()` — so the `signedOut` event
  emitted *before* the network revoke drives persisted-storage removal
  (`_prefs.remove(persistSessionKey)`).

Conclusion: the persisted + in-memory session is cleared before the network
part, so `currentSession == null` even offline. The plan's "gotrue clears local
storage before the network part, login guaranteed even on timeout" claim is
**accurate** (with the precise note that persisted removal is performed by
supabase_flutter's `signedOut` listener, which the pre-network event triggers;
the decisive in-memory clear is synchronous inside gotrue).

### Timeout / catch cannot leave a live restored anonymous session

`_removeSession()` runs at the very top of `_signOut`, **before any `await`**.
Therefore in **every** path the in-memory session is already null:

- **Success** — network revoke completes, `currentSession == null`.
- **Timeout** — `.timeout(2 s, onTimeout: () {})` completes normally (returns
  void, does not throw); the in-memory clear already happened before the network
  await, so `currentSession == null`.
- **Throw** — a non-4xx `AuthException` rethrown by gotrue is caught by
  `main.dart`'s try/catch (→ `debugPrint`), but `_removeSession()` already ran,
  so `currentSession == null`.

The absolute expected behavior ("a restored anonymous session must never remain
live at cold start") holds on all three paths. The only theoretical exception is
a synchronous throw before `_removeSession()` (e.g. logger failure) — pathological,
and the plan/report already document worst-case = pre-fix behavior backstopped by
#289 TTL, no crash.

### Predicate scoping — real users and fresh demos preserved

`hasSession && isAnonymous` returns `true` **only** for a session-present +
anonymous case. Real users (`isAnonymous == false`) and the no-session case are
never purged, so real-user session persistence is preserved exactly. Fresh
in-run demo sessions are created by `DemoSessionService.provisionAndEnter()`
*after* startup via the demo button and never traverse `main.dart`'s cold-start
path, so they are unaffected. `restoredSession?.user.isAnonymous == true` uses
`User.isAnonymous` (verified present in gotrue 2.27.2 `types/user.dart`, `bool`,
defaults `false`).

### Web behavior / native-only demo fact

`login_screen.dart` line 53: `const bool _kDemoBandVisible = !kIsWeb;` — the demo
button is native-only, so an anonymous session can only ever exist on native. On
web the purge is inert: any web session is a real user (`isAnonymous == false` →
not purged) or none (→ not purged). No `!kIsWeb` gate is needed and none was
added; web real-user resume is preserved. Correct per plan.

### Init-order / routing race

With `currentSession == null` established before `runApp()`, every downstream
auth path (`AuthStateNotifier.build()`, the `build()` safeguard, the 5 s sync
timer, `refreshSession`/`forceRefresh`, the `initialSession` replay) agrees "no
session" and routes to `LoginScreen` with zero provider/widget special-casing.
The `_reconcileOrphanedAnonymousSession()` backstop is untouched and still passes
its tests (Test D global sign-out, Test E preserve). No init step other than the
inserted 6.5 was reordered.

---

## Regression Check

Overall regression risk: **LOW–MEDIUM** (plan rated MEDIUM for touching
init-order + auth session handling; observed behavior is tightly gated and fully
covered by static analysis + tests).

| Affected system (plan impact map) | Risk | Notes |
| --- | --- | --- |
| Auth / session | **LOW** | Change is gated to `hasSession && isAnonymous`; `isAuthenticated` semantics unchanged; in-memory clear is synchronous and total. |
| Routing (indirect) | **LOW** | No routing code changed; `currentSession == null` drives existing login route. |
| Init order | **LOW** | Single insertion at 6.5, logged (DECISION-006) + RUNTIME_CONFIG updated; no other step moved. |
| Anonymous reconcile backstop | **LOW** | `_reconcileOrphanedAnonymousSession()` untouched; `auth_gate_anonymous_recovery_test.dart` Tests A–E pass. |
| Real-user persistence | **LOW** | Predicate case 2 (`isAnonymous:false → false`) + full-suite pass; no purge for real users. |
| Startup robustness | **LOW** | try/catch + `.timeout(onTimeout: () {})` guarantee `runApp()` is reached even offline/on throw. |
| Platform parity | **LOW** | Native-only effect; web inert (verified via `_kDemoBandVisible`). No native-only change silently affecting web or vice-versa. |
| Setlists / Gigs / Rehearsals / Members / Notifications | **LOW** | No touchpoints. |
| DB / RLS / RPC | **N/A** | No DB change. |

No new `setState`-after-async-gap, no Controller/FocusNode disposal change, no
RPC signature/parameter-order change, no rebuild-frequency change.

---

## Database Safety

**N/A.** No migration, RLS policy, RPC, trigger, grant, or edge-function change
(confirmed: no `supabase/**` path in the diff). #289's advisory lock, TTL, cron,
grants, and capacity math are untouched and off-limits. No Supabase branch
apply-check was required (no `.sql` migration in the diff), so none was run; no
production or remote Supabase environment was contacted.

---

## Analyzer Results

`flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
test/features/auth/demo_lifecycle_predicate_test.dart` →
**"No issues found!"** — clean at every severity on all changed Dart files
(`analysis_options.yaml` promotes the AI-slop lints to error; none tripped, and
no info-level residue). The two changed docs are Markdown (not analyzed). No
pre-existing violation exists in any diff-touched file.

---

## Test Results

- `flutter test test/features/auth/demo_lifecycle_predicate_test.dart
  test/features/auth/auth_gate_anonymous_recovery_test.dart` → **All 12 tests
  passed.** The 4 new `shouldPurgeRestoredAnonymousSession` truth-table cases
  pass (`T/T→true`, `T/F→false`, `F/F→false`, `F/T→false`); the existing
  lifecycle-predicate group and the anonymous-recovery reconcile backstop
  (Tests A–E, incl. Test D global sign-out and Test E preserve) pass unchanged.
- `flutter test` (full suite) → **All 292 tests passed.** No new failures; the
  previously-flaky `login_screen_demo_button_test.dart` passed in this run. This
  branch introduces zero changes under `test/` outside the one predicate test
  file.

---

## Diff Safety Review

- **Secrets / API keys:** none. Added-line scan for
  `api_key|secret|password|token=|bearer` → no matches.
- **`TODO` / `FIXME`:** none in the diff.
- **`debugPrint(`:** **one** added line —
  `debugPrint('[Main] Anonymous demo session purge failed: $e');` in
  `main.dart`. Recorded as a finding below (non-blocking; see Issues Found →
  Warnings, `code-quality`). Rationale: it is prescribed **verbatim** by
  ARCHITECT_PLAN Task 2 (the validation authority), matches the file's
  established, analyzer-sanctioned startup-logging convention (3 pre-existing
  `debugPrint` calls in `main.dart` — `FormatException` retry, Firebase-init
  catch), the analyzer passes clean (`avoid_print` targets `print`, not
  `debugPrint`), and it is intentional error logging, not a leftover debug
  artifact. Surfaced explicitly for Tony's visibility; it does not by itself
  force REQUIRES CHANGES given the plan authority + file convention +
  analyzer-clean status.
- **`print(`:** none.
- **Leftover scaffolding / accidental deletions / unrelated churn:** none.
  Zero deletions is expected — this is a net-additive guard inserted into an
  existing flow (not a bug fix), as the Engineer report explains.

---

## Change Budget Review

`git diff --numstat` vs. the plan's Change Budget:

| File | Budget | Actual | Ratio | Assessment |
| --- | --- | --- | --- | --- |
| `lib/main.dart` | +~12 | +24 | 2.0x | See Warning (comments only; plan under-budgeted its own snippet). |
| `demo_session_service.dart` | +~10 | +12 | 1.2x | Within 1.5x — OK. |
| `demo_lifecycle_predicate_test.dart` | +~30 | +43 | 1.43x | Within 1.5x — OK. |
| `AI_DECISIONS.md` | +~30 | +87 | 2.9x | See Warning (mandated doc content; proportional to siblings). |
| `RUNTIME_CONFIG.md` | +~2 | +1 | 0.5x | Under budget — OK. |
| New files | 0 | 0 | — | OK. |
| New public methods | 1 | 1 | — | Exactly the planned predicate. |
| New dependencies | 0 | 0 | — | OK. |

The two >1.5x files are both cases where the plan's per-file line *budget* was
optimistic relative to the content the plan's own *tasks* required, not
engineer-introduced bloat (details in Issues Found).

---

## Code Efficiency Review

- **Reuse:** independently grepped `lib/` for a pre-existing cold-start /
  restored-anonymous purge helper. The sibling
  `DemoSessionService.shouldReleaseDemoOnLifecycle` has different semantics
  (lifecycle-`detached` slot *release*, not cold-start *purge*); the inline
  `isAnonymous` checks in `auth_gate.dart` / `app_shell.dart` are runtime
  routing/exit checks, not a reusable pure predicate. No existing equivalent —
  the new predicate is justified and mirrors #289's established testable-seam
  pattern. Engineer's reuse claim independently confirmed.
- **No AI-shaped code:** no single-use `_buildX()`/private widget, no new
  provider/notifier, no `Future`/`StreamBuilder`, no hand-rolled match/dedupe
  loop, no unused field/`copyWith` entry, no barrel file, no "for future use"
  flags/enums, no single-call-site wrapper.
- **try/catch swallows-and-continues** (does not log-and-rethrow) — intentional
  and required: startup must reach `runApp()` even if the bounded sign-out
  throws/times out. Mirrors the existing `FormatException` "sign out and
  continue" pattern at the same point in `main.dart`. Not a code-smell here.
- **File sizes:** `main.dart` = 348 lines, `demo_session_service.dart` = 107
  lines — both well under the 500-line target; no justification required.

---

## Manual Verification Punch List (owner-run — Tony; requires a running app)

QA cannot and did not execute these — relaunch/resume behavior needs a running
native app, which is categorically owner-run. The plan correctly classifies these
as owner-run (not a QA gate). Run on a **native** build (macOS and at least one of
iOS/Android):

1. From the login screen, tap **"Check out the demo band."**
   **Expected:** you land in the Demo Band (fresh in-run session unaffected).
2. Fully quit the app (macOS Cmd-Q; iOS/Android swipe-kill) **within the TTL
   window** (well under 8 minutes), then reopen.
   **Expected:** the app shows the **login screen** — it does **not** resume into
   the Demo Band.
3. Repeat step 2 but reopen with the device in **airplane mode / no network**.
   **Expected:** still the **login screen** (local sign-out clears storage
   offline).
4. Sign in as a normal (non-anonymous) account, quit, and reopen.
   **Expected:** the app resumes **directly into the account** with no login
   prompt (real-user persistence preserved exactly).
5. Web smoke (any browser): confirm **no demo button** is present and normal
   real-user session resume across a page reload is unchanged.

---

## Issues Found

### Critical

None.

### Warnings

1. **`main.dart` change is 2.0x its line budget (24 vs +~12).** — Category:
   `code-quality`. The excess is entirely explanatory comments: the plan's own
   Task-2 code snippet is already ~20 lines (6-line comment + the guarded block),
   and the Engineer added one further ~3-line inline comment documenting the
   offline/timeout guarantee. So the overage versus the code the plan *actually
   prescribed* is ~4 comment lines — the `+~12` figure was internally
   inconsistent with the plan's own Task-2 listing. No logic bloat; no new
   symbol beyond the planned predicate. **Non-blocking.**
2. **`AI_DECISIONS.md` entry is 2.9x its line budget (87 vs +~30).** — Category:
   `code-quality`. This is a documentation decision-log entry whose content was
   explicitly mandated by plan Task 4 (init-order step, local-sign-out-only
   choice, login-guaranteed failure behavior, rollback) and is proportional to
   the sibling `DECISION-005` entry (~81 lines) in the same established format.
   It is not code and introduces no maintenance burden or scope inflation; the
   `+~30` budget under-estimated the mandated content. **Non-blocking.**
3. **One `debugPrint(` in the diff.** — Category: `code-quality`. The mode's
   diff-safety heuristic flags `debugPrint(` generically, but this instance is
   prescribed verbatim by the Architect plan, matches `main.dart`'s established
   analyzer-sanctioned convention, and passes the analyzer clean. Surfaced for
   visibility; **non-blocking** (see Diff Safety Review for full rationale). If
   Tony prefers zero `debugPrint` in committed code as a hard policy, this line
   (and the 3 pre-existing ones in `main.dart`) would be the follow-up — but
   that is a project-wide convention decision, out of scope for this feature.

### Suggestions

1. Consider tightening the plan's Change Budget figures in future cycles so the
   per-file line budgets match the plan's own prescribed code/doc content (the
   two Warnings above are budget-vs-content inconsistencies in the plan, not
   engineer bloat). Cosmetic; no action required on this branch.

---

## Verdict Rationale

All APPROVED gates are met: plan match (5 files, no off-limits surface), all
tasks complete, no regressions (reconcile backstop + full suite green), DB safety
N/A, analyzer clean at every severity, required tests pass, no out-of-scope or
unsafe changes, no secrets, no Critical-level bloat (0 new files, 1 planned
public method, 0 new dependencies, no AI-shaped code). The core offline/timeout
safety guarantee was verified by source analysis of gotrue 2.27.2 /
supabase_flutter 2.17.2. The three Warnings are non-blocking (two are
plan-budget-vs-content inconsistencies; one is a plan-prescribed,
convention-consistent, analyzer-clean `debugPrint`). Relaunch behavior is
owner-run and captured as a Manual Verification Punch List, not a QA gate.

**Final Verdict: APPROVED.**
