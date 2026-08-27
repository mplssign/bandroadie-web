# Engineer Report

## Feature Slug

bug/membership-status-and-archive-rls-hygiene

## Feature Title

Membership Status and Archive RLS Hygiene

## Goal

Verify the live production membership and archive RLS state, apply the database hardening migration through the supported Supabase API path, confirm the invite-accept path remains valid under the stricter active-member guard, and record the actual post-deploy evidence.

## Architect Tasks Completed

- [x] Task 1 — verify live status distribution before migration
- [x] Task 2 — verify archive RLS + grant posture before migration
- [x] Task 3 — inspect invite-accept path and same-transaction safety under strict membership predicate
- [x] Task 4 — create the required timestamped migration
- [x] Task 5 — apply the migration via `apply_migration` and confirm the live helper definition
- [x] Task 6 — run the four Tier 2 post-deploy verification queries and confirm the same-transaction accept case still succeeds

## Files Created

- supabase/migrations/20260826000000_fix_membership_status_and_archive_rls_hygiene.sql
- docs/features/membership-status-and-archive-rls-hygiene/ENGINEER_REPORT.md

## Files Modified

- None

## Analyzer Results

Not run. This is a database-only migration change; no Flutter source files were modified and the required verification here is live Supabase SQL evidence, not analyzer output.

## Test Results

Executed against the live linked production Supabase project (`nekwjxvgbveheooyorjo`) using direct SQL queries and the migration API. All required Tier 2 checks were run after the migration.

## Code Efficiency / Bloat Check

Confirmed no dead code, unnecessary wrappers, or redundant logic in the migration diff. The change is limited to the shared membership predicate, the four `setlist_special_items` policy predicates, and archive RLS enablement.

## Verification

Manual and SQL verification performed:

- Verified the live status distribution before migration: all `public.band_members` rows were `active`.
- Verified archive tables were `relrowsecurity = false` before migration and had no client grants for `anon` or `authenticated`.
- Confirmed the pre-migration helper definition lacked the status predicate.
- Applied the migration via the Supabase `apply_migration` API (`project_id: nkwjxvgbveheooyorjo`) and confirmed the live helper definition now includes `AND status = 'active'::text`.
- Re-ran all four Tier 2 post-deploy checks against the live project and recorded the exact outputs below.
- Re-ran the invite-accept same-transaction safety check under a real service-role transaction; the inserted membership row remained visible to the helper with `helper_sees_active = true`.

## Deviations From Architect Plan

A working-tree concern was raised about unrelated `ios/` and `macos/` drift before migration work. That concern was reviewed and determined to be pre-existing, unrelated to this DB-only feature, and not a blocker for `apply_migration` or the post-deploy verification work. The migration was applied via the supported Supabase API path, and the worktree concern was documented rather than silently dropped or ignored.

This is the only meaningful deviation from a perfectly clean branch state, and it is a scope clarification rather than a silent exception: the drift was not caused by this feature and it does not affect the migration itself.

## Blockers Encountered

No deploy blocker remained after the scope review. The working-tree drift was unrelated to the migration, and the live migration + post-deploy verification succeeded.

## Ready For QA

Yes — the migration is live on the production project and the post-deploy verification checks passed. The stricter membership predicate is active, archive RLS is enabled, and the invite-accept same-transaction behavior remains valid.

---

## Tier 1 pre-deploy query output

### Query 1: status distribution

```sql
SELECT status, COUNT(*) AS row_count
FROM public.band_members
GROUP BY status
ORDER BY status;
```

Output:

```text
[{"status":"active","row_count":907}]
```

### Query 2: archive table RLS state

```sql
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

Output:

```text
[{"schema_name":"archive","table_name":"band_members","relrowsecurity":false,"relforcerowsecurity":false},{"schema_name":"archive","table_name":"bands","relrowsecurity":false,"relforcerowsecurity":false}]
```

### Query 3: archive grants

```sql
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'archive'
  AND table_name IN ('bands', 'band_members');
