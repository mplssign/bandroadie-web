# ARCHITECT PLAN — rehearsal-deletion-fails

**Feature Slug:** `feature/rehearsal-deletion-fails`
**Feature Type:** bug
**Date:** 2026-03-06
**Branch:** `feature/rehearsal-deletion-fails`

---

## 1. Problem Summary

When a user attempts to delete a rehearsal — either a single event or an entire
recurring series — the operation fails. The error message "Please check your
input and try again" appears and the rehearsal remains in the system.

This affects all rehearsal deletion attempts across Web and Mobile platforms.

Gig deletion works correctly, confirming the issue is isolated to the rehearsal
deletion workflow, not the general event deletion system.

---

## 2. Existing System Analysis

### 2.1 Flutter Deletion Flow

**UI Layer:**

- `lib/features/events/widgets/event_editor_drawer.dart`
  - `_showDeleteConfirmation()` → standard single-event delete dialog
  - `_showRecurringDeleteDialog()` → "Delete this rehearsal" vs "Delete entire series"
  - `_handleDelete(deleteEntireSeries:)` → entry point for all deletion
  - Permission guard uses `canDeleteGigs` (shared gig/rehearsal permission)
  - Catch block maps errors via `_mapDeleteErrorToMessage()` →
    `mapEventErrorToMessage(error, context: 'delete')`

**Repository Layer:**

- `lib/features/events/events_repository.dart`
  - `deleteRehearsal(rehearsalId, bandId)` → direct `.delete()` on `rehearsals`
  - `deleteRehearsalSeries(rehearsalId, bandId, parentRehearsalId?)` → two-strategy approach:
    1. Parent-child link deletion (via `parent_rehearsal_id` FK)
    2. Pattern-matching fallback (same time, location, day-of-week)
  - `deleteGig(gigId, bandId)` → direct `.delete()` on `gigs` (**WORKS**)

**Error Classification:**

- `lib/shared/utils/event_permission_helper.dart`
  - `classifyError()` checks `error.toString().toLowerCase()` for keywords:
    - `'permission'`, `'denied'`, etc. → `EventErrorType.permission`
    - `'validation'`, `'invalid'`, `'required'` → `EventErrorType.validation`
    - `'network'`, `'socket'`, etc. → `EventErrorType.network`
    - fallthrough → `EventErrorType.unknown`
  - `EventErrorType.validation` → "Please check your input and try again."

### 2.2 Database Layer

**Rehearsals Table Schema** (reconstructed from migrations and model):

- `id` UUID PRIMARY KEY
- `band_id` UUID REFERENCES bands(id) NOT NULL
- `date` DATE
- `start_time` TEXT
- `end_time` TEXT
- `location` TEXT
- `notes` TEXT (nullable)
- `setlist_id` UUID (nullable, FK to setlists)
- `is_recurring` BOOLEAN DEFAULT FALSE
- `recurrence_frequency` TEXT (nullable)
- `recurrence_days` INTEGER[] (nullable)
- `recurrence_until` DATE (nullable)
- `parent_rehearsal_id` UUID REFERENCES rehearsals(id) ON DELETE SET NULL

**Triggers on rehearsals:**

- `rehearsal_created_notification` — AFTER INSERT only (does NOT fire on DELETE)

**RLS Status:**

- RLS is ENABLED on `rehearsals`
- Current active policies: **uncertain** (see Root Cause analysis)

### 2.3 Migration Timeline (Critical Sequence)

