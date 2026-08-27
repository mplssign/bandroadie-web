# Feature Slug

bug/membership-status-and-archive-rls-hygiene

# Problem Summary

Three low-severity backend-only hardening gaps are confirmed against production and are intentionally bundled because they are distinct but share the same release window, are low-risk, and require no client-side changes:

1. `public.is_band_member(p_band_id uuid)` does not require `band_members.status = 'active'` on the matching membership row. This helper gates 26 RLS policies across membership, band, calendar, setlist, gig, rehearsal, and song access.
2. `public.setlist_special_items` enforces its four access policies with inline `EXISTS` checks that also omit the active-status filter, duplicating the same bug outside the helper.
3. `archive.bands` and `archive.band_members` have RLS disabled. This is a hygiene issue rather than a current exposure because no client role currently has grants on the `archive` schema, but the schema should still enforce RLS.

The root issue is not a product-level outage; it is a latent security hardening gap that should be neutral for current data because production membership rows are active-only today.

# Root Cause

Confirmed root cause: the database membership helper and the duplicated inline checks use an existence test on `band_members` without constraining the row to `status = 'active'`. That is inconsistent with the patterns already used by admin checks such as `band_members_update_admins`, which explicitly require `band_members.status = 'active'::text`.

The `archive.*` issue is also confirmed by live schema metadata: both tables currently have `relrowsecurity = false` and `relforcerowsecurity = false`, and the `archive` schema has no `anon`/`authenticated` grants. This is a schema hygiene violation, not an active privilege exposure under current grants.

Root cause confidence: HIGH.

# Reference Docs Consulted

- `docs/reference/notifications/`: not present in this repository; not applicable to this database-only RLS hardening fix.
- Relevant schema and migration evidence reviewed directly in repo:
  - `supabase/migrations/20260823120000_wrap_rls_auth_functions.sql`
  - `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`
  - `supabase/migrations/20260825221507_fix_songs_band_scoping_and_anon_grants.sql`

# Existing System Analysis

The current production access pattern shows the problem clearly:

- `is_band_member(p_band_id)` checks only `band_id = p_band_id AND user_id = auth.uid()`.
- `setlist_special_items` policies use the same logic inline, without checking `status`.
- The `band_members` schema itself has a CHECK constraint allowing `invited`, `active`, `inactive`, and `removed` values, and existing admin checks consistently require `status = 'active'::text`.
- The invite-accept code path writes `status = 'active'` on successful acceptance; removal is still hard-delete-only by product decision. That means the current live data in production is all active and this change is defense-in-depth rather than a business-impacting correction.

The direct evidence from the migration history confirms the intended pattern. In the RLS hardening migration, membership checks for admin rights consistently use:

```sql
band_members.user_id = (select auth.uid())
AND band_members.status = 'active'::text
```

This helper omission is therefore not a data-model mismatch; it is a missing status guard in the shared membership predicate and the duplicate policy checks that were not centralized.

For the `archive` schema, the live schema state confirms the problem is a policy hygiene issue, not an immediate bypass pathway:

- `relrowsecurity = false`
- `relforcerowsecurity = false`
- zero `USAGE` on `archive` schema for `anon` and `authenticated`
- zero table grants on `archive.bands` / `archive.band_members` for client roles

No additional application behavior is required beyond enabling RLS and re-confirming there are no client-side grants that would suddenly become active after the migration.

# Proposed Solution

The minimal safe fix is to patch only the database-layer membership predicates and archive RLS state:

1. Update `public.is_band_member(p_band_id uuid)` to require the matching row to be active:

```sql
SELECT EXISTS (
  SELECT 1
  FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active'::text
);
```

2. Update the four `public.setlist_special_items` policies to add the same status predicate in their `EXISTS` subqueries, matching the same `status = 'active'::text` guard used elsewhere, rather than allowing any membership row.

3. Enable RLS on `archive.bands` and `archive.band_members` and confirm grants remain absent for `anon` and `authenticated` before finalizing the migration. No new policy objects are required because no client role should have any access to this schema under the current grant model.

