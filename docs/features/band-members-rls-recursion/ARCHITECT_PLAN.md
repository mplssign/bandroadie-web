# Architect Plan — Band Members RLS Recursion During Restore

## 1) Feature Slug

`bug/band-members-rls-recursion`

## 2) Problem Summary

Restoring band data from Edit Band → Restore Band Data fails with PostgreSQL error 42P17: `infinite recursion detected in policy for relation 'band_members'`. The restore flow is supposed to replace the band's existing data with a backup, but it aborts immediately when the `band_members` upsert path reaches the UPDATE branch.

The failure is server-side, so it affects every platform that can invoke the restore flow.

## 3) Root Cause

**Confidence: HIGH**

The live `band_members_update_admins` RLS policy queries `band_members` directly inside its own `USING` and `WITH CHECK` clauses:

```sql
EXISTS (
  SELECT 1
  FROM band_members admin_check
  WHERE admin_check.band_id = band_members.band_id
    AND admin_check.user_id = auth.uid()
    AND admin_check.role = 'admin'
    AND admin_check.status = 'active'
)
```

That is the exact self-referential anti-pattern that triggers 42P17. The restore flow in `lib/features/settings/data_backup_service.dart` calls `supabase.from('band_members').upsert(..., onConflict: 'id')`, so any conflicting membership row takes the UPDATE path and evaluates this policy. The rest of the restore path is already SECURITY DEFINER / authenticated correctly; the failure originates in the policy, not in the RPC wrapper.

The correct helper already exists and is already used safely elsewhere: `public.is_band_admin(p_band_id uuid)`. That helper is the right replacement for the inline self-query.

## 4) Reference Docs Consulted

I read all notification reference docs required by protocol, but they are unrelated to this database/RLS bug:

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

They describe the push-notification architecture, not band-member restore behavior. No dedicated restore/RLS reference doc exists in `docs/reference/` for this specific failure.

## 5) Existing System Analysis

Current restore data flow for an existing band:

1. `lib/features/bands/band_form_screen.dart` opens the restore dialog and hands the selected backup file to `DataBackupService.importBandData()`.
2. `lib/features/settings/data_backup_service.dart` parses the backup and enters `_restoreBandData(...)`.
3. For an existing band, `_restoreBandData()` calls `_upsertRows('band_members', entry['band_members'] as List? ?? [])`.
4. `_upsertRows()` uses `supabase.from(table).upsert(data, onConflict: 'id', ignoreDuplicates: false)`.
5. PostgREST/SQL takes the UPDATE branch for rows whose `id` already exists.
6. The `band_members_update_admins` policy evaluates on that UPDATE path.
7. Because the policy contains a self-referential subquery against `band_members`, PostgreSQL raises 42P17 and the restore aborts.

The missing-band restore path also uses `band_members` writes, but the current user is filtered out and fresh rows are usually inserted, so the existing-band path is the one directly responsible for the observed failure.

## 6) Proposed Solution

Replace the inline self-query in `band_members_update_admins` with the existing helper `is_band_admin(band_id)` in both `USING` and `WITH CHECK`.

What changes:

- Keep the current authorization semantics: only active admins may update band member rows.
- Remove the direct `FROM band_members` subquery from the policy body.
- Leave `restore_band_members()` unchanged.
- Leave `DataBackupService` unchanged.

What must not change:

- The restore RPC signature and call sites.
- The single-argument helper overload choice. Use `is_band_admin(p_band_id uuid)`, not the two-argument overload.
- The current ACL posture of existing functions, unless a future review proves an ACL regression unrelated to this fix.

## 7) Database Impact

Affected:

- RLS policy on `public.band_members`:
  - `band_members_update_admins` must stop self-querying the protected table.

Unaffected:

- RPC signature: unchanged.
- Triggers: unchanged.
- Table schema: unchanged.
- Function bodies: unchanged.
- Function ACLs: unchanged.

Migration required: yes, a new SQL migration that replaces the policy definition.

Edge function deploy required: no.

## 8) Flutter Architecture Changes

None.

This is a backend RLS fix. The Flutter restore flow already uses the correct generic upsert path and should not be changed unless the post-migration verification reveals a second defect.

## 9) Files to Create

- `supabase/migrations/<new_timestamp>_fix_band_members_update_policy_recursion.sql` — update the `band_members_update_admins` policy to call `is_band_admin(band_id)` instead of querying `band_members` directly.

## 10) Files to Modify

