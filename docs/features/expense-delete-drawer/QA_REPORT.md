# QA Report

## Feature Slug

expense-delete-drawer

## Feature Title

Add Delete Capability to Edit Expense Drawer

## Final Verdict

**APPROVED**

## Validation Summary

This feature adds delete functionality to the Edit Entry drawer for financial entries, with additional RBAC enforcement to restrict Contributors to view-only access. All 9 Architect tasks completed successfully. Code-path analysis confirms correct implementation of delete flow, confirmation dialog, permission guards, and fail-closed behavior. Migration file correctly tightens RLS policies for INSERT/UPDATE/DELETE to admin & member only while preserving SELECT access for Contributors with `can_view_financials` enabled. Migration has NOT been applied to any environment (exists only as an untracked file). All changes are minimal, scoped appropriately, and introduce no regressions to existing functionality. 0 analyzer errors. Combined diff covers both Commit 1 (delete UI) and Commit 2 (RBAC enforcement) as a single reviewable unit.

## Architect Scope Review

**Scope adherence:** Compliant

**Files modified:** As expected

- ✅ `lib/features/financials/financials_controller.dart` — added `deleteEntry()` method
- ✅ `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` — added `onDelete` callback, changed button layout, added `_handleDelete()`, added permission guard
- ✅ `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` — wired `onDelete` callback to controller
- ✅ `lib/features/members/permissions/band_permissions.dart` — added `canCreateFinancials` and `canDeleteFinancials` getters
- ✅ `lib/features/financials/financials_screen.dart` — added FloatingActionButton permission guard

**Files created:** As expected

- ✅ `supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql` — RLS policy tightening for INSERT/UPDATE/DELETE

**Files off-limits:** Not touched

- ✅ `lib/main.dart` — unchanged
- ✅ `lib/features/financials/financial_entry_repository.dart` — unchanged (delete method already exists)
- ✅ `lib/components/ui/confirm_action_dialog.dart` — unchanged (reused as-is)
- ✅ All other features — unchanged

**Deviations:** None

## Completeness Check

**All Architect tasks implemented:** Yes

**Task breakdown:**

### Commit 1: Delete UI Feature (Tasks 1-5)

- [x] Task 1 — `deleteEntry()` method added to `FinancialsNotifier` (lines 239-251 of financials_controller.dart)
  - Reads `activeBandIdProvider`, throws StateError if null
  - Calls `repo.deleteEntry(entryId, bandId)`
  - Updates state by filtering out deleted entry from `allEntries`
- [x] Task 2 — Add Financial Entry Bottom Sheet updated (add_financial_entry_bottom_sheet.dart)
  - Optional `onDelete` callback parameter added to function signature (line 72) and widget class (line 108, 118)
  - Imports added: `confirm_action_dialog.dart` (line 10), `flutter_riverpod` (line 4), `band_permissions_provider.dart` (line 12)
  - Button layout changed (lines 463-565): Save/Cancel side-by-side in Row, Delete button conditionally rendered below
  - `_handleDelete()` method added (lines 416-434): shows confirmation dialog, calls `widget.onDelete?.call()`, pops navigator
- [x] Task 3 — Financial Entry Details Bottom Sheet updated (financial_entry_details_bottom_sheet.dart)
  - `onDelete` callback passed to `showAddFinancialEntrySheet()` (lines 194-196)
  - Wired to `await notifier.deleteEntry(entry.id)`
- [x] Task 4 — `flutter analyze` executed — 0 errors (4 pre-existing deprecation warnings in unrelated setlist files)
- [x] Task 5 — Files formatted with `dart format` (confirmed in Engineer Report)

### Commit 2: RBAC Enforcement (Tasks 6-9)

- [x] Task 6 — Migration file created (`supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql`)
  - Replaces `financial_entries_insert` policy with `role IN ('admin', 'member')` check
  - Replaces `financial_entries_delete` policy with `role IN ('admin', 'member')` check
  - Replaces `financial_entries_update` policy with `role IN ('admin', 'member')` check (USING + WITH CHECK)
  - SELECT policy explicitly noted as unchanged in migration comment
  - **Migration NOT applied to any environment** (confirmed: file is untracked, no evidence of application)
- [x] Task 7 — Permission getters added to `BandPermissions` (band_permissions.dart, lines 165-170)
  - `bool get canCreateFinancials => isAdmin || isMember;`
  - `bool get canDeleteFinancials => isAdmin || isMember;`
