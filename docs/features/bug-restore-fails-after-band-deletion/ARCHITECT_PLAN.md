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

Restoring from a valid BandRoadie backup file fails with the generic toast
"Restore failed. Please try again." when the source band has been deleted.

**Tony's exact words (verbatim):** "when I back up a band's data, then delete the
band, and then upload the restore file, I get an error 'Restore failed. please try
again.'"

---

## 3. Root Cause

This is the third Architect diagnosis cycle for this bug. All root causes were
independently verified from the current code on disk and from a live database query
in this session — no finding from any prior write-up has been accepted without
independent confirmation. Differences from the prior second-pass hypothesis are
explicitly noted where they exist.

### Verification status for second-pass hypothesis

The second-pass diagnosis identified:

- RC-1: `gig_responses` INSERT RLS requires `user_id = auth.uid()`, failing with
  code `42501` when other members' responses are restored.
- RC-2 (defensive): `block_dates` INSERT RLS has the same pattern.

**My independent investigation confirms RC-1. RC-2 requires qualification (see
below).**

---

### RC-1 — `gig_responses` INSERT RLS blocks other members' rows (HIGH — confirmed)

**File:** `lib/features/settings/data_backup_service.dart`, `_restoreBandData`

**Confirmed from live database query (this session):**

```sql
-- gig_responses INSERT policies queried from pg_policies:
-- Policy: gig_responses_insert_own
-- cmd: INSERT
-- with_check: ((user_id = auth.uid()) AND (EXISTS (
--     SELECT 1 FROM gigs g
--     WHERE g.id = gig_responses.gig_id AND is_band_member(g.band_id))))
--
-- Policy: Band members can create gig responses
-- cmd: INSERT
-- with_check: ((user_id = auth.uid()) AND (EXISTS (
--     SELECT 1 FROM gigs g JOIN band_members bm ON g.band_id = bm.band_id
--     WHERE g.id = gig_responses.gig_id AND bm.user_id = auth.uid()
--     AND bm.status = 'active')))
```

Both active INSERT policies on `gig_responses` require `user_id = auth.uid()`.

**Failure mechanism:**

`delete_band` explicitly deletes all `gig_responses` for the band:

```sql
DELETE FROM public.gig_responses
  WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
```

After deletion, all backup `gig_responses` rows are INSERTs on restore. If the
backup contains `gig_responses` rows with `user_id` values belonging to other band
members (e.g., a contributor who responded to a gig before leaving the band), the
INSERT fails with `PostgrestException` code `42501`, message:
`"new row violates row-level security policy for table \"gig_responses\""`.

**Why Tony's band reached step 10 (not step 2):** Tony's band had only one active
member at export time (Tony himself), so the `band_members` upsert at step 2
contained only Tony's own row, which trivially passes the INSERT policy's
`user_id = auth.uid()` condition. Historical `gig_responses` from users who had
since left the band (but responded before leaving) remained in the export.

**Confidence: HIGH** — confirmed via live DB policy query and by tracing
`delete_band`'s explicit deletion of `gig_responses` rows.

---

### RC-2 — `block_dates` INSERT RLS blocks other members' rows (MEDIUM — defensive,

qualified)

**Confirmed from live database query (this session):**

```sql
-- block_dates INSERT policy:
-- Policy: block_dates_insert_own
-- cmd: INSERT
-- with_check: (is_band_member(band_id) AND (user_id = auth.uid()))
```

The INSERT policy on `block_dates` does require `user_id = auth.uid()`.

**QUALIFICATION (differs from second-pass hypothesis):** Unlike `gig_responses`,
`delete_band` does **NOT** delete `block_dates`. After `delete_band`, the
`block_dates` rows for the band remain orphaned in the database. On restore, when
`_upsertRows('block_dates', ...)` runs with `onConflict: 'id'`, all backup rows that
still exist in the database go through the **UPDATE** path (not INSERT). The
`block_dates` UPDATE policy allows admins to update any member's rows:

