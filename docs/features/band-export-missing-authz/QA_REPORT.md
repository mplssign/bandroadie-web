# QA Report

## Feature Slug

`band-export-missing-authz`

## Feature Title

Add Server-Side Authorization Check for Band Data Export

## Final Verdict

**APPROVED**

## Validation Summary

Implementation correctly adds server-side authorization enforcement for band data export via a SECURITY DEFINER RPC function (`check_band_export_permission`) and corresponding guard in `DataBackupService.exportBandData()`. The fix matches the Architect plan exactly, introduces no regressions, passes static analysis with zero errors, and follows established RBAC patterns. Code is lean with no AI-generated bloat. The live UI path (Edit Band → Backup / Restore → Backup Data) remains intact with its existing client-side gate (`canExportBandData`), now backed by server-side enforcement. Ready for Tier 1/Tier 2 deployment verification and end-to-end testing.

## Architect Scope Review

- **Scope adherence:** compliant
- **Files modified:** as expected (1 new migration file, 1 modified Dart file)
- **Files off-limits:** not touched (verified `band_form_screen.dart`, `band_permissions.dart`, `main.dart`, all setlists/gigs/songs features untouched)

## Completeness Check

- **All Architect tasks implemented:** yes
  - ✅ Task 1 — Migration created with correct filename, RPC function definition, SECURITY DEFINER, SET search_path = public, admin/member/contributor/non-member logic, REVOKE from PUBLIC, GRANT to authenticated
  - ✅ Task 2 — Authorization check added at correct location (after login check, before `_buildBandExport()`), correct parameter name (`p_band_id`), user-friendly exception message
  - ✅ Task 3 — Verified git diff shows exactly 2 files (1 new, 1 modified), no unintended changes
- **Missing tasks:** none

## Behavior Verification

### Validation method

Code-path analysis with runtime flow verification

### Expected behavior confirmed:

1. **Admin role:** RPC returns `TRUE` → export proceeds (line 45-47 in migration)
2. **Member role:** RPC returns `TRUE` → export proceeds (line 45-47 in migration)
3. **Contributor role:** RPC returns `FALSE` → throws `DataBackupException` (line 51-53 in migration, lines 82-87 in Dart)
4. **Non-member:** RPC returns `FALSE` (no row in band_members) → throws exception (line 40-42 in migration)
5. **Unauthenticated:** RPC returns `FALSE` (`auth.uid()` is null) → throws exception (line 28-30 in migration)
6. **Default deny:** All unexpected cases return `FALSE` (line 57 in migration)

### Live UI path verified:

The production export flow remains unchanged and correct:

- Button visibility: gated by `BandPermissions.canExportBandData` (`isAdmin || isMember`) at `band_form_screen.dart:2191`
- Button press: calls `_showBackupRestoreSheet()` at `:2208`
- Backup panel: calls `_startExport()` at `:596` or `:635`
- Export initiation: calls `_performExport(band.id, band.name)` at `:649`
- Export execution: calls `DataBackupService.exportBandData(bandId, bandName)` at `:764`
- **New:** Authorization check (lines 76-88 in `data_backup_service.dart`) enforces server-side policy before any data queries
- Existing: `_buildBandExport()` queries remain unchanged (line 89 onwards)

The client-side UI gate prevents contributors from seeing the button; the new server-side check prevents direct service invocation bypassing the UI.

### Single call site confirmed:

`grep` search shows only one production call site for `exportBandData()`: `band_form_screen.dart:764` in the `_performExport()` method. No other code paths invoke this method.

### Result

Matches expected behavior. Authorization policy is correctly enforced server-side with clear, user-friendly error messages. The live UI flow for admin/member users is preserved unchanged.

## Regression Check

### Risk level: LOW

**Rationale:**
While this is a live production feature used by real users (typically elevated risk), the implementation mitigates risk through:

1. **Single injection point with fail-fast behavior** — Authorization check occurs before any data queries; failure throws immediately with no partial state
2. **Well-precedented pattern** — Follows exact structure of existing `check_financial_view_permission()` RPC (migration `20260814120001`), a proven pattern already deployed
3. **Minimal change surface** — Only one service method modified (13 lines added); no controllers, providers, repositories, or UI widgets touched
4. **Client-side gate preserved** — Existing UI button visibility check remains unchanged; server-side check adds defense-in-depth, not replacement
5. **Safe failure mode** — RPC errors propagate as exceptions, aborting export cleanly (same as any other Supabase query failure)
6. **No schema changes** — Migration adds one RPC function only; no table alterations, no RLS policy changes, no trigger modifications

**Risk factors (mitigated):**

- Feature is live and used by admin/member users → Any false denial would block legitimate exports, but the logic is simple (2 role checks) and matches client-side gate, minimizing false-denial risk
- New remote call adds latency/failure point → RPC is lightweight (single band_members query), and failure mode is safe (abort with error message)

### Systems reviewed:

- **Gigs:** Unaffected (export reads `gigs`, `gig_dates`, `gig_responses` via SELECT; no mutation, no flow change)
- **Rehearsals:** Unaffected (export reads `rehearsals` via SELECT; no mutation, no flow change)
- **Setlists / Catalog:** Unaffected (export reads `setlists`, `setlist_songs`, `setlist_special_items` via SELECT; no mutation, no flow change)
- **Members / RBAC:** Affected (authorization only) — New RPC queries `band_members` to retrieve role; no schema changes, no mutation of member data. Pattern matches existing `check_financial_view_permission` (already deployed, no known issues).
- **Auth / Session:** Unaffected (uses existing `auth.uid()` from Supabase session; no auth flow changes)
- **Routing:** Unaffected (export invoked from Edit Band screen button; no route changes)
- **Notifications:** Unaffected (export does not trigger or interact with notifications)
- **Platform (iOS / Android / Web / macOS):** Unaffected (Dart service backed by Supabase RPC; platform-agnostic)

### Regressions found:

None. Code-path analysis confirms:

- No changes to setlist repositories, controllers, or widgets
- No changes to gig/rehearsal repositories, controllers, or widgets
- No changes to member management logic beyond new read-only RPC
- No changes to existing `check_financial_view_permission` RBAC path
- No changes to initialization order (`main.dart` not modified)
- No changes to auth flow or session handling

## Database Safety

**Verified** — No issues found

### Migration safety:

- **Function signature:** `check_band_export_permission(p_band_id UUID)` matches Dart call site parameter (`params: {'p_band_id': bandId}`)
- **Return type:** `BOOLEAN` — Dart casts to `bool` correctly
- **SECURITY DEFINER:** Required to query `band_members` in function owner's context, bypassing caller's RLS. Same pattern as `check_financial_view_permission` (precedent: `20260814120001_fix_financial_entries_select_rbac.sql`)
- **SET search_path = public:** Prevents schema hijacking attacks per GUARDRAILS.md §4
- **No infinite recursion:** Function queries `band_members` table with SECURITY DEFINER, which bypasses RLS. No RLS policy on `band_members` calls this RPC, so no recursion risk.
- **No self-reference:** RPC does not query the table it protects (no table involved—this is a service-layer check, not an RLS policy)
- **No privilege escalation:** Function enforces a _narrower_ policy than RLS (admin/member only vs. RLS's "all active members"). Denies access for contributors who would otherwise have RLS SELECT access.
- **No cascade or destructive behavior:** Function is read-only (SELECT only from `band_members`), no INSERT/UPDATE/DELETE
- **C6 hardening applied:** `REVOKE EXECUTE ... FROM PUBLIC` prevents anon role execution; `GRANT EXECUTE ... TO authenticated` restricts to logged-in users only (proactive fix for C6 gap)

### RLS policies:

Not modified. Existing SELECT policies on `bands`, `songs`, `setlists`, `gigs`, `rehearsals`, etc., remain unchanged. The RPC adds an authorization layer _before_ queries are issued, not at the RLS level.

### Triggers:

Not affected.

### RPC function logic verified:

1. Line 27: `v_user_id := auth.uid()` — retrieves authenticated user ID
2. Lines 28-30: If `v_user_id IS NULL`, return `FALSE` — blocks unauthenticated
3. Lines 33-37: Query `band_members` for role where `band_id = p_band_id AND user_id = v_user_id AND status = 'active'`
4. Lines 40-42: If `v_role IS NULL` (no row found), return `FALSE` — blocks non-members
5. Lines 45-47: If `v_role IN ('admin', 'member')`, return `TRUE` — allows admin and member
6. Lines 51-53: If `v_role = 'contributor'`, return `FALSE` — blocks contributor (comment clarifies this is role-level, not permission-level)
7. Line 57: Default `RETURN FALSE` — deny any unexpected role value

Logic is correct, exhaustive, and defaults deny.

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors

8 pre-existing info/warnings found (all in unrelated files):

- 4 info: `use_build_context_synchronously` (2 in setlists widgets, 0 related to this change)
- 4 info: `sized_box_for_whitespace` (2 in setlists widgets, 0 related to this change)
- 4 warnings: `unused_local_variable` (all in test files, 0 related to this change)

**No new errors or warnings introduced by this implementation.**

## Test Results

**Not run** — No test files exist for `DataBackupService` (verified via `file_search test/**/*backup*`). The Architect plan specifies deployment-time verification (Tier 1/Tier 2 SQL tests) which require Supabase database access, not unit tests.

### Deployment verification required (per Architect plan):

**Tier 1 — Pre-deployment (before `supabase db push`):**

```sql
-- Verify migration SQL syntax via dry-run parse
BEGIN;
\i supabase/migrations/20260821120000_add_band_export_authorization.sql
ROLLBACK;
```

Expected: No syntax errors

**Tier 2 — Post-deployment (after `supabase db push`):**

```sql
-- Verify function exists and has correct definition
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'check_band_export_permission'
  AND pronamespace = 'public'::regnamespace;
```

Expected: Returns function definition with SECURITY DEFINER, SET search_path = public, admin/member allow, contributor deny

**RPC behavior tests with test UUIDs:**

- Admin role: `SELECT check_band_export_permission('<test_band_id>')` as admin → TRUE
- Member role: `SELECT check_band_export_permission('<test_band_id>')` as member → TRUE
- Contributor role: `SELECT check_band_export_permission('<test_band_id>')` as contributor → FALSE
- Non-member: `SELECT check_band_export_permission('<test_band_id>')` as non-member → FALSE
- Unauthenticated: RPC call without session → FALSE or auth error

**End-to-end UI flow test:**

- As admin: Edit Band → Backup / Restore → Backup Data → should succeed, file saved
- As member: Edit Band → Backup / Restore → Backup Data → should succeed, file saved
- As contributor: Verify button is hidden; if service invoked directly, should fail with user-friendly error message

## Diff Safety Review

### Secrets:

None found. Migration contains only function definition (no credentials). Dart change contains only RPC call (no secrets).

### Debug artifacts:

None. No `print` statements, TODO comments, temporary flags, or test scaffolding in production code.

### Unrelated changes:

None. `git diff --name-status` shows exactly 1 modified file (M): `lib/features/settings/data_backup_service.dart`. Migration file is new (untracked), as expected.

### Unintended file deletions:

None.

### Formatting churn:

None. Engineer report confirms `dart format` reported 0 changes.

### Dead code / \_showExportDialog:

Not touched (correct). `_showExportDialog()` at `band_form_screen.dart:653-764` remains off-limits per Architect plan. The dead method (`// ignore: unused_element`) has no callers and was correctly left unchanged.

## Code Efficiency Review

Evaluated per GUARDRAILS.md §7a (AI-generated bloat screening):

### Dead code / unused imports, vars, params:

**None found.**

- Migration: All function logic is reachable; no unused variables
- Dart: `isAuthorized` variable is used immediately in guard (line 82); no unused imports or parameters

### Redundant restating comments:

**None found.**

- Migration comment (lines 1-14): Explains authorization policy and role-level restrictions, not code mechanics. Appropriate for a SECURITY DEFINER function with non-obvious policy.
- Dart comment (line 76): "Server-side authorization check (admin and member only)" — explains policy enforcement point, not a restatement of the RPC call syntax. Appropriate.

### Unnecessary abstraction for single call sites:

**None found.**

- Authorization check is inline at the single enforcement point (method entry), not wrapped in a separate helper
- RPC call is direct, not abstracted behind a repository method (appropriate for a service-layer security gate)

### Unneeded defensive checks (impossible-case guards, try/catch):

**None found.**

- `as bool` cast (line 80): Required by Dart's type system — Supabase RPC returns `dynamic`, must be cast to `bool` for the guard
- No redundant null checks (covered by RPC logic)
- No unnecessary try/catch around code that cannot throw

### Duplicated logic that should reuse existing code:

**None found.**

- Authorization logic is new; does not duplicate existing `canExportBandData` client check (server-side RPC vs. client-side computed property)
- Pattern follows existing `check_financial_view_permission` precedent but does not duplicate it (different policy: export blocks all contributors, financial allows if `can_view_financials=true`)

### Overall assessment:

**Lean.** 13 lines added in Dart (2 comment, 7 RPC call, 4 exception throw). Migration is minimal (65 lines total including comments and whitespace; function body is ~35 lines). No unnecessary complexity, no over-engineering, no bloat. Implementation is the most direct path to satisfy the Architect plan.

## Issues Found

None.

---

## Deployment Checklist

Before merging to `main`, complete:

1. ✅ **Static analysis passed** — `flutter analyze` 0 errors
2. ⏳ **Tier 1 pre-deploy verification** — SQL syntax check (dry-run parse in Supabase SQL Editor or psql)
3. ⏳ **Migration deployment** — `supabase db push` (staging first, then production)
4. ⏳ **Tier 2 post-deploy verification** — RPC function existence, permissions, and behavior tests (admin/member/contributor/non-member/unauthenticated scenarios)
5. ⏳ **End-to-end UI test** — Edit Band → Backup / Restore → Backup Data for admin and member roles on at least one platform (iOS, Android, Web, or macOS)
6. ⏳ **Negative test** — Attempt direct `DataBackupService.exportBandData()` invocation as contributor (should fail with user-friendly message)

## Additional Notes

### Precedent comparison:

This implementation closely follows the `check_financial_view_permission` pattern from `20260814120001_fix_financial_entries_select_rbac.sql` with one improvement: the new RPC includes C6 hardening (`REVOKE EXECUTE FROM PUBLIC`) that the financial RPC was missing. Consider backporting this hardening to `check_financial_view_permission` in a future cleanup pass.

### Client-side gate remains critical:

While the server-side check now enforces the policy, the existing client-side UI gate (`canExportBandData` at `band_form_screen.dart:2191`) remains important for UX—it prevents contributors from seeing a button that would immediately fail on press. Both layers work together: UI gate provides immediate feedback, server-side check provides defense-in-depth.

### Error message UX:

The exception message "You do not have permission to export this band's data. Only admins and members can create backups." is clear, user-friendly, and actionable. It does not expose internal implementation details (role names, RPC function names, or database structure).

---

**QA Verdict: APPROVED**  
Ready for deployment with Tier 1/Tier 2 verification and end-to-end testing.
