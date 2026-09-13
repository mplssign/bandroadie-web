# Architect Plan

## Feature Slug
`bug/demo-capacity-check-race-and-leak`

## Feature Title
Demo session cap (30 concurrent) has no atomic enforcement, and abandoned sessions occupy slots for up to ~20 minutes

## Problem Summary
`provision_demo_session()` enforces a hardcoded ceiling of 30 live demo sessions with a
non-atomic **count-then-insert**, and there is no client signal that releases a demo slot
when a visitor abandons the demo (closes/kills the app) without tapping "Exit Demo". Two
independent defects:

1. **Check-then-insert race.** The `SELECT count(*) ... WHERE expires_at > now()` ceiling
   check and the subsequent `INSERT INTO demo_sessions` are not serialized by any lock,
   partial index, or isolation guarantee. Under READ COMMITTED, N concurrent first-time
   visitors can each read `count < 30` before any commits, provisioning **more than 30**
   simultaneous sessions — each cloning two full template bands (heavy write amplification).

2. **Abandoned-slot leak.** `exit_demo_session()` runs only on the explicit "Exit Demo"
   tap. When a visitor closes/kills the app instead, the slot stays occupied until
   `expires_at` (up to 15 min after the last heartbeat) plus up to 5 min for the
   `cleanup_demo_sessions` cron sweep — **up to ~20 minutes of a wasted slot per drive-by
   visitor**, which compounds defect 1 by lowering real available capacity below 30.

## Root Cause

