# ARCHITECT_PLAN.md

**Feature Slug:** `bug/restore-fails-after-band-deletion`
**Type:** bug
**Date:** 2026-06-07
**Status:** Ready for Engineer

---

## 1. Feature Slug

`bug/restore-fails-after-band-deletion`

Branch: `bug/restore-fails-after-band-deletion`
Docs path: `docs/features/bug-restore-fails-after-band-deletion/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

Restoring from a valid BandRoadie backup file fails with the generic toast "Restore failed. Please try again." when the source band has been deleted. The user receives no actionable information about what failed. The expected behaviour is that restore recreates the band from the backup's identity fields (name, avatar colour, avatar image) and populates all child data, regardless of whether the original band still exists.

---

## 3. Root Cause

Four root causes were confirmed in code. All four must be fixed. They interact as a failure chain.

### RC-1 — `_restoreBandData` ignores `targetBandId` and upserts original IDs directly (HIGH — confirmed)

**File:** `lib/features/settings/data_backup_service.dart`, `_restoreBandData` (line ~290)

```dart
static Future<void> _restoreBandData(
  Map<String, dynamic> entry,
  String targetBandId,   // ← accepted but NEVER used
  String userId,         // ← accepted but NEVER used
) async {
  final band = entry['band'] as Map<String, dynamic>?;
  if (band != null) await _upsertRows('bands', [band]);  // original band ID used
  await _upsertRows('band_members', entry['band_members'] as List? ?? []);
  ...
}
```

`targetBandId` is passed in from `BandFormScreen._performImport` but is discarded. The function upserts the raw backup rows with their original UUIDs.

**When the source band still exists:** the `bands` upsert is an UPDATE (row exists) → passes RLS → works.

**When the source band was deleted:** the `bands` upsert attempts an INSERT. At that moment the user has no `band_members` row for the deleted band (it was cascade-deleted by `delete_band`), so any INSERT policy that checks band membership fails. Even if the INSERT somehow succeeds, the subsequent `band_members` upsert (step 2) tries to insert ALL original members. Because the user has no admin row yet at that point, the INSERT RLS for adding other users' rows is blocked — a bootstrapping deadlock.

The `create_band` RPC is the intended band-creation path. It atomically inserts the band row, inserts the creator as `admin`, and handles the `public.users` edge case via `SECURITY DEFINER`. Bypassing it via direct `upsert` is incorrect for the new-band scenario.

### RC-2 — Generic `catch (e)` in `_performImport` swallows the real exception (HIGH — confirmed)

**File:** `lib/features/bands/band_form_screen.dart`, `_performImport` (line ~955)

```dart
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
}
```

Any exception that is not a `DataBackupException` — including `PostgrestException` from Supabase with a specific error code and message — is converted to the generic toast. The real error is only visible in debug logs, invisible to the user and to any crash reporter.

This is the direct cause of "Restore failed. Please try again." being shown instead of a specific message.

### RC-3 — `delete_band` does not cascade `rehearsals` or `block_dates` (HIGH — confirmed)

**File:** `supabase/migrations/20260302000000_band_user_roles.sql`, `delete_band` function (line ~326)

The `delete_band` RPC explicitly deletes: `band_members`, `band_invitations`, `gig_responses`, `gigs`, `setlist_songs`, `setlists`, `songs`, `bands`.

It does **not** delete `rehearsals` or `block_dates`. These rows are orphaned post-deletion with `band_id = deleted-band-uuid`.

**Impact on restore:** When restore runs after deletion with a new band ID (`new-band-uuid`), it tries to upsert the backup's rehearsal rows — same original UUIDs, but with `band_id = new-band-uuid`. Because those UUIDs already exist as orphaned rows (`band_id = old-band-uuid`), PostgREST's `INSERT … ON CONFLICT (id) DO UPDATE` triggers the UPDATE path. The rehearsals UPDATE RLS policy is:

```sql
USING (
  EXISTS (
    SELECT 1 FROM public.band_members bm
    WHERE bm.band_id = rehearsals.band_id   -- EXISTING row's band_id = old-band-uuid
    AND bm.user_id = auth.uid()
    AND bm.status = 'active'
    AND bm.role IN ('admin', 'member')
  )
)
```

`rehearsals.band_id` in the USING clause is the **current row's** `band_id` (`old-band-uuid`). The user has no membership in the deleted band → UPDATE is rejected → `PostgrestException` → swallowed → generic toast. Identical logic applies to `block_dates`.

### RC-4 — `bands` table direct INSERT is the wrong creation path; bootstrap deadlock for `band_members` (MEDIUM — strongly implied)

The `bands` INSERT RLS policy is defined in the Supabase dashboard and is not present in any tracked migration. Two failure sub-modes are possible:

- **Sub-mode A:** The INSERT policy checks `band_members` for admin status → fails immediately (no membership rows exist post-deletion).
- **Sub-mode B:** The INSERT policy only requires `created_by = auth.uid()` → the `bands` row is inserted. But step 2 then tries to upsert ALL backup `band_members` rows (including other users). The `band_members` INSERT policy requires the caller to be an active admin for the target band. The caller's admin row has not been inserted yet at this point → deadlock → RLS blocks the INSERT → exception → swallowed.

Confidence is MEDIUM because the exact `bands` INSERT policy is not visible in migrations. However, both sub-modes lead to the same failure and are fully resolved by RC-1's fix (call `create_band` instead, which handles the bootstrap atomically).

> **Engineer action required:** Before implementing, run the following query against production to confirm the exact bands INSERT policy. Record the result in `ENGINEER_REPORT.md`:
>
> ```sql
> SELECT policyname, cmd, qual, with_check
> FROM pg_policies
> WHERE tablename = 'bands' AND schemaname = 'public';
> ```

---

## 4. Reference Docs Consulted

No `docs/reference/` folder specific to backup/restore exists. The following files were read during diagnosis:

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/reference/architecture/database_schema.md`
- `docs/reference/architecture/architecture.md`
- `lib/features/settings/data_backup_service.dart` (full)
- `lib/features/bands/band_form_screen.dart` (lines 531–970)
- `supabase/migrations/20260302000000_band_user_roles.sql` (full)
- `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql`
- `supabase/migrations/087_fix_create_band_no_profile.sql`