```sql
-- block_dates_update_own_or_admin
-- USING: (((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id))
```

Since the restoring user is admin, UPDATE passes for all rows regardless of
`user_id`. **In Tony's specific scenario, `block_dates` does not cause the failure.**

The INSERT policy _does_ apply if a `block_dates` row in the backup was manually
deleted from the database before the restore (so the upsert takes the INSERT path).
This is an unusual edge case. A defensive filter is recommended to prevent a future
`42501` in this edge case but is not the cause of Tony's reported failure.

**Confidence: MEDIUM** — the INSERT policy is confirmed; whether it causes a failure
depends on whether any `block_dates` row takes the INSERT path. In Tony's scenario
it does not.

---

### RC-3 — Generic `catch (e)` in `_performImport` swallows the real exception (HIGH

— confirmed)

**File:** `lib/features/bands/band_form_screen.dart`, `_performImport` (line 956)

**Current code (read directly from disk in this session):**

```dart
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
}
```

Any exception that is not a `DataBackupException` — including `PostgrestException`
with a specific code (`42501`) and message — is converted to the generic toast. The
real error is only visible in debug logs. This is the direct cause of Tony seeing
"Restore failed. Please try again." instead of a specific error.

**Confidence: HIGH** — confirmed by reading the current file on disk.

---

### Additional finding: potential latent failure for multi-member bands

During this investigation, `is_band_member` was confirmed as `STABLE SECURITY
DEFINER`:

```sql
CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER ...
```

The `band_members` INSERT policy is:

```sql
WITH CHECK: (is_band_member(band_id) OR (user_id = auth.uid()))
```

Because `is_band_member` is `STABLE`, it evaluates with the snapshot from the
**start of the statement** — it cannot see rows inserted earlier in the same
multi-row upsert batch. This means: when restoring a band backup that contains
**multiple active members** (not just the restoring admin), other members' rows in
the `band_members` batch upsert would fail with `42501` at step 2, not step 10.

**This is a separate failure mode, not Tony's reported failure.** It would affect any
user attempting to restore a backup of a band they shared with other active members
at export time. It is flagged here as a scope question for the Manager — see §18.

---

## 4. Reference Docs Consulted

No `docs/reference/` folder specific to backup/restore exists. The following files
were read or queried during this diagnosis:

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/architecture/database_schema.md`
- `lib/features/settings/data_backup_service.dart` (full, 353 lines)
- `lib/features/bands/band_form_screen.dart` (lines 900–980)
- `supabase/migrations/20260302000000_band_user_roles.sql` (lines 323–375,
  `delete_band` function)
- `supabase/migrations/073_fix_gig_responses_unique_constraint.sql` (full)
- Live DB query: `pg_policies` for `bands`, `gig_responses`, `block_dates`
  (INSERT, SELECT, UPDATE, DELETE policies — queried this session)
- Live DB query: `pg_policies` for `band_members`, `songs`, `setlists`, `gigs`,
  `rehearsals` (INSERT policies — queried this session)
- Live DB query: `pg_get_functiondef('is_band_member')` — queried this session

---

## 5. Existing System Analysis

### Call chain for restore

```
BandFormScreen._showBackupRestoreSheet()       [admin-only gate]
  └─> _showImportDialog()
        └─> _performImport(jsonContent, band.id)
              └─> DataBackupService.importBandData(jsonContent, targetBandId)
                    └─> _restoreBandData(entry, targetBandId, userId)
                          │  NOTE: targetBandId and userId are accepted
                          │  but NEITHER is currently used. All backup
                          │  rows are upserted with their original IDs.
                          │
                          ├─> _upsertRows('bands',        [backup.band])          step 1
                          ├─> _upsertRows('band_members', [backup.band_members])  step 2
                          ├─> _upsertRows('contributor_permissions', [...])       step 3
                          ├─> _upsertRows('songs',        [...])                  step 4
                          ├─> _upsertRows('setlists',     [...])                  step 5
                          ├─> _upsertRows('setlist_special_items', [...])         step 6
                          ├─> _upsertRows('setlist_songs', [...])                 step 7
                          ├─> _upsertRows('gigs',         [...])                  step 8
                          ├─> _upsertRows('gig_dates',    [...])                  step 9
                          ├─> _upsertRows('gig_responses',[...])                  step 10 ← FAILS (RC-1)
                          ├─> _upsertRows('rehearsals',   [...])                  step 11
                          └─> _upsertRows('block_dates',  [...])                  step 12
