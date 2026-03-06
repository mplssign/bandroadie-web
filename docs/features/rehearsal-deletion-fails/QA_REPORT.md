# QA REPORT — rehearsal-deletion-fails

**Feature Slug:** `feature/rehearsal-deletion-fails`
**Feature Title:** Fix Rehearsal Deletion Failure
**Date:** 2026-03-06
**Branch:** `feature/rehearsal-deletion-fails`

---

## Validation Summary

The Engineer implementation correctly follows the Architect plan. The fix is database-only: one new migration patches the `delete_band()` RPC to restore missing rehearsal cleanup. The existing RLS + trigger fix migration (20260305100000) was validated as correct and left unmodified. No Flutter code was changed, as the Architect plan determined the application layer was correct.

---

## Bug Reproduction Result

**Root cause confirmed:** The RBAC migration (20260302000000) dropped/rewrote RLS policies for gigs, setlists, and bands but skipped the rehearsals table entirely. This left rehearsals with missing or broken DELETE/UPDATE RLS policies, causing all rehearsal deletion attempts to fail with a misleading "Please check your input and try again" error.

**Secondary bug confirmed:** The same RBAC migration rewrote `delete_band()` without the `DELETE FROM public.rehearsals` cleanup line present in the original (migration 082).

**Static verification:** Both fixes address the root causes. Full behavioral verification requires post-deployment testing per the Architect's verification plan (§11.2).

---

## Implementation Review

### Approach

- **Database-only fix** — no application code changes, matching Architect plan exactly
- **Minimal surface area** — one new migration file created; zero files modified
- **Existing migration validated** — 20260305100000 confirmed correct (4 RLS policies + trigger fix)

### New Migration: `20260306000000_fix_delete_band_missing_rehearsals.sql`

- Replaces `delete_band()` RPC body via `CREATE OR REPLACE FUNCTION`
- Adds `DELETE FROM public.rehearsals WHERE band_id = band_uuid` before gigs deletion
- Preserves admin-only permission check from RBAC migration (does not revert to 082's "any member" check)
- All other cascade deletes unchanged
- Function signature unchanged: `delete_band(UUID) RETURNS BOOLEAN`
- `SECURITY DEFINER` and `SET search_path = public` preserved

### RLS Policies (existing migration 20260305100000)

| Policy                                   | Command | Access                            | Matches Gig Pattern? |
| ---------------------------------------- | ------- | --------------------------------- | -------------------- |
| Band members can view rehearsals         | SELECT  | Any active member                 | ✅                   |
| Admins and members can create rehearsals | INSERT  | Admin/member only                 | ✅                   |
| Admins and members can update rehearsals | UPDATE  | Admin/member (USING + WITH CHECK) | ✅ Exact match       |
| Admins and members can delete rehearsals | DELETE  | Admin/member only                 | ✅ Exact match       |

### Trigger Fix (existing migration 20260305100000)

- Uses `first_name` (correct column) instead of non-existent `name`
- Exception handler wraps entire body — trigger never blocks inserts
- AFTER INSERT only — does not affect DELETE operations

---

## Files Verified

### Created (by Engineer)

| File                                                                        | Purpose                   | Verified |
| --------------------------------------------------------------------------- | ------------------------- | -------- |
| `supabase/migrations/20260306000000_fix_delete_band_missing_rehearsals.sql` | Patch `delete_band()` RPC | ✅       |

### Validated (pre-existing, not modified)

| File                                                                   | Purpose                    | Verified |
| ---------------------------------------------------------------------- | -------------------------- | -------- |
| `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql` | RLS policies + trigger fix | ✅       |

### Modified

None. ✅ (Matches Architect plan §9: no files to modify)

---

## Regression Check

| System           | Risk | Notes                                                          |
| ---------------- | ---- | -------------------------------------------------------------- |
| Gigs             | NONE | No gig code or policies touched                                |
| Rehearsals       | LOW  | Additive: restoring missing policies                           |
| Setlists         | NONE | Not touched                                                    |
| Notifications    | LOW  | Trigger fix uses exception handler                             |
| Role permissions | NONE | No RBAC changes; policies use existing `band_members.role`     |
| Routing          | NONE | No Flutter changes                                             |
| Auth/Session     | NONE | Not touched                                                    |
| Band deletion    | LOW  | `delete_band()` adds 1 DELETE statement; admin check preserved |

**Regression Risk Level: LOW**

All changes are strictly additive (restoring functionality that was accidentally removed by the RBAC migration).

---

## Analyzer Results

```
flutter analyze
Analyzing bandroadie...

warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19 • dead_code

1 issue found. (ran in 3.6s)
```

- **0 errors** ✅
- **1 pre-existing warning** (dead_code in lyrics — unrelated to this change) ✅
- **No new warnings introduced** ✅

---

## Diff Review

- **No secrets or credentials** in any new files ✅
- **No config changes** (pubspec.yaml, build.gradle, entitlements unchanged) ✅
- **No unrelated refactors** ✅
- **Minimal surface area** — only the necessary migration + documentation ✅
- **No application code changes** — consistent with Architect plan ✅

---

## Database Safety

- **No privilege escalation** — admin-only check preserved in `delete_band()` ✅
- **No cascade dangers** — rehearsal delete order is safe (no FK to gigs) ✅
- **RLS remains secure** — all policies require active band membership + appropriate role ✅
- **SECURITY DEFINER functions** use `SET search_path = public` (prevents search path injection) ✅
- **Trigger cannot block inserts** — exception handler catches all errors ✅
- **DROP POLICY IF EXISTS** pattern is idempotent and safe ✅

---

## Final Verdict

## **APPROVED**

The implementation is safe to commit. All Architect plan tasks are completed. Changes are minimal, focused, and correctly scoped. No regressions detected. Database safety verified.

**Post-commit requirement:** Migrations must be deployed to production in order:

1. `20260305100000_fix_rehearsal_rls_and_trigger.sql` (RLS + trigger)
2. `20260306000000_fix_delete_band_missing_rehearsals.sql` (delete_band patch)

Post-deployment verification should follow the Architect's verification plan (§11.2).
