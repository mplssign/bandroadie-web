# ARCHITECT_PLAN — Demo Session Provisioning Not Idempotent

## Feature Slug

`bug/demo-session-provisioning-not-idempotent`

## Feature Title

Demo session provisioning is not idempotent — fix idempotency read type mismatch, add concurrency ceiling, harden pg_cron registration, and reuse anonymous sessions on re-entry.

## Problem Summary

The interactive-demo work on `feature/interactive-demo-band-experience` shipped a clone-per-visitor model (visitor gets a fresh `auth.uid()`, RPC clones both template bands + all child rows for that user, cascade cleanup on session expire). That model is **settled and correct** — this plan does NOT redesign it. What it does have is four defects and one operational gap that together cause the "not idempotent" symptom in production:

1. The RPC's returning-visitor path assigns a `UUID[]` column into a scalar `UUID` variable — any second call by the same anon user hits a PL/pgSQL runtime error before the early-return can execute.
2. The Flutter client calls `signInAnonymously()` unconditionally on every demo entry, minting a fresh `auth.uid()` even when a live anonymous session is already restored, so the RPC's `auth_user_id` dedupe key never matches — which cascades into a full re-clone.
3. The RPC has no concurrency ceiling: a burst of demo taps can clone unboundedly (each ~200 rows) before the cron sweep runs.
4. The `INSERT INTO demo_sessions` has no `EXCEPTION WHEN unique_violation` guard, so a double-tap or two-tab race on the same identity surfaces a raw `duplicate key value violates unique constraint` Postgres error instead of returning the winner's clone IDs.
5. The pg_cron job that sweeps expired sessions is **not registered** in production (`SELECT * FROM cron.job WHERE jobname='cleanup_demo_sessions'` returns 0 rows). Eight stale sessions have accumulated since the schema was applied because nothing has swept them.

Also identified during the file re-run-safety audit: `20260904120000_demo_bands_schema.sql` creates two RLS policies without `DROP POLICY IF EXISTS` guards, so re-applying the file against the already-live prod state errors with "policy already exists" — blocking every corrective re-apply. And an admin/analytics quality gap: `bands` currently counts demo rows in every query, with no view that excludes them.

## Root Cause

All causes verified directly in code. Confidence per item below.

### #1 — RPC idempotency read assigns `UUID[]` into scalar `UUID` (HIGH — BLOCKING)

`supabase/migrations/20260904120003_provision_demo_session_rpc.sql`, lines 55-65:

```sql
SELECT id, clone_band_ids INTO v_session_id, v_bs_band_id  -- L55 — v_bs_band_id is UUID, clone_band_ids is UUID[]
FROM demo_sessions
WHERE auth_user_id = v_user_id;

IF FOUND THEN
  RETURN jsonb_build_object(
    'banana_stand_band_id', (SELECT clone_band_ids[1] FROM demo_sessions WHERE id = v_session_id),  -- L62
    'modal_nodes_band_id',  (SELECT clone_band_ids[2] FROM demo_sessions WHERE id = v_session_id)   -- L63
  );
END IF;
```

`v_bs_band_id` is declared `UUID` at L20; `demo_sessions.clone_band_ids` is `UUID[] NOT NULL DEFAULT '{}'` per `20260904120000_demo_bands_schema.sql` L20. PL/pgSQL raises `cannot assign a value of type uuid[] to a variable of type uuid` at `SELECT ... INTO`. The redundant subselects at L62-63 (re-reading the same row to extract `[1]` and `[2]`) indicate the original author knew the array shape but never removed the broken `INTO` — the whole idempotency block is dead code because the exception fires on L55 first. Every returning-visitor call (refresh, tab-switch, reconnect within the 30-min window) hits this.

### #2 — Client mints a fresh anon session unconditionally (HIGH)

`lib/features/auth/demo_session_service.dart`, lines 15-27:

```dart
static Future<String> provisionAndEnter(WidgetRef ref) async {
  final client = Supabase.instance.client;
  final bandNotifier = ref.read(activeBandProvider.notifier);
  try {
    await client.auth.signInAnonymously();                    // L20 — unconditional mint
    final result = await client.rpc('provision_demo_session');
    final bananaId =
        (result as Map<String, dynamic>)['banana_stand_band_id'] as String;
    await bandNotifier.loadAndSelectBand(bananaId);
    return bananaId;
  } catch (e, st) { ... }
}
```

