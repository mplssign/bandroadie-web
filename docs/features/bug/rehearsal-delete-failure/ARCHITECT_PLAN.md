# ARCHITECT PLAN — bug/rehearsal-delete-failure

**Feature Slug:** `bug/rehearsal-delete-failure`
**Feature Type:** bug
**Date:** 2026-03-06
**Branch:** `bug/rehearsal-delete-failure` (to be created by Engineer from `main`)

---

## 1. Problem Summary

Users cannot delete rehearsals. The UI displays "Please check your input and
try again" and the rehearsal remains in the database.

### Background

A previous fix cycle (`feature/rehearsal-deletion-fails`) correctly diagnosed
the root cause: the RBAC migration (`20260302000000_band_user_roles.sql`)
dropped RLS policies for gigs, setlists, and bands — but **skipped rehearsals
entirely**, leaving them with missing or broken policies.

That cycle produced:

- `20260305100000_fix_rehearsal_rls_and_trigger.sql` — restores 4 rehearsal RLS policies + fixes trigger
- `20260306000000_fix_delete_band_missing_rehearsals.sql` — patches `delete_band()` RPC

However, **deploying these fixes triggered a cascade of 5 additional emergency
hotfix migrations** to address collateral damage on the `band_members` table:

| #   | Migration        | Problem Fixed                                                              | New Problem Introduced                                                             |
| --- | ---------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 1   | `20260306100000` | band_members policies reference stale `'owner'` enum value                 | Self-referencing SELECT policy too restrictive (`status='active'` blocks own rows) |
| 2   | `20260306200000` | Users locked out — can't see own memberships                               | Self-referencing SELECT subquery remains on band_members                           |
| 3   | `20260307000000` | Stale `'owner'` policies remain across ALL tables                          | May have dropped band_members SELECT policies during cleanup                       |
| 4   | `20260307100000` | band_members SELECT policies missing after cleanup; PostgREST cache stale  | Re-introduces self-referencing SELECT on band_members                              |
| 5   | `20260307200000` | Infinite recursion (ERROR 42P17) from self-referencing band_members SELECT | Introduces `is_band_member()` SECURITY DEFINER helper — **resolves recursion**     |

**Current state:** The 5 hotfix migrations are **untracked in git** (applied
directly to production). Two Flutter files have uncommitted debug `print()`
statements. The rehearsal deletion bug persists because the full migration
chain has not been consolidated and properly deployed.

---

## 2. Existing System Analysis

### 2.1 Flutter Deletion Flow

**UI Layer — `lib/features/events/widgets/event_editor_drawer.dart`:**

- `_handleDelete(deleteEntireSeries:)` — entry point for all deletion
- Permission guard uses `canDeleteGigs` (shared gig/rehearsal permission)
- Calls `repository.deleteRehearsal()` or `repository.deleteRehearsalSeries()`
- Catch block (currently with debug `debugPrint`) maps errors via
  `mapEventErrorToMessage(error, context: 'delete')`
- Contains uncommitted debug logging that should be removed

**Repository Layer — `lib/features/events/events_repository.dart`:**

- `deleteRehearsal(rehearsalId, bandId)` → `supabase.from('rehearsals').delete().eq('id', ...).eq('band_id', ...)`
- `deleteRehearsalSeries(rehearsalId, bandId, parentRehearsalId?)` — two-strategy: parent-child FK then pattern-matching fallback
- `deleteGig(gigId, bandId)` → `.from('gigs').delete()` — **WORKS** (gig policies are correct)
- No error wrapping — exceptions propagate directly to UI catch block

**Error Classification — `lib/shared/utils/event_permission_helper.dart`:**

- `classifyError()` scans `error.toString().toLowerCase()` for keywords
- `'invalid'` or `'required'` → `EventErrorType.validation` → "Please check your input and try again."
- A PostgreSQL/PostgREST error containing `'invalid'` (e.g., "invalid input value for enum band_role_type") hits this path
- This is a **misclassification**: the actual error is a database policy/enum failure, not a user validation error

**Band Repository — `lib/features/bands/band_repository.dart`:**

- `fetchUserBands()` has a `catch (e) { return []; }` that silently swallows all errors
- Contains uncommitted debug `print()` statements added during hotfix troubleshooting
- The silent catch masked the infinite recursion error (42P17) making it appear users had no bands

