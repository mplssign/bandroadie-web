# Architect Plan — Demo Session Cleanup Leaves Orphaned Anonymous Auth Users

## Feature Slug

`bug/demo-session-cleanup-orphaned-anonymous-users`

## Feature Title

Demo session cleanup (both the cron sweep and the "Exit Demo" button) deletes the session/bands but leaves the visitor's anonymous `auth.users` row behind permanently

## Problem Summary

Both demo teardown paths — the every-5-min pg_cron sweep `cleanup_expired_demo_sessions()` and the client-invoked `exit_demo_session()` RPC fired by the "Exit Demo" drawer button — delete the `demo_sessions` ledger row and cascade the visitor's cloned bands, but never touch the visitor's anonymous `auth.users` row. Every demo entry therefore leaves one permanent orphaned row in `auth.users` forever. Prod (`nekwjxvgbveheooyorjo`) currently holds 59 already-orphaned real-visit rows (36 of them still carrying a `public.users` row) accumulated in roughly two days of real traffic, and the rate scales with demo traffic.

## Root Cause — HIGH confidence (confirmed in code)

Two independent single-statement deletes, each ignorant of the `auth.users` residue:

1. **Cron sweep** — [supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql#L29-L37](supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql#L29-L37):

   ```sql
   CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()
   RETURNS void
   LANGUAGE sql
   SECURITY DEFINER
   SET search_path = public
   AS $$
     DELETE FROM public.demo_sessions
     WHERE expires_at < now();
   $$;
   ```

   `bands.demo_session_id ON DELETE CASCADE` correctly nukes the clone bands (and everything scoped under them via each band's own `band_id` cascade chain), but the row in `auth.users` is only referenced by `demo_sessions.auth_user_id ON DELETE CASCADE` in that direction — the reverse cascade the fix requires is not automatic.

2. **Exit Demo RPC** — [supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql#L11-L28](supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql#L11-L28):

   ```sql
   DELETE FROM demo_sessions WHERE auth_user_id = auth.uid();
   ```

   Identical shape, identical gap. Verified live from source; not just theorised from the cron path.

The demo entry side ([lib/features/auth/demo_session_service.dart#L18-L48](lib/features/auth/demo_session_service.dart#L18-L48)) does `client.auth.signInAnonymously()` and then `client.rpc('provision_demo_session')`, so a fresh `auth.users` row is created every time a returning visitor's persisted anon session is not found — that row is never cleaned up on the way back out.

## Existing System Analysis

- `demo_sessions.auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE` (verified at [supabase/migrations/20260904120000_demo_bands_schema.sql#L15-L22](supabase/migrations/20260904120000_demo_bands_schema.sql#L15-L22)). This is why `auth.users` accumulates: cascade points the wrong direction for the cleanup we need.
- `bands.demo_session_id UUID REFERENCES public.demo_sessions(id) ON DELETE CASCADE` (same file, L52). Deleting a `demo_sessions` row correctly cascades both clone bands, and their `band_id` cascades take out all band-scoped children (`songs`, `setlists`, `setlist_songs`, `gigs`, `rehearsals`, `contacts`, `venues`, `venue_contacts`, `financial_entries`, `band_members`). Confirmed by walking the migration.
- Feature Input confirmed via live `pg_constraint`: `public.users.id → auth.users.id ON DELETE CASCADE`. Deleting the `auth.users` row will automatically clean up the leftover `public.users` row — no separate `public.users` delete needed.
- Feature Input flagged the two `ON DELETE NO ACTION` back-references — `setlists.created_by` and `gigs.created_by`. If any row from these two tables still references the visitor's `auth.users.id` when the `auth.users` delete runs, that delete fails with a FK violation. In our teardown sequence they are gone by that point (deleted via each row's own `band_id → bands → demo_sessions` cascade path, one step earlier). This assumption is load-bearing and is called out in the verification plan.
- Template-fixture accounts (13 rows, ids `00000000-0000-4000-8000-…`/`8001-…`/`8002-…`) are the 12 dummy band members plus 1 "Demo System" band creator seeded by [supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql) — they carry `is_anonymous = true` and `raw_user_meta_data->>'demo_placeholder' = 'true'`. They must never be swept. Confirmed by reading the seed inserts (13 explicit rows, all with that marker).
- Existing "delete my account" precedent — [supabase/migrations/075_delete_user_account_rpc.sql](supabase/migrations/075_delete_user_account_rpc.sql) — deliberately does not `DELETE FROM auth.users` from a client-invoked SECURITY DEFINER function. Its own inline comment defers that step to `auth.admin.deleteUser()` from an Edge Function. Nothing in the codebase currently uses `auth.admin.deleteUser` (grep across `supabase/functions/**` returns zero hits) — this feature is the first to build what that comment envisioned.
- Anonymous JWT-guard helper `isAnonymousSession(req)` already exists in [supabase/functions/send-bug-report/index.ts#L37-L52](supabase/functions/send-bug-report/index.ts#L37-L52) and [supabase/functions/send-band-invite/index.ts#L22-L38](supabase/functions/send-band-invite/index.ts#L22-L38); both are the "reject anon" polarity. The new Edge Function inverts it (accept only anon).

## Proposed Solution

Two paths, each fixed in its own execution context per the Feature Input's explicit guidance ("don't copy one solution into both"):

### Path A — `cleanup_expired_demo_sessions()` (postgres via pg_cron)

Runs as the `postgres` superuser inside pg_cron's background worker. Superuser can touch `auth.users` directly; the direct-SQL delete is the correct primitive here.

Rewritten function (language changes from `sql` to `plpgsql` to allow a captured id list and one guarded delete):

1. `SELECT array_agg(auth_user_id) INTO v_expired_user_ids FROM public.demo_sessions WHERE expires_at < now();`
2. Early-return if the array is empty.
3. `DELETE FROM public.demo_sessions WHERE auth_user_id = ANY(v_expired_user_ids);` — cascades bands, cascades band-scoped children including any `setlists`/`gigs` row that references the visitor via `created_by`.
4. Wrapped in `BEGIN ... EXCEPTION WHEN foreign_key_violation THEN RAISE WARNING ...; END;`: `DELETE FROM auth.users WHERE id = ANY(v_expired_user_ids);` — cascades `public.users` and every other `ON DELETE CASCADE` back-reference.

The `EXCEPTION` wrapper is the FI's "treat a FK violation there as a signal" turned into an observable pg_cron log entry: the `demo_sessions` delete in step 3 is already committed at the point step 4 runs (they're separate statements inside the same top-level pg_cron txn — plpgsql exception handling creates a subtransaction around step 4 that rolls back only step 4 on FK violation), so a failure in step 4 preserves the cascade progress of step 3 and leaves a retryable orphan for the next tick to sweep. If we let the exception propagate we'd roll back the whole batch and enter a poison-pill retry loop.

**One-time historical backfill (same migration, DO block at the end):** delete the 59 already-orphaned rows with a single narrowly-filtered statement:

```sql
DELETE FROM auth.users
WHERE is_anonymous = true
  AND (raw_user_meta_data->>'demo_placeholder') IS DISTINCT FROM 'true'
  AND NOT EXISTS (SELECT 1 FROM public.demo_sessions WHERE auth_user_id = auth.users.id)
  AND NOT EXISTS (SELECT 1 FROM public.setlists    WHERE created_by    = auth.users.id)
  AND NOT EXISTS (SELECT 1 FROM public.gigs        WHERE created_by    = auth.users.id);
```

The `raw_user_meta_data` predicate is the load-bearing exclusion for the 13 template placeholders; the two `NOT EXISTS` predicates defend against the FK-violation ordering constraint (skip any orphan that unexpectedly still has a `setlists`/`gigs` reference — those need manual investigation, not silent auto-delete). `RAISE NOTICE` the deleted-row count for the migration log so Tony can confirm the expected ~59 landed.

### Path B — `exit_demo_session()` (client-invoked)

Follow the existing `delete_user_account` convention: leave the RPC's SQL boundary at `public.*` and route the final `auth.users` deletion through a new Edge Function using `auth.admin.deleteUser()` under the service role. This is the FI's explicitly preferred option ("Follow that same convention here for consistency rather than inventing a different approach").

**New Edge Function** `supabase/functions/exit-demo-session/index.ts` — `verify_jwt = true`. Two Supabase clients per the codebase pattern:

- User-scoped client (Authorization header forwarded): calls `client.rpc('exit_demo_session')` — the existing RPC's own `is_anonymous` check passes because the JWT is the caller's.
- Service-role client: calls `admin.auth.admin.deleteUser(uid)` after the RPC returns.

Anonymous check: reuse the `isAnonymousSession(req)` JWT-decode pattern from `send-bug-report`/`send-band-invite`, inverted polarity (accept only when `is_anonymous === true`). Extract `sub` from the same decoded payload for the uid to pass to `admin.deleteUser`. `verify_jwt = true` already guarantees signature and expiry, so the decode is only a claims read.

**Sequence inside the handler** is exactly the FI's ordering constraint made mechanical: RPC first (deletes `demo_sessions`, cascades bands, cascades `setlists`/`gigs` via `band_id`), then `admin.deleteUser` (safe because nothing references `uid` anymore in `setlists.created_by`/`gigs.created_by`). If `admin.deleteUser` returns an error, respond 500 with the message; the cron sweep will pick up the residual `auth.users` row within 5 minutes as an orphan.

**Existing `exit_demo_session()` RPC is intentionally NOT modified.** Two reasons: (1) it's the "step 1" primitive the Edge Function orchestrates, so its contract stays scoped to `demo_sessions` cleanup; (2) any legacy direct-RPC caller that hasn't updated to the Edge Function still gets partial cleanup and the cron sweep converges within one tick. Direct SQL delete of `auth.users` from within a client-invoked SECURITY DEFINER RPC is explicitly declined here per the FI: no rationale in this bug's scope justifies diverging from the `delete_user_account` precedent.

**Client change** ([lib/features/auth/demo_session_service.dart#L52-L60](lib/features/auth/demo_session_service.dart#L52-L60)): replace `await client.rpc('exit_demo_session')` with `await client.functions.invoke('exit-demo-session')`; check the response's status and throw on non-2xx; keep the subsequent `await client.auth.signOut()` unchanged.

### Complementary owner-run action (not blocking, out of scope for Engineer)

Feature Input flagged a Supabase Auth dashboard toggle for automatic anonymous-user cleanup after N days. Only Tony can enable this. It doesn't obviate the ordering-safe fix above (it hits the same FK constraint if enabled without the ordering) but is a useful additional safety net. Called out in Rollout Strategy → Owner Punch List.

## Database Impact

New migration `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` — one file, two operations:

1. `CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()` with the rewritten body (LANGUAGE `plpgsql`, same `SECURITY DEFINER`, same `SET search_path = public`).
2. Idempotent grant re-application: `REVOKE ALL ON FUNCTION public.cleanup_expired_demo_sessions() FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.cleanup_expired_demo_sessions() TO postgres;` (identical to the current file — `CREATE OR REPLACE` preserves grants, but explicit re-apply is defensive and matches the surrounding style).
3. One-time historical backfill DO block executing the filtered `DELETE FROM auth.users` above, with `RAISE NOTICE` reporting `rowcount`.

No new tables, no RLS changes, no new RPCs, no pg_cron reschedule (the job name and cron expression are unchanged — the function body swap propagates transparently on the next tick).

## Flutter Architecture Changes

None beyond one method-body change in [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart): swap the RPC call for `functions.invoke('exit-demo-session')` and add a response-status check. No new controllers, providers, repositories, or files.

## Files to Create

- [supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql](supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql) — described in Database Impact.
- [supabase/functions/exit-demo-session/index.ts](supabase/functions/exit-demo-session/index.ts) — Edge Function with the two-client orchestration.

## Files to Modify

- [supabase/config.toml](supabase/config.toml) — add `[functions.exit-demo-session]` block with `verify_jwt = true`, placed alphabetically after `[functions.deliver-notifications]` (line ~114) or grouped with the other `verify_jwt = true` functions. Placement is up to Engineer; the guardrail is that `verify_jwt = true` matches the deployed config.
- [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) — inside `DemoSessionService.exit(WidgetRef ref)`, change the RPC call to an Edge Function invocation and check the response status. Do not touch `provisionAndEnter` or `heartbeat`; do not remove or restructure the try/catch or the `client.auth.signOut()` that follows.

## Files Off-Limits

- [supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql](supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql) — historical migration; the `exit_demo_session()` RPC's contract is intentionally preserved (see Path B rationale). Do not append to or edit this file.
- [supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql](supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql) — historical migration; the new migration `20260908120000_...` supersedes the function body via `CREATE OR REPLACE`. Do not edit this file.
- [supabase/migrations/075_delete_user_account_rpc.sql](supabase/migrations/075_delete_user_account_rpc.sql) — the analogous real-user gap the FI notes but explicitly excludes ("This is explicitly OUT OF SCOPE for this feature — do not fix it, just note it if relevant"). Do not touch.
- [supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql) — the 13 template-fixture `auth.users` rows are permanent by design; the `raw_user_meta_data->>'demo_placeholder' = 'true'` marker is the load-bearing exclusion. Do not modify the marker or the seed rows.
- [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql) — demo entry path; unchanged.
- Any other `supabase/functions/**` or `lib/**` — unrelated to this bug.
- `.github/agents/**` — pipeline configuration; do not modify.

## Change Budget

- `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` — new file, expected ~80–100 lines (function body + guarded delete + grants + backfill DO block + explanatory comments).
- `supabase/functions/exit-demo-session/index.ts` — new file, expected ~90–110 lines (env vars, `isAnonymousSession`/uid-extract helpers, CORS, two-client orchestration, error responses).
- `supabase/config.toml` — expected `+3` lines (one section header, one `verify_jwt` line, one blank separator).
- `lib/features/auth/demo_session_service.dart` — expected net delta approximately `+4` lines inside the existing `exit` method (RPC call → `functions.invoke` call + response-status check). No other changes to the file.
- Expected new files: `2`.
- Expected new public classes/methods: `0` (the Edge Function has no exported symbols; the Dart change is inside an existing static method).
- Expected new dependencies: `0`.

## System Impact Map

| System        | Status                        | Notes                                                                                                                                                                                                                                                                 |
| ------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs          | unaffected                    | `gigs.created_by → auth.users` is one of the two `ON DELETE NO ACTION` back-references — the fix specifically relies on demo-owned `gigs` rows being cascade-deleted via `band_id` before `auth.users` is touched, but no `gigs` schema, RPC, or client code changes. |
| Rehearsals    | unaffected                    | Cascade path only; no code touch.                                                                                                                                                                                                                                     |
| Setlists      | unaffected                    | `setlists.created_by → auth.users` — same story as `gigs.created_by`. Cascade path only; no code touch.                                                                                                                                                               |
| Members       | unaffected                    | `band_members` cascades on `band_id` from `bands` and on `user_id` from `auth.users`; both paths already exist and are unchanged.                                                                                                                                     |
| Auth          | affected — additive only      | New Edge Function invocation replaces one RPC call in the demo exit flow. Existing real-user auth (magic link, PKCE, sign-out) is not touched. Template-placeholder `auth.users` rows are protected by the `demo_placeholder` filter.                                 |
| Routing       | unaffected                    | No routing/navigation changes.                                                                                                                                                                                                                                        |
| Notifications | unaffected                    | No touchpoint.                                                                                                                                                                                                                                                        |
| Platforms     | unaffected — parity preserved | The Dart change lives in `lib/features/auth/demo_session_service.dart` (shared across iOS, Android, macOS, Web). No platform-conditional code. Native and web both hit the new Edge Function.                                                                         |
| Init order    | unaffected                    | Fixed init sequence (`WidgetsFlutterBinding` → URL strategy → orientation → `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize` → conditional Firebase → `DeepLinkService` → `runApp`) is not touched.                                        |

## Regression Risk — MEDIUM

Justification for MEDIUM (not LOW, not HIGH):

- Auth surface IS touched (the whole point of the fix). But the touch is narrowly scoped to the demo exit path plus a superuser cron function that has no other caller — real-user auth is entirely off the diff.
- Load-bearing assumption: the `setlists`/`gigs` back-references (`created_by ON DELETE NO ACTION`) are cleared via the `band_id` cascade chain before `auth.users` is deleted. This is verified by walking the migrations for both `demo_sessions → bands` and `bands → setlists`/`gigs` cascade edges, and by the wrapping `EXCEPTION WHEN foreign_key_violation` handler in Path A that surfaces any violation as a `WARNING` in the pg_cron log rather than crashing the sweep. QA verifies this against an ephemeral DB.
- Load-bearing exclusion: template-fixture accounts are protected by `raw_user_meta_data->>'demo_placeholder' = 'true'` in the backfill filter. QA verifies this in the SQL review — an accidentally-broadened predicate would delete the 13 seed accounts and gut both template bands.
- No RLS changes, no new RPC surface exposed to `anon`, no init-order changes, no routing changes, no dependency changes. Cron job name and schedule unchanged.

## Engineer Task Breakdown

1. Create [supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql](supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql). Structure:
   - Header comment (one paragraph) — refer to the bug slug and summarise the two-part change.
   - `CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ DECLARE v_expired_user_ids uuid[]; BEGIN ... END; $$;` with the four-step body from Path A. Use `RAISE WARNING` (not `NOTICE`) inside the `EXCEPTION` handler so pg_cron logs surface FK violations at the right severity.
   - `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon;` + `GRANT EXECUTE ... TO postgres;` — verbatim from the existing migration for consistency, since `CREATE OR REPLACE` preserves grants but explicit re-apply matches surrounding style.
   - Single `DO $$ ... END $$;` block executing the filtered `DELETE FROM auth.users` above with a `GET DIAGNOSTICS` + `RAISE NOTICE 'backfill deleted % orphaned anon auth.users rows', ...` so the migration output confirms the expected count.
2. Create [supabase/functions/exit-demo-session/index.ts](supabase/functions/exit-demo-session/index.ts). Structure mirroring the `send-bug-report` skeleton:
   - Imports: `"jsr:@supabase/functions-js/edge-runtime.d.ts"` + `{ createClient } from "https://esm.sh/@supabase/supabase-js@2"`.
   - Env constants: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` (needed for the user-scoped client — verify the exact env var name via `Deno.env.get("SUPABASE_ANON_KEY")` matches what the runtime injects; if unavailable, the user-scoped client can be built with the caller's JWT as both auth header and apikey per the Supabase JS SDK convention).
   - `isAnonymousDemo(req: Request): { ok: true; uid: string } | { ok: false }` helper: JWT-decode the Authorization header, verify `payload.is_anonymous === true`, return `{ ok: true, uid: payload.sub }`.
   - `Deno.serve` handler: OPTIONS/CORS preflight; POST-only (405 on other verbs); reject non-anonymous JWTs with 403; build user-scoped client (forwarding `Authorization` header); `await userClient.rpc('exit_demo_session')` and return 500 if it errors; build service-role client; `await serviceClient.auth.admin.deleteUser(uid)` and return 500 if it errors; return 200 `{ success: true }`.
   - No body payload required from the client — uid comes from the JWT.
3. Modify [supabase/config.toml](supabase/config.toml) to add:
   ```toml
   [functions.exit-demo-session]
   verify_jwt = true
   ```
   Placement: grouped with the other `verify_jwt = true` entries. Do not touch any other section.
4. Modify [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) `exit` method: swap `await client.rpc('exit_demo_session')` for `final response = await client.functions.invoke('exit-demo-session');` and add `if (response.status < 200 || response.status >= 300) { throw DemoSessionException('Demo exit failed: HTTP ${response.status}'); }`. Keep the subsequent `await client.auth.signOut()` and the surrounding try/catch unchanged.
5. Run `flutter analyze` after the client change; expect zero new warnings/errors.

There is no step 6.

## Verification Plan

QA cannot run the app, cannot exercise the demo entry/exit UI, and cannot invoke Supabase Auth's admin API against prod. QA's gate is mechanical: static analysis + SQL/migration review + ephemeral-DB apply-check. On-device and prod-touching checks land in the Owner Punch List for Tony.

### Tier 1 — pre-deploy, mechanical (QA gate for APPROVED)

Static:

1. `flutter analyze` — clean, zero new warnings/errors introduced by the `demo_session_service.dart` change.
2. Diff review of the two new files and two modified files against Change Budget line counts; flag any drift ≥ 25% as WARNING.
3. Migration file passes SQL syntax parse (e.g. `psql --set ON_ERROR_STOP=on -f <file> --dry-run`-style check via ephemeral apply below).

Ephemeral DB apply-check (against a throwaway Supabase-schema DB, no prod touch — QA already runs this class of check): 4. Apply all existing migrations in order, then apply the new `20260908120000_fix_demo_auth_user_cleanup.sql`. Confirm it applies cleanly. 5. `SELECT prosecdef, pronargs, lanname FROM pg_proc JOIN pg_language ON pg_language.oid = pg_proc.prolang WHERE proname = 'cleanup_expired_demo_sessions' AND pronamespace = 'public'::regnamespace;` — confirm `prosecdef = true`, `pronargs = 0`, `lanname = 'plpgsql'`. 6. `SELECT has_function_privilege('postgres', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` — expect `true`. Then `SELECT has_function_privilege('anon', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` and `SELECT has_function_privilege('authenticated', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` — both expect `false`. Do NOT string-match `proacl` array; use `has_function_privilege`. 7. SQL rollback test for the guarded delete path — never calls the function itself, only verifies the FK topology the fix relies on:

```sql
BEGIN;
  -- Seed: minimal anon auth.users + demo_sessions + clone band + a setlist/gig owned by the anon user
  -- ...
  -- Assert: DELETE FROM public.demo_sessions WHERE auth_user_id = <id> cascades bands, setlists, gigs
  -- Assert: DELETE FROM auth.users WHERE id = <id> succeeds (no FK violation) and cascades public.users
ROLLBACK;
```

Add this as a new test group in whichever SQL test harness the repo uses (or as a standalone `.sql` file executed by the ephemeral apply pipeline — Engineer picks the surface; QA verifies it runs and passes). The test must NOT hardcode any production UUID; every UUID is generated in the test setup and torn down by the rollback. 8. Backfill filter safety check — assert the query in the DO block would NOT match any of the 13 template-fixture accounts. Same ephemeral DB, seeded with the template migration:

```sql
SELECT count(*) FROM auth.users
WHERE id IN ('00000000-0000-4000-8000-000000000001', /* ...12 more... */)
  AND is_anonymous = true
  AND (raw_user_meta_data->>'demo_placeholder') IS DISTINCT FROM 'true';
-- Expect: 0
```

9. TypeScript sanity for the new Edge Function: `deno check supabase/functions/exit-demo-session/index.ts` (or the repo's existing edge-function typecheck target if one exists — check `Makefile` / `tools/`). No runtime execution required; typecheck only.

If any of 1–9 fail, QA returns CHANGES_REQUESTED with the specific failing item. Never wave through a warning on a load-bearing item.

### Tier 2 — post-apply (owner-run, not a QA gate)

Tony runs these after applying the migration and deploying the Edge Function. Everything below is on the Owner Punch List; QA hands the list to Tony verbatim.

10. Apply the migration against prod (`supabase db push` or Dashboard). Watch the migration log for the backfill's `RAISE NOTICE` — expect the deleted-row count to be near the FI's 59 (may be higher if additional visitors have entered between plan date and apply date; may be lower if any of the 59 already got manually cleaned).
11. `SELECT count(*) FROM auth.users WHERE is_anonymous = true AND (raw_user_meta_data->>'demo_placeholder') IS DISTINCT FROM 'true';` — expect 0 (all orphans gone; only active demo sessions if any).
12. `SELECT count(*) FROM auth.users WHERE id IN (/* 13 template placeholder ids */);` — expect 13 (none deleted).
13. `SELECT count(*) FROM public.bands WHERE is_demo_template = true;` — expect 2 (both template bands intact).
14. Deploy the Edge Function: `supabase functions deploy exit-demo-session`. Verify `[functions.exit-demo-session] verify_jwt = true` in `config.toml` matches the Dashboard's function config.
15. On-device manual: enter demo, tap Exit Demo, then in prod query `SELECT * FROM auth.users WHERE id = '<the demo visitor uid>';` — expect zero rows immediately after the button tap returns.
16. On-device manual: enter demo, background the app for 30+ minutes to let the session expire, then check auth.users — expect zero rows after the next cron tick.
17. (Optional owner-run) In the Supabase Auth dashboard, check whether the automatic-anonymous-cleanup toggle exists and consider enabling it as a complementary safety net (documented in FI Additional Context).

### Explicitly NOT verified

- No RLS policy is created or modified, so no anon-grant/policy-recursion audit.
- No new SECURITY DEFINER function is introduced — `cleanup_expired_demo_sessions()` already existed and its grant surface is unchanged.
- No submission flow (Engineer Task Breakdown adds no serialize/re-parse path); the idempotency check that applies to submission flows is `n/a` here.

## QA Regression Areas

- Prod query — no non-template `is_anonymous = true` rows remain after apply (item 11 above).
- Prod query — 13 template placeholders unchanged (item 12).
- Prod query — both template bands intact (item 13).
- Ephemeral DB test — cascade ordering holds (item 7).
- Ephemeral DB test — backfill filter never touches template placeholders (item 8).
- `flutter analyze` — clean (item 1).
- `has_function_privilege` — grants intact (item 6).

## Rollout Strategy

Single-branch, single-PR. No feature flag — the Edge Function is a new deploy target and the migration is idempotent (`CREATE OR REPLACE` + a filtered DO block that's safe to re-run because a re-run finds zero matching rows). Apply order at deploy time:

1. Merge PR to main.
2. Tony applies migration `20260908120000_fix_demo_auth_user_cleanup.sql` against prod. Confirm backfill row count.
3. Tony deploys Edge Function `exit-demo-session` via `supabase functions deploy exit-demo-session`.
4. Tony ships the mobile/web build carrying the updated `demo_session_service.dart`.

Order 2 → 3 → 4 is deliberate: even if Tony holds off on 4, the cron sweep (step 2's function body change) starts cleaning up expired sessions cleanly and the historical backfill has already run. Clients on the OLD build still calling the old RPC continue to work (RPC contract unchanged); their `auth.users` residue is picked up by the cron sweep within 5 minutes. No client outage window.

Rollback plan: single migration revert file that re-`CREATE OR REPLACE`s the pre-fix function body (`LANGUAGE sql`, the one-statement delete). Historical backfill is irreversible (deleted rows are gone) but the deleted rows were already logically orphaned so the effective rollback is only for the ongoing function behavior. Edge Function can be un-deployed (`supabase functions delete exit-demo-session`); the client's `functions.invoke` call then 404s and the DemoSessionException is thrown — visitors see an error snackbar, not a crash — and can log out via the standard sign-out flow. Client rollback: revert the `demo_session_service.dart` diff to restore the RPC call.

### Owner Punch List (Tony runs these; QA does not attempt them)

1. Apply migration; confirm backfill NOTICE count. Expected step in Rollout Strategy §2.
2. Deploy Edge Function; verify Dashboard `verify_jwt` matches `config.toml`.
3. Ship client build.
4. Run prod verification queries 11–13.
5. On-device demo entry → Exit Demo → verify `auth.users` is gone (item 15).
6. On-device demo entry → wait for 30-min expiry → verify cron cleanup (item 16).
7. Check Supabase Auth dashboard for the anonymous-user auto-cleanup toggle; enable if it's now available and Tony wants the extra safety net.

## Out of Scope

- Fixing `delete_user_account` (migration `075_delete_user_account_rpc.sql`) to actually remove the real-user `auth.users` row. FI explicitly excludes this: "This is explicitly OUT OF SCOPE for this feature — do not fix it, just note it if relevant." Noted here; not fixed.
- Modifying `exit_demo_session()` RPC's body. It's the Edge Function's step-1 primitive; direct SQL delete of `auth.users` from a client-invoked SECURITY DEFINER function is declined per the FI's guidance to follow the `delete_user_account` convention.
- Revoking `authenticated` from `exit_demo_session()` to force all callers through the Edge Function. Anonymous sessions are ephemeral (max 30 min lifetime); legacy direct-RPC callers get partial cleanup and the cron sweep converges within one tick. Locking the RPC would break any not-yet-updated client, which is a bigger regression risk than the transient residue.
- Provisioning-side changes to `provision_demo_session()`. The bug is on the teardown path only.
- Any changes to the `is_anonymous` JWT guard used by other Edge Functions (`send-bug-report`, `send-band-invite`). Their reject-anon polarity is correct and unrelated.
- Configuring/enabling Supabase Auth dashboard toggles. Owner-only action.
- Google Sheet sync (`bandroadie-band-member-sheet-sync`) — FI notes this was fixed separately today and is unrelated to this DB-side cleanup.
