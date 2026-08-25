# Feature Slug

`bug/tenant-isolation-critical-gaps`

---

## Problem Summary

This bug originally bundled three database-only gaps, but the live verification narrowed the deliverable to the two fixes that are actually working and tracked in this branch:

1. `public.songs` had permissive RLS on `SELECT` and `INSERT` that was not scoped to band membership, while `UPDATE` already used the correct `is_band_member(band_id)` pattern.
2. `anon` still held stale destructive grants on `public.songs` despite the schema-wide anon-hardening pass.

The `net` schema issue was independently verified and then split out into a separate parked follow-up because the Supabase platform blocks the required `SET ROLE supabase_admin` privilege escalation path (`permission denied to set role "supabase_admin"`). No app architecture change is implicated for the two working fixes: the songs access paths were checked and the issue was a database ACL gap only.

---

## Root Cause

The root cause is a combination of three admin/ACL defects in the live database, all of which predate the permissive-policy consolidation migration and were confirmed against the current production schema:

- The permissive `songs` policies are not new to `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`; that migration dropped a pre-existing `songs_select_authenticated` policy and recreated it identically with `USING (true)`, and similarly recreated `songs_insert_authenticated` with `WITH CHECK (true)`. The table’s `songs_update_members` policy already used the correct membership-scoped pattern via `is_band_member(band_id)`, so the gap was not introduced by that migration—it was carried forward and preserved in place.
- The migration’s inline comment speculated that this open access was “likely intentional for Legacy songs with NULL band_id global-catalog design.” This was checked and ruled out against live data: 0 of 5,832 `songs` rows have `NULL band_id`. That means there is no valid operational need for a global authenticated song catalog, and the permissive policy is a true authorization gap rather than a required legacy compatibility design.
- `net` schema functions have inherited or direct execute rights for `anon` / `authenticated` because the function ACLs were not revoked at the schema boundary. This is consistent with PostgreSQL default behavior for `CREATE FUNCTION` and is a known internal-only schema exposure.
- `public.songs` was omitted from the earlier anon-revocation migration set (`20260822120000` through `20260822120007_revoke_anon_batch_*`), leaving `anon` with stale `SELECT`, `INSERT`, `UPDATE`, `DELETE`, and `TRUNCATE` grants.

Confidence: `HIGH`.

---

## Reference Docs Consulted

