# Engineer Report

## Feature Slug

feature/backup-member-role-access

## Feature Title

Backup access for member role (split from delete permission)

## Goal

Allow `member` role users to access band data backup while keeping restore and delete admin-only. Introduce a dedicated `canExportBandData` permission and split the UI gates accordingly.

## Architect Tasks Completed

- [x] Task 1 — Added `canExportBandData` getter to `BandPermissions`
- [x] Task 2 — Restructured `Builder` in `_buildSubmitButton` to use `canExportBandData` for the backup button and `canDeleteBand` for the delete button; backup label adapts to `'Backup / Restore Data'` (admin) vs `'Backup Data'` (member)
- [x] Task 3 — `_showBackupRestoreSheet` now reads permissions and conditionally renders the restore panel for admins only; members see a single Backup panel

## Files Created

- none

## Files Modified

- lib/features/members/permissions/band_permissions.dart
- lib/features/bands/band_form_screen.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings (no new warnings introduced)

## Test Results

Not run (Architect plan did not require tests; no test files in scope)

## Verification

- `flutter analyze` clean on full project
- `dart format` applied to changed files
- Spot-checked diff matches Architect-specified code blocks for Tasks 1, 2, and 3
- No off-limits files were modified (`main.dart`, `data_backup_service.dart`, supabase migrations/functions all untouched)

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes
