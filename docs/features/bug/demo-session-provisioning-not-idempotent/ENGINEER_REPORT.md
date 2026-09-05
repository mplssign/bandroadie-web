# ENGINEER_REPORT — Demo Session Provisioning Not Idempotent

## Feature Slug

`bug/demo-session-provisioning-not-idempotent`

## Feature Title

Demo session provisioning is not idempotent — fix idempotency read type mismatch, add concurrency ceiling, harden pg_cron registration, and reuse anonymous sessions on re-entry.

## Cycle Number

2

## Cycle 2 Change (this cycle — single bounded QA-requested fix)

QA Cycle 1 returned **REQUIRES CHANGES** with exactly one Critical
`implementation-gap`: the `INSERT INTO users` (section 3 of
`20260904120003_provision_demo_session_rpc.sql`) had no `ON CONFLICT` clause and
runs **before** the `unique_violation`-guarded `demo_sessions` insert (section 4).
So the same-identity double-tap/two-tab race collided on `users_pkey` first
(defeating #4's graceful handling), and a returning-visitor-after-sweep collided on
the leftover `public.users` PK (cleanup deletes `demo_sessions` + cascades bands,
but the `users` row persists) — a raw error violating the RPC's idempotency contract.

**The only change this cycle** — added `ON CONFLICT (id) DO NOTHING` to that one
`INSERT INTO users` statement:

Before:

```sql
    '1990-11-09',
    ARRAY['Drums'],
    true
  );
```

After:

```sql
    '1990-11-09',
    ARRAY['Drums'],
    true
  )
  ON CONFLICT (id) DO NOTHING;
```

- **Conflict target confirmed:** the `users` row is inserted with `id = v_user_id`
  (`auth.uid()` of the anonymous caller), and QA Cycle 1 identified the collision
  constraint by name as `users_pkey` — a single-column primary key on `id` — so
  `ON CONFLICT (id)` is the correct, valid target. No alternate/composite target
  applies.
- **Effect:** the loser of a same-`auth.uid()` double-tap now skips the `users`
  insert instead of raising, falls through to the `demo_sessions` insert, and hits
  the **existing** `unique_violation` handler (section 4), which re-reads and returns
  the winner's clone band IDs — so #4's graceful path is now **reachable**. A
  returning visitor after a cron sweep skips the leftover `users` row and
  re-provisions cleanly (fresh `demo_sessions` + clones).
- **Re-run safe against live prod state:** `ON CONFLICT (id) DO NOTHING` is
  idempotent — re-applying `CREATE OR REPLACE FUNCTION` with this body is harmless
  whether or not the visitor's `users` row already exists. No DB was touched by
  Engineer; nothing was applied.
- **Scope:** SQL-only. **No Dart change**, so there is **no analyzer delta** this
  cycle. Nothing else was modified — every other QA-approved item (#1 read fix, #3
  ceiling, #4 handler, #6 cron, `20260904120000` guards/`bands_real` view,
  `demo_session_service.dart`) is unchanged, and `auth_gate.dart` was not touched.
- **Client contract preserved:** the `{banana_stand_band_id, modal_nodes_band_id}`
  JSONB shape is unchanged (this edit touches only the `users` insert, not any
  `RETURN`).

## Goal

Repair the four defects + one operational gap that make demo-session provisioning
non-idempotent in production, while preserving the settled clone-per-visitor
architecture and the `provision_demo_session` client contract
(`{banana_stand_band_id, modal_nodes_band_id}`). All migration fixes are IN-PLACE
edits to the already-applied (but untracked-in-`schema_migrations`) files and are
re-run-safe against the live prod state. No DB was touched by Engineer.

## Numbering note (for QA)

This report uses the **owner's canonical item numbers**. The `ARCHITECT_PLAN.md`
labels the pg_cron hardening item **"#5"**; that is the owner's **#6**. The owner's
**#5 (cursor → set-based inserts) is OUT OF SCOPE and was NOT implemented** (see
Deviations). Mapping:

| Owner # | Plan doc label | Item                                                     |
| ------- | -------------- | -------------------------------------------------------- |
| #1      | #1             | RPC idempotency read `UUID[]`→scalar type fix (BLOCKING) |
| #2      | #2             | Client reuse of live anon session                        |
| #3      | #3             | Concurrency ceiling of 30                                |
| #4      | #4             | `unique_violation` guard on `demo_sessions` insert       |
| #5      | —              | Cursor → set-based inserts — **OUT OF SCOPE, not done**  |
| #6      | #5             | pg_cron registration hardening (BLOCKING)                |
| —       | #0             | `DROP POLICY IF EXISTS` guards                           |
| —       | added scope    | `bands_real` view                                        |

## Architect Tasks Completed

### #1 (BLOCKING) — RPC idempotency read type mismatch — `20260904120003`

- Added declaration `v_existing_clone_ids UUID[]` to the `DECLARE` block.
- Changed the idempotency read from
  `SELECT id, clone_band_ids INTO v_session_id, v_bs_band_id` (which assigned a
  `UUID[]` column into scalar `UUID` and raised at runtime) to
  `SELECT id, clone_band_ids INTO v_session_id, v_existing_clone_ids`.
- Replaced the two redundant re-query subselects in the early-return
  `jsonb_build_object` with direct reads `v_existing_clone_ids[1]::text` /
  `v_existing_clone_ids[2]::text`.
- `v_bs_band_id` / `v_mn_band_id` declarations retained — they are still used by
  the clone-build path (`§5` loop and final `UPDATE ... SET clone_band_ids` /
  `RETURN`); only their use in the idempotency read was removed.

### #2 — Client reuse of live anon session — `demo_session_service.dart`

- Before `signInAnonymously()`, added a guard: skip the mint when
  `client.auth.currentSession != null && currentUser != null &&
currentUser.isAnonymous == true`. A fresh mint still happens when there is no
  live anon session (post-signOut) or the current user is a real
  (non-anonymous) user (defensive).
- Per the plan, **`auth_gate.dart` was NOT modified** — its reconciler already
  gates the global sign-out on the correct condition.

### #3 — Concurrency ceiling of 30 — `20260904120003`

- Added `v_max_concurrent CONSTANT INTEGER := 30;` (named PL/pgSQL constant; no
  `app_config` table) and `v_live_count INTEGER;` to the `DECLARE` block.
- Inserted a live-session count check (`count(*) ... WHERE expires_at > now()`)
  that `RAISE EXCEPTION 'demo_capacity_exceeded' USING ERRCODE='P0001', HINT=...`
  at/over the ceiling.
- Placed the check **AFTER the fixed-#1 idempotency early-return** so returning
  visitors (who are themselves part of the live count) are never blocked by the
  ceiling on their own existing clone.
- Client mapping: added an `on PostgrestException catch (e)` branch in
  `provisionAndEnter` that maps `demo_capacity_exceeded` to the roadie-voice
  message `"Demo's booked solid — try again in a few minutes."`. `login_screen.dart`
  renders `DemoSessionException.message` verbatim, so no change there.

### #4 — `unique_violation` guard on `demo_sessions` insert — `20260904120003`

- Wrapped the `INSERT INTO demo_sessions` in a nested
  `BEGIN ... EXCEPTION WHEN unique_violation THEN ... END;` block that re-reads the
  winner's row into `v_existing_clone_ids` and returns its JSON payload
  (`v_existing_clone_ids[1]::text` / `[2]::text`).

### #6 (BLOCKING) [plan calls this "#5"] — pg_cron hardening — `20260904120005`

- Removed the in-transaction `CREATE EXTENSION IF NOT EXISTS pg_cron;`.
- Prepended a `pg_extension` pre-check `DO` block that `RAISE EXCEPTION` with an
  actionable message if `pg_cron` is not installed.