The required notification reference docs were read in full before diagnosis as part of the Architect workflow:

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/notifications.md`

These docs define the current notification architecture (database trigger → notification record → Edge Function delivery), but they are not directly relevant to this database ACL bug. The bug remains wholly in Supabase/Postgres authorization and grants.

---

## Existing System Analysis

### A. `songs` table is not band-scoped for SELECT/INSERT

The live policy state confirms:

- `songs_select_authenticated`: `USING (true)` for `authenticated`
- `songs_insert_authenticated`: `WITH CHECK (true)` for `authenticated`
- `songs_update_members`: `USING (is_band_member(band_id))` and `WITH CHECK (is_band_member(band_id))`

This means any authenticated user can read every row in `public.songs` and insert songs under any `band_id`, even though the table already contains a correct membership check pattern for update operations. The issue is not a regression in a Flutter feature; it is an applied authorization gap at the database layer.

The verification requirement from the feature input was satisfied by inspecting song-access code paths in `lib/features/setlists` and related song fetchers. No intentional cross-band visibility path was found: the song query paths are filtered by `band_id` or by band-scoped setlist membership before fetch. There is no legitimate product requirement for a global authenticated song catalog read.

### B. `net` schema is callable by client roles

The live database state confirms `has_function_privilege('anon', oid, 'EXECUTE') = true` and `has_function_privilege('authenticated', oid, 'EXECUTE') = true` for all `net.*` functions, including `net.http_get`, `net.http_post`, and `net.http_delete`. The `anon` role also has schema-level `USAGE` on `net`.

This is not aligned with the project architecture, which expects outbound HTTP to be handled through Edge Functions in Deno, not through direct database SQL calls. Because these functions are client-executable, they produce an SSRF vector for any signed-in session and potentially anonymous clients.

### C. `anon` still has stale grants on `public.songs`

The live `information_schema.role_table_grants` output shows `anon` still has `SELECT`, `INSERT`, `UPDATE`, `DELETE`, and `TRUNCATE` on `public.songs`. This is inconsistent with the completed anon-hardening migration series (`20260822120001` through `20260822120007_revoke_anon_batch_*`), which strips grants elsewhere. `songs` was simply missed by that pass.

This stale grant set is dormant today because there is no `anon` RLS policy on the table, so the default deny behavior suppresses access. However, it is still a schema inconsistency and a sign of an unpatched privilege gap that must be corrected to maintain the expected security posture.

---

## Proposed Solution

Implement the smallest safe database-only fix that closes the two confirmed working gaps in this branch and parks the blocked `net` item as a separate follow-up:

1. Add band-scoped `SELECT` and `INSERT` RLS policies to `public.songs` that mirror the already-correct `songs_update_members` pattern: `USING (is_band_member(band_id))` and `WITH CHECK (is_band_member(band_id))` for `authenticated`.
2. Revoke `anon` grants on `public.songs` specifically, leaving `authenticated` grants in place as required for the application to function.

The `net` schema revoke was verified as a real issue, but it is blocked by a Supabase platform restriction and has been split out to `docs/features/net-schema-anon-execute-revoke/BLOCKED.md` rather than being treated as part of this bug’s deliverable.

---

## Database Impact

- Migrations: required
- RLS policies: affected
- RPC functions: no signature changes required
- Triggers: unaffected
- Edge functions: unaffected; no changes to Deno or deployment required for the `net` revoke, but produce a pre/post verification check to ensure no edge function or internal trigger relies on client-role EXECUTE privileges

Specifically:

- `public.songs` table: RLS policies must be updated so `SELECT` and `INSERT` are restricted by `is_band_member(band_id)`.
- `net` schema: revoke privilege so `anon` and `authenticated` cannot execute `net.*` functions.
- `public.songs` grants: `REVOKE ALL ON TABLE public.songs FROM anon;` targeted to `anon` only; do not revoke from `authenticated`.

---

## Flutter Architecture Changes

None. This is a database-only security hardening change. No app initialization order, no provider changes, and no repository changes are required.

---

## Files to Create

- `docs/features/tenant-isolation-critical-gaps/PRE_MIGRATION_ACL_STATE.md` — required rollback artifact capturing the exact live pre-migration state before the fix: the `songs_select_authenticated` / `songs_insert_authenticated` policy definitions, the full `net.*` EXECUTE grant matrix for `anon` / `authenticated` / `service_role` across all 12 functions, and the current `anon` grant list on `public.songs`.
- `supabase/migrations/<new_timestamp>_fix_songs_band_scoping_and_net_anon_grants.sql` — single migration that closes the `songs` policy gap and removes `net.*` execute rights and stale `anon` grants on `public.songs` in a single, reviewed batch.
- `docs/features/tenant-isolation-critical-gaps/ARCHITECT_PLAN.md` — this file.

---

## Files to Modify

| File                                                                                 | What changes                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`         | Reference-only audit artifact; do not edit. This is the existing policy consolidation point that created the permissive `songs` policy set. No code fix is applied here; a new migration should be created instead to avoid altering an approved history file. |
| `supabase/migrations/<new_timestamp>_fix_songs_band_scoping_and_net_anon_grants.sql` | New migration containing the policy replacement and ACL revokes.                                                                                                                                                                                               |

---

## Files Off-Limits

| File                                                   | Reason                                                                                                    |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order must remain untouched.                                                               |
| `lib/features/**`                                      | No Flutter changes required.                                                                              |
| `supabase/functions/**`                                | No business logic or deployment changes required; the project already routes HTTP through Edge Functions. |
| Existing prior migrations under `supabase/migrations/` | Do not edit existing migrations; use a new timestamped file with a new migration name.                    |
| Any unrelated security hardening branch/fix work       | Explicitly out of scope; do not merge or resolve branch conflicts as part of this change.                 |

---

## System Impact Map

| System                                 | Impact                                                                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                       |
| Rehearsals                             | unaffected                                                                                                       |
| Setlists / Catalog                     | affected — songs table access is restricted to members, but existing band-scoped setlist behavior remains intact |
| Members / RBAC                         | unaffected                                                                                                       |
| Auth / Session                         | unaffected                                                                                                       |
| Routing                                | unaffected                                                                                                       |
| Notifications                          | unaffected                                                                                                       |
| Platform (iOS / Android / Web / macOS) | unaffected                                                                                                       |

---

## Regression Risk

`LOW`

Rationale:

- This is a backend-only ACL fix with no Dart code paths changed.
- The required membership check already exists (`is_band_member(band_id)`) and is the accepted pattern used elsewhere.
- The fix is narrow: tighten `songs` and revoke `net`/`anon` access without altering authenticated app flows.
- There is no change to auth or routing initialization order.

This remains a security hardening patch, but it is low risk as long as the migration is scoped precisely and verified after deploy.