| File                                                                               | What changes                                                                                                                                                                                    |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<new_timestamp>_fix_band_members_update_policy_recursion.sql` | Drop and recreate `band_members_update_admins` so `USING` and `WITH CHECK` call `is_band_admin(band_id)`; include rollback SQL in the migration comments if the repo's migration style uses it. |

## 11) Files Off-Limits

| File                                                              | Reason                                                                        |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `lib/features/settings/data_backup_service.dart`                  | The client restore path is already correct; the failure is in RLS evaluation. |
| `lib/features/bands/band_form_screen.dart`                        | UI only launches restore; it is not the source of the bug.                    |
| `supabase/migrations/20260621000002_restore_band_members_rpc.sql` | Existing RPC is not the failure point and should remain stable.               |
| `supabase/functions/**`                                           | No edge function is involved in this restore path.                            |
| `lib/main.dart`                                                   | Init order and app startup are unrelated.                                     |
| Existing migration files                                          | Do not rewrite history; add one new migration only.                           |

## 12) System Impact Map

| System                                 | Impact     |
| --------------------------------------- | ---------- |
| Gigs                                    | unaffected |
| Rehearsals                              | unaffected |
| Setlists / Catalog                      | unaffected |
| Members / RBAC                          | affected   |
| Auth / Session                          | unaffected |
| Routing                                 | unaffected |
| Notifications                           | unaffected |
| Platform (iOS / Android / Web / macOS)  | unaffected |

## 13) Regression Risk

**MEDIUM**

Rationale:

- The change is small, but it alters an authorization policy used by every `band_members` UPDATE.
- Any mistake here would affect member-management workflows, not just restore.
- The fix is still low surface area because it swaps a self-query for an existing SECURITY DEFINER helper with identical intent.
- No Flutter, auth, routing, or edge-function code changes are needed.

## 14) Engineer Task Breakdown

1. Create a new migration in `supabase/migrations/` for the policy fix.
2. Replace the `band_members_update_admins` policy body so `USING` and `WITH CHECK` both call `is_band_admin(band_id)`.
3. Keep the existing active-admin semantics intact; do not change the helper overload or add a new function.
4. Confirm the migration does not modify function ACLs or any other table policy.
5. Run the pre-deployment verification queries against the current schema.
6. Apply the migration.
7. Run the post-deployment verification queries and the restore-flow integration test.
8. Confirm the restore path succeeds without 42P17 and without writing malformed member rows.

## 15) Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

These checks use only objects that already exist and do not depend on the new migration.

```sql
-- PRE-DEPLOY TEST 1: Confirm the current band_members UPDATE policy still self-queries band_members
SELECT policyname, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'band_members'
  AND policyname = 'band_members_update_admins';
-- Expected: both qual and with_check contain an EXISTS subquery against band_members
```

```sql
-- PRE-DEPLOY TEST 2: Confirm the single-argument helper exists and is grantable only to authenticated users
SELECT
  has_function_privilege('authenticated', 'public.is_band_admin(uuid)'::regprocedure, 'EXECUTE') AS authenticated_exec,
  has_function_privilege('anon', 'public.is_band_admin(uuid)'::regprocedure, 'EXECUTE') AS anon_exec;
-- Expected: authenticated_exec = true, anon_exec = false
```

```sql
-- PRE-DEPLOY TEST 3: Confirm the restore RPC still uses ON CONFLICT ... DO UPDATE on band_members
SELECT pg_get_functiondef('public.restore_band_members(uuid, jsonb)'::regprocedure);
-- Expected: function body contains INSERT INTO band_members ... ON CONFLICT (id) DO UPDATE
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Confirm the updated policy no longer self-queries band_members
SELECT policyname, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'band_members'
  AND policyname = 'band_members_update_admins';
-- Expected: qual and with_check use is_band_admin(band_id) and do not contain a direct band_members subquery
```

```sql
-- POST-DEPLOY TEST 2: Confirm the helper-backed policy still resolves the same admin gate
SELECT pg_get_functiondef('public.is_band_admin(uuid)'::regprocedure);
-- Expected: helper still checks band_members for auth.uid(), role = 'admin', status = 'active'
```

```sql
-- POST-DEPLOY TEST 3: Exercise the restore flow against a band fixture and confirm no error is thrown
-- Run the app-level restore flow or an equivalent authenticated upsert path against a test band backup.
-- Expected: restore completes successfully with no 42P17 error banner.
```

```sql
-- POST-DEPLOY TEST 4: Verify the restored band does not contain duplicate membership ids
SELECT band_id, COUNT(*) AS row_count, COUNT(DISTINCT id) AS distinct_row_count
FROM band_members
WHERE band_id = '<restored_band_id>'
GROUP BY band_id;
-- Expected: row_count = distinct_row_count
```

```sql
-- POST-DEPLOY TEST 5: Verify the restored band has the expected membership set
SELECT id, band_id, user_id, role, status
FROM band_members
WHERE band_id = '<restored_band_id>'
ORDER BY role, user_id;
-- Expected: rows match the backup contents used for the restore
```

## 16) QA Regression Areas

QA must specifically test:

1. Restore Band Data succeeds for an existing band that already has members.
2. Restore Band Data succeeds for a band backup that includes multiple members and an admin row.
3. Other band-member update flows still work for admins and still reject non-admins.
4. Restore does not surface the 42P17 recursion error banner.
5. A restore does not create duplicate or malformed `band_members` rows.
6. Existing band data remains intact after a failed restore attempt is retried.

## 17) Rollout / Migration Strategy

Use a single database migration that redefines the `band_members_update_admins` policy. No Flutter release, no edge-function deploy, and no schema backfill are required.

Recommended rollout order:

1. Verify the current live policy and helper definitions.
2. Apply the migration to the target Supabase project.
3. Run the post-deploy restore smoke test against a non-production band fixture or a carefully chosen production-safe test band.
4. Confirm the policy change did not alter ACLs or other band member operations.

Rollback strategy:

- Reapply the prior policy body if the migration introduces any unexpected authorization regression.
- Because this is a policy-only change, rollback is a single reverse migration; no data repair should be necessary unless a bad deployment writes partial restore data.

## 18) Out of Scope

- Any changes to `restore_band_members()`.
- Any changes to the Flutter restore UI or file parsing logic.
- Any changes to notification delivery, preference storage, or push-token code.
- Any unrelated RLS cleanup or policy consolidation beyond `band_members_update_admins`.
- Any new helper functions or new abstractions.
- Any data migration or backfill.

---
**Manager recovery note (post-hoc):** This file was lost from disk between the Architect session ending and QA starting (untracked file, wiped by an operation outside this pipeline). Restored verbatim from the Manager's own recorded gate-review transcript. Content above is unchanged from the original.
