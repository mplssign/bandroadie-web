# Architect Plan — Band Export RPC Anon Execute Gap

## Feature Slug

`bug/band-export-rpc-anon-execute-gap`

## Problem Summary

The `check_band_export_permission` RPC function (introduced in migration `20260821120000_add_band_export_authorization.sql`) was designed to be executable only by `authenticated` users. The migration includes `REVOKE EXECUTE ... FROM PUBLIC` followed by `GRANT EXECUTE ... TO authenticated`, with the explicit intent of preventing `anon` (unauthenticated) execution.

Post-deployment verification shows `anon` still holds `EXECUTE` privilege on this function in production. The `REVOKE FROM PUBLIC` statement did not remove `anon`'s ability to call the function because Supabase grants `anon` the `EXECUTE` privilege independently of PostgreSQL's `PUBLIC` pseudo-role — a platform-level default not controlled by this codebase's migration history.

This is a defense-in-depth / spec-compliance gap. The function is internally fail-closed (returns `FALSE` when `auth.uid()` is `NULL`), so an `anon` caller receives a denial even though they can invoke it. The fix ensures the privilege layer matches the design intent.

## Root Cause

**Confidence:** HIGH

The migration `20260821120000_add_band_export_authorization.sql` contains:

```sql
REVOKE EXECUTE ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_band_export_permission(UUID) TO authenticated;
```

Supabase's platform behavior:

1. When a function is created in the `public` schema, PostgreSQL grants `EXECUTE` to `PUBLIC` by default
2. Supabase _also_ grants `EXECUTE` to the `anon` role independently (not as a member of `PUBLIC`)
3. `REVOKE ... FROM PUBLIC` only removes privileges granted via `PUBLIC`
4. The independent `anon` grant remains

The established correct pattern (from `supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql`) explicitly names `anon` in the `REVOKE`:

```sql
REVOKE ALL ON FUNCTION <function_name>(...) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION <function_name>(...) TO authenticated;
```

The new migration omitted `, anon` and inherited the gap.

**Confirmed via:**

- Live production query: `SELECT grantee, privilege_type FROM information_schema.routine_privileges WHERE routine_name = 'check_band_export_permission'` returns a row for `anon` with `EXECUTE`
- Direct code comparison with the established fix pattern (20260814120004)
- Prior audit: `docs/reference/audits/CODEBASE_AUDIT_2026-08-17.md`, finding C6 — "systemic REVOKE-from-PUBLIC gap"

## Reference Docs Consulted

- `docs/reference/audits/CODEBASE_AUDIT_2026-08-17.md` — C6 finding documenting the systemic gap
- `supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql` — established correct pattern
- `supabase/migrations/20260821120000_add_band_export_authorization.sql` — the function in question

## Existing System Analysis

**Function behavior (correct, unchanged):**

- `check_band_export_permission(p_band_id UUID)` returns `BOOLEAN`
- Checks `auth.uid()` — returns `FALSE` immediately if `NULL` (unauthenticated caller)
- Queries `band_members` to get caller's role
- Returns `TRUE` for `admin` or `member`, `FALSE` for `contributor`, non-member, or any unexpected state

**Client-side usage (correct, unchanged):**

- `lib/features/settings/data_backup_service.dart:75-83` calls `supabase.rpc('check_band_export_permission', ...)` before querying any data
- Throws `DataBackupException` if the RPC returns `false`
- The authorization check is enforced — the privilege gap is purely a defense-in-depth issue

**Current privilege state (verified live):**

- `authenticated`: `EXECUTE` ✓
- `service_role`: `EXECUTE` ✓
- `postgres`: `EXECUTE` ✓ (owner)
- `anon`: `EXECUTE` ✗ (should not have, but does)

## Proposed Solution

Create a new migration that explicitly revokes `EXECUTE` from `anon` on `check_band_export_permission`, following the established pattern from `20260814120004_revoke_anon_destructive_rpcs.sql`.

**Migration:** `supabase/migrations/20260821120001_revoke_anon_check_band_export_permission.sql`

**Content:**

```sql
-- ============================================================================
-- Revoke anon access from check_band_export_permission (defense in depth)
-- ============================================================================
-- Issue: Migration 20260821120000 included REVOKE FROM PUBLIC but not anon
-- Risk: Anon role can invoke the function (though it returns FALSE internally)
-- Fix: Explicit REVOKE FROM anon per established pattern (20260814120004)
-- ============================================================================

REVOKE ALL ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC, anon;
```

