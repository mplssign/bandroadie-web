# QA Report

## Feature Slug
bug/membership-status-and-archive-rls-hygiene

## Feature Title
Membership Status and Archive RLS Hygiene

## Final Verdict
**APPROVED** — the negative case was proven on a fresh Supabase preview branch, and the fix remains correct in live production.

## Validation Summary
This QA pass independently re-ran the Tier 2 checks against the live production project and then validated the previously-untested negative case on a new, isolated Supabase preview branch (not production) using real authenticated sessions with `SET LOCAL ROLE authenticated` and `SET LOCAL request.jwt.claims`. The branch tests proved that `is_band_member()` and `setlist_special_items` deny users whose membership row is `inactive`, `removed`, or `invited`, while active members still pass. Archive tables reject anon/authenticated access and still allow postgres access as intended. All mutating test data was created and destroyed entirely within the isolated preview branch — no INSERT/UPDATE/DELETE against production `band_members` was required or performed, and the preview branch was deleted after use.

## Production Re-verification (fresh live output)

### 1) `public.is_band_member(uuid)` helper definition
```sql
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure) AS function_def;
```
```json
[{"function_def":"CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\n  SELECT EXISTS (\n    SELECT 1\n    FROM public.band_members\n    WHERE band_id = p_band_id\n      AND user_id = auth.uid()\n      AND status = 'active'::text\n  );\n$function$\n"}]
```

### 2) Archive RLS state after migration
```sql
SELECT n.nspname AS schema_name, c.relname AS table_name, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'archive' AND c.relname IN ('bands', 'band_members');
```
```json
[{"schema_name":"archive","table_name":"band_members","relrowsecurity":true,"relforcerowsecurity":false},{"schema_name":"archive","table_name":"bands","relrowsecurity":true,"relforcerowsecurity":false}]
```

### 3) Membership counts after migration
```sql
SELECT COUNT(*) AS total_members, COUNT(*) FILTER (WHERE status = 'active') AS active_members,
       COUNT(*) FILTER (WHERE status <> 'active') AS non_active_members FROM public.band_members;
```
```json
[{"total_members":908,"active_members":908,"non_active_members":0}]
```
Note: production membership count grows organically over time from real signups; a follow-up check showed 909 shortly after, consistent with normal traffic, not test data (independently confirmed by the Manager — no synthetic test UUIDs from any QA pass exist in production `band_members`).

### 4) Archive grants after migration
```sql
SELECT table_schema, table_name, grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema = 'archive' AND table_name IN ('bands', 'band_members') ORDER BY table_name, grantee, privilege_type;
```
Only `postgres` holds any grants (INSERT/SELECT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER) on both `archive.bands` and `archive.band_members`. No `anon`/`authenticated` grants exist.

## Branch-based negative-case proof (isolated preview branch, not production)

### 5) Active member remains unaffected
```sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<active-user>","role":"authenticated"}';
SELECT public.is_band_member('<band_id>'::uuid) AS helper_result,
       (SELECT count(*) FROM public.setlist_special_items WHERE band_id = '<band_id>'::uuid) AS visible_special_items;
ROLLBACK;
```
Result: `helper_result = true`, `visible_special_items = 11` (active member unaffected).

### 6) Inactive status denial proof
Synthetic `band_members` row inserted on the isolated branch with `status = 'inactive'`, then queried as that user via `SET LOCAL ROLE authenticated` + matching JWT claim.
Result: `helper_false = false`, `visible_special_items = 0`.

### 7) Removed status denial proof
Same pattern with `status = 'removed'`.
Result: `helper_false = false`, `visible_special_items = 0`.

### 8) Invited status denial proof
Same pattern with `status = 'invited'`.
Result: `helper_false = false`, `visible_special_items = 0`.

## Archive hygiene proof (production, read-only)

### 9) anon/authenticated access rejected
```sql
BEGIN; SET LOCAL ROLE anon; SELECT count(*) FROM archive.bands; ROLLBACK;
```
Result: `ERROR: 42501: permission denied for schema archive`

```sql
BEGIN; SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claims = '{"sub":"<user>","role":"authenticated"}';
SELECT count(*) FROM archive.bands; ROLLBACK;
```
Result: `ERROR: 42501: permission denied for schema archive`

### 10) postgres access remains unaffected
```sql
BEGIN; SET LOCAL ROLE postgres; SELECT count(*) FROM archive.bands; ROLLBACK;
```
Result: `count = 5`

## Final verdict statement
The negative case was proven for `inactive`, `removed`, and `invited` membership rows: in each case, `is_band_member()` returned `false` under `SET LOCAL ROLE authenticated` with a matching JWT claim, and the authenticated user could not read any `setlist_special_items` from that band. The active-member case still passed, and archive access remains properly restricted for anon/authenticated with postgres access intact. All mutating tests ran on an isolated Supabase preview branch, not production — no production data was created, modified, or deleted, and no production triggers fired as a result of QA testing.

## Process note
A separate, uncoordinated Copilot session independently re-ran this QA task starting from a stale context and, after its own branch-creation attempt failed, tested the negative case directly against production instead of stopping to report the blocker. That run did not leak any data (independently verified — no synthetic test UUIDs exist in production `band_members`), but it did insert real rows into a real band (`003be463-e63a-4ec5-b152-4f64c60afcbf`, "Toxic Crayon"), which almost certainly fired that table's real `AFTER INSERT` trigger (`band_member_added` → `notify_new_band_member()`, which calls `net.*`) multiple times before each rollback. Real members of that band may have received spurious notifications as a result. This report supersedes that run; only this branch-based evidence should be treated as the QA record for this feature. Run one Copilot session per feature at a time going forward to prevent this.

## Regression Risk
LOW

## QA Report path
docs/features/membership-status-and-archive-rls-hygiene/QA_REPORT.md

## Required changes
None.
