# ENGINEER_REPORT — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Cycle Number

5

## Goal

Ensure a restored **anonymous** demo session never auto-resumes into the Demo
Band on cold start. The Cycle 1–3 mechanism (a post-init local sign-out at init
step 6.5) passed static analysis but **failed Tony's owner relaunch test** — a
demo still resumed into the Demo Band. Cycle 4 diagnoses why and replaces the
mechanism with a deterministic one: purge the persisted anonymous session from
disk **before** `Supabase.initialize()` reads it (init step 5.5). Real-user
(non-anonymous) persistence and the live in-run demo flow are preserved exactly.
No database/TTL/cron/edge-function change (all #289 surfaces off-limits).

## Architect Tasks Completed

Cycle 4 reworks the mechanism to close the implementation gap (see **Cycle 4 —
Root-Cause Repair** below). The plan's intent — "a restored anonymous demo
session must not resume across relaunch" — is preserved; the *how* changed from a
post-init local sign-out to a pre-init disk purge because the former was undone by
the SDK's background `recoverSession()`.

1. **`DemoSessionService` — two pure/static seams.** Replaced the obsolete
   `shouldPurgeRestoredAnonymousSession` predicate with:
   `isPersistedSessionAnonymous(String? rawSessionJson)` (pure, testable —
   classifies a persisted session blob as anonymous, fail-safe on malformed/absent
   input) and `purgePersistedAnonymousSession(String supabaseUrl)` (reads
   supabase_flutter's own persist key from `SharedPreferences` and removes it only
   when the stored session is anonymous). No existing method
   (`provisionAndEnter`, `exit`, `heartbeat`, `releaseSlotOnDetach`,
   `shouldReleaseDemoOnLifecycle`) was altered.
2. **`main.dart` — pre-init purge (init step 5.5).** Removed the broken post-init
   step-6.5 sign-out block and added, **before** `Supabase.initialize()` (after
   `validateSupabaseConfig()`), a native-only
   `await DemoSessionService.purgePersistedAnonymousSession(supabaseUrl)`.
3. **Tests** — replaced the pure truth-table group with an
   `isPersistedSessionAnonymous` group (6 cases) **and** a
   `purgePersistedAnonymousSession (startup storage race)` group (4 cases) that
   exercises the actual `SharedPreferences` the SDK restores from at cold start.
4. **`DECISION-006`** — rewritten to the pre-init disk-purge mechanism, with a
   "Cycle 4 correction" subsection documenting the SDK background-restore root
   cause, the updated login guarantee, constraints, and rollback.
5. **`RUNTIME_CONFIG.md`** — replaced init step `6.5` with `5.5 Purge persisted
   anonymous demo session ← native-only; BEFORE Supabase.initialize()`.

## Files Created

None.

## Files Modified

| File                                                                                                                    | Change                                                                                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/main.dart](../../../lib/main.dart)                                                                                 | Removed the broken post-init step-6.5 sign-out block; added the native-only pre-init purge call before `Supabase.initialize()`. Net −6 lines.                                |
| [lib/features/auth/demo_session_service.dart](../../../lib/features/auth/demo_session_service.dart)                     | Removed `shouldPurgeRestoredAnonymousSession`; added `isPersistedSessionAnonymous` + `purgePersistedAnonymousSession` + `dart:convert`/`shared_preferences` imports. Net +44. |
| [test/features/auth/demo_lifecycle_predicate_test.dart](../../../test/features/auth/demo_lifecycle_predicate_test.dart) | Replaced the truth-table group with the `isPersistedSessionAnonymous` (6) + `purgePersistedAnonymousSession` storage-race (4) groups. Net +112.                              |
| [docs/reference/general/AI_DECISIONS.md](../../../docs/reference/general/AI_DECISIONS.md)                               | Rewrote `DECISION-006` to the pre-init disk-purge mechanism + Cycle 4 correction.                                                                                            |
| [docs/reference/general/RUNTIME_CONFIG.md](../../../docs/reference/general/RUNTIME_CONFIG.md)                           | Replaced init step 6.5 with step 5.5 (pre-init purge).                                                                                                                       |

`git diff --stat` (working tree, this cycle): 5 files changed, 255
insertions(+), 121 deletions(-). All 5 are plan-listed files; no off-limits or
unplanned file touched. The uncommitted `AI_DECISIONS.md` Markdown-escaping edits
were used as the working base (not reverted); the `DECISION-006` rewrite
supersedes the two escaped lines because they described the now-removed step-6.5
disk-ordering behavior (see Deviations).

