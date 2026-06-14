# ARCHITECT_PLAN.md

**Feature Slug:** `feature/restore-backup-from-welcome-screen`
**Type:** feature
**Date:** 2026-06-07
**Status:** Ready for Engineer

---

## 1. Feature Slug

`feature/restore-backup-from-welcome-screen`

Branch: `feature/restore-backup-from-welcome-screen`
Docs path: `docs/features/feature-restore-backup-from-welcome-screen/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

A user whose band was deleted has no UI path to restore their data, despite the
`bug/restore-fails-after-band-deletion` fix having shipped a complete working restore
path for the missing-band scenario. The existing "Backup / Restore" entry point lives
inside `BandFormScreen` (band Settings), which is admin-only and requires an existing
band to enter. A user with zero bands is shown the "Welcome backstage!" screen
(`NoBandShell`) but has no way to invoke the restore flow from there, creating a dead
end exactly where the fix was needed most.

Adding a **"Restore from backup"** text button directly below "Create a Band" on the
welcome screen closes this gap: the user can select their backup file, confirm, and
land in their restored band — all without needing a pre-existing band.

---

## 3. Root Cause / Design Analysis

This is a feature addition, not a bug. Two confirmed design facts govern the implementation:

### Fact A — `_showImportDialog` requires `widget.initialBand != null` (HIGH — confirmed)

**File:** `lib/features/bands/band_form_screen.dart`, `_showImportDialog` (line 773)

```dart
Future<void> _showImportDialog() async {
  final band = widget.initialBand;
  if (band == null) return;          // ← hard guard: returns if no band
  ...
  await _performImport(jsonContent, band.id);
}
```

The existing restore flow is embedded in `BandFormScreen`, which is routed to via
`EditBandScreen` and requires an existing band. Attempting to expose the restore flow
from the welcome screen by routing into `BandFormScreen` with `initialBand: null`
would immediately return without doing anything. The welcome-screen entry point cannot
reuse `BandFormScreen` and must implement its own lightweight restore method.

**Design decision:** Implement `_performRestore()` directly in `_NoBandContentState`
within `no_band_shell.dart`. No changes to `BandFormScreen`. No new screen or widget
class.

### Fact B — `importBandData`'s `targetBandId` parameter is unused in both paths (HIGH — confirmed)

**File:** `lib/features/settings/data_backup_service.dart`, `importBandData` (line 142)

```dart
static Future<void> importBandData(
  String jsonContent,
  String targetBandId,     // ← passed to _restoreBandData but never used
) async {
  ...
  final backupBandId =
      (bandEntry['band'] as Map<String, dynamic>?)?['id'] as String?;
  bool bandExists = false;
  if (backupBandId != null) {
    final result = await supabase
        .from('bands')
        .select('id')
        .eq('id', backupBandId)
        .maybeSingle();
    bandExists = result != null;
  }
  await _restoreBandData(bandEntry, targetBandId, userId, bandExists);
}
```

The `bandExists` check uses `backupBandId` from the JSON, not `targetBandId`.
Inside `_restoreBandData`:

- **Existing-band path**: upserts the backup's original band row directly; `targetBandId` is never referenced.
- **Missing-band path**: calls `create_band` RPC → receives `newBandId`; `targetBandId` is never referenced.

`targetBandId` is forwarded into `_restoreBandData` but neither path reads it.
The welcome-screen call has no "current band ID" to pass, so the parameter must be
made nullable (`String? targetBandId`) to allow `null` from the new call site.

The existing call site `DataBackupService.importBandData(jsonContent, band.id)` in
`BandFormScreen._performImport` is unaffected: `String` is assignable to `String?`.

**Design decision:** Change `targetBandId` from `String` to `String?` in both
`importBandData` and `_restoreBandData`. No other logic changes.

### Fact C — Post-restore navigation is reactive (HIGH — confirmed)

**File:** `lib/features/auth/auth_gate.dart`, line 528–557

```dart
final bandState = ref.watch(activeBandProvider);
...
if (bandState.userBands.isEmpty) {
  mainContent = NoBandShell(isNewUser: _isNewUser);
} else {
  mainContent = const AppShell();
}
```

`auth_gate.dart` watches `activeBandProvider`. After a successful restore,
calling `ref.read(activeBandProvider.notifier).loadUserBands()` will re-fetch the
user's bands (which now includes the newly created band) and update `activeBandProvider`
state. `auth_gate.dart` reacts: `bandState.userBands` is no longer empty → `AppShell`
is shown, with the restored band active. No explicit `Navigator.push` is required.

### Fact D — `_NoBandContentState` is a plain `State`, not `ConsumerState` (HIGH — confirmed)

**File:** `lib/features/shell/no_band_shell.dart`, line 96+

`_NoBandContent extends StatefulWidget` / `_NoBandContentState extends State<_NoBandContent>`.
`NoBandShell extends ConsumerWidget` (line 30) — it has `WidgetRef ref` in its `build` method.

`_NoBandContentState` needs `ref` only for the post-restore provider refresh. Storing
`ref` in the state is an anti-pattern. The cleanest idiomatic approach is to pass an
`onRestoreSuccess` callback from `NoBandShell.build` (which has `ref`) into
`_NoBandContent`, allowing `_NoBandContentState` to trigger the Riverpod action without
holding a `ref` directly.

**Design decision:** Add `final VoidCallback? onRestoreSuccess` to `_NoBandContent`'s
constructor. `NoBandShell.build` passes
`onRestoreSuccess: () { ref.read(activeBandProvider.notifier).loadUserBands(); }`.
After successful import, `_NoBandContentState._performRestore()` calls
`widget.onRestoreSuccess?.call()`.

---

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/features/bug-restore-fails-after-band-deletion/ARCHITECT_PLAN.md`
- `docs/features/bug-restore-fails-after-band-deletion/ENGINEER_REPORT.md`
- `lib/features/shell/no_band_shell.dart` (full)
- `lib/features/bands/band_form_screen.dart` (lines 534–980 — restore flow)
- `lib/features/settings/data_backup_service.dart` (lines 121–470 — previewBackup, importBandData, \_restoreBandData)
- `lib/features/auth/auth_gate.dart` (lines 525–580 — NoBandShell routing)
- `lib/features/bands/active_band_controller.dart` (lines 280–470 — loadUserBands, loadAndSelectBand)
- `lib/shared/utils/snackbar_helper.dart` (lines 1–60 — showSuccessSnackBar, showErrorSnackBar)
- `lib/app/theme/design_tokens.dart` (referenced for Spacing constants)
- `pubspec.yaml` (confirmed `file_picker: ^8.1.2` present)