| Migration                                               | Date           | Impact on Rehearsals                                                                                                                                              |
| ------------------------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/.../071_fix_events_rls_policies.sql`               | Historical     | Created band-member-only policies (no role check)                                                                                                                 |
| `lib/.../078_add_rehearsal_recurrence.sql`              | Historical     | Added `parent_rehearsal_id` FK with ON DELETE SET NULL                                                                                                            |
| `20260128210000_notification_triggers.sql`              | 2026-01-28     | Created `rehearsal_created_notification` trigger                                                                                                                  |
| `20260207..._fix_recurring_rehearsal_notifications.sql` | 2026-02-07     | Rewrote `notify_rehearsal_created()` — references wrong `name` column                                                                                             |
| **`20260302000000_band_user_roles.sql`**                | **2026-03-02** | **RBAC migration: dynamically dropped policies referencing `band_members` + `.role`; recreated policies for gigs, setlists, bands — SKIPPED rehearsals entirely** |
| `20260305100000_fix_rehearsal_rls_and_trigger.sql`      | 2026-03-05     | **Fix migration (NOT YET DEPLOYED): restores rehearsal RLS + fixes trigger**                                                                                      |

### 2.4 Working vs Failing Path Comparison

| Aspect                  | Gig Delete (WORKS)                       | Rehearsal Delete (FAILS)                        |
| ----------------------- | ---------------------------------------- | ----------------------------------------------- |
| Repository method       | `deleteGig()`                            | `deleteRehearsal()` / `deleteRehearsalSeries()` |
| Supabase call           | `.from('gigs').delete().eq(...)`         | `.from('rehearsals').delete().eq(...)`          |
| RLS policies after RBAC | **Recreated** (Phase 4 of 20260302)      | **Not recreated** (not mentioned in 20260302)   |
| DELETE policy           | "Admins and members can delete gigs" ✅  | Missing or stale ❌                             |
| Notification trigger    | `gig_created_notification` (INSERT only) | `rehearsal_created_notification` (INSERT only)  |
| FK self-reference       | None                                     | `parent_rehearsal_id` → ON DELETE SET NULL      |

---

## 3. Root Cause

### 3.1 Failure Layer Analysis

| Layer               | Assessment     | Reasoning                                                                             |
| ------------------- | -------------- | ------------------------------------------------------------------------------------- |
| Flutter UI logic    | UNLIKELY       | Same UI pattern used for gigs (which works)                                           |
| Controller / state  | UNLIKELY       | No rehearsal-specific state mutation during delete                                    |
| Repository          | UNLIKELY       | `deleteRehearsal()` is a straightforward `.delete()` call, identical to `deleteGig()` |
| Supabase RPC        | NOT APPLICABLE | No RPC used for rehearsal deletion                                                    |
| **RLS policy**      | **LIKELY**     | RBAC migration (20260302) missed rehearsal policies                                   |
| Database constraint | POSSIBLE       | `parent_rehearsal_id` ON DELETE SET NULL + missing UPDATE policy                      |
| Database trigger    | UNLIKELY       | Only INSERT trigger exists                                                            |
| Data integrity      | UNLIKELY       | Standard data, no corruption pattern                                                  |

### 3.2 Primary Failure Surface

**PRIMARY FAILURE SURFACE: RLS Policy**

The RBAC migration (`20260302000000_band_user_roles.sql`) is the most probable
failure origin. It:

1. **Dynamically dropped** all RLS policies whose USING or WITH CHECK expressions
   reference both `band_members` and `.role` (Step 3.5)
2. **Recreated** RBAC-aware policies for gigs (Phase 4), setlists (Phase 5), and
   bands (Phase 6)
3. **Never recreated** any policies for rehearsals

The dynamic drop condition (`qual LIKE '%band_members%' AND qual LIKE '%.role%'`)
would only match policies that reference `band_members.role`. The historical
rehearsal policies from migration 071 did NOT reference `.role`. However:

- Policies may have been created or modified via the Supabase dashboard with
  different expressions that DID match the drop condition
- The exact policy state at migration time cannot be determined from code alone

Regardless of the exact drop mechanism, the result is the same: after the RBAC
migration, the rehearsal table either has **no policies**, **incomplete policies**,
or **stale policies** that may not correctly authenticate the current user.

### 3.3 Evidence

1. **The RBAC migration (20260302) contains ZERO references to "rehearsals"** —
   confirmed via grep search. It updated policies for gigs, setlists, and bands
   but completely skipped the rehearsals table.

2. **Gig deletion works correctly** — gig policies were explicitly recreated in
   Phase 4 of the RBAC migration with proper RBAC-aware checks.

3. **The fix migration (20260305100000) already exists** — a team member already
   diagnosed this class of issue and wrote a fix that restores rehearsal RLS
   policies and fixes the trigger function, but it has NOT been deployed.

4. **The `delete_band` RPC was also broken** — the RBAC migration rewrote
   `delete_band()` without including `DELETE FROM public.rehearsals`, which the
   original (migration 082) DID include. This is a secondary bug in the same
   migration.

5. **Error classification maps to "validation"** — the error message
   "Please check your input and try again" corresponds to
   `EventErrorType.validation`, triggered when the error string contains
   'invalid', 'required', or 'validation'. This is consistent with a
   PostgreSQL/PostgREST error during the delete operation containing one of
   these keywords.

### 3.4 Potential Root Cause Candidates

1. **Missing DELETE RLS policy on rehearsals** — Primary candidate. After RBAC
   migration, no DELETE policy exists (or a stale one remains). Depending on
   PostgREST version behavior, this either silently deletes 0 rows or throws a
   PostgrestException.

2. **Missing UPDATE RLS policy blocking FK cascade** — When deleting a parent
   rehearsal, `ON DELETE SET NULL` on `parent_rehearsal_id` needs to UPDATE child
   rows. If no UPDATE policy exists, this could fail. (Note: PostgreSQL typically
   handles FK cascading operations internally, bypassing RLS, but behavior may
   vary by version.)

3. **PostgREST error response containing 'invalid' keyword** — The specific
   error from PostgREST when operating on a table with broken or missing RLS
   policies may contain keywords that trigger the `validation` classification.

### 3.5 Root Cause (Most Likely)

**The RBAC migration (20260302) left the rehearsals table with missing or broken
RLS policies. Specifically, the DELETE and UPDATE policies were either dropped
and not recreated, or are stale references that don't work with the new
`band_role_type` ENUM column. This causes all rehearsal deletion attempts to
fail at the database level.**

### 3.6 Minimal Reproduction Query

```sql
-- Run as an authenticated user who is an active band member

