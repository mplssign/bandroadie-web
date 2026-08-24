# Architect Plan — bug/band-create-catalog-trigger-race

## Feature Slug

`bug/band-create-catalog-trigger-race`

## Problem Summary

Users cannot create a new band on any platform (Web, iOS, Android, macOS). Every `create_band` RPC call fails with `Access denied: not an active member of this band` since 2026-08-22 12:52 UTC. This is a 100% failure rate — zero successful band creations in production since that timestamp. Core onboarding flow is completely broken.

The root cause is a trigger execution race: the `ensure_catalog_setlist` authorization check (added in migration `20260822120101_add_membership_check_ensure_catalog.sql` to fix `bug/setlist-rpc-missing-membership-check`) fires during the `bands` table INSERT trigger before the creator's own `band_members` row exists, causing the membership check to fail for the band's legitimate creator.

## Root Cause

**Cause:** The `trigger_auto_create_catalog` AFTER INSERT trigger on `bands` calls `auto_create_catalog_for_band()` → `ensure_catalog_setlist(NEW.id)` synchronously within the `INSERT INTO bands` statement. The 2026-08-22 membership authorization check in `ensure_catalog_setlist` queries `band_members` for the new band, but that table has zero rows because `create_band()`'s next statement (which inserts the creator's admin membership) has not yet executed. The check evaluates `v_is_member = false` for the band's own creator and raises `Access denied`, aborting the transaction before the `band_members` row can be inserted.

**Execution order in `create_band` (from `087_fix_create_band_no_profile.sql`):**

1. `INSERT INTO bands (...) RETURNING id INTO v_band_id;`
   - **Trigger fires here (synchronous):** `trigger_auto_create_catalog` → `auto_create_catalog_for_band()` → `ensure_catalog_setlist(v_band_id)`
   - **Authorization check fails:** `band_members` WHERE `band_id = v_band_id` returns zero rows
   - **Exception raised:** `'Access denied: not an active member of this band'`
   - **Transaction aborts**
2. `INSERT INTO band_members (band_id, user_id, status, role) VALUES (v_band_id, v_user_id, 'active', 'admin');` — **never reached**

**Confidence:** `HIGH`

**Evidence:**

- Direct code inspection: migration `20260822120101_add_membership_check_ensure_catalog.sql` and `087_fix_create_band_no_profile.sql`
- Production logs (project `nekwjxvgbveheooyorjo`): `Access denied: not an active member of this band` at exact millisecond of every failed `create_band` call
- Production data: `bands` table last successful insert 2026-08-22 12:52:47 UTC, zero successful inserts since despite repeated user attempts in edge logs

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — RPC function list, band management operations
- `docs/reference/architecture/supabase_functions.md` — edge function inventory (none relevant to this bug)
- `docs/features/setlist-rpc-missing-membership-check/ARCHITECT_PLAN.md` — context for the 2026-08-22 security fix that introduced this regression

No band-creation-specific or catalog-trigger-specific reference documentation exists in `docs/reference/`.

## Existing System Analysis

### Current Authorization Check (from migration `20260822120101`)

```plpgsql
CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  catalog_id UUID;
  -- ... other declarations
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK (added 2026-08-22)
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ... rest of function body unchanged
END;
$function$;
```

### Current `create_band` Flow (from migration `087_fix_create_band_no_profile.sql`)

```plpgsql
CREATE OR REPLACE FUNCTION public.create_band(
  p_name TEXT,
  p_avatar_color TEXT DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_email TEXT;
  v_band_id UUID;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Ensure user exists in public.users table
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id) THEN
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    IF v_user_email IS NULL THEN
      RAISE EXCEPTION 'User not found in auth system';
    END IF;
    INSERT INTO users (id, email) VALUES (v_user_id, v_user_email);
  END IF;

  -- Create the band
  INSERT INTO bands (name, avatar_color, image_url, created_by)
  VALUES (p_name, COALESCE(p_avatar_color, '#F43F5E'), p_image_url, v_user_id)
  RETURNING id INTO v_band_id;
  -- ↑ trigger_auto_create_catalog fires HERE (synchronous, before next statement)

  -- Add the creator as admin (never reached due to trigger exception)
  INSERT INTO band_members (band_id, user_id, status, role)
  VALUES (v_band_id, v_user_id, 'active', 'admin');

  RETURN v_band_id;
END;
$$;
```