- Kept `CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()` and its
  `REVOKE ALL ... FROM PUBLIC, anon; GRANT EXECUTE ... TO postgres;` unchanged.
- Added an idempotent `DO $$ BEGIN PERFORM cron.unschedule('cleanup_demo_sessions');
EXCEPTION WHEN undefined_object THEN NULL; WHEN OTHERS THEN NULL; END $$;` block
  before scheduling.
- Fully qualified the scheduled command as
  `$$SELECT public.cleanup_expired_demo_sessions()$$`.
- Appended a post-schedule assertion `DO` block that `RAISE EXCEPTION` if no
  `cron.job` row exists for `cleanup_demo_sessions` after `cron.schedule` runs.

### `DROP POLICY IF EXISTS` guards — `20260904120000`

- Added `DROP POLICY IF EXISTS demo_sessions_select_own ON public.demo_sessions;`
  and `DROP POLICY IF EXISTS demo_sessions_update_own ON public.demo_sessions;`
  before their respective `CREATE POLICY` statements, matching the file's existing
  `DROP TRIGGER IF EXISTS` re-run-safety pattern. Policy predicates are recreated
  byte-for-byte. The file audit in the plan confirmed only these two statements
  needed guards; no other statement was changed.

### `bands_real` view — `20260904120000`

- Appended `CREATE OR REPLACE VIEW public.bands_real AS SELECT * FROM public.bands
WHERE is_demo_template = false AND is_demo_clone = false;` as a new section 4 at
  the end of the file (idempotent; default `SECURITY INVOKER`, so underlying
  `bands` RLS still applies).

## Files Created

None.

## Files Modified

| File                                                                | Change                                                                                                                                |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`          | 2× `DROP POLICY IF EXISTS` guards; appended `bands_real` view (section 4).                                                            |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql` | 3 new declarations; fixed idempotency read + early-return; concurrency ceiling; `unique_violation`-guarded insert.                    |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql` | Removed in-txn `CREATE EXTENSION`; pg_cron pre-check; idempotent `cron.unschedule`; fully-qualified command; post-schedule assertion. |
| `lib/features/auth/demo_session_service.dart`                       | Live-anon-session reuse guard; `PostgrestException` branch mapping `demo_capacity_exceeded` to roadie-voice message.                  |

> Note: all four files are currently **untracked** on `feature/interactive-demo-band-experience`
> (they show as `??` in `git status`, i.e. this branch's new demo work not yet
> committed), so `git diff` shows no hunks for them. The edits are in the working
> tree and were verified by re-reading each file after editing. Full post-edit
> content of the changed regions is included in the Engineer's final message to
> the Manager.

## Analyzer Results

`flutter analyze lib/features/auth/demo_session_service.dart` → **No issues found!**
(clean at every severity). `get_errors` on the same file → No errors found.
`dart format` → 0 changes (already formatted). SQL files are not analyzed by
`flutter analyze`; verified by careful manual review against the plan.

## Test Results

No automated tests were run or added. Per Architect Task 5, a Dart test for the
live-anon reuse guard was **deferred**: there is no existing
`demo_session_service_test.dart`, and neither `login_screen_demo_button_test.dart`
(widget-visibility only) nor `auth_gate_anonymous_recovery_test.dart` (AuthGate
reconciler) is a natural home for a static-method service test. `provisionAndEnter`
takes a `WidgetRef`, reads `activeBandProvider.notifier`, and issues a live
`rpc('provision_demo_session')` round-trip — isolating just the guard would require
a full offline HTTP + notifier + primed-anon-session harness, i.e. effectively a new
test file, which the plan explicitly says NOT to create for one guard. Manual
verification steps are documented below instead. The concurrency-ceiling and RPC
behaviors are SQL-only and are covered by the owner-run Tier-2 steps (a Dart test
for a Postgres RPC would need a live DB harness this repo lacks).

## Code Efficiency / Bloat Check

- Searched `lib/` for an existing anon-session reuse / "is live anon" helper before
  adding the guard (`grep` for `isAnonymous`, `currentSession`, `signInAnonymously`):
  the only other `isAnonymous` reads are in `auth_gate.dart`'s reconciler (a
  different concern — orphan detection, not provisioning reuse). **No existing
  helper for "reuse live anon session before provisioning"** — the 5-line inline
  guard is the smallest correct change and is local to the single call site, so no
  new helper/extension was justified.
- No new provider/notifier/model/field introduced. No new Dart file. No new SQL
  function (the `bands_real` view is a VIEW; the two edited functions keep their
  signatures and grants).
- `v_bs_band_id` / `v_mn_band_id` retained (still used by the clone-build path) —
  not dead code.
- Bug-fix-with-zero-deleted-lines check: #1 and #6 both **delete** the defective
  code (the broken scalar `INTO v_bs_band_id` line and its two redundant subselects
  for #1; the in-txn `CREATE EXTENSION` and the unqualified command string for #6),
  so these are root-cause replacements, not additive layers. #3, #4, `#0`, and the
  view are genuinely net-new safety/quality additions (nothing defective to remove),
  and the client guard replaces the unconditional mint with a conditional one.