-- Step 1: Verify current RLS policies on rehearsals
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'rehearsals';

-- Step 2: Attempt to delete a test rehearsal
DELETE FROM rehearsals
WHERE id = '<test-rehearsal-id>'
AND band_id = '<test-band-id>';

-- Expected:
-- If policies are missing: 0 rows deleted (silent failure) OR PostgrestException
-- If policies are present and correct: 1 row deleted
```

---

## 4. Proposed Solution

### 4.1 Solution Overview

Deploy the existing fix migration (`20260305100000_fix_rehearsal_rls_and_trigger.sql`)
which restores RBAC-aware RLS policies for rehearsals and fixes the notification
trigger function. Additionally, patch the `delete_band` RPC to include
rehearsal cleanup.

### 4.2 Solution Components

**Component 1: Deploy Existing Fix Migration (20260305100000)**

The fix migration already addresses:

- Drops all stale rehearsal policies
- Creates RBAC-aware SELECT, INSERT, UPDATE, DELETE policies
- Fixes `notify_rehearsal_created()` to use `first_name` instead of `name`
- Wraps trigger in exception handler so it never blocks operations

This migration is correct, complete for RLS/trigger purposes, and safe to deploy.

**Component 2: Fix `delete_band` RPC — Missing Rehearsal Cleanup**

The RBAC migration (20260302) rewrote `delete_band()` without including
`DELETE FROM public.rehearsals`. This must be patched. A new migration will
add the missing rehearsal cleanup to the cascade delete sequence.

**Component 3: Improve Error Classification (Flutter)**

The current `classifyError()` function may misclassify database policy errors
as "validation" errors due to broad keyword matching. The error message
"Please check your input and try again" is misleading for what is actually
a database permission/policy issue. No change is strictly required for the
fix, but the Engineer should verify the actual error message after deploying
the migration fix and adjust classification if needed.

---

## 5. Database Impact

### 5.1 Tables Affected

| Table        | Impact                                 |
| ------------ | -------------------------------------- |
| `rehearsals` | RLS policies recreated (DROP + CREATE) |
| None         | No schema changes, no column additions |

### 5.2 Data Impact

- **No data is modified or deleted** by the migration
- Policy changes are immediate and affect all subsequent queries
- Existing rehearsal data is unaffected

### 5.3 Rollback Risk

- LOW: If a policy is invalid, it can be quickly corrected via a new migration
- The DROP + CREATE pattern is safe — it removes stale policies before adding new ones

---

## 6. RLS / RPC Changes

### 6.1 RLS Policy Changes (via existing migration 20260305100000)

**Dropped:**

- "Band members can view rehearsals"
- "Band members can create rehearsals"
- "Band members can update rehearsals"
- "Band members can delete rehearsals"
- "Admins and members can create rehearsals"
- "Admins and members can update rehearsals"
- "Admins and members can delete rehearsals"

**Created:**

- "Band members can view rehearsals" — SELECT for any active band member
- "Admins and members can create rehearsals" — INSERT for admin/member only
- "Admins and members can update rehearsals" — UPDATE for admin/member only
- "Admins and members can delete rehearsals" — DELETE for admin/member only

These match the gig policy pattern from the RBAC migration exactly.

### 6.2 RPC Changes (new migration required)

**`delete_band(UUID)`** — add missing rehearsal cleanup:

Before the `DELETE FROM public.gigs` line, add:

```sql
DELETE FROM public.rehearsals WHERE band_id = band_uuid;
```

This restores the cleanup line that was present in migration 082 but dropped
during the RBAC rewrite.

### 6.3 Trigger Changes (via existing migration 20260305100000)

**`notify_rehearsal_created()`** — already fixed in existing migration:

- Uses `first_name` instead of non-existent `name` column
- Wraps entire body in exception handler
- AFTER INSERT only (does not affect DELETE operations)

---

## 7. Flutter Architecture Changes

### 7.1 Required Changes

**None.** The Flutter code is correct. The deletion flow, repository methods,
error handling, and UI are all properly implemented. The bug is entirely
at the database layer (missing RLS policies).

### 7.2 Optional Improvements (Out of Scope for this fix)

- The `classifyError()` function could be improved to better distinguish
  database policy errors from validation errors
- The `_handleDelete` permission check uses `canDeleteGigs` for rehearsals —
  a `canDeleteRehearsals` permission could be added for finer-grained RBAC

These are NOT required for this fix and should be tracked separately.

---

## 8. Exact Files to Create

| File                                                                        | Purpose                                              |
| --------------------------------------------------------------------------- | ---------------------------------------------------- |
| `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql` | Patch `delete_band` RPC to include rehearsal cleanup |

---

## 9. Exact Files to Modify

| File | Modification                         |
| ---- | ------------------------------------ |
| None | No application code changes required |

**Existing migration to deploy (no modification needed):**
| File | Status |
|------|--------|
| `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql` | Deploy as-is (already correct) |

---

## 10. Risks / Edge Cases

### 10.1 Risks

| Risk                                                       | Severity | Mitigation                                                                       |
| ---------------------------------------------------------- | -------- | -------------------------------------------------------------------------------- |
| Migration applied to wrong database                        | HIGH     | Verify target database before deployment                                         |
| Stale policies from dashboard not caught by DROP IF EXISTS | LOW      | Migration drops all known policy names; unlikely to miss                         |
| `ON DELETE SET NULL` cascade requires UPDATE policy        | MEDIUM   | Fix migration creates UPDATE policy; FK cascades typically bypass RLS internally |
| `delete_band` migration ordering                           | LOW      | New migration only patches RPC; no dependency on RLS changes                     |

### 10.2 Edge Cases

1. **Contributors cannot delete rehearsals** — By design. The new policies
   require `admin` or `member` role, matching the gig pattern. Contributors
   are blocked at both RLS and Flutter permission layers.

2. **Recurring series with mixed parent-child relationships** — The
   `deleteRehearsalSeries()` repository method handles both linked and legacy
   series (pattern-matching fallback). No change needed.

3. **Concurrent deletion of parent and child rehearsals** — The
   `ON DELETE SET NULL` FK on `parent_rehearsal_id` handles this safely.

4. **Rehearsals with setlist references** — Deleting a rehearsal does NOT
   cascade to delete the setlist (rehearsal holds the FK, not the other way).
   Safe.

---

## 11. Verification Plan

### 11.1 Pre-Deployment Verification

1. **Query current policies** on production rehearsals table:

   ```sql
   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'rehearsals';
   ```

   Document what policies exist (or don't exist) before applying fix.

2. **flutter analyze** — run to confirm no code changes introduced issues.

### 11.2 Post-Deployment Verification

1. **Verify policies created** — re-run the policy query and confirm all four
   policies exist (SELECT, INSERT, UPDATE, DELETE).

2. **Single rehearsal delete** — as admin user:
   - Create a single rehearsal
   - Delete it
   - Confirm it's removed

3. **Recurring series delete ("Delete this rehearsal")** — as admin user:
   - Create a recurring series
   - Select one instance, choose "Delete this rehearsal"
   - Confirm only the selected instance is deleted

4. **Recurring series delete ("Delete entire series")** — as admin user:
   - Select any instance, choose "Delete entire series"
   - Confirm all instances are deleted

5. **Gig delete regression check** — confirm gig deletion still works.

6. **Rehearsal creation check** — confirm new rehearsals can still be created
   (trigger fix validated).

7. **delete_band regression check** — confirm band deletion cleans up
   rehearsals.

### 11.3 Platform Verification

- Web (primary)
- Mobile (iOS or Android)

---

## 12. Engineer Task Breakdown

### Task 1: Validate Existing Fix Migration

- Read `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql`
- Confirm policies match the RBAC pattern from the gigs section of 20260302
- Confirm trigger function fix is correct
- **No modification needed** — migration is correct as-is

### Task 2: Create `delete_band` Patch Migration

- Create `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql`
- Add `DELETE FROM public.rehearsals WHERE band_id = band_uuid;` to the
  `delete_band()` RPC cascade sequence
- Place it BEFORE `DELETE FROM public.gigs` (matching the order from migration 082)
- Use `CREATE OR REPLACE FUNCTION` to update the RPC

### Task 3: Deploy Migrations

- Apply migration `20260305100000_fix_rehearsal_rls_and_trigger.sql` to production
- Apply migration `20260306000000_fix_delete_band_missing_rehearsals.sql` to production
- Verify via SQL Editor that policies are created

### Task 4: Run Verification Plan

- Execute all verification steps from Section 11
- Document results

### Task 5: Run `flutter analyze`

- Confirm no lint or type errors
- No code changes expected, but verify clean state

---

## 13. Rollout / Migration Strategy

### 13.1 Deployment Order

1. Deploy `20260305100000_fix_rehearsal_rls_and_trigger.sql` (RLS + trigger fix)
2. Deploy `20260306000000_fix_delete_band_missing_rehearsals.sql` (delete_band patch)
3. Both migrations are additive and non-destructive

### 13.2 Rollback Plan

If issues arise after deployment:

1. **RLS policies** — can be dropped individually via:

   ```sql
   DROP POLICY "Admins and members can delete rehearsals" ON public.rehearsals;
   ```

   And recreated with corrected logic.

2. **delete_band RPC** — `CREATE OR REPLACE` overwrites the function. If
   rollback is needed, re-deploy the RBAC migration's version of the function.

### 13.3 No Downtime Required

- Policy changes take effect immediately
- No schema changes
- No data migration
- No app deployment needed (Flutter code is unchanged)

---

## 14. Out of Scope

The following items are explicitly out of scope for this fix:

1. **Improving `classifyError()` keyword matching** — the error classification
   function uses broad keyword matching that can misclassify database errors.
   This is a general improvement, not specific to this bug.

2. **Adding `canDeleteRehearsals` permission** — the current permission model
   uses `canDeleteGigs` for both gigs and rehearsals. Adding a separate
   rehearsal permission is a feature enhancement, not a bug fix.

3. **Rehearsal notification improvements** — the trigger fix in 20260305100000
   addresses the `name` column issue but does not add new notification features.

4. **Refactoring the event editor drawer** — the deletion flow works correctly;
   the issue is entirely database-side.

5. **Adding automated tests for RLS policies** — valuable but separate work.

6. **Reviewing all other tables for missing RBAC policies** — the RBAC migration
   should be audited for completeness, but that is a broader task beyond this
   specific bug fix.