### Call Sites

**Client-side (legitimate):** `lib/features/setlists/setlist_repository.dart` ~line 3099 — calls `ensure_catalog_setlist` directly for existing bands where caller is already an active member. This call site is NOT broken; the authorization check works correctly here.

**Trigger (broken during band creation):** `trigger_auto_create_catalog` on `bands` table → `auto_create_catalog_for_band()` → `ensure_catalog_setlist(NEW.id)`. This is the broken path.

## Proposed Solution

**Core Change:**

Extend the authorization check in `ensure_catalog_setlist` to include a bypass clause for the band-creation race condition:

```sql
-- Check active membership
SELECT EXISTS(
  SELECT 1 FROM band_members
  WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
) INTO v_is_member;

-- If not a member, check for band-creation race exception:
-- Allow if (1) we're in a trigger context AND (2) caller is band creator AND (3) no membership rows exist yet
IF NOT v_is_member THEN
  SELECT
    pg_trigger_depth() > 0
    AND EXISTS(SELECT 1 FROM bands WHERE id = p_band_id AND created_by = v_user_id)
    AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)
  INTO v_is_member;
END IF;

IF NOT v_is_member THEN
  RAISE EXCEPTION 'Access denied: not an active member of this band';
END IF;
```

**How this fixes the race:**

1. During `create_band` → trigger → `ensure_catalog_setlist`:
   - First check: `band_members` WHERE `band_id = NEW.id` → 0 rows → `v_is_member = false`
   - Second check: `pg_trigger_depth() > 0` (TRUE in trigger context) AND caller is `bands.created_by` for NEW.id AND `band_members` has 0 rows for NEW.id → `v_is_member = true`
   - Authorization passes, catalog is created
   - Function returns to `create_band`, which then inserts the `band_members` row

2. For all subsequent calls (client-side or direct RPC):
   - If caller is an active member: first check passes, done
   - If caller is not a member but is the creator of a zero-member band: second check fails because `pg_trigger_depth() = 0` (not in trigger context) → access denied (correct)
   - If caller is neither: both checks fail → access denied (correct)

**Security properties preserved:**

- The bypass **only fires during trigger execution** (`pg_trigger_depth() > 0`) — direct RPC calls from `setlist_repository.dart` or any future caller can never satisfy the bypass, even if the band has zero members
- Once any `band_members` row exists for a band, the bypass never applies (even from triggers)
- All client-side calls from existing bands go through the full membership check unchanged
- The 2026-08-22 security intent (prevent cross-tenant tampering via `ensure_catalog_setlist`) is fully preserved for every call except the synchronous nested call from `trigger_auto_create_catalog` during `create_band`
- The cross-tenant hole that `bug/setlist-rpc-missing-membership-check` closed remains closed: if a band drains to zero members after creation, the original creator cannot use the bypass to regain access via direct RPC, because `pg_trigger_depth() = 0` for direct calls

**What does not change:**

- Trigger architecture (no changes to `trigger_auto_create_catalog`, `auto_create_catalog_for_band`)
- `create_band` function body
- Client-side code (no changes to `band_form_screen.dart` or error handling)
- RLS policies
- ACL grants

## Database Impact

**Affected:**

- `public.ensure_catalog_setlist(uuid)` — function body modified to add band-creation bypass clause

**Unaffected:**

- RLS policies
- Trigger definitions (`trigger_auto_create_catalog`, `auto_create_catalog_for_band`)
- `create_band` RPC
- All other RPC functions
- Table schemas
- ACL grants

**Migration required:** Yes — one new migration to replace `ensure_catalog_setlist` function body.