### 2.2 Database Layer

**Rehearsals Table Schema:**

| Column                 | Type      | Constraints                            |
| ---------------------- | --------- | -------------------------------------- |
| `id`                   | UUID      | PRIMARY KEY                            |
| `band_id`              | UUID      | NOT NULL, FK → bands(id)               |
| `date`                 | DATE      |                                        |
| `start_time`           | TEXT      |                                        |
| `end_time`             | TEXT      |                                        |
| `location`             | TEXT      |                                        |
| `notes`                | TEXT      | nullable                               |
| `setlist_id`           | UUID      | nullable, FK → setlists(id)            |
| `is_recurring`         | BOOLEAN   | DEFAULT FALSE                          |
| `recurrence_frequency` | TEXT      | nullable                               |
| `recurrence_days`      | INTEGER[] | nullable                               |
| `recurrence_until`     | DATE      | nullable                               |
| `parent_rehearsal_id`  | UUID      | FK → rehearsals(id) ON DELETE SET NULL |

**Triggers:** `rehearsal_created_notification` — AFTER INSERT only (not affected by DELETE)

**RLS:** ENABLED on `rehearsals`. Current policy state depends on which migrations have been applied (see §3).

### 2.3 Migration Timeline (Critical Sequence)

| Migration                                                | Date  | Status                              | Effect on Rehearsals                                                                  |
| -------------------------------------------------------- | ----- | ----------------------------------- | ------------------------------------------------------------------------------------- |
| `20260302000000_band_user_roles.sql`                     | 03-02 | **Deployed**                        | RBAC migration — skipped rehearsals; dropped policies dynamically                     |
| `20260305000000_band_scoped_calendar.sql`                | 03-05 | Deployed                            | Unrelated (calendar feeds)                                                            |
| `20260305100000_fix_rehearsal_rls_and_trigger.sql`       | 03-05 | **Committed, deployment uncertain** | Restores 4 rehearsal RLS policies + fixes trigger                                     |
| `20260306000000_fix_delete_band_missing_rehearsals.sql`  | 03-06 | **Committed, deployment uncertain** | Patches `delete_band()` to include rehearsal cleanup                                  |
| `20260306100000_fix_band_members_rls_owner_enum.sql`     | 03-06 | **Untracked**                       | Drops all band_members policies, recreates with self-referencing SELECT               |
| `20260306200000_hotfix_band_members_select_policy.sql`   | 03-06 | **Untracked**                       | Splits band_members SELECT into own-rows + co-members (still self-referencing)        |
| `20260307000000_fix_stale_owner_policies_all_tables.sql` | 03-07 | **Untracked**                       | Drops all policies with 'owner'; recreates SELECT on many tables including rehearsals |
| `20260307100000_ensure_band_visibility_and_notify.sql`   | 03-07 | **Untracked**                       | Re-establishes band_members SELECT/INSERT/UPDATE + PostgREST cache reload             |
| `20260307200000_fix_band_members_infinite_recursion.sql` | 03-07 | **Untracked**                       | Creates `is_band_member()` SECURITY DEFINER; replaces self-referencing policies       |

### 2.4 Working vs Failing Path Comparison

| Aspect                       | Gig Delete (WORKS)                | Rehearsal Delete (FAILS)                   |
| ---------------------------- | --------------------------------- | ------------------------------------------ |
| Repository method            | `deleteGig()`                     | `deleteRehearsal()`                        |
| Supabase call                | `.from('gigs').delete().eq(...)`  | `.from('rehearsals').delete().eq(...)`     |
| DELETE RLS policy after RBAC | **Present** (Phase 4 of 20260302) | **Missing** (not in 20260302)              |
| FK self-reference            | None                              | `parent_rehearsal_id` → ON DELETE SET NULL |

---

## 3. Root Cause

### 3.1 Failure Layer Analysis

| Layer               | Assessment     | Reasoning                                                             |
| ------------------- | -------------- | --------------------------------------------------------------------- |
| Flutter UI logic    | UNLIKELY       | Same UI pattern used for gigs (which works)                           |
| Controller / state  | UNLIKELY       | No rehearsal-specific state mutation during delete                    |
| Repository          | UNLIKELY       | `deleteRehearsal()` is identical pattern to working `deleteGig()`     |
| Supabase RPC        | NOT APPLICABLE | No RPC used for rehearsal deletion                                    |
| **RLS policy**      | **LIKELY**     | RBAC migration skipped rehearsals; fix migrations may not be deployed |
| Database constraint | POSSIBLE       | `parent_rehearsal_id` ON DELETE SET NULL needs UPDATE policy          |
| Database trigger    | UNLIKELY       | Only INSERT trigger exists                                            |
| Data integrity      | UNLIKELY       | No corruption pattern                                                 |