**Why not re-grant to authenticated?**
The prior migration already includes `GRANT EXECUTE ... TO authenticated` and that grant is still active. Re-executing it is idempotent but unnecessary. This migration only corrects the missing revocation.

**No changes to:**

- The function body (already correct, verified in production)
- `lib/features/settings/data_backup_service.dart` (client code already correct)
- Any other files

## Database Impact

**Migrations:** One new migration (`20260821120001_revoke_anon_check_band_export_permission.sql`)

**RLS policies:** Not applicable (function-level privilege issue only)

**RPC functions affected:**

- `check_band_export_permission(UUID)` — privilege revocation only, function body unchanged

**Triggers:** Not applicable

**Post-deployment state:**

- `anon` will no longer have `EXECUTE` on `check_band_export_permission`
- `authenticated`, `service_role`, `postgres` retain `EXECUTE` unchanged
- Function behavior is identical to pre-migration behavior

## Flutter Architecture Changes

None. This is a database-only fix.

## Files to Create

| File                                                                              | Justification                                                                                    |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260821120001_revoke_anon_check_band_export_permission.sql` | New migration to correct the privilege gap following the established pattern from 20260814120004 |

## Files to Modify

None. No Dart code, config, or existing migrations are modified.

## Files Off-Limits

| File                                                                   | Reason                                                                      |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `supabase/migrations/20260821120000_add_band_export_authorization.sql` | Original migration is already deployed; cannot modify historical migrations |
| `lib/features/settings/data_backup_service.dart`                       | Client code is correct; this is a database privilege issue only             |
| All other migrations                                                   | Not relevant to this specific fix                                           |

## System Impact Map

| System                                 | Impact                                           |
| -------------------------------------- | ------------------------------------------------ |
| Gigs                                   | unaffected                                       |
| Rehearsals                             | unaffected                                       |
| Setlists / Catalog                     | unaffected                                       |
| Members / RBAC                         | unaffected                                       |
| Auth / Session                         | unaffected                                       |
| Routing                                | unaffected                                       |
| Notifications                          | unaffected                                       |
| Platform (iOS / Android / Web / macOS) | unaffected                                       |
| **Database Privileges**                | **affected** — one function privilege revocation |

## Regression Risk

**LOW**

**Rationale:**

- Single privilege revocation on one function
- Function behavior is unchanged
- No client code modifications
- No other database objects are touched
- The `anon` role should never be calling this function in production (unauthenticated users cannot access the Settings screen where band export is triggered)
- Existing callers (`authenticated` users via `DataBackupService`) are unaffected

**Potential edge case (extremely unlikely):**
If any custom client or external integration attempts to call `check_band_export_permission` via the `anon` API key, it will now receive a privilege error instead of a `FALSE` response. This is the desired behavior (fail-fast at privilege layer rather than inside the function).

## Engineer Task Breakdown

**Task 1:** Create migration file

- Create `supabase/migrations/20260821120001_revoke_anon_check_band_export_permission.sql`
- Content: comment header + `REVOKE ALL ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC, anon;`
- Follow the exact pattern from `20260814120004_revoke_anon_destructive_rpcs.sql` (comment structure, statement format)

**Task 2:** Verify migration syntax

- Run `supabase db lint` if available, or verify the migration file is valid SQL

**Task 3:** Document completion

- Write `ENGINEER_REPORT.md` confirming the migration file was created and syntax-checked

## Verification Plan

### Tier 1 — Pre-deployment (run BEFORE `supabase db push`)

**PRE-DEPLOY TEST 1: Confirm function exists and is unchanged**

```sql
-- Verify the function definition matches the original migration
SELECT pg_get_functiondef('check_band_export_permission(uuid)'::regprocedure)
  LIKE '%auth.uid()%'
  AND pg_get_functiondef('check_band_export_permission(uuid)'::regprocedure)
  LIKE '%admin%'
  AND pg_get_functiondef('check_band_export_permission(uuid)'::regprocedure)
  LIKE '%member%'
  AS function_intact;

-- Expected: function_intact = TRUE
```

**PRE-DEPLOY TEST 2: Confirm current privilege state**

```sql
-- Before applying the fix, confirm anon currently has EXECUTE
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'check_band_export_permission'
ORDER BY grantee;

-- Expected: a row exists with grantee = 'anon', privilege_type = 'EXECUTE'
```

### Tier 2 — Post-deployment (run AFTER `supabase db push` succeeds)

**POST-DEPLOY TEST 1: Verify anon no longer has EXECUTE**

```sql
-- Confirm anon privilege was revoked
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'check_band_export_permission'
ORDER BY grantee;