## Flutter Architecture Changes

None. This is a database-only fix. No changes to state management, widgets, repositories, controllers, or services.

## Files to Create

| File                                                                           | Justification                                                                                                                                                                       |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/YYYYMMDDHHMMSS_fix_ensure_catalog_band_creation_race.sql` | New migration to replace `ensure_catalog_setlist` function body with extended authorization check. Timestamp to be generated at implementation time per Supabase naming convention. |

## Files to Modify

None. All changes are in the new migration.

## Files Off-Limits

| File                                                                         | Reason                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `supabase/migrations/087_fix_create_band_no_profile.sql`                     | Existing migration — historical migrations must never be modified         |
| `supabase/migrations/20260822120101_add_membership_check_ensure_catalog.sql` | Existing migration — historical migrations must never be modified         |
| All trigger definition migrations                                            | Not required — bypass clause handles race without touching trigger timing |
| `lib/features/bands/band_form_screen.dart`                                   | Client-side code — fix is server-side only                                |
| All other Flutter code                                                       | Server-side fix only                                                      |
| All other Supabase migrations                                                | No other migrations are involved                                          |

## System Impact Map

| System                                 | Impact                                                      |
| -------------------------------------- | ----------------------------------------------------------- |
| Gigs                                   | unaffected                                                  |
| Rehearsals                             | unaffected                                                  |
| Setlists / Catalog                     | **affected** — `ensure_catalog_setlist` authorization logic |
| Members / RBAC                         | unaffected — membership check logic preserved               |
| Auth / Session                         | unaffected                                                  |
| Routing                                | unaffected                                                  |
| Notifications                          | unaffected                                                  |
| Platform (iOS / Android / Web / macOS) | unaffected — server-side fix only                           |

## Regression Risk

**Overall risk:** `LOW`

**Rationale:**

- Single function body change
- Bypass clause is narrowly scoped: only applies when (1) `pg_trigger_depth() > 0` (inside trigger context) AND (2) caller is band's `created_by` AND (3) zero `band_members` rows exist for that band
- Direct RPC calls can never satisfy the bypass, even for creators of zero-member bands — only the nested call from `trigger_auto_create_catalog` during `create_band` can
- All existing authorization checks remain active unchanged
- No changes to trigger architecture, RLS policies, client code, or other RPCs
- Database-only change — no cross-platform concerns
- The bypass window is mechanically restricted to the synchronous trigger call during band creation

**Mitigating factors:**

- Verification plan includes Tier 2 test confirming bypass only works during band creation (before first member row exists)
- QA regression testing will confirm existing bands' catalog operations still require active membership
- The bypass logic is explicit and commented in the migration

## Engineer Task Breakdown

### Task 1: Generate migration timestamp and create migration file

Generate timestamp:

```bash
date -u +"%Y%m%d%H%M%S"
```

Create file at `supabase/migrations/<timestamp>_fix_ensure_catalog_band_creation_race.sql` with the following structure:

```sql
-- ===========================================================================
-- Migration: Fix ensure_catalog_setlist band creation race condition
-- Description: Extends authorization check to allow band creator during
--              trigger execution (before first band_members row exists)
-- Bug: bug/band-create-catalog-trigger-race
-- Root Cause: trigger_auto_create_catalog fires synchronously during bands
--             INSERT, before create_band() inserts creator's membership row
-- Date: 2026-08-24
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if user is an active member of the band
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  -- If not a member, check for band-creation race exception:
  -- Allow if (1) we're in a trigger context AND (2) caller is band creator AND (3) no membership rows exist yet
  -- (this handles the trigger_auto_create_catalog race during create_band)
  -- The pg_trigger_depth() > 0 check ensures this bypass ONLY works during trigger execution,
  -- not for direct RPC calls from clients (closes re-introduction of cross-tenant tampering hole)
  IF NOT v_is_member THEN
    SELECT
      pg_trigger_depth() > 0
      AND EXISTS(SELECT 1 FROM bands WHERE id = p_band_id AND created_by = v_user_id)
      AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)
    INTO v_is_member;
  END IF;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ===========================================================================
  -- CATALOG LOGIC (unchanged from 20260822120101)
  -- ===========================================================================

  -- Check how many Catalogs exist for this band
  SELECT COUNT(*) INTO catalog_count
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- If exactly one exists, return it
  IF catalog_count = 1 THEN
    SELECT id INTO catalog_id
    FROM public.setlists
    WHERE band_id = p_band_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
    LIMIT 1;

    -- Ensure metadata is correct
    UPDATE public.setlists
    SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
    WHERE id = catalog_id AND (name != 'Catalog' OR setlist_type != 'catalog' OR is_catalog != true);

    RETURN catalog_id;
  END IF;

  -- If none exists, create one
  IF catalog_count = 0 THEN
    INSERT INTO public.setlists (band_id, name, setlist_type, is_catalog, total_duration)
    VALUES (p_band_id, 'Catalog', 'catalog', true, 0)
    RETURNING id INTO catalog_id;

    RETURN catalog_id;
  END IF;

  -- If multiple exist, keep the oldest one and merge songs from others
  SELECT id, name INTO oldest_catalog
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  ORDER BY created_at ASC
  LIMIT 1;

  catalog_id := oldest_catalog.id;

  -- Move songs from duplicate Catalogs to the primary one
  INSERT INTO public.setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
  SELECT
    catalog_id,
    ss.song_id,
    COALESCE((SELECT MAX(position) FROM public.setlist_songs WHERE setlist_id = catalog_id), 0) + ROW_NUMBER() OVER (ORDER BY ss.position),
    ss.bpm,
    ss.tuning,
    ss.duration_seconds
  FROM public.setlist_songs ss
  JOIN public.setlists sl ON ss.setlist_id = sl.id
  WHERE sl.band_id = p_band_id
    AND sl.id != catalog_id
    AND (sl.setlist_type = 'catalog' OR sl.is_catalog = true OR LOWER(sl.name) IN ('catalog', 'all songs'))
    AND NOT EXISTS (
      SELECT 1 FROM public.setlist_songs existing
      WHERE existing.setlist_id = catalog_id AND existing.song_id = ss.song_id
    );

  -- Delete songs from duplicate Catalogs
  DELETE FROM public.setlist_songs
  WHERE setlist_id IN (
    SELECT id FROM public.setlists
    WHERE band_id = p_band_id
      AND id != catalog_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  );

  -- Delete duplicate Catalogs
  DELETE FROM public.setlists
  WHERE band_id = p_band_id
    AND id != catalog_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- Ensure primary Catalog has correct metadata
  UPDATE public.setlists
  SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
  WHERE id = catalog_id;

  RETURN catalog_id;
