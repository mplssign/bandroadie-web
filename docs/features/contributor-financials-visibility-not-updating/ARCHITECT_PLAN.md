# ARCHITECT_PLAN.md

## Feature Slug

`bug/contributor-financials-visibility-not-updating`

---

## Problem Summary

Contributor role members do not see the Financials button on the dashboard even after being granted "Can view financials" permission by an Admin. The permission persists correctly in the database (after the write-path fix in `bug/contributor-view-financials-toggle-not-saving`), but the UI does not respect it. Even after hot reload, force-quit, and full app restart, the Financials button never appears.

This is a **read-path bug**, separate from but dependent on the write-path bug. The write-path ensures the database has the correct value; this fix ensures the UI reads and uses it.

---

## Root Cause

**Confidence: HIGH**

Lines 999-1004 of `lib/features/home/home_tab_content.dart` use a hardcoded role check (`!isContributor`) instead of the permission-based check (`canViewFinancials`).

**Code Evidence:**

The code correctly computes `canViewFinancials` from the permissions provider at line 544-547:

```dart
final canViewFinancials = permissionsAsync.when(
  data: (perms) => perms.canViewFinancials,
  loading: () => false,
  error: (_, __) => false,
);
```

And correctly passes it to the content builder at line 689:

```dart
canViewFinancials: canViewFinancials,
```

But then **ignores it entirely** at lines 999-1004 and uses a hardcoded role check instead:

```dart
onFinancials: !isContributor ? _handleOpenFinancials : null,
...
showFinancials: !isContributor,
```

**Why the bug exists:**

This is a legacy hardcoded role check that predates the introduction of the `can_view_financials` permission. When the permission was added in June 2026 (migration `20260604000001_add_can_view_financials_to_contributor_permissions.sql`), the permission model and provider were updated correctly, but this UI callsite was never migrated to use the permission check.

**Why it's not immediately caught:**

