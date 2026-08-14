# QA Report

## Feature Slug

`bug/supabase-security-hardening`

## Feature Title

Supabase Security Hardening — Fix Five Backend Security Vulnerabilities

## Final Verdict

**APPROVED**

## Validation Summary

All six migrations (including the 6th migration added mid-implementation to complete the search_path hardening scope) have been validated against the Architect plan via direct SQL inspection. Critical database safety checks passed: the `check_financial_view_permission` helper correctly avoids querying `financial_entries` to prevent infinite recursion, `regenerate_calendar_token` places the authorization check as the first statement in the function body, and all ALTER FUNCTION statements use valid PostgreSQL signatures. The implementation is backend-only with zero client code changes, introduces no new analyzer errors, and all regression risk has been appropriately assessed as MEDIUM with comprehensive QA testing guidance provided.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected — 6 migration files created (5 originally planned + 1 follow-up to complete migration 4's scope), 1 Engineer report created, no client code modified
- **Files off-limits:** No violations — all files in `lib/` untouched, no existing migrations modified

### Deviation Analysis

One additional migration file created beyond the 5 originally enumerated in Task 1 of the Architect plan:

- **Migration 6** (`20260814120005_harden_remaining_search_path_functions.sql`) was added mid-implementation to complete the full scope of 28 functions specified in the Architect plan's Task 5 enumerated list. Migration 4 correctly applied 21 functions (excluding functions already handled in migrations 1-3), and migration 6 added the 7 remaining functions that were inadvertently missed during initial implementation.

This deviation was discovered during the Manager's Implementation Gate review and is documented in the Engineer Report. The 6th migration is architecturally sound and completes the original security hardening scope as intended.

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

### Task Verification

- [x] Task 1: Create 5 migration files (6 created — see deviation analysis above)
- [x] Task 2: Implement migration 1 — Fix `regenerate_calendar_token` IDOR
- [x] Task 3: Implement migration 2 — Fix `financial_entries_select` RLS policy
- [x] Task 4: Implement migration 3 — Restore missing setlist RPC definitions
- [x] Task 5: Implement migration 4 — Bulk `ALTER FUNCTION` for search_path (completed via migrations 4 + 6)
- [x] Task 6: Implement migration 5 — Revoke anon access from destructive RPCs
- [x] Task 7: Validate migrations locally (Tier 1 + Tier 2 tests documented in Engineer Report)
- [x] Task 8: Write ENGINEER_REPORT.md

## Behavior Verification

- **Validation method:** Code-path analysis via direct SQL inspection of all 6 migration files + git diff review
- **Result:** Matches expected behavior as defined in Architect plan

### Security Fix Verification

**Finding #1 — IDOR on `regenerate_calendar_token`:**

- ✅ Authorization check placed as **first statement** in function body
- ✅ Check verifies `auth.uid() IS NULL OR auth.uid() != p_user_id` and raises exception
- ✅ `SET search_path = public` added to function definition (not in body)
- ✅ Function signature unchanged (`p_user_id UUID` parameter preserved)
- ✅ Return type unchanged (`RETURNS UUID`)

**Finding #2 — `financial_entries_select` policy:**

- ✅ Helper function `check_financial_view_permission` created
- ✅ Helper queries `band_members` and `contributor_permissions` tables only
- ✅ **Critical:** Helper does NOT query `financial_entries` table (infinite recursion prevention per GUARDRAILS.md)
- ✅ Helper checks: admin/member always TRUE, contributor TRUE only if `can_view_financials=true`
- ✅ Helper is `SECURITY DEFINER` with `SET search_path = public` in definition
- ✅ SELECT policy replaced to use `public.check_financial_view_permission(band_id)`

**Finding #3 — Missing setlist RPC definitions:**

- ✅ `reorder_setlist_songs` — one-line delegate to `reorder_setlist_items`, parameter is `p_row_ids` (not `p_song_ids`), returns JSON
- ✅ `reorder_setlist_items` — atomic two-phase position update, returns JSON
- ✅ `add_special_item_to_setlist` — returns JSONB with success/error structure
- ✅ `delete_setlist` — re-issued with `SET search_path = public` in definition
- ✅ All 4 functions have `SECURITY DEFINER` and `SET search_path = public` in function definition (not in body)
- ✅ All 4 functions granted to `authenticated` role

**Finding #4 — Mutable search_path on SECURITY DEFINER functions:**

- ✅ Migration 4: 21 ALTER FUNCTION statements (destructive RPCs + 18 others)
- ✅ Migration 6: 7 ALTER FUNCTION statements (functions missed in migration 4)
- ✅ Total: 28 functions hardened (matches Architect plan's enumerated list)
- ✅ All ALTER FUNCTION statements use valid PostgreSQL signatures (parameter names optional, types case-insensitive)

**Finding #5 — Anon access to destructive RPCs:**

- ✅ Uses corrected syntax: `REVOKE ALL ... FROM PUBLIC, anon` (not just `FROM PUBLIC`)
- ✅ Followed by `GRANT EXECUTE ... TO authenticated` for each function
- ✅ Applied to 4 destructive RPCs: `delete_band`, `update_member_role`, `remove_band_member`, `delete_user_account`

## Regression Check

- **Risk level:** MEDIUM
- **Systems reviewed:** Setlists/Catalog (reordering RPCs restored), Members/RBAC (destructive RPCs hardened, financial view permissions enforced), Calendar (token regeneration IDOR fixed)
- **Regressions found:** None detected via code-path analysis

### Risk Assessment

**MEDIUM risk is justified:**

- Setlist reordering RPCs restored from live production — high-value feature with moderate usage frequency
- Financial entries SELECT policy tightened — contributors with `can_view_financials=false` will now be blocked (UI already hides this case)
- 28 `SECURITY DEFINER` functions altered — mechanical change (search_path hardening only), no logic modifications
- Destructive RBAC RPCs hardened — low-frequency operations, all have existing `auth.uid()` checks (anon revocation is defense-in-depth)
- Calendar token regeneration — IDOR fixed, signature unchanged, existing client code (deprecated, currently uncalled) will continue to work

**Mitigations in place:**

- All changes are additive hardening — no behavioral changes except closing security gaps
- No auth/session/init order changes — initialization guardrails preserved
- Engineer performed Tier 1 (pre-deploy) and Tier 2 (post-deploy) tests as documented
- Comprehensive QA regression testing guidance provided in Architect plan's "QA Regression Areas" section

## Database Safety

**Verified — all critical safety checks passed:**

### RLS Policy Safety

- ✅ `check_financial_view_permission` helper does NOT self-reference `financial_entries` table
- ✅ Queries only `band_members` and `contributor_permissions` tables
- ✅ Prevents PostgreSQL error 42P17 (infinite recursion) per GUARDRAILS.md

### Privilege Escalation Prevention

- ✅ All `SECURITY DEFINER` functions now have immutable `SET search_path = public` as function attribute
- ✅ Prevents search_path hijacking attacks via `pg_temp` schema manipulation
- ✅ 28 functions hardened across migrations 4 and 6

### Authorization Check Placement

- ✅ `regenerate_calendar_token` auth check is **first statement** in function body (before any data access)
- ✅ Check validates `auth.uid()` matches `p_user_id` parameter
- ✅ Prevents IDOR (Insecure Direct Object Reference) vulnerability

### Least-Privilege Enforcement

- ✅ Destructive RPCs revoked from `PUBLIC` and `anon` roles explicitly
- ✅ Granted only to `authenticated` role
- ✅ Uses `REVOKE ALL ... FROM PUBLIC, anon` syntax (corrected from initial `FROM PUBLIC` only)

### Signature Preservation

- ✅ `regenerate_calendar_token` signature unchanged — existing client code compatible
- ✅ All setlist RPCs match live production signatures (verified via Manager-provided definitions)
- ✅ No breaking changes to RPC interfaces

### Migration Content Review

All 6 migration files inspected directly (not just filenames):

1. **20260814120000**: `regenerate_calendar_token` redefined with auth check + search_path
2. **20260814120001**: `check_financial_view_permission` helper + policy replacement
3. **20260814120002**: 4 setlist RPCs defined with `SECURITY DEFINER` + search_path
4. **20260814120003**: 21 ALTER FUNCTION statements for search_path hardening
5. **20260814120004**: 4 REVOKE/GRANT pairs for destructive RPCs
6. **20260814120005**: 7 ALTER FUNCTION statements for remaining functions

All SQL syntax is valid PostgreSQL, all function signatures use standard patterns, no destructive operations beyond those explicitly approved in the Architect plan.

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors / 8 warnings (all pre-existing, unrelated to this implementation)

### Warning Breakdown (all pre-existing):

- 2 warnings: Unused imports in `bulk_entry_screen.dart` and test files
- 4 warnings: Unused local variables in test files
- 2 info messages: `use_build_context_synchronously` in async methods (bulk_entry_screen.dart, original_song_screen.dart)

**No new warnings introduced by this implementation.**

## Test Results

**Not run** — Backend-only changes with zero client code modifications. All validation performed via:

- Tier 1 pre-deployment SQL tests (documented in Engineer Report)
- Tier 2 post-deployment SQL tests (documented in Engineer Report)
- Direct SQL inspection by QA

Per Architect plan: "Run tests only if: The Architect plan requires them, The Engineer report says they were run, The changed area has relevant test coverage." This implementation affects database layer only; no Flutter test coverage exists for SQL migrations.

## Diff Safety Review

- **Secrets:** None found ✅
- **Debug artifacts:** None found ✅
- **Unrelated changes:** None — only 6 migration files + 1 Engineer report ✅
- **Accidental deletions:** None ✅
- **Formatting churn:** None ✅

### Staged Files (verified via `git status`):

```
new file:   docs/features/supabase-security-hardening/ENGINEER_REPORT.md
new file:   supabase/migrations/20260814120000_fix_regenerate_calendar_token_idor.sql
new file:   supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql
new file:   supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql
new file:   supabase/migrations/20260814120003_harden_security_definer_search_path.sql
new file:   supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql
new file:   supabase/migrations/20260814120005_harden_remaining_search_path_functions.sql
```

All files are new migrations + documentation. No modifications to existing code, configs, or migrations.

## Issues Found

None

## QA Regression Testing Guidance

Per the Architect plan, the following regression testing is required before production deployment:

### Primary Validation (must test):

1. **Calendar token regeneration** — verify user can regenerate their own token, URL updates correctly, verify **cannot** regenerate another user's token (should receive permission denied error)

2. **Financial entry access (contributor)** — create contributor with `can_view_financials = false`, verify they **cannot** see financial entries (both in UI and via direct API query)

3. **Financial entry access (admin/member)** — verify admin and member can still view/create/edit/delete financial entries

4. **Setlist reordering** — drag-and-drop reorder songs in a setlist, verify positions persist after reload, test with both small (2-3 songs) and large (10+ songs) setlists

5. **Special item insertion** — add set break or pause to setlist, verify it appears in correct position, verify reordering still works with mixed songs + special items

6. **Band deletion (admin)** — verify admin can still delete band (not affected by search_path hardening)

7. **Member role change (admin)** — verify admin can promote/demote members, verify contributor permissions save correctly when assigning contributor role

8. **Member removal (admin)** — verify admin can remove members (not self)

9. **User account deletion** — verify user can delete their own account via Settings

### Regression Coverage (spot-check):

10. Gig creation — verify no permission errors
11. Rehearsal creation — verify no permission errors
12. Setlist CRUD — create, view, edit, delete setlists
13. Song CRUD — add song to catalog, edit BPM/tuning inline, delete from setlist
14. Catalog integrity — verify Catalog setlist cannot be deleted

---

**QA Performed By:** GitHub Copilot QA Agent  
**Date:** 2026-08-14  
**Branch:** `bug/supabase-security-hardening`  
**Commit Status:** Ready for commit (pending manager approval)