### 3.2 Primary Failure Surface

**PRIMARY FAILURE SURFACE: RLS Policy**

The RBAC migration (`20260302000000`) is the root origin. It:

1. Dynamically dropped policies matching `'%band_members%' AND '%.role%'`
2. Recreated RBAC-aware policies for gigs, setlists, bands
3. **Never recreated** any policies for rehearsals

The fix migration `20260305100000` was created to restore rehearsal policies,
but its deployment status is uncertain. Even if deployed, subsequent hotfix
migrations (`20260307000000`) drop and recreate the rehearsal SELECT policy
(though INSERT/UPDATE/DELETE should survive).

### 3.3 Evidence

1. **RBAC migration contains ZERO references to "rehearsals"** — confirmed via grep
2. **Gig deletion works** — gig policies were recreated in RBAC Phase 4
3. **Error message "Please check your input"** maps to `EventErrorType.validation`,
   triggered when PostgREST errors contain `'invalid'` — consistent with enum
   mismatch or missing policy errors
4. **5 cascading hotfix migrations** exist, each fixing problems caused by the previous
5. **Silent `catch (e) { return []; }`** in `band_repository.dart` masked the
   infinite recursion error, making it appear users had no bands
6. **Debug print statements** in modified Flutter files confirm active troubleshooting
   was underway

### 3.4 Potential Root Cause Candidates

1. **Missing rehearsal DELETE/UPDATE/INSERT RLS policies** — If `20260305100000`
   was never deployed, rehearsals have no write policies at all
2. **Missing rehearsal SELECT policy** — If `20260307000000` was deployed but
   `20260305100000` was not, only a SELECT policy exists (no DELETE)
3. **Stale 'owner' enum reference in band_members policies** causes all
   `band_members` subqueries to fail — would break ALL RLS checks for all tables
4. **Infinite recursion (42P17) in band_members** kills all queries that
   subquery band_members — would break rehearsal AND gig deletion (but gig
   deletion reportedly works, suggesting this was resolved)

### 3.5 Root Cause (Most Likely)

**The rehearsal DELETE RLS policy is missing or broken in production.** The most
likely scenario is that `20260305100000` (which creates the rehearsal DELETE
policy) was either:

(a) Never deployed, or
(b) Deployed but its policies were partially overwritten by later hotfix
migrations (specifically `20260307000000` which only recreates SELECT)

In either case, the rehearsal table lacks a DELETE policy, causing
`supabase.from('rehearsals').delete()` to either silently delete 0 rows or
throw a PostgrestException containing 'invalid', which gets misclassified as
a validation error.

### 3.6 Minimal Reproduction Query

```sql
-- Step 1: Check current policy state
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'rehearsals';

-- Expected if fully fixed: 4 rows (SELECT, INSERT, UPDATE, DELETE)
-- If broken: 0-1 rows (missing DELETE at minimum)

-- Step 2: Attempt deletion as authenticated user
DELETE FROM rehearsals
WHERE id = '<test-rehearsal-id>'
AND band_id = '<test-band-id>';
```

---

## 4. Proposed Solution

### 4.1 Strategy: Single Consolidated Migration

Rather than deploying 7 incremental fix migrations (2 committed + 5 untracked)
which creates fragility and audit risk, create **one consolidated migration**
that establishes the correct final state for all affected tables.

This migration will be **idempotent** (safe to run regardless of which hotfixes
have already been applied) by using `DROP POLICY IF EXISTS` + `CREATE POLICY`
and `CREATE OR REPLACE FUNCTION` patterns.

### 4.2 Solution Components

**Component 1: Consolidated Database Migration**

One new migration that:

1. Creates `is_band_member()` SECURITY DEFINER helper (if not exists)
2. Establishes correct `band_members` RLS policies (no self-referencing)
3. Establishes correct `bands` SELECT policy using `is_band_member()`
4. Restores all 4 rehearsal RLS policies (SELECT, INSERT, UPDATE, DELETE)
5. Patches `delete_band()` RPC to include rehearsal cleanup
6. Fixes `notify_rehearsal_created()` trigger
7. Issues `NOTIFY pgrst, 'reload schema'`