END;
$function$;

-- ===========================================================================
-- ACL: No changes — preserve existing grants
-- (authenticated has EXECUTE from prior migrations, anon was already revoked)
-- ===========================================================================

-- ===========================================================================
-- VERIFICATION QUERY (run after deploy)
-- Confirm function body contains the band-creation bypass clause
-- ===========================================================================
-- SELECT pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
--   LIKE '%created_by = v_user_id%' AS has_bypass_clause;
-- Expected: true
```

### Task 2: Validate migration syntax

Validate SQL syntax by inspection (no local CLI available). Confirm:

- All function signatures match existing `ensure_catalog_setlist(uuid)`
- `pg_trigger_depth()` condition is present in bypass clause
- Migration follows established comment header format

### Task 3: Document completion

Create `ENGINEER_REPORT.md` in `docs/features/band-create-catalog-trigger-race/` with:

- Tasks completed
- Migration file path and timestamp
- Confirmation that migration syntax was validated
- Statement that no Flutter code changes were made
- Reference to Verification Plan for branch-based deployment testing

## Verification Plan

### Tier 1 — Pre-deployment (before branch creation)

**Context:** All Tier 1 tests run against the current production database state (before the new migration is applied). The current `ensure_catalog_setlist` still has the 2026-08-22 authorization check with no bypass clause. These tests confirm supporting infrastructure exists and is correct.

**Test 1.1:** Verify `create_band` function exists and contains expected statement order

```sql
-- PRE-DEPLOY TEST 1.1: Verify create_band function structure
SELECT
  pg_get_functiondef('public.create_band(text, text, text)'::regprocedure)::text
  LIKE '%INSERT INTO bands%RETURNING id INTO v_band_id%'
  AND pg_get_functiondef('public.create_band(text, text, text)'::regprocedure)::text
  LIKE '%INSERT INTO band_members%'