No `docs/reference/` folder specific to backup/restore exists.

---

## 5. Existing System Analysis

### Current welcome-screen layout

`NoBandShell` renders `_NoBandContent`, which shows:

```
[Logo animation]
[Title: "Welcome backstage!"]
[Body: "Create your band or ask a fellow bandmate to invite you."]
[↑ _bodyFade animation]

[FilledButton: "Create a Band"]
[↑ _createButtonScale rubberband animation]
```

There is no restore entry point. The "Backup / Restore" UI exists only in
`BandFormScreen._showBackupRestoreSheet()` → `_showImportDialog()`, guarded behind
`widget.initialBand != null`.

### Current restore call chain (existing entry point)

```
BandFormScreen._showBackupRestoreSheet()      [admin only, requires widget.initialBand]
  └─> _showImportDialog()                     [guard: if (band == null) return;]
        ├─> FilePicker.platform.pickFiles()
        ├─> DataBackupService.previewBackup(jsonContent)
        ├─> showDialog(confirmation)
        └─> _performImport(jsonContent, band.id)
              └─> DataBackupService.importBandData(jsonContent, band.id)
                    └─> _restoreBandData(entry, targetBandId, userId, bandExists)
```

### What `importBandData` actually does with `targetBandId`

`targetBandId` is passed into `_restoreBandData` but is used in neither path:

| Path               | `targetBandId` used? | Actual band ID source                       |
| ------------------ | -------------------- | ------------------------------------------- |
| Existing-band path | No                   | Backup's original band row (upserted as-is) |
| Missing-band path  | No                   | `newBandId` returned by `create_band` RPC   |

### Post-restore state transition

After `importBandData` returns successfully in the missing-band path:

1. A new band exists in `public.bands` (created by `create_band` RPC).
2. The user is `admin` of that band (inserted by `create_band` RPC).
3. All child data is populated (songs, setlists, gigs, rehearsals, block-out dates).
4. `activeBandProvider` still has `userBands = []` (stale, pre-restore state).
5. Calling `ref.read(activeBandProvider.notifier).loadUserBands()` fetches the fresh
   band list, populates `userBands`, and sets `activeBand = bands.first`.
6. `auth_gate.dart` watches `activeBandProvider` → `bandState.userBands.isNotEmpty` →
   `AppShell` rendered → user lands in the restored band.

---

## 6. Proposed Solution

### Design decision: implement `_performRestore()` in `_NoBandContentState`

The welcome-screen restore flow is a **new entry point** that calls the same
`DataBackupService.importBandData` as the existing flow. It does NOT route into
`BandFormScreen` or reuse `_showImportDialog`. Instead, `_NoBandContentState` receives
a callback (`onRestoreSuccess`) from `NoBandShell`, does the full file-pick → validate
→ confirm → import sequence itself, then invokes the callback on success.

This is the minimal change: one private method added to an existing private state class,
one callback wired in the parent `ConsumerWidget`, and one parameter made nullable in
the service.

### What the new "Restore from backup" button does

1. **Tap** → `_performRestore()` is called.
2. **File pick** → `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true)`.
3. **Validate** → `DataBackupService.previewBackup(jsonContent)` — throws
   `DataBackupException` on invalid format/version → surfaces error via `showErrorSnackBar`.
4. **Confirmation dialog** → Equivalent to the dialog in `BandFormScreen._showImportDialog`:
   shows `stats.bandName`, data counts, cannot-be-undone warning. User confirms with
   "Restore Band" (label differs from "Replace Data" since there is no existing band to
   replace — see §10 for exact wording).
5. **Import** → `DataBackupService.importBandData(jsonContent, null)`.
6. **Success** → `showSuccessSnackBar(context, message: '🎸 Band restored successfully!')`.
   Then `widget.onRestoreSuccess?.call()` → `loadUserBands()` → `auth_gate.dart`
   transitions to `AppShell`.
7. **Failure** → `showErrorSnackBar` with specific `DataBackupException` message, or
   generic fallback from bare `catch (e)`.

### What does NOT change

- `BandFormScreen._showImportDialog` / `_performImport` — unchanged.
- `DataBackupService` internal logic (`_restoreBandData`, `_upsertRows`, `_generateUuid`,
  `previewBackup`, `exportBandData`) — unchanged.
- `auth_gate.dart` routing logic — unchanged.
- `activeBandProvider` / `ActiveBandNotifier` — no new methods; `loadUserBands()` is
  called as-is.
- The backup file schema (schema v1) — unchanged.
- The confetti animation, logo animation, and "Create a Band" button — unchanged.

---

## 7. Database Impact

**Not applicable.**

No new tables, columns, migrations, RLS policies, or RPC functions are required. The
`create_band` and `delete_band` RPCs are called as-is (the former by
`DataBackupService._restoreBandData`, not directly by this feature). No RLS changes.

---

## 8. Flutter Architecture Changes

### State management

`activeBandProvider.notifier.loadUserBands()` is called after a successful restore.
This is an existing public method. No new providers, no new notifiers.

### Providers

No changes to any provider or notifier class.

### Repositories

No changes.

### Widgets

`_NoBandContent` gains one new optional constructor parameter (`onRestoreSuccess`).
`_NoBandContentState` gains:

- `bool _isImporting = false` field
- `Future<void> _performRestore()` method
- A `TextButton` in `build()` beneath the "Create a Band" `ScaleTransition`

`NoBandShell.build()` passes the new `onRestoreSuccess` callback.

---

## 9. Files to Create

| File                                                                         | Justification                                |
| ---------------------------------------------------------------------------- | -------------------------------------------- |
| `docs/features/feature-restore-backup-from-welcome-screen/ARCHITECT_PLAN.md` | This document — required by operating model. |

**No new Dart files.** Changes are localised to existing files.

---

## 10. Files to Modify