**Component 2: Remove Debug Code from Flutter**

Revert the uncommitted debug `print()` and `debugPrint()` statements in:

- `band_repository.dart` — remove 5 debug print lines + restore original formatting
- `event_editor_drawer.dart` — remove 6 debug print lines in catch block

**Component 3: Delete Stale Hotfix Migrations**

Remove the 5 untracked migration files that are superseded by the consolidated
migration. Also remove the 2 committed fix migrations that will be superseded:

- `20260305100000_fix_rehearsal_rls_and_trigger.sql`
- `20260306000000_fix_delete_band_missing_rehearsals.sql`
- `20260306100000_fix_band_members_rls_owner_enum.sql`
- `20260306200000_hotfix_band_members_select_policy.sql`
- `20260307000000_fix_stale_owner_policies_all_tables.sql`
- `20260307100000_ensure_band_visibility_and_notify.sql`
- `20260307200000_fix_band_members_infinite_recursion.sql`

These are replaced by the single consolidated migration.

### 4.3 Why Consolidation Over Incremental

- 7 sequential fix migrations are brittle and order-dependent
- Each hotfix was reactive (fixing the previous fix)
- Production state is unknown — we don't know which of the 7 were applied
- A single idempotent migration handles ALL production states correctly
- Reduces audit surface from 7 files to 1 file
- Eliminates the risk of partial application

---

## 5. Database Impact

### 5.1 Tables Affected

| Table          | Impact                                                              |
| -------------- | ------------------------------------------------------------------- |
| `rehearsals`   | RLS policies dropped and recreated (SELECT, INSERT, UPDATE, DELETE) |
| `band_members` | SELECT policies replaced with non-recursive versions                |
| `bands`        | SELECT policy replaced to use `is_band_member()`                    |
| None           | No schema changes, no column additions, no new tables               |

### 5.2 Functions Created/Updated

| Function                     | Action                                                  |
| ---------------------------- | ------------------------------------------------------- |
| `is_band_member(UUID)`       | CREATE OR REPLACE — SECURITY DEFINER helper             |
| `delete_band(UUID)`          | CREATE OR REPLACE — add missing rehearsal cleanup       |
| `notify_rehearsal_created()` | CREATE OR REPLACE — fix column name + exception handler |

### 5.3 Data Impact

- **No data modified or deleted** by the migration
- Policy changes are immediate and affect all subsequent queries
- Function replacements are atomic

### 5.4 Rollback Risk

LOW. All operations use `DROP IF EXISTS` + `CREATE` or `CREATE OR REPLACE`.
Individual policies can be dropped and recreated if issues arise.

---

## 6. RLS / RPC Changes

### 6.1 `is_band_member()` Helper Function

```
FUNCTION: is_band_member(p_band_id UUID) RETURNS BOOLEAN
LANGUAGE: sql, STABLE, SECURITY DEFINER
SET search_path = public
GRANT: authenticated role

Purpose: Checks if auth.uid() is a member of the given band.
         Bypasses RLS (SECURITY DEFINER) to prevent infinite recursion
         when used inside band_members policies.
```

### 6.2 band_members Policies (Final State)

| Policy Name                               | Command | Condition                                                      |
| ----------------------------------------- | ------- | -------------------------------------------------------------- |
| "Users can view own memberships"          | SELECT  | `user_id = auth.uid()`                                         |
| "Active members can view band co-members" | SELECT  | `public.is_band_member(band_id)`                               |
| "Band members can insert band members"    | INSERT  | existing active member OR self-insert (`user_id = auth.uid()`) |
| "Admins can update band members"          | UPDATE  | admin via `is_band_member` + role check                        |
| (no DELETE policy)                        | —       | Handled by `remove_band_member()` RPC                          |

**CRITICAL:** No self-referencing subqueries on band_members. All membership
checks use `is_band_member()` or direct `user_id = auth.uid()`.

### 6.3 bands Policies (Final State)

| Policy Name                   | Command | Condition                   |
| ----------------------------- | ------- | --------------------------- |
| "Band members can view bands" | SELECT  | `public.is_band_member(id)` |