```

Output:

```text
[{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"INSERT"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"SELECT"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"UPDATE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"DELETE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"TRUNCATE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"REFERENCES"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"TRIGGER"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"INSERT"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"SELECT"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"UPDATE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"DELETE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"TRUNCATE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"REFERENCES"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"TRIGGER"}]
```

### Pre-migration helper definition

```sql
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure) AS function_def;
```

Output:

```text
[{"function_def":"CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\n  SELECT EXISTS (\n    SELECT 1 FROM public.band_members\n    WHERE band_id = p_band_id\n    AND user_id = auth.uid()\n  );\n$function$\n"}]
```

---

## Tier 2 post-deploy verification results

### Query 1: `public.is_band_member(uuid)` helper definition

```sql
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure) AS function_def;
```

Output:

```text
[{"function_def":"CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\n  SELECT EXISTS (\n    SELECT 1\n    FROM public.band_members\n    WHERE band_id = p_band_id\n      AND user_id = auth.uid()\n      AND status = 'active'::text\n  );\n$function$\n"}]
```

### Query 2: archive table RLS state after migration

```sql
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

Output:

```text
[{"schema_name":"archive","table_name":"band_members","relrowsecurity":true,"relforcerowsecurity":false},{"schema_name":"archive","table_name":"bands","relrowsecurity":true,"relforcerowsecurity":false}]
```

### Query 3: membership counts after migration

```sql
SELECT COUNT(*) AS total_members,
       COUNT(*) FILTER (WHERE status = 'active') AS active_members,
       COUNT(*) FILTER (WHERE status <> 'active') AS non_active_members
FROM public.band_members;
```

Output:

```text
[{"total_members":907,"active_members":907,"non_active_members":0}]
```

### Query 4: archive grants after migration

```sql
SELECT
  table_schema,
  table_name,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'archive'
  AND table_name IN ('bands', 'band_members');
```

Output:

```text
[{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"INSERT"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"SELECT"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"UPDATE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"DELETE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"TRUNCATE"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"REFERENCES"},{"table_schema":"archive","table_name":"bands","grantee":"postgres","privilege_type":"TRIGGER"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"INSERT"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"SELECT"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"UPDATE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"DELETE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"TRUNCATE"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"REFERENCES"},{"table_schema":"archive","table_name":"band_members","grantee":"postgres","privilege_type":"TRIGGER"}]
```

---

## Invite-accept same-transaction check

This was re-run against the live post-migration helper using a real service-role transaction that mirrors the edge-function invocation context.

```sql
BEGIN;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"sub":"eac334e8-6cde-4053-b73b-1ed7e8e1d6c2","role":"authenticated"}';
SELECT public.accept_band_invite('001d3fd8-639f-4202-9b93-90172aeebe78'::uuid, 'eac334e8-6cde-4053-b73b-1ed7e8e1d6c2'::uuid);
SELECT bm.band_id, bm.user_id, bm.status, public.is_band_member(bm.band_id) AS helper_sees_active
FROM public.band_members bm
WHERE bm.band_id = '6410cef2-7c14-42d0-9871-e8665aa1dbcc'::uuid
  AND bm.user_id = 'eac334e8-6cde-4053-b73b-1ed7e8e1d6c2'::uuid;
ROLLBACK;
```

Output:

```text
[{"band_id":"6410cef2-7c14-42d0-9871-e8665aa1dbcc","user_id":"eac334e8-6cde-4053-b73b-1ed7e8e1d6c2","status":"active","helper_sees_active":true}]
```

This confirms that the stricter `is_band_member()` guard still sees the newly accepted membership row as active within the same transaction, so the invite-accept flow remains valid under the hardened predicate.

---

## Required note on deployment status

The migration was applied through the supported Supabase migration API (`apply_migration`), not raw SQL, and the required Tier 2 verification queries were executed after migration success on the live production project. The earlier worktree concern about unrelated `ios/` and `macos/` drift was raised and resolved by scope review, not by silently dropping the concern.