```

### What `delete_band` removes vs. what remains

| Table              | Deleted by `delete_band`       | Remains post-deletion         |
| ------------------ | ------------------------------ | ----------------------------- |
| `bands`            | ✓                              | —                             |
| `band_members`     | ✓                              | —                             |
| `band_invitations` | ✓                              | —                             |
| `gig_responses`    | ✓ (explicit DELETE via gig_id) | —                             |
| `gigs`             | ✓                              | —                             |
| `setlist_songs`    | ✓                              | —                             |
| `setlists`         | ✓                              | —                             |
| `songs`            | ✓                              | —                             |
| `rehearsals`       | —                              | ✓ orphaned with old `band_id` |
| `block_dates`      | —                              | ✓ orphaned with old `band_id` |

### Post-deletion restore: INSERT vs UPDATE for each step

| Step | Table                     | Op after delete_band | Why                                 |
| ---- | ------------------------- | -------------------- | ----------------------------------- |
| 1    | `bands`                   | INSERT               | Deleted by `delete_band`            |
| 2    | `band_members`            | INSERT               | Deleted by `delete_band`            |
| 3    | `contributor_permissions` | INSERT               | FK on `band_member_id` was deleted  |
| 4    | `songs`                   | INSERT               | Deleted by `delete_band`            |
| 5    | `setlists`                | INSERT               | Deleted by `delete_band`            |
| 6    | `setlist_special_items`   | INSERT or UPDATE     | Depends on FK cascade from setlists |
| 7    | `setlist_songs`           | INSERT               | Deleted when setlists deleted       |
| 8    | `gigs`                    | INSERT               | Deleted by `delete_band`            |
| 9    | `gig_dates`               | INSERT               | Deleted via FK CASCADE from `gigs`  |
| 10   | `gig_responses`           | **INSERT**           | Deleted by `delete_band` explicitly |
| 11   | `rehearsals`              | UPDATE               | NOT deleted; rows still exist       |
| 12   | `block_dates`             | UPDATE               | NOT deleted; rows still exist       |

### Why the failure chain ends at step 10

1. Step 1 (`bands` INSERT): `bands_insert_authenticated` / `bands: insert own` policies
   both use `WITH CHECK: (created_by = auth.uid())`. Tony's backup has
   `band.created_by = Tony's user_id` → **passes**.

2. Step 2 (`band_members` INSERT): Policy `WITH CHECK: (is_band_member(band_id) OR
(user_id = auth.uid()))`. For Tony's row: `user_id = auth.uid()` → passes. In
   Tony's case, his band had only his own row in `band_members` at export time →
   **passes**.

3. Steps 3–9: Various checks using `is_band_member(band_id)` → Tony is now a member
   (after step 2) → **pass**.

4. Step 10 (`gig_responses` INSERT): Both active INSERT policies require
   `user_id = auth.uid()`. Backup contains `gig_responses` rows from other users
   (e.g., ex-members who responded to gigs before leaving). Those rows have
   `user_id ≠ auth.uid()` → **`PostgrestException` code `42501` thrown**.

5. `_upsertRows` does not catch the exception → propagates to `importBandData` →
   propagates to `_performImport`'s `catch (e)` block → converted to generic toast
   (RC-3).

---

## 6. Proposed Solution

### Design decision: filter, do not drop