AS has_expected_structure;
-- Expected: true
```

**Test 1.2:** Verify trigger `trigger_auto_create_catalog` exists on `bands` table

```sql
-- PRE-DEPLOY TEST 1.2: Verify auto-catalog trigger exists
SELECT EXISTS(
  SELECT 1 FROM pg_trigger
  WHERE tgname = 'trigger_auto_create_catalog'
    AND tgrelid = 'public.bands'::regclass
) AS trigger_exists;
-- Expected: true
```

**Test 1.3:** Verify `auto_create_catalog_for_band` function exists

```sql
-- PRE-DEPLOY TEST 1.3: Verify trigger function exists
SELECT EXISTS(
  SELECT 1 FROM pg_proc
  WHERE proname = 'auto_create_catalog_for_band'
    AND pronamespace = 'public'::regnamespace
) AS function_exists;
-- Expected: true
```

**Test 1.4:** Verify current `ensure_catalog_setlist` has the 2026-08-22 membership check

```sql
-- PRE-DEPLOY TEST 1.4: Verify current function has membership check
SELECT
  pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%Access denied: not an active member of this band%'
AS has_membership_check;
-- Expected: true (confirms we're fixing the right function)
```

**All Tier 1 tests must pass before proceeding to branch creation.**

---

### Tier 2 — Post-deployment (after migration applied to branch)

**Context:** The new migration is now applied. `ensure_catalog_setlist` has the band-creation bypass clause. These tests verify the fix works and does not regress security.

**Test 2.1:** Verify new function body contains bypass clause

```sql
-- POST-DEPLOY TEST 2.1: Verify bypass clause was added
SELECT
  pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%created_by = v_user_id%'
  AND pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)%'
AS has_bypass_clause;
-- Expected: true
```

**Test 2.2:** Verify `create_band` succeeds end-to-end (the fix)

```sql
-- POST-DEPLOY TEST 2.2: Create a band and verify catalog is auto-created
DO $$
DECLARE
  test_band_id UUID;
  test_catalog_id UUID;
  test_member_count INT;
BEGIN
  -- Create a test band (this should now succeed)
  SELECT public.create_band('Test Band ' || gen_random_uuid()::text, '#F43F5E', NULL)
  INTO test_band_id;

  -- Verify band was created
  IF NOT EXISTS(SELECT 1 FROM bands WHERE id = test_band_id) THEN
    RAISE EXCEPTION 'Band creation failed';
  END IF;

  -- Verify creator was added as admin member
  SELECT COUNT(*) INTO test_member_count
  FROM band_members
  WHERE band_id = test_band_id AND user_id = auth.uid() AND status = 'active' AND role = 'admin';

  IF test_member_count != 1 THEN
    RAISE EXCEPTION 'Creator membership not created (expected 1, got %)', test_member_count;
  END IF;

  -- Verify Catalog setlist was auto-created by trigger
  SELECT id INTO test_catalog_id
  FROM setlists
  WHERE band_id = test_band_id AND setlist_type = 'catalog' AND is_catalog = true;

  IF test_catalog_id IS NULL THEN
    RAISE EXCEPTION 'Catalog setlist not auto-created';
  END IF;

  -- Cleanup: delete test data
  DELETE FROM band_members WHERE band_id = test_band_id;
  DELETE FROM setlists WHERE band_id = test_band_id;
  DELETE FROM bands WHERE id = test_band_id;

  RAISE NOTICE 'Test 2.2 PASSED: create_band succeeded, catalog auto-created';