- Contributors are rarely granted financials access (default is `false`)
- The hardcoded check `!isContributor` produces the "correct" behavior for the common case (Contributors don't see Financials)
- The bug only surfaces when an Admin explicitly grants the permission and expects it to work

---

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — Confirmed `contributor_permissions` table schema and RLS policies
- `docs/features/contributor-view-financials-toggle-not-saving/ARCHITECT_PLAN.md` — Documented write-path fix

No dedicated reference docs exist for the permissions domain or UI permission gating patterns.

---

## Existing System Analysis

**Current Data Flow (Database → UI):**

1. App loads → `currentUserPermissionsProvider` (defined in `band_permissions_provider.dart`) runs
2. Fetches user's role from `band_members` table → gets `'contributor'`
3. Fetches user's `band_member_id` from the same query
4. If role is `'contributor'`, fetches `contributor_permissions` row using `band_member_id`
5. Deserializes to `ContributorPermissions.fromJson(permResponse)` → `canViewFinancials` field is populated correctly from database
6. Returns `BandPermissions.fromRole('contributor', subPerms: subPerms)`
7. Provider result is watched in `home_tab_content.dart` → `permissionsAsync` variable
8. `canViewFinancials` computed from `perms.canViewFinancials` (line 544-547) ✓
9. Passed to `_buildContentState` as named parameter (line 689) ✓
10. **BUG**: Lines 999-1004 ignore `canViewFinancials` and use `!isContributor` instead
11. `QuickActionsRow` widget receives `showFinancials: false` for all Contributors
12. Financials button never renders

**Why the Infrastructure Works:**

- Database column exists with correct default (`FALSE`)
- RLS policy "Band members can view contributor permissions" allows the Contributor to read their own row
- `band_permissions_provider.dart` correctly fetches and deserializes the permission
- `BandPermissions.canViewFinancials` correctly returns `subPermissions?.canViewFinancials ?? false` for Contributors
- `canViewFinancials` is computed and available in scope at the UI callsite

**The Only Failure:** The UI code doesn't use the computed value.

---

## Proposed Solution

Replace the hardcoded role check with the permission-based check on lines 999 and 1004 of `lib/features/home/home_tab_content.dart`.

**Change 1 (line 999):**

```diff
- onFinancials: !isContributor ? _handleOpenFinancials : null,
+ onFinancials: canViewFinancials ? _handleOpenFinancials : null,
```

**Change 2 (line 1004):**

```diff
- showFinancials: !isContributor,
+ showFinancials: canViewFinancials,
```

**Why this is safe:**

- `canViewFinancials` already returns `true` for Admin and Member roles (lines 157-162 of `band_permissions.dart`)
- For Contributors, it returns the sub-permission value (default `false`, `true` only when explicitly granted)
- No behavior change for Admin/Member — they still see the button
- Behavior change only for Contributors with `can_view_financials = true` — they now correctly see the button
- The variable is already computed and in scope — no new logic required

---

## Database Impact

**Not applicable.**

- No migrations required
- No RLS policy changes
- No RPC function changes
- The `can_view_financials` column already exists with correct defaults
- RLS already permits Contributors to read their own `contributor_permissions` row

---

## Flutter Architecture Changes

**State Management:**

- No new providers
- No changes to existing providers
- `currentUserPermissionsProvider` already fetches the data correctly

**Widgets:**

- `home_tab_content.dart`: Replace hardcoded role check with permission-based check
- `QuickActionsRow`: No changes (already accepts `showFinancials` parameter)

**Repositories:**

- No changes required

**Models:**

- No changes required (`BandPermissions` and `ContributorPermissions` already correct)

---

## Files to Create

**None.**

---

## Files to Modify

| File                                      | Changes                                                                                                                                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/home/home_tab_content.dart` | Line 999: Replace `!isContributor` with `canViewFinancials` in `onFinancials` callback<br>Line 1004: Replace `!isContributor` with `canViewFinancials` in `showFinancials` parameter |

---

## Files Off-Limits

| File                                                              | Reason                                                            |
| ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| `lib/features/members/permissions/band_permissions_provider.dart` | Already correct — fetches permissions correctly                   |
| `lib/features/members/permissions/band_permissions.dart`          | Already correct — `canViewFinancials` getter works as designed    |
| `lib/features/members/permissions/contributor_permissions.dart`   | Already correct — model includes field and deserializes correctly |
| `lib/features/home/widgets/quick_actions_row.dart`                | Already correct — uses `showFinancials` parameter as designed     |
| All migrations                                                    | No database changes required                                      |
| All other Dart files                                              | Not in scope for this fix                                         |

---

## System Impact Map

| System                                 | Impact                                                                      |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                  |
| Rehearsals                             | unaffected                                                                  |
| Setlists / Catalog                     | unaffected                                                                  |
| Members / RBAC                         | unaffected (read-only permission check)                                     |
| Auth / Session                         | unaffected                                                                  |
| Routing                                | unaffected                                                                  |
| Notifications                          | unaffected                                                                  |
| Financials                             | **affected** — visibility now respects permission instead of hardcoded role |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms share same UI code                             |

---

## Regression Risk

**Level: LOW**

**Rationale:**

- Single file modified (`home_tab_content.dart`)
- Two-line change: replace role check with permission check
- `canViewFinancials` is a pure getter that already returns the correct value for all roles
- For Admin/Member: No behavior change (`canViewFinancials` returns `true`)
- For Contributor without permission: No behavior change (`canViewFinancials` returns `false`)
- For Contributor with permission: **Intended behavior change** — button now appears (this is the fix)
- No database, auth, or routing changes
- Same widget used (`QuickActionsRow`) — only parameter value changes
- No new abstractions, no new providers, no new dependencies

---

## Engineer Task Breakdown

1. **Read context** — Read `band_permissions.dart`, `band_permissions_provider.dart`, and `home_tab_content.dart` to understand the permission flow
2. **Modify UI** — Replace `!isContributor` with `canViewFinancials` on lines 999 and 1004 of `home_tab_content.dart`
3. **Verify build** — Run `flutter analyze` (expect 0 errors)
4. **Visual verification** — Hot reload on a device, confirm no syntax errors or runtime crashes

---

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

**Not applicable.** This is a client-only fix with no database changes.

---

### Tier 2 — Post-deployment (run after code changes applied)

**Note:** These tests require a working Supabase environment with the write-path fix (`bug/contributor-view-financials-toggle-not-saving`) already deployed, so that `can_view_financials` can be toggled and persisted correctly.

#### Test 1: Admin/Member see Financials (no regression)

```sql
-- POST-DEPLOY TEST 1: Verify Admin and Member roles are unaffected
-- Expected: canViewFinancials returns TRUE for both roles

SELECT
  'Admin' AS role,
  TRUE AS expected,
  (SELECT can_view_financials FROM contributor_permissions WHERE band_member_id = (SELECT id FROM band_members WHERE role = 'admin' LIMIT 1)) IS NULL AS actual_is_null
UNION ALL
SELECT
  'Member' AS role,
  TRUE AS expected,
  (SELECT can_view_financials FROM contributor_permissions WHERE band_member_id = (SELECT id FROM band_members WHERE role = 'member' LIMIT 1)) IS NULL AS actual_is_null;

-- Admin/Member should have no contributor_permissions row (actual_is_null = true)
-- UI logic: canViewFinancials returns true for isAdmin || isMember regardless of subPermissions
```

#### Test 2: Contributor without permission does not see Financials (no regression)

```sql
-- POST-DEPLOY TEST 2: Verify Contributor with can_view_financials = FALSE does not see button
-- Expected: canViewFinancials returns FALSE

SELECT
  bm.id AS band_member_id,
  bm.role,
  COALESCE(cp.can_view_financials, FALSE) AS can_view_financials,
  COALESCE(cp.can_view_financials, FALSE) = FALSE AS test_passes
FROM band_members bm
LEFT JOIN contributor_permissions cp ON cp.band_member_id = bm.id
WHERE bm.role = 'contributor'
  AND bm.status = 'active'
LIMIT 5;

-- All rows should have can_view_financials = FALSE (default) and test_passes = TRUE
```

#### Test 3: Contributor with permission granted DOES see Financials (FIX VALIDATION)

```sql
-- POST-DEPLOY TEST 3: Verify the fix works — Contributor with can_view_financials = TRUE sees button

DO $$
DECLARE
  test_band_id UUID;
  test_user_id UUID;
  test_member_id UUID;
  original_value BOOLEAN;
BEGIN
  -- Find a real test band and user (adjust query as needed for your test data)
  SELECT id INTO test_band_id FROM bands LIMIT 1;
  SELECT id INTO test_user_id FROM users LIMIT 1;

  -- Create or get a Contributor member
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (test_band_id, test_user_id, 'contributor', 'active')
  ON CONFLICT (band_id, user_id) DO UPDATE SET role = 'contributor', status = 'active'
  RETURNING id INTO test_member_id;

  -- Create or update contributor_permissions row
  INSERT INTO contributor_permissions (band_member_id, can_view_financials)
  VALUES (test_member_id, FALSE)
  ON CONFLICT (band_member_id) DO UPDATE SET can_view_financials = FALSE
  RETURNING can_view_financials INTO original_value;

  -- Enable the permission
  UPDATE contributor_permissions SET can_view_financials = TRUE WHERE band_member_id = test_member_id;

  -- Verify it persisted
  IF (SELECT can_view_financials FROM contributor_permissions WHERE band_member_id = test_member_id) = TRUE THEN
    RAISE NOTICE 'PASS: can_view_financials persisted as TRUE for Contributor';
  ELSE
    RAISE EXCEPTION 'FAIL: can_view_financials did not persist';
  END IF;

  -- Restore original value (cleanup)
  UPDATE contributor_permissions SET can_view_financials = original_value WHERE band_member_id = test_member_id;
  RAISE NOTICE 'Cleanup: Restored original value (%)' , original_value;
END $$;
```

#### Test 4: UI Manual Verification (Primary Fix Validation)

**Setup:**

1. Deploy the code fix to a test environment (web, iOS, or Android)
2. Ensure the write-path fix is also deployed (so you can toggle the permission)
3. Log in as Admin
4. Create or identify a Contributor member

**Test Steps:**

1. **Baseline** — Log in as the Contributor → Dashboard should NOT show Financials button
2. **Grant Permission** — Log in as Admin → Open Manage Roles for the Contributor → Enable "Can view financials" → Save
3. **Verify Persistence** — Reopen Manage Roles for the same Contributor → Confirm toggle is still ON (validates write-path fix)
4. **Verify UI Update (hot reload)** — Log in as Contributor → Hot reload app → Dashboard should NOW show Financials button
5. **Verify UI Update (full restart)** — Force-quit app → Reopen → Log in as Contributor → Dashboard should still show Financials button
6. **Verify Access** — Tap Financials button → Should navigate to FinancialsScreen (read-only for Contributor)
7. **Revoke Permission** — Log in as Admin → Disable "Can view financials" → Save
8. **Verify Removal** — Log in as Contributor → Hot reload → Financials button should disappear
9. **Verify Admin/Member unchanged** — Log in as Admin → Dashboard shows Financials button (no regression)
10. **Verify Member unchanged** — Log in as Member → Dashboard shows Financials button (no regression)

**Expected Results:**

- Steps 1-2: Write-path confirmed working
- Steps 3-6: **Fix validated** — Contributor sees button when permission is granted
- Steps 7-8: Permission removal works correctly
- Steps 9-10: No regression for Admin/Member roles

---

## QA Regression Areas

QA must specifically test:

1. **Primary Fix Validation:**
   - Contributor with `can_view_financials = true` sees Financials button on Dashboard
   - Tapping the button navigates to FinancialsScreen
   - Contributor can view but not create/edit/delete financial entries (existing RBAC enforced by RLS)

2. **Permission Toggle Lifecycle:**
   - Admin can toggle "Can view financials" ON → persists → Contributor sees button
   - Admin can toggle "Can view financials" OFF → persists → Contributor does not see button
   - Permission change reflects immediately after hot reload
   - Permission change persists after full app restart

3. **No Regression for Other Roles:**
   - Admin always sees Financials button (unchanged behavior)
   - Member always sees Financials button (unchanged behavior)

4. **Multi-Platform Consistency:**
   - Test on iOS, Android, Web, and macOS
   - Behavior should be identical across all platforms

5. **Other Permission Toggles (sanity check):**
   - "Can view setlists" toggle still works correctly
   - "Can view calendar" toggle still works correctly
   - "Can view members" toggle still works correctly
   - No cross-contamination between permission fields

6. **Edge Cases:**
   - Contributor with no `contributor_permissions` row (should fail closed — no Financials button)
   - Contributor whose role is changed from Member → Contributor (permissions should apply immediately on next load)
   - Contributor in multiple bands (permission is per-band, not global)

---

## Rollout / Migration Strategy

**Not applicable.**

This is a client-only code fix with no database changes. Standard deployment:

1. Merge feature branch to `main`
2. Deploy web: `./tools/deploy_web.sh`
3. Release mobile: Standard iOS/Android release process (App Store / Play Store)

**Deployment Dependency:**

This fix depends on the write-path fix (`bug/contributor-view-financials-toggle-not-saving`) being deployed first. If this fix deploys before the write-path fix, Contributors still won't see the button because the database value will remain `false` (the toggle doesn't save). The two fixes are independent in code but dependent in behavior.

**Recommendation:** Merge and deploy both fixes together in the same release.

---

## Out of Scope

- Changing the default value of `can_view_financials` (remains `false` per existing schema)
- Adding audit logging for permission changes (not requested)
- Refactoring the permission provider architecture (works correctly as-is)
- Creating reference documentation for the permissions domain (would be useful but not required for this fix)
- Implementing edit/delete permissions for Contributors (Financials access is explicitly read-only per existing RLS policies)