## Analyzer Results

`flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
test/features/auth/demo_lifecycle_predicate_test.dart` → **No issues found!**
(clean at every severity, re-run after `dart format`). `dart fix --dry-run`
(read-only, whole package) → **Nothing to fix!** for the plan-listed files.
`dart format` applied to the three changed Dart files (test file reflowed).

## Test Results

- `flutter test test/features/auth/demo_lifecycle_predicate_test.dart
test/features/auth/auth_gate_anonymous_recovery_test.dart` → **All 18 tests
  passed** (3 `shouldReleaseDemoOnLifecycle` + 6 `isPersistedSessionAnonymous` +
  4 `purgePersistedAnonymousSession` storage-race + the unchanged
  anonymous-recovery reconcile backstop Tests A–E).
- `flutter test` (full suite) → **All 298 tests passed.** No new failures
  (net +6 vs the prior 292: −4 obsolete truth-table cases, +10 new predicate +
  storage-race cases). The `auth_gate_anonymous_recovery_test.dart` reconcile
  backstop (Tests A–E) still passes unchanged.

## Code Efficiency / Bloat Check

- **Reuse search performed.** Searched `lib/` for an existing persist-key /
  session-storage / restored-anonymous purge helper before adding the two new
  methods. The sibling `DemoSessionService.shouldReleaseDemoOnLifecycle` is
  lifecycle-`detached` slot _release_, not a cold-start disk purge; the
  `isAnonymous` checks in `auth_gate.dart` / `app_shell.dart` are inline runtime
  routing/exit checks, not a reusable pure predicate; and `supabase_flutter`
  exposes **no** public accessor for its persist key or for awaiting/cancelling
  the background `recoverSession()`. **No existing helper** — the two new seams
  are justified; the key derivation necessarily mirrors the SDK's (unavoidable,
  and replicated exactly).
- No `_buildX()`/private `_Foo` widgets, no new provider/notifier, no
  `Future`/`StreamBuilder`, no hand-rolled match/dedupe loops, no new model field
  or `copyWith` entry, no barrel file, no "for future use" flags/enums added.