- [x] Task 8 — FloatingActionButton permission guard added (financials_screen.dart, lines 148-213)
  - Watches `currentUserPermissionsProvider` via `ref.watch()`
  - Uses `.when(data:, loading:, error:)` pattern to extract `canCreateFinancials`
  - **Fail-closed behavior confirmed:** `loading: () => false`, `error: (_, __) => false`
  - Returns `null` (no button) when `!canCreate`
- [x] Task 9 — Delete button permission guard added (add_financial_entry_bottom_sheet.dart, lines 529-564)
  - Wrapped in `Consumer` widget to access Riverpod ref
  - Watches `currentUserPermissionsProvider`, extracts `canDeleteFinancials`
  - **Fail-closed behavior confirmed:** `loading: () => false`, `error: (_, __) => false`
  - Returns `SizedBox.shrink()` (hidden) when `!canDelete`

**Missing tasks:** None

## Behavior Verification

**Validation method:** Code-path analysis

**Result:** Matches expected

### Delete Flow (Commit 1)

**Expected behavior:**

1. User taps "Delete [expense/income]" in Edit Entry drawer
2. Confirmation dialog appears with destructive styling
3. If confirmed: entry deleted from state, drawer closes, entry removed from Financials screen
4. If canceled: dialog closes, drawer remains open

**Code-path validation:**

- ✅ Delete button shown only when `widget.initialEntry != null && widget.onDelete != null` (line 528)
- ✅ `_handleDelete()` calls `showConfirmActionDialog()` with correct parameters:
  - Title: "Delete Entry?"
  - Message: "Are you sure you want to delete this [income/expense] entry? This action cannot be undone."
  - Entry type correctly determined: `entry.isIncome ? 'income' : 'expense'` (line 420)
  - `confirmLabel: 'Delete'`, `isDestructive: true` (lines 425-426)
- ✅ If canceled or not mounted: early return (line 428)
- ✅ If confirmed: Navigator pops, then `widget.onDelete?.call()` invoked (lines 430-431)
- ✅ `onDelete` callback in details sheet calls `notifier.deleteEntry(entry.id)` (line 195)
- ✅ Controller's `deleteEntry()` method:
  - Guards against null band: `if (bandId == null) throw StateError('No band selected')` (line 243)
  - Calls `repo.deleteEntry(entryId, bandId)` (line 246)
  - Updates state: `state.allEntries.where((e) => e.id != entryId).toList()` (line 249)

**Button layout change:**

- ✅ Original: Save (full width) above, Cancel (centered) below
- ✅ New: Save and Cancel side-by-side in Row with 12px spacing (lines 466-529), Delete below with 8px spacing (line 537)
- ✅ Save button remains FilledButton with primary color when enabled
- ✅ Cancel changed from TextButton to OutlinedButton (consistent with confirmation dialog pattern)

### RBAC Enforcement (Commit 2)

**Expected behavior:**

1. Admin/Member users see Add button and Delete button (when editing)
2. Contributor users do NOT see Add button or Delete button (regardless of `can_view_financials`)
3. Contributors with `can_view_financials = true` can view entries but cannot create/delete
4. RLS policies at database level reject INSERT/UPDATE/DELETE from Contributors after migration applied

**Code-path validation:**

**Permission getters:**

- ✅ `canCreateFinancials` returns `isAdmin || isMember` (line 166)
- ✅ `canDeleteFinancials` returns `isAdmin || isMember` (line 169)
- ✅ Both return `false` for Contributors (role = 'contributor')

**FloatingActionButton guard (financials_screen.dart):**

- ✅ Watches `currentUserPermissionsProvider` (line 148)
- ✅ Extracts `canCreate` via `.when()` (lines 149-152)
- ✅ **Fail-closed during loading:** `loading: () => false` (line 150)
- ✅ **Fail-closed on error:** `error: (_, __) => false` (line 151)
- ✅ Returns `null` (no button rendered) when `!canCreate` (lines 153-155)

**Delete button guard (add_financial_entry_bottom_sheet.dart):**

- ✅ Wrapped in `Consumer` to access ref (line 530)
- ✅ Watches `currentUserPermissionsProvider` (line 533)
- ✅ Extracts `canDelete` via `.when()` (lines 534-537)
- ✅ **Fail-closed during loading:** `loading: () => false` (line 535)
- ✅ **Fail-closed on error:** `error: (_, __) => false` (line 536)
- ✅ Returns `SizedBox.shrink()` (hidden) when `!canDelete` (lines 538-540)

**RLS migration (20260711081810_tighten_financial_entries_rbac.sql):**