(Other bands policies — INSERT, UPDATE, DELETE — are unchanged from RBAC migration.)

### 6.4 rehearsals Policies (Final State)

| Policy Name                                | Command | Condition                                     |
| ------------------------------------------ | ------- | --------------------------------------------- |
| "Band members can view rehearsals"         | SELECT  | Active member via `band_members` subquery     |
| "Admins and members can create rehearsals" | INSERT  | Admin/member role via `band_members` subquery |
| "Admins and members can update rehearsals" | UPDATE  | Admin/member role (USING + WITH CHECK)        |
| "Admins and members can delete rehearsals" | DELETE  | Admin/member role via `band_members` subquery |

These policies subquery `band_members` — this is safe because it's
cross-table (not self-referencing). PostgreSQL evaluates `band_members` RLS
for the subquery, which uses `is_band_member()` (no recursion).

### 6.5 delete_band() RPC (Patched)

Add `DELETE FROM public.rehearsals WHERE band_id = band_uuid` to the cascade
sequence, before gigs deletion. Preserves admin-only permission check.

### 6.6 notify_rehearsal_created() Trigger (Fixed)

- Uses `first_name` (correct column) instead of non-existent `name`
- Exception handler wraps entire body — trigger never blocks inserts
- AFTER INSERT only — does not affect DELETE

---

## 7. Flutter Architecture Changes

### 7.1 Required Changes

**Remove debug code** from two files:

- `lib/features/bands/band_repository.dart` — revert to committed version
  (`f056f72`): remove 5 `print()` statements, restore original formatting
- `lib/features/events/widgets/event_editor_drawer.dart` — revert catch block
  to committed version: remove 6 `debugPrint()` statements in catch block

### 7.2 No Architectural Changes

The Flutter deletion flow, repository methods, error classification, and UI
are all correctly implemented. The bug is entirely at the database layer.

### 7.3 Out-of-Scope Improvements (Do Not Implement)

- `classifyError()` could better distinguish database policy errors from
  validation errors — track separately
- `fetchUserBands()` silently swallows errors with `catch (e) { return []; }`
  — track separately
- `canDeleteGigs` permission is shared for rehearsals — a dedicated
  `canDeleteRehearsals` could be added — track separately

---

## 8. Exact Files to Create

| File                                                                         | Purpose                                                     |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `supabase/migrations/20260308000000_consolidate_rls_and_rehearsal_fixes.sql` | Single consolidated migration replacing 7 incremental fixes |

---

## 9. Exact Files to Modify

| File                                                   | Modification                                                   |
| ------------------------------------------------------ | -------------------------------------------------------------- |
| `lib/features/bands/band_repository.dart`              | Remove debug `print()` statements; restore original formatting |
| `lib/features/events/widgets/event_editor_drawer.dart` | Remove debug `debugPrint()` statements from catch block        |

### Files to Delete

| File                                                                         | Reason                               |
| ---------------------------------------------------------------------------- | ------------------------------------ |
| `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql`       | Superseded by consolidated migration |
| `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql`  | Superseded by consolidated migration |
| `supabase/migrations/20260306100000_fix_band_members_rls_owner_enum.sql`     | Superseded by consolidated migration |
| `supabase/migrations/20260306200000_hotfix_band_members_select_policy.sql`   | Superseded by consolidated migration |
| `supabase/migrations/20260307000000_fix_stale_owner_policies_all_tables.sql` | Superseded by consolidated migration |
| `supabase/migrations/20260307100000_ensure_band_visibility_and_notify.sql`   | Superseded by consolidated migration |
| `supabase/migrations/20260307200000_fix_band_members_infinite_recursion.sql` | Superseded by consolidated migration |

---

## 10. Risks / Edge Cases

### 10.1 Risks

| Risk                                                            | Severity | Mitigation                                                                        |
| --------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------- |
| Some hotfix migrations applied in production but not all        | MEDIUM   | Consolidated migration is idempotent — safe regardless of current state           |
| PostgREST schema cache stale after policy changes               | MEDIUM   | Migration includes `NOTIFY pgrst, 'reload schema'`                                |
| `band_members` UPDATE policy uses self-referencing subquery     | MEDIUM   | Use `is_band_member()` helper for the admin check too                             |
| Removing committed migrations changes git history               | LOW      | These files are on a feature branch, not `main`                                   |
| `parent_rehearsal_id` ON DELETE SET NULL requires UPDATE policy | LOW      | UPDATE policy is included; PostgreSQL FK cascades typically bypass RLS internally |