---

## 5. Existing System Analysis

### Call chain for restore

```
BandFormScreen._showBackupRestoreSheet()        [gate: canDeleteBand = admin-only]
  └─> _showImportDialog()                       [requires widget.initialBand != null]
        └─> _performImport(jsonContent, band.id) [band.id = CURRENT band being edited]
              └─> DataBackupService.importBandData(jsonContent, bandId)
                    └─> _restoreBandData(bandEntry, bandId, userId)  ← bandId unused
                          ├─> _upsertRows('bands',        [backup.band])          step 1
                          ├─> _upsertRows('band_members', [backup.band_members])  step 2
                          ├─> _upsertRows('contributor_permissions', [...])       step 3
                          ├─> _upsertRows('songs',        [...])                  step 4
                          ├─> _upsertRows('setlists',     [...])                  step 5
                          ├─> _upsertRows('setlist_special_items', [...])         step 6
                          ├─> _upsertRows('setlist_songs', [...])                 step 7
                          ├─> _upsertRows('gigs',         [...])                  step 8
                          ├─> _upsertRows('gig_dates',    [...])                  step 9
                          ├─> _upsertRows('gig_responses',[...])                  step 10
                          ├─> _upsertRows('rehearsals',   [...])                  step 11
                          └─> _upsertRows('block_dates',  [...])                  step 12
```

### What `delete_band` removes vs. what remains

| Table              | Deleted by `delete_band`          | Remains (orphaned)            |
| ------------------ | --------------------------------- | ----------------------------- |
| `bands`            | ✓                                 | —                             |
| `band_members`     | ✓                                 | —                             |
| `band_invitations` | ✓                                 | —                             |
| `gig_responses`    | ✓                                 | —                             |
| `gigs`             | ✓                                 | —                             |
| `setlist_songs`    | ✓                                 | —                             |
| `setlists`         | ✓                                 | —                             |
| `songs`            | ✓                                 | —                             |
| `rehearsals`       | —                                 | ✓ orphaned with old `band_id` |
| `block_dates`      | —                                 | ✓ orphaned with old `band_id` |
| `gig_dates`        | implicit CASCADE via `gigs.id` FK | —                             |

### Why the current restore breaks in the post-deletion scenario