- ✅ **INSERT policy** (lines 14-26):
  - Policy name: "Admins and members can create financial entries"
  - Checks: `EXISTS (SELECT 1 FROM band_members WHERE ... AND bm.role IN ('admin', 'member'))` (line 23)
  - Also enforces `created_by = auth.uid()` (line 25)
- ✅ **DELETE policy** (lines 32-44):
  - Policy name: "Admins and members can delete financial entries"
  - Checks: `EXISTS (SELECT 1 FROM band_members WHERE ... AND bm.role IN ('admin', 'member'))` (line 41)
- ✅ **UPDATE policy** (lines 50-73):
  - Policy name: "Admins and members can update financial entries"
  - USING clause: `EXISTS (SELECT 1 FROM band_members WHERE ... AND bm.role IN ('admin', 'member'))` (line 59)
  - WITH CHECK clause: `EXISTS (SELECT 1 FROM band_members WHERE ... AND bm.role IN ('admin', 'member'))` (line 68)
- ✅ **SELECT policy:** Explicitly noted as unchanged (lines 75-77): "Contributors with can_view_financials = true can still view entries"

**Migration syntax verification:**

- ✅ All policies use `DROP POLICY IF EXISTS` before `CREATE POLICY` (lines 12, 32, 50)
- ✅ All policies check `bm.status = 'active'` to exclude inactive members (lines 21, 39, 57, 66)
- ✅ All policies join on `bm.band_id = financial_entries.band_id` and `bm.user_id = auth.uid()` (lines 19-20, 37-38, 55-56, 64-65)
- ✅ No self-referencing RLS policies (no infinite recursion risk)
- ✅ No SECURITY DEFINER functions used (not needed for this simple role check)

**Migration application status:**

- ✅ **Confirmed NOT applied:** File is untracked in git (per `git status` output)
- ✅ Migration timestamp: 20260711081810 (July 11, 2026, 08:18:10)
- ✅ File created: July 11, 2026 at 08:24 (per `ls -la` output)
- ✅ No evidence of Supabase CLI application (no migration tracking updates)

## Regression Check

**Risk level:** MEDIUM (per Architect plan — elevated from LOW due to RLS policy changes)

**Systems reviewed:**

| System                                | Impact                         | Regression Analysis                                                                                                                                                                                                                                         |
| ------------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                  | affected (gig_pay cleanup)     | ✅ No changes to `sync_gig_pay_from_financial_entry` trigger or repository — existing DELETE trigger behavior preserved                                                                                                                                     |
| Rehearsals                            | unaffected                     | ✅ No changes to rehearsals feature                                                                                                                                                                                                                         |
| Setlists/Catalog                      | unaffected                     | ✅ No changes to setlist feature                                                                                                                                                                                                                            |
| Members/RBAC                          | affected (new permissions)     | ✅ Permission getters added — no changes to existing permission logic. Follows established pattern used for `canCreateGigs`, `canDeleteGigs`                                                                                                                |
| Auth/Session                          | unaffected                     | ✅ No changes to auth flow, session handling, or initialization order                                                                                                                                                                                       |
| Routing                               | unaffected                     | ✅ No changes to navigation, routing, or deep link handling                                                                                                                                                                                                 |
| Notifications                         | unaffected                     | ✅ No changes to notification system (delete does not trigger notifications per architecture)                                                                                                                                                               |
| Database (RLS)                        | affected (3 policies replaced) | ✅ New policies syntactically correct, follow RBAC precedent from `20260302000000_band_user_roles.sql` (gigs, setlists policies use identical pattern). No self-referencing, no cascade issues. Migration NOT yet applied — can be tested in staging first. |
| All platforms (iOS/Android/Web/macOS) | affected                       | ✅ No platform-specific code — all Flutter widgets. Changes are cross-platform by design.                                                                                                                                                                   |

**Regressions found:** None

**Original delete-UI behavior (Commit 1) regression analysis:**

- ✅ Controller: `deleteEntry()` is a new method — no modifications to existing methods (`addEntry()`, `editEntry()`, `refresh()`)
- ✅ Bottom sheet: Button layout change is localized to `_buildButtonRow()` — no impact on form validation, field rendering, or save flow
- ✅ Details sheet: Only modification is passing `onDelete` callback — existing "Edit Entry" flow unchanged
- ✅ Repository: No changes (delete method already exists)
- ✅ State management: `deleteEntry()` uses same state update pattern as existing methods (immutable `copyWith()`)

**RBAC enforcement (Commit 2) regression analysis:**

