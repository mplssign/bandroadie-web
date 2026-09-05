# QA_REPORT — Demo Session Provisioning Not Idempotent

## Feature Slug

`bug/demo-session-provisioning-not-idempotent`

## Feature Title

Demo session provisioning is not idempotent — fix idempotency read type mismatch,
add concurrency ceiling, harden pg_cron registration, and reuse anonymous sessions
on re-entry.

## Cycle Number

2

## Final Verdict

**APPROVED**

The sole Cycle 1 Critical (`implementation-gap`) is fully resolved. Engineer added
`ON CONFLICT (id) DO NOTHING` to the section-3 `INSERT INTO users` in
`20260904120003_provision_demo_session_rpc.sql` (L102) — the one bounded change this
cycle. It targets the correct constraint (`users_pkey`, the single-column PK on `id`
= the anon `auth.uid()` held in `v_user_id`), is idempotent / re-run-safe, and closes
BOTH collision vectors from Cycle 1: the same-identity double-tap/two-tab race now
falls through to the existing `demo_sessions` `unique_violation` handler and returns
the winner's clone IDs, and the returning-visitor-after-sweep case re-provisions
cleanly instead of raising on the leftover `public.users` row. Everything else the
plan required — both BLOCKING items (#1, #6) and #2, #3, #4, #0, `bands_real`, re-run
safety, and the client service — is unchanged from Cycle 1 and remains
approval-quality. No new issues. The two pre-existing `debugPrint` lines (Warning
below) and the `auth_gate.dart` info-level lints are pre-existing, out-of-this-cycle
observations, not blockers.

## Numbering Note

This report uses the **owner's canonical numbering** (per Manager instruction). The
`ARCHITECT_PLAN.md` labels the pg_cron item **"#5"**; that is the owner's **#6**. The
owner's **#5 (cursor → set-based inserts) is OUT OF SCOPE and was correctly NOT
implemented** — its absence is not a defect and is not flagged.

| Owner # | Plan doc label | Item                                                | Result                               |
| ------- | -------------- | --------------------------------------------------- | ------------------------------------ |
| #1      | #1             | RPC idempotency read `UUID[]`→scalar fix (BLOCKING) | PASS                                 |
| #2      | #2             | Client reuse of live anon session                   | PASS                                 |
| #3      | #3             | Concurrency ceiling of 30                           | PASS                                 |
| #4      | #4             | `unique_violation` guard on insert                  | **PASS** (Cycle 1 gap fixed Cycle 2) |
| #5      | —              | Cursor → set-based inserts                          | Out of scope, correctly not done     |
| #6      | #5             | pg_cron registration hardening (BLOCKING)           | PASS                                 |
| —       | #0             | `DROP POLICY IF EXISTS` guards                      | PASS                                 |
| —       | added          | `bands_real` view                                   | PASS                                 |

## Validation Summary

- **Cycle 2 is a focused re-check** of the single bounded fix requested after the
  Cycle 1 REQUIRES CHANGES: `ON CONFLICT (id) DO NOTHING` on the section-3 `INSERT
INTO users`. Verified the fix is present and correct, both Cycle 1 collision vectors
  are closed, and nothing else in the Cycle-1-approved set changed or regressed.
- Branch `feature/interactive-demo-band-experience`, working tree contains the
  Engineer's uncommitted implementation (correct at this stage; nothing is committed
  — not flagged).