END $$;
-- Expected: NOTICE "Test 2.2 PASSED"
```

**Test 2.3:** Verify bypass does NOT work for direct RPC calls from creator of abandoned band (pg_trigger_depth security check)

```sql
-- POST-DEPLOY TEST 2.3: Verify pg_trigger_depth() blocks direct calls to bypass
-- After the fix, a direct call to ensure_catalog_setlist from the creator of a
-- zero-member band MUST raise 'Access denied', because pg_trigger_depth() = 0
-- for direct calls (not in trigger context).
DO $$
DECLARE
  test_band_id UUID;
  test_user_id UUID;
  call_succeeded BOOLEAN := FALSE;
BEGIN
  test_user_id := auth.uid();

  -- Create a test band (should succeed via normal flow)
  SELECT public.create_band('Abandoned Band Security Test ' || gen_random_uuid()::text, '#F43F5E', NULL)
  INTO test_band_id;

  -- Verify band was created with creator as admin
  IF NOT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = test_band_id AND user_id = test_user_id AND status = 'active' AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Test setup failed: creator not added as admin';
  END IF;

  -- Simulate abandonment: remove all members (including creator)
  DELETE FROM band_members WHERE band_id = test_band_id;

  -- Verify band now has zero members
  IF EXISTS(SELECT 1 FROM band_members WHERE band_id = test_band_id) THEN
    RAISE EXCEPTION 'Test setup failed: band still has members after delete';
  END IF;

  -- Verify creator relationship is intact
  IF NOT EXISTS(SELECT 1 FROM bands WHERE id = test_band_id AND created_by = test_user_id) THEN
    RAISE EXCEPTION 'Test setup failed: creator relationship lost';
  END IF;

  -- NOW THE CRITICAL TEST:
  -- Try to call ensure_catalog_setlist directly (not via trigger)
  -- Bypass conditions: pg_trigger_depth() > 0 (FALSE for direct call)
  --                    created_by = v_user_id (TRUE)
  --                    NOT EXISTS(band_members) (TRUE)
  -- Result: bypass should NOT fire because pg_trigger_depth() = 0
  -- Expected: 'Access denied: not an active member of this band'
  BEGIN
    PERFORM public.ensure_catalog_setlist(test_band_id);
    call_succeeded := TRUE;  -- Should not reach here
  EXCEPTION
    WHEN OTHERS THEN
      -- Expected exception
      IF SQLERRM NOT LIKE '%Access denied%' AND SQLERRM NOT LIKE '%not an active member%' THEN
        -- Cleanup before re-raising
        DELETE FROM setlists WHERE band_id = test_band_id;
        DELETE FROM bands WHERE id = test_band_id;
        RAISE EXCEPTION 'Test 2.3 FAILED: Got unexpected exception: %', SQLERRM;
      END IF;
      -- Correct exception received
  END;

  -- Verify the call actually failed
  IF call_succeeded THEN
    -- Cleanup
    DELETE FROM setlists WHERE band_id = test_band_id;
    DELETE FROM bands WHERE id = test_band_id;
    RAISE EXCEPTION 'Test 2.3 FAILED: Direct call to ensure_catalog_setlist succeeded for creator of abandoned band (bypass should be blocked by pg_trigger_depth() = 0)';
  END IF;

  -- Cleanup
  DELETE FROM setlists WHERE band_id = test_band_id;
  DELETE FROM bands WHERE id = test_band_id;

  RAISE NOTICE 'Test 2.3 PASSED: Direct call from creator of abandoned band correctly denied (pg_trigger_depth() = 0 blocks bypass)';
