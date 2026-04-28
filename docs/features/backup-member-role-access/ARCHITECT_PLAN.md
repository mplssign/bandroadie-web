# ARCHITECT PLAN

## Feature Slug

`feature/backup-member-role-access`

---

## Problem Summary

Band data export/backup is restricted to admin-only because the "Backup / Restore Data"
button in `band_form_screen.dart` is gated on `perms.canDeleteBand`, which returns
`isAdmin`. This means members and contributors cannot access backup. The fix is to
introduce a dedicated `canExportBandData` permission (admin + member), split the UI
gate so the backup button and the delete button are governed by separate permissions,
and restrict the restore panel inside the bottom sheet to admins only.

---

## Root Cause

**Confidence: HIGH — confirmed by direct code inspection**

In `lib/features/bands/band_form_screen.dart`, `_buildSubmitButton()` uses a single
`Builder` that watches `currentUserPermissionsProvider` and evaluates
`perms.canDeleteBand`. If this returns `false` (i.e. the user is not an admin), the
entire block — including both the "Backup / Restore Data" button **and** the "Delete"
button — is hidden via `return const SizedBox.shrink()`.

```dart
// band_form_screen.dart ~line 2169
final canDelete = permissionsAsync.when(
  data: (perms) => perms.canDeleteBand,   // ← admin-only
  loading: () => false,
  error: (__, _) => false,
);
if (!canDelete) return const SizedBox.shrink();  // ← hides backup + delete for members
```

`BandPermissions` has no `canExportBandData` getter. There is no permission that
expresses "admin or member can export". The service layer (`DataBackupService`) has no
role check of its own — enforcement is UI-only, with Supabase RLS as the final
authority for data reads.

The bottom sheet (`_showBackupRestoreSheet`) shows both "Backup Data" and
"Restore Data" panels unconditionally. If the sheet is made accessible to members,
the restore panel must be hidden for non-admins.

---

## Reference Docs Consulted

No `docs/reference/` subfolder exists for backup/settings. The following general
reference files were read:

- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/features/backup-member-access-and-scheduled/FEATURE_INPUT.md` — reviewed to
  ensure this plan does not conflict with that (broader, unstarted) feature; it does
  not. This plan implements only the role-access subset.

---

## Existing System Analysis

### Data flow for export

1. User taps "Backup / Restore Data" (`OutlinedButton.icon`) in `band_form_screen.dart`
2. `_showBackupRestoreSheet()` opens a bottom sheet with two side-by-side panels
3. Tapping "Backup Data" calls `_startExport()` → `_performExport()` →
   `DataBackupService.exportBandData(bandId, bandName)`
4. `exportBandData` checks only that the user is logged in, then reads all band tables
   via Supabase (bands, band_members, contributor_permissions, songs, setlists,
   setlist_special_items, setlist_songs, gigs, gig_dates, gig_responses, rehearsals,
   block_dates) and triggers a file download
5. RLS governs which rows each user can read — any active band member can read all of
   these tables in the normal app flow

### Data flow for import (restore)

1. User taps "Restore Data" in the same bottom sheet
2. `_showImportDialog()` opens a file picker, validates the JSON, shows a confirmation
   dialog, then calls `DataBackupService.importBandData(jsonContent, bandId)`
3. `importBandData` upserts all rows across all tables — a destructive write operation
4. RLS for writes is more restrictive; this must remain admin-only

### Current permission gate

| Role        | `canDeleteBand` | Backup button visible | Restore usable |
| ----------- | --------------- | --------------------- | -------------- |
| admin       | `true`          | yes                   | yes            |
| member      | `false`         | **no — incorrect**    | no             |
| contributor | `false`         | no                    | no             |

---

## Proposed Solution

Two targeted changes across two files. No new files. No new providers. No DB changes.

### 1. Add `canExportBandData` to `BandPermissions`

```dart
/// Whether this user can export / backup band data.
/// Admin & member: yes. Contributor: no.
bool get canExportBandData => isAdmin || isMember;
```

This follows the established pattern used by `canDeleteGigs`, `canCreateSetlists`, etc.

### 2. Restructure the `Builder` in `_buildSubmitButton`

Currently: a single `Builder` reads `canDeleteBand` and gates both backup and delete.

After: the same `Builder` reads **both** `canExportBandData` and `canDeleteBand`:

- If `!canExportBandData` (contributor): return `SizedBox.shrink()` — nothing shown
- If `canExportBandData` (member or admin): show the backup button
- If `canDeleteBand` (admin only): also show the delete button beneath it

The button label should reflect what is accessible:

- Admin: `'Backup / Restore Data'`
- Member: `'Backup Data'`

### 3. Restrict restore panel inside `_showBackupRestoreSheet`

Read `currentUserPermissionsProvider` inside the method and conditionally include the
restore panel (and the `VerticalDivider`) only when `canDeleteBand` is true.

When only the backup panel is shown (member), the two-column `IntrinsicHeight` + `Row`
layout is unnecessary — render a single full-width panel instead.

---

## Database Impact

**Not applicable.** No schema changes, no new migrations, no RLS policy changes, no
new or modified RPC functions or triggers. RLS already permits active band members to
read all band-scoped tables. Import writes remain gated in the UI (admin-only) and RLS
enforces writes independently.

---

## Flutter Architecture Changes

| Area                              | Change                                                                |
| --------------------------------- | --------------------------------------------------------------------- |
| `BandPermissions`                 | New getter `canExportBandData` added                                  |
| `_buildSubmitButton` (state)      | Builder reads two permissions; layout conditioned on each             |
| `_showBackupRestoreSheet` (state) | Conditionally renders restore panel; single-column layout for members |
| Providers                         | None — existing `currentUserPermissionsProvider` is reused            |
| State fields                      | None added or removed                                                 |
| Controllers                       | None                                                                  |
| Repositories                      | None                                                                  |

---

## Files to Create

None.

---

## Files to Modify

| File                                                     | What changes                                                                                                                                                                                                                   |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/members/permissions/band_permissions.dart` | Add `canExportBandData` getter (`isAdmin \|\| isMember`)                                                                                                                                                                       |
| `lib/features/bands/band_form_screen.dart`               | (1) Restructure `Builder` in `_buildSubmitButton` to use `canExportBandData` for backup button and `canDeleteBand` for delete button; (2) Modify `_showBackupRestoreSheet` to conditionally show restore panel for admins only |

