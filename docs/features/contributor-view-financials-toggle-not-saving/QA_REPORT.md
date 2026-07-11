# QA Report

## Feature Slug

`bug/contributor-view-financials-toggle-not-saving`

---

## Feature Title

Fix update_member_role RPC to persist can_view_financials toggle

---

## Final Verdict

**APPROVED**

---

## Validation Summary

Verified the new migration file `20260711120000_fix_update_member_role_can_view_financials.sql` is byte-for-byte identical to the original `update_member_role` function (from migration `20260302000000_band_user_roles.sql` lines 379-463) except for the single required change: adding `can_view_financials = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),` to the UPDATE statement's SET clause. Function signature, SECURITY DEFINER, search_path, and GRANT EXECUTE all preserved exactly. SQL syntax correct (trailing commas verified). Migration has not been applied to any environment.

---

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** None (migration file created as expected, no Flutter code changes)
- **Files off-limits:** Not touched

---

## Completeness Check

- **All Architect tasks implemented:** Task 1 completed (migration file created with correct function replacement)
- **Missing tasks:** Tasks 2-4 (db reset, db push, verification) intentionally deferred per project convention — Tony applies migrations manually after confirming project-ref configuration

---

## Behavior Verification

- **Validation method:** Code-path analysis (line-by-line comparison against original function)
- **Result:** Matches expected — single line added to UPDATE statement SET clause in correct position (after `can_view_members`, before `updated_at`) with correct default value (FALSE) and correct syntax

---

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:**
  - Members/RBAC (affected — fixes contributor permission persistence)
  - Financials (affected — downstream visibility depends on this permission)
  - All other systems unaffected (gigs, rehearsals, setlists, auth, routing, notifications)
- **Regressions found:** None
  - Change is additive (adds one field to existing UPDATE)
  - Other permission fields unchanged
  - No RLS policy changes
  - No trigger changes
  - No auth flow changes
  - Function signature unchanged (no client compatibility concerns)

---

## Database Safety

**Verified**

- Migration uses `CREATE OR REPLACE FUNCTION` (safe for already-applied functions)
- Function body copied exactly from original except for single field addition
- SECURITY DEFINER preserved with `SET search_path = public` (prevents search_path injection)
- No RLS self-reference risk
- No privilege escalation
- No unintended cascade behavior
- Default value FALSE matches column schema and fail-closed philosophy
- GRANT EXECUTE statement retained (maintains existing access model)

---

## Analyzer Results

**Not applicable** — This is a database-only fix with no Dart code changes. Running `flutter analyze` would only validate unchanged Flutter codebase, providing no value for this migration. All client code (models, UI, repository, controller) was already correct per Architect plan.

---

## Test Results

**Not run** — Per project convention and Engineer report, SQL verification tests (Tier 1 and Tier 2) cannot be executed by Engineer or QA against a real database. Migration has not been applied to any environment. Tony must manually apply migration and run the provided SQL test scripts to confirm:

- Column exists with correct schema
- RLS allows admin UPDATE
- Function contains the fix
- Full integration test with RPC call succeeds for TRUE and FALSE values
- Other permission fields unaffected
- No production data corruption

This is expected behavior for database-only changes and is not a QA gap.

---

## Diff Safety Review

- **Secrets:** None found
- **Debug artifacts:** None found
- **Unrelated changes:** None — single migration file only

---

## Migration-Specific Verification

**Confirmed per user instructions:**

1. ✓ **Byte-for-byte comparison:** Read `supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql` line-by-line against original function in `supabase/migrations/20260302000000_band_user_roles.sql` (lines 379-465 including GRANT statement). Confirmed identical except for single new line.

2. ✓ **Function signature:** Preserved exactly
   - Parameter names, types, and order: identical
   - Return type: `RETURNS BOOLEAN` unchanged
   - Language: `LANGUAGE plpgsql` unchanged

3. ✓ **SECURITY DEFINER:** Present and unchanged

4. ✓ **Internal SET statement:** `SET search_path = public;` present and unchanged (line 29 in new migration)

5. ✓ **GRANT EXECUTE:** Trailing statement preserved exactly (line 100 in new migration)

6. ✓ **New line placement:** Correctly placed after `can_view_members` (line 95) and before `updated_at` (line 97)

7. ✓ **SQL syntax:** Trailing comma correctness verified
   - `can_view_members` line retains original trailing comma
   - New `can_view_financials` line has trailing comma
   - `updated_at` line correctly has no trailing comma (final item in SET clause)

8. ✓ **Default value:** `FALSE` matches column schema default and fail-closed philosophy documented in `contributor_permissions.dart`

9. ✓ **Migration status:** Confirmed NOT applied to any environment (no applied migrations tracked in Supabase CLI state, Tony will apply manually)

---

## Issues Found

None

---

## Additional Notes

- This bug fix branch was created from `feature/expense-delete-drawer` branch, not from `main`. Migration file `20260711081810_tighten_financial_entries_rbac.sql` is present in working tree from parent branch but is not part of this feature's scope.

- Engineer correctly followed project convention of not applying migrations directly. Tony retains manual control over migration application to prevent accidental deployment to wrong environment.

- The Architect plan correctly identified this as a server-side-only fix. All Flutter client code was already functioning correctly (model includes field, UI renders toggle, repository serializes field in JSON payload). Only the RPC function was missing the field in its UPDATE statement.

---

## QA Agent Notes

This is a textbook example of a minimal, surgical database fix:

- Single function affected
- Single line added
- No architectural changes
- No client changes required
- Clear root cause identified and addressed
- Low regression risk
- Unblocks verification of dependent feature (`feature/expense-delete-drawer` RBAC tightening)

Ready for Tony to apply migration and execute SQL verification tests.