END $$;
-- Expected: NOTICE "Test 2.3 PASSED"
-- This test confirms the pg_trigger_depth() fix prevents the cross-tenant tampering hole
-- from re-opening when a band's membership drains to zero post-creation.
```

**Test 2.4:** Production verification — confirm no bad data exists

```sql
-- POST-DEPLOY TEST 2.4: Verify no orphaned bands exist (bands with 0 members)
-- since 2026-08-22 12:52 UTC (when bug started)
SELECT
  b.id,
  b.name,
  b.created_at,
  b.created_by,
  (SELECT COUNT(*) FROM band_members WHERE band_id = b.id) AS member_count
FROM bands b
WHERE b.created_at >= '2026-08-22 12:52:00+00'::timestamptz
  AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = b.id)
ORDER BY b.created_at DESC;
-- Expected: 0 rows (all create_band calls failed completely, no partial data)
```

**Test 2.5:** Verify existing bands' catalog operations still require membership

```sql
-- POST-DEPLOY TEST 2.5: Verify authorization works for existing bands
-- Pick any existing band and verify ensure_catalog_setlist succeeds for a member
DO $$
DECLARE
  test_band_id UUID;
  test_user_id UUID;
BEGIN
  test_user_id := auth.uid();

  -- Find a band where current user is an active member
  SELECT band_id INTO test_band_id
  FROM band_members
  WHERE user_id = test_user_id AND status = 'active'
  LIMIT 1;

  IF test_band_id IS NULL THEN
    RAISE NOTICE 'Test 2.5 SKIPPED: current user is not a member of any band';
    RETURN;
  END IF;

  -- Call ensure_catalog_setlist (should succeed)
  BEGIN
    PERFORM public.ensure_catalog_setlist(test_band_id);
    RAISE NOTICE 'Test 2.5 PASSED: ensure_catalog_setlist succeeded for member of existing band';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Test 2.5 FAILED: ensure_catalog_setlist failed for active member: %', SQLERRM;
  END;
END $$;
-- Expected: NOTICE "Test 2.5 PASSED" or "Test 2.5 SKIPPED"
```

**All Tier 2 tests must pass before QA proceeds.**

## QA Regression Areas

QA must test the following in production (after branch merge to production and Tier 2 verification pass):

### Primary: Band Creation Flow (All Platforms)

1. **Create new band (happy path):**
   - Web: Tap "+" → Create Band → enter name → Create
   - iOS: Tap "+" → Create Band → enter name → Create
   - Android: Tap "+" → Create Band → enter name → Create
   - macOS: Tap "+" → Create Band → enter name → Create
   - **Expected:** Band is created, user is navigated to new band, Catalog setlist exists, no error

2. **Verify catalog auto-created:**
   - After creating band, navigate to Setlists tab
   - **Expected:** "Catalog" setlist is present with type "catalog"

3. **Verify creator is admin:**
   - After creating band, navigate to Members tab
   - **Expected:** Creator appears with "Admin" role badge

### Regression: Existing Band Catalog Operations

4. **Call ensure_catalog_setlist for existing band (client-side):**
   - Use existing band with active membership
   - Navigate to Setlists tab
   - Tap on Catalog setlist (this may trigger `ensure_catalog_setlist` if Catalog is missing)
   - **Expected:** No error, catalog loads normally

5. **Add song to Catalog:**
   - In existing band, add a song to Catalog setlist
   - **Expected:** Song is added successfully, no authorization error

### Regression: Authorization Security

6. **Verify non-members cannot tamper:**
   - Specifically: verify creator of an abandoned (zero-member) band cannot call `ensure_catalog_setlist` via direct RPC
   - Covered by Tier 2 Test 2.3 (executable SQL test)
   - Test 2.3 confirms `pg_trigger_depth() = 0` for direct calls blocks the bypass
   - QA note: Authorization checks working correctly per Tier 2 verification (Test 2.3 PASSED)

### Edge Cases

7. **Create band with special characters in name:**
   - Create band named `Test's "Band" & More`
   - **Expected:** Band created successfully, Catalog exists

8. **Create band then immediately delete it:**
   - Create band → navigate to Settings → Delete Band
   - **Expected:** No orphaned Catalog or membership rows

## Rollout / Migration Strategy

