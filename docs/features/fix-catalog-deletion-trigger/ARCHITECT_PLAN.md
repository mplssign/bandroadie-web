# ARCHITECT_PLAN

## 1. Feature Slug

bug/fix-catalog-deletion-trigger

## 2. Problem Summary

Deleting a Catalog setlist is intentionally blocked, but the current trigger guard blocks all delete paths, including cascade-style cleanup during band deletion and account deletion. This causes destructive cleanup flows to fail with `Cannot delete Catalog setlist` when they should succeed.

Expected behavior:

- Direct user-initiated delete of Catalog setlist: blocked
- Cascade/system cleanup deletes (band/account teardown): allowed

Actual behavior:

- Both direct and cascade delete paths are blocked.

## 3. Root Cause

The trigger function `prevent_catalog_deletion()` raises unconditionally when the target row is Catalog, without checking trigger execution depth.

Root cause confidence: HIGH

- Confirmed by feature input and existing schema reference to the guard trigger/function pair.
- Existing migration history shows multiple band/account cascade delete flows that include `DELETE FROM public.setlists ...`, which would invoke the guard trigger.

## 4. Relevant References Consulted

- docs/agents/ARCHITECT.md
- docs/agents/GUARDRAILS.md
- docs/agents/OPERATING_MODEL.md
- docs/reference/architecture/database_schema.md
- supabase/migrations/20260302000000_band_user_roles.sql
- supabase/migrations/20260607000000_fix_delete_band_cascade.sql
- supabase/migrations/075_delete_user_account_rpc.sql
- supabase/migrations/20260228000000_create_delete_setlist_rpc.sql

Note:

- Local migration files do not currently contain a textual definition for `prevent_catalog_deletion()` / `prevent_catalog_deletion_trigger`, so this fix must be shipped as a new migration that replaces the existing DB function in-place.

## 5. Existing System Analysis

Current deletion paths impacting `setlists`:

1. Direct setlist deletion path (UI/RPC) attempts to remove setlist rows.
2. Band deletion RPC (`delete_band`) explicitly deletes from `setlists` during cascade cleanup.
3. Account deletion and related teardown can transitively invoke band-level cleanup in admin-owned scenarios.

Because `prevent_catalog_deletion_trigger` is attached to `setlists` DELETE and `prevent_catalog_deletion()` raises without a trigger-depth exception path, all deletes of Catalog rows are blocked regardless of caller context.

## 6. Proposed Solution

Apply a targeted function-body change only:

- Update `prevent_catalog_deletion()` so it raises only when Catalog deletion is direct (`pg_trigger_depth() = 0`).
- Allow delete when invoked from nested trigger/cascade context (`pg_trigger_depth() > 0`).

Implementation shape inside function:

- Keep existing Catalog detection logic unchanged.
- Wrap exception branch with trigger-depth guard:
  - `IF <is_catalog_condition> AND pg_trigger_depth() = 0 THEN RAISE EXCEPTION ...; END IF;`

What must not change:

- No table schema changes
- No trigger name changes
- No trigger attachment changes
- No RLS policy changes
- No RPC signature changes

## 7. Database Impact

- Migrations: affected (new migration required)
- RLS: unaffected
- RPC signatures: unaffected
- Triggers: unchanged attachment; behavior changes via function body
- Tables: unchanged schema (`setlists` only behaviorally affected)

## 8. Flutter Architecture Changes

None.

- No Flutter/Riverpod/state/widget/repository file changes are required.
- Behavior change is entirely in Supabase Postgres trigger function logic.

## 9. Files to Create

- supabase/migrations/<timestamp>\_fix_prevent_catalog_deletion_trigger_cascade.sql
  - Reason: versioned, auditable replacement of `prevent_catalog_deletion()` function body.

## 10. Files to Modify

- none

## 11. Files Off-Limits

- lib/main.dart (initialization order guardrail)
- All `lib/**` feature code (not needed for DB trigger bug)
- Existing historical migration files under `supabase/migrations/` (append-only migration policy)

## 12. System Impact Map

| System                                 | Impact                                         |
| -------------------------------------- | ---------------------------------------------- |
| Gigs                                   | unaffected                                     |
| Rehearsals                             | unaffected                                     |
| Setlists / Catalog                     | affected                                       |
| Members / RBAC                         | unaffected                                     |
| Auth / Session                         | unaffected                                     |
| Routing                                | unaffected                                     |
| Notifications                          | unaffected                                     |
| Platform (iOS / Android / Web / macOS) | unaffected (server-side fix applies uniformly) |

## 13. Regression Risk

