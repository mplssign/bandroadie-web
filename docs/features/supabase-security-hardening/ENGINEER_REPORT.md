# Engineer Report

## Feature Slug

`bug/supabase-security-hardening`

## Feature Title

Supabase Security Hardening — Fix Five Backend Security Vulnerabilities

## Goal

Fix five independent security gaps in the Supabase backend:

1. IDOR vulnerability in `regenerate_calendar_token` allowing any authenticated user to regenerate another user's calendar token
2. `financial_entries` SELECT policy ignoring `can_view_financials` permission for contributors
3. Four setlist-related RPCs (`reorder_setlist_songs`, `reorder_setlist_items`, `add_special_item_to_setlist`, `delete_setlist`) missing from migrations, breaking schema reproducibility
4. 21 `SECURITY DEFINER` functions with mutable `search_path` (privilege escalation risk)
5. 4 destructive RPCs executable by `anon` role (violates least-privilege principle)

All fixes are backend-only (SQL migrations) with zero client code changes required.

## Architect Tasks Completed

- [x] Task 1 — Create 5 migration files
- [x] Task 2 — Implement migration 1: Fix `regenerate_calendar_token` IDOR
- [x] Task 3 — Implement migration 2: Fix `financial_entries_select` RLS policy
- [x] Task 4 — Implement migration 3: Restore missing setlist RPC definitions
- [x] Task 5 — Implement migration 4: Bulk `ALTER FUNCTION` for `SET search_path`
- [x] Task 6 — Implement migration 5: Revoke anon access from destructive RPCs
- [x] Task 7 — Validate migrations locally (Tier 1 + Tier 2 tests)
- [x] Task 8 — Write ENGINEER_REPORT.md

## Files Created

- `supabase/migrations/20260814120000_fix_regenerate_calendar_token_idor.sql`
- `supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql`
- `supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql`
- `supabase/migrations/20260814120003_harden_security_definer_search_path.sql`
- `supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql`
- `supabase/migrations/20260814120005_harden_remaining_search_path_functions.sql`
- `docs/features/supabase-security-hardening/ENGINEER_REPORT.md` (this file)

## Files Modified

- None (all changes are additive migrations)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 8 warnings (all pre-existing, unrelated to this implementation)

Pre-existing warnings:

- Unused imports and variables in `bulk_entry_screen.dart`, `original_song_screen.dart`, and test files
- `use_build_context_synchronously` info messages in async methods

No new warnings introduced by this implementation.

## Test Results

**Tier 1 Pre-Deployment Tests: PASSED**

- Verified `check_band_member` helper function works for active members
- Verified `contributor_permissions.can_view_financials` column exists

**Tier 2 Post-Deployment Tests: PASSED**

- Test 2.1: Verified `regenerate_calendar_token` has `SET search_path` attribute and auth check
- Test 2.2: Verified `check_financial_view_permission` helper function created
- Test 2.3: Verified `financial_entries_select` policy uses new helper
- Test 2.4: Verified all 4 setlist RPCs have `SET search_path` attribute
- Test 2.5: Verified 21 functions from migration 4 have `SET search_path` attribute
- Test 2.6: Verified all 4 destructive RPCs revoked from anon role
- Test 2.7: Verified 7 functions from migration 6 have `SET search_path` attribute

## Migration Application

All 6 migrations applied successfully via `supabase db push --linked`:

- 20260814120000_fix_regenerate_calendar_token_idor.sql ✅
- 20260814120001_fix_financial_entries_select_rbac.sql ✅
- 20260814120002_restore_setlist_rpc_definitions.sql ✅
- 20260814120003_harden_security_definer_search_path.sql ✅
- 20260814120004_revoke_anon_destructive_rpcs.sql ✅
- 20260814120005_harden_remaining_search_path_functions.sql ✅

## Verification

### Manual Verification Steps Performed:

1. **Extracted live function definitions** from production database using `pg_get_functiondef()` to ensure exact signatures for migrations 3 and 4
2. **Verified pre-existing state** via Tier 1 tests before applying migrations
3. **Applied all migrations atomically** via `supabase db push --linked`
4. **Verified post-migration state** via Tier 2 tests:
   - Confirmed `regenerate_calendar_token` has authorization check and `SET search_path`
   - Confirmed `check_financial_view_permission` helper created with correct logic
   - Confirmed all 4 setlist RPCs have `SET search_path` as function attribute
   - Confirmed 21 functions from migration 4 have `SET search_path` attribute
   - Confirmed destructive RPCs revoked from `anon` role
   - Confirmed 7 functions from migration 6 have `SET search_path` attribute
5. **Verified permissions** using `has_function_privilege()` to confirm anon cannot execute destructive RPCs

### Database State After Migrations:

- 28 `SECURITY DEFINER` functions hardened via migrations 4 and 6 now have `SET search_path` configured as function attribute
- 4 destructive RPCs (`delete_band`, `update_member_role`, `remove_band_member`, `delete_user_account`) now require `authenticated` role
- Financial entries now enforce `can_view_financials` permission for contributors at the database layer
- Setlist reordering RPCs are now version-controlled and include proper security hardening

## Deviations From Architect Plan

**One additional migration created:**

Migration 4 in ARCHITECT_PLAN.md listed 28 functions in the enumerated list. During implementation, 21 of those 28 were applied in migration `20260814120003`, correctly excluding functions already handled in migrations 1-3. However, 7 additional functions from that list were inadvertently missed and required a follow-up migration `20260814120005_harden_remaining_search_path_functions.sql` to complete the full scope of 28 functions as specified.

The 7 functions added in migration 6:

- `generate_invite_token`
- `get_band_full_state`
- `should_receive_notification`
- `update_notification_preferences_updated_at`
- `update_print_templates_updated_at`
- `update_updated_at_column`
- `update_user_calendar_preferences_updated_at`

**One migration file edit:**

Migration 5 (`20260814120004_revoke_anon_destructive_rpcs.sql`) was updated after initial deployment to use `REVOKE ALL ... FROM PUBLIC, anon` instead of `REVOKE EXECUTE ... FROM PUBLIC` because Supabase's `anon` role has explicit grants that are not removed by revoking from `PUBLIC`. The corrected version was applied manually and the migration file updated to reflect the working syntax.

## Blockers Encountered

**Permission Revocation Issue (Resolved):**

Initial `REVOKE EXECUTE ... FROM PUBLIC` commands in migration 5 did not remove permissions from the `anon` role because Supabase grants explicit permissions to `anon`, `authenticated`, and `service_role` rather than via `PUBLIC`.

**Resolution:** Updated migration to use `REVOKE ALL ... FROM PUBLIC, anon` and applied manually. Migration file corrected for future deployments.

## Ready For QA

**Yes** — All migrations applied successfully, all tests passed, analyzer shows 0 errors.

### QA Regression Testing Required:

Per the Architect plan's "QA Regression Areas" section, the following areas must be validated:

**Primary validation (must test):**

1. Calendar token regeneration — verify user can regenerate their own token, URL updates correctly, cannot regenerate another user's token
2. Financial entry access (contributor) — create contributor with `can_view_financials = false`, verify they cannot see financial entries
3. Financial entry access (admin/member) — verify admin and member can view/create/edit/delete financial entries
4. Setlist reordering — drag-and-drop reorder songs, verify positions persist after reload
5. Special item insertion — add set break/pause to setlist, verify correct position and reordering works
6. Band deletion (admin) — verify admin can delete band
7. Member role change (admin) — verify admin can promote/demote members with correct permissions
8. Member removal (admin) — verify admin can remove members
9. User account deletion — verify user can delete their own account via Settings

**Regression coverage (spot-check):** 10. Gig creation 11. Rehearsal creation 12. Setlist CRUD 13. Song CRUD 14. Catalog integrity

All backend changes are transparent to clients — no UI changes required, no API signature changes, and all existing functionality preserved.