- The two `try/catch` blocks in `purgePersistedAnonymousSession` /
  `isPersistedSessionAnonymous` **swallow and continue** (no log-and-rethrow) —
  intentional and required: startup must reach `Supabase.initialize()` even if a
  `SharedPreferences` read fails, and a malformed blob must fail safe (never drop
  a real user's session). Worst case is pre-fix behavior for one launch,
  backstopped by #289 TTL.
- Comments state _why_ (the SDK's non-awaited background-restore race), not
  _what_; no `TODO`/`FIXME`/`debugPrint` left in the new code. The one
  `debugPrint` from the old step-6.5 block was **removed** with that block.
- **This is a root-cause fix that deletes the defective mechanism** (the step-6.5
  post-init sign-out block + the `shouldPurgeRestoredAnonymousSession` predicate +
  its truth-table tests), not an addition layered on top of the bug — 121
  deletions this cycle, satisfying the "a genuine fix usually removes/replaces the
  defective code" guardrail.
- **File sizes:** `lib/main.dart` = 337 lines (< 500 target);
  `lib/features/auth/demo_session_service.dart` = 141 lines (< 500 target). No
  target exceeded; no justification required.

## Verification (manual steps performed)

- Confirmed the pre-init purge sits **between** `validateSupabaseConfig()` and the
  `Supabase.initialize()` try block (init-order step 5.5), gated `!kIsWeb`, and
  that `isAuthenticated == session != null` in `auth_state_provider.dart` is
  **not** touched (grep confirmed no edit there); `auth_gate.dart`,
  `login_screen.dart`, `app_shell.dart`, and all `supabase/**` are unchanged.
- Confirmed the root cause in the resolved SDK sources: `supabase_flutter`
  2.17.2 `supabase.dart` fires `recoverSession()` as a non-awaited
  `CancelableOperation` **after** `SupabaseAuth.initialize()` returns; that
  background call re-reads storage and (for a non-expired token, always true
  within #289's 8-min TTL) `_saveSession()`s the session back into
  `currentSession`, undoing any post-init sign-out. `is_anonymous` is persisted
  and restored (gotrue 2.27.2 `user.dart` `toJson`/`fromJson`), so a restored
  anonymous session is reliably detectable on disk.
- Confirmed the persist-key derivation matches the SDK exactly
  (`sb-${Uri.parse(url).host.split('.').first}-auth-token`, `supabase.dart`), so
  the purge targets the same key the SDK reads; a mismatch would fail safe
  (no real-user session ever dropped).
- Confirmed all changes are confined to the 5 plan-listed files (`git status
  --porcelain`); the only paths outside them are the tracked
  `docs/features/demo-session-no-relaunch-resume/` artifacts.
- Ran `dart fix --dry-run` (read-only, whole package) — no suggestions for the
  plan-listed files.

## Deviations From Plan

**Material deviation-in-kind (mechanism), within plan-listed files — required to
close the QA implementation-gap.** The plan's mechanism (Task 2: a post-init
local `signOut()` at init step 6.5) is architecturally insufficient — it is
deterministically undone by the SDK's non-awaited background `recoverSession()`
(see **Cycle 4 — Root-Cause Repair**). No tuning of a *post-init* sign-out
(timeout, retry, await) can win that race. The repair keeps the plan's **intent**
("a restored anonymous demo session must not resume across relaunch") but changes
the **how**: a **pre-init** disk purge (init step 5.5) that removes the persisted
anonymous session before `Supabase.initialize()` reads it.

Scope of the deviation:

- Init step moved from **6.5** (after Supabase init) to **5.5** (before it). Still
  a single logged init-order insertion; `RUNTIME_CONFIG.md` + `DECISION-006`
  updated to match.
- Predicate replaced: `shouldPurgeRestoredAnonymousSession(hasSession,
  isAnonymous)` (a pure truth table that never exercised the failing path) → the
  pair `isPersistedSessionAnonymous` + `purgePersistedAnonymousSession`.
- `main.dart` now reads/removes `supabase_flutter`'s `SharedPreferences` persist
  key directly (via the already-declared `shared_preferences` dependency — **no
  new dependency**, no `pubspec` change). This couples to the SDK's key
  derivation, which is replicated exactly; a mismatch fails safe.

**All changes remain within the plan-listed files** (`main.dart`,
`demo_session_service.dart`, the predicate test, `AI_DECISIONS.md`,
`RUNTIME_CONFIG.md`). No off-limits file (`auth_state_provider.dart`,
`auth_gate.dart`, `login_screen.dart`, `app_shell.dart`, `supabase/**`) and no
unplanned file was touched, so this was implemented rather than escalated per the
Manager's routing ("stop only if a file outside plan scope is proven").

**AI_DECISIONS.md escaping edits.** Tony's uncommitted Markdown-escaping edits
(`supabase*flutter`, `\_not*`) fell inside `DECISION-006`'s old
"Login-guaranteed failure behavior" paragraph, which described the removed
step-6.5 disk-ordering behavior. The `DECISION-006` rewrite (required because the
implementation guarantee changed) supersedes those two lines with accurate
new-mechanism prose; this is a content correction, not a revert of the escaping
work, and no escaping edit elsewhere in the file was altered.

## Blockers Encountered

None.

## Cycle 4 — Root-Cause Repair (owner relaunch test FAILED)

**Symptom (owner test, Tony).** In Demo Band → quit macOS → `./run.sh macos` →
the app reopened **directly into Demo Band** instead of login. Quit-time logs
showed only `null -> inactive -> hidden` (no `detached`), so
`releaseSlotOnDetach` never fired — the server slot **and** the persisted
anonymous session both survived, which is the precondition for the resume (not
the cause). `./run.sh macos` performs a genuine cold process launch through
`main()`, so this is a true relaunch, not a warm resume.

**Root cause (implementation-gap — confirmed in resolved SDK source, not
assumed).** The Cycle 1–3 mechanism (step 6.5: read `currentSession` after
`Supabase.initialize()`, and `signOut(local)` if anonymous) is undone by the
SDK's own background restore:

1. `Supabase.initialize()` → `SupabaseAuth.initialize()`
   (`supabase_flutter-2.17.2/lib/src/supabase_auth.dart`) awaits
   `setInitialSession(persistedSession)`, which sets
   `_currentSession = <restored anon session>` synchronously. `is_anonymous`
   survives persistence (gotrue 2.27.2 `types/user.dart` — `toJson` writes it,
   `fromJson` reads it), so at step 6.5 the predicate correctly fired and
   `signOut()` did null the in-memory session.
2. **But `Supabase.initialize()` also kicks off a _non-awaited_ background
   `recoverSession()`** as a `CancelableOperation`
   (`supabase_flutter-2.17.2/lib/src/supabase.dart`, ~L158–160) that runs **after
   `initialize()` returns**. That background call re-reads the still-persisted
   session from disk and calls `GoTrueClient.recoverSession(jsonStr)`; for a
   **non-expired** token — always true within #289's 8-minute TTL window — it
   takes the `_saveSession(session)` branch (`gotrue_client.dart` ~L1268–1275),
   setting `_currentSession = session` **again** and (because step 6.5 had just
   nulled it) emitting `tokenRefreshed`. The anonymous session is **resurrected**.
3. Step 6.5's disk removal (`removePersistedSession`, dispatched fire-and-forget
   from the `signedOut` event via `_onAuthStateChange`) is itself async and
   **loses the race** with the background `recoverSession()`.
4. After `runApp()`, `AuthStateNotifier` observes the resurrected anonymous
   session (`tokenRefreshed` and/or `currentSession != null` in the `build()`
   safeguard / 5 s sync timer) and routes into the Demo Band.

No post-init sign-out — timed out, retried, or awaited — can deterministically
beat a non-awaitable background restore. `supabase_flutter` exposes no public API
to await or cancel that `CancelableOperation`. Static analysis and the pure
truth-table predicate could not have caught this: the predicate was correct; the
*mechanism around it* raced the SDK.

**Exact fix (deterministic, no race).** Remove the persisted anonymous session
from disk **before** `Supabase.initialize()` ever reads it (init step 5.5):

- `DemoSessionService.purgePersistedAnonymousSession(supabaseUrl)` reads the SDK's
  own persist key (`sb-<ref>-auth-token`, derived exactly as
  `SharedPreferencesLocalStorage` does in `supabase.dart`) from
  `SharedPreferences` and removes it **only** when
  `isPersistedSessionAnonymous(...)` is true.
- Called native-only (`!kIsWeb`) in `main.dart`, after `validateSupabaseConfig()`
  and before `Supabase.initialize()`.

With nothing anonymous on disk, `hasAccessToken()` returns false during init,
`setInitialSession` is skipped, and the background `recoverSession()` finds
nothing — `currentSession` stays `null` for the whole launch (no network), so the
app lands on login. Real (non-anonymous) sessions are never matched, so real-user
persistence is byte-for-byte preserved; fresh in-run demo sessions (created after
startup) are unaffected and are purged on the *next* launch. The old step-6.5
block and its predicate/tests were deleted.

**Verification added (fails under the old mechanism, passes under the repair).**
Beyond the pure `isPersistedSessionAnonymous` truth table, the new
`purgePersistedAnonymousSession (startup storage race)` group seeds
`SharedPreferences` with the exact key the SDK restores from and asserts the
anonymous blob is **gone after purge** (nothing left for init/`recoverSession` to
restore) while a real-user blob is **preserved**. This exercises the real startup
storage the race hinges on — coverage the prior truth-table predicate lacked. A
full driven `Supabase.initialize()` harness was intentionally **not** added: it
would require the Supabase singleton with `persistSession: true`, timers, and
platform-channel plumbing (app_links) that make it flaky in-suite, whereas the
storage-level assertion deterministically captures the same guarantee (the SDK
restores from exactly this key/value).



Per Tony's independent review (code confirmed correct and safe; **no re-test
needed**), this cycle is a **documentation-only** correction. **No Dart, test, or
config behavior was changed.** All source and test files remain unchanged from the
committed PR head `5a86287` — verified via `git diff --name-only 5a86287`, which
lists only Markdown files (`AI_DECISIONS.md`, `RUNTIME_CONFIG.md`, and the three
`docs/features/demo-session-no-relaunch-resume/` reports); `git diff --name-only
5a86287 -- '*.dart'` and `git diff --name-only 5a86287 -- ':(exclude)docs/**'` both
return empty.

**Correction applied** — `docs/reference/general/AI_DECISIONS.md`, `DECISION-006`,
section "Login-guaranteed failure behavior": the prior text incorrectly claimed
`signOut()` removes the **persisted** session from local storage _before_ the
network revoke. Corrected against the resolved SDK sources:

- gotrue 2.27.2 `_removeSession()` synchronously nulls only the **in-memory**
  `_currentSession` before any `await`/network revoke — that guaranteed in-memory
  `null` is what ensures `currentSession == null` and login is shown on this launch,
  including offline.
- **Persisted disk removal is separate:** supabase_flutter 2.17.2 receives the
  `signedOut` event via its auth listener and dispatches persisted-session removal
  **asynchronously / fire-and-forget**; `signOut()` does **not** await that disk
  write. The doc no longer overclaims that disk removal is ordered or awaited.
- Still functionally safe: the cold-start purge (step 6.5) reruns unconditionally
  on every launch, so a restored anonymous session left behind by an incomplete
  disk removal is detected and purged again before `runApp()`.
- The existing server-slot #289 TTL + cron backstop and the startup catch/continue
  behavior remain accurately described and unchanged.

The same overclaim in this report's Verification section (gotrue "awaits
persisted-storage removal") was corrected to match. Markdown formatter/reflow
changes already present in the touched docs were preserved, not reverted or
normalized.

