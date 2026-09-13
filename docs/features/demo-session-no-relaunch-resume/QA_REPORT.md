# QA_REPORT — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Cycle Number

5

## Final Verdict

**APPROVED**

The Cycle 5 Architect amendment to `ARCHITECT_PLAN.md` now ratifies the exact
mechanism the implementation ships — the native-only, pre-init (init step 5.5)
`SharedPreferences` purge of a persisted anonymous session, the SDK persist-key
coupling, the fail-safe positive-only classifier, the file scope, the reset change
budget, the tests, and the owner punch list. The single blocking reason from Cycle
4 (Critical `[out-of-scope]`: the plan still described the disproven post-init
step-6.5 sign-out) is **resolved** — the plan, `DECISION-006`, and
`RUNTIME_CONFIG.md` now describe the same step-5.5 mechanism, and the
implementation matches the amended plan's Engineer Task Breakdown byte-for-byte.
All other gates pass: root cause independently re-confirmed in the resolved SDK
source, analyzer clean at every severity, 18 focused + 298 full tests green, no
DB change, no secrets/debug artifacts, scope/budget/security/bloat acceptable.

> **Runtime caveat (must be stated plainly):** the macOS relaunch failure that
> Tony observed (Demo Band → Cmd-Q within TTL → `./run.sh macos` reopened into
> Demo Band) is **fixed in code and tests only**. Everything below is code-path
> analysis + resolved-SDK-source confirmation + headless tests. QA does not and
> cannot run the app. **The fix is not confirmed at runtime until Tony completes
> owner punch-list steps 2–3 on a real native build.**

## Validation Summary