`gotrue-dart`'s `signInAnonymously()` always POSTs to `/signup` with `is_anonymous = true`, minting a new `auth.users` row and replacing the local session — there is no "reuse existing" path in the SDK. Because L20 is unconditional, every `provisionAndEnter` call gets a fresh `auth.uid()`, so the RPC's dedupe key at (fixed-#1) L55 never matches even if #1 were repaired. Net effect: each tap of the demo button produces a fresh clone (~200 rows), and the previous clone sits stranded until the (currently unregistered — see #5) cron sweep.

### #2b — `auth_gate.dart` reconciler interaction (HIGH — no change required)

`lib/features/auth/auth_gate.dart`, lines 295-311, `_reconcileOrphanedAnonymousSession()`:

```dart
await ref.read(activeBandProvider.notifier).loadUserBands();
if (!mounted) return;
final hasBands = ref.read(activeBandProvider).userBands.isNotEmpty;
final stillAnonymous = supabase.auth.currentUser?.isAnonymous == true;
if (!hasBands && stillAnonymous) {
  // ...
  await supabase.auth.signOut(scope: SignOutScope.global);
}
```

The global sign-out fires **only** when both conditions hold: the anonymous session was restored AND the user has zero band memberships (i.e., the cron has already swept this visitor's clone). This is the correct gate — if the visitor still has active `band_members` rows, the reconciler is a no-op and the session persists across restarts. Therefore the #2 fix in the client has something real to reuse: a cold-restart with intact memberships preserves the anon session, and re-entry via the login screen would (with the guard) skip the fresh mint and let the RPC's fixed-#1 idempotency check return the existing clone IDs. **No change to `auth_gate.dart` is required for #2**, and none is proposed here.

### #3 — No concurrency ceiling (HIGH)

The RPC (`20260904120003`) has no guard against unbounded concurrent provisioning. A burst of demo taps from marketing traffic — plausible for a public demo — will clone once per fresh `auth.uid()`, each producing ~200 rows across 14 tables. Even after #1/#2 are fixed, distinct visitors are inherently new UUIDs and will each get their own clone (the settled design). A ceiling protects against pathological load and lets the client show a friendly "demo's busy" message instead of a slow success followed by a stranded orphan clone. The task specifies **30** as the ceiling.

### #4 — No `unique_violation` guard on `demo_sessions` insert (HIGH)

`20260904120003_provision_demo_session_rpc.sql`, lines 87-89:

```sql
INSERT INTO demo_sessions (auth_user_id, clone_band_ids)
VALUES (v_user_id, '{}')
RETURNING id INTO v_session_id;
```

`demo_sessions.auth_user_id` is `UNIQUE` (schema L17). There is no `SELECT ... FOR UPDATE` upstream — the idempotency check at L55-65 is a plain `SELECT` — so two concurrent RPC calls by the same anon user (double-tap, two tabs, or a race between the client retry after a network blip and the original inflight request) both fall through, both hit L87, and the loser gets `duplicate key value violates unique constraint "demo_sessions_auth_user_id_key"` (PostgreSQL SQLSTATE `23505`) surfacing at the client as a raw `PostgrestException`. The fix is a nested block with `EXCEPTION WHEN unique_violation THEN`, re-reading the winner's row and returning its JSON.

### #5 — pg_cron job not registered in production (HIGH — BLOCKING)

Owner verified against prod: `SELECT * FROM cron.job WHERE jobname = 'cleanup_demo_sessions'` returns zero rows. All 8 stale `demo_sessions` and their cascaded clone bands have accumulated because nothing sweeps them. Migration `20260904120005_cleanup_demo_sessions_cron.sql` at L32-36 calls `cron.schedule(...)` (which IS upsert-by-jobname per pg_cron docs), so on paper a re-apply would register it. Most likely reasons the first apply silently produced no job row (ranked by fit for the observed symptom):

1. **`CREATE EXTENSION IF NOT EXISTS pg_cron` and the subsequent `cron.schedule` call ran in the same top-level transaction, and pg_cron requires the extension to be visible in a committed transaction before `cron.schedule` can register a job.** On Supabase, extensions are typically enabled via the Dashboard's Extensions UI (which commits its own txn), not from a migration — a raw `psql`-style bulk-apply of the file can hit this ordering issue. This best matches "L10 says `CREATE EXTENSION IF NOT EXISTS` and L32 says `cron.schedule` but the resulting `cron.job` row does not exist."
2. The command string at L35 (`$$SELECT cleanup_expired_demo_sessions()$$`) is missing the `public.` schema qualifier, so pg_cron's background worker (which runs with `search_path` reset to safe defaults) would fail to resolve the function even IF the job registered. Registration and execution failure are separate concerns, but qualifying the name closes both.
3. Role/permission on the `cron` schema is a distant third — the owner applies via direct SQL as `postgres` per the task, which has `cron.schedule` privileges by default on Supabase.
4. Malformed schedule string is out — `*/5 * * * *` is valid.

**Hardening approach** (details in Proposed Solution) makes registration self-verifying: a pre-check that fails loudly if `pg_extension` doesn't list `pg_cron`, an idempotent `cron.unschedule` first, the `cron.schedule` call with the fully qualified function name, and a post-assertion `DO` block that raises if `cron.job` doesn't contain the row afterward. Whichever of (1)/(2) actually caused the silent failure, the re-apply now either succeeds provably or fails loudly.

### #0 (file audit) — Missing `DROP POLICY IF EXISTS` guards (HIGH)

`20260904120000_demo_bands_schema.sql`, L32-40:

```sql
CREATE POLICY demo_sessions_select_own ON public.demo_sessions
  FOR SELECT
  USING (auth_user_id = auth.uid());

CREATE POLICY demo_sessions_update_own ON public.demo_sessions
  FOR UPDATE
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());
```

No `DROP POLICY IF EXISTS` guards. Re-applying against the already-live prod state errors with `policy "demo_sessions_select_own" for table "demo_sessions" already exists` on the first `CREATE POLICY`. This blocks the corrective re-apply of the whole file — including the view fix below. Same-file precedent is already the correct pattern: `DROP TRIGGER IF EXISTS` at L98/L103/L108/L113/L118/L123/L128/L133 all use the guard.

Full re-run-safety audit of `20260904120000_demo_bands_schema.sql`:

| Line         | Statement                                                               | Re-run safe? | Notes                            |
| ------------ | ----------------------------------------------------------------------- | ------------ | -------------------------------- |
| 15-21        | `CREATE TABLE IF NOT EXISTS demo_sessions`                              | Yes          | `IF NOT EXISTS`                  |
| 23-24, 26-27 | `CREATE INDEX IF NOT EXISTS`                                            | Yes          | `IF NOT EXISTS`                  |
| 29           | `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`                             | Yes          | Idempotent by Postgres           |
| 32-34        | `CREATE POLICY demo_sessions_select_own`                                | **No**       | Fix: add `DROP POLICY IF EXISTS` |
| 36-40        | `CREATE POLICY demo_sessions_update_own`                                | **No**       | Fix: add `DROP POLICY IF EXISTS` |
| 47-51        | `ALTER TABLE ADD COLUMN IF NOT EXISTS` (x3)                             | Yes          | `IF NOT EXISTS`                  |
| 53-57        | `CREATE INDEX IF NOT EXISTS` (x2)                                       | Yes          | `IF NOT EXISTS`                  |
| 63-92        | `CREATE OR REPLACE FUNCTION prevent_anonymous_template_write`           | Yes          | `OR REPLACE`                     |
| 94-95        | `REVOKE ALL ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated;` | Yes          | Idempotent grants                |
| 98-136       | `DROP TRIGGER IF EXISTS ... ; CREATE TRIGGER ...` (x8)                  | Yes          | Already guarded                  |

Only the two `CREATE POLICY` statements need guards. Every other statement in the file is safe.

### Added scope — `bands_real` view (from Feature Input)

No `bands_real` view exists (grep confirmed). Admin/analytics queries against `bands` silently count demo template + clone rows. Adding a view with `WHERE is_demo_template = false AND is_demo_clone = false` is a one-line quality gate.

### Confidence summary

| Item                            | Confidence              | Blocking?             |
| ------------------------------- | ----------------------- | --------------------- |
| #1 idempotency type mismatch    | HIGH                    | Yes                   |
| #2 client always mints anon     | HIGH                    | No                    |
| #2b `auth_gate.dart` reconciler | HIGH (no change needed) | —                     |
| #3 no concurrency ceiling       | HIGH                    | No                    |
| #4 no unique_violation guard    | HIGH                    | No                    |
| #5 pg_cron not registered       | HIGH                    | Yes                   |
| #0 missing policy guards        | HIGH                    | Yes (blocks re-apply) |
| Added `bands_real` view         | HIGH (net-new feature)  | No                    |

## Existing System Analysis

### Ground truth (owner verified against prod, per Feature Input)

- The clone-per-visitor demo schema is **already live** in prod, applied via direct SQL — not via `supabase db push`.
- `provision_demo_session()` has run 8 times in prod.
- **None of `20260904120000`–`20260904120005` are tracked in `supabase_migrations.schema_migrations`** (last tracked: `20260902120001`).
- Consequence: **in-place edits to these six migration files ARE effective.** Whatever next re-applies them (owner, via direct SQL) will pick up the edits. Therefore all fixes below are IN-PLACE edits, NOT new forward migrations.
- Consequence: every edited migration must be **re-run safe** against the already-live prod state.

### Architecture — settled, this plan preserves it verbatim

Keeping unchanged: the `demo_sessions` ledger (`UNIQUE(auth_user_id)`), `bands.is_demo_template` / `bands.is_demo_clone` / `bands.demo_session_id` (with `ON DELETE CASCADE` → cascade cleanup on `demo_sessions` DELETE), `demo_sessions.clone_band_ids`, the `prevent_anonymous_template_write` trigger, `heartbeat_demo_session` / expiry semantics, and the pg_cron 5-min sweep. The client contract of `provision_demo_session` — return shape `{banana_stand_band_id, modal_nodes_band_id}` — is preserved.

### Client surface

`demo_session_service.dart` (51 lines total) is the sole caller of `provision_demo_session`, `exit_demo_session`, and `heartbeat_demo_session`. Its `provisionAndEnter` (L15-33) is the only site touched by this plan. `exit` (L35-43) and `heartbeat` (L45-50) are unchanged.

`auth_gate.dart` — reconciler at L295-311 gates global sign-out on the correct condition (see §Root Cause #2b). No change.

## Cycle Note

This plan **replaces** a prior stale plan at the same path that proposed a wholesale redesign (drop `is_demo_clone`, `demo_session_id`, `clone_band_ids`, trigger; convert clone-per-visitor → shared-bands+reset). The owner has rejected that redesign. This corrected plan keeps the settled clone-per-visitor architecture and addresses the concrete defects in place. All prior "Files to Create" / "Files to Modify" from the stale plan are void.

## Proposed Solution

### #1 — Fix the idempotency read (`20260904120003`)

Replace the `SELECT id, clone_band_ids INTO v_session_id, v_bs_band_id` at L55 and the two redundant subselects at L62-63 with:

- Declare a new local variable `v_existing_clone_ids UUID[]` alongside the existing declarations (L17-50 block).
- Change L55 to `SELECT id, clone_band_ids INTO v_session_id, v_existing_clone_ids`.
- Change L62 to `'banana_stand_band_id', v_existing_clone_ids[1]::text` (or `to_jsonb(v_existing_clone_ids[1])`, whichever matches the existing JSON encoding — `to_jsonb` is safer against a NULL element).
- Change L63 to `'modal_nodes_band_id', v_existing_clone_ids[2]::text` similarly.
- Delete the two `(SELECT clone_band_ids[N] FROM demo_sessions WHERE id = v_session_id)` subqueries.

Result: returning-visitor path succeeds silently, no re-clone, no exception.

### #2 — Reuse the live anonymous session (`demo_session_service.dart`)

Change `provisionAndEnter` (L15-33) to check the current session before minting:

```dart
static Future<String> provisionAndEnter(WidgetRef ref) async {
  final client = Supabase.instance.client;
  final bandNotifier = ref.read(activeBandProvider.notifier);
  try {
    final currentUser = client.auth.currentUser;
    final hasLiveAnon = client.auth.currentSession != null
        && currentUser != null
        && currentUser.isAnonymous == true;
    if (!hasLiveAnon) {
      await client.auth.signInAnonymously();
    }
    final result = await client.rpc('provision_demo_session');
    // ... rest unchanged
```

Reasoning: `_reconcileOrphanedAnonymousSession` (auth_gate.dart L295-311) has already globally signed out any anon session with zero band memberships. Anything reaching `provisionAndEnter` with a live anonymous session therefore still has valid memberships — the RPC's fixed-#1 idempotency read will return the existing JSON, and no new clone is created. When the session is null (post-signOut) or is a real (non-anonymous) user (defensive; AuthGate should never route here in that case), the fresh mint path is preserved.

No behavioral change to `exit` or `heartbeat`. No change to `auth_gate.dart`.

### #3 — Concurrency ceiling of 30 (`20260904120003`)

**Config-knob mechanism: named PL/pgSQL `CONSTANT` in the RPC body.** Rationale:

- No `app_config` table exists in this repo (grep across `supabase/`, `database/` returns zero matches). Introducing one for a single knob is a new table + RLS + revoke/grant + seed row + client-facing surface = a lot of new surface for one integer.
- The owner's workflow is already "edit SQL, re-apply directly via psql." Editing `v_max_concurrent CONSTANT INTEGER := 30;` and re-applying the migration file IS a one-line tune under the owner's existing flow. The tune is auditable via git blame on the migration file.
- If more knobs appear later, promoting to a proper `app_config` table is a straight refactor and not blocked by this choice.

Add near the top of the `DECLARE` block:

```sql
v_max_concurrent CONSTANT INTEGER := 30;  -- tune here; re-apply migration file
v_live_count     INTEGER;
```

After the caller-is-anonymous check (L52-56) and BEFORE the idempotency read (fixed L55), add:

```sql
SELECT count(*) INTO v_live_count
FROM public.demo_sessions
WHERE expires_at > now();

IF v_live_count >= v_max_concurrent THEN
  RAISE EXCEPTION 'demo_capacity_exceeded'
    USING ERRCODE = 'P0001',  -- generic user-defined; client greps the message
          HINT = 'Retry in a few minutes; the interactive demo is at capacity.';
END IF;
```

Ordering rationale: the ceiling check runs BEFORE the idempotency read so that a returning visitor with an existing session is NOT blocked by the ceiling on top of an already-provisioned clone — but wait, returning visitors ARE part of the live count (they have an unexpired `demo_sessions` row), so putting the ceiling first would spuriously block them. **Correction: put the ceiling check AFTER the fixed idempotency read** — if the caller already has a row, return the existing clone IDs; only enforce the ceiling for genuinely-new provisions. Final order in the RPC body:

1. Verify anonymous caller (existing L52-56, unchanged).
2. Fixed idempotency read (#1) → early return if `FOUND`.
3. Ceiling check (new #3) — only reached for new provisions.
4. Fixed `demo_sessions` insert with unique_violation guard (#4).
5. Everything else (existing L71+ clone loop).

**Client mapping to friendly error** (`demo_session_service.dart` catch block, L26-31): Extend the existing `catch (e, st)` to detect the capacity message and throw a distinct exception the LoginScreen can render as roadie-voice:

```dart
} on PostgrestException catch (e) {
  await Supabase.instance.client.auth.signOut();
  if (e.message.contains('demo_capacity_exceeded')) {
    throw DemoSessionException(
      "Demo's booked solid — try again in a few minutes.",
    );
  }
  throw DemoSessionException('Demo session failed: ${e.message}');
} catch (e, st) {
  // existing fallback unchanged
  ...
}
```

`login_screen.dart` renders `DemoSessionException.message` verbatim in its snackbar today (per existing pattern in the file), so no change there.

### #4 — `unique_violation` guard on `demo_sessions` insert (`20260904120003`)

Wrap the `INSERT INTO demo_sessions` at L87-89 in a nested block:

```sql
BEGIN
  INSERT INTO demo_sessions (auth_user_id, clone_band_ids)
  VALUES (v_user_id, '{}')
  RETURNING id INTO v_session_id;
EXCEPTION WHEN unique_violation THEN
  -- Race lost to a concurrent call by the same anon user; return the winner's clones.
  SELECT id, clone_band_ids INTO v_session_id, v_existing_clone_ids
  FROM public.demo_sessions
  WHERE auth_user_id = v_user_id;
  RETURN jsonb_build_object(
    'banana_stand_band_id', v_existing_clone_ids[1]::text,
    'modal_nodes_band_id',  v_existing_clone_ids[2]::text
  );
END;
```

`v_existing_clone_ids` is already declared for #1, reused here. The winner's row is guaranteed to exist and to have `clone_band_ids` populated by the time this handler runs — the exception handler only fires AFTER the winner's outer transaction committed (Postgres serializes transactions on unique-index conflicts).

### #5 — Harden pg_cron registration (`20260904120005`)

Rewrite the file end-to-end to be re-run safe AND self-verifying. Structure:

1. **Pre-check** — fail loudly if pg_cron isn't installed (extension is enabled outside this file, via a preceding committed transaction — the Supabase Dashboard Extensions UI or a prior `CREATE EXTENSION` in its own transaction). Remove the `CREATE EXTENSION IF NOT EXISTS pg_cron` at L10 because bundling extension creation with `cron.schedule` in the same transaction is the leading suspect for the silent-registration failure.
2. **Function** — keep `CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions()` as-is (L16-24).
3. **Grants** — keep `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO postgres;` as-is (L27-28).
4. **Idempotent unschedule** — `PERFORM cron.unschedule('cleanup_demo_sessions');` in a `DO` block that swallows `undefined_object` (no such job yet on first apply).
5. **Schedule with fully qualified function name** — `$$SELECT public.cleanup_expired_demo_sessions()$$` (add `public.` — pg_cron's background worker runs with a reset `search_path`).
6. **Post-assertion** — `DO` block that raises if `cron.job` doesn't contain a row for `cleanup_demo_sessions` after `cron.schedule` runs.

Sketch:

```sql
-- Pre-check: extension must be installed via a preceding COMMITTED transaction.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'pg_cron extension is not installed. Enable it via Supabase Dashboard → Database → Extensions in its own transaction, then re-apply this migration.';
  END IF;
END $$;

-- Function (unchanged)
CREATE OR REPLACE FUNCTION public.cleanup_expired_demo_sessions() ... ;

REVOKE ALL ON FUNCTION public.cleanup_expired_demo_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_demo_sessions() TO postgres;

-- Idempotent unschedule (no-op on first apply; clean slate on re-apply)
DO $$
BEGIN
  PERFORM cron.unschedule('cleanup_demo_sessions');
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN OTHERS THEN NULL; -- pg_cron returns "job not found" as raise_exception; swallow it
END $$;

-- Schedule with fully qualified function name
SELECT cron.schedule(
  'cleanup_demo_sessions',
  '*/5 * * * *',
  $$SELECT public.cleanup_expired_demo_sessions()$$
);

-- Post-assertion: proves the job registered, or fails loudly with a specific message.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_demo_sessions') THEN
    RAISE EXCEPTION 'cron.schedule() completed without error but cleanup_demo_sessions is not in cron.job. Check pg_cron install, role privileges on the cron schema, and that this file was applied against the pg_cron-hosting database.';
  END IF;
END $$;
```

**Owner post-apply verification** (Tier 2, in §Verification Plan): `SELECT jobname, schedule, command, active FROM cron.job WHERE jobname = 'cleanup_demo_sessions';` — must return exactly one row with `active = true` and `command = 'SELECT public.cleanup_expired_demo_sessions()'`.

### #0 — Add `DROP POLICY IF EXISTS` guards (`20260904120000`)

Before each `CREATE POLICY` at L32-34 and L36-40, insert:

```sql
DROP POLICY IF EXISTS demo_sessions_select_own ON public.demo_sessions;
-- existing CREATE POLICY demo_sessions_select_own ...

DROP POLICY IF EXISTS demo_sessions_update_own ON public.demo_sessions;
-- existing CREATE POLICY demo_sessions_update_own ...
```

Matches the same-file `DROP TRIGGER IF EXISTS` pattern at L98/L103/L108/L113/L118/L123/L128/L133. No behavioral change; policies are recreated identically.

### `bands_real` view (`20260904120000`)

Append at the end of `20260904120000_demo_bands_schema.sql`:

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 4. bands_real view — filters out demo templates and per-visitor clones so
--    admin/analytics queries don't silently count demo rows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.bands_real AS
SELECT * FROM public.bands
WHERE is_demo_template = false
  AND is_demo_clone = false;
```

Rationale for placement: this file is where `is_demo_template` and `is_demo_clone` are declared; the view sits with the schema it filters on. `CREATE OR REPLACE VIEW` is idempotent. Default `SECURITY INVOKER` semantics + RLS on `bands` keep authorization enforcement identical to querying `bands` directly.

## Database Impact

### Migration approach — IN-PLACE edits ONLY

Per Feature Input ground truth: migrations `20260904120000`–`20260904120005` are NOT tracked in `supabase_migrations.schema_migrations`. The owner will re-apply the edited files via direct SQL. **No new forward migration files.** Every edit must be re-run safe against the already-live prod state; the re-run-safety audit above documents that all edits meet this bar.

### Files edited

| File                                                                | Change summary                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`          | Add `DROP POLICY IF EXISTS` guards before both `CREATE POLICY` statements (L32, L36). Append `CREATE OR REPLACE VIEW public.bands_real`.                                                                                                                                                                                                                                                                          |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql` | Declare `v_existing_clone_ids UUID[]` and `v_max_concurrent CONSTANT INTEGER := 30;` + `v_live_count INTEGER`. Fix idempotency read at L55 to populate `v_existing_clone_ids`; drop redundant subselects at L62-63. Insert ceiling check after idempotency early-return. Wrap `INSERT INTO demo_sessions` at L87-89 in a nested block with `EXCEPTION WHEN unique_violation`. All other RPC body logic unchanged. |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql` | Remove `CREATE EXTENSION IF NOT EXISTS pg_cron` (L10) in favor of a `pg_extension`-check `DO` block that raises with actionable message if missing. Idempotent `PERFORM cron.unschedule` before `cron.schedule`. Fully qualify the scheduled command as `public.cleanup_expired_demo_sessions()`. Post-schedule assertion `DO` block verifying `cron.job` contains the row.                                       |

### Files NOT edited

- `supabase/migrations/20260904120001_seed_demo_templates.sql` — no changes required by any item in scope.
- `supabase/migrations/20260904120002_cleanup_old_demo_account.sql` — independent of the demo path.
- `supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql` — Feature Input explicitly defers row-by-row / batch-insert refactor (item #5); no other defect touches this file. Cascade-delete semantics (`DELETE FROM demo_sessions WHERE auth_user_id = auth.uid()` relying on `bands.demo_session_id ON DELETE CASCADE`) remain correct for the settled architecture.

### RLS impact

No RLS policy semantics change. The two `demo_sessions` policies are re-created byte-for-byte; only the enclosing `DROP POLICY IF EXISTS` guard is added. No new policy queries the table it protects. No RLS on the new `bands_real` view (view defaults to SECURITY INVOKER; underlying `bands` RLS applies to callers).

### SECURITY DEFINER grant verification (per Architect guardrails)

Functions edited or newly introduced:

- `public.provision_demo_session()` — signature unchanged, grants unchanged (`REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;` at L346-347, preserved verbatim).
- `public.cleanup_expired_demo_sessions()` — signature unchanged, grants unchanged (`REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO postgres;`).

Verification uses `has_function_privilege(role, oid::regprocedure, 'EXECUTE')` per guardrail — never a string-match on ACL arrays. See §Verification Plan.

## Flutter Architecture Changes

None. No new providers, notifiers, repositories, services, models, screens, routes. `provisionAndEnter` gains a ~7-line guard + a typed `PostgrestException` branch in its `catch`. Public signature unchanged. State management unchanged.

## Files to Create

None.

## Files to Modify

| File                                                                                                                                   | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [supabase/migrations/20260904120000_demo_bands_schema.sql](supabase/migrations/20260904120000_demo_bands_schema.sql)                   | Add `DROP POLICY IF EXISTS demo_sessions_select_own ON public.demo_sessions;` before L32 and `DROP POLICY IF EXISTS demo_sessions_update_own ON public.demo_sessions;` before L36. Append a new section 4 with `CREATE OR REPLACE VIEW public.bands_real AS SELECT * FROM public.bands WHERE is_demo_template = false AND is_demo_clone = false;` at the end of the file. No other statements change.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql) | Declarations block (L17-50): add `v_existing_clone_ids UUID[]`, `v_max_concurrent CONSTANT INTEGER := 30`, `v_live_count INTEGER`. Idempotency read (L55): change `INTO v_session_id, v_bs_band_id` to `INTO v_session_id, v_existing_clone_ids`. Early-return block (L61-64): replace the two subselects with `v_existing_clone_ids[1]::text` / `v_existing_clone_ids[2]::text` (or `to_jsonb(...)` if the file already uses `to_jsonb` elsewhere). Insert new ceiling check between the L64 `END IF;` and the L71 `INSERT INTO users` — `SELECT count(*) INTO v_live_count FROM public.demo_sessions WHERE expires_at > now(); IF v_live_count >= v_max_concurrent THEN RAISE EXCEPTION 'demo_capacity_exceeded' USING ERRCODE='P0001', HINT='...';`. Wrap L87-89 `INSERT INTO demo_sessions` in a nested `BEGIN ... EXCEPTION WHEN unique_violation THEN ... RETURN jsonb_build_object(...); END;` that re-reads via `v_existing_clone_ids` and returns the winner's JSON. All other body logic (clone loops L91-337, final `UPDATE demo_sessions SET clone_band_ids`, `RETURN jsonb_build_object`) unchanged. Grants (L346-347) unchanged. |
| [supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql](supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql) | Delete `CREATE EXTENSION IF NOT EXISTS pg_cron;` at L10. Prepend a `DO` block that raises if `pg_extension` doesn't list `pg_cron`, with an actionable HINT about enabling it via the Dashboard Extensions UI. Function definition (L16-24) and grants (L27-28) unchanged. Between the grants and the `cron.schedule` call, insert an idempotent `DO $$ BEGIN PERFORM cron.unschedule('cleanup_demo_sessions'); EXCEPTION WHEN OTHERS THEN NULL; END $$;` block. Change the scheduled command from `$$SELECT cleanup_expired_demo_sessions()$$` to `$$SELECT public.cleanup_expired_demo_sessions()$$` (add `public.` qualifier). Append a post-schedule `DO` block that raises if `NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_demo_sessions')`.                                                                                                                                                                                                                                                                                                                                                                              |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart)                                             | In `provisionAndEnter` (L15-33): before `signInAnonymously()` at L20, insert a guard — read `client.auth.currentSession` and `client.auth.currentUser`, skip `signInAnonymously()` if session is non-null AND user is non-null AND `user.isAnonymous == true`. In the `catch` block (L26-31): split off a `on PostgrestException catch (e)` clause BEFORE the existing generic `catch (e, st)`; if `e.message.contains('demo_capacity_exceeded')`, throw `DemoSessionException("Demo's booked solid — try again in a few minutes.")`; otherwise `throw DemoSessionException('Demo session failed: ${e.message}');`. The generic `catch (e, st)` fallback stays byte-for-byte. Existing `debugPrint` calls preserved. No signature change. No change to `exit` (L35-43) or `heartbeat` (L45-50).                                                                                                                                                                                                                                                                                                                                                |

## Files Off-Limits

| File                                                                         | Why                                                                                                                                                     |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/agents/*.agent.md`                                                  | Pipeline spec — not touchable per Manager instructions.                                                                                                 |
| `lib/features/auth/auth_gate.dart`                                           | Reconciler at L295-311 is already correctly gated (see §Root Cause #2b). Any change here risks the fragile cold-start / global-signout balance.         |
| `lib/features/auth/login_screen.dart`                                        | Renders `DemoSessionException.message` verbatim; no change to the display path.                                                                         |
| `lib/features/auth/auth_state_provider.dart` and other auth files            | Not on the failure path for any item in scope.                                                                                                          |
| `supabase/migrations/20260904120001_seed_demo_templates.sql`                 | Seed data not implicated by any defect in scope.                                                                                                        |
| `supabase/migrations/20260904120002_cleanup_old_demo_account.sql`            | Legacy shared-account cleanup, independent of the current demo path.                                                                                    |
| `supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql` | Cascade-delete via `bands.demo_session_id ON DELETE CASCADE` is correct for the settled architecture; batch-insert refactor is explicitly out of scope. |
| `main.dart`                                                                  | No init-order change. Preserved invariant per Architect guardrails.                                                                                     |
| Any new `.sql` migration file                                                | Fixes are in-place per Feature Input; no forward migrations.                                                                                            |
| `docs/reference/**`                                                          | No architectural decision changed; no runtime config change.                                                                                            |

## Change Budget

Enforced by QA against the actual diff. Numbers are line delta / new symbols.

| File                                                                | Expected net line delta        | Notes                                                                                                                                           |
| ------------------------------------------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`          | +12 to +18                     | 2 `DROP POLICY IF EXISTS` lines + a short section 4 view block (~8-12 lines with header comment).                                               |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql` | +25 to +40                     | 3 new declarations, ceiling check (~10 lines), unique_violation nested block (~10 lines), 2 subselect deletions offset by 2 direct index reads. |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql` | +25 to +40                     | Pre-check DO block (~8 lines), unschedule DO block (~7 lines), post-assertion DO block (~7 lines), minus the removed `CREATE EXTENSION` line.   |
| `lib/features/auth/demo_session_service.dart`                       | +8 to +14                      | ~5-line session guard + ~6-line PostgrestException branch.                                                                                      |
| **Total**                                                           | **+70 to +112** across 4 files |                                                                                                                                                 |

Expected new files: **0**.
Expected new public classes / methods: **0** (Dart) / **0** net-new SQL functions (existing functions edited in place; the new `bands_real` view is a VIEW, not a function).
Expected new dependencies (`pubspec.yaml`): **0**.

If Engineer's diff exceeds the upper bound of any file's budget by more than ~15%, that's a signal the fix has drifted from the plan — QA should flag and Architect re-reviews.

## System Impact Map

| System                   | Affected?                         | Notes                                                                                                                                                                          |
| ------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                     | Unaffected                        | No schema, RLS, or client change to gigs / gig_dates / gig_responses.                                                                                                          |
| Rehearsals               | Unaffected                        | Same.                                                                                                                                                                          |
| Setlists                 | Unaffected                        | Cloned as part of the (unchanged) provision flow; no path change.                                                                                                              |
| Members                  | Affected (positive)               | Fewer orphaned `band_members` rows for demo visitors because #1/#2 eliminate the re-clone loop and #5 gets the cron sweeping again. No change to member RLS or role semantics. |
| Auth                     | Affected (surgical)               | Client-side guard against unconditional `signInAnonymously()`. No change to `auth_gate.dart`, auth state provider, PKCE flow, deep links, or session storage.                  |
| Routing                  | Unaffected                        | No routing/navigation change.                                                                                                                                                  |
| Notifications            | Unaffected                        | Push registration path unchanged.                                                                                                                                              |
| Platforms                | All (iOS / macOS / Android / Web) | Client change is in shared `demo_session_service.dart`; no `Platform.isX` branch. Migrations are DB-only and platform-agnostic.                                                |
| Init order               | Unaffected                        | `main.dart` untouched; Architect init-order invariant preserved.                                                                                                               |
| Config (`--dart-define`) | Unaffected                        | No new env vars.                                                                                                                                                               |

## Regression Risk

**MEDIUM.**

Why medium (not low):

- The `provision_demo_session` RPC body change touches control flow (idempotency read + new ceiling check + unique_violation handler). A logic error there could either leak clones (worse than status quo) or block legitimate provisioning (visible failure).
- The `pg_cron` hardening changes the failure mode from silent (job never registers) to loud (migration re-apply fails with specific error). This is intentional and desirable, but engineers who don't read the pre-check will misdiagnose the migration failure.
- Client guard interacts with `_reconcileOrphanedAnonymousSession` — the analysis above shows they compose correctly, but the failure mode if wrong is subtle (missed sign-out on a genuinely-orphaned session).

Why not high:

- No init-order change. No auth flow change. No RLS policy semantics change. No routing/navigation change. No new DB tables.
- Every change is scoped to the demo path — a real (non-anonymous) user never hits any modified code path.
- The added `bands_real` view is a new read-only artifact; nothing yet reads it, so its presence can't regress anything.

## Engineer Task Breakdown

Execute in this order. Each task is atomic and independently verifiable.

1. **Edit `supabase/migrations/20260904120000_demo_bands_schema.sql`** — add the two `DROP POLICY IF EXISTS` guards before the existing `CREATE POLICY` statements at L32 and L36; append a new section 4 with the `CREATE OR REPLACE VIEW public.bands_real` block. No other lines change.
2. **Edit `supabase/migrations/20260904120003_provision_demo_session_rpc.sql`** — apply five sub-edits in a single pass:
   - Add `v_existing_clone_ids UUID[]`, `v_max_concurrent CONSTANT INTEGER := 30`, `v_live_count INTEGER` to the `DECLARE` block.
   - Change the idempotency-read `SELECT ... INTO v_session_id, v_bs_band_id` to `INTO v_session_id, v_existing_clone_ids`.
   - Replace the two `(SELECT clone_band_ids[N] FROM demo_sessions WHERE id = v_session_id)` subselects with `v_existing_clone_ids[1]::text` / `v_existing_clone_ids[2]::text`.
   - After the idempotency `END IF;`, insert the concurrency ceiling check.
   - Wrap the `INSERT INTO demo_sessions` in a nested block with the `EXCEPTION WHEN unique_violation` handler.
3. **Edit `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql`** — delete the `CREATE EXTENSION IF NOT EXISTS pg_cron` line; add the pg_extension pre-check DO block; add the idempotent `cron.unschedule` DO block; fully qualify the scheduled command as `public.cleanup_expired_demo_sessions()`; add the post-schedule assertion DO block.
4. **Edit `lib/features/auth/demo_session_service.dart`** — add the live-anon-session guard around `signInAnonymously()`; split the `catch` into a `PostgrestException` branch that maps `demo_capacity_exceeded` to the roadie-voice message + a fallthrough generic catch.
5. **Run local verification** — `flutter analyze` clean; `flutter test test/features/auth/` clean. If a `demo_session_service_test.dart` group exists (or one of `login_screen_demo_button_test.dart` / `auth_gate_anonymous_recovery_test.dart` is a natural home), add a single test case for the live-anon reuse guard — otherwise document manual verification steps in the ENGINEER_REPORT instead of creating a new test file for one guard.

Do NOT execute steps 6+ (SQL apply against prod). Those are owner-only steps in §Verification Plan Tier 2.

## Verification Plan

Since migrations are applied by the owner via direct SQL (no CI, no pipeline apply), Tier 1 (pre-apply) and Tier 2 (post-apply) both consist of owner-run steps. Client verification is standard `flutter analyze` + `flutter test`.

### Tier 1 — pre-apply (owner runs against a scratch DB, NOT prod)

Preconditions: a Supabase branch DB or `supabase db reset` local dev DB with all migrations from `main` applied but none of `20260904120000`-`20260904120005`. Then apply each corrected file in order.

1. **`20260904120000` re-apply from clean** — expect success. `SELECT policyname FROM pg_policies WHERE tablename = 'demo_sessions';` returns both `demo_sessions_select_own` and `demo_sessions_update_own`. `SELECT COUNT(*) FROM pg_views WHERE viewname = 'bands_real';` returns 1.
2. **`20260904120000` re-apply against already-applied state** — expect success (no "policy already exists" error). `SELECT policyname FROM pg_policies WHERE tablename = 'demo_sessions';` returns the same two policies with unchanged predicates.
3. **`20260904120003` re-apply** — expect success. `\df+ public.provision_demo_session` shows the updated function body.
4. **`20260904120005` re-apply against a DB WITHOUT pg_cron enabled** — expect failure with the actionable pre-check message (proves the pre-check works). Then enable the extension via Dashboard / dedicated `CREATE EXTENSION` transaction, re-apply — expect success.

### Tier 2 — post-apply (owner runs against prod after applying edited files)

1. **#5 pg_cron registration** — `SELECT jobname, schedule, command, active FROM cron.job WHERE jobname = 'cleanup_demo_sessions';` must return exactly one row: schedule = `*/5 * * * *`, command = `SELECT public.cleanup_expired_demo_sessions()`, active = `true`. If zero rows, the file's post-assertion DO block already failed the apply — so seeing rows == 0 here means the migration was applied incompletely.
2. **#1 idempotency read** — from an anonymous session (owner can mint one via the Supabase Auth REST endpoint using the anon key), call `SELECT public.provision_demo_session();` twice. First returns freshly-cloned band IDs; second returns identical band IDs with no error. If the second call errors, #1 fix is broken.
3. **#4 unique_violation guard** — from two concurrent psql sessions, both authenticated as the same anon `auth.uid()` (owner can `SET request.jwt.claims` locally to spoof), call `provision_demo_session()` simultaneously. Neither should raise `duplicate key value violates unique constraint`; both should return the same JSON payload. Cleanup: `DELETE FROM public.demo_sessions WHERE auth_user_id = '<test uuid>';` (cascade cleans up the clone bands).
4. **#3 ceiling** — temporarily flip `v_max_concurrent` to 1 in the migration file, re-apply, then attempt a fresh anon provision while an existing session is live: expect `demo_capacity_exceeded`. Restore the constant to 30 and re-apply. Roll back the test session with `DELETE FROM public.demo_sessions WHERE auth_user_id = '<test uuid>';`.
5. **`bands_real` view** — `SELECT COUNT(*) FROM public.bands;` and `SELECT COUNT(*) FROM public.bands_real;` — the latter should be strictly less than the former by exactly the count of rows where `is_demo_template = true OR is_demo_clone = true`. Verify: `SELECT COUNT(*) FROM public.bands WHERE is_demo_template = true OR is_demo_clone = true;` equals the difference.
6. **SECURITY DEFINER grants unchanged** — for `provision_demo_session`:
   - `SELECT has_function_privilege('authenticated', 'public.provision_demo_session()'::regprocedure, 'EXECUTE');` → `true`
   - `SELECT has_function_privilege('anon', 'public.provision_demo_session()'::regprocedure, 'EXECUTE');` → `false`

   For `cleanup_expired_demo_sessions`:
   - `SELECT has_function_privilege('postgres', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` → `true`
   - `SELECT has_function_privilege('authenticated', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` → `false`
   - `SELECT has_function_privilege('anon', 'public.cleanup_expired_demo_sessions()'::regprocedure, 'EXECUTE');` → `false`

   These use `has_function_privilege(role, oid::regprocedure, 'EXECUTE')` per the Architect grant-verification guardrail; a PUBLIC grant would satisfy all three roles, so `authenticated = true` + `anon = false` on `provision_demo_session` proves no PUBLIC grant is present.

7. **Post-apply cleanup (one-shot manual sweep)** — owner runs `SELECT public.cleanup_expired_demo_sessions();` once immediately after the migration re-apply to drain the 8 currently-stale sessions (the cron will start sweeping on the next scheduled tick, but a one-shot manual call gets the state clean immediately). Verify: `SELECT COUNT(*) FROM public.demo_sessions WHERE expires_at < now();` → 0.

### Client verification

- `flutter analyze` — clean, no new warnings introduced by `demo_session_service.dart`.
- `flutter test test/features/auth/` — existing suite (`auth_gate_anonymous_recovery_test.dart`, `login_screen_demo_button_test.dart`) passes; if a new test case is added per Engineer Task 5, it goes into whichever file naturally holds it (do NOT create a new test file solely for the guard — the task budget is one case, not a file).
- Manual: on a physical device or simulator, launch app, tap Demo, exit, tap Demo again within the 30-min window — verify no fresh clones in `public.bands` (owner checks `SELECT COUNT(*) FROM bands WHERE is_demo_clone = true AND created_by = '<test anon uuid>';`), and the second entry re-enters the same demo bands.

## QA Regression Areas

- Real (non-anonymous) user sign-in / sign-up flows — verify unchanged (client change is scoped to demo path).
- Existing anon session cold-restart with valid memberships — verify AuthGate still routes to demo shell without hitting the login screen.
- Existing anon session cold-restart with zero memberships — verify `_reconcileOrphanedAnonymousSession` still fires and does the global sign-out.
- `exit_demo_session` cascade cleanup — verify unchanged (this file is off-limits).
- Non-demo band CRUD by real users — verify `bands_real` view presence doesn't affect any existing query (nothing reads it yet; grep confirmed).
- Push notification token registration — verify unaffected (auth flow not altered).
- iPad multitasking / lifecycle handling — verify unaffected (no changes to `didChangeAppLifecycleState`).

## Rollout Strategy

- Owner applies the four edited files in timestamp order via direct SQL against prod: `20260904120000` → `20260904120003` → `20260904120005`. (`20260904120001` / `20260904120002` / `20260904120004` are NOT re-applied; nothing changed.)
- After each apply, owner runs the corresponding Tier-2 verification step for that file. If any step fails, the fix is diagnosed inline (each fail-loud DO block includes a specific message identifying the missing invariant).
- Client change ships in the same PR / build as the migration edits. The client guard is a strict superset of the pre-guard behavior (fresh mint still happens when there's no live anon session), so a client build without the RPC fix applied would still work — just less idempotently. This ordering is defensive: even if the owner staggers apply + build, no user-facing regression is introduced by either half deployed alone.
- One-shot manual `SELECT public.cleanup_expired_demo_sessions();` immediately after migration apply drains the current 8 stale sessions without waiting for the cron's next tick.
- Rollback: if any migration edit produces unexpected prod behavior, owner can restore the pre-edit content of that specific file from git (`git show HEAD:supabase/migrations/<file>`) and re-apply. `bands_real` is a `CREATE OR REPLACE VIEW`, safely droppable via `DROP VIEW IF EXISTS public.bands_real;`. The policy guards, ceiling check, and unique_violation handler are all additive — reverting them restores prior behavior exactly.

## Out of Scope

- Batch-insert refactor of the row-by-row clone loops in `20260904120003` (Feature Input #5, explicitly deferred).
- Migration of the `v_max_concurrent` knob to an `app_config` table — deferred until a second demo-related knob appears; premature abstraction now would exceed the "smallest change" bar.
- Changes to `20260904120001` (seed) or `20260904120004` (exit / heartbeat) — no defect in scope touches them.
- Any change to `auth_gate.dart` — the reconciler's global-signout gate is already correct (see §Root Cause #2b).
- Any redesign of the clone-per-visitor model — explicitly rejected by owner; this plan preserves it verbatim.
- Marketing-page / landing-page changes to route users to the demo differently — not implicated by any defect.
- New `--dart-define` values — none required.
- Adding tests for the concurrency ceiling — SQL-only verification per §Verification Plan Tier 2 is sufficient; a Dart/Flutter test for a Postgres RPC would require a live DB harness that this repo doesn't have.