---

## Files Off-Limits

| File                                             | Reason                                                                                               |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                  | Init order must not change                                                                           |
| `lib/features/settings/data_backup_service.dart` | Service is role-agnostic by design; RLS is the authority for data access; no role check belongs here |
| Any file under `supabase/migrations/`            | No schema changes required                                                                           |
| Any file under `supabase/functions/`             | No edge function changes required                                                                    |

---

## System Impact Map

| System                                 | Impact                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                          |
| Rehearsals                             | unaffected                                                                          |
| Setlists / Catalog                     | unaffected                                                                          |
| Members / RBAC                         | **affected** — new `canExportBandData` permission getter added to `BandPermissions` |
| Auth / Session                         | unaffected                                                                          |
| Routing                                | unaffected                                                                          |
| Notifications                          | unaffected                                                                          |
| Platform (iOS / Android / Web / macOS) | unaffected — change is pure Flutter/Dart logic, no platform-specific paths          |

---

## Regression Risk

**LOW**

Rationale:

- Only one permission getter is added (additive, does not change existing getters)
- Admin behavior is unchanged: admins continue to see both backup and delete
- Contributor behavior is unchanged: contributors see neither
- No database mutations, no RLS changes, no new providers or controllers
- `DataBackupService` is not modified; no risk to export/import logic
- The only risk surface is the conditional layout in `_buildSubmitButton` and
  `_showBackupRestoreSheet` — both are display-only

---

## Engineer Task Breakdown

Execute in order. Each task is atomic and independently verifiable.

**Task 1 — Add `canExportBandData` to `BandPermissions`**

File: `lib/features/members/permissions/band_permissions.dart`

Add the following getter in the "Admin-only actions" section, after `canDeleteBand`:

```dart
/// Whether this user can export / backup band data.
/// Admin & member: yes. Contributor: no.
bool get canExportBandData => isAdmin || isMember;
```

---

**Task 2 — Restructure the `Builder` in `_buildSubmitButton`**

File: `lib/features/bands/band_form_screen.dart`

Locate the `Builder` inside `if (_isEditMode) ...` in `_buildSubmitButton()`.

Replace the single permission read (`canDelete`) with two reads:

```dart
Builder(builder: (context) {
  final permissionsAsync = ref.watch(currentUserPermissionsProvider);
  final canExport = permissionsAsync.when(
    data: (perms) => perms.canExportBandData,
    loading: () => false,
    error: (__, _) => false,
  );
  final canDelete = permissionsAsync.when(
    data: (perms) => perms.canDeleteBand,
    loading: () => false,
    error: (__, _) => false,
  );
  if (!canExport) return const SizedBox.shrink();
  final isBusy =
      _isSubmitting || _isDeleting || _isExporting || _isImporting;
  return Column(
    children: [
      const SizedBox(height: Spacing.space24),
      OutlinedButton.icon(
        onPressed: isBusy ? null : _showBackupRestoreSheet,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.6), width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        icon: (_isExporting || _isImporting)
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : const Icon(AppIcons.rotateCcw, size: 15),
        label: Text(
          canDelete ? 'Backup / Restore Data' : 'Backup Data',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      if (canDelete) ...[
        const SizedBox(height: Spacing.space8),
        TextButton(
          onPressed:
              (_isSubmitting || _isDeleting) ? null : _deleteBand,
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                )
              : const Text(
                  'Delete',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.primary,
                    decoration: TextDecoration.none,
                  ),
                ),
        ),
      ],
    ],
  );
}),
```

---

**Task 3 — Restrict restore panel in `_showBackupRestoreSheet`**

File: `lib/features/bands/band_form_screen.dart`

The method `_showBackupRestoreSheet` currently builds a two-column `IntrinsicHeight`
row unconditionally. Read permissions at the top of the method and conditionally
include the restore panel.