1. Step 1 (`bands` upsert) → attempts INSERT on deleted band → fails RLS or succeeds but cannot bootstrap membership (RC-1, RC-4).
2. If step 1 fails → `PostgrestException` thrown from `_upsertRows`.
3. `PostgrestException` is not a `DataBackupException` → falls into bare `catch (e)` in `_performImport` (RC-2) → generic toast.
4. Even if step 1 somehow succeeded, steps 11 and 12 (`rehearsals`, `block_dates`) would still fail with a RLS UPDATE rejection on orphaned rows (RC-3).

### Why the current restore works when the band still exists

The band row exists → `bands` upsert is an UPDATE (not INSERT) → user is still an admin → band_members upsert passes → all subsequent RLS checks pass (admin membership established) → rehearsals and block_dates upsert as UPDATEs on existing rows where the user IS a member → succeeds.

---

## 6. Proposed Solution

### Design decision: use `create_band` RPC for the missing-band path

When the backup's band ID is not found in the database, the restore must:

1. Call `supabase.rpc('create_band', params: {...})` to create a fresh band and get `newBandId`. The RPC atomically inserts the band row and adds the current user as `admin` — eliminating the bootstrap deadlock entirely.
2. Remap `band_id` to `newBandId` in every child table row before upserting.
3. Handle the current user's `band_member` row: `create_band` inserts it with a fresh UUID. Upserting the backup's original member row for the same user (same `user_id`, different UUID) would collide on the `(band_id, user_id)` unique constraint. The current user's row must be filtered out of the backup's `band_members` list.
4. For `rehearsals` and `block_dates`: orphaned rows with the original UUIDs still exist in the database. The `ON CONFLICT (id) DO UPDATE` path is blocked by RLS. Solution: generate fresh UUIDs for each row using a local UUID v4 helper (see §10) before upserting. For `rehearsals`, also remap the self-referential `parent_rehearsal_id` using an old→new UUID map.
5. For all other child tables (songs, setlists, setlist_special_items, setlist_songs, gigs, gig_dates, gig_responses): their original UUIDs were deleted by `delete_band` → INSERT path succeeds → only `band_id` remapping needed.

### Design decision: fix `delete_band` cascade gap

The orphaned `rehearsals` and `block_dates` rows are a pre-existing data integrity defect. The fix must include a migration that updates `delete_band` to also delete these tables, preventing future orphaning. This does not retroactively clean up existing orphaned rows (those are handled by the UUID regeneration in the Dart fix).

### Design decision: surface specific errors

Replace the bare `catch (e)` in `_performImport` with a handler that wraps unknown exceptions as `DataBackupException` with the underlying message. All errors thrown from `_restoreBandData` should be typed `DataBackupException` with user-readable messages before they propagate.

### What does NOT change

- The backup file schema/format (out of scope).
- The `importBandData` public method signature.
- The `previewBackup` / `exportBandData` methods (unaffected).
- The UI flow in `BandFormScreen` (only `_performImport` error handler changes).
- The "band still exists" path (no behavioural change for normal restores).
- Any other feature, controller, repository, or service.

---

## 7. Database Impact

### `delete_band` RPC — updated (new migration required)

Add `DELETE FROM public.rehearsals WHERE band_id = band_uuid;` and `DELETE FROM public.block_dates WHERE band_id = band_uuid;` to the `delete_band` function body, in FK-safe order before `DELETE FROM public.bands`.

**Migration file:** `supabase/migrations/<timestamp>_fix_delete_band_cascade.sql`

No schema change. `CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)` only — signature is unchanged.

**RLS impact:** None. `delete_band` is `SECURITY DEFINER` and bypasses RLS.

**No new tables, columns, triggers, or policies.**

### `create_band` RPC — called, not modified

The existing `create_band(p_name TEXT, p_avatar_color TEXT DEFAULT NULL, p_image_url TEXT DEFAULT NULL)` RPC is used as-is from the Dart restore path. No changes to its implementation.

### Other DB objects

| Object                                                                             | Impact                         |
| ---------------------------------------------------------------------------------- | ------------------------------ |
| RLS policies (bands, band_members, songs, setlists, gigs, rehearsals, block_dates) | Unaffected — no policy changes |
| All other RPC functions                                                            | Unaffected                     |
| Triggers                                                                           | Unaffected                     |
| Migrations (other than the one above)                                              | Unaffected                     |

---

## 8. Flutter Architecture Changes

