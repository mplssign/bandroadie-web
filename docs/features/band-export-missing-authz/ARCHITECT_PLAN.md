# ARCHITECT_PLAN.md

## Feature Slug

`bug/band-export-missing-authz`

---

## Problem Summary

`DataBackupService.exportBandData()` (`lib/features/settings/data_backup_service.dart:69`) performs no server-side authorization check beyond confirming the caller is logged in. The method directly queries all band-scoped tables (`bands`, `band_members`, `songs`, `setlists`, `gigs`, `rehearsals`, `block_dates`, and associated relations) and returns a complete JSON export. Since regular members already have RLS SELECT access to these tables for normal app functionality, any authenticated user with membership in any role (including `contributor`) can call this service method directly and receive the full band data dump—member PII, gig responses, notes, financial entries (when combined with the financial_entries RLS gap that was fixed in C2).

**The export feature is live and actively used.** The Edit Band screen contains a "Backup / Restore" button (`lib/features/bands/band_form_screen.dart:2208`) that invokes `_showBackupRestoreSheet()` → `_startExport()` → `_performExport()` → `DataBackupService.exportBandData()`. This button is correctly gated client-side by `BandPermissions.canExportBandData` (`:2190-2200`), which checks `isAdmin || isMember`, matching the intended policy. Contributors do not see the button. However, this client-side gate is insufficient—`DataBackupService.exportBandData()` is a public static method callable from anywhere in the app (test code, debug builds, direct service invocation), and it performs no server-side role check.

The only server-side enforcement today is RLS on the underlying tables, which grants SELECT to all active band members regardless of role. A contributor who bypasses the UI and calls `exportBandData()` directly will succeed, receiving the same export as an admin or member.

The intended policy per Tony's confirmation: `admin` and `member` roles are allowed to export band data; the `contributor` role is explicitly blocked regardless of any fine-grained permissions in `contributor_permissions`. This is a role-level restriction, not a per-permission check.

**Why the fix is needed:** The export functionality is live and in use by admin/member users today, with only client-side gating. The authorization gap means any contributor who discovers or is directed to call the service method directly (bypassing the hidden UI button) can exfiltrate complete band data. Closing this gap adds server-side enforcement under an already-active feature, ensuring the policy holds regardless of caller.

---

## Root Cause

**Confidence Level: HIGH** (confirmed by direct code inspection)

**Primary failure:** `DataBackupService.exportBandData()` contains no authorization logic. The method signature is:

```dart
static Future<void> exportBandData(String bandId, String bandName) async
```

The only guard in the method body is:

```dart
final userId = supabase.auth.currentUser?.id;
if (userId == null) throw const DataBackupException('Not logged in');
```

After this check, the method proceeds directly to `_buildBandExport()`, which issues plain Supabase `.select()` queries against every band-scoped table. No role lookup, no membership check beyond what RLS already enforces for SELECT (which is membership in any role, including contributor).

**Secondary observation:** The client-side `BandPermissions.canExportBandData` property already exists and correctly implements the intended policy (`isAdmin || isMember`). It is used to gate the "Backup / Restore" button in the Edit Band screen (`band_form_screen.dart:2190-2200`), which is the only production UI entry point to the export feature. This client-side gate works as intended for normal UI flows—contributors never see the button—but it cannot protect against direct service invocation. Any code path that bypasses the UI and calls `DataBackupService.exportBandData()` directly will succeed for a contributor, because the service method performs no role check of its own.

**Why this violates guardrails:** Per `GUARDRAILS.md` §4, "RLS policies are the final authority. Never bypass them from the client." The current implementation relies on the fact that RLS grants SELECT to all active band members, but the intended _authorization policy_ is narrower than the _RLS policy_—admin and member should export, contributor should not—and nothing enforces this narrower policy server-side. A Dart method callable from anywhere in the app (including test code, debug builds, or direct service calls) is not a safe enforcement point.

---

## Reference Docs Consulted