- Branch `feature/demo-session-no-relaunch-resume`; working tree clean-except-
  expected (3 plan-listed source/test files + 2 plan-listed docs +
  the 3 feature-doc pipeline artifacts, all uncommitted — correct at this pipeline
  stage; nothing committed until Manager's Release step after APPROVED).
- Both slugs (plan + report) match the branch and each other; Cycle numbers align
  (Architect amendment = Cycle 5, Engineer = Cycle 5, this QA = Cycle 5).
- Root-cause diagnosis **independently re-confirmed against the resolved SDK
  source** this cycle: `supabase_flutter` 2.17.2, gotrue 2.27.2, supabase 2.16.1,
  `shared_preferences` 2.5.5 (versions verified from `pubspec.lock`).
- Analyzer clean at every severity on all 3 changed Dart files; **18/18** focused
  tests and **298/298** full suite pass (all re-run independently by QA).
- No secrets, no `TODO`/`FIXME`/`debugPrint(` in code, no off-limits file touched,
  no DB/migration change, no `pubspec` change (no new dependency).
- The Cycle 4 blocking `[out-of-scope]` findings are closed by the plan amendment,
  not by any code change — Engineer Cycle 5 made no source/test edits (confirmed
  by diff review); the mechanism now matches the ratified plan.

## Architect Scope Review

**Files touched (all plan-listed — no off-limits or unplanned file):**

| File | Plan-listed? | Notes |
| --- | --- | --- |
| `lib/main.dart` | Yes | Native-only pre-init purge at init step 5.5, before `Supabase.initialize()`; old post-init block removed. |
| `lib/features/auth/demo_session_service.dart` | Yes | Two new static seams (`isPersistedSessionAnonymous`, `purgePersistedAnonymousSession`); old predicate removed; no existing method altered. |
| `test/features/auth/demo_lifecycle_predicate_test.dart` | Yes | Classifier (6) + storage-race (4) groups; obsolete truth-table group removed. |
| `docs/reference/general/AI_DECISIONS.md` | Yes | `DECISION-006` = pre-init step-5.5 mechanism. |
| `docs/reference/general/RUNTIME_CONFIG.md` | Yes | Init-order block shows step 5.5 before Supabase.initialize(). |

Off-limits surfaces confirmed **untouched** (diff + grep): `auth_state_provider.dart`
(`isAuthenticated == session != null` unchanged), `auth_gate.dart` (safeguards,
sync timer, `_reconcileOrphanedAnonymousSession` intact), `login_screen.dart`,
`app_shell.dart`, and all `supabase/**` (#289 TTL/cron/advisory-lock/migrations).
`pubspec.yaml`/`pubspec.lock` unchanged.

**Scope verdict:** file-scope **and** mechanism now both match the plan. The
amended plan's Proposed Solution, Decision (RATIFIED), Task Breakdown, Change
Budget, System Impact Map, and Verification Plan all describe the pre-init
step-5.5 disk purge the implementation ships. The superseded step-6.5 mechanism
survives only in the clearly-labeled "Superseded Mechanism (DISPROVEN; historical
only)" section, which is not an active instruction. The Cycle 4 governance blocker
is therefore resolved.

## Completeness Check

Every Architect task in the amended Engineer Task Breakdown is complete and
matches the shipped code:

- **Task 1 (classifier seam):** `isPersistedSessionAnonymous(String?)` returns
  `true` only when `decoded['user']['is_anonymous'] == true`; `false` for null,
  malformed JSON, missing `user`, or absent/`false` `is_anonymous`; wrapped in
  `try/catch`. Matches.
- **Task 2 (purge seam):** `purgePersistedAnonymousSession(supabaseUrl)` derives
  `'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`, awaits
  `prefs.remove(key)` only when the blob classifies anonymous, whole body in a
  swallow-and-continue `try/catch`; `dart:convert` + `shared_preferences`
  imported; no existing method altered. Matches.
- **Task 3 (`main.dart` step 5.5):** import added; native-only `await
  DemoSessionService.purgePersistedAnonymousSession(supabaseUrl)` sits after
  `validateSupabaseConfig()` and before the `Supabase.initialize()` try block; old
  post-init block gone; `FormatException` retry unchanged. Matches.
- **Task 4 (tests):** `isPersistedSessionAnonymous` (6 cases) +
  `purgePersistedAnonymousSession (startup storage race)` (4 cases) present;
  obsolete truth-table group removed. Matches.
- **Tasks 5–6 (`DECISION-006` / `RUNTIME_CONFIG.md`):** both describe step 5.5,
  the ratified persist-key coupling + upgrade fail-safe, and the local-purge-only
  choice. Matches.

No partial implementation, no missing edge case the plan specified.

## Behavior Verification

**Method: code-path analysis + resolved-SDK-source confirmation + headless tests.
No running app was used — that is Tony's job.** This is code-path analysis, not a
runtime-exercised end-to-end verification.

Root cause — **independently re-confirmed correct** in the pub-cache SDK source:

- **Non-awaited background restore.** `supabase_flutter-2.17.2/lib/src/supabase.dart`
  L156–159: after `await supabaseAuth.initialize(...)`, init assigns
  `_restoreSessionCancellableOperation = CancelableOperation.fromFuture(
  supabaseAuth.recoverSession())` — a fire-and-forget task that runs *after*
  `initialize()` returns. A post-init `signOut()` is deterministically undone by
  it; the plan's original mechanism was genuinely defective.
- **Both restores read the same disk key.** `supabase_auth.dart` L107–113
  (`initialize()`) and L143–149 (`recoverSession()`) each call
  `_localStorage.hasAccessToken()` / `accessToken()` then seed the session. With
  the key removed pre-init, **both** find nothing → `currentSession` stays `null`
  for the whole launch → routes to `LoginScreen`. Deterministic.
- **Key derivation matches the SDK exactly.** SDK (`supabase.dart` L132–133):
  `"sb-${Uri.parse(url).host.split(".").first}-auth-token"`. Purge:
  `'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`. Identical —
  and `main.dart` passes the *same* `supabaseUrl` constant to both
  `Supabase.initialize(url:)` and the purge, so derivation is guaranteed identical.
- **Default native backend matches.** `FlutterAuthClientOptions` defaults
  `localStorage` to null and `persistSession` to `true`
  (`flutter_go_true_client_options.dart` L34/L37); `supabase.dart` L127–136 then
  injects `SharedPreferencesLocalStorage`, whose `initialize()` uses
  `SharedPreferences.getInstance()` (`local_storage.dart` L80) — the exact same
  process-wide singleton the purge reads/removes from (L89 `containsKey`, L97
  `getString`, L105 `remove`). The awaited `prefs.remove(key)` before init is
  visible to the SDK's later `containsKey(key)`. No stale-cache race.
- **`is_anonymous` shape confirmed.** gotrue-2.27.2 `session.dart` L67 persists
  `'user': user.toJson()`; `user.dart` L118 always writes `'is_anonymous':
  isAnonymous` (a **bool**, L29, default `false`), `fromJson` L91 reads
  `json['is_anonymous'] ?? false`. So the classifier reads the identical field
  from the identical path the SDK uses to decide anonymity.
- **Real users provably never dropped.** A real-user blob always serializes
  `is_anonymous: false`; the classifier removes the key **only** on a positive
  `== true`, so a real session is never matched. The storage-race test asserts the
  real blob is preserved.
- **Malformed/legacy fail-safe = accepted residual.** Malformed/absent JSON → not
  purged (never drops a real user); a blob the SDK can't parse it also can't
  restore, so login still shows. Legacy Hive `MigrationLocalStorage` is documented
  "Not actually in use" (`local_storage.dart` L12), so there is no second on-disk
  location. The only path by which a demo could resume once is a *future* SDK
  key/shape change → the purge degrades to a silent no-op, bounded to one launch,
  backstopped by #289's untouched TTL + cron. Matches the plan's accepted residual
  exactly; a more aggressive classifier would violate the "never drop a real user"
  requirement.
- **Native-only gate / web:** purge gated `if (!kIsWeb)`; web uses
  `window.localStorage` (not `SharedPreferences`) and never creates an anonymous
  session, so the gate is both correct and inert on web.
- **Fresh in-run demo unaffected:** created post-startup via the demo button,
  never through `main()`; purged only on the *next* cold start, as designed.
- **FormatException path safe:** the retry inside the `Supabase.initialize()`
  block is unchanged and runs after the key is already purged, re-initializing
  from clean state.
- **#289 DB behavior:** no DB/migration/RPC/cron/edge-function change; server-side
  reclamation stays with the untouched TTL + cron.

## Regression Check

Overall regression risk of the code as written: **LOW–MEDIUM** (init-order and
auth-storage are high-sensitivity surfaces, but the change is tightly gated to
`user.is_anonymous == true` on disk and is native-only).

| Area | Risk | Finding |
| --- | --- | --- |
| Real-user session persistence | LOW | Classifier provably never matches a real session (bool always serialized `false`); storage-race test asserts the real blob preserved. |
| Auth semantics (`isAuthenticated`) | LOW | `auth_state_provider.dart` untouched (grep-confirmed). |
| Supabase RPC signatures / param order | NONE | No RPC or client-call signature change. |
| Anonymous reconcile backstop | LOW | `auth_gate_anonymous_recovery_test.dart` Tests A–E pass unchanged. |
| Init order | MEDIUM | Real init-order change (new step 5.5 *before* Supabase.initialize) — now logged consistently in `RUNTIME_CONFIG.md`, `DECISION-006`, and the amended plan. |
| Platform parity (web) | LOW | `!kIsWeb` gate; web backend differs and has no anon session. Native-only change does not affect web. |
| Controller/FocusNode disposal, setState-after-async | NONE | No widget/controller/lifecycle code touched. |
| Startup robustness | LOW | `purgePersistedAnonymousSession` swallows all errors; `main()` always reaches `Supabase.initialize()`. |
| Setlists/Gigs/Rehearsals/Members/Notifications | NONE | No touchpoints. |

## Database Safety

**n/a.** No migration, RLS policy, RPC, trigger, grant, cron, or edge-function
change. No `.sql` in the diff, so no Supabase branch apply-check is required (and
per instruction, remote Supabase/production was not touched). All #289 surfaces
off-limits and untouched. No new/changed `SECURITY DEFINER` function → no EXECUTE
grants to verify.

## Analyzer Results

`flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
test/features/auth/demo_lifecycle_predicate_test.dart` → **No issues found!**
(clean at every severity; ran independently by QA). No diff-touched file carries
any pre-existing violation.

## Test Results

- `flutter test test/features/auth/demo_lifecycle_predicate_test.dart
  test/features/auth/auth_gate_anonymous_recovery_test.dart` → **18 passed**
  (3 lifecycle + 6 `isPersistedSessionAnonymous` + 4 storage-race + 5 reconcile
  backstop A–E).
- `flutter test` (full suite) → **All 298 tests passed.** No new failures.

**Test-quality assessment (as requested):** the storage-race group seeds
`SharedPreferences.setMockInitialValues` under the exact SDK-derived key
(`sb-test-auth-token`) and asserts the anon blob is **removed** and the real-user
blob **preserved** — it exercises the **real storage state** the SDK restores
from, not merely the parser, and would fail if the purge did not actually clear
disk. It also distinguishes old from new mechanism: under the disproven post-init
sign-out the anon blob was still on disk at init time (the storage assertion would
fail), and the method under test did not even exist in the old truth-table design.
Honest limitation (declared and confirmed): the tests assert the storage
*precondition* (nothing left for the SDK to restore); they do **not** drive a full
`Supabase.initialize()` + background `recoverSession()` end-to-end, so race-closure
itself rests on SDK-source analysis + the storage assertion, not an executed
integration harness. Acceptable for a headless gate; runtime confirmation remains
owner-run.

## Diff Safety Review

- No secrets/API keys/tokens introduced (grep for `api_key|secret|password|eyJ…|
  BEGIN PRIVATE` on added lines → none).
- No `TODO`/`FIXME`/`debugPrint(` in the code/test diff (grep-confirmed on added
  lines). The old step-6.5 block's `debugPrint` was removed with that block.
- No leftover scaffolding, no accidental deletions, no unrelated formatting churn.
- `git diff --check` clean (no whitespace errors).
- Tony's uncommitted `AI_DECISIONS.md` Markdown-escaping edits were used as the
  base and incorporated into the `DECISION-006` rewrite (not reverted).

## Change Budget Review

Measured against the amended plan's Change Budget (which ratifies the Cycle 4
`git diff --numstat` actuals as the budget), via `git diff --numstat HEAD`:

| File | Ratified budget (net) | Actual | Match |
| --- | --- | --- | --- |
| `lib/main.dart` | ≈ −11 (+12/−23) | +12 / −23 = **−11** | exact |
| `lib/features/auth/demo_session_service.dart` | ≈ +34 (+45/−11) | +45 / −11 = **+34** | exact |
| `test/…/demo_lifecycle_predicate_test.dart` | ≈ +86 (+111/−25) | +111 / −25 = **+86** | exact |
| `docs/…/AI_DECISIONS.md` | ≈ +86/−61 | +86 / −61 | exact |
| `docs/…/RUNTIME_CONFIG.md` | ≈ ±1 | +1 / −1 | exact |

New files: **0** (matches). New public members: **2**
(`isPersistedSessionAnonymous`, `purgePersistedAnonymousSession`) — matches the
ratified budget. New dependencies: **0** (`shared_preferences` already declared
`^2.2.2`; no `pubspec` change). Every actual is at ~1.0x of the ratified budget —
well within the 1.5x threshold. The Cycle 4 budget-breach warning is **resolved**
by the amendment resetting the budget to this mechanism.

## Code Efficiency Review

- **Reuse check performed independently.** Grepped `lib/` for any pre-existing
  persist-key derivation / `is_anonymous` purge helper — **none** outside the two
  new seams. `shouldReleaseDemoOnLifecycle` is lifecycle-release; the `isAnonymous`
  checks in `auth_gate.dart` / `app_shell.dart` are inline runtime routing, not a
  reusable pure classifier. The two new seams are justified; no duplication.