**Branch-based verification required before production deployment** (per sibling bug `bug/rls-migration-comment-escaping` lesson learned — that bug broke production today because migration wasn't execution-verified before deploy). Org upgraded to Pro today to enable Supabase managed branching.

Deploy sequence:

### Phase 1: Pre-Deployment Preparation

1. **Engineer completes Tier 1 verification** against current production database (before migration applied)
2. **Engineer commits** migration file to `bug/band-create-catalog-trigger-race` branch
3. **QA reviews** migration file in PR
4. **Manager approves** migration for branch testing

### Phase 2: Supabase Branch Verification

5. **Confirm cost with Tony:** Use `confirm_cost` (or show Tony ~$0.01344/hr estimate) and verify budget approval before creating branch
6. **Engineer creates Supabase branch** off current production project:
   - Use Supabase MCP tool: `create_branch` with project_id `nekwjxvgbveheooyorjo`, branch name `band-catalog-race-fix`
   - Tool returns new branch's project_id for subsequent operations
7. **Engineer applies migration to branch:**
   - Use Supabase MCP tool: `apply_migration` targeting the branch's project_id (from step 6)
   - Provide migration file path: `supabase/migrations/<timestamp>_fix_ensure_catalog_band_creation_race.sql`
8. **Engineer runs ALL Tier 1 and Tier 2 verification queries** against the branch's project_id:
   - Use Supabase MCP tool: `execute_sql` for each verification query (Tests 1.1-1.4, 2.1-2.5)
   - Target: branch's project_id from step 6
   - **Critical:** Test 2.3 must PASS (direct call from creator of abandoned band must fail)
9. **If any test fails:** Diagnose on branch, fix migration, re-apply to branch via `apply_migration`, re-test. Do NOT proceed to production.
10. **If all tests pass on branch:** Proceed to Phase 3

### Phase 3: Production Deployment

11. **Engineer merges branch to production:**

- Use Supabase MCP tool: `merge_branch` targeting branch `band-catalog-race-fix`
- This promotes the exact verified branch state (migration + tests) into production
- **DO NOT apply migration separately to production** — `merge_branch` is the deployment

12. **Engineer re-runs Tier 2 verification queries** against production project_id `nekwjxvgbveheooyorjo` to confirm:

- Use Supabase MCP tool: `execute_sql` for Tests 2.1, 2.2, 2.3, 2.4
- Target: production project_id `nekwjxvgbveheooyorjo`

13. **If Tier 2 fails on production:** Execute rollback plan immediately (see below)
14. **If Tier 2 passes on production:** Delete the Supabase branch, QA proceeds with regression testing

### Phase 4: Branch Cleanup

15. **Engineer deletes Supabase branch** (stop billing):

- Use Supabase MCP tool: `delete_branch` for branch `band-catalog-race-fix`

16. **QA proceeds** with full regression testing per QA Regression Areas

**Rollback procedure** (if Tier 2 fails on production):

```sql
-- EMERGENCY ROLLBACK: Restore function to 2026-08-22 state (no bypass clause)
-- This reverts the fix, re-breaking band creation, but restores known state

CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- [rest of function body unchanged from 20260822120101]
  -- [omitted for brevity — copy full body from that migration]

END;
$function$;
```

**Note:** Band creation will remain broken until the fix is re-applied or an alternative solution is deployed.

## Out of Scope

1. **Reworking trigger architecture** — not required, bypass clause solves the race surgically
2. **Changing `create_band` function** — not required, band creation flow is correct
3. **Client-side error handling changes** — not required, generic error message is appropriate for all unrecognized errors
4. **Deferred constraint trigger conversion** — not required, bypass clause is simpler and safer
5. **RLS policy changes** — not applicable, this is a SECURITY DEFINER function authorization issue, not an RLS issue
6. **ACL grant changes** — not required, grants are correct (authenticated has EXECUTE, anon does not)
7. **Other RPCs or triggers** — not affected, this bug is isolated to `ensure_catalog_setlist` band-creation race