### 10.2 Edge Cases

1. **Contributors cannot delete rehearsals** — By design. DELETE policy requires
   `admin` or `member` role.
2. **Recurring series with parent-child FK** — ON DELETE SET NULL safely nullifies
   children's `parent_rehearsal_id`. UPDATE policy covers this.
3. **Rehearsals with setlist references** — Rehearsal holds the FK (`setlist_id`),
   not the other way around. Deleting a rehearsal does not cascade to setlists.
4. **Band deletion cascade order** — Rehearsals deleted before gigs (no FK between them).
5. **`is_band_member()` called from multiple tables' policies** — Function is
   STABLE and SECURITY DEFINER — safe for concurrent access, no recursion risk.

---

## 11. Verification Plan

### 11.1 Pre-Deployment

1. **Query current policy state** on production:

   ```sql
   SELECT tablename, policyname, cmd
   FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename IN ('rehearsals', 'band_members', 'bands')
   ORDER BY tablename, cmd;
   ```

2. **Check if `is_band_member()` exists:**

   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'is_band_member';
   ```

3. **Run `flutter analyze`** — confirm no new issues from debug code removal

### 11.2 Post-Deployment

1. **Verify all expected policies exist:**

   ```sql
   SELECT tablename, policyname, cmd
   FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename IN ('rehearsals', 'band_members', 'bands')
   ORDER BY tablename, cmd;
   ```

   Expected: band_members (2 SELECT, 1 INSERT, 1 UPDATE), bands (1 SELECT),
   rehearsals (1 SELECT, 1 INSERT, 1 UPDATE, 1 DELETE)

2. **Verify no self-referencing policies on band_members:**

   ```sql
   SELECT policyname, qual
   FROM pg_policies
   WHERE tablename = 'band_members'
     AND qual::text LIKE '%band_members%'
     AND qual::text NOT LIKE '%is_band_member%';
   ```

   Expected: 0 rows (only `user_id = auth.uid()` and `is_band_member()` patterns)

3. **Single rehearsal delete** (as admin/member):
   - Create a rehearsal → delete it → confirm removed

4. **Recurring series — "Delete this rehearsal"**:
   - Create recurring series → delete one instance → confirm only that one removed

5. **Recurring series — "Delete entire series"**:
   - Delete entire series → confirm all instances removed

6. **Gig delete regression** — confirm gig deletion still works

7. **Band visibility regression** — confirm users see their bands after login

8. **Band deletion regression** — confirm `delete_band()` cleans up rehearsals

9. **Rehearsal creation** — confirm new rehearsals can be created (trigger test)

### 11.3 Platform Verification

- macOS (primary development platform)
- Web (secondary)

---

## 12. Engineer Task Breakdown

### Task 1: Create Feature Branch

```
git checkout main
git pull origin main
git checkout -b bug/rehearsal-delete-failure
```

### Task 2: Create Consolidated Migration

Create `supabase/migrations/20260308000000_consolidate_rls_and_rehearsal_fixes.sql`

Contents (architectural specification — Engineer writes the SQL):

**Section 1: `is_band_member()` helper**

- `CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id UUID)`
- SECURITY DEFINER, STABLE, `SET search_path = public`
- Returns `EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id AND user_id = auth.uid())`
- `GRANT EXECUTE ON FUNCTION ... TO authenticated`

**Section 2: band_members RLS policies**

- Dynamically drop ALL existing policies on `band_members`
- `ALTER TABLE public.band_members ENABLE ROW LEVEL SECURITY`
- Create SELECT 1: `user_id = auth.uid()` ("Users can view own memberships")
- Create SELECT 2: `public.is_band_member(band_id)` ("Active members can view band co-members")
- Create INSERT: existing active member OR `user_id = auth.uid()` ("Band members can insert band members")
- Create UPDATE: admin via `is_band_member()` + role = 'admin' check ("Admins can update band members")
- No DELETE policy (handled by RPC)

**Section 3: bands SELECT policy**

- `DROP POLICY IF EXISTS "Band members can view bands" ON public.bands`
- Create using `public.is_band_member(id)` — do NOT touch other bands policies

**Section 4: rehearsals RLS policies**

- `ALTER TABLE public.rehearsals ENABLE ROW LEVEL SECURITY`
- Drop all known rehearsal policy names (IF EXISTS)
- Create SELECT: active member subquery on `band_members`
- Create INSERT: admin/member role subquery on `band_members`
- Create UPDATE: admin/member role (USING + WITH CHECK)
- Create DELETE: admin/member role subquery on `band_members`

**Section 5: `delete_band()` RPC**

- `CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)`
- Include `DELETE FROM public.rehearsals WHERE band_id = band_uuid` BEFORE gigs deletion
- Preserve admin-only permission check
- SECURITY DEFINER, `SET search_path = public`

**Section 6: `notify_rehearsal_created()` trigger**

- `CREATE OR REPLACE FUNCTION notify_rehearsal_created()`
- Use `first_name` not `name`
- Wrap entire body in exception handler
- SECURITY DEFINER, `SET search_path = public`

**Section 7: PostgREST cache reload**

- `NOTIFY pgrst, 'reload schema'`

**Section 8: Verification block**

- DO $$ block that counts policies and raises NOTICE/WARNING

### Task 3: Remove Debug Code

- Revert `lib/features/bands/band_repository.dart` to the state at commit `f056f72`
  (remove all `print('DEBUG fetchUserBands...')` lines, restore original formatting)
- Revert `lib/features/events/widgets/event_editor_drawer.dart` catch block
  to the state at commit `f056f72` (remove debug `debugPrint` lines, restore
  `catch (e)` instead of `catch (e, stackTrace)`)

### Task 4: Delete Superseded Migrations

Delete these 7 files:

- `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql`
- `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql`
- `supabase/migrations/20260306100000_fix_band_members_rls_owner_enum.sql`
- `supabase/migrations/20260306200000_hotfix_band_members_select_policy.sql`
- `supabase/migrations/20260307000000_fix_stale_owner_policies_all_tables.sql`
- `supabase/migrations/20260307100000_ensure_band_visibility_and_notify.sql`
- `supabase/migrations/20260307200000_fix_band_members_infinite_recursion.sql`

### Task 5: Run Verification

- `flutter analyze` — 0 errors expected
- Review the consolidated migration for:
  - No self-referencing policies on `band_members`
  - All rehearsal CRUD policies present
  - `is_band_member()` exists and is SECURITY DEFINER
  - `delete_band()` includes rehearsal cleanup
  - `NOTIFY pgrst` at the end

### Task 6: Prepare QA Handoff

Document what was done, what to test, and the exact deployment steps.

---

## 13. Rollout / Migration Strategy

### 13.1 Deployment

1. Deploy `20260308000000_consolidate_rls_and_rehearsal_fixes.sql` to production
2. This single migration handles ALL states — whether none, some, or all of the
   7 previous hotfixes were applied
3. The migration is idempotent: `DROP IF EXISTS` + `CREATE`, `CREATE OR REPLACE`

### 13.2 Post-Deployment

1. Run verification queries from §11.2
2. Test rehearsal deletion on Web and mobile
3. Confirm band visibility unaffected
4. Confirm gig operations unaffected

### 13.3 Rollback

If issues arise:

- Individual policies can be dropped: `DROP POLICY "name" ON table`
- Functions can be replaced: `CREATE OR REPLACE FUNCTION ...`
- No schema changes to roll back
- No data migrations to reverse

---

## 14. Out of Scope

The following are **not** addressed by this plan:

1. **Error classification improvement** — `classifyError()` misclassifies database
   policy errors as validation errors. Should be tracked as a separate improvement.
2. **Silent error swallowing** — `band_repository.dart`'s `catch (e) { return []; }`
   should log or surface errors. Separate concern.
3. **Fine-grained rehearsal permissions** — `canDeleteGigs` is used for rehearsals.
   Adding `canDeleteRehearsals` is a separate feature.
4. **Contributor permissions for rehearsals** — The rehearsal policies follow the
   gig pattern (admin/member only). Contributor rehearsal access is out of scope.
5. **RLS policies on other tables** — Only `rehearsals`, `band_members`, and `bands`
   are touched. Other tables' policies (gigs, setlists, songs) are not modified.
6. **Previous feature docs** — The `docs/features/rehearsal-deletion-fails/` folder
   from the previous fix cycle is preserved as historical reference. Not modified.