This remains intentionally narrow and does not expand the attack surface, change auth flows, or modify any application code.

# Database Impact

Database: affected.

- Migration required: yes.
- Existing migration modification: no. Create a new timestamped migration under `supabase/migrations/` in the standard naming convention.
- No source-code changes required.
- No edge function deploy required.
- No RPC signature change is required.
- No new dependencies are required.

Required migration content:

- Add the exact pre-migration `is_band_member()` definition in the migration header comment for rollback reference, as required by the feature input.
- Replace the helper body with the `status = 'active'::text` guard.
- Replace the inline `setlist_special_items` policy predicates to add the same active-status filter.
- Enable row-level security on `archive.bands` and `archive.band_members` with `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`.
- Re-check `information_schema.role_table_grants` and `has_table_privilege` for `anon`/`authenticated` to confirm no additional policy creation is needed. If the assumption fails at implementation time, the migration must add the corresponding policy set to preserve the no-access posture, but no policy should be created if the current grants remain empty.

Affected / unaffected status by database area:

- `public.band_members`: affected (status predicate logic)
- `public.setlist_special_items`: affected (four policy checks)
- `public.is_band_member()`: affected
- `archive.bands`: affected (enable RLS)
- `archive.band_members`: affected (enable RLS)
- `public.*` tables depending on `is_band_member()`: indirectly affected by stricter membership predicate, but no behavior change for active-only data

# Flutter Architecture Changes

Not applicable.

This is a database-only fix. No widget, provider, repository, controller, or other Flutter code should be changed. No app release changes are expected beyond migration deployment.

# Files to Create

- `supabase/migrations/20260826000000_fix_membership_status_and_archive_rls_hygiene.sql`
  - Justification: required by repository migration convention and the feature input; this single migration encapsulates the helper change, the `setlist_special_items` policy change, and archive RLS enablement.

# Files to Modify

- None in existing source files.
- The required work is a new migration only; no existing SQL migration should be edited, per repo convention and the feature input.

# Files Off-Limits

| File                                                     | Reason                                                                                                          |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `lib/**`                                                 | No Flutter code change is required for a backend-only DB hardening fix.                                         |
| `supabase/functions/**`                                  | No edge function logic is implicated by the confirmed root cause.                                               |
| `lib/main.dart`                                          | Initialization order and app bootstrap are not touched.                                                         |
| `docs/agents/**`                                         | This plan is the only approved design artifact; no policy or operational doc changes are necessary for the fix. |
| `supabase/migrations/*.sql` other than the new migration | Existing migrations must not be edited; the repo requires a new timestamped migration for this fix.             |

# System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | affected   |
| Rehearsals                             | affected   |
| Setlists / Catalog                     | affected   |
| Members / RBAC                         | affected   |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected |

Notes:

- The affected systems are the ones that rely on `is_band_member()` or the duplicated `setlist_special_items` membership checks.
- In production, the change is effectively a no-op because all current membership rows are active, but the stricter predicate is still required for future hygiene and defense-in-depth.

# Regression Risk

LOW.

Reasoning:

- No client code changes or app lifecycle changes.
- Production membership data is active-only today; this should be behaviorally neutral.
- The `archive` schema currently has no client grants, so enabling RLS should not alter access for any current role.
- The only cross-cutting risk is the strict membership gate on tables that depend on `is_band_member()`, which is exactly the intended behavior and should be validated against same-transaction invite acceptance.

# Engineer Task Breakdown

1. Re-query live production status distribution before any migration.
   - Confirm all `public.band_members.status` rows are `'active'`.
   - Record row counts and verify no rows are `'inactive'`, `'invited'`, or `'removed'`.
2. Trace the invite-accept path end-to-end.
   - Inspect `accept_band_invite_rpc` and any variant/repair RPCs that write `status = 'active'`.
   - Confirm the newly inserted row is visible to the same transaction that reads it back, especially after the membership helper becomes stricter.