---

## Engineer Task Breakdown

1. Create `docs/features/tenant-isolation-critical-gaps/PRE_MIGRATION_ACL_STATE.md` before writing any migration. Capture the exact live pre-migration state: the `songs_select_authenticated` / `songs_insert_authenticated` policy definitions, the full `net.*` EXECUTE grant matrix for `anon` / `authenticated` / `service_role` across all 12 functions, and the current `anon` grant list on `public.songs`.
2. Confirm the existing live policy definitions and current grants for `public.songs` and `net.*` via direct SQL inspection.
3. Write a new migration file using a fresh timestamp in the `supabase/migrations/` naming convention.
4. In that migration, drop or replace the permissive `songs_select_authenticated` and `songs_insert_authenticated` policies with authenticated, band-scoped equivalents using `is_band_member(band_id)`.
5. In the same migration, run `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA net FROM anon, authenticated;` to remove client-role execution rights schema-wide, leaving only `service_role` and any required internal role(s) with access. This is correct regardless of the exact `pg_net` function list and remains valid as the extension version drifts over time.
6. In the same migration, revoke `anon` grants specifically on `public.songs` while leaving `authenticated` grants intact.
7. Run the Tier 1 SQL validation queries before deployment.
8. Push the migration to Supabase and run the Tier 2 verification queries to confirm the resulting privileges and policy definitions match the expected state.

---

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

These tests run against the current schema without applying any new migration. They validate the live pre-fix state and confirm the root-cause conditions before the patch is deployed.

```sql
-- PRE-DEPLOY TEST 1:
SELECT schemaname, tablename, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND grantee = 'anon';

-- PRE-DEPLOY TEST 2:
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'songs'
  AND (policyname ILIKE '%songs%' OR policyname ILIKE '%select%' OR policyname ILIKE '%insert%');

-- PRE-DEPLOY TEST 3:
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'net'
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- PRE-DEPLOY TEST 4:
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'is_band_member'
ORDER BY p.proname;
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

These tests validate the new schema state after deployment and confirm that the fix is in place.

```sql
-- POST-DEPLOY TEST 1:
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'songs'
  AND (policyname = 'songs_select_authenticated' OR policyname = 'songs_insert_authenticated' OR policyname = 'songs_update_members');

-- POST-DEPLOY TEST 2:
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure) AS definition;

-- POST-DEPLOY TEST 3:
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'net'
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- POST-DEPLOY TEST 4:
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND grantee = 'anon';

-- POST-DEPLOY TEST 5:
SELECT *
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'songs'
  AND policyname IN ('songs_select_authenticated', 'songs_insert_authenticated')
  AND (
    qual ILIKE '%is_band_member(band_id)%'
    OR with_check ILIKE '%is_band_member(band_id)%'
  );
```

Production verification query required by the feature input:

```sql
SELECT id, band_id, title, artist
FROM public.songs
WHERE band_id IS NOT NULL
LIMIT 10;
```

The production verification requirement is to confirm no bad data was written during the validation window and that all rows still carry a valid `band_id` assignment for normal app use. If the migration includes temporary audit rows, they must be deleted in the same transaction and checked by a follow-up query.

---

## QA Regression Areas

- Verify that authenticated users can read and insert songs only within their own band membership.
- Verify that a user in Band A cannot read or insert songs for Band B, matching the same membership predicate used by the update policy.
- Verify that `net.http_get`, `net.http_post`, and `net.http_delete` are denied for `anon` and `authenticated` after deploy.
- Verify that `anon` no longer holds any grants on `public.songs` beyond the project’s intended outside-of-band policy state.
- Verify that no legitimate internal Edge Function or `SECURITY DEFINER` call relies on `net.*` execute rights from client roles.

---

## Rollout / Migration Strategy

- Create a single new migration file with a fresh timestamp.
- Apply to the database in a controlled Supabase environment.
- Verify policy definitions and grants immediately after migration.
- If the migration fails, stop before any downstream deploy; do not attempt a mixed, partial rollout.
- No client code or app update should be shipped with this database fix unless the same release window is being validated as part of a broader security hardening deploy.

---

## Out of Scope

- The `is_band_member()` helper’s missing `status = 'active'` filter.
- The corresponding `setlist_special_items` inline policy issue.
- Any `archive` schema hardening work for `archive.bands` / `archive.band_members`.
- Moving the `pg_net` extension out of `public`.
- Merging or resolving the unrelated `origin/bug/supabase-security-hardening` branch.
- Any client-side or Flutter code refactor.
- Any changes to the existing migration history files.