- The three edited migrations and `demo_session_service.dart` are **untracked new
  files** on this branch (part of the interactive-demo feature's uncommitted work),
  so `git diff HEAD` shows no hunks for them. Validated by reading the full file
  contents directly against the plan, as expected for untracked files.
- No DB access in this pipeline (per Manager). Migration correctness validated by
  **code review + reasoning only — NOT runtime-applied**. Runtime confirmations are
  expressed as owner-run steps below. This is explicit, not implied.
- Analyzer run on the edited Dart file: clean.

## Architect Scope Review

- **In-scope files edited (this cycle):** `20260904120000_demo_bands_schema.sql`,
  `20260904120003_provision_demo_session_rpc.sql`,
  `20260904120005_cleanup_demo_sessions_cron.sql`,
  `lib/features/auth/demo_session_service.dart`, plus `ENGINEER_REPORT.md`. All match
  the plan's Files-to-Modify list.
- **No new forward migration** — the demo migration set is exactly the original six
  (`…000`–`…005`); all fixes are in-place edits. Confirmed via directory listing.
- **Off-limits files untouched by this cycle:**
  - `lib/features/auth/auth_gate.dart` shows as modified in the working tree, but
    that is **pre-existing interactive-demo branch work, not this cycle's**. Its
    `_reconcileOrphanedAnonymousSession()` (auth_gate.dart L299-313) matches the
    plan's quoted "already-correct" reconciler byte-for-byte — global sign-out gated
    on `!hasBands && stillAnonymous`. Consistent with "unchanged this cycle."
  - `login_screen.dart`, `…001`, `…002`, `…004` not touched by any in-scope edit.
- **No unapproved architectural change**, no unrelated formatting churn in the
  in-scope files. The broader modified/untracked files in `git status` are prior
  branch work outside this cycle and are not this cycle's defects.

## Completeness Check

| Item                         | Complete? | Evidence                                                                                                                                                                                      |
| ---------------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| #1 idempotency read          | Yes       | `v_existing_clone_ids UUID[]` declared; read populates it; early-return reads `[1]`/`[2]`; path `RETURN`s.                                                                                    |
| #2 client anon reuse         | Yes       | `hasLiveAnon` guard skips mint when a live anon session exists.                                                                                                                               |
| #3 concurrency ceiling       | Yes       | Named `CONSTANT 30`; live-session count; placed after #1 early-return; RAISE + client mapping.                                                                                                |
| #4 unique_violation graceful | Yes       | `users` insert now `ON CONFLICT (id) DO NOTHING` (L102), so the loser falls through to the `demo_sessions` insert and its existing `unique_violation` handler returns the winner's clone IDs. |
| #6 pg_cron hardening         | Yes       | Extension removed from txn; pre-check; idempotent unschedule; qualified command; post-assertion.                                                                                              |
| #0 policy guards             | Yes       | `DROP POLICY IF EXISTS` before both `CREATE POLICY`.                                                                                                                                          |
| `bands_real` view            | Yes       | `CREATE OR REPLACE VIEW` filtering `is_demo_template = false AND is_demo_clone = false`.                                                                                                      |

## Behavior Verification

Method: **code-path analysis / static code review only** (no runtime execution, no
device testing, no SQL applied). Stated explicitly per QA precision rules.

### #1 — idempotency read (BLOCKING) — PASS

- `v_existing_clone_ids UUID[]` declared alongside the existing locals (DECLARE
  block). No `UUID[]`→scalar assignment remains.
- Idempotency read now `SELECT id, clone_band_ids INTO v_session_id,
v_existing_clone_ids` — array-to-array, type-correct.
- Early return under `IF FOUND THEN` returns
  `jsonb_build_object('banana_stand_band_id', v_existing_clone_ids[1]::text,
'modal_nodes_band_id', v_existing_clone_ids[2]::text)` — the returning-visitor path
  now **returns instead of raising**. The two redundant re-query subselects are gone.
- `v_bs_band_id` / `v_mn_band_id` scalars retained and still correctly drive the
  clone-build path: set per `v_band_idx` in the clone loop (`1 → bs`, else `mn`),
  then the final `UPDATE demo_sessions SET clone_band_ids = ARRAY[v_bs_band_id,
v_mn_band_id]` and the terminal `RETURN`. The #1 fix did **not** break clone
  creation. Confirmed in code.

### #3 — concurrency ceiling — PASS

- `v_max_concurrent CONSTANT INTEGER := 30;` — named constant, as specified.
- `SELECT count(*) ... WHERE expires_at > now()` — counts genuinely-live sessions.
- Placed in section 2b, **after** the #1 `IF FOUND ... RETURN` — returning visitors
  (who are part of the live count) are not blocked by the ceiling. Ordering correct.
- `RAISE EXCEPTION 'demo_capacity_exceeded' USING ERRCODE = 'P0001'`.
- Client mapping: `on PostgrestException catch (e)` → `if
(e.message.contains('demo_capacity_exceeded'))`. PostgREST surfaces a `RAISE
EXCEPTION '<msg>'` as the `message` field, which `PostgrestException.message`
  carries verbatim, so `.contains('demo_capacity_exceeded')` matches the raised
  signal. Error-signal ↔ client-check confirmed to line up.

### #6 — pg_cron hardening (BLOCKING) — PASS

- In-transaction `CREATE EXTENSION IF NOT EXISTS pg_cron` **removed**.
- `pg_extension` pre-check `DO` block raises with an actionable message if pg_cron is
  absent (fail-loud). pg_cron is already installed in prod, so this passes there.
- Idempotent `DO $$ ... PERFORM cron.unschedule('cleanup_demo_sessions');
EXCEPTION WHEN undefined_object THEN NULL; WHEN OTHERS THEN NULL; END $$;` — safe on
  first apply (no job) and on re-apply (clean slate).
- Scheduled command **fully qualified**: `$$SELECT
public.cleanup_expired_demo_sessions()$$`.
- Post-schedule assertion `DO` block **RAISES** if `cron.job` has no
  `cleanup_demo_sessions` row — registration is now self-verifying.
- Owner-run verification step present in report §5 and reproduced below.

### #2 — client anon reuse — PASS

- Guard: `hasLiveAnon = client.auth.currentSession != null && currentUser != null &&
currentUser.isAnonymous == true`; `signInAnonymously()` only runs when
  `!hasLiveAnon`. Matches the plan verbatim.
- Client contract preserved: reads `['banana_stand_band_id']`; the RPC still returns
  both `banana_stand_band_id` and `modal_nodes_band_id`. `{banana_stand_band_id,
modal_nodes_band_id}` contract intact.
- `auth_gate.dart` correctly left unchanged (reconciler already gated on `!hasBands &&
stillAnonymous`). `exit` / `heartbeat` unchanged.

### #4 — `unique_violation` graceful path (Cycle 2 fix) — PASS

- Section-3 `INSERT INTO users (...) VALUES (v_user_id, ...)` now ends with
  `ON CONFLICT (id) DO NOTHING` (L102). `id = v_user_id = auth.uid()`; the conflict
  target infers `users_pkey` (single-column PK on `id`) — valid column-inference form.
- **Double-tap / two-tab race (the race #4 targets):** the loser's `users` insert
  blocks on the winner's uncommitted PK tuple, then becomes a no-op once the winner
  commits, and falls through to the section-4 `demo_sessions` insert. Since the loser
  was blocked until the winner **fully** committed — including the section-6
  `UPDATE demo_sessions SET clone_band_ids = ARRAY[...]` — the existing
  `unique_violation` handler re-reads a **populated** `clone_band_ids` and returns the
  winner's IDs. #4's graceful handler is now reachable. Confirmed in code.
- **Returning-visitor-after-sweep:** the `…005` sweep deletes `demo_sessions` and
  cascades clone `bands` (via `demo_session_id ... ON DELETE CASCADE`) but leaves the
  `public.users` row (no FK path deletes it). Re-provision now skips that leftover row
  (DO NOTHING, no raise), inserts a fresh `demo_sessions`, clones fresh bands, and
  returns the new IDs — no raw error; the RPC header's idempotency contract holds.
- No signature, grant, RLS, or client-contract change; the clause is idempotent.

## Regression Check

Overall regression risk: **LOW–MEDIUM** (control-flow changes are confined to the
demo RPC and the single demo client call site; a real, non-anonymous user never
enters any modified path).

| Affected system (plan impact map)                             | Risk     | Finding                                                                                                                                                               |
| ------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth / session                                                | LOW      | Client guard composes correctly with the unchanged `auth_gate` reconciler; PKCE/deep-link/session-storage paths untouched.                                            |
| Supabase RPC signatures                                       | LOW      | `provision_demo_session()` / `cleanup_expired_demo_sessions()` signatures and grants unchanged; `{banana_stand_band_id, modal_nodes_band_id}` return shape preserved. |
| Init order                                                    | NONE     | `main.dart` untouched.                                                                                                                                                |
| Platform parity                                               | NONE     | Client change is in shared `demo_session_service.dart`; no `Platform.isX` branch; migrations are DB-only.                                                             |
| Members / setlists / gigs / rehearsals                        | POSITIVE | #1/#2 stop the re-clone loop; #6 restores the sweep — fewer orphaned rows. No RLS/role change.                                                                        |
| Controller/FocusNode disposal, setState-after-async, rebuilds | N/A      | No widget/controller lifecycle changed in scope.                                                                                                                      |

## Database Safety

Validated by **SQL code review + reasoning only — NOT applied to any database**
(no DB access this pipeline, per Manager). The migration-apply-clean check is
deferred to the owner-run steps below; treat this section as code-level assurance,
not a runtime apply confirmation.

**Cycle 2 addition:** `ON CONFLICT (id) DO NOTHING` on the section-3 `INSERT INTO
users` (L102). No signature, grant, RLS policy, or client-contract change; the clause
is idempotent and re-run safe inside the `CREATE OR REPLACE FUNCTION`. Grepped the
three edited migrations for `TODO` / `FIXME` / `service_role` / `SUPABASE_` / secret /
api-key — none present.

- **SECURITY DEFINER grants (code-level):**
  - `public.provision_demo_session()` — `REVOKE ALL ... FROM PUBLIC, anon; GRANT
EXECUTE ... TO authenticated;` preserved verbatim at the file tail. Signature
    unchanged.
  - `public.cleanup_expired_demo_sessions()` — `REVOKE ALL ... FROM PUBLIC, anon;
GRANT EXECUTE ... TO postgres;` preserved. Signature unchanged.
  - `public.prevent_anonymous_template_write()` — unchanged (not in scope).
  - `has_function_privilege(...)` could not be executed (no DB) — owner-run step
    below; note the code contains no `PUBLIC` EXECUTE grant that would mask a
    per-role check.
- **No self-referencing RLS:** the two `demo_sessions` policies reference only
  `auth.uid()`, never `demo_sessions` — no `42P17` recursion risk. Re-created
  byte-for-byte behind `DROP POLICY IF EXISTS`.
- **No privilege escalation / destructive cascade introduced.** `bands_real` view is
  default `SECURITY INVOKER`; underlying `bands` RLS still applies to callers.
- **RPC ↔ client signature match:** client calls `rpc('provision_demo_session')` with
  no params; function takes none. Return keys match client reads.

### Re-run safety against the already-live prod state (hard requirement) — PASS (code-level)

Every statement in each edited file is re-run safe against the current live state:

| File   | Re-run-safety mechanisms                                                                                                                                                                                                                     | Verdict     |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `…000` | `CREATE TABLE/INDEX IF NOT EXISTS`, `ENABLE RLS` (idempotent), `DROP POLICY IF EXISTS` before each `CREATE POLICY`, `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP TRIGGER IF EXISTS`, `CREATE OR REPLACE VIEW bands_real`. | Re-run safe |
| `…003` | Single `CREATE OR REPLACE FUNCTION` + idempotent `REVOKE`/`GRANT`.                                                                                                                                                                           | Re-run safe |
| `…005` | Read-only `pg_extension` pre-check; `CREATE OR REPLACE FUNCTION`; idempotent `REVOKE`/`GRANT`; `cron.unschedule` (errors swallowed); `cron.schedule` (upsert by jobname); read-only post-assertion.                                          | Re-run safe |

Note on `bands_real`: `CREATE OR REPLACE VIEW ... SELECT *` is safe on re-apply
against identical `bands` columns (the `is_demo_*` columns are added earlier in the
same file, before the view). No blocking concern.

**Important:** reading the SQL as correct is **not** the same as it applying
cleanly. I could not apply it. The owner-run apply-clean check below is mandatory
before trusting these files against prod.

## Analyzer Results

`flutter analyze lib/features/auth/demo_session_service.dart` → **No issues found!**
(clean at every severity). The Cycle 2 diff is SQL-only, which `flutter analyze` does
not cover. Running the analyzer across `demo_session_service.dart` + `auth_gate.dart`
surfaces 13 info-level lints — **all in `auth_gate.dart`, zero in
`demo_session_service.dart`**. `auth_gate.dart` is not touched by this cycle (nor by
this bug's plan — it is pre-existing interactive-demo branch work), so those do not
block. `analysis_options.yaml` promotes AI-slop lints to error; none of the 13 are
error-level and none are in a file this cycle's diff touches.

## Test Results

No automated tests were required by the plan for the SQL items, and the single-guard
Dart change was deferred from a new test file per the plan (correctly — creating a
full offline HTTP + notifier + primed-anon harness for one guard is disproportionate).
No `flutter test` run required for this verdict. The SQL behaviors are covered by the
owner-run steps below.

## Diff Safety Review

- **No secrets / API keys / service-role usage** in any in-scope file. The demo
  visitor seed data in the `users` insert (`demo-…@bandroadie.com`, Wrigley Field
  address, etc.) is demo fixture data, not credentials.
- **No `TODO` / `FIXME`** in the in-scope files.
- **`debugPrint(` — two occurrences** at `demo_session_service.dart` L44-45
  (`'[DemoSession] ❌ …'`). These are **pre-existing** (added when the file was first
  created by prior demo-feature work) and were **preserved per the plan's explicit
  instruction**, not introduced by this cycle. Flagged as a minor Warning below
  (they execute in release builds), but not this cycle's artifact and not the
  verdict driver.
- No leftover test scaffolding, no accidental deletions, no unrelated churn in the
  in-scope files.

## Change Budget Review

Files are untracked, so `git diff --numstat` shows no hunks; assessed by direct
reading against the plan's Change Budget.

| File                                         | Budget (net delta)                           | Observed                                                                    | Within?   |
| -------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------- | --------- |
| `…000`                                       | +12 to +18                                   | 2 `DROP POLICY` lines + ~10-line view section                               | Yes       |
| `…003`                                       | +25 to +40                                   | 3 declarations + ceiling (~10) + nested guard (~12) − 2 subselects          | Yes       |
| `…005`                                       | +25 to +40 (net; file rewritten to 69 lines) | pre-check + unschedule + qualified command + assertion − `CREATE EXTENSION` | Yes       |
| `demo_session_service.dart`                  | +8 to +14                                    | ~7-line guard + ~7-line `PostgrestException` branch (68 lines total)        | At/within |
| New files                                    | 0                                            | 0                                                                           | Yes       |
| New public classes / methods / SQL functions | 0                                            | 0 (view is a VIEW; functions edited in place)                               | Yes       |
| New deps                                     | 0                                            | 0                                                                           | Yes       |

No bloat threshold exceeded. No new file, provider, notifier, model, helper, or
dependency. **Cycle 2 delta:** a single `ON CONFLICT (id) DO NOTHING` line (+1 line of
substance) on `…003` — trivially within budget; no other file changed this cycle.

## Code Efficiency Review

- No new helper/extension/util/provider introduced; the anon-reuse guard is a local
  inline check at its single call site — correct (a helper would be over-abstraction).
- `v_bs_band_id` / `v_mn_band_id` retained are **not** dead code — still used by the
  clone-build path and the final `UPDATE`/`RETURN`.
- No single-use `_buildX()`, no redundant `FutureBuilder`/`StreamBuilder`, no
  hand-rolled dedupe, no unread field/param, no barrel file, no speculative flags.
- Bug-fix-with-deletions check: #1 and #6 both **delete** the defective code (broken
  scalar `INTO`, redundant subselects, in-txn `CREATE EXTENSION`, unqualified
  command) — root-cause replacements, not additive layers.

## Issues Found

### Critical

None. The Cycle 1 Critical (`implementation-gap`) is **RESOLVED** — see
"Cycle 1 Critical — Resolution" below.

### Cycle 1 Critical — Resolution `[Issue Category: implementation-gap]`

Cycle 1 blocked on the section-3 `INSERT INTO users` having no `ON CONFLICT`, so it
collided on `users_pkey` **before** reaching the section-4 `demo_sessions`
`unique_violation` handler — defeating #4's graceful intent (double-tap/two-tab race)
and leaving a raw-error idempotency hole for the returning-visitor-after-sweep case.
Cycle 2 adds `ON CONFLICT (id) DO NOTHING` (L102). Verified by code review + reasoning
(no SQL executed):

- **Correct target:** `id = v_user_id = auth.uid()`; `users_pkey` is the single-column
  PK on `id`, which the `ON CONFLICT (id)` column-inference form resolves. Valid.
- **Double-tap / two-tab race — closed:** the loser's `users` insert blocks on the
  winner's uncommitted PK tuple, becomes a no-op once the winner commits, and falls
  through to the `demo_sessions` insert — where the existing `unique_violation` handler
  re-reads the winner's (now committed and section-6-populated) `clone_band_ids` and
  returns them. The graceful handler is reachable.
- **Returning-visitor-after-sweep — closed:** the leftover `public.users` row now
  yields DO NOTHING instead of raising; a fresh `demo_sessions` + clones are created
  and new IDs returned. No raw error; idempotency contract satisfied.
- **Re-run safe:** idempotent clause inside `CREATE OR REPLACE FUNCTION`.

### Warnings

1. **Pre-existing `debugPrint` in a release-executing code path.**
   `[Issue Category: code-quality]`
   `demo_session_service.dart` L44-45 call `debugPrint('[DemoSession] ❌ …')` in the
   generic `catch`. `debugPrint` is not stripped in release builds. These were
   preserved per the plan's explicit instruction and are **not** this cycle's
   addition, so this does not block — but the owner/Architect may want to gate them
   behind `kDebugMode` (and the `❌` glyph, while a dev log rather than a user-facing
   string, is inconsistent with the repo's no-emoji direction). Optional follow-up.

### Suggestions

- None beyond the Critical remedy.

## Owner-Run Verification Steps (post-apply, run by Tony via direct SQL)

Apply order: `…000 → …003 → …005`. Run against a scratch DB first, then prod.

1. **Re-apply-without-error (all three files).** Apply each edited file **twice**
   against the current live state; expect **no** `policy … already exists`, no
   `function … already exists`, no cron error on either pass. Then:

   ```sql
   SELECT policyname FROM pg_policies WHERE tablename = 'demo_sessions';
   -- expect demo_sessions_select_own AND demo_sessions_update_own
   SELECT count(*) FROM pg_views WHERE viewname = 'bands_real';   -- expect 1
   ```

2. **cron.job assertion (#6 — the file self-asserts, but confirm the row):**

   ```sql
   SELECT jobname, schedule, command, active
   FROM cron.job
   WHERE jobname = 'cleanup_demo_sessions';
   -- expect exactly 1 row:
   --   schedule = '*/5 * * * *'
   --   command  = 'SELECT public.cleanup_expired_demo_sessions()'
   --   active   = true
   ```

3. **Returning-visitor idempotency (#1 — stable IDs, no error):** from an anonymous
   session, call `SELECT public.provision_demo_session();` **twice**. The second call
   must return the **identical** `banana_stand_band_id` / `modal_nodes_band_id` with
   **no** `cannot assign a value of type uuid[] to a variable of type uuid` error.

4. **Grants (code-level claim — confirm at runtime):**

   ```sql
   SELECT has_function_privilege('authenticated',
     'public.provision_demo_session()'::regprocedure, 'EXECUTE');           -- true
   SELECT has_function_privilege('anon',
     'public.provision_demo_session()'::regprocedure, 'EXECUTE');           -- false
   SELECT has_function_privilege('postgres',
     'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');    -- true
   SELECT has_function_privilege('authenticated',
     'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');    -- false
   ```

5. **Double-tap idempotency (Critical remedy now applied):** issue two concurrent
   `provision_demo_session()` calls as the same anon `auth.uid()` (two tabs / rapid
   double-tap). Both must return the **same** `{banana_stand_band_id,
modal_nodes_band_id}` JSON with **no** `users_pkey` and **no**
   `demo_sessions_auth_user_id_key` raw error. Then confirm exactly one clone set
   exists (not a doubled clone):
   `SELECT count(*) FROM bands WHERE is_demo_clone = true AND created_by = '<uuid>';`
   → 2 (one Banana Stand + one Modal Nodes). Cleanup:
   `DELETE FROM public.demo_sessions WHERE auth_user_id = '<uuid>';`.

6. **Stale-session drain (#6 operational goal):**
   `SELECT public.cleanup_expired_demo_sessions();` then
   `SELECT count(*) FROM public.demo_sessions WHERE expires_at < now();` → 0.

---

**Verdict: APPROVED.** The single Cycle 1 Critical is resolved by `ON CONFLICT (id)
DO NOTHING` on the section-3 `INSERT INTO users` (L102), which makes the existing
`demo_sessions` `unique_violation` handler reachable for the double-tap race and lets
a returning-visitor-after-sweep re-provision cleanly. Nothing else changed or
regressed; both BLOCKING items (#1, #6) and every other in-scope item remain
approval-quality and re-run safe on code review. Migration apply-clean confirmation is
deferred to the owner-run steps above (no SQL executed this pipeline, per Manager —
this is code-path analysis, not a runtime apply). No secrets, no new forward
migration, no DB writes.