## Cycle 3 — Documentation Reconciliation

Per Tony's independent review (code confirmed correct and safe; **no re-test
needed**), this cycle is a **documentation-only reconciliation** aligning this
report with the Architect's now-corrected `ARCHITECT_PLAN.md`. The Architect
corrected every remaining stale SDK-ordering claim in the plan — including the
Task-2 documentation code sample's comment — so the architecture artifact now
consistently distinguishes the **guaranteed synchronous in-memory nulling** of
`currentSession` (gotrue 2.27.2 `_removeSession()` sets `_currentSession = null`
before any `await`/network revoke — the decisive offline login guarantee) from
the **separate, asynchronous / non-awaited disk cleanup** (supabase_flutter
2.17.2 dispatches persisted-session removal from the `signedOut` event as
fire-and-forget; `signOut()` does not await it). The plan no longer claims disk
removal is ordered or awaited relative to the network revoke, matching the
corrected `DECISION-006` and this report's Cycle 2 correction.

- **No code or task scope changed.** No Dart, test, or config behavior was
  touched this cycle; the implementation and its task breakdown are identical to
  Cycle 1.
- **Source/test/non-doc delta from committed PR head `5a86287` remains zero** —
  verified via `git diff --name-only 5a86287 -- '*.dart' 'test/**'` and
  `git diff --name-only 5a86287 -- ':(exclude)docs/**'`, both empty. All changes
  versus `5a86287` are Markdown docs only; `git diff --check 5a86287` reports no
  whitespace errors.
- Flutter analysis/tests were **intentionally not re-run** (nothing executable
  changed); the Cycle 1 clean-analyzer and all-green-test results stand.
- Markdown formatter/reflow changes already present in the touched docs were
  preserved, not reverted or normalized.

## Cycle 5 — Plan Reconciliation (no source/test change)

QA Cycle 4 found the code technically correct (analyzer-clean, 298/298 tests,
LOW–MEDIUM risk) and returned **REQUIRES CHANGES** for a single
`[out-of-scope]` reason only: `ARCHITECT_PLAN.md` still described the disproven
**step-6.5** post-init sign-out while the shipped implementation, `DECISION-006`,
and `RUNTIME_CONFIG.md` already described the **step-5.5** pre-init disk purge.
The Architect resolved this in the Cycle 5 plan amendment, ratifying the pre-init
purge mechanism, the exact SDK persist-key coupling, the fail-safe classifier, the
current file scope, the tests, and the adjusted change budget.