- `demo_session_service.dart` is 65 lines — well under the 500-line helper target.
  All three edited SQL files remain single-purpose migrations; no size target
  applies to SQL migrations and none grew disproportionately.
- No `TODO`/`FIXME` added. The two pre-existing `debugPrint('[DemoSession] ❌ ...')`
  lines in the generic `catch` were preserved byte-for-byte per the plan (they are
  debug logs, not user-facing strings, so the no-emoji brand rule does not require
  changing them, and the plan explicitly says preserve them).

## Verification (manual steps performed by Engineer)

- Re-read every edited region after applying the multi-file edit; confirmed each
  matches the plan's Proposed Solution and Task Breakdown.
- `flutter analyze` on the touched Dart file — clean.
- `dart format` on the touched Dart file — no changes needed.
- Confirmed `PostgrestException` is in scope via the existing
  `package:supabase_flutter/supabase_flutter.dart` import (no new import added).
- Confirmed `exit` and `heartbeat` in `demo_session_service.dart` are unchanged.
- Confirmed `auth_gate.dart`, `login_screen.dart`, and migrations `…001` / `…002` /
  `…004` were NOT touched.
- **Did NOT** run `supabase db push`, `execute_sql`, `supabase migration list`, or
  any command that connects to the linked Supabase project. **Did NOT** apply any
  migration. **Did NOT** run any git write command.

## Owner-run verification steps (Engineer cannot execute — no DB access)

Run against a scratch DB first (Tier 1), then prod (Tier 2), in timestamp order
`…000 → …003 → …005`:

1. **Re-run safety (`…000`)** — apply twice against already-live state; expect no
   `policy … already exists` error. Then:
   `SELECT policyname FROM pg_policies WHERE tablename = 'demo_sessions';` → both
   `demo_sessions_select_own` and `demo_sessions_update_own`.
   `SELECT COUNT(*) FROM pg_views WHERE viewname = 'bands_real';` → 1.
2. **#1 idempotency (`…003`)** — from an anonymous session, call
   `SELECT public.provision_demo_session();` **twice**. First returns freshly-cloned
   band IDs; **second returns the identical IDs with no error** (previously raised
   `cannot assign a value of type uuid[] to a variable of type uuid`).
3. **#4 unique_violation** — two concurrent sessions as the same anon `auth.uid()`
   call `provision_demo_session()` simultaneously; neither raises
   `duplicate key value violates unique constraint`; both return the same JSON.
   Cleanup: `DELETE FROM public.demo_sessions WHERE auth_user_id = '<uuid>';`.