| File                                             | What changes                                                                                                                                                                                                                                                                                                                        |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/shell/no_band_shell.dart`          | Primary change. Add `onRestoreSuccess` callback to `_NoBandContent`; wire in `NoBandShell.build`; add `_isImporting`, `_performRestore()`, confirmation dialog, and "Restore from backup" `TextButton` to `_NoBandContentState`. Add imports for `dart:convert`, `file_picker`, `data_backup_service.dart`, `snackbar_helper.dart`. |
| `lib/features/settings/data_backup_service.dart` | Make `targetBandId` nullable (`String? targetBandId`) in `importBandData` signature. Propagate nullable type to `_restoreBandData` signature (where it is also unused). No logic change in either method.                                                                                                                           |

### `no_band_shell.dart` — detailed change summary

#### 1. New imports (add after existing imports, alphabetically within each group)

```dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../../shared/utils/snackbar_helper.dart';
import '../settings/data_backup_service.dart';
```

#### 2. `_NoBandContent` — add `onRestoreSuccess` parameter

```dart
class _NoBandContent extends StatefulWidget {
  final VoidCallback onOpenMenu;
  final VoidCallback? onOpenBandSwitcher;
  final bool isNewUser;
  final VoidCallback? onRestoreSuccess;   // ← NEW

  const _NoBandContent({
    required this.onOpenMenu,
    this.onOpenBandSwitcher,
    this.isNewUser = false,
    this.onRestoreSuccess,                // ← NEW
  });
  ...
}
```

#### 3. `NoBandShell.build` — wire up callback

In the `_NoBandContent(...)` constructor call inside `NoBandShell.build`:

```dart
_NoBandContent(
  onOpenMenu: () => overlayNotifier.openMenuDrawer(),
  onOpenBandSwitcher: bandState.userBands.isNotEmpty
      ? () => overlayNotifier.openBandSwitcher()
      : null,
  isNewUser: isNewUser,
  onRestoreSuccess: () {                                     // ← NEW
    ref.read(activeBandProvider.notifier).loadUserBands();
  },
),
```

#### 4. `_NoBandContentState` — add `_isImporting` field

```dart
bool _isImporting = false;
```

#### 5. `_NoBandContentState` — add `_performRestore()` method

Add this method to `_NoBandContentState`. It mirrors the pattern from
`BandFormScreen._showImportDialog` / `_performImport` but is self-contained:

```dart
Future<void> _performRestore() async {
  // Step 1: File pick
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
  } catch (_) {
    if (mounted) showErrorSnackBar(context, message: 'Could not open file picker.');
    return;
  }
  if (result == null || result.files.single.bytes == null) return;

  // Step 2: Decode bytes
  final String jsonContent;
  try {
    jsonContent = utf8.decode(result.files.single.bytes!);
  } catch (_) {
    if (mounted) showErrorSnackBar(context, message: 'Could not read the selected file.');
    return;
  }

  // Step 3: Validate and preview
  final BandBackupStats stats;
  try {
    stats = DataBackupService.previewBackup(jsonContent);
  } on DataBackupException catch (e) {
    if (mounted) showErrorSnackBar(context, message: e.message);
    return;
  } catch (_) {
    if (mounted) {
      showErrorSnackBar(context, message: 'This file does not appear to be a valid backup.');
    }
    return;
  }

  if (!mounted) return;

  // Step 4: Confirmation dialog
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _buildRestoreConfirmDialog(context, stats),
  );
  if (confirmed != true || !mounted) return;

  // Step 5: Import
  setState(() => _isImporting = true);
  try {
    await DataBackupService.importBandData(jsonContent, null);
    if (mounted) {
      showSuccessSnackBar(context, message: '🎸 Band restored successfully!');
      widget.onRestoreSuccess?.call();
    }
  } on DataBackupException catch (e) {
    if (mounted) showErrorSnackBar(context, message: e.message);
  } catch (e) {
    if (mounted) {
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      showErrorSnackBar(context, message: 'Restore failed: $msg');
    }
  } finally {
    if (mounted) setState(() => _isImporting = false);
  }
}
```

#### 6. `_NoBandContentState` — add `_buildRestoreConfirmDialog` helper

Add a private helper method that builds the confirmation `AlertDialog`. The dialog
should be visually equivalent to the one in `BandFormScreen._showImportDialog` but
with copy adapted to the "recreate from backup" context:

- **Title:** "Restore from Backup?"
- **Body:** "A band named **[stats.bandName]** will be recreated with the following data:"
- **Counts row**: Members / Songs / Setlists / Gigs / Rehearsals / Block-out dates (same
  layout as `BandFormScreen._buildRestoreRow`)
- **Warning box:** "This will create a new band and populate it with the backup data.
  This action cannot be undone."
- **Buttons:** "Cancel" (dismiss with `false`) and a filled "Restore Band" (dismiss
  with `true`) — use `AppColors.primary` background, white text
- **`backgroundColor`:** `context.colors.surface`
- **`shape`:** `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`

The engineer should implement `_buildRestoreConfirmDialog` as a private helper method
in `_NoBandContentState` that accepts `(BuildContext context, BandBackupStats stats)`.
Reuse the same `Row`/`Expanded`/`Text` layout pattern from `BandFormScreen._buildRestoreRow`
inline (no shared helper needed — these are private methods in different classes).

#### 7. `_NoBandContentState.build()` — add "Restore from backup" TextButton

Inside the `Column` in `LayoutBuilder.builder`, directly after the `ScaleTransition`
wrapping the "Create a Band" `FilledButton`, add:

```dart
const SizedBox(height: Spacing.space16),