3. Create the new timestamped migration file with the exact rollback comment header and the pre-migration helper definition in the header.
4. Update `public.is_band_member()` and the four `setlist_special_items` policy predicates to require `status = 'active'::text`.
5. Enable RLS on `archive.bands` and `archive.band_members` and re-check schema grants before finalizing the migration.
6. Run the post-deploy verification queries and confirm row counts remain unchanged.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before `supabase db push`)

These tests must use existing tables and objects with no schema changes applied yet. They validate the current state and the assumptions used to implement the migration.

```sql
-- PRE-DEPLOY TEST 1:
SELECT status, COUNT(*) AS row_count
FROM public.band_members
GROUP BY status
ORDER BY status;
```

Expected: all rows are `active` and total row count is stable.

```sql
-- PRE-DEPLOY TEST 2:
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity,
  c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'archive'
  AND c.relname IN ('bands', 'band_members');
```

Expected: `relrowsecurity = false` and `relforcerowsecurity = false` on both archive tables, confirming current state before enabling RLS.

```sql
-- PRE-DEPLOY TEST 3:
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'archive'
  AND table_name IN ('bands', 'band_members');
```

Expected: zero rows for `anon` / `authenticated` client roles. No new policies should be required unless this assumption fails during implementation.

## Tier 2 — Post-deployment (run after `supabase db push` succeeds)

These tests exercise the modified function and policy state after the migration has been applied.

```sql
-- POST-DEPLOY TEST 1:
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure) AS function_def;
```

Expected: the definition contains `AND status = 'active'::text` and does not contain the old unfiltered body.

```sql
-- POST-DEPLOY TEST 2:
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity,
  c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'archive'
  AND c.relname IN ('bands', 'band_members');
```

Expected: `relrowsecurity = true` for both tables after the migration.

```sql
-- POST-DEPLOY TEST 3:
SELECT COUNT(*) AS total_members,
       COUNT(*) FILTER (WHERE status = 'active') AS active_members,
       COUNT(*) FILTER (WHERE status <> 'active') AS non_active_members
FROM public.band_members;
```

Expected: row counts remain unchanged from the pre-deployment baseline; the only intended change is stricter membership checks, not data mutation.

```sql
-- POST-DEPLOY TEST 4:
SELECT
  table_schema,
  table_name,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'archive'
  AND table_name IN ('bands', 'band_members');
```

Expected: no `anon` / `authenticated` grants if the live schema still has no client access. If a grant exists, it must be understood and documented before the migration is considered complete.

Additional required verification step (explicit engineer check):

- Trace the `accept_band_invite_rpc` path and its repair variants, then verify the same transaction can read the newly inserted row with `status = 'active'` under the updated helper predicate. This is a required sanity check because the change affects 26 policies and must not silently break the invite acceptance path.

# QA Regression Areas

Because this is a backend database hardening fix, QA should focus on membership and access policy correctness rather than a client feature flow:

- Invite acceptance path: confirm a newly accepted invite inserts `status = 'active'` and remains visible to the same transaction that reads it back.
- Membership gating: confirm inactive or removed members are not treated as active members by `is_band_member()`.
- `setlist_special_items` access control: verify only active band members can create, read, update, or delete special items.
- Archive schema hygiene: verify `archive.bands` and `archive.band_members` reject client access without named grants while the schema remains protected by RLS.
- Data integrity: confirm row counts and status distribution are unchanged before and after migration for the current production state.

# Rollout / Migration Strategy

- Create one new migration file only.
- Run the migration through the repo's usual Supabase migration flow (`supabase db push` / standard migration deploy path).
- No app version bump is required because this is a server-side hardening change.
- No feature flag or client rollout is necessary.
- The migration must be reviewed as a single logical patch: helper fix + duplicate policy fix + archive RLS enablement.

# Out of Scope

- `origin/bug/supabase-security-hardening` is being merged separately and must not be reconciled here.
- Moving `pg_net` out of the `public` schema is explicitly deferred.
- The `net.*` schema execute-revoke work remains blocked by the separate Supabase support ticket and is tracked outside this fix.
- No changes to app behavior, notification flows, or UI are part of this fix.
- No cleanup or refactoring beyond the minimal required migration code.