- No `_buildX()`/private widget, no new provider/notifier, no
  `Future`/`StreamBuilder`, no hand-rolled dedupe/grouping loop, no new model
  field or `copyWith` entry, no barrel file, no "for future use" flags/enums.
- The two `try/catch` blocks swallow-and-continue **by design** (startup must
  reach `Supabase.initialize()`; a malformed blob must fail safe) — appropriate,
  not log-and-rethrow noise.
- Comments state *why* (the non-awaited background restore), not *what*.
- This is a root-cause fix that **deletes** the defective mechanism (121 deletions
  this cycle: the step-6.5 block + old predicate + old truth-table tests), not an
  addition layered on the bug.
- File sizes within target (`main.dart` 337, `demo_session_service.dart` 141; both
  < 500). No justification required.

## Manual Verification Punch List (owner-run — Tony; requires a running app)

**None of these are QA gates.** They require a running native app and are Tony's
to run (per the plan's Verification Plan, correctly classified as owner-run). QA
does not and cannot execute them. Run on a **native** build (macOS, plus at least
one of iOS/Android):

1. Login screen → tap "Check out the demo band". **Expected:** lands in Demo Band
   (fresh in-run session unaffected).
2. **Reproduce the Cycle-3 failure:** in Demo Band, fully quit (macOS Cmd-Q; mobile
   swipe-kill) **well within the 8-minute TTL**, then `./run.sh macos` (a genuine
   cold `main()` launch). **Expected (was failing):** the app presents the **login
   screen** — it does **not** resume into Demo Band.
3. Repeat step 2 with the device in **airplane mode / no network**. **Expected:**
   still the login screen (the purge is a local `SharedPreferences` op; no network
   needed).
4. Real-user regression: sign in as a normal (non-anonymous) account, quit, reopen.
   **Expected:** resumes straight into the account, **no** login prompt.
5. Web smoke (any browser): no demo button; normal real-user resume across a page
   reload is unchanged.

**The macOS relaunch is fixed in code/tests/analysis only until Tony completes
steps 2–3 successfully.** Those steps are the authoritative runtime confirmation;
this APPROVED verdict certifies the code/analysis/test gate, not the on-device
behavior.

## Issues Found

### Critical

None. (Cycle 4's two Critical `[out-of-scope]` findings — the unratified
mechanism deviation and the unratified SDK-internal persist-key coupling — are
**resolved** by the Cycle 5 plan amendment, which ratifies both explicitly in the
Proposed Solution, the "Decision (RATIFIED)" section, and `DECISION-006`.)

### Warnings

None. (Cycle 4's `[code-quality]` change-budget breach is resolved by the reset
budget; the authoritative-doc contradiction is resolved — plan, `DECISION-006`,
and `RUNTIME_CONFIG.md` now all describe step 5.5.)

### Suggestions

1. **[code-quality] Runtime race-closure is asserted only at the storage level.**
   The headless tests prove nothing is left on disk for the SDK to restore, which
   — with the SDK-source analysis — is sound, but no executed harness drives
   `Supabase.initialize()` + background `recoverSession()` end-to-end. This is a
   reasonable and plan-accepted headless limitation; the owner punch list (esp.
   steps 2–3) remains the authoritative runtime confirmation. No action required
   for approval.

## Notes For Manager

- **Verdict: APPROVED.** The Cycle 5 plan amendment closes the only Cycle 4
  blocker (the mechanism/plan mismatch). The implementation matches the amended
  plan's Task Breakdown exactly; Engineer Cycle 5 made no source/test change (diff-
  confirmed). Diagnosis independently re-confirmed in the resolved SDK source;
  analyzer clean; 18 focused + 298 full tests green; no DB change; no secrets/debug
  artifacts; scope/budget/security/bloat all acceptable.
- **Regression risk: LOW–MEDIUM**, concentrated in init-order + auth-storage, both
  tightly gated (`user.is_anonymous == true`, native-only, swallow-and-continue).
- **Runtime caveat (must travel with this approval):** the previously-failing
  macOS relaunch behavior is fixed **in code/tests/analysis only**. QA cannot run
  the app. It is **not** confirmed on-device until Tony executes owner punch-list
  steps 2–3 (and ideally 3 in airplane mode) on a real native build. Hand Tony the
  punch list above verbatim.
- Report path: `docs/features/demo-session-no-relaunch-resume/QA_REPORT.md`.
