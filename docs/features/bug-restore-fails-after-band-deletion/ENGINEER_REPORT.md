# Engineer Report

## Feature Slug

`bug/restore-fails-after-band-deletion`

## Feature Title

Restore fails after band deletion

## Goal

Fix `_restoreBandData` so that restoring a band backup after the source band has
been deleted succeeds instead of throwing `PostgrestException` 42501. Also surface
real error messages from the restore flow instead of the generic "Restore failed.
Please try again." toast.

---

## Pre-Implementation State Checks

### Task 1 STOP condition — `_restoreBandData` step 10

The plan reproduces the exact step-10 code it read from disk. I read the file and
confirmed the code matched verbatim before making any changes:

```dart
// 10. Gig responses
await _upsertRows('gig_responses', entry['gig_responses'] as List? ?? []);
```

**Result: MATCH. No stop condition triggered.**

### Task 4 STOP condition — `_performImport` catch block

The plan reproduces the exact `catch (e)` block. I read lines 920–975 of
`band_form_screen.dart` and confirmed the code matched verbatim:

```dart
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
}
```

**Result: MATCH. No stop condition triggered.**

---

## Tasks Executed

### Task 1 — Filter `gig_responses` to own-user rows

**File:** `lib/features/settings/data_backup_service.dart`

**Change:** Replaced step 10 of `_restoreBandData` with a filtered version that
only upserts rows where `r['user_id'] == userId`.

### Task 2 — Filter `block_dates` to own-user rows (defensive)

**File:** `lib/features/settings/data_backup_service.dart`

**Change:** Replaced step 12 of `_restoreBandData` with a filtered version that
only upserts rows where `r['user_id'] == userId`.

### Task 3 — Wrap `_restoreBandData` in `PostgrestException` try/catch

**File:** `lib/features/settings/data_backup_service.dart`

**Change:** Wrapped the entire body of `_restoreBandData` (steps 1–12) in a
`try { … } on PostgrestException catch (e)` block that re-throws as
`DataBackupException('Database error during restore: ${e.message}')`.

**Deviation from plan note — import required:**
The plan stated: "`PostgrestException` is already available via the existing
`package:supabase_flutter/supabase_flutter.dart` import. Do not add a new import."

After implementing Task 3, `flutter analyze` reported:

```
error • The name 'PostgrestException' isn't a type and can't be used in an
       on-catch clause • lib/features/settings/data_backup_service.dart:349:10
       • non_type_in_catch_clause
```

Investigation: `data_backup_service.dart` imports
`../../app/services/supabase_client.dart`, which itself imports
`package:supabase_flutter/supabase_flutter.dart`. In Dart, transitive imports are
not re-exported — `PostgrestException` was not in scope in `data_backup_service.dart`.

**Action taken:** Added `import 'package:supabase_flutter/supabase_flutter.dart';`
directly to `data_backup_service.dart`. This is a direct fix for an error caused by
Task 3, the file is listed in the plan, and the plan's intent (using
`PostgrestException`) requires it. This is not a new dependency — the package is
already a transitive dependency in the project.

No instruction was given to override the plan's import note — the import was added
because the plan's premise ("already present") was factually incorrect, and the
analyzer error is directly caused by Task 3.

### Task 4 — Fix `_performImport` fallback catch

**File:** `lib/features/bands/band_form_screen.dart`

**Change:** Replaced the generic `'Restore failed. Please try again.'` snackbar
with one that surfaces the actual exception message after stripping the `Exception: `
prefix.

---

## `flutter analyze` Result

### Scoped (two changed files only):

```
Analyzing 2 items...
No issues found! (ran in 1.1s)
```

### Full workspace:

```
Analyzing bandroadie...
No issues found! (ran in 2.8s)
```

**Result: PASS — zero errors, zero new warnings.**

---

## `dart format` Result

```
Formatted lib/features/settings/data_backup_service.dart
Formatted 2 files (1 changed) in 0.01 seconds.
```