### State management

`_performImport` in `BandFormScreen` already calls `ref.read(gigProvider.notifier).refresh()` etc. after a successful restore. This provider refresh logic is **not changed**.

### Providers

No provider changes. The restore path does not need new or modified providers.

### Repositories

No repository changes. All DB calls remain inside `DataBackupService`.

### Widgets

No widget changes beyond the `_performImport` error handler in `BandFormScreen`.

---

## 9. Files to Create

| File                                                                    | Justification                                                                                                                                                                                         |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<timestamp>_fix_delete_band_cascade.sql`           | Fixes `delete_band` cascade gap — required to prevent future orphaned rehearsals/block_dates. Timestamp format: `YYYYMMDDHHMMSS`. Use a timestamp after the most recent migration (`20260604000001`). |
| `docs/features/bug-restore-fails-after-band-deletion/ARCHITECT_PLAN.md` | This document — already created.                                                                                                                                                                      |

**No new Dart files.** Changes are localised to existing files.

---

## 10. Files to Modify

| File                                             | What changes                                                    |
| ------------------------------------------------ | --------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | Primary fix. See detailed task breakdown in §14.                |
| `lib/features/bands/band_form_screen.dart`       | `_performImport` catch block only — surface real error message. |

### `data_backup_service.dart` — detailed change summary

1. **`importBandData`**: Before calling `_restoreBandData`, check whether the backup band ID exists in the database via a `maybeSingle` SELECT. Pass the existence result + current user ID into `_restoreBandData`.

2. **`_restoreBandData`**: Split into two paths:
   - **Existing-band path** (band row found): current behaviour unchanged — upsert with original IDs.
   - **Missing-band path** (band row not found — the bug path):
     a. Call `create_band` RPC with `p_name`, `p_avatar_color`, `p_image_url` from the backup → receive `newBandId`.
     b. Remap `band_id` to `newBandId` in: `band_members`, `songs`, `setlists`, `setlist_special_items`, `gigs`, `rehearsals`, `block_dates`.
     c. `setlist_songs`, `gig_dates`, `gig_responses`, `contributor_permissions`: no `band_id` field → no remapping needed.
     d. Filter out the current user's row from `band_members` (avoid `(band_id, user_id)` unique constraint collision with the row just inserted by `create_band`).
     e. For `rehearsals`: generate a fresh UUID for each row using `_generateUuid()` (see below). Build an `oldToNewRehearsalId` map. Remap `parent_rehearsal_id` using this map. Remap `band_id` to `newBandId`.
     f. For `block_dates`: generate a fresh UUID for each row. Remap `band_id` to `newBandId`. (No self-referential FK.)
     g. Proceed with the same `_upsertRows` calls in the same FK-safe order.

3. **`_upsertRows`**: No change to the method itself. All calls remain identical.

4. **`_generateUuid()`**: Add a private static helper using `dart:math` and `dart:typed_data` — no new package required:

   ```dart
   static String _generateUuid() {
     final rng = Random.secure();
     final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
     bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
     bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant bits
     final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
     return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
         '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
         '${hex.substring(20, 32)}';
   }
   ```

   Add `import 'dart:math';` at the top of the file.

5. **Error propagation**: Wrap `PostgrestException` and other uncaught exceptions inside `_restoreBandData` with descriptive `DataBackupException` messages before rethrowing. The existing `DataBackupException` catch in `_performImport` will then surface them correctly.

### `band_form_screen.dart` — detailed change summary

In `_performImport`, change the bare `catch (e)` handler:

```dart
// BEFORE
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
}