**No source or test implementation change was required this cycle** — the QA
finding was a plan/implementation mismatch, not a code defect, and it was closed by
amending the plan (the Architect's artifact), not by editing code. I reconciled the
existing uncommitted Cycle 4 implementation against the now-amended plan and
confirmed a byte-for-byte match to its Engineer Task Breakdown:

- **Task 1 (classifier seam):** `DemoSessionService.isPersistedSessionAnonymous`
  returns `true` only when `decoded['user']['is_anonymous'] == true`, `false` for
  null / malformed / missing-`user` / absent-`is_anonymous`, wrapped in
  `try/catch` — matches plan.
- **Task 2 (purge seam):** `purgePersistedAnonymousSession(supabaseUrl)` derives
  `'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`, removes the
  key only when the blob classifies anonymous, whole body in swallow-and-continue
  `try/catch`; `dart:convert` + `shared_preferences` imported; no existing method
  altered — matches plan.
- **Task 3 (`main.dart` step 5.5):** the `demo_session_service.dart` import is
  present and the native-only `await
  DemoSessionService.purgePersistedAnonymousSession(supabaseUrl)` sits **after**
  `validateSupabaseConfig()` and **before** the `Supabase.initialize()` try block;
  the old post-init block is gone; the `FormatException` retry is unchanged —
  matches plan.
- **Task 4 (tests):** the `isPersistedSessionAnonymous` (6 cases) and
  `purgePersistedAnonymousSession (startup storage race)` (4 cases) groups are
  present; the obsolete `shouldPurgeRestoredAnonymousSession` truth-table group is
  gone — matches plan.
- **Tasks 5–6 (`DECISION-006` / `RUNTIME_CONFIG.md`):** both already describe step
  **5.5** (pre-init purge), the ratified persist-key coupling + upgrade fail-safe,
  and the local-purge-only choice — matches plan. Tony's Markdown escaping/reflow
  edits in `AI_DECISIONS.md` are preserved as incorporated into the current
  `DECISION-006` rewrite; no doc was reverted or re-normalized this cycle.

**Re-verification (Cycle 4 introduced executable changes, so re-run per the
amended plan's Tier-1 gate):**

- `flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
  test/features/auth/demo_lifecycle_predicate_test.dart` → **No issues found!**
  (clean at every severity).
- `flutter test test/features/auth/demo_lifecycle_predicate_test.dart
  test/features/auth/auth_gate_anonymous_recovery_test.dart` → **18/18 passed**
  (3 lifecycle + 6 classifier + 4 storage-race + 5 reconcile backstop).
- `flutter test` (full suite) → **All 298 tests passed.** No new failures.

**Scope / budget / bloat re-check:**

- Working-tree changes are confined to the 8 expected paths: the three plan-listed
  source/test files (`main.dart`, `demo_session_service.dart`,
  `demo_lifecycle_predicate_test.dart`), the two plan-listed docs
  (`AI_DECISIONS.md`, `RUNTIME_CONFIG.md`), and the three pipeline artifacts under
  `docs/features/demo-session-no-relaunch-resume/`. No off-limits file
  (`auth_state_provider.dart`, `auth_gate.dart`, `login_screen.dart`,
  `app_shell.dart`, `supabase/**`) or unplanned file is touched.
- `git diff --numstat main` for the code/doc files (`main.dart` +13/−0,
  `demo_session_service.dart` +46/−0, `demo_lifecycle_predicate_test.dart`
  +134/−5, `AI_DECISIONS.md` +121/−0, `RUNTIME_CONFIG.md` +27/−21) reconciles with
  the plan's ratified per-cycle budget: the cumulative-vs-`main` footprint equals
  the prior committed step-6.5 baseline plus the Cycle 4 replacement delta the plan
  budgets (e.g. `main.dart` = prior +24, Cycle 4 net −11 → +13).
- Bloat re-read: no `_buildX()`/private `_Foo`, no new provider/notifier, no
  `Future`/`StreamBuilder`, no hand-rolled match/dedupe, no dead flag or unread
  field; the two `try/catch` blocks swallow-and-continue by design (startup must
  reach `Supabase.initialize()`; a malformed blob must fail safe). `dart
  fix --dry-run` (read-only, whole package) reports nothing for the plan-listed
  files. No `dart format` diff was produced (the files were already formatted in
  Cycle 4).

## Ready For QA

**Yes (Cycle 5).** The Cycle 4 REQUIRES CHANGES was `[out-of-scope]` only — a
plan/implementation mismatch now closed by the Architect's Cycle 5 plan amendment,
not by a code change. The shipped Cycle 4 implementation reconciles byte-for-byte
with the amended plan's Engineer Task Breakdown and file scope. **No source or test
implementation change was required this cycle.** Re-verification per the ratified
Tier-1 gate is green: focused analyzer clean at every severity on all three changed
Dart files; 18 focused tests (classifier + storage-race + reconcile backstop) and
the full 298-test suite pass; diff/scope/bloat checks confirm changes stay within
the plan-listed files with no off-limits or unplanned file touched. The on-device
relaunch behavior remains an owner-run check (Tony): enter demo → quit → `./run.sh
macos` should land on **login**, plus the airplane-mode and real-user regression
cases in the plan's owner punch list.