Replace the body of `_showBackupRestoreSheet` with the following:

```dart
void _showBackupRestoreSheet() {
  final permissionsAsync = ref.read(currentUserPermissionsProvider);
  final canRestore = permissionsAsync.when(
    data: (perms) => perms.canDeleteBand,
    loading: () => false,
    error: (__, _) => false,
  );

  showModalBottomSheet(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: context.colors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canRestore)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BackupSheetPanel(
                          icon: AppIcons.download,
                          label: 'Backup Data',
                          description:
                              'Save a local copy of your band\'s current data.',
                          bullets: const [
                            'Band info & members',
                            'Songs & setlists',
                            'Gigs & rehearsals',
                            'Block-out dates',
                          ],
                          isLoading: _isExporting,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _startExport();
                          },
                        ),
                      ),
                      VerticalDivider(
                        width: 28,
                        thickness: 1,
                        color:
                            context.colors.textMuted.withValues(alpha: 0.2),
                      ),
                      Expanded(
                        child: _BackupSheetPanel(
                          icon: AppIcons.rotateCcw,
                          label: 'Restore Data',
                          description:
                              'Replace current band data with a backup file.',
                          bullets: const [
                            'Band info & members',
                            'Songs & setlists',
                            'Gigs & rehearsals',
                            'Block-out dates',
                          ],
                          isLoading: _isImporting,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _showImportDialog();
                          },
                        ),
                      ),
                    ],
                  ),
                )
              else
                _BackupSheetPanel(
                  icon: AppIcons.download,
                  label: 'Backup Data',
                  description:
                      'Save a local copy of your band\'s current data.',
                  bullets: const [
                    'Band info & members',
                    'Songs & setlists',
                    'Gigs & rehearsals',
                    'Block-out dates',
                  ],
                  isLoading: _isExporting,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startExport();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
```

Note: `ref.read` (not `ref.watch`) is correct here because this is an imperative
method call (not a `build` method). The permissions are read at the point the sheet
is opened; no reactive rebuild of the modal is needed.

---

## Verification Plan

### Tier 1 — Pre-deployment (no schema changes apply; run before any `supabase db push`)

**Not applicable.** This feature has no database changes. No SQL verification tests
are required.

---

### Tier 2 — Post-deployment (Flutter app; manual device testing)

Manual verification matrix — test on at least one platform (e.g. iOS or macOS):

**POST-DEPLOY TEST 1: Member role — backup button visible**

1. Log in as a user with `member` role in a band
2. Navigate to Edit Band (band form screen, edit mode)
3. Scroll to the bottom — verify "Backup Data" button is visible
4. Verify the "Delete" button is NOT present
5. Tap "Backup Data" — verify the bottom sheet opens with ONLY the Backup panel
   (single column, no Restore panel, no divider)
6. Tap the backup panel — verify a backup file is saved/downloaded successfully

**POST-DEPLOY TEST 2: Admin role — both backup and restore accessible**

1. Log in as a user with `admin` role
2. Navigate to Edit Band
3. Scroll to the bottom — verify "Backup / Restore Data" button is visible
4. Verify the "Delete" button IS present beneath it
5. Tap "Backup / Restore Data" — verify the two-column sheet opens (Backup + Restore)
6. Test backup: tap Backup panel — verify export works as before
7. Test restore: tap Restore panel — verify import dialog appears as before

**POST-DEPLOY TEST 3: Contributor role — no backup button**

1. Log in as a user with `contributor` role in a band
2. Navigate to Edit Band
3. Scroll to the bottom — verify neither "Backup Data" nor "Backup / Restore Data"
   button is visible, and "Delete" is also not present

**POST-DEPLOY TEST 4: `canExportBandData` unit check (optional, if unit tests are run)**

1. Instantiate `BandPermissions.fromRole('admin')` — assert `canExportBandData == true`
2. Instantiate `BandPermissions.fromRole('member')` — assert `canExportBandData == true`
3. Instantiate `BandPermissions.fromRole('contributor', subPerms: ContributorPermissions.allDisabled)` — assert `canExportBandData == false`

---

## QA Regression Areas

- **Primary:** Member role can trigger backup; contributor cannot
- **Primary:** Restore panel is absent in the sheet for members
- **Primary:** Admin behavior is unchanged (backup + restore + delete all present)
- **Secondary:** Backup file content is identical regardless of triggering role
- **Secondary:** Contributor permissions and nav visibility are unaffected
- **Secondary:** `canDeleteBand`, `canEditBandSettings` and all other existing
  `BandPermissions` getters return the same values as before

---

## Rollout / Migration Strategy

Not applicable. Flutter-only change. No backend deployment required.

---

## Out of Scope

- Scheduled / automatic backup with email delivery (separate feature `backup-member-access-and-scheduled`)
- Contributor role access to backup (explicitly excluded by feature input)
- Any changes to the backup JSON format or schema version
- Import/restore access for any role other than admin
- Service-layer RBAC checks in `DataBackupService` (UI + RLS is the existing pattern)
- New test files (no test infrastructure changes required for this scope)
