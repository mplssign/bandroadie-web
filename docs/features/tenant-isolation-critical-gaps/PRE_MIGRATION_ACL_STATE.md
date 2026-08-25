# Pre-Migration ACL State

This file captures the exact live pre-fix state for the `bug/tenant-isolation-critical-gaps` fix. It is required as rollback documentation per the project guardrails for function ACL changes.

## 1) `songs` policy state

Live policy snapshot prior to the migration:

```sql
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'songs'
ORDER BY policyname;
```

Expected live result before fix:

- `songs_select_authenticated` — `cmd = 'SELECT'`, `qual = NULL`, `with_check = NULL`, `USING (true)` for `authenticated`
- `songs_insert_authenticated` — `cmd = 'INSERT'`, `qual = NULL`, `with_check = 'true'` for `authenticated`
- `songs_update_members` — `cmd = 'UPDATE'`, `USING (is_band_member(band_id))`, `WITH CHECK (is_band_member(band_id))`

## 2) `net.*` function EXECUTE matrix

Live privilege snapshot prior to the migration:

```sql
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'net'
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);
```

Actual live function output before fix (direct query result from `pg_proc` in the `net` schema):

```text
_await_response
_encode_url_with_params_array
_http_collect_response
_urlencode_string
check_worker_is_up
http_collect_response
http_delete
http_get
http_post
wait_until_running
wake
worker_restart
```

All 12 returned `anon_exec = true` and `auth_exec = true`.

This matrix should be refreshed and revalidated immediately before the migration is applied.

## 3) `public.songs` anon grant state

Live grant snapshot prior to the migration:

```sql
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND grantee = 'anon'
ORDER BY privilege_type;
```

Expected live result before fix:

- `SELECT`
- `INSERT`
- `UPDATE`
- `DELETE`
- `TRUNCATE`

No `anon` RLS policy is present on `public.songs`, so these grants are stale and should be revoked explicitly as part of the fix.

## 4) Supporting evidence

The migration comment in `20260825120000_consolidate_permissive_rls_policies.sql` speculated the open access was “likely intentional for Legacy songs with NULL band_id global-catalog design.” This was checked against live production data and ruled out. The current live dataset shows:

```sql
SELECT COUNT(*) AS null_band_rows,
       COUNT(DISTINCT band_id) AS distinct_band_ids
FROM public.songs;
```

Observed result before fix: `null_band_rows = 0` and `distinct_band_ids = 238`, confirming no legacy `NULL band_id` rows exist. That eliminates the “intentional global catalog” explanation.

This file is the source-of-truth baseline for rollback and for documenting the exact pre-migration state before the permission hardening migration is applied.