// Restore from backup — secondary action for users with no bands
FadeTransition(
  opacity: _bodyFade,
  child: TextButton(
    onPressed: _isImporting ? null : _performRestore,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.space12,
        horizontal: Spacing.space16,
      ),
    ),
    child: _isImporting
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          )
        : Text(
            'Restore from backup',
            style: AppTextStyles.body.copyWith(
              fontSize: 15,
              color: AppColors.primary,
            ),
          ),
  ),
),
```

**Animation:** Uses existing `_bodyFade` animation (interval 0.35 → 0.70) so the button
fades in with the body copy without requiring a new `AnimationController`.

**Loading state:** While `_isImporting` is true, the text is replaced with a
`CircularProgressIndicator` sized to match the text height, and `onPressed` is set to
`null` (disabled). The "Create a Band" button has no explicit loading state and does
not need to be disabled during restore — the operations are independent.

### `data_backup_service.dart` — detailed change summary

#### 1. `importBandData` — make `targetBandId` nullable

```dart
// BEFORE
static Future<void> importBandData(
  String jsonContent,
  String targetBandId,
) async {

// AFTER
static Future<void> importBandData(
  String jsonContent,
  String? targetBandId,
) async {
```

#### 2. `_restoreBandData` — make `targetBandId` nullable

```dart
// BEFORE
static Future<void> _restoreBandData(
  Map<String, dynamic> entry,
  String targetBandId,
  String userId,
  bool bandExists,
) async {

// AFTER
static Future<void> _restoreBandData(
  Map<String, dynamic> entry,
  String? targetBandId,
  String userId,
  bool bandExists,
) async {
```

No logic changes inside either method. The parameter remains unreferenced in both paths.

---

## 11. Files Off-Limits

| File                                                                                                                                                                              | Reason                                                                                 |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                                                                                                                   | Initialisation order must not change                                                   |
| `lib/features/bands/band_form_screen.dart`                                                                                                                                        | Existing restore entry point must be fully preserved                                   |
| `lib/features/auth/auth_gate.dart`                                                                                                                                                | Routing logic is correct and must not change                                           |
| `lib/features/bands/active_band_controller.dart`                                                                                                                                  | `loadUserBands()` is called as-is; no method changes                                   |
| `lib/features/settings/data_backup_service.dart` — `_restoreBandData`, `_upsertRows`, `_generateUuid`, `previewBackup`, `exportBandData`, `_buildBandExport`, `_parseAndValidate` | All internal logic is correct and off-limits; only the signature's nullability changes |
| All Supabase migrations                                                                                                                                                           | No DB changes required                                                                 |
| `supabase/functions/**`                                                                                                                                                           | No edge function changes required                                                      |
| `pubspec.yaml`                                                                                                                                                                    | No new packages — `file_picker` already present at `^8.1.2`                            |
| All other `lib/features/**` files                                                                                                                                                 | Not in scope                                                                           |

---

## 12. System Impact Map

| System                                 | Impact                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------- |
| Band management (create/edit/delete)   | Unaffected                                                                                    |
| Backup / Restore                       | Affected — new entry point; existing entry point unchanged                                    |
| Gigs                                   | Unaffected                                                                                    |
| Rehearsals                             | Unaffected                                                                                    |
| Setlists / Catalog                     | Unaffected                                                                                    |
| Songs / Catalog                        | Unaffected                                                                                    |
| Members / RBAC                         | Unaffected (no policy changes; create_band RPC used as-is by the service)                     |
| Auth / Session                         | Unaffected                                                                                    |
| Routing                                | Affected — `auth_gate.dart` reacts to provider update after restore (no code change required) |
| Notifications                          | Unaffected                                                                                    |
| Calendar / Block-out dates             | Unaffected                                                                                    |
| Welcome / Empty-state screen           | Affected — new button added                                                                   |
| Platform (iOS / Android / Web / macOS) | Unaffected — Dart change is cross-platform; `file_picker` already supports all platforms      |

---

## 13. Regression Risk

**LOW**

Rationale:

- The existing-band restore path in `BandFormScreen` is completely unchanged. The new
  `_performRestore()` in `no_band_shell.dart` is an additive method; it does not modify
  any shared logic.
- The `targetBandId` nullability change in `data_backup_service.dart` is a type
  annotation change only. Both paths in `_restoreBandData` already ignore the parameter.
  The existing call site `DataBackupService.importBandData(jsonContent, band.id)` passes
  `String` which is assignable to `String?` — zero change in behaviour.
- `auth_gate.dart` routing is reactive and already handles the transition from
  `NoBandShell` to `AppShell` when `activeBandProvider.userBands` becomes non-empty.
  No routing code is modified.
- The change is confined to two files. Auth, session, and init order are untouched.
- Risk is LOW (not MEDIUM) because the missing-band restore path was already tested by
  `bug/restore-fails-after-band-deletion` QA. This feature only adds a UI entry point
  that calls the same tested service method.

---

## 14. Engineer Task Breakdown

Execute in strict order. Do not skip or reorder.

### Task 1 — Make `targetBandId` nullable in `data_backup_service.dart`

In `importBandData`:

- Change `String targetBandId` → `String? targetBandId`

In `_restoreBandData`:

- Change `String targetBandId` → `String? targetBandId`

No other changes in this file. Run `flutter analyze` after this task to confirm
the existing call site in `band_form_screen.dart` still compiles (it will — `String` is
assignable to `String?`).

### Task 2 — Add imports to `no_band_shell.dart`

Add the following imports. Insert them in appropriate groupings (Dart SDK first,
then Flutter packages, then project-relative):

```dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
```

And in the project-relative group:

```dart
import '../../shared/utils/snackbar_helper.dart';
import '../settings/data_backup_service.dart';
```

### Task 3 — Add `onRestoreSuccess` callback to `_NoBandContent`

Add `final VoidCallback? onRestoreSuccess;` field and constructor parameter to
`_NoBandContent`. The field is optional (nullable) — the screen is functional without
it (no restore button action would fire, but the UI would still render).

### Task 4 — Wire `onRestoreSuccess` in `NoBandShell.build`

Pass `onRestoreSuccess: () { ref.read(activeBandProvider.notifier).loadUserBands(); }`
to the `_NoBandContent(...)` constructor call in `NoBandShell.build`.

**Important:** `loadUserBands()` returns `Future<void>`. The callback is `void Function()`.
Invoking `loadUserBands()` without `await` inside a `VoidCallback` is intentional and
correct here — the provider update is fire-and-forget; `auth_gate.dart` reacts
reactively when it completes.

### Task 5 — Add `_isImporting` field to `_NoBandContentState`

Add `bool _isImporting = false;` as an instance field in `_NoBandContentState`.

### Task 6 — Add `_buildRestoreConfirmDialog` helper to `_NoBandContentState`

Implement as a private method. Signature:

```dart
Widget _buildRestoreConfirmDialog(BuildContext context, BandBackupStats stats)
```

Content:

- Title row: warning icon + "Restore from Backup?" text
- Body: intro sentence → "**[stats.bandName]** will be recreated with the following data:"
- Data rows (use `Row` with Expanded label + right-aligned count text):
  - Members: `stats.memberCount`
  - Songs: `stats.songCount`
  - Setlists: `stats.setlistCount`
  - Gigs: `stats.gigCount`
  - Rehearsals: `stats.rehearsalCount`
  - Block-out dates: `stats.blockOutCount`
- Warning box (container with `AppColors.error` text): "This will create a new band and
  populate it with your backup data. This cannot be undone."
- Buttons:
  - "Cancel" → `Navigator.of(context).pop(false)` — text style, `textSecondary` color
  - "Restore Band" → `Navigator.of(context).pop(true)` — filled, `AppColors.primary`
    background, white text, `fontSize: 16`, `FontWeight.w600`

Use `AlertDialog` with `backgroundColor: context.colors.surface`,
`shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`.

### Task 7 — Add `_performRestore()` method to `_NoBandContentState`

Implement the method as specified in §10 (detailed change summary, item 5). Key points:

- File pick → null-check → UTF-8 decode → `previewBackup` → confirm dialog → `importBandData(jsonContent, null)` → success/error handling
- Every async gap followed by a `mounted` guard
- `setState(() => _isImporting = true)` before the import call; `setState(() => _isImporting = false)` in `finally`
- On success: `showSuccessSnackBar(context, message: '🎸 Band restored successfully!')` then `widget.onRestoreSuccess?.call()`
- On `DataBackupException`: `showErrorSnackBar(context, message: e.message)`
- On bare `catch (e)`: extract message (strip "Exception: " prefix) and `showErrorSnackBar`

### Task 8 — Add "Restore from backup" TextButton to `_NoBandContentState.build()`

In the `Column` inside `LayoutBuilder.builder`, after the `ScaleTransition` for
"Create a Band", add:

1. `const SizedBox(height: Spacing.space16)`
2. `FadeTransition(opacity: _bodyFade, child: TextButton(...))` as specified in §10
   (item 7). The button shows text when idle and a 18×18 `CircularProgressIndicator`
   when `_isImporting == true`.

### Task 9 — `flutter analyze` — zero errors

Run `flutter analyze`. Fix any analysis errors introduced by these changes. Do not
modify files not listed in this plan to fix pre-existing errors.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment

No Supabase migration is deployed in this feature. All Tier 1 checks are Dart/Flutter
analysis only.

```
-- PRE-DEPLOY TEST 1: flutter analyze passes with 0 errors
Run: flutter analyze
Expected: 0 errors, 0 warnings on modified files.

-- PRE-DEPLOY TEST 2: Existing call site compiles without change
Confirm: lib/features/bands/band_form_screen.dart still compiles.
The call DataBackupService.importBandData(jsonContent, band.id) passes a non-null
String to String? — valid in Dart null safety with no syntax change required.
Expected: no error at line ~936 of band_form_screen.dart.

-- PRE-DEPLOY TEST 3: _NoBandContentState has no WidgetRef stored as field
Confirm: no `WidgetRef ref` field added to _NoBandContentState.
The only Riverpod access is via the `onRestoreSuccess` VoidCallback passed from
NoBandShell.build.
Expected: grep for 'WidgetRef' in no_band_shell.dart returns 0 matches within
_NoBandContentState.

-- PRE-DEPLOY TEST 4: _isImporting field is reset in finally block
Confirm: _performRestore contains a finally { if (mounted) setState(() => _isImporting = false); }
block. This ensures the loading indicator clears on both success and error paths.
Expected: method contains exactly one finally block that resets _isImporting.
```

### Tier 2 — Post-deployment (manual integration tests)

No database push is required. These are app-level integration tests.

```
-- POST-DEPLOY TEST 1: "Restore from backup" button is visible on welcome screen
Steps:
  1. Log in as a user with zero bands.
  2. Observe the "Welcome backstage!" screen.
Expected:
  - A text button labeled "Restore from backup" is visible below "Create a Band".
  - The button uses rose/primary color text.

-- POST-DEPLOY TEST 2: File picker opens on tap
Steps:
  1. On the welcome screen, tap "Restore from backup".
Expected:
  - The system file picker opens.
  - Filtering to .json files only.

-- POST-DEPLOY TEST 3: Restore recreates deleted band (primary scenario)
Steps:
  1. Export a band's data (JSON backup file) from any band's Settings screen.
  2. Delete that band via Settings → "Delete Band".
  3. Confirm the user now has zero bands (welcome screen shown).
  4. Tap "Restore from backup".
  5. Select the previously exported JSON file.
  6. Confirm the restoration dialog shows correct band name and data counts.
  7. Tap "Restore Band".
Expected:
  - Loading indicator replaces button text during restore.
  - "🎸 Band restored successfully!" snackbar appears.
  - App transitions from welcome screen to AppShell (band dashboard).
  - The restored band is active and contains songs, setlists, gigs, rehearsals, and
    block-out dates from the backup.
  - The original deleted band's ID is NOT reused (new UUID assigned by create_band RPC).

-- POST-DEPLOY TEST 4: Error shown for invalid backup file
Steps:
  1. On the welcome screen, tap "Restore from backup".
  2. Select a JSON file that is not a BandRoadie backup (e.g., any arbitrary JSON).
Expected:
  - A specific error snackbar is shown: "Unrecognised backup format. This file is not
    a BandRoadie backup." (message from DataBackupException in _parseAndValidate).
  - The welcome screen remains. No band is created.

-- POST-DEPLOY TEST 5: Error shown for version-mismatch backup
Steps:
  1. Manually edit a valid backup JSON to change "schema_version" to 99.
  2. Attempt restore from welcome screen.
Expected:
  - Error snackbar: "Unsupported backup version (99). This app supports version 1."

-- POST-DEPLOY TEST 6: Cancel in confirmation dialog does nothing
Steps:
  1. Tap "Restore from backup", select a valid backup file.
  2. When the confirmation dialog appears, tap "Cancel".
Expected:
  - Dialog dismisses.
  - No restore is performed.
  - Welcome screen is unchanged.

-- POST-DEPLOY TEST 7: Existing band restore entry point unaffected
Steps:
  1. Log in as admin of an existing band.
  2. Navigate to Settings → Backup / Restore.
  3. Tap "Restore Data" and select a valid backup file.
Expected:
  - Flow is identical to pre-feature behavior.
  - Restore completes successfully for the existing band.

-- POST-DEPLOY TEST 8: importBandData(jsonContent, band.id) call site unchanged
Steps:
  1. Confirm flutter analyze passes with 0 errors on band_form_screen.dart.
Expected:
  - No warnings or type errors at the existing call site (String passed to String?).
```

---

## 16. QA Regression Areas

1. **Restore after deletion from welcome screen (primary)** — verify full flow works end-to-end for the zero-bands user (POST-DEPLOY TEST 3).
2. **Error surfacing** — invalid file, version mismatch, cancel (POST-DEPLOY TESTS 4–6).
3. **Existing Settings restore entry point regression** — must behave identically to pre-feature (POST-DEPLOY TEST 7).
4. **No band created on cancel** — tapping Cancel does not create any band or write any data (POST-DEPLOY TEST 6).
5. **Loading state** — `_isImporting` loading indicator shows during restore, clears after (success or error).
6. **Auth / Session unaffected** — logging in, logging out, and the full auth flow must be unaffected by the new import and callback.
7. **Multi-band user unaffected** — a user with existing bands never sees the welcome screen and therefore never encounters this new button. Confirm by logging in as a user with ≥1 band.

---

## 17. Rollout / Migration Strategy

1. Deploy the Flutter app (web: `./tools/deploy_web.sh`; mobile: standard release build).
2. No `supabase db push` required — no database changes.
3. No data backfill required.

---

## 18. Out of Scope

- Any change to the restore logic inside `DataBackupService` beyond the `targetBandId` nullability fix.
- Changes to `BandFormScreen` (existing restore entry point must be fully preserved).
- Adding an "export" / "backup" entry point to the welcome screen (export requires an existing band to export from; out of scope by definition).
- Changing the onboarding copy ("Create your band or ask a fellow bandmate to invite you.") — no copy changes.
- Adding confetti or animated entrance to the new button (kept consistent with body fade only).
- Deduplication of the confirmation dialog UI between `BandFormScreen` and `_NoBandContentState` (they are private helpers in different classes; sharing would require a new widget — over-engineering).
- UX to distinguish "recreating a deleted band" vs. "restoring into an existing band" beyond the dialog copy change ("Restore Band" vs. "Replace Data") — full UX redesign is out of scope.
- Expanding restore access to non-admin roles (separate planned feature).