4. **#3 ceiling** — temporarily set `v_max_concurrent := 1`, re-apply, attempt a
   fresh anon provision while a live session exists → expect `demo_capacity_exceeded`
   (client shows "Demo's booked solid…"). Restore to 30 and re-apply.
5. **#6 pg_cron (`…005`)** — apply against a DB WITHOUT pg_cron → expect the
   pre-check `RAISE EXCEPTION` (proves fail-loud). Enable pg_cron in its own txn,
   re-apply → success. Then:
   `SELECT jobname, schedule, command, active FROM cron.job WHERE jobname = 'cleanup_demo_sessions';`
   → exactly one row, `schedule = '*/5 * * * *'`,
   `command = 'SELECT public.cleanup_expired_demo_sessions()'`, `active = true`.
   (If the job failed to register, the file's post-assertion `DO` block already
   aborted the apply.)
6. **`bands_real`** — `SELECT COUNT(*) FROM public.bands` minus
   `SELECT COUNT(*) FROM public.bands_real` equals
   `SELECT COUNT(*) FROM public.bands WHERE is_demo_template = true OR is_demo_clone = true;`.
7. **Grants unchanged** —
   `has_function_privilege('authenticated','public.provision_demo_session()'::regprocedure,'EXECUTE')` → true;
   `has_function_privilege('anon', …)` → false.
   `has_function_privilege('postgres','public.cleanup_expired_demo_sessions()'::regprocedure,'EXECUTE')` → true;
   `authenticated`/`anon` → false.
8. **One-shot drain** — `SELECT public.cleanup_expired_demo_sessions();` once after
   apply to clear the 8 stale sessions; verify
   `SELECT COUNT(*) FROM public.demo_sessions WHERE expires_at < now();` → 0.

### Client manual verification

- On device/simulator: launch → tap Demo → exit → tap Demo again within the 30-min
  window. Expect no fresh clones in `public.bands` and re-entry into the same demo
  bands (with #1 + #2 applied). Owner checks
  `SELECT COUNT(*) FROM bands WHERE is_demo_clone = true AND created_by = '<anon uuid>';`.

## Deviations From Plan

- **Owner #5 (cursor → set-based inserts) intentionally NOT implemented** — out of
  scope per Manager instructions and the plan's Out-of-Scope section. The row-by-row
  clone loops in `20260904120003` were left untouched.
- **Non-blocking observation on #4 (RESOLVED in Cycle 2):** In Cycle 1 the
  `unique_violation` guard was placed around the `demo_sessions` insert exactly as the
  plan specified, and I flagged that a true same-`auth.uid()` double-tap inserts into
  `public.users` (section 3) **before** reaching the `demo_sessions` insert (section
  4), so the collision could surface on `users_pkey` outside the guarded block. QA
  Cycle 1 elevated this to a Critical `implementation-gap`. **Cycle 2 addresses it**
  by adding `ON CONFLICT (id) DO NOTHING` to the section-3 `users` insert (see
  "Cycle 2 Change" above), which makes the existing section-4 `unique_violation`
  handler reachable and lets the after-sweep visitor re-provision cleanly. No other
  behavior changed.

## Blockers Encountered

None.

## Ready For QA

**Yes (Cycle 2).** The single Critical `implementation-gap` from QA Cycle 1 is
fixed: `ON CONFLICT (id) DO NOTHING` was added to the section-3 `INSERT INTO users`
in `20260904120003_provision_demo_session_rpc.sql`, making the existing
`demo_sessions` `unique_violation` handler reachable for the double-tap race and
allowing the after-sweep visitor to re-provision cleanly. This is the **only** change
this cycle — SQL-only, no Dart change (no analyzer delta), no other QA-approved item
altered, `auth_gate.dart` untouched, the `{banana_stand_band_id, modal_nodes_band_id}`
client contract preserved, and the edit is re-run-safe against live prod state. No
prod DB was touched and nothing was applied. The out-of-scope owner-#5 cursor refactor
remains not done (correct).