### Defect 1 — race (Confidence: HIGH)
Confirmed in [supabase/migrations/20260912122827_demo_relative_date_offsets.sql](supabase/migrations/20260912122827_demo_relative_date_offsets.sql#L146-L157):
the ceiling section reads a live count and, only if `< 30`, proceeds to insert the
`demo_sessions` reservation row. Nothing serializes the interval between the count and the
insert. The table's only uniqueness guard is `UNIQUE (auth_user_id)` (see
[supabase/migrations/20260904120000_demo_bands_schema.sql](supabase/migrations/20260904120000_demo_bands_schema.sql#L16)),
which prevents the *same* visitor double-provisioning but does nothing for the 30-wide
cardinality cap. A unique index cannot express "at most 30 rows"; only serialization can.

### Defect 2 — leak (Confidence: HIGH)
Confirmed across three files:
- Teardown is reachable only from the explicit tap:
  [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart#L309-L327) →
  [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart#L51-L64)
  → the `exit-demo-session` Edge Function → `exit_demo_session()` RPC.
- The lifecycle observer in [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L118-L146)
  handles only `AppLifecycleState.resumed`; there is **no** `detached`/`hidden` handler and
  no web `beforeunload` handler that releases a demo slot on close.
- TTL is a 15-minute sliding window: `expires_at` default is `now() + 15 minutes` and
  `heartbeat_demo_session()` renews to `now() + 15 minutes`
  ([supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql#L6-L26)).
  Heartbeats fire from the 5-second timer in
  [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L81-L112) only while
  the process is alive. Cron reaps expired rows every 5 minutes
  ([supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql](supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql#L60-L64)).
  A killed app stops heartbeating → slot held to `expires_at` (≤15 min) + ≤5 min cron.

## Existing System Analysis

### Merge-state reconciliation (corrects a stale premise in the Feature Input)
The Feature Input states `feature/demo-relative-date-offsets` is *not yet merged*. **That is
now stale.** As of this diagnosis it is **merged to `main`** — commit
`9c28ab4` ("feat(demo): make template dates relative (#288)") — and its migration
`20260912122827_demo_relative_date_offsets.sql` is tracked on `main` and is the authoritative
live definition of `provision_demo_session()`. Consequences:
- The fix must **layer a NEW migration on top of** `20260912122827` (later timestamp), doing
  a full `CREATE OR REPLACE FUNCTION` that reproduces the current body verbatim plus the lock
  line. The later migration is authoritative going forward.
- `20260912122827_...` is **off-limits** — it is committed and already applied to production;
  editing it would diverge the repo from prod.
- The older `20260904120003_provision_demo_session_rpc.sql` is superseded and inert; editing
  it changes nothing live — **off-limits**.

### Confirmed facts driving the design
- `provision_demo_session()` runs as one transaction (single RPC statement), so a
  transaction-scoped advisory lock spans the whole body and auto-releases on commit/rollback.
- The idempotency early-return for returning visitors
  ([20260912122827 L131-L141](supabase/migrations/20260912122827_demo_relative_date_offsets.sql#L131-L141))
  precedes the ceiling check, so serializing the ceiling section does not block returning
  visitors — only genuinely-new provisions.
- `demo_sessions` RLS is already correct and non-recursive (predicate references only
  `auth.uid()`); no INSERT/DELETE policy — writes come only via SECURITY DEFINER RPCs.
- `DemoSessionService.exit(WidgetRef ref)` does not actually use `ref` — it only uses the
  Supabase client — so a ref-free best-effort variant is trivial.
- `AppLifecycleState.detached` fires on true termination, **not** on ordinary backgrounding
  (which delivers `inactive`/`hidden`/`paused`), so gating the teardown strictly on
  `detached` avoids tearing down a demo the visitor intends to return to.
- Demo entry is native-only: [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L53)
  gates the demo button on `!kIsWeb`. Web never holds an anonymous demo session, so the
  lifecycle teardown is inert on web.

## Proposed Solution

### Defect 1 — atomic admission via transaction advisory lock
In the new layered migration's `CREATE OR REPLACE FUNCTION provision_demo_session()`, insert a
single serialization point immediately **before** the ceiling count and **after** the
idempotency early-return:

```sql
-- Serialize the count-then-insert admission window across concurrent provisions.
-- Transaction-scoped: auto-released on commit OR rollback (no leak on error).
PERFORM pg_advisory_xact_lock(8675309001);  -- arbitrary stable key, demo-admission only
```

Because the reservation `INSERT INTO demo_sessions` commits before the lock is released, each
serialized provision sees the prior reservation in its count. Invariant held: **no two
provisions ever both observe `count < 30` for the same slot**, so live rows with
`expires_at > now()` never exceed 30. Expired-but-unreaped rows still don't count (the
`expires_at > now()` filter excludes them), so freed slots remain immediately reusable.

**Chosen over alternatives** (documented, not implemented): a counter table (state-sync
complexity), serializable isolation + client retry (more surface, retry storms), and a
session-level `pg_advisory_lock`/`unlock` bracketing only the reservation to let clones run
concurrently (needs an EXCEPTION handler to guarantee unlock; higher risk under pooling). The
transaction advisory lock is one line, cannot leak, and fully satisfies the correctness
requirement. Its only cost is serializing the (bounded, ≤30) clone bodies under a cold burst
— acceptable given real load is 1/30 and this is a preventive fix. If burst throughput ever
matters, the session-lock variant is the documented upgrade path.

### Defect 2 — best-effort release on close + faster reclaim backstop
Two layers, because the client signal is inherently best-effort and the reaper is the
guarantee:

1. **Best-effort teardown on `detached`** (client). In `didChangeAppLifecycleState`, when the
   state is `AppLifecycleState.detached` **and** the current session is anonymous, fire a
   ref-free, error-swallowing `DemoSessionService.releaseSlotOnDetach()` that invokes the
   existing `exit-demo-session` Edge Function without awaiting. Frees the slot immediately in
   graceful-close cases (notably macOS quit; often iOS/Android swipe-close when the OS grants
   a moment). Gated on `detached` only, so it never fires on backgrounding and cannot regress
   the "background briefly and return" flow.

2. **Faster reclaim backstop** (DB), for hard-kill / crash / OS-eviction cases where no
   lifecycle callback is delivered:
   - Reduce the cron sweep interval `*/5` → `*/2` (pure backstop; negligible cost).
   - Reduce the sliding TTL from 15 min → **8 min** (`expires_at` default + heartbeat
     renewal). With heartbeats every ~60s while alive, an active session keeps ~7 minutes of
     headroom (tolerant of many transient heartbeat failures), while an abandoned slot is
     reclaimable in ≤8 min + ≤2 min cron = **≤10 min** worst case (down from ~20).

   > **Product decision (Tony, decided):** the demo-session TTL is **8 minutes**, paired with
   > the **2-minute** cron interval. Rationale: the advisory lock independently enforces the
   > hard 30-session safety cap, so TTL is **not** the capacity guarantee — it only governs
   > abandoned-slot turnover. Because there is **no background heartbeat execution** (the
   > renewal timer is suspended while the app is backgrounded) and demo use is
   > interruption-prone, a longer TTL gives a backgrounded-but-alive demo materially more grace
   > before it must re-provision. At the current 1/30 load, faster turnover buys nothing
   > operationally, while 8 minutes still cuts worst-case abandoned-slot reclamation from ~20
   > min to ~10 min. Engineer implements **8 minutes** as a fixed constant in both the
   > `expires_at` default and the heartbeat renewal — no apply-time tuning.

## Database Impact
One new migration (all DB changes bundled; single clean point in migration order after
`20260912122827`):
- `CREATE OR REPLACE FUNCTION public.provision_demo_session()` — verbatim current body + the
  one advisory-lock line. Re-apply grants exactly: `REVOKE ALL ... FROM PUBLIC, anon;`
  `GRANT EXECUTE ... TO authenticated;`. Keeps `SECURITY DEFINER` + `SET search_path = public`.
- `ALTER TABLE public.demo_sessions ALTER COLUMN expires_at SET DEFAULT now() + interval '8 minutes';`
- `CREATE OR REPLACE FUNCTION public.heartbeat_demo_session()` — renewal `interval '8 minutes'`;
  re-apply the same REVOKE/GRANT.
- Cron reschedule to `*/2` (unschedule-then-schedule with the existing loud post-assertion).

- **RLS:** unchanged. No policy touched; no recursion introduced (no new policy queries its
  own table).
- **RPC/grants:** re-declaring the two functions requires re-issuing REVOKE/GRANT in the same
  migration so `anon` never gains EXECUTE. No new SECURITY DEFINER function is introduced.
- **Migration order:** new file strictly after `20260912122827_...`; no reordering of
  existing files.
- **Idempotency:** provision's returning-visitor early-return and `unique_violation` catch are
  unchanged; the lock sits after them. Identical input → identical `clone_band_ids` output; no
  second clone. The `detached` teardown is idempotent (deleting an absent session is a no-op).

## Flutter Architecture Changes
None structural. No new provider/controller/repository. Additions:
- A `detached`-gated branch in the existing `WidgetsBindingObserver` in
  [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart#L118-L146).
- A static, ref-free `DemoSessionService.releaseSlotOnDetach()` and a pure predicate
  `shouldReleaseDemoOnLifecycle(state, {required bool isAnonymous})` (testable seam) in
  [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart).

## Files to Create
- `supabase/migrations/<new-timestamp>_demo_session_capacity_hardening.sql` — the layered
  migration described above. (Engineer assigns a timestamp strictly greater than
  `20260912122827`.)
- `test/features/auth/demo_lifecycle_predicate_test.dart` — unit tests for
  `shouldReleaseDemoOnLifecycle` (justified: no existing demo-service test group to extend; the
  existing [test/features/auth/login_screen_demo_button_test.dart](test/features/auth/login_screen_demo_button_test.dart)
  is a login-screen widget test with a different concern).

## Files to Modify
- [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart) — add the
  `detached`-gated best-effort teardown call in `didChangeAppLifecycleState`. No change to
  init order, splash, or the resumed-refresh path.
- [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) —
  add `releaseSlotOnDetach()` and `shouldReleaseDemoOnLifecycle(...)`. Do not alter the
  existing `provisionAndEnter` / `exit` / `heartbeat` behavior.
- [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) — append one
  DECISION entry (see task 6). Documentation only.

## Files Off-Limits
- [supabase/migrations/20260912122827_demo_relative_date_offsets.sql](supabase/migrations/20260912122827_demo_relative_date_offsets.sql)
  — merged (PR #288) and applied to prod; editing diverges repo from prod. Layer a new
  migration instead.
- [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql)
  and [supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql](supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql)
  and [supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql)
  — historical/superseded; edits change nothing live. Layer forward.
- [supabase/functions/exit-demo-session/index.ts](supabase/functions/exit-demo-session/index.ts)
  — teardown Edge Function is correct and is reused as-is.
- [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart) — explicit Exit Demo
  path is correct; do not touch.
- [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) — demo-visibility
  gating is unrelated.
- The client-side `demo_capacity_exceeded` rejection path
  ([demo_session_service.dart L37-L39](lib/features/auth/demo_session_service.dart#L37-L39)) —
  correct as-is.

## Change Budget
- `supabase/migrations/<new>_demo_session_capacity_hardening.sql`: **new file, ~360 lines**,
  but the *meaningful* change is ~6 lines (advisory-lock line + comment, expires-default
  ALTER, heartbeat interval, cron reschedule). The remaining ~350 lines are a mandatory
  verbatim re-declaration of the current function body (plpgsql has no in-place line insert).
- `lib/features/auth/auth_gate.dart`: **net +8 to +14 lines**.
- `lib/features/auth/demo_session_service.dart`: **net +12 to +18 lines**.
- `test/features/auth/demo_lifecycle_predicate_test.dart`: **new file, ~30-50 lines**.
- `docs/reference/general/AI_DECISIONS.md`: **net +~25 lines** (one DECISION entry).
- Expected new files: **2** (1 migration, 1 test).
- Expected new public methods: **2** (`releaseSlotOnDetach`, `shouldReleaseDemoOnLifecycle`).
- Expected new dependencies: **0**.

## System Impact Map
- **Auth:** affected (anonymous demo sessions only; real-user auth/session/routing unchanged —
  the teardown is gated on `isAnonymous`).
- **Platforms:** iOS / Android / macOS affected (demo is native-only). **Web unaffected** — no
  anonymous demo session exists there, so the `detached` teardown is inert; PKCE and all other
  web behavior unchanged.
- **Setlists / Gigs / Rehearsals / Members / Financials:** unaffected in the app; they exist
  only as cloned demo-band child data, whose provisioning path is unchanged except for the
  admission lock.
- **Routing / Notifications / Init order:** unaffected. No change to the fixed init sequence,
  so no RUNTIME_CONFIG update is required.

## Regression Risk
**MEDIUM** (leaning LOW). It touches an auth-adjacent file
([auth_gate.dart](lib/features/auth/auth_gate.dart)) and re-declares a demo RPC, which is why
this is not LOW. But blast radius is confined to the native-only demo path: the advisory lock
affects only new demo provisions; the lifecycle teardown is doubly gated (`detached` +
`isAnonymous`) so it cannot fire for real users or on backgrounding; no change to real
auth/session/routing/init/RLS. The DB change is a reversible function re-declaration plus a
column default and cron interval.

## Engineer Task Breakdown (ordered, atomic)
1. Create `supabase/migrations/<ts>_demo_session_capacity_hardening.sql` (timestamp strictly >
   `20260912122827`). Copy the current `provision_demo_session()` body **verbatim** from
   `20260912122827_demo_relative_date_offsets.sql`, adding only
   `PERFORM pg_advisory_xact_lock(8675309001);` (with the explanatory comment) immediately
   before the `SELECT count(*) INTO v_live_count` line and after the idempotency early-return.
   Re-issue `REVOKE ALL ON FUNCTION public.provision_demo_session() FROM PUBLIC, anon;` and
   `GRANT EXECUTE ON FUNCTION public.provision_demo_session() TO authenticated;`.
2. In the same migration: `ALTER TABLE public.demo_sessions ALTER COLUMN expires_at SET
   DEFAULT now() + interval '8 minutes';` and `CREATE OR REPLACE FUNCTION
   public.heartbeat_demo_session()` with `interval '8 minutes'` renewal, re-issuing its
   REVOKE/GRANT. Add a one-line comment on both `8 minutes` values recording the decided
   8-minute demo TTL (see the Product decision above) — a fixed constant, not apply-time
   tunable.
3. In the same migration: reschedule cron — `cron.unschedule('cleanup_demo_sessions')` (guarded
   as in the existing file), `cron.schedule('cleanup_demo_sessions', '*/2 * * * *', $$SELECT
   public.cleanup_expired_demo_sessions()$$)`, then the existing loud post-assertion that the
   job registered.
4. Add `DemoSessionService.releaseSlotOnDetach()` (static, ref-free): fire-and-forget invoke
   `exit-demo-session`, swallow all errors. Add pure predicate
   `bool shouldReleaseDemoOnLifecycle(AppLifecycleState state, {required bool isAnonymous})`
   returning `true` only for `state == AppLifecycleState.detached && isAnonymous`.
5. In `auth_gate.dart` `didChangeAppLifecycleState`, before updating
   `_previousLifecycleState`, call `shouldReleaseDemoOnLifecycle(state, isAnonymous:
   supabase.auth.currentSession?.user.isAnonymous == true)` and, if true, invoke
   `DemoSessionService.releaseSlotOnDetach()` (unawaited). Leave the existing `resumed` branch
   untouched.
6. Append DECISION-XXX to `docs/reference/general/AI_DECISIONS.md`: "Atomic demo admission via
   transaction advisory lock + faster abandoned-slot reclaim" — record the advisory-lock
   choice, the alternatives rejected, and the decided **8-minute** TTL paired with the
   **2-minute** cron interval, with Tony's rationale (the advisory lock is the hard 30-cap
   guarantee, so TTL only governs abandoned-slot turnover; no background heartbeat execution;
   interruption-prone demo use; 1/30 load; 8 min preserves background grace while cutting
   worst-case reclaim from ~20 min to ~10 min).
7. Add `test/features/auth/demo_lifecycle_predicate_test.dart` per the Verification Plan.

## Verification Plan

> **Cycle 2 amendment (2026-09-12) — verification contract only; implementation scope is
> UNCHANGED.** QA Cycle 1 returned REQUIRES CHANGES on a single Critical `[database-safety]`
> item with **no implementation defect** (Dart analyzer clean, predicate test 3/3, SQL
> byte-diff-confirmed correct). The blocker was purely that the original Tier 1 #4 (clean
> migration apply) and #5 (runtime grant assertions), plus the DB-side Tier 2 checks, are not
> executable by any agent in this pipeline. Independently re-confirmed this cycle:
> `docker` / `colima` / `podman` are **all absent**, so `supabase db reset` / `supabase start`
> cannot bring up a local Supabase stack; the only Supabase CLI link
> (`supabase/.temp/linked-project.json`) is to a **remote** project, which agents are
> forbidden to touch. There is therefore **no agent-runnable isolated Supabase environment.**
> This section is restructured to cleanly separate the **QA gate** (static + headless,
> mechanically executable now) from the **owner-run pre-apply DB + live-app checks** (Tony, on
> an environment he controls). **No agent may run any check against production or the remotely
> linked Supabase project — ever, including rolled-back, branch, or throwaway attempts.**

### Environment finding — why the DB checks are owner-run, not agent-runnable
- Confirmed this cycle: `docker`/`colima`/`podman` = **NOT FOUND**; `supabase`, `psql`, and
  native Postgres server binaries (`initdb`/`pg_ctl`/`postgres`; Homebrew `postgresql@17`/`@18`)
  **are** present; the Supabase CLI is linked to a **remote** project.
- A bare local Postgres cluster (via `initdb`/`pg_ctl`) is technically isolatable but is **not
  a valid substitute** for the Supabase apply-check. The migration depends on Supabase-managed
  objects a vanilla cluster lacks: the `anon`/`authenticated`/`service_role` roles (used by the
  `REVOKE`/`GRANT`), the `auth` schema and `auth.users` (referenced in the function body), and
  `pg_cron` (`cron.schedule`/`cron.unschedule`/`cron.job`). Applying the real migration there
  would either error on missing objects (a **false** negative) or require hand-built stub
  roles/schema/extension — at which point the apply and the `has_function_privilege` assertions
  test the **stubs**, not the real Supabase catalog, so a PASS would be a fiction ("clean apply
  on stubs" ≠ "clean apply on Supabase"). Manufacturing that and reporting it as a passed gate
  is exactly the "do not pretend they ran" failure mode. **This route is rejected;** the DB
  checks move to the owner, who applies against a real Supabase environment.
- **Why owner-run is sound here (not a lowered bar):** QA independently **byte-diffed the
  entire migration** against SQL **already applied to production**. Every statement is
  byte-identical to applied prod SQL (`20260912122827`, `20260908194500`, `20260904120005`) or
  a literal-constant change on top of it; the whole novel surface is ~6 lines (`15`→`8 minutes`
  ×2, `*/5`→`*/2`, and one well-formed `PERFORM pg_advisory_xact_lock(8675309001);`), and the
  grants are re-issued verbatim — essentially no room for a novel apply-time syntax/ordering
  error. Tony already applies every migration to prod **manually**; running the clean-apply,
  grant, concurrency, reclaim, and idempotency checks as his own pre-apply step (his local
  Docker Supabase stack, or a staging/branch project he owns) is the identical owner-run
  pattern the plan already used for the concurrency check and the live-app A/B/C checks. Safety
  is unchanged — every DB check still runs before the migration reaches prod, just by the party
  who can structurally run it.

### QA gate — the pass/fail scope for this cycle (static + headless; executable now)
QA issues its verdict on **exactly** these. All run with no container runtime, no running app,
and no Supabase environment. If all pass **and** the Manual Verification Punch List below is
attached verbatim for Tony, QA may **APPROVE** on this scope. QA must **not** treat the
owner-run DB items as a blocking gate — they are structurally outside QA's executable surface,
not an unmet QA obligation.
1. `flutter analyze` on the diff files — clean (no new warnings).
2. `flutter test test/features/auth/demo_lifecycle_predicate_test.dart` — asserts
   `shouldReleaseDemoOnLifecycle` returns `true` only for `(detached, isAnonymous: true)` and
   `false` for every other state (`resumed`, `inactive`, `hidden`, `paused`) and for
   `(detached, isAnonymous: false)`.
3. **Static SQL review + byte-diff against already-applied authoritative SQL** — the formal
   static-acceptance basis that stands in for an agent apply-check: (a) advisory-lock line
   present, **after** the idempotency early-return and **before** `SELECT count(*) INTO
   v_live_count`; (b) the **only** diffs vs the authoritative bodies are the ~6 enumerated lines
   — provision body byte-identical to `20260912122827` except the lock insertion, heartbeat
   byte-identical to `20260908194500` except `15`→`8 minutes`, cron block byte-identical to
   `20260904120005` except `*/5`→`*/2`, and the `expires_at` default `15`→`8 minutes`;
   (c) `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated` re-issued for
   **both** re-declared functions; (d) both retain `SECURITY DEFINER` + `SET search_path =
   public`; (e) cron reschedule present with its loud post-assertion.
4. Scope / off-limits / diff-safety / change-budget review (as QA Cycle 1 performed).

### Manual Verification Punch List — owner-run (Tony); NOT a QA gate; required BEFORE the migration is applied to prod
Run on an environment **Tony controls** — his local Docker Supabase stack (`supabase db reset` /
`supabase start`, local Postgres :54322) or a staging/branch project he owns. **Never
production; never the remotely linked project — not even a rolled-back or throwaway attempt.**
Items 1–5 are DB checks (previously Tier 1 #4–5 and Tier 2 #6–8, reclassified here as owner-run
because no agent-runnable isolated Supabase environment exists); items A–C are live-app checks.
All demo rows are harness-created and cleaned up; no production UUIDs.

1. **Clean migration apply (was Tier 1 #4).** `supabase db reset` on a fresh local stack.
   *Expected:* completes with **no error**; `SELECT 1 FROM cron.job WHERE jobname =
   'cleanup_demo_sessions';` returns exactly one row.
2. **Grant assertions (was Tier 1 #5).** After apply, run (privilege-correct, never an ACL
   string-match — a `PUBLIC` grant satisfies a string-match for every role):
   `SELECT has_function_privilege('anon', 'public.provision_demo_session()'::regprocedure,
   'EXECUTE');` → **false**;
   `SELECT has_function_privilege('authenticated', 'public.provision_demo_session()'::regprocedure,
   'EXECUTE');` → **true**. Repeat both for `public.heartbeat_demo_session()`.
   *Expected:* `anon` = false, `authenticated` = true for **both** functions.
3. **Concurrency admission — core defect-1 proof (was Tier 2 #6).** Seed 29 live
   `demo_sessions`; create 10 anon `auth.users` with fresh UUIDs; open 10 parallel `psql`
   connections, each `SELECT set_config('request.jwt.claims', json_build_object('is_anonymous',
   true, 'sub', '<that-uuid>', 'role', 'authenticated')::text, true);` then
   `provision_demo_session()`. *Expected:* exactly **1** succeeds, **9** raise
   `demo_capacity_exceeded`, and `SELECT count(*) FROM demo_sessions WHERE expires_at > now();`
   = **30 (never 31+)**. Repeat from an empty table with 40 parallel callers → final live count
   exactly **30**. Truncate seeded demo rows and delete seeded `auth.users` at the end.
4. **Reclaim (was Tier 2 #7).** *Expected:* a fresh provision's `expires_at ≈ now() + 8 min`;
   `heartbeat_demo_session()` renews to `now() + 8 min`; a row inserted with `expires_at =
   now() - interval '1 minute'` is deleted by `cleanup_expired_demo_sessions()`.
5. **Idempotency (was Tier 2 #8).** Call `provision_demo_session()` twice under the same spoofed
   anon uid. *Expected:* identical `clone_band_ids` both times; `SELECT count(*) FROM bands
   WHERE demo_session_id = <that session>;` stays at **2** (no second clone pair).
6. **A — Graceful-close release (macOS, live app).** Enter the demo; `Cmd-Q` without tapping
   Exit Demo; query `demo_sessions` for that `auth_user_id` within ~10s. *Expected:* row gone
   (best-effort `detached` hook fired).
7. **B — Hard-kill reclaim (iOS or Android, live app).** Enter the demo; force-swipe-kill; query
   the row immediately (may still be present), then again after ~10 min. *Expected:* gone by
   then (TTL 8 min + cron ≤2 min).
8. **C — Background survival, no false teardown (live app).** Enter the demo; background the app
   <8 min; return. *Expected:* demo still alive (heartbeat), confirming TTL is not too aggressive
   and `detached` did not fire on mere backgrounding.

## QA Regression Areas
- Demo entry still returns both clone band IDs and lands on Banana Stand.
- Explicit "Exit Demo" tap still tears down fully (Edge Function + `auth.admin.deleteUser`).
- Real-user (non-anonymous) auth: lifecycle transitions (background/resume) do **not** trigger
  any demo teardown; login/session/routing unchanged.
- Heartbeat keeps an active demo session alive across the reduced TTL window.
- Web build: demo entry still hidden; no lifecycle teardown path exercised.

## Rollout Strategy
Single PR (Dart + one migration + one DECISION entry). **Before applying to production**, Tony
runs Manual Verification Punch List items 1–5 (clean apply, grant assertions, concurrency,
reclaim, idempotency) against an environment he controls — his local Docker Supabase stack or a
staging/branch project he owns, **never** production and **never** the remotely linked project;
these are the owner-run substitute for the agent-unrunnable DB gates and are the pre-apply
confirmation that the migration applies cleanly and grants are privilege-correct. He applies the
migration at release, then exercises live-app items A–C. The 8-minute TTL is a fixed decided
constant, so there is no apply-time tuning step. No feature flag needed (native-only,
demo-isolated). Rollback = revert the migration (a follow-up `CREATE OR REPLACE` restoring the
prior function bodies, prior `expires_at` default, and `*/5` cron) plus revert the two Dart
files.

## Out of Scope
- Whether **30** is the right cap (product capacity call; unchanged here).
- A reaper for **orphaned anonymous `auth.users`** rows left when the best-effort `detached`
  teardown or a hard-kill does not reach `auth.admin.deleteUser()` (flag as a follow-up; the
  slot itself is still freed by cron via `demo_sessions` expiry).
- The **session-level advisory-lock** throughput optimization (documented alternative; not
  implemented at current load).
- Investigating **why migrations landed in prod without matching `main`/ledger entries**
  (Feature Input meta-concern; separate work).
- Evaluating Supabase Auth **anonymous sign-in rate limiting** as a mitigating factor.
