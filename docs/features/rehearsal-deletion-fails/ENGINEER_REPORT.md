# ENGINEER REPORT — rehearsal-deletion-fails

**Feature Slug:** `feature/rehearsal-deletion-fails`
**Feature Type:** bug
**Date:** 2026-03-06
**Branch:** `feature/rehearsal-deletion-fails`

---

## Goal

Fix rehearsal deletion (single and recurring series) which fails with "Please check your input and try again" due to missing RLS policies after the RBAC migration (20260302) skipped the rehearsals table. Also patch the `delete_band` RPC which was missing rehearsal cleanup.

---

## Implementation Summary

The Architect plan identified that:

1. **No Flutter changes are needed** — the deletion flow, repository, and error handling are correct. The bug is entirely at the database layer.
2. **An existing fix migration (20260305100000) already restores rehearsal RLS policies and fixes the trigger** — validated as correct, no modifications needed.
3. **A new migration is needed** to patch the `delete_band` RPC, which was rewritten by the RBAC migration without the `DELETE FROM public.rehearsals` cleanup line.

### What was done:

- **Validated** `20260305100000_fix_rehearsal_rls_and_trigger.sql` — confirmed all four RLS policies (SELECT, INSERT, UPDATE, DELETE) match the RBAC pattern from the gigs policies. Trigger fix correctly uses `first_name` instead of non-existent `name` column. Exception handler wraps entire trigger body.
- **Created** `20260306000000_fix_delete_band_missing_rehearsals.sql` — replaces `delete_band()` RPC with the rehearsal cleanup line added before the gigs deletion, restoring the cascade order from migration 082.

---

## Files Modified

None.

---

## Files Created

| File                                                                        | Purpose                                                                                    |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql` | Patches `delete_band()` RPC to include `DELETE FROM public.rehearsals` in cascade sequence |

---

## Files to Deploy (Pre-existing, No Modification)

| File                                                                   | Purpose                                                                       |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql` | Restores RBAC-aware RLS policies on rehearsals table + fixes trigger function |

---

## Verification Commands

```bash
# Flutter analysis — PASSED (0 errors, 1 pre-existing warning unrelated to this change)
flutter analyze
```

**Result:** 1 pre-existing warning (`dead_code` in `lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19`). No new issues.

---

## Manual Test Steps

### Pre-deployment: Query current policies

```sql
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'rehearsals';
```

### Deployment order

1. Deploy `20260305100000_fix_rehearsal_rls_and_trigger.sql` (RLS + trigger fix)
2. Deploy `20260306000000_fix_delete_band_missing_rehearsals.sql` (delete_band patch)

### Post-deployment verification

1. **Verify policies created:**

   ```sql
   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'rehearsals';
   ```

   Expected: 4 policies (SELECT, INSERT, UPDATE, DELETE)

2. **Single rehearsal delete** (as admin/member):
   - Create a single rehearsal
   - Delete it
   - Confirm removal

3. **Recurring series — "Delete this rehearsal"** (as admin/member):
   - Create a recurring series
   - Select one instance → "Delete this rehearsal"
   - Confirm only selected instance deleted

4. **Recurring series — "Delete entire series"** (as admin/member):
   - Select any instance → "Delete entire series"
   - Confirm all instances deleted

5. **Gig delete regression check** — confirm gig deletion still works

6. **Rehearsal creation check** — confirm new rehearsals can be created (trigger fix validated)

7. **delete_band regression check** — confirm band deletion cleans up rehearsals

---

## QA Focus Areas

1. **RLS policy correctness** — Verify the new rehearsal policies grant correct access:
   - Admin/member: full CRUD
   - Contributor: SELECT only (no create/update/delete)
   - Non-member: no access

2. **delete_band cascade order** — The rehearsal DELETE is placed BEFORE gigs DELETE. Verify no FK constraint violations during band deletion.

3. **Recurring series edge cases** — Parent-child relationships with `ON DELETE SET NULL` on `parent_rehearsal_id`. Deleting a parent should set children's `parent_rehearsal_id` to NULL (not delete them).

4. **Trigger safety** — The fixed trigger should NEVER block inserts even if notification logic fails.

5. **No Flutter changes** — Verify no application code was modified.

---

## Assumptions

1. The existing migration `20260305100000_fix_rehearsal_rls_and_trigger.sql` has NOT been deployed to production yet (as stated in Architect plan).
2. The `delete_band` RPC function signature (`delete_band(UUID) RETURNS BOOLEAN`) is unchanged — only the body is patched.
3. The cascade delete order in the patched function preserves all other deletions identically to the RBAC migration version; only the rehearsal line was added.
4. The pre-existing `dead_code` warning in lyrics is unrelated and not introduced by this change.
