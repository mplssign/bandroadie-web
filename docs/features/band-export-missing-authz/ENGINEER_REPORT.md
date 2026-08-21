# Engineer Report

## Feature Slug

`band-export-missing-authz`

## Feature Title

Add Server-Side Authorization Check for Band Data Export

## Goal

Close the authorization gap in `DataBackupService.exportBandData()` by adding a server-side RPC check that enforces the intended admin/member-only export policy before any data is queried. Prevents contributors and non-members from bypassing the client-side UI gate and invoking the export service method directly.

## Architect Tasks Completed

- [x] Task 1 — Created migration `supabase/migrations/20260821120000_add_band_export_authorization.sql` defining `check_band_export_permission(UUID)` RPC function with SECURITY DEFINER, SET search_path = public, and correct admin/member/contributor/non-member logic
- [x] Task 2 — Added authorization check at the start of `exportBandData()` in `lib/features/settings/data_backup_service.dart` (after login check, before `_buildBandExport()`). Throws `DataBackupException` with user-friendly message on denial
- [x] Task 3 — Verified git diff shows exactly two files: one new migration file and one modified Dart file. No unintended changes to band_form_screen.dart, band_permissions.dart, or any other off-limits files

## Files Created

- `supabase/migrations/20260821120000_add_band_export_authorization.sql` — Defines `check_band_export_permission(p_band_id UUID)` RPC function with SECURITY DEFINER, admin/member allow, contributor/non-member deny, REVOKE from PUBLIC, GRANT to authenticated

## Files Modified

- `lib/features/settings/data_backup_service.dart` — Added server-side authorization check (lines 76-88: RPC call to `check_band_export_permission` with `p_band_id` parameter, throws `DataBackupException` on false). No other logic changes

## Analyzer Results

Command: `flutter analyze`  
Result: 0 errors / 8 pre-existing info/warnings (all in unrelated files: setlists widgets, test files). No new errors or warnings introduced by this implementation.

## Test Results

Not run — no test files exist for `DataBackupService`. The Architect plan specifies Tier 1 (pre-deploy SQL syntax check) and Tier 2 (post-deploy RPC behavior tests) which require Supabase access and are deferred to QA/deployment phase.

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff. The authorization check is inline at the single point of enforcement (exportBandData entry), the comment explains authorization policy (not code mechanics), the `isAuthorized` variable is used immediately in the guard, and the RPC cast to `bool` is required by Dart's type system. Implementation is minimal and direct — 13 lines added (2 comment, 7 RPC call, 4 exception throw).

## Verification

Manual steps performed:

- Confirmed current branch is `bug/band-export-missing-authz` (matches feature slug)
- Confirmed working tree was clean before implementation (no unrelated changes)
- Confirmed migration file exists at correct path with correct filename (timestamp `20260821120000`)
- Confirmed migration SQL includes all required elements: SECURITY DEFINER, SET search_path = public, admin/member allow logic, contributor deny logic, non-member deny logic, null auth.uid() deny logic, REVOKE from PUBLIC, GRANT to authenticated
- Confirmed Dart change is positioned after login check and before `_buildBandExport()` as specified
- Confirmed RPC parameter name (`p_band_id`) matches migration function signature
- Confirmed exception type is `DataBackupException` (matches existing pattern in the file)
- Confirmed exception message is user-friendly and does not expose internal implementation details
- Confirmed `git diff --name-status` shows exactly 1 modified file (M) and `git status --short` shows exactly 1 new untracked file (??)
- Confirmed no changes to off-limits files (band_form_screen.dart, band_permissions.dart, main.dart, any setlists/gigs/songs features)
- Confirmed `dart format` reported 0 changes (code was already formatted correctly)

## Deviations From Architect Plan

None. Implementation matches the plan exactly:

- Migration filename, function signature, logic flow, and SQL attributes match the plan specification
- Dart change location, RPC call syntax, parameter name, exception type, and error message match the plan specification
- No additional files were created or modified beyond the two specified
- No dead code (`_showExportDialog`) was touched
- No client-side UI changes were made

## Blockers Encountered

None. Both the migration and Dart change were straightforward implementations with clear specifications in the Architect plan. No ambiguities, missing dependencies, or out-of-scope requirements were encountered.

## Ready For QA

Yes. Implementation is complete, analyzer passes with 0 errors, code is formatted, and git diff confirms only the two expected files are affected. Ready for:

1. Tier 1 pre-deploy verification (SQL syntax check via dry-run parse in Supabase SQL Editor or psql)
2. Migration deployment via `supabase db push`
3. Tier 2 post-deploy verification (RPC function existence, permissions, and behavior tests per the plan's Verification section)
4. End-to-end QA testing of the live export UI flow (Edit Band → Backup / Restore → Backup Data) for admin and member roles across platforms
5. Direct service invocation tests to confirm contributor and non-member denial