- `docs/reference/audits/CODEBASE_AUDIT_2026-08-14.md` — C3 finding, originally describing this as "admin-only" (superseded by Tony's confirmation of admin+member policy)
- `docs/reference/audits/CODEBASE_AUDIT_2026-08-17.md` — C3 re-verification confirming the issue is still open
- `docs/agents/GUARDRAILS.md` — §4 (Supabase Safety), §7 (Code Change Discipline)
- `docs/agents/OPERATING_MODEL.md` — server-is-authoritative principle
- `supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql` — prior art for `check_financial_view_permission`, the closest precedent for admin/member/contributor branching in a SECURITY DEFINER helper function

---

## Existing System Analysis

### Current Data Flow (Live UI Path)

The export feature is reachable in production via this call chain:

**UI Entry Point:** Edit Band screen (`lib/features/bands/band_form_screen.dart`) in edit mode, for users with `canExportBandData` permission (admin or member).

1. **Button visibility gate (`:2190-2200`):** The "Backup / Restore" button is conditionally rendered based on `ref.watch(currentUserPermissionsProvider).canExportBandData`. Contributors do not see this button.

2. **Button press (`:2208`):** When the button is tapped, it invokes `_showBackupRestoreSheet()`.

3. **Bottom sheet (`:535-647`):** `_showBackupRestoreSheet()` displays a modal with "Backup Data" and (if `canDeleteBand`) "Restore Data" panels. The "Backup Data" panel's `onTap` handler calls `_startExport()`.

4. **Export initiation (`:646-650`):** `_startExport()` retrieves the current band and calls `_performExport(band.id, band.name)`.

5. **Export execution (`:761-785`):** `_performExport()` calls `DataBackupService.exportBandData(bandId, bandName)` (`:764`).

6. **Service method (data_backup_service.dart:69-118):**
   - **Login check:** Confirms `supabase.auth.currentUser?.id != null`, throws `DataBackupException('Not logged in')` if absent.
   - **Authorization check:** **None**—method proceeds directly to `_buildBandExport()`.
   - **Export construction:** `_buildBandExport()` issues these Supabase queries in sequence:
     - `bands` — `.select().eq('id', bandId).maybeSingle()`
     - `band_members` — `.select().eq('band_id', bandId)`
     - `contributor_permissions` — `.select().inFilter('band_member_id', memberIds)` (if any members exist)
     - `songs` — `.select().eq('band_id', bandId)`
     - `setlists` — `.select().eq('band_id', bandId)`
     - `setlist_special_items` — `.select().eq('band_id', bandId)`
     - `setlist_songs` — `.select().inFilter('setlist_id', setlistIds)` (if any setlists exist)
     - `gigs` — `.select().eq('band_id', bandId)`
     - `gig_dates` — `.select().inFilter('gig_id', gigIds)` (if any gigs exist)
     - `gig_responses` — `.select().inFilter('gig_id', gigIds)` (if any gigs exist)
     - `rehearsals` — `.select().eq('band_id', bandId)`
     - `block_dates` — `.select().eq('band_id', bandId)`
   - **RLS enforcement (passive):** Each query succeeds or fails based on existing RLS SELECT policies. For all of these tables, the SELECT policy is "active member of the band" (any role), with no further restrictions in RLS itself.
   - **JSON assembly:** The returned rows are bundled into a JSON object with metadata (schema version, export timestamp, app version, `exported_by_user_id`, `band_id`, `band_name`) and returned.
   - **File save:** The JSON is written to disk via the native file picker (web, iOS, Android, macOS, Windows variants).

**No step in this flow checks the caller's role.** The UI gate at step 1 hides the button from contributors, but if a contributor were to call `DataBackupService.exportBandData()` directly (bypassing the UI), they would receive the same export as an admin or member.

### Current Client-Side Check (Effective for UI, Insufficient for Service Layer)

The Edit Band screen's button visibility is gated correctly:

```dart
final canExport = permissionsAsync.when(
  data: (perms) => perms.canExportBandData,  // ← isAdmin || isMember
  loading: () => false,
  error: (_, __) => false,
);
if (!canExport) return const SizedBox.shrink();
```

This ensures contributors never see the "Backup / Restore" button in the UI. However:

- `DataBackupService.exportBandData()` is a public static method—any Dart code can call it.
- The service method performs no role check of its own.
- A contributor with knowledge of the service API can invoke it directly and succeed.

There is an unrelated `canDeleteBand` check at `:539` that controls whether the "Restore Data" panel appears inside the bottom sheet (admin-only), but this does not gate export—export is gated by `canExportBandData`, not `canDeleteBand`.

### Dead Code Note

`_showExportDialog()` (`:653-764`, flagged `// ignore: unused_element`) is a separate, older export dialog UI that has no callers. It is unrelated to the live `_showBackupRestoreSheet()` flow and remains off-limits for this fix.

---

## Proposed Solution

### Minimal Fix: Server-Side Authorization Gate

Introduce a `SECURITY DEFINER` RPC function `check_band_export_permission(p_band_id UUID)` that:

1. Retrieves the caller's `auth.uid()`
2. Queries `band_members` to get the caller's role in the specified band
3. Returns `TRUE` if the role is `admin` or `member`
4. Returns `FALSE` for `contributor` (regardless of any `contributor_permissions` grants)
5. Returns `FALSE` for non-members or if `auth.uid()` is null
6. Defaults deny in all other cases

Then modify `DataBackupService.exportBandData()` to call this RPC at the start of the method (before any data queries) and throw `DataBackupException` if the check returns false.

**Why this pattern:** This mirrors the existing `check_financial_view_permission()` pattern from the financial_entries RBAC fix (C2, `20260814120001_fix_financial_entries_select_rbac.sql`), which already implements correct admin/member/contributor branching and defaults deny. The only difference is that financial permission allows contributors with `can_view_financials = true`, whereas export permission blocks all contributors unconditionally. This makes the export check even simpler.

**Why SECURITY DEFINER:** The function needs to query `band_members` in the context of the authenticated user's session (`auth.uid()`). By marking it `SECURITY DEFINER`, the function executes with the privileges of the function owner (typically the service role or superuser), allowing it to reliably query `band_members` without depending on the caller's RLS context. This is the standard pattern for authorization helper functions in this codebase.

**Why not RLS-only:** Export is not a table-level operation—it's a bulk read across 12+ tables. Creating an "export-scoped" RLS context would require either a session variable toggle or a separate "export mode" mechanism, both of which are more complex and error-prone than a single RPC check. The RPC pattern is simpler, explicit, and matches existing precedent.

### Changes Required

1. **New migration:** `supabase/migrations/20260821120000_add_band_export_authorization.sql`
   - Create `check_band_export_permission(UUID)` RPC
   - Include `SECURITY DEFINER` and `SET search_path = public`
   - `REVOKE EXECUTE ... FROM PUBLIC; GRANT EXECUTE ... TO authenticated;` (closes the C6 anon-executable gap proactively)
2. **Modify:** `lib/features/settings/data_backup_service.dart`
   - Add a server-side authorization check at the start of `exportBandData()`, before `_buildBandExport()`
   - Call the new RPC: `await supabase.rpc('check_band_export_permission', params: {'p_band_id': bandId})`
   - If the RPC returns `false`, throw `DataBackupException` with a user-friendly message
   - Preserve all existing export logic unchanged

**No other files are modified.** The live UI path in `band_form_screen.dart` (the "Backup / Restore" button and `_showBackupRestoreSheet()` flow) remains untouched and continues to work as intended. The dead `_showExportDialog()` method also remains untouched.

---

## Database Impact

**Migration required:** Yes — `20260821120000_add_band_export_authorization.sql`

### New RPC Function

```sql
CREATE OR REPLACE FUNCTION check_band_export_permission(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role TEXT;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Get user's role in the band
  SELECT role INTO v_role
  FROM band_members
  WHERE band_id = p_band_id
    AND user_id = v_user_id
    AND status = 'active';

  -- If not a member, deny access
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Admin and member roles are allowed to export
  IF v_role IN ('admin', 'member') THEN
    RETURN TRUE;
  END IF;

  -- Contributor role is explicitly blocked, regardless of permissions
  -- (This is a role-level restriction, not a fine-grained permission check)
  IF v_role = 'contributor' THEN
    RETURN FALSE;
  END IF;

  -- Default deny for any unexpected role value
  RETURN FALSE;
END;
$$;

-- Explicitly revoke from PUBLIC to prevent anon execution (C6 hardening)
REVOKE EXECUTE ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC;

-- Grant only to authenticated users
GRANT EXECUTE ON FUNCTION check_band_export_permission(UUID) TO authenticated;
```

**RLS policies:** Not modified. The existing SELECT policies on `bands`, `songs`, `setlists`, etc., remain unchanged. This RPC adds an additional authorization layer _before_ any queries are issued, but does not alter the RLS enforcement on the tables themselves.

**Triggers:** Not affected.

**Other functions:** Not affected.

---

## Flutter Architecture Changes

### Modified: `lib/features/settings/data_backup_service.dart`

**Change:** Add server-side authorization check at method entry.

**Before:**

```dart
static Future<void> exportBandData(
  String bandId,
  String bandName,
) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw const DataBackupException('Not logged in');

  final exportJson = await _buildBandExport(bandId, bandName, userId);
  // ...
}
```

**After:**

```dart
static Future<void> exportBandData(
  String bandId,
  String bandName,
) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw const DataBackupException('Not logged in');

  // Server-side authorization check (admin and member only)
  final isAuthorized = await supabase.rpc(
    'check_band_export_permission',
    params: {'p_band_id': bandId},
  ) as bool;

  if (!isAuthorized) {
    throw const DataBackupException(
      'You do not have permission to export this band\'s data. '
      'Only admins and members can create backups.',
    );
  }

  final exportJson = await _buildBandExport(bandId, bandName, userId);
  // ...
}
```

**Rationale:** This is the minimal, safest injection point. The check happens before any data is read, surfaces a clear error to the caller (consistent with the existing `DataBackupException` pattern used elsewhere in the file), and does not alter the export schema, file format, or any other behavior.

### State Management

**Not affected.** `DataBackupService` is a static utility class with no providers, controllers, or state. The authorization check is synchronous from the Dart caller's perspective (awaited inline), so no state coordination is required.

### Repositories

**Not affected.** The export logic does not use repository abstractions—it queries Supabase directly. No repository files are modified.

### Widgets / UI

**Not affected.** The live "Backup / Restore" button and `_showBackupRestoreSheet()` flow in `band_form_screen.dart` are not modified—they are working as intended. The server-side RPC adds enforcement under the existing UI, ensuring the policy holds even if the UI gate is bypassed.

---

## Files to Create

| File Path                                                              | Justification                                                                                           |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260821120000_add_band_export_authorization.sql` | Defines the `check_band_export_permission` RPC function. Required to enforce server-side authorization. |

---

## Files to Modify

| File Path                                        | What Changes                                                                                                                                                                                  |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | Add authorization check at the start of `exportBandData()` method (after login check, before `_buildBandExport()`). Throw `DataBackupException` if RPC returns false. No other logic changes. |

---

## Files Off-Limits

| File                                                                               | Reason                                                                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/bands/band_form_screen.dart`                                         | The live `_showBackupRestoreSheet()` flow and "Backup / Restore" button (`:2208`) are working as intended and are not modified. The only dead code is `_showExportDialog()` (`:653-764`), which has no callers and remains off-limits. Do not alter the live UI path or the dead method. |
| `lib/features/members/permissions/band_permissions.dart`                           | The `canExportBandData` property already exists and is correct (`isAdmin \|\| isMember`). No change needed.                                                                                                                                                                              |
| `lib/main.dart`                                                                    | Initialization order must not change (Guardrails §1).                                                                                                                                                                                                                                    |
| `supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql`         | Prior art for reference only. Do not modify existing migrations.                                                                                                                                                                                                                         |
| All files in `lib/features/setlists/`, `lib/features/gigs/`, `lib/features/songs/` | Export reads these tables but does not alter their logic. No changes to repositories, controllers, or widgets in these features.                                                                                                                                                         |

---

## System Impact Map

| System                                 | Impact                                                                                                                                  |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **Unaffected** — export reads `gigs`, `gig_dates`, `gig_responses` via SELECT; no mutation, no flow change                              |
| Rehearsals                             | **Unaffected** — export reads `rehearsals` via SELECT; no mutation, no flow change                                                      |
| Setlists / Catalog                     | **Unaffected** — export reads `setlists`, `setlist_songs`, `setlist_special_items` via SELECT; no mutation, no flow change              |
| Members / RBAC                         | **Affected (authorization only)** — new RPC queries `band_members` to enforce role check; no schema changes, no mutation of member data |
| Auth / Session                         | **Unaffected** — relies on existing `auth.uid()` from Supabase session; no auth flow changes                                            |
| Routing                                | **Unaffected** — export is invoked from Edit Band screen via button press; no route changes                                             |
| Notifications                          | **Unaffected** — export does not trigger or interact with notifications                                                                 |
| Platform (iOS / Android / Web / macOS) | **Unaffected** — Dart service backed by Supabase RPC; platform-agnostic                                                                 |

---

## Regression Risk

**Level: MEDIUM**

**Rationale:**

1. **Live UI flow exists:** The export functionality is actively used by admin and member users via the Edit Band screen's "Backup / Restore" button. This is a production feature, not a hypothetical future path. Any regression in the authorization check or service method could break legitimate exports for these users.

2. **Single injection point, fail-fast behavior:** The fix adds one authorization check at the entry point of `exportBandData()`, before any data is queried. If the check fails, it throws immediately—no partial state or data corruption is possible. The guard is fail-fast (denies on error), minimizing risk of incorrect allow decisions.

3. **Client-side gate still in place:** The UI-level button visibility check (`canExportBandData`) remains unchanged. Contributors still won't see the button in normal usage. The server-side check adds defense-in-depth, not a replacement for the client gate.

4. **Well-precedented pattern:** The `check_*_permission` helper RPC pattern is already in use (`check_financial_view_permission`, `check_gig_response_access`). This follows the same structure, so failure modes are well-understood from prior deployments.

5. **Single-file Dart change:** Only one service file is modified. The change does not touch controllers, providers, repositories, or UI widgets. The failure surface is narrow.

6. **No schema changes:** The migration adds one new RPC function with no table alterations, no RLS policy changes, and no trigger modifications. Existing queries and data access patterns are unaffected.

7. **RPC failure handling:** If the RPC call fails (network error, DB unavailable), the Dart exception propagates and the export aborts cleanly—the same behavior as if any other Supabase query in `_buildBandExport()` had failed. The user sees an error message; no partial export is written.

**Risk factors that prevent a LOW rating:**

- The feature is live and used by real users today, so any bug in the authorization check (e.g., false denial for admin/member) would block legitimate exports.
- The RPC introduces a new remote call before the export, adding one more potential point of failure (network, DB latency, RPC syntax error). While the failure mode is safe (abort cleanly), it's a change to a working flow that must be tested end-to-end.

**Mitigation:**

- Tier 2 verification tests admin, member, contributor, and non-member cases explicitly with real or test UUIDs.
- QA must validate the full UI flow (Edit Band → Backup / Restore → Backup Data) for admin and member roles on at least one platform to confirm the new check does not false-deny.
- If the RPC check false-denies a legitimate user, the error message is clear and actionable ("You do not have permission…"), not a generic failure, so the user can report it.

---

## Engineer Task Breakdown

### Task 1: Create Migration for RPC Authorization Function

**File:** `supabase/migrations/20260821120000_add_band_export_authorization.sql`

**Steps:**

1. Create the migration file in `supabase/migrations/` with the exact filename `20260821120000_add_band_export_authorization.sql`.
2. Add a clear header comment block explaining the purpose: "Add server-side authorization check for band data export. Admin and member roles allowed, contributor role blocked."
3. Define the `check_band_export_permission(p_band_id UUID)` function:
   - Return type: `BOOLEAN`
   - Language: `plpgsql`
   - Attributes: `SECURITY DEFINER`, `SET search_path = public`
   - Logic:
     - Declare `v_user_id UUID` and `v_role TEXT`
     - Assign `v_user_id := auth.uid()`
     - If `v_user_id IS NULL`, return `FALSE`
     - Query `band_members` for `role` where `band_id = p_band_id AND user_id = v_user_id AND status = 'active'`
     - If no row found (`v_role IS NULL`), return `FALSE`
     - If `v_role IN ('admin', 'member')`, return `TRUE`
     - If `v_role = 'contributor'`, return `FALSE`
     - Default: return `FALSE`
4. Add `REVOKE EXECUTE ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC;` (C6 hardening)
5. Add `GRANT EXECUTE ON FUNCTION check_band_export_permission(UUID) TO authenticated;`
6. Verify the function signature exactly matches the call site in Task 2 (parameter name `p_band_id`, not `band_id` or `bandId`).

**Acceptance Criteria:**

- Migration file exists with correct timestamp and filename.
- Function compiles without syntax errors when applied via `supabase db push`.
- Function is executable by `authenticated` role, not by `anon`.
- Function returns `TRUE` for an admin or member of the specified band, `FALSE` for a contributor, `FALSE` for a non-member.

---

### Task 2: Add Authorization Check to `exportBandData()`

**File:** `lib/features/settings/data_backup_service.dart`

**Steps:**

1. Locate the `exportBandData()` method (currently at line 69).
2. After the existing login check (`if (userId == null) throw const DataBackupException('Not logged in');`), add the authorization RPC call:

   ```dart
   // Server-side authorization check (admin and member only)
   final isAuthorized = await supabase.rpc(
     'check_band_export_permission',
     params: {'p_band_id': bandId},
   ) as bool;

   if (!isAuthorized) {
     throw const DataBackupException(
       'You do not have permission to export this band\'s data. '
       'Only admins and members can create backups.',
     );
   }
   ```

3. Preserve all existing logic below this check unchanged—`_buildBandExport()`, file picker logic, platform variants, etc.
4. Verify the parameter name in `params` exactly matches the RPC function definition (`p_band_id`).
5. Verify the exception message is user-friendly, grammatically correct, and consistent with the existing `DataBackupException` messages in the file (e.g., "Not logged in", "Invalid file", etc.).

**Acceptance Criteria:**

- `flutter analyze` passes with zero errors.
- The authorization check is positioned after the login check and before `_buildBandExport()`.
- The exception type is `DataBackupException` (matches existing error handling in the file).
- The exception message is clear, actionable, and does not expose internal implementation details.

---

### Task 3: Verify No Unintended Changes

**Steps:**

1. Run `git diff` and confirm only two files are modified:
   - `supabase/migrations/20260821120000_add_band_export_authorization.sql` (new file)
   - `lib/features/settings/data_backup_service.dart` (modified)
2. Confirm no changes to:
   - `lib/features/bands/band_form_screen.dart`
   - `lib/features/members/permissions/band_permissions.dart`
   - Any repository, controller, or widget files in `lib/features/setlists/`, `lib/features/gigs/`, `lib/features/songs/`
3. Confirm no changes to `lib/main.dart` or any initialization files.
4. If any unintended files appear in the diff, revert them before proceeding to QA.

**Acceptance Criteria:**

- `git diff --name-status` shows exactly one new file (`A`) and one modified file (`M`).
- No other files are staged or modified.

---

## Verification Plan

### Tier 1 — Pre-deployment (Before `supabase db push`)

These tests verify the migration SQL is syntactically correct and can be inspected in isolation. **Do not call `check_band_export_permission` yet—it does not exist in the database until the migration is applied.**

```sql
-- PRE-DEPLOY TEST 1: Verify migration file syntax (dry-run parse)
-- Run this in the Supabase SQL Editor or via psql connected to the project
-- Expected: No syntax errors

BEGIN;
\i supabase/migrations/20260821120000_add_band_export_authorization.sql
ROLLBACK;

-- If the above succeeds with no errors, the migration is syntactically valid.
-- Proceed to Tier 2 after `supabase db push`.
```

---

### Tier 2 — Post-deployment (After `supabase db push`)

These tests verify the RPC function exists in the database, has the correct definition, and behaves as expected.

```sql
-- POST-DEPLOY TEST 1: Verify function exists and contains expected logic
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'check_band_export_permission'
  AND pronamespace = 'public'::regnamespace;

-- Expected: Returns the full function definition.
-- Verify the definition includes:
--   - SECURITY DEFINER
--   - SET search_path = public
--   - IF v_role IN ('admin', 'member') THEN RETURN TRUE;
--   - IF v_role = 'contributor' THEN RETURN FALSE;


-- POST-DEPLOY TEST 2: Verify function permissions (anon blocked, authenticated granted)
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'check_band_export_permission'
  AND routine_schema = 'public';

-- Expected:
--   - 'authenticated' | 'EXECUTE'
--   - No row for 'anon' (or if present, privilege_type should NOT be 'EXECUTE')


-- POST-DEPLOY TEST 3: Verify function returns TRUE for admin
DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000001';  -- Replace with a real test user
  v_test_band_id UUID;
  v_result BOOLEAN;
BEGIN
  -- Create a test band
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Export Band', v_test_user_id)
  RETURNING id INTO v_test_band_id;

  -- Add the test user as an admin
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, v_test_user_id, 'admin', 'active');

  -- Simulate auth.uid() returning the test user
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_user_id)::text, true);

  -- Call the function
  SELECT check_band_export_permission(v_test_band_id) INTO v_result;

  -- Assert
  IF v_result = TRUE THEN
    RAISE NOTICE 'PASS: Admin can export';
  ELSE
    RAISE EXCEPTION 'FAIL: Admin returned FALSE';
  END IF;

  -- Cleanup
  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;
END $$;


-- POST-DEPLOY TEST 4: Verify function returns TRUE for member
DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000002';  -- Replace with a real test user
  v_test_band_id UUID;
  v_result BOOLEAN;
BEGIN
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Export Band Member', v_test_user_id)
  RETURNING id INTO v_test_band_id;

  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, v_test_user_id, 'member', 'active');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_user_id)::text, true);

  SELECT check_band_export_permission(v_test_band_id) INTO v_result;

  IF v_result = TRUE THEN
    RAISE NOTICE 'PASS: Member can export';
  ELSE
    RAISE EXCEPTION 'FAIL: Member returned FALSE';
  END IF;

  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;
END $$;


-- POST-DEPLOY TEST 5: Verify function returns FALSE for contributor
DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000003';  -- Replace with a real test user
  v_test_band_id UUID;
  v_result BOOLEAN;
BEGIN
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Export Band Contributor', v_test_user_id)
  RETURNING id INTO v_test_band_id;

  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, v_test_user_id, 'contributor', 'active');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_user_id)::text, true);

  SELECT check_band_export_permission(v_test_band_id) INTO v_result;

  IF v_result = FALSE THEN
    RAISE NOTICE 'PASS: Contributor blocked from export';
  ELSE
    RAISE EXCEPTION 'FAIL: Contributor returned TRUE';
  END IF;

  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;
END $$;


-- POST-DEPLOY TEST 6: Verify function returns FALSE for non-member
DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000004';  -- Replace with a real test user
  v_test_band_id UUID;
  v_result BOOLEAN;
BEGIN
  INSERT INTO bands (id, name, created_by)
  VALUES (gen_random_uuid(), 'Test Export Band Non-Member', v_test_user_id)
  RETURNING id INTO v_test_band_id;

  -- Do NOT insert a band_members row for this user

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_user_id)::text, true);

  SELECT check_band_export_permission(v_test_band_id) INTO v_result;

  IF v_result = FALSE THEN
    RAISE NOTICE 'PASS: Non-member blocked from export';
  ELSE
    RAISE EXCEPTION 'FAIL: Non-member returned TRUE';
  END IF;

  DELETE FROM bands WHERE id = v_test_band_id;
END $$;


-- POST-DEPLOY TEST 7: Verify function returns FALSE when auth.uid() is NULL
DO $$
DECLARE
  v_test_band_id UUID := gen_random_uuid();
  v_result BOOLEAN;
BEGIN
  -- Clear the auth context to simulate anon/unauthenticated request
  PERFORM set_config('request.jwt.claims', NULL, true);

  SELECT check_band_export_permission(v_test_band_id) INTO v_result;

  IF v_result = FALSE THEN
    RAISE NOTICE 'PASS: NULL auth.uid() blocked from export';
  ELSE
    RAISE EXCEPTION 'FAIL: NULL auth.uid() returned TRUE';
  END IF;
END $$;


-- POST-DEPLOY TEST 8: Production verification — no bad data written
-- This is a read-only verification that the function exists and is callable
-- from a real authenticated session (not a test user).
-- Run this as yourself (logged into Supabase SQL Editor as an authenticated user):

SELECT check_band_export_permission('<your-real-band-id-here>'::UUID);

-- Expected:
--   - TRUE if you are an admin or member of that band
--   - FALSE if you are a contributor or not a member
-- If the result matches your actual role, the function is working correctly in production context.
```

---

## QA Regression Areas

### Primary Validation (Critical)

**Test via Live UI Path (Admin/Member):**

1. **Export authorization for admin via UI:** As an admin of a test band, navigate to Edit Band screen → tap "Backup / Restore" button → tap "Backup Data" panel. Verify the export succeeds and a valid JSON backup file is created.

2. **Export authorization for member via UI:** As a member (non-admin) of a test band, navigate to Edit Band screen → tap "Backup / Restore" button → tap "Backup Data" panel. Verify the export succeeds.

3. **Button visibility for contributor:** As a contributor of a test band, navigate to Edit Band screen. Verify the "Backup / Restore" button is **not visible** (existing client-side gate still works).

**Test via Direct Service Invocation (Contributor/Non-Member):**

4. **Export authorization denial for contributor:** As a contributor of a test band, call `DataBackupService.exportBandData()` directly (e.g., via a debug harness, test code, or Flutter DevTools service call). Verify the export is **rejected** with the error message "You do not have permission to export this band's data. Only admins and members can create backups."

5. **Export authorization denial for non-member:** As a user who is not a member of the target band, attempt to trigger `DataBackupService.exportBandData()` directly. Verify the export is rejected with the same error message.

6. **Export authorization denial when not logged in:** Without an active Supabase session (`auth.currentUser == null`), attempt to trigger the export directly. Verify it fails with "Not logged in" (the existing check, not the new one).

### Regression Testing (Other Features)

7. **Setlist operations:** Verify that viewing, editing, reordering, and adding songs to setlists works for admin, member, and contributor roles (per their respective permissions). Export does not touch these tables' mutation logic—this confirms no unintended RLS or query side effects.

8. **Gig operations:** Verify that viewing gigs, creating gigs (if permitted), and RSVP'ing to gigs works as expected. Export reads `gigs`, `gig_dates`, `gig_responses` but does not alter them.

9. **Rehearsal operations:** Verify that viewing and creating rehearsals works. Export reads `rehearsals` but does not alter them.

10. **Member management:** Verify that admin users can still invite members, change roles, and remove members. The new RPC queries `band_members` for authorization but does not mutate it.

11. **Financial entries (if applicable):** Verify that the existing financial entries view permission logic (`check_financial_view_permission`) still works correctly—contributors with `can_view_financials = true` can view entries, those with `false` cannot. This confirms the new RPC did not interfere with the existing RBAC RPC pattern.

### Edge Cases

12. **Network failure during RPC call:** Simulate a network interruption (e.g., turn off Wi-Fi mid-export, or use a network throttling tool) and verify the export fails gracefully with an error message, not a partial/corrupted backup file.

13. **Band with no members (hypothetical):** Attempt to export a band that has zero active `band_members` rows (should not be possible in normal usage, but test as a defensive check). Verify the export is rejected with "You do not have permission…" (the RPC will return `FALSE` because no role is found).

14. **Band with contributor_permissions row but contributor role:** Verify a contributor with various `contributor_permissions` grants (e.g., `can_create_gigs = true`, `can_view_financials = true`) is still blocked from export—the export check is role-level, not permission-level.

### Multi-Platform Validation

15. **Platform consistency:** Test the live UI export flow on at least two platforms (e.g., iOS and Web) to confirm the authorization check works identically across all supported platforms (the RPC is server-side, so behavior should be uniform).

---

## Rollout / Migration Strategy

**Deployment sequence:**

1. **Merge and deploy migration:** After QA approval, merge the PR and deploy the Supabase migration via `supabase db push` or the Supabase Dashboard migration runner.
2. **Deploy Flutter app:** Rebuild and deploy the Flutter app with the updated `data_backup_service.dart`. This can happen immediately after the migration is live (same release) or in a subsequent deploy—the new RPC will simply not be called until the Dart code that invokes it is deployed.

**Backward compatibility:** The new RPC does not alter any existing tables, policies, or functions. Existing app versions (pre-fix) that do not call the RPC will continue to work as before (with the authorization gap still present). Once the updated Dart code is deployed, the authorization check becomes active.

**Rollback plan:** If the migration causes unforeseen issues (e.g., the RPC fails to compile, or an edge case blocks legitimate users), the rollback is:

1. Revert the Dart change (remove the RPC call from `exportBandData()`).
2. Optionally drop the RPC function via a new migration:
   ```sql
   DROP FUNCTION IF EXISTS check_band_export_permission(UUID);
   ```
   This is safe because the function is only called from one location in the Dart codebase, and reverting that code removes all call sites.

**No data migration required.** This is a pure authorization gate—no user data is read, written, or transformed. The export schema version remains `1` (unchanged).

---

## Out of Scope

The following are explicitly **not** part of this fix:

1. **Modifying the live export UI:** The "Backup / Restore" button in the Edit Band screen (`lib/features/bands/band_form_screen.dart:2208`) and its associated `_showBackupRestoreSheet()` flow are working as intended and are not modified. The button visibility gate (`canExportBandData` at `:2190-2200`) is already correct. This fix adds server-side enforcement under the existing UI, not a UI redesign.

2. **Changing the export data schema:** The JSON structure, included tables, and schema version remain unchanged. This fix adds authorization only.

3. **Changing the import logic:** `DataBackupService.importBandData()` is not modified. Authorization for import (if needed) would be a separate analysis—import currently requires the user to be an admin of the target band (enforced by the RLS policies on the tables being written), but that enforcement is implicit, not explicit like this export fix.

4. **Updating `docs/agents/PROJECT_CONTEXT.md`:** The Feature Input notes that PROJECT_CONTEXT currently describes export as "admin-only" when the actual policy is admin+member. Correcting that documentation is acknowledged but not part of this bug fix—it can be updated in a subsequent docs pass.

5. **Touching `_showExportDialog()` dead code:** `_showExportDialog()` (`:653-764`, flagged `// ignore: unused_element`) is a separate, older export dialog UI that has no callers. It is unrelated to the live `_showBackupRestoreSheet()` flow and remains explicitly off-limits per the Files Off-Limits section.

6. **Generalizing the RPC pattern:** While `check_band_export_permission` follows the same pattern as `check_financial_view_permission`, this fix does not refactor or extract a shared helper function. Each RPC remains standalone. If a pattern emerges across 3+ similar functions in the future, a shared helper could be considered, but that's a separate refactor task.