`band_form_screen.dart` was already correctly formatted (no changes).
`data_backup_service.dart` had minor line-wrapping reformats applied by `dart format`
in methods outside the Engineer's scope (`_buildBandExport`, `_upsertRows`). These
are pure whitespace/line-length reformats — no semantic or logic changes.

---

## Git Diff Summary

### `lib/features/bands/band_form_screen.dart`

```diff
@@ -955,7 +955,10 @@ class _BandFormScreenState extends ConsumerState<BandFormScreen>
     if (mounted) _showErrorSnackBar(e.message);
   } catch (e) {
     debugPrint('[Restore] Unexpected error: $e');
-    if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
+    if (mounted) {
+      final msg = e.toString().replaceFirst('Exception: ', '');
+      _showErrorSnackBar('Restore failed: $msg');
+    }
   } finally {
```

### `lib/features/settings/data_backup_service.dart`

Key changes only (excluding `dart format` whitespace reformats in unchanged methods):

```diff
+import 'package:supabase_flutter/supabase_flutter.dart';

 // _restoreBandData — before (steps 1–12 unwrapped):
-    // 10. Gig responses
-    await _upsertRows('gig_responses', entry['gig_responses'] as List? ?? []);
-    // 12. Block-out dates
-    await _upsertRows(
-      'block_dates',
-      entry['block_dates'] as List? ?? [],
-    );

 // _restoreBandData — after (steps 1–12 wrapped in try/catch, steps 10 & 12 filtered):
+    try {
+      // ... steps 1–9, 11 unchanged ...
+
+      // 10. Gig responses — filter to own-user rows only.
+      // INSERT RLS (gig_responses_insert_own) requires user_id = auth.uid().
+      // Other members' responses cannot be inserted by the restoring admin.
+      final allGigResponses = entry['gig_responses'] as List? ?? [];
+      final ownGigResponses = allGigResponses
+          .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
+          .toList();
+      await _upsertRows('gig_responses', ownGigResponses);
+
+      // 12. Block-out dates — filter to own-user rows only (defensive).
+      // block_dates_insert_own requires user_id = auth.uid() on INSERT path.
+      // Rows still in the DB take the UPDATE path (admins can update all); this
+      // filter guards the edge case where a row was deleted after the export.
+      final allBlockDates = entry['block_dates'] as List? ?? [];
+      final ownBlockDates = allBlockDates
+          .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
+          .toList();
+      await _upsertRows('block_dates', ownBlockDates);
+    } on PostgrestException catch (e) {
+      throw DataBackupException('Database error during restore: ${e.message}');
+    }
```

---

## Out of Scope Item (noted per plan §18)

The Architect flagged a latent multi-member `band_members` restore issue (STABLE
`is_band_member` cannot see intra-statement inserts). This was not encountered during
implementation and is explicitly out of scope per plan §18. No action taken.

---

## Files Modified

| File                                             | Change summary                                                                                                                                                             |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | Added `supabase_flutter` import; added `user_id` filter to `gig_responses` and `block_dates` upserts; wrapped `_restoreBandData` body in `on PostgrestException` try/catch |
| `lib/features/bands/band_form_screen.dart`       | `_performImport` fallback catch now surfaces actual exception message                                                                                                      |

## Files NOT Modified

All files listed in plan §11 (Off-Limits) were untouched:

- `lib/main.dart` — not touched
- `_upsertRows`, `exportBandData`, `previewBackup`, `_buildBandExport`, `_parseAndValidate`, `importBandData` — logic unchanged (formatter-only whitespace change in `_buildBandExport` / `_upsertRows` from `dart format`)
- All `supabase/migrations/**` — not touched
- `supabase/functions/**` — not touched
- `pubspec.yaml` — not touched
- All other `lib/features/**` files — not touched

---

## Status

**COMPLETE** — all four tasks implemented, `flutter analyze` passes with zero issues,
`dart format` applied. Ready for QA verification per plan §15–§16.
