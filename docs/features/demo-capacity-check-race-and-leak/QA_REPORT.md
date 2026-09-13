# QA Report

## Feature Slug
`bug/demo-capacity-check-race-and-leak`

## Feature Title
Demo session cap (30 concurrent) has no atomic enforcement, and abandoned sessions occupy
slots for up to ~20 minutes

## Cycle Number
2

## Final Verdict
**APPROVED**

> **Scope of this APPROVAL:** the amended plan's **static + headless QA gate** — `flutter
> analyze` (clean), the `shouldReleaseDemoOnLifecycle` predicate test (3/3), the static SQL
> review + byte-diff against already-applied-to-prod SQL, and the scope / diff-safety / change-
> budget review. All were **executed this cycle and passed**.
>
> **Why the prior Critical is resolved (not masked).** QA Cycle 1 returned REQUIRES CHANGES on
> a single Critical `[database-safety]` item whose entire cause was environmental: the isolated
> migration apply-check (former Tier 1 #4) and runtime grant assertions (Tier 1 #5) were
> mandated as a **QA gate**, yet no agent-runnable isolated Supabase environment exists here.
> Cycle 1's own actionable resolution (b) was "Architect amends the Verification Plan to
> explicitly reclassify Tier 1 #4–5 (and Tier 2 #7–8) as owner-run checks for Tony." The
> Architect has now done exactly that (plan "Cycle 2 amendment" block): the QA gate is the
> static + headless scope, and clean apply, grant assertions, concurrency, reclaim, idempotency,
> and live-app A/B/C are reclassified as an **owner-run pre-apply Manual Verification Punch
> List**. QA independently re-verified the amendment is genuinely environmental and does **not**
> mask an implementation defect (see Database Safety): (1) `docker`/`colima`/`podman`/`nerdctl`
> are all **NOT FOUND**, so no local Supabase stack can start; the only Supabase CLI link is to
> the **remote production project** ("Band Roadie", ref `nekwjxvgbveheooyorjo`), which QA is
> forbidden to touch (including via branch); (2) the entire novel SQL surface is ~6 lines, every
> other statement byte-identical to SQL already applied to prod, so there is essentially no
> room for a hidden novel apply-time error. Safety is unchanged: every DB check still runs
> **before** the migration reaches prod — by Tony, who applies every migration manually anyway,
> on an environment he controls. This APPROVAL is explicitly conditioned on Tony completing the
> attached punch list **before** applying the migration to production.

## Validation Summary
| Gate | Result | Method |
|------|--------|--------|
| Branch / working-tree state | PASS | `git branch --show-current`, `git status` |
| Slug match (plan ↔ report ↔ branch) | PASS | file read |
| Prior report not already ≥ Cycle 2 / APPROVED | PASS | existing report was Cycle 1 / REQUIRES CHANGES |
| Plan amendment genuine (environmental, not masking) | PASS | container-runtime probe + remote-link probe + byte-diff |
| Scope (only plan-listed files touched) | PASS | `git status`, `git diff --numstat` |
| Provision function verbatim + lock placement | PASS (executed) | byte-diff vs authoritative `20260912122827` |
| Heartbeat / expires / cron deltas faithful | PASS (executed) | read vs authoritative `20260908194500` / `20260904120005` |
| SECURITY DEFINER + search_path + grants re-issued | PASS (static) | SQL review (not runtime-executed) |
| Analyzer (diff files) | PASS (executed) | `flutter analyze` (scoped) — clean |
| Predicate unit test | PASS (executed) | `flutter test` — 3/3 |
| Diff safety (secrets / TODO / FIXME / debugPrint) | PASS (executed) | grep of added lines + new files |
| Change budget / bloat | PASS (2 Suggestions) | `git diff --numstat` + file line counts vs plan budget |
| Clean apply / grants / concurrency / reclaim / idempotency / A/B/C | OWNER-RUN | reclassified by amended plan → punch list (not a QA gate) |

## Cycle 2 Delta
- Engineer Cycle 2 made **zero source/migration/test changes**; the working tree is byte-for-byte
  identical to Cycle 1 (`git diff --numstat`: `AI_DECISIONS.md` +81, `auth_gate.dart` +9,
  `demo_session_service.dart` +22; migration and predicate test unchanged untracked files).
- The only substantive change this cycle is the **Verification Plan amendment** (verification
  contract only; implementation scope unchanged), which QA independently validated as the correct
  resolution of the Cycle 1 Critical.
- All static + headless gate checks were **re-executed fresh this cycle** (not inherited from
  Cycle 1): analyzer clean, predicate test 3/3, provision/heartbeat/cron byte-diffs re-run.

## Architect Scope Review
All changes are confined to the plan's declared surface — no out-of-scope or unapproved files
touched, no off-limits file edited, no unrelated formatting churn.

- **Modified (all plan-listed):** `lib/features/auth/auth_gate.dart`,
  `lib/features/auth/demo_session_service.dart`, `docs/reference/general/AI_DECISIONS.md`.
- **Created (all plan-listed):** `supabase/migrations/20260912130000_demo_session_capacity_hardening.sql`
  (timestamp strictly > `20260912122827` ✓), `test/features/auth/demo_lifecycle_predicate_test.dart`.
- **Off-limits files confirmed untouched:** `20260912122827_demo_relative_date_offsets.sql`,
  `20260904120003_provision_demo_session_rpc.sql`,
  `20260904120004_exit_and_heartbeat_demo_session_rpc.sql`,
  `20260908194500_reduce_demo_session_ttl_to_15min.sql`,
  `supabase/functions/exit-demo-session/index.ts`, `lib/features/shell/app_shell.dart`,
  `lib/features/auth/login_screen.dart`, and the client `demo_capacity_exceeded` rejection path.
- Untracked `docs/features/demo-capacity-check-race-and-leak/` is the expected pipeline-artifact
  directory (plan/report/this QA report), not an implementation change.

## Completeness Check
All 7 ordered Architect tasks are implemented (static/headless confirmation):

1. ✅ New layered migration re-declares `provision_demo_session()` **verbatim** + one advisory
   lock. Byte-diff of the full function body (authoritative `20260912122827` → new file) shows
   **only** a 5-line insertion (3 comment lines + `PERFORM pg_advisory_xact_lock(8675309001);`
   + a blank line) at `72a73,77` — i.e. immediately **after** the idempotency
   `IF FOUND ... RETURN ... END IF;` and **before** `SELECT count(*) INTO v_live_count`. Nothing
   else in the ~427-line body changed. `REVOKE ALL ... FROM PUBLIC, anon` +
   `GRANT EXECUTE ... TO authenticated` re-issued.
2. ✅ `expires_at` default → `now() + interval '8 minutes'` (line 472);
   `heartbeat_demo_session()` byte-identical to authoritative `20260908194500` except
   `15 minutes` → `8 minutes` (line 487) + the fixed-TTL comment; REVOKE/GRANT re-issued.
3. ✅ Cron reschedule `*/2 * * * *` (line 511) via guarded `cron.unschedule` DO-block +
   `cron.schedule` + the loud post-assertion — byte-identical to the authoritative
   `20260904120005` pattern except the `*/5` → `*/2` schedule string.
4. ✅ `DemoSessionService.releaseSlotOnDetach()` (static, ref-free, fire-and-forget invoke of
   `exit-demo-session`, all errors swallowed) + pure predicate
   `shouldReleaseDemoOnLifecycle(state, {required isAnonymous})` returning `true` only for
   `detached && isAnonymous`.
5. ✅ `auth_gate.dart` `didChangeAppLifecycleState`: doubly-gated (`detached` + `isAnonymous`)
   `unawaited(releaseSlotOnDetach())` placed immediately before `_previousLifecycleState = state;`;
   the `resumed` branch is untouched.
6. ✅ `[DECISION-005]` appended to `AI_DECISIONS.md`.
7. ✅ `demo_lifecycle_predicate_test.dart` added (3 tests).

No skipped or partial tasks.

## Behavior Verification

### Defect 1 — atomic admission (CODE-PATH ANALYSIS, not runtime-exercised)
- `pg_advisory_xact_lock(8675309001)` is a **transaction-scoped** exclusive advisory lock.
  `provision_demo_session()` is invoked as a single RPC = single transaction, so the lock is
  held across `count → INSERT reservation → clone → COMMIT` and auto-released on commit **or**
  rollback (no leak on error).
- Placement is **after** the idempotency early-return, so genuinely-returning callers
  early-return and never contend for the lock; it is **before** the ceiling `SELECT count(*)`,
  so every new provision reads a count that already includes any prior committed reservation.
  Invariant (by construction): no two new provisions both observe `count < 30` for the same
  slot ⇒ live rows with `expires_at > now()` never exceed 30. Expired-but-unreaped rows are
  excluded by the `expires_at > now()` filter, so freed slots remain immediately reusable.
- **Idempotent returning callers preserved:** the early-return and the `unique_violation`
  handler are unchanged and both sit around/before the lock. A *sequential* re-provision under
  the same anon uid hits the idempotency early-return and returns identical `clone_band_ids`
  with no second clone (plan Tier 2 #8) — the returning-caller path is not blocked or altered.
- **This correctness argument is static (code-path) only.** The genuine concurrent proof (N
  parallel spoofed-anon callers → exactly one succeeds, live count never 31+) was **NOT
  executed** — no isolated DB. Plan-authorized owner-run (see Punch List).

### Defect 2 — best-effort release + faster reclaim (predicate runtime-verified; rest code-path)
- `shouldReleaseDemoOnLifecycle` runtime-verified by the unit test: `true` only for
  `(detached, isAnonymous: true)`; `false` for `(detached, isAnonymous: false)` and for every
  non-detached state (`resumed`/`inactive`/`hidden`/`paused`).
- `releaseSlotOnDetach()` is fire-and-forget: `async` but invoked via `unawaited(...)` in the
  lifecycle handler, so it **does not await in lifecycle code** and cannot block shutdown or
  background transitions. All errors swallowed; DB cron sweep is the guaranteed backstop.
- Doubly-gated (`detached` + `isAnonymous`) ⇒ cannot fire for real (non-anonymous) users or on
  ordinary backgrounding, and is inert on web (no anon demo session exists there).
- 8-min TTL / 2-min cron are internally consistent: both `8 minutes` occurrences (default line
  472, heartbeat line 487) agree, and the cron string is `*/2` (line 511).

## Regression Check — Overall risk: **LOW–MEDIUM** (leaning LOW)
| Area | Risk | Notes |
|------|------|-------|
| Auth / session (real users) | LOW | Teardown gated on `isAnonymous`; real-user login/session/routing untouched; `resumed`-refresh branch unchanged. |
| Init order / splash | LOW | No change to `initState`, splash, or init sequence; new branch only appends to `didChangeAppLifecycleState`. |
| Lifecycle correctness | LOW | `unawaited(...)` fire-and-forget; `detached`-only gating prevents false teardown on background/return. |
| Supabase RPC signatures | LOW | `provision_demo_session()` / `heartbeat_demo_session()` signatures unchanged (0-arg); client calls (`rpc('provision_demo_session')`, `rpc('heartbeat_demo_session')`) match. |
| Platform parity | LOW | Native-only demo; web inert (predicate false); no web-only path altered. |
| Controller/FocusNode disposal, setState-after-async | LOW | No new controllers/FocusNodes; no `setState` added; predicate is pure; no rebuild-trigger change. |
| Imports | LOW | `import 'package:flutter/widgets.dart' show AppLifecycleState;` is `show`-scoped (no bulk material pull-in); `unawaited` sourced from existing `dart:async` in `auth_gate.dart`. |

**Minor code-path observation (non-blocking, see Suggestions):** because the lock now
serializes new provisions, *two truly-concurrent first-time provisions from the **same** anon
uid* at the exact 29→30 capacity boundary could return `demo_capacity_exceeded` to the second
caller instead of the idempotent clone ids (the second caller's post-lock count now includes
the winner's committed row, and it raises before reaching the `unique_violation` handler). This
is **not** a returning-caller regression (returning callers early-return before the lock and
are fully preserved) and is **not reachable by the actual client**, which awaits a single
sequential `provision_demo_session()` per entry.

## Database Safety
Read of the actual SQL (not filenames):

- **Verbatim preservation confirmed by byte-diff**, not eyeballing: provision body identical
  except the 5-line lock insertion; heartbeat identical except `15`→`8 minutes`; cron block
  identical except `*/5`→`*/2`; `expires_at` default identical except `15`→`8 minutes`. Every
  statement in the migration is therefore either byte-identical to SQL **already applied to
  production** (via `20260912122827`, `20260908194500`, `20260904120005`) or a literal-constant
  change on top of it — leaving essentially no room for a novel syntax error.
- Both re-declared functions retain `SECURITY DEFINER` + `SET search_path = public`.
- Grants (static review): `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon` + `GRANT EXECUTE ...
  TO authenticated` re-issued for **both** functions, so `anon` never gains EXECUTE. No new
  SECURITY DEFINER function introduced. RLS unchanged; no self-referencing/recursive policy; no
  privilege escalation; no destructive cascade.
- **Independently re-confirmed this cycle — no agent-runnable isolated environment exists:**
  `docker` / `colima` / `podman` / `nerdctl` are **all NOT FOUND**, so `supabase db reset` /
  `supabase start` cannot bring up a local Supabase stack; the only Supabase CLI link
  (`supabase/.temp/linked-project.json`) is to the **remote production project** ("Band Roadie",
  ref `nekwjxvgbveheooyorjo`). QA is forbidden to touch production or the remotely linked
  project — including via a preview branch, which is a cloud resource of that linked project and
  has previously produced a real production side effect. There is therefore no isolated Supabase
  environment any agent can use, and no fallback-to-prod is permissible.
- **NOT runtime-executed (correctly reclassified as owner-run by the amended plan):**
  - Ephemeral apply-check (`supabase db reset` + `SELECT 1 FROM cron.job WHERE jobname =
    'cleanup_demo_sessions'`).
  - Runtime privilege assertions via `has_function_privilege('anon' | 'authenticated',
    'public.provision_demo_session()'::regprocedure, 'EXECUTE')` (and for
    `heartbeat_demo_session()`).
  - Concurrency / reclaim / idempotency DB behavior.
- **Consequence (Cycle 2):** clean apply and privilege correctness are established **statically
  to a high degree** — the entire novel SQL surface is ~6 lines and every other statement is
  byte-identical to already-applied-to-prod SQL, so there is essentially no room for a hidden
  novel apply-time error. Per the **amended** Verification Plan these DB checks are an
  **owner-run pre-apply Manual Verification Punch List**, not a QA gate; QA validated the
  amendment as genuinely environmental (not masking any defect). This is **no longer a blocking
  gap** — it is routed to Tony, who must run the punch list before applying to prod. QA's
  APPROVAL is scoped accordingly and explicitly conditioned on that pre-apply run.

## Analyzer Results
`flutter analyze lib/features/auth/auth_gate.dart lib/features/auth/demo_session_service.dart
test/features/auth/demo_lifecycle_predicate_test.dart` → **"No issues found!"** (clean at every
severity, ran in ~1.9s). No pre-existing violations in the touched files.

## Test Results
`flutter test test/features/auth/demo_lifecycle_predicate_test.dart` → **All 3 tests passed**:
- `(detached, isAnonymous: true)` → true.
- `(detached, isAnonymous: false)` → false.
- every non-detached state (`resumed`/`inactive`/`hidden`/`paused`) with `isAnonymous: true`
  → false.

This runtime-proves the lifecycle **predicate** (the testable seam), exactly as the plan's
Verification Plan Tier 1 item 2 requires. It does **not** exercise the DB-side concurrency
invariant (that is Tier 2 / owner-run).

## Diff Safety Review
- No secrets / API keys / tokens introduced (grep of added lines + new files: none).
- No `TODO` / `FIXME` / `debugPrint(` added anywhere in the diff or the new files. (The two
  pre-existing `debugPrint` calls in `demo_session_service.dart` `provisionAndEnter` are
  outside the diff and untouched.)
- No leftover test scaffolding, no accidental deletions (diff is +112 tracked / 0 deletions;
  all additive), no unrelated churn.

## Change Budget Review
| File | Plan budget | Actual | Assessment |
|------|-------------|--------|------------|
| `auth_gate.dart` | +8 to +14 | **+9** | within budget ✓ |
| `demo_session_service.dart` | +12 to +18 | **+22** | ~1.2× (extra = `show`-import + doc comments); acceptable |
| `demo_lifecycle_predicate_test.dart` | ~30–50 (new) | **52-line file** | ~1.04×; fine |
| migration (new) | ~360 (meaningful ~6) | **522 lines** | verbatim re-declaration is mandatory (plpgsql has no in-place insert); every line diff-proven identical-to-applied-prod except ~6 meaningful lines; not bloat |
| `AI_DECISIONS.md` | +~25 | **+81** | >3× the plan's numeric estimate — but see below |
| New files | 2 | **2** | ✓ |
| New public methods | 2 | **2** (`releaseSlotOnDetach`, `shouldReleaseDemoOnLifecycle`) | ✓ |
| New dependencies | 0 | **0** | ✓ |

- **`AI_DECISIONS.md` +81 vs +25 budget:** numerically >3×, which the arithmetic rule would
  flag. Judgment override to **Suggestion, not Critical**: the added content is exactly the
  **one** required DECISION entry (plan task 6) and is **proportionate to the established local
  format** — measured this cycle, prior entries run 36/38/45/**75** lines; `[DECISION-005]` (81
  lines) is the same order as the nearest comparable substantive entry `[DECISION-004]` (75) and
  uses the same house sections (Context / Decision / Rationale / Constraints Imposed / Rollback
  Plan). This is documentation matching house style, not scope-inflating maintenance burden. The
  plan's numeric estimate was simply low relative to the repo's actual DECISION-entry norm.
- **Zero-deleted-lines guardrail:** the fix is legitimately additive — both defects are *missing*
  behavior (a missing serialization point; a missing lifecycle handler + faster reclaim), and
  `ENGINEER_REPORT.md` states this explicitly. Guardrail satisfied; no Warning.
- **File-size targets:** `auth_gate.dart` (751) is over the 500-line Dart target but is
  pre-existing; this cycle adds only a 9-line branch to a plan-listed *modify* file, and
  splitting is out of scope — `ENGINEER_REPORT.md` provides the one-line justification. Migration
  (522) is not Dart and is governed by the verbatim-re-declaration constraint, justified in the
  report. Satisfied.

## Code Efficiency Review
- **Reuse verified independently:** grepped `lib/` for a pre-existing equivalent of the two new
  symbols (`releaseSlot`, `onDetach`, `shouldRelease`, `AppLifecycleState.detached` handling)
  outside the two touched files — none found. The two new methods are genuinely new surface, not
  duplicates of an existing helper.
- No AI-shaped bloat: no single-use `_buildX()`/private widget, no new provider/notifier/
  controller/repository (plan forbids), no `FutureBuilder`/`StreamBuilder`, no hand-rolled
  first-match/dedupe loop that `package:collection` provides, no unused field/param/`copyWith`
  entry, no barrel file, no future-use flags/enum cases, no restating comments, no single-call-site
  wrapper.
- `try/catch` in `releaseSlotOnDetach()` intentionally swallows all errors (fire-and-forget best
  effort during termination; cron is the backstop) — it does not log-and-rethrow and does not
  catch what cannot be thrown. Appropriate.

## Manual Verification Punch List — owner-run (Tony); NOT a QA gate; required BEFORE the migration is applied to prod
Reproduced from the amended Architect plan. Run on an environment **Tony controls** — his local
Docker Supabase stack (`supabase db reset` / `supabase start`, local Postgres :54322) or a
staging/branch project he owns. **Never production; never the remotely linked project — not even
a rolled-back or throwaway attempt.** Items 1–5 are DB checks; items 6–8 (A/B/C) are live-app
checks. All demo rows are harness-created and cleaned up; no production UUIDs.

1. **Clean migration apply.** `supabase db reset` on a fresh local stack. *Expected:* completes
   with **no error**; `SELECT 1 FROM cron.job WHERE jobname = 'cleanup_demo_sessions';` returns
   exactly one row.
2. **Grant assertions.** After apply, run (privilege-correct, never an ACL string-match — a
   `PUBLIC` grant satisfies a string-match for every role):
   `SELECT has_function_privilege('anon', 'public.provision_demo_session()'::regprocedure,
   'EXECUTE');` → **false**;
   `SELECT has_function_privilege('authenticated', 'public.provision_demo_session()'::regprocedure,
   'EXECUTE');` → **true**. Repeat both for `public.heartbeat_demo_session()`. *Expected:*
   `anon` = false, `authenticated` = true for **both** functions.
3. **Concurrency admission — core defect-1 proof.** Seed 29 live `demo_sessions`; create 10 anon
   `auth.users` with fresh UUIDs; open 10 parallel `psql` connections, each
   `SELECT set_config('request.jwt.claims', json_build_object('is_anonymous', true, 'sub',
   '<that-uuid>', 'role', 'authenticated')::text, true);` then `provision_demo_session()`.
   *Expected:* exactly **1** succeeds, **9** raise `demo_capacity_exceeded`, and
   `SELECT count(*) FROM demo_sessions WHERE expires_at > now();` = **30 (never 31+)**. Repeat
   from an empty table with 40 parallel callers → final live count exactly **30**. Truncate
   seeded demo rows and delete seeded `auth.users` at the end.
4. **Reclaim.** *Expected:* a fresh provision's `expires_at ≈ now() + 8 min`;
   `heartbeat_demo_session()` renews to `now() + 8 min`; a row inserted with `expires_at =
   now() - interval '1 minute'` is deleted by `cleanup_expired_demo_sessions()`.
5. **Idempotency.** Call `provision_demo_session()` twice under the same spoofed anon uid.
   *Expected:* identical `clone_band_ids` both times; `SELECT count(*) FROM bands WHERE
   demo_session_id = <that session>;` stays at **2** (no second clone pair).
6. **A — Graceful-close release (macOS, live app).** Enter the demo; `Cmd-Q` without tapping
   Exit Demo; query `demo_sessions` for that `auth_user_id` within ~10s. *Expected:* row gone
   (best-effort `detached` hook fired).
7. **B — Hard-kill reclaim (iOS or Android, live app).** Enter the demo; force-swipe-kill; query
   the row immediately (may still be present), then again after ~10 min. *Expected:* gone by
   then (TTL 8 min + cron ≤2 min).
8. **C — Background survival, no false teardown (live app).** Enter the demo; background the app
   <8 min; return. *Expected:* demo still alive (heartbeat), confirming TTL is not too aggressive
   and `detached` did not fire on mere backgrounding.

## Issues Found

### Critical
**None.** The Cycle 1 Critical `[database-safety]` (mandatory agent-run migration apply-check +
grant assertions with no isolated environment) is **resolved** by the Architect's Cycle 2
Verification Plan amendment, which adopted Cycle 1's own actionable resolution (b): the
clean-apply, grant, concurrency, reclaim, and idempotency DB checks are now correctly classified
as an **owner-run pre-apply Manual Verification Punch List** for Tony, not a QA gate. QA
independently verified the amendment is genuinely environmental (no container runtime; only a
remote-linked production project) and does **not** mask an implementation defect — the novel SQL
surface is ~6 lines, all literal-constant changes on byte-identical already-applied-to-prod SQL.
Every DB check still runs before prod, by the only party who can structurally run it. This is a
plan-amendment resolution of an environmental blocker, not a re-classification QA performed on
its own authority.

### Warnings
None.

### Suggestions
1. **[code-quality] Concurrent same-uid first-time provisions at the exact 29→30 boundary.**
   After the lock, a second *truly-concurrent* provision from the **same** anon uid could receive
   `demo_capacity_exceeded` rather than the idempotent clone ids (its post-lock count now includes
   the winner's committed row, raising before the `unique_violation` handler). Not a
   returning-caller regression, not reachable by the current client (single sequential provision
   per entry), and not a plan violation — noted only for completeness. No change required.
2. **[code-quality] `AI_DECISIONS.md` entry is +81 lines vs the plan's +25 estimate.**
   Proportionate to the local format (`[DECISION-004]` measured 75 lines this cycle) and is the
   single required entry using the same house sections (Context / Decision / Rationale /
   Constraints Imposed / Rollback Plan); recorded as an observation, not a defect.

## Notes on Method (static vs runtime, per QA discipline)
- **Runtime-exercised here:** analyzer (scoped, clean); the `shouldReleaseDemoOnLifecycle`
  predicate (3/3 unit tests).
- **Code-path / static-proof only (explicitly NOT runtime):** the advisory-lock concurrency
  invariant; the migration's clean apply; the EXECUTE grants; reclaim/idempotency DB behavior;
  and all live-app lifecycle behavior (macOS quit / hard-kill / background survival). These are
  handed off via the Punch List. "Confirmed in code" ≠ "confirmed at runtime" throughout this
  report.