The correct fix for `gig_responses` is to filter the backup's `gig_responses` list to
only rows where `user_id == userId` (the restoring admin's own responses) before
calling `_upsertRows`. Other members' historical responses cannot be restored by the
admin — they are owned by those users. The affected rows are silently skipped; this
is correct behaviour because:

1. The RLS policy reflects a deliberate intent: users manage their own RSVP state.
2. If a band is re-created, other members can re-join and re-submit their own responses.
3. The backup exists primarily to restore the admin's view of the data, not to
   impersonate other users.

The same filter is applied defensively to `block_dates` for the edge case where a
row in the backup takes the INSERT path (e.g., the row was manually deleted between
export and restore).

### Design decision: filter, not wrap

The filter is applied inside `_restoreBandData` directly before the affected
`_upsertRows` calls. `_upsertRows` itself is not changed. `importBandData` is not
changed.

### Design decision: surface errors via service layer

Rather than modifying `_performImport`'s bare `catch (e)` in `band_form_screen.dart`
to pattern-match exception types, `_restoreBandData` wraps any `PostgrestException`
as a `DataBackupException` before it propagates. The existing
`on DataBackupException catch (e)` in `_performImport` then handles it correctly.
The bare `catch (e)` in `_performImport` is also updated as a belt-and-suspenders
fallback to surface the error message rather than showing a generic string.

### What does NOT change

- `_upsertRows` — unchanged
- `importBandData` — unchanged
- `previewBackup`, `exportBandData`, `_buildBandExport`, `_parseAndValidate` — unchanged
- The restore flow for the "band still exists" path — no behavioural change for
  normal (non-deletion) restores
- `band_members` upsert — unchanged (see §18 for the latent multi-member concern)
- No migrations, no database changes, no new RPCs, no new packages
- No new Dart files

---

## 7. Database Impact

**No database changes in this fix.**

All three root causes are fixed entirely in Dart:

| Object            | Impact                         |
| ----------------- | ------------------------------ |
| RLS policies      | Unaffected — no policy changes |
| `delete_band` RPC | Unaffected                     |
| `create_band` RPC | Not called                     |
| Migrations        | None required                  |
| Triggers          | Unaffected                     |

The orphaned `rehearsals` and `block_dates` rows (surviving `delete_band`) are an
existing data integrity concern noted in the prior architecture doc but are **out of
scope for this fix** per the problem statement.

---

## 8. Flutter Architecture Changes

### State management

`_performImport` in `BandFormScreen` already calls `ref.read(...notifier).refresh()`
and `ref.invalidate(bandFullStateProvider)` after a successful restore. This provider
refresh logic is **not changed**.

### Providers

No provider changes.

### Repositories

No repository changes. All DB interaction remains inside `DataBackupService`.

### Widgets

No widget changes beyond the `_performImport` fallback catch block in
`BandFormScreen`.

---

## 9. Files to Create

**None.** All changes are localised to existing files. No new files required.

---

## 10. Files to Modify

| File                                             | What changes                                                                                                                                                     |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | Filter `gig_responses` and (defensively) `block_dates` to own-user rows before upsert. Wrap `PostgrestException` in `_restoreBandData` as `DataBackupException`. |
| `lib/features/bands/band_form_screen.dart`       | Improve fallback `catch (e)` in `_performImport` to surface real error message.                                                                                  |

### `data_backup_service.dart` — detailed change

In `_restoreBandData`, before step 10, filter `gig_responses`:

```dart
// 10. Gig responses — filter to own-user rows only.
// The gig_responses INSERT RLS policy (gig_responses_insert_own) requires
// user_id = auth.uid(). Other members' responses cannot be inserted by the
// restoring admin and must be skipped.
final allGigResponses = entry['gig_responses'] as List? ?? [];
final ownGigResponses = allGigResponses
    .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
    .toList();
await _upsertRows('gig_responses', ownGigResponses);
```

Before step 12, filter `block_dates`:

```dart
// 12. Block-out dates — filter to own-user rows only (defensive).
// block_dates_insert_own requires user_id = auth.uid(). In the normal
// post-deletion restore scenario these rows still exist and take the UPDATE
// path (admins can update any member's rows). The filter guards the edge case
// where a row takes the INSERT path (e.g., manually deleted between export
// and restore).
final allBlockDates = entry['block_dates'] as List? ?? [];
final ownBlockDates = allBlockDates
    .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
    .toList();
await _upsertRows('block_dates', ownBlockDates);
```

Wrap the `_restoreBandData` body in a try/catch for `PostgrestException`:

```dart
} on PostgrestException catch (e) {
  throw DataBackupException('Database error during restore: ${e.message}');
}
```

Add import `package:supabase_flutter/supabase_flutter.dart` — already present.

### `band_form_screen.dart` — detailed change

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
    final msg = e.toString().replaceFirst('Exception: ', '');
    _showErrorSnackBar('Restore failed: $msg');
  }
}
```

This is a belt-and-suspenders fallback; the primary error path is `_restoreBandData`
wrapping `PostgrestException` → `DataBackupException` → caught by the existing
`on DataBackupException catch (e)` handler above it.

---

## 11. Files Off-Limits

| File                                                                                                                                         | Reason                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `lib/main.dart`                                                                                                                              | Initialisation order must not change               |
| `lib/features/settings/data_backup_service.dart` — `exportBandData`, `previewBackup`, `_buildBandExport`, `_parseAndValidate`, `_upsertRows` | These methods are correct and must not be modified |
| `lib/features/bands/band_form_screen.dart` — everything except `_performImport`                                                              | No other changes to this file                      |
| All `supabase/migrations/**`                                                                                                                 | No database changes required                       |
| `supabase/functions/**`                                                                                                                      | No edge function changes required                  |
| `pubspec.yaml`                                                                                                                               | No new packages required                           |
| All other `lib/features/**` files                                                                                                            | Not in scope                                       |

---

## 12. System Impact Map

| System                                 | Impact                                                                      |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Band management (create/edit/delete)   | Unaffected                                                                  |
| Backup / Restore                       | Affected — primary fix target                                               |
| Gigs                                   | Unaffected                                                                  |
| Rehearsals                             | Unaffected                                                                  |
| Setlists / Catalog                     | Unaffected                                                                  |
| Songs / Catalog                        | Unaffected                                                                  |
| Members / RBAC                         | Unaffected                                                                  |
| Auth / Session                         | Unaffected                                                                  |
| Routing                                | Unaffected                                                                  |
| Notifications                          | Unaffected                                                                  |
| Calendar / Block-out dates             | Affected (defensive filter on restore; no behaviour change for normal path) |
| Print templates                        | Unaffected                                                                  |
| Venues / Contacts                      | Unaffected                                                                  |
| Financial entries                      | Unaffected                                                                  |
| Platform (iOS / Android / Web / macOS) | Unaffected — Dart fix is cross-platform                                     |

---

## 13. Regression Risk

**LOW**

Rationale:

- The change is confined to `_restoreBandData` (adding two list filters) and the
  `_performImport` fallback catch. The method body is otherwise unchanged.
- The filter operates on in-memory lists before calling `_upsertRows`. `_upsertRows`
  itself is unchanged.
- The "band still exists" restore path is completely unaffected. The filters apply
  only when `gig_responses` or `block_dates` contain rows with other users' `user_id`
  values — which is benign for the existing-band path (those rows would have been
  UPDATEs owned by the original users and would succeed; filtering them skips an
  update that was optional anyway since the admin didn't create those rows).
- Auth, routing, initialisation order, and all non-backup features are untouched.
- No database migrations.

---

## 14. Engineer Task Breakdown

Execute in strict order. Do not skip or reorder. Stop and report if blocked.

---

### Task 1 — Filter `gig_responses` to own-user rows in `_restoreBandData`

In `lib/features/settings/data_backup_service.dart`, locate step 10 in
`_restoreBandData`:

```dart
// 10. Gig responses
await _upsertRows('gig_responses', entry['gig_responses'] as List? ?? []);
```

Replace with:

```dart
// 10. Gig responses — filter to own-user rows only.
// INSERT RLS (gig_responses_insert_own) requires user_id = auth.uid().
// Other members' responses cannot be inserted by the restoring admin.
final allGigResponses = entry['gig_responses'] as List? ?? [];
final ownGigResponses = allGigResponses
    .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
    .toList();
await _upsertRows('gig_responses', ownGigResponses);
```

**STOP condition:** If `_restoreBandData`'s signature or body differs materially
from the version read in this session (reproduced below for reference), stop and
report the discrepancy.

**Reference — current `_restoreBandData` signature and step 10 (read this session):**

```dart
static Future<void> _restoreBandData(
  Map<String, dynamic> entry,
  String targetBandId,
  String userId,
) async {
  // ...
  // 10. Gig responses
  await _upsertRows('gig_responses', entry['gig_responses'] as List? ?? []);
  // ...
}
```

---

### Task 2 — Filter `block_dates` to own-user rows in `_restoreBandData` (defensive)

In the same method, locate step 12:

```dart
// 12. Block-out dates
await _upsertRows(
  'block_dates',
  entry['block_dates'] as List? ?? [],
);
```

Replace with:

```dart
// 12. Block-out dates — filter to own-user rows only (defensive).
// block_dates_insert_own requires user_id = auth.uid() on INSERT path.
// Rows still in the DB take the UPDATE path (admins can update all); this
// filter guards the edge case where a row was deleted after the export.
final allBlockDates = entry['block_dates'] as List? ?? [];
final ownBlockDates = allBlockDates
    .where((r) => (r as Map<String, dynamic>)['user_id'] == userId)
    .toList();
await _upsertRows('block_dates', ownBlockDates);
```

---

### Task 3 — Wrap `PostgrestException` in `_restoreBandData`

Wrap the entire body of `_restoreBandData` in a try/catch that converts
`PostgrestException` to a typed `DataBackupException`. Structure:

```dart
static Future<void> _restoreBandData(
  Map<String, dynamic> entry,
  String targetBandId,
  String userId,
) async {
  try {
    // step 1 … step 12 (unchanged except Tasks 1 & 2 filters)
  } on PostgrestException catch (e) {
    throw DataBackupException('Database error during restore: ${e.message}');
  }
}
```

`PostgrestException` is already available via the existing
`package:supabase_flutter/supabase_flutter.dart` import. Do not add a new import.

---

### Task 4 — Fix `_performImport` fallback catch in `band_form_screen.dart`

In `lib/features/bands/band_form_screen.dart`, locate the `catch (e)` block inside
`_performImport` (line ~956):

```dart
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
}
```

Replace with:

```dart
} catch (e) {
  debugPrint('[Restore] Unexpected error: $e');
  if (mounted) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    _showErrorSnackBar('Restore failed: $msg');
  }
}
```

Do not modify any other part of `_performImport` or any other method in this file.

**STOP condition:** If the `catch (e)` block text does not match exactly, stop and
report the actual text found.

---

### Task 5 — `flutter analyze` — zero new errors

Run `flutter analyze`. Fix any analysis errors introduced by Tasks 1–4. Do not
modify files not listed in this plan to fix pre-existing errors.

**STOP condition:** If `flutter analyze` reports errors in files not touched by this
plan, document them in `ENGINEER_REPORT.md` and do not attempt to fix them.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (no schema changes required — database read-only)

```sql
-- PRE-DEPLOY TEST 1: Confirm gig_responses INSERT RLS requires user_id = auth.uid()
-- Expected: at least one policy row where with_check contains 'user_id = auth.uid()'
SELECT policyname, cmd, with_check
FROM pg_policies
WHERE tablename = 'gig_responses'
  AND schemaname = 'public'
  AND cmd = 'INSERT';
-- Expected: gig_responses_insert_own with with_check containing '(user_id = auth.uid())'

-- PRE-DEPLOY TEST 2: Confirm block_dates INSERT RLS requires user_id = auth.uid()
SELECT policyname, cmd, with_check
FROM pg_policies
WHERE tablename = 'block_dates'
  AND schemaname = 'public'
  AND cmd = 'INSERT';
-- Expected: block_dates_insert_own with with_check containing 'user_id = auth.uid()'

-- PRE-DEPLOY TEST 3: Confirm delete_band explicitly deletes gig_responses (not block_dates)
-- Expected: true for gig_responses, false for block_dates, false for rehearsals
SELECT
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
    LIKE '%DELETE FROM public.gig_responses%' AS deletes_gig_responses,
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
    LIKE '%DELETE FROM public.block_dates%' AS deletes_block_dates,
  pg_get_functiondef('public.delete_band(uuid)'::regprocedure)
    LIKE '%DELETE FROM public.rehearsals%' AS deletes_rehearsals;
-- Expected: true, false, false

-- PRE-DEPLOY TEST 4: Confirm is_band_member is STABLE (intra-statement insert not visible)
SELECT proname, provolatile
FROM pg_proc
WHERE proname = 'is_band_member'
  AND pronamespace = 'public'::regnamespace;
-- Expected: provolatile = 's' (STABLE)

-- PRE-DEPLOY TEST 5: Confirm bands INSERT policy only checks created_by (not band membership)
-- Expected: no 'band_members' reference in bands INSERT with_check
SELECT policyname, cmd, with_check
FROM pg_policies
WHERE tablename = 'bands'
  AND schemaname = 'public'
  AND cmd = 'INSERT';
-- Expected: with_check = '(created_by = auth.uid())' — no band_members join
```

### Tier 2 — Post-deployment (Flutter app changes deployed — manual app testing)

These tests require running the app as Tony's test account with a band that has
multiple members' `gig_responses` in its export history.

```
POST-DEPLOY TEST 1: Primary — restore after deletion (the reported failure path)
  1. Create a test band with at least one other member.
  2. Have that other member (or simulate via admin) confirm attendance for a gig
     (creates a gig_response with their user_id).
  3. Remove the other member from the band (they leave or are removed).
  4. Export the band data as admin (backup now contains gig_responses with
     other_member.user_id).
  5. Delete the band (Settings → Delete Band).
  6. Create a new band (or use existing band) to navigate to band settings.
  7. Open Settings → Backup / Restore for that band.
  8. Select the backup file and confirm restore.
  Expected:
    - Restore SUCCEEDS. Success snackbar shown.
    - Band data is restored: songs, setlists, gigs, rehearsals, block-out dates.
    - Only the restoring admin's own gig_responses are restored.
    - The other member's gig_response is NOT restored (intentional — they must
      re-submit their own response).
    - No error toast shown.

POST-DEPLOY TEST 2: Regression — restore when source band still exists
  1. Export a band that has other members' gig_responses.
  2. Do NOT delete the band.
  3. Navigate to Settings → Backup / Restore for the same band.
  4. Select the backup file and confirm restore.
  Expected:
    - Restore SUCCEEDS. Behaviour identical to pre-fix.
    - Only own gig_responses are upserted (pre-existing other members' responses
      in the DB are not overwritten, which is correct behaviour — no change from
      pre-fix because INSERT would have failed anyway for other members' rows on
      the existing-band path too).

POST-DEPLOY TEST 3: Error surfacing
  1. Corrupt the backup JSON (manually remove the 'band_data' key).
  2. Attempt restore.
  Expected: Specific error message shown:
    "Unrecognised backup format. This file is not a BandRoadie backup."
    NOT "Restore failed. Please try again."

POST-DEPLOY TEST 4: Verify Supabase row counts post-restore (SQL)
  After POST-DEPLOY TEST 1 completes successfully, confirm expected row counts.
  Replace 'restored-band-uuid' with the band ID from the restored backup.
  -- Should show 1 member (the restoring admin):
  SELECT COUNT(*) FROM band_members WHERE band_id = 'restored-band-uuid';
  -- Should show only the admin's own responses (not other_member's):
  SELECT user_id, COUNT(*) FROM gig_responses
    WHERE gig_id IN (SELECT id FROM gigs WHERE band_id = 'restored-band-uuid')
    GROUP BY user_id;
  -- Expected: only one user_id (the restoring admin)
```

---

## 16. QA Regression Areas

QA must verify the following test cases:

### Primary — restore after deletion with multi-user gig_responses

1. Setup: band with gig_responses from multiple users (see POST-DEPLOY TEST 1 above).
2. Delete band, restore from backup.
3. **Expected:** Restore succeeds. Only admin's own responses are in the restored
   data. No error toast.
4. **Confirm:** The `gig_responses` for other historical members are absent from the
   restored DB (not an error — expected and correct per RLS design).

### Regression — restore when source band still exists

1. Export, do not delete, restore.
2. **Expected:** Restore succeeds. Behaviour matches pre-fix.

### Error surfacing

1. Use malformed backup file.
2. **Expected:** Specific error shown, NOT "Restore failed. Please try again."

### Block-out dates defensive path

1. If possible, manually delete one `block_dates` row for another member from the DB
   before restoring, then restore.
2. **Expected:** Restore succeeds. The deleted row is not re-inserted (filtered out).
   Own block-out dates are restored normally.

### Multi-band safety

1. Export Band A data.
2. Navigate to Band B Settings → Restore.
3. Restore Band A's backup into Band B's settings screen.
4. **Expected:** Document result in QA report. (This is a UX concern; behaviour may
   be surprising. Not a blocking issue for this fix but should be noted.)

---

## 17. Rollout / Migration Strategy

1. No database migration required.
2. Deploy the Flutter app (web: `./tools/deploy_web.sh`; mobile: standard release).
3. No data backfill needed. The filter only affects in-memory data during the restore
   operation; no existing DB rows are changed.

---

## 18. Out of Scope

### Multi-member `band_members` restore latent issue (scope question for Manager)

During this investigation the following was found: `is_band_member` is `STABLE`, and
the `band_members` INSERT RLS policy is:

```sql
WITH CHECK: (is_band_member(band_id) OR (user_id = auth.uid()))
```

For a user restoring a backup of a band that had **multiple active members** at
export time, the `band_members` batch upsert (step 2) could fail with `42501` for
other members' rows. `is_band_member` being STABLE means it uses the command-start
snapshot and cannot see the admin's own row (just inserted) — so other members' rows
would fail the `(is_band_member(band_id) OR user_id = auth.uid())` check.

This was NOT the failure Tony reported (his band had a single active member at export
time). However, it would affect any admin restoring a band backup that includes
multiple active `band_members` rows. Addressing it cleanly requires a more
significant change (e.g., issuing the `band_members` upsert in separate calls, or
the admin's own row first as a separate call, or rethinking the RLS policy). **This
is flagged for the Manager to determine whether it should be a follow-on bug or
addressed in a second Engineer task.**

### Other explicitly out-of-scope items

- Changing the backup file schema/format (schema v1 is unchanged)
- Expanding backup/restore to non-admin roles
- Cleaning up orphaned `rehearsals`/`block_dates` rows from deleted bands
- Fixing `delete_band` to cascade `rehearsals`/`block_dates`
- The `create_band` / band re-creation approach (cycle 1) — not required to fix the
  confirmed failure
- UUID regeneration for `rehearsals` or `block_dates` (cycle 1) — not required
- UX improvements to the restore confirmation dialog