// AFTER
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) {
    final msg = e is Exception
        ? e.toString().replaceFirst('Exception: ', '')
        : e.toString();
    _showErrorSnackBar('Restore failed: $msg');
  }
}
```

This ensures that any `DataBackupException` or other exception not already caught propagates a useful message. (The innermost catch in `data_backup_service.dart` should already be wrapping PostgrestExceptions into DataBackupExceptions — this is the fallback for anything that escapes.)

---

## 11. Files Off-Limits

| File                                                                                                                                         | Reason                                                         |
| -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `lib/main.dart`                                                                                                                              | Initialisation order must not change                           |
| `vercel.json`                                                                                                                                | Deployment config — unrelated                                  |
| `lib/features/settings/data_backup_service.dart` — `exportBandData`, `previewBackup`, `_buildBandExport`, `_parseAndValidate`, `_upsertRows` | These methods are correct and must not be modified             |
| `lib/features/bands/band_form_screen.dart` — everything except `_performImport`                                                              | No other changes to this file                                  |
| All other `lib/features/**` files                                                                                                            | Not in scope                                                   |
| All migrations except the new `_fix_delete_band_cascade.sql`                                                                                 | Must not be modified                                           |
| `supabase/functions/**`                                                                                                                      | No edge function changes required                              |
| `pubspec.yaml`                                                                                                                               | No new packages required — use `dart:math` for UUID generation |

---

## 12. System Impact Map

| System                                 | Impact                                                            |
| -------------------------------------- | ----------------------------------------------------------------- |
| Band management (create/edit/delete)   | Affected — `delete_band` RPC updated (cascade fix)                |
| Backup / Restore                       | Affected — primary fix target                                     |
| Gigs                                   | Unaffected                                                        |
| Rehearsals                             | Affected (delete_band cascade; restored correctly with new UUIDs) |
| Setlists / Catalog                     | Unaffected (original IDs used, cascade-deleted by delete_band)    |
| Songs / Catalog                        | Unaffected                                                        |
| Members / RBAC                         | Unaffected (no policy changes; create_band RPC used as-is)        |
| Auth / Session                         | Unaffected                                                        |
| Routing                                | Unaffected                                                        |
| Notifications                          | Unaffected                                                        |
| Calendar / Block-out dates             | Affected (delete_band cascade; restored correctly with new UUIDs) |
| Print templates                        | Unaffected                                                        |
| Venues / Contacts                      | Unaffected                                                        |
| Financial entries                      | Unaffected                                                        |
| Platform (iOS / Android / Web / macOS) | Unaffected — Dart fix is cross-platform                           |

---

## 13. Regression Risk

**MEDIUM**

Rationale:

- The `delete_band` change is low-risk: `CREATE OR REPLACE FUNCTION` with an expanded cascade. The additional DELETEs run inside the same SECURITY DEFINER context. The only regression surface is if something downstream depended on rehearsals or block_dates surviving band deletion — which is incorrect behaviour by definition.
- The Dart restore changes are isolated to `data_backup_service.dart` and the `_performImport` catch block. The existing-band path is unchanged. The new missing-band path only triggers when the band does not exist.
- Auth, routing, initialisation order, and all non-backup features are untouched.
- Risk is MEDIUM (not LOW) because the restore flow now calls `create_band` RPC and manipulates band IDs, which is new logic that must be tested explicitly.

---

## 14. Engineer Task Breakdown

Execute in strict order. Do not skip or reorder.

### Task 1 — Confirm `bands` INSERT RLS policy (required before coding)

Run against production:

```sql
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'bands' AND schemaname = 'public';
```

Record the full output in `ENGINEER_REPORT.md`. This confirms RC-4 and documents the actual INSERT policy so future engineers understand why direct upsert fails for the missing-band case.

### Task 2 — Create migration: fix `delete_band` cascade

Create `supabase/migrations/<timestamp>_fix_delete_band_cascade.sql`.

The migration must:

- `CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)` — same signature, same `SECURITY DEFINER SET search_path = public`
- Add `DELETE FROM public.rehearsals WHERE band_id = band_uuid;` before the existing `DELETE FROM public.bands`
- Add `DELETE FROM public.block_dates WHERE band_id = band_uuid;` before the existing `DELETE FROM public.bands`
- Preserve ALL existing DELETE statements in their current order
- Preserve ALL existing permission checks (`v_is_admin`, `v_band_exists`)
- End with `RETURN TRUE`
- **Do not** change the function's return type, security context, or parameter name

No `GRANT` change needed — the existing grant covers all function replacements.

### Task 3 — Add `_generateUuid` helper to `data_backup_service.dart`

Add `import 'dart:math';` at the top (after existing imports).

Add the private static helper exactly as specified in §10. No other changes in this task.

### Task 4 — Implement the missing-band path in `_restoreBandData`

Refactor `_restoreBandData` to:

1. Accept a new parameter `bool bandExists` (determined before the call — see Task 5).
2. If `bandExists == true`: current body unchanged.
3. If `bandExists == false`:
   a. Call `create_band` RPC: `final newBandId = await supabase.rpc('create_band', params: {'p_name': <name>, 'p_avatar_color': <color>, 'p_image_url': <image>}) as String;`
   b. Extract `name`, `avatar_color`, `image_url` from the backup's `band` map.
   c. Remap `band_id` → `newBandId` in: `band_members`, `songs`, `setlists`, `setlist_special_items`, `gigs`, `rehearsals`, `block_dates`.
   d. Filter `band_members`: remove any row where `user_id == userId`.
   e. Remap rehearsals with fresh UUIDs:
   - Build `Map<String, String> oldToNewRehearsal = {}` by calling `_generateUuid()` for each row.
   - Replace each row's `id` with its new UUID.
   - Replace `parent_rehearsal_id` (if non-null) using `oldToNewRehearsal[oldParentId]`. If the parent UUID is not found in the map (should not happen for well-formed backups), set `parent_rehearsal_id` to `null`.
     f. Remap block_dates with fresh UUIDs: replace each row's `id` with `_generateUuid()`.
     g. Proceed with the same `_upsertRows` calls in the same FK-safe order using the remapped data.

### Task 5 — Update `importBandData` to check band existence and pass to `_restoreBandData`

In `importBandData`, before calling `_restoreBandData`:

```dart
final backupBandId = (backup['band_data']['band'] as Map<String, dynamic>?)?['id'] as String?;
bool bandExists = false;
if (backupBandId != null) {
  final result = await supabase
      .from('bands')
      .select('id')
      .eq('id', backupBandId)
      .maybeSingle();
  bandExists = result != null;
}
```

Pass `bandExists` to `_restoreBandData`.

### Task 6 — Wrap raw exceptions as `DataBackupException` in `_restoreBandData`

Wrap the body of `_restoreBandData` in a try/catch that converts `PostgrestException` to a readable `DataBackupException`:

```dart
} on PostgrestException catch (e) {
  throw DataBackupException('Database error during restore: ${e.message}');
}
```

Import `package:supabase_flutter/supabase_flutter.dart` is already present.

### Task 7 — Fix `_performImport` catch block in `band_form_screen.dart`

Apply the change described in §10 to the `catch (e)` handler.

### Task 8 — `flutter analyze` — zero errors

Run `flutter analyze` and fix any analysis errors introduced by the changes. Do not modify files not listed in this plan to fix pre-existing errors.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (run before `supabase db push`)

All Tier 1 tests are read-only and do not depend on the migrated function.

```sql
-- PRE-DEPLOY TEST 1: Confirm current delete_band does NOT cascade rehearsals
-- Expected: returns the function body and 'rehearsals' is NOT present in DELETE statements
SELECT pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
  LIKE '%DELETE FROM public.rehearsals%' AS cascades_rehearsals;
-- Expected: false

-- PRE-DEPLOY TEST 2: Confirm current delete_band does NOT cascade block_dates
SELECT pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
  LIKE '%DELETE FROM public.block_dates%' AS cascades_block_dates;
-- Expected: false

-- PRE-DEPLOY TEST 3: Confirm create_band RPC signature is unchanged (3 params)
SELECT proname, pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname = 'create_band' AND pronamespace = 'public'::regnamespace;
-- Expected: create_band | p_name text, p_avatar_color text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text

-- PRE-DEPLOY TEST 4: Confirm rehearsals UPDATE RLS checks existing band_id (confirms RC-3 mechanism)
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'rehearsals' AND schemaname = 'public' AND cmd = 'UPDATE';
-- Expected: USING clause references rehearsals.band_id (existing row)

-- PRE-DEPLOY TEST 5: Confirm bands INSERT RLS policy (confirms or refines RC-4)
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'bands' AND schemaname = 'public';
-- Record full output in ENGINEER_REPORT.md
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Confirm delete_band now cascades rehearsals
SELECT pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
  LIKE '%DELETE FROM public.rehearsals%' AS cascades_rehearsals;
-- Expected: true

-- POST-DEPLOY TEST 2: Confirm delete_band now cascades block_dates
SELECT pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
  LIKE '%DELETE FROM public.block_dates%' AS cascades_block_dates;
-- Expected: true

-- POST-DEPLOY TEST 3: Confirm delete_band still cascades original tables
-- All of these must remain true
SELECT
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure) LIKE '%DELETE FROM public.band_members%' AS band_members,
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure) LIKE '%DELETE FROM public.gigs%' AS gigs,
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure) LIKE '%DELETE FROM public.setlists%' AS setlists,
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure) LIKE '%DELETE FROM public.songs%' AS songs;
-- Expected: true, true, true, true

-- POST-DEPLOY TEST 4: Confirm delete_band still has admin check
SELECT pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
  LIKE '%Permission denied: only admins can delete this band%' AS has_admin_guard;
-- Expected: true

-- POST-DEPLOY TEST 5: Functional test — delete band, verify rehearsals/block_dates cleaned up
-- (Requires a test band with rehearsals and block_dates. Replace 'test-band-uuid' with actual ID.)
-- DO NOT run against a real band. Use a test band created for this purpose.
DO $$
DECLARE
  v_band_id UUID;
  v_rehearsal_count INT;
  v_blockout_count INT;
BEGIN
  -- Create a test band via create_band RPC (call from client, or use service role here)
  -- This is a Tier 2 manual integration test — run from app or Supabase dashboard
  -- with a test account that is admin of a test band.
  RAISE NOTICE 'Manual integration test required: see QA Regression Areas §16';
END $$;
```

---

## 16. QA Regression Areas

QA must verify the following test cases:

### Primary — restore after deletion (new band path)

1. Export a band's data (JSON backup file).
2. Delete the band via app Settings → "Delete Band".
3. Create a new band (or use an existing band).
4. Navigate to the new band's Settings → Backup / Restore.
5. Select the backup file and confirm restore.
6. **Expected:** Restore succeeds. A new band is created with the name, avatar colour, and avatar image from the backup. Songs, setlists, gigs, rehearsals, block-out dates, and members (excluding the current user, who is already admin) are all present.
7. **Expected:** Success snackbar is shown, not the generic error toast.
8. **Confirm:** The original deleted band is not re-created with its old ID.

### Regression — restore when source band still exists (existing-band path)

1. Export a band's data.
2. Do NOT delete the band.
3. Navigate to the same band's Settings → Backup / Restore.
4. Select the backup file and confirm restore.
5. **Expected:** Restore succeeds. Band data is replaced with backup content. No new band is created. Behaviour is identical to pre-fix.

### Error surfacing

1. Corrupt the backup JSON (manually remove the `band_data` key).
2. Attempt restore.
3. **Expected:** Specific error message appears (e.g., "Unrecognised backup format. This file is not a BandRoadie backup.") — NOT "Restore failed. Please try again."

### `delete_band` cascade regression

1. Create a test band with at least one rehearsal and one block-out date.
2. Delete the band.
3. **Expected (SQL verification):** No orphaned `rehearsals` or `block_dates` rows remain with the deleted band's ID.

### Multi-band safety

1. User has Band A and Band B.
2. Export Band A's data.
3. Navigate to Band B's Settings → Backup / Restore.
4. Restore Band A's backup into Band B's settings screen.
5. **Expected:** The restored data creates a new band (Band A re-created), NOT a replacement of Band B's data. (Note: the UX may be surprising — this is a UX concern, not a bug in scope. Document in QA report if behaviour is confusing, but do not fail the build over it.)

---

## 17. Rollout / Migration Strategy

1. Run `supabase db push` to deploy `_fix_delete_band_cascade.sql`. Verify post-deploy tests pass.
2. Deploy the Flutter app (web: `./tools/deploy_web.sh`; mobile: standard release build).
3. No data backfill is required. Existing orphaned `rehearsals`/`block_dates` rows (from pre-fix deletions) are handled by the UUID regeneration logic in the Dart code.

---

## 18. Out of Scope

- Changing the backup file schema/format (schema v1 is unchanged).
- Expanding backup/restore to non-admin roles (separate planned feature).
- Cleaning up historically orphaned `rehearsals`/`block_dates` rows from bands deleted before this fix (data is harmless; a separate maintenance migration could clean it up independently).
- UX improvements to the restore confirmation dialog (e.g., clarifying that a new band will be created vs. overwriting an existing band).
- The `gig_dates` cascade: already handled implicitly via PostgreSQL FK `ON DELETE CASCADE` on `gig_dates.gig_id` → no explicit fix needed (confirmed: `delete_band` deletes `gigs`, which cascades to `gig_dates`).