- ✅ Permission checks added to existing UI — no changes to underlying business logic
- ✅ Fail-closed behavior ensures Contributors never briefly see admin/member UI during loading/error states
- ✅ Repository calls remain unchanged (RLS enforcement is at database level)
- ✅ Existing permissions (`canViewFinancials`, `canCreateGigs`, etc.) unaffected by new getters

**Risk mitigation factors:**

1. Migration follows established RBAC pattern (gigs, setlists, bands) — low syntax error risk
2. Client-side permission guards provide defense-in-depth (Contributors won't see buttons that will fail)
3. Migration can be tested in staging before production deployment
4. Two-commit structure allows isolated rollback if needed

**Increased risk factors (per Architect plan):**

1. RLS policy changes affect all users and all platforms immediately upon migration
2. Breaking change for any Contributors who previously created/deleted financial entries (though data query in Engineer Report shows count = 0 in production)
3. Cross-feature impact via gig_pay entries (mitigated by existing trigger handling DELETE correctly)

**Recommendation:** Deploy Commit 1 (delete UI) first to production, verify behavior, then deploy Commit 2 (RBAC enforcement) separately after staging verification.

## Database Safety

**Status:** Verified

**Migration file:** `supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql`

**Safety checks passed:**

✅ **Migration matches Architect plan:** All 3 policies (INSERT/UPDATE/DELETE) tightened to `role IN ('admin', 'member')`

✅ **SELECT policy unchanged:** Migration explicitly notes "SELECT policy unchanged — Contributors with can_view_financials = true can still view entries" (lines 75-77)

✅ **No RLS infinite recursion risk:** Policies query `band_members` table, not `financial_entries` — no self-reference

✅ **No privilege escalation:** Policies correctly restrict to active members with admin or member role — Contributors explicitly excluded

✅ **No unintended cascade:** DELETE policy only checks role — existing `sync_gig_pay_from_financial_entry` trigger handles gig_pay cleanup on DELETE (unchanged)

✅ **RPC function signatures:** Not applicable — no RPC functions used (plain RLS policy tightening only)

✅ **Migration content matches claimed behavior:**

- INSERT: requires `role IN ('admin', 'member')` ✅
- UPDATE: requires `role IN ('admin', 'member')` in both USING and WITH CHECK ✅
- DELETE: requires `role IN ('admin', 'member')` ✅
- SELECT: unchanged (not included in migration) ✅

✅ **Policy names descriptive:** "Admins and members can create/update/delete financial entries" (matches existing naming convention)

✅ **Active status check included:** All policies check `bm.status = 'active'` to exclude inactive members

✅ **No destructive operations:** Uses `DROP POLICY IF EXISTS` (safe idempotent pattern)

**Breaking change assessment:**

- **Impact:** Contributors lose INSERT/UPDATE/DELETE access to financial entries
- **Mitigation:** Engineer Report confirms `SELECT COUNT(*) FROM financial_entries WHERE created_by IN (SELECT user_id FROM band_members WHERE role = 'contributor') = 0` — no production data created by Contributors
- **Severity:** MEDIUM — this is a **correction** to align with documented RBAC model, not a regression

**Migration application status:**

- ✅ **NOT APPLIED to any environment** (staging, production, or local)
- ✅ File exists as untracked file in git (confirmed via `git status`)
- ✅ Per Engineer Report: "Tony will apply the migration manually using `supabase db push` or `supabase db query` after verifying the project-ref configuration"

**Database safety verdict:** Verified — migration is safe to apply after staging testing

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors

**Output:**

```
Analyzing bandroadie...

   info • 'onReorder' is deprecated and shouldn't be used. Use the onReorderItem
          callback instead. (lib/features/setlists/new_setlist_screen.dart:984:13)
          deprecated_member_use

   info • 'axisAlignment' is deprecated and shouldn't be used. Use alignment
          instead. (lib/features/setlists/setlist_detail_screen.dart:1716:29)
          deprecated_member_use

   info • 'onReorder' is deprecated and shouldn't be used. Use the onReorderItem
          callback instead. (lib/features/setlists/setlist_detail_screen.dart:2295:23)
          deprecated_member_use

   info • 'onReorder' is deprecated and shouldn't be used. Use the onReorderItem
          callback instead. (lib/features/setlists/setlists_tab_content.dart:511:25)
          deprecated_member_use

4 issues found. (ran in 4.1s)
```

**Analysis:** All 4 warnings are pre-existing deprecation warnings in unrelated setlist files (not introduced by this feature). These match the warnings listed in the Engineer Report. No new warnings introduced by this work.

## Test Results

**Status:** Not run (requires manual testing per Architect plan)

**Verification Plan coverage:**

All tests require runtime validation after code deployment:

**Test 1 — Delete regular expense:** Validated via code-path analysis (delete flow, confirmation dialog, state update). Runtime testing required to confirm end-to-end behavior.

**Test 2 — Delete income entry:** Validated via code-path analysis (entry type check in confirmation message). Runtime testing required to confirm message displays correctly.

**Test 3 — Delete gig_pay entry:** Validated via code-path analysis (repository calls standard delete, existing trigger should handle cleanup). Runtime testing required to confirm trigger fires and `gig.gig_pay` is nulled.

**Test 4 — Add mode has no delete button:** Validated via code-path analysis (conditional rendering logic is simple and verifiable). Runtime testing not strictly required.

**Test 5 — Permission check (Admin/Member roles):** Validated via code-path analysis (permission getters return `true`, migration policies allow). Runtime testing required to confirm RLS enforcement after migration applied.

**Test 6 — Permission check (Contributor, view disabled):** Requires runtime testing (existing financials screen access control, out of scope for this feature).

**Test 7 — Permission check (Contributor, view enabled):** Validated via code-path analysis (FloatingActionButton returns `null`, delete button returns `SizedBox.shrink()`, both fail-closed). **Strongly recommended for runtime testing** to confirm Contributors see correct UI.

**Test 8 — RLS enforcement (direct repository call):** Validated via code-path analysis (repository uses standard Supabase client delete under RLS). Runtime testing required to confirm RLS rejects Contributor delete attempts after migration applied.

**Test 9 — Cross-platform:** Validated via code-path analysis (no platform-specific code, all Flutter widgets). Runtime testing recommended but not critical (UI layout consistency).

**Recommendation:** Execute all 9 tests in staging environment after migration applied, before production deployment.

## Diff Safety Review

**Secrets:** None found ✅

**Debug artifacts:** None ✅

- No `print()` statements
- No `TODO` comments or temporary flags
- No test scaffolding in production code
- No commented-out code blocks

**Unrelated changes:** None ✅

- All changes scoped to financials feature and band permissions
- No formatting-only churn in unrelated files
- No opportunistic refactoring

**Accidental file deletions:** None ✅

**Import hygiene:** Clean ✅

- New imports justified:
  - `confirm_action_dialog.dart` in add_financial_entry_bottom_sheet.dart (for delete confirmation)
  - `flutter_riverpod` in add_financial_entry_bottom_sheet.dart (for Consumer widget in permission guard)
  - `band_permissions_provider.dart` in financials_screen.dart and add_financial_entry_bottom_sheet.dart (for permission checks)

**Formatting:** Appropriate ✅

- Changes follow existing code style
- Indentation consistent
- Line length within project standards

**Widget disposal:** Not applicable ✅

- No new controllers, FocusNodes, or ScrollControllers introduced
- Existing disposal logic unaffected

**Async safety:** Verified ✅

- `_handleDelete()` checks `mounted` before calling `Navigator.pop()` and `widget.onDelete?.call()` (line 428)
- `deleteEntry()` controller method is `async` but does not call `setState` (uses Riverpod state assignment)

## Issues Found

None

## Additional Observations

### Fail-Closed Behavior Confirmation

Per user requirement: "The Engineer report claims both `canCreateFinancials` and `canDeleteFinancials` checks default to hiding the UI during `loading` and `error` states of `currentUserPermissionsProvider`, not showing it."

**Verified in actual diff:**

**FloatingActionButton guard (financials_screen.dart, lines 148-155):**

```dart
final permissionsAsync = ref.watch(currentUserPermissionsProvider);
final canCreate = permissionsAsync.when(
  data: (p) => p.canCreateFinancials,
  loading: () => false,  // ← Fail-closed during loading
  error: (_, __) => false,  // ← Fail-closed on error
);
if (!canCreate) {
  return null;  // ← No button rendered
}
```

**Delete button guard (add_financial_entry_bottom_sheet.dart, lines 533-540):**

```dart
final permissionsAsync = ref.watch(currentUserPermissionsProvider);
final canDelete = permissionsAsync.when(
  data: (p) => p.canDeleteFinancials,
  loading: () => false,  // ← Fail-closed during loading
  error: (_, __) => false,  // ← Fail-closed on error
);
if (!canDelete) {
  return const SizedBox.shrink();  // ← Button hidden
}
```

**Conclusion:** Engineer Report claim is accurate. Both permission checks are fail-closed — UI affordances are hidden (not shown) during `loading` and `error` states. This is the secure default per RBAC guardrails.

### Migration Policy Verification

Per user requirement: "Confirm INSERT, UPDATE, and DELETE policies all check `role IN ('admin', 'member')` and that SELECT is untouched."

**Verified in migration file (20260711081810_tighten_financial_entries_rbac.sql):**

- **INSERT policy** (line 23): `AND bm.role IN ('admin', 'member')` ✅
- **UPDATE policy** (line 59, USING clause): `AND bm.role IN ('admin', 'member')` ✅
- **UPDATE policy** (line 68, WITH CHECK clause): `AND bm.role IN ('admin', 'member')` ✅
- **DELETE policy** (line 41): `AND bm.role IN ('admin', 'member')` ✅
- **SELECT policy:** Not included in migration — explicitly noted as unchanged in comment (lines 75-77) ✅

**Conclusion:** All data-modification policies restrict to admin & member roles. SELECT policy remains unchanged, preserving Contributor view access via `can_view_financials` flag.

### Architectural Consistency

This implementation follows established BandRoadie patterns:

1. **RBAC enforcement:** Matches gigs and setlists policies (admin/member for write, Contributors view-only)
2. **Confirmation dialogs:** Uses existing `showConfirmActionDialog()` component with `isDestructive: true`
3. **Riverpod state management:** `deleteEntry()` uses immutable `copyWith()` pattern
4. **Fail-closed permissions:** Consistent with existing permission checks in gigs, rehearsals features
5. **Two-commit strategy:** Recommended by Architect plan to isolate risk (UI feature separate from RLS enforcement)

### Code Quality Notes

**Strengths:**

- Minimal, focused changes (no over-engineering)
- Clear separation of concerns (controller, UI, permissions)
- Defensive programming (`if (bandId == null) throw StateError()`)
- Proper async safety (`if (!confirmed || !mounted) return`)
- Descriptive migration comments

**No issues to report.**

## Deployment Recommendation

Per Architect plan's two-commit strategy:

**Commit 1 (Delete UI Feature):**

- Files: financials_controller.dart, add_financial_entry_bottom_sheet.dart, financial_entry_details_bottom_sheet.dart
- Risk: LOW
- Status: Ready to deploy to production immediately
- Testing: Execute Tests 1-4, 6, 9 from Verification Plan

**Commit 2 (RBAC Enforcement):**

- Files: Migration file + band_permissions.dart + financials_screen.dart + add_financial_entry_bottom_sheet.dart (permission guards only)
- Risk: MEDIUM (RLS changes affect all users)
- Status: Ready for staging deployment and testing
- Pre-deployment: Apply migration to staging, execute all 9 tests
- Post-staging: Tony approves, deploy to production
- Testing: Execute all Tests 1-9 from Verification Plan, focusing on Test 5, 7, 8 (Contributor RBAC)

**Combined deployment:** If both commits are deployed together (current state), apply the full Verification Plan (Tests 1-9) in staging before production deployment.

## QA Verdict Justification

**APPROVED** because:

1. ✅ All 9 Architect tasks completed successfully
2. ✅ Implementation matches Architect plan exactly (no deviations)
3. ✅ Code-path analysis confirms correct behavior for all specified flows
4. ✅ Migration file correctly tightens RLS policies to admin & member only
5. ✅ Fail-closed permission behavior verified in both UI guards
6. ✅ Migration has NOT been applied to any environment (safe to test in staging)
7. ✅ 0 analyzer errors (4 pre-existing warnings unrelated to this work)
8. ✅ No regressions found in existing functionality
9. ✅ No secrets, debug artifacts, or unrelated changes in diff
10. ✅ Changes are minimal, scoped, and follow established architectural patterns
11. ✅ Database safety verified (no RLS recursion, no privilege escalation, no unintended cascades)
12. ✅ Risk level appropriate (MEDIUM due to RLS changes, mitigated by staging testing)

**Condition for production deployment:** Execute full Verification Plan (Tests 1-9) in staging environment after migration applied. Confirm Contributor users cannot create/delete financial entries but can still view (if `can_view_financials = true`).

---

**QA Agent:** GitHub Copilot  
**QA Date:** 2026-07-11  
**Branch:** feature/expense-delete-drawer  
**Commits Reviewed:** Combined diff covering Commit 1 (delete UI) + Commit 2 (RBAC enforcement)