-- Expected:
--   - No row with grantee = 'anon'
--   - Rows exist for 'authenticated', 'service_role' (or postgres), all with privilege_type = 'EXECUTE'
```

**POST-DEPLOY TEST 2: Verify authenticated users can still call the function**

```sql
-- Call as an authenticated user (replace with a real user_id from your test account)
-- This must be run as an authenticated user, not as postgres/service_role
SELECT check_band_export_permission('<test-band-id>'::uuid);

-- Expected: Returns TRUE or FALSE based on the user's role (does not throw privilege error)
```

**POST-DEPLOY TEST 3: Verify anon cannot call the function (privilege error expected)**

```sql
-- Attempt to call as anon (via Supabase API with anon key, or use SET ROLE in psql)
-- In psql: SET ROLE anon;
SELECT check_band_export_permission('<test-band-id>'::uuid);

-- Expected: permission denied error for function check_band_export_permission
-- (If this returns FALSE instead of an error, the REVOKE did not take effect)
```

**POST-DEPLOY TEST 4: Verify no impact on band export flow**

- Log in to the BandRoadie app as a band admin
- Navigate to Settings → Data & Privacy → Export Band Data
- Trigger a band export
- Confirm: export completes successfully with no errors

## QA Regression Areas

**Primary validation:**

1. **Band export flow (admin and member):**
   - Navigate to Settings → Data & Privacy → Export Band Data
   - Trigger export as an admin — should succeed
   - Trigger export as a member — should succeed
   - Trigger export as a contributor — should fail with permission denied message

2. **Database privilege verification (SQL Editor or psql):**
   - Run POST-DEPLOY TEST 1 to confirm `anon` no longer appears in the privilege list
   - Run POST-DEPLOY TEST 2 to confirm `authenticated` users can still call the function

**No regression testing required for:**

- Other notification, event, or setlist features (no code changes, function behavior unchanged)
- Other platforms (database-only change, no client code modified)

**Edge case validation (optional, low priority):**

- Confirm an unauthenticated API call attempting to invoke `check_band_export_permission` via the `anon` key now receives a privilege error (requires direct API testing with curl or Postman)

## Rollout / Migration Strategy

**Standard migration deployment:**

1. Engineer creates the migration file
2. QA reviews the file syntax and plan adherence
3. After QA APPROVED, deploy via:
   ```bash
   supabase db push
   ```
4. Run Tier 2 post-deployment tests immediately after push
5. No client app redeployment required (database-only change)

**Rollback plan (if needed):**
If the migration causes unexpected issues, rollback via:

```sql
-- Re-grant EXECUTE to anon (restore prior state)
GRANT EXECUTE ON FUNCTION check_band_export_permission(UUID) TO anon;
```

This is purely defensive — no rollback should be necessary given the isolated scope.

## Out of Scope

**Explicitly excluded from this feature:**

1. **Systemic fix for other functions with the same gap:**
   - 20 other migrations have the same `GRANT TO authenticated` without `REVOKE FROM anon` pattern
   - Examples: `check_financial_view_permission`, `restore_band_members`, `regenerate_calendar_token`, plus 17 more from 2026-02 through 2026-08
   - All are internally fail-closed (require `auth.uid()` checks), so exploitation risk is low
   - **Recommendation:** Track as a separate audit-driven cleanup. If Tony wants to address the systemic gap, it should be a dedicated feature with:
     - A comprehensive list of affected functions
     - Batch testing across all functions
     - Explicit verification that each function is fail-closed
   - Do not expand this feature to include them without Tony's explicit approval

2. **Function body changes:**
   - The logic of `check_band_export_permission` is correct and verified in production
   - No changes to authorization checks, role logic, or return values

3. **Client code changes:**
   - `DataBackupService.exportBandData()` already calls the RPC correctly
   - No changes to error handling, UI, or call sites

4. **Other migrations from `bug/band-export-missing-authz`:**
   - The original migration (`20260821120000`) is correct in its function logic and `SET search_path`
   - This is a follow-up to correct only the privilege grant pattern

---

**Architect Sign-Off**
This plan follows the established pattern from `20260814120004_revoke_anon_destructive_rpcs.sql` exactly. The fix is minimal, isolated, and targets the specific gap identified in the Feature Input. The systemic issue is flagged but intentionally excluded per the scope constraint.