LOW

Rationale:

- Single-function behavioral guard change
- No schema or API contract change
- Explicitly narrows blocking scope from all delete contexts to direct delete contexts only

## 14. Engineer Task Breakdown

1. Add a new SQL migration file in `supabase/migrations/` with current timestamp naming.
2. In that migration, `CREATE OR REPLACE FUNCTION public.prevent_catalog_deletion()` with existing logic plus `pg_trigger_depth() = 0` direct-delete guard on the exception path.
3. Preserve existing exception message text (`Cannot delete Catalog setlist`) to avoid UI/error-contract drift.
4. Ensure function remains `LANGUAGE plpgsql` and includes `SET search_path = public` if existing function style in DB requires it.
5. Do not recreate or rename `prevent_catalog_deletion_trigger`; rely on function replacement only.
6. Add concise migration comments describing direct vs cascade behavior.

## 15. Verification Plan

### Tier 1 - Pre-deployment (must pass before `supabase db push`)

These tests validate baseline supporting behavior without calling the to-be-replaced function.

```sql
-- PRE-DEPLOY TEST 1:
-- Confirm trigger exists and points to prevent_catalog_deletion()
SELECT
  t.tgname AS trigger_name,
  p.proname AS function_name
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'setlists'
  AND t.tgname = 'prevent_catalog_deletion_trigger';

-- PRE-DEPLOY TEST 2:
-- Snapshot current function body for before/after diff evidence
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'prevent_catalog_deletion';
```

### Tier 2 - Post-deployment (run after `supabase db push`)

```sql
-- POST-DEPLOY TEST 1:
-- Verify function definition includes trigger-depth direct-delete guard
SELECT
  pg_get_functiondef(p.oid) LIKE '%pg_trigger_depth() = 0%' AS has_depth_guard
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'prevent_catalog_deletion';

-- POST-DEPLOY TEST 2:
-- Direct delete of Catalog should still fail
-- Requires a real catalog row in a test band. Wrap in transaction.
BEGIN;
DO $$
DECLARE
  v_setlist_id uuid;
BEGIN
  SELECT id INTO v_setlist_id
  FROM public.setlists
  WHERE COALESCE(is_catalog, false) = true OR name IN ('Catalog', 'All Songs')
  LIMIT 1;

  IF v_setlist_id IS NULL THEN
    RAISE NOTICE 'No catalog row found in this environment; skip direct-delete assertion.';
  ELSE
    BEGIN
      DELETE FROM public.setlists WHERE id = v_setlist_id;
      RAISE EXCEPTION 'Expected direct delete to be blocked, but delete succeeded';
    EXCEPTION WHEN OTHERS THEN
      IF POSITION('Cannot delete Catalog setlist' IN SQLERRM) = 0 THEN
        RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
      END IF;
    END;
  END IF;
END $$;
ROLLBACK;

-- POST-DEPLOY TEST 3:
-- Nested delete context should be allowed.
-- Validate via integration path: delete_band on a test band containing catalog setlist.
-- Dependency: real FK-linked test band + admin caller context.
-- Expected: delete_band returns true and no "Cannot delete Catalog setlist" exception.

-- POST-DEPLOY TEST 4:
-- Production safety check: ensure no orphaned setlist_songs rows remain.
SELECT COUNT(*) AS orphaned_setlist_song_rows
FROM public.setlist_songs ss
LEFT JOIN public.setlists s ON s.id = ss.setlist_id
WHERE s.id IS NULL;
```

## 16. QA Regression Areas

1. Direct setlist delete in UI:
   - Catalog delete remains blocked with expected message.
2. Band deletion flow:
   - Deleting a band that has a Catalog setlist succeeds end-to-end.
3. Account deletion flow:
   - User deletion path that triggers band cleanup completes without Catalog exception.
4. Non-Catalog setlist delete:
   - Existing allowed deletion behavior remains unchanged.
5. Cross-platform sanity:
   - iOS, Android, Web, macOS all unaffected in UI flow because fix is server-side.

## 17. Rollout / Migration Strategy

1. Add migration and run local verification SQL (Tier 1 then Tier 2).
2. Deploy migration via normal Supabase migration process.
3. Run post-deploy verification queries in production.
4. Monitor delete_band/delete-account error logs for 24h for residual Catalog exceptions.

## 18. Out of Scope

- Any Flutter UI/UX changes
- Any notification/auth/routing modifications
- Refactoring delete RPCs beyond what is required to validate this trigger bug
- Renaming Catalog semantics (`Catalog` vs `All Songs`) beyond existing guard behavior
