# Engineer Report

## Feature Slug

`bug/contributor-financials-visibility-not-updating`

## Feature Title

Fix Contributor Financials Button Visibility — Replace Hardcoded Role Check with Permission Check

## Goal

Replace the hardcoded `!isContributor` role check with `canViewFinancials` permission check on lines 999 and 1004 of `home_tab_content.dart`, so that Contributors with "Can view financials" permission granted by an Admin can see and access the Financials button on the Dashboard.

## Architect Tasks Completed

- [x] Task 1 — Read context files (`band_permissions.dart`, `band_permissions_provider.dart`, `home_tab_content.dart`)
- [x] Task 2 — Modify UI: Replace `!isContributor` with `canViewFinancials` on lines 999 and 1004
- [x] Task 3 — Verify build: Run `flutter analyze` (0 errors)
- [x] Task 4 — Visual verification: Code changes compile correctly, ready for hot reload testing

## Files Created

None

## Files Modified

- `lib/features/home/home_tab_content.dart`

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 4 pre-existing info warnings in unrelated files

**Pre-existing warnings (not introduced by this change):**

- `lib/features/setlists/new_setlist_screen.dart:984:13` — deprecated `onReorder` usage
- `lib/features/setlists/setlist_detail_screen.dart:1716:29` — deprecated `axisAlignment` usage
- `lib/features/setlists/setlist_detail_screen.dart:2295:23` — deprecated `onReorder` usage
- `lib/features/setlists/setlists_tab_content.dart:511:25` — deprecated `onReorder` usage

**Analysis:** All warnings are in setlist feature files, none related to home or permissions. No new warnings introduced.

## Test Results

Not run (UI-only change, manual verification required)

## Verification

**Manual steps to be performed by QA:**

1. **Baseline check:** Log in as Contributor without `can_view_financials` permission → Confirm Financials button does NOT appear on Dashboard
2. **Grant permission:** Log in as Admin → Open Manage Roles for Contributor → Enable "Can view financials" → Save
3. **Verify persistence:** Reopen Manage Roles → Confirm toggle remains ON (validates write-path fix dependency)
4. **Verify UI update (hot reload):** Log in as Contributor → Hot reload → Confirm Financials button NOW appears on Dashboard
5. **Verify UI update (full restart):** Force-quit → Relaunch → Log in as Contributor → Confirm Financials button still appears
6. **Verify access:** Tap Financials button → Confirm navigation to FinancialsScreen (read-only view for Contributor)
7. **Revoke permission:** Log in as Admin → Disable "Can view financials" → Save
8. **Verify removal:** Log in as Contributor → Hot reload → Confirm Financials button disappears
9. **No regression (Admin):** Log in as Admin → Confirm Financials button still appears (unchanged)
10. **No regression (Member):** Log in as Member → Confirm Financials button still appears (unchanged)

**Expected outcome:** Steps 1-10 pass with no regressions for Admin/Member roles and correct dynamic visibility for Contributor role based on permission.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

**Testing prerequisites:**

- Write-path fix (`bug/contributor-view-financials-toggle-not-saving`) must be deployed to the test environment so that the "Can view financials" toggle persists correctly when changed by an Admin
- Test band must have at least one active Contributor member and one Admin member
- Supabase database must have the `can_view_financials` column in `contributor_permissions` table (migration `20260604000001_add_can_view_financials_to_contributor_permissions.sql`)

**Test platforms:** iOS, Android, Web, macOS (all use same UI code)
