# ARCHITECT_PLAN.md

**Feature Slug:** `bug/restore-duplicate-catalog-setlist`
**Type:** bug
**Date:** 2026-06-07
**Status:** Ready for Engineer — REVISED (post-implementation re-diagnosis 2026-06-07)

---

## 1. Feature Slug

`bug/restore-duplicate-catalog-setlist`

Branch: `bug/restore-duplicate-catalog-setlist`
Docs path: `docs/features/bug-restore-duplicate-catalog-setlist/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

When restoring a backup for a previously-deleted band (the "missing-band path" in
`_restoreBandData`), the restore fails with:

> "Database error during restore: duplicate key value violates unique constraint
> 'setlists_one_catalog_per_band'"

The user receives a raw database error. The restore does not complete. The bug is
triggered from both call sites:

- `BandFormScreen._performImport` (band settings)
- `NoBandShell._performRestore` (welcome-screen entry point — where it was first observed)

---

## 3. Root Cause

> **REVISION NOTE (2026-06-07 re-diagnosis):** The initial implementation of this fix
> was confirmed deployed (Task 3 as specified), but Tony re-tested with the same backup
> file and got the identical error. This section supersedes the original §3. The initial
> mechanism diagnosis was correct but the fix was incomplete — it only handled the
> single-catalog case. The sections below explain both the original mechanism and the
> residual failure mode.

---

### RC-1 (Confirmed / Incomplete fix) — `create_band` fires `auto_create_catalog_for_band()`, which pre-creates a catalog setlist that then conflicts with backup catalog setlist upsert

**File:** `lib/features/settings/data_backup_service.dart`, `_restoreBandData`,
missing-band path (both the original upsert path and the implemented remap path).

**Original mechanism (still correct):**

1. `create_band` → INSERT into `public.bands` → fires `auto_create_catalog_for_band()` trigger → `ensure_catalog_setlist(newBandId)` → INSERT into `setlists` creates `(id = trigger-catalog-uuid, band_id = newBandId, is_catalog = true)`.
2. The backup also contains `(id = backup-catalog-uuid, is_catalog = true)`. Upsert calls `ON CONFLICT (id)`: `backup-catalog-uuid ≠ trigger-catalog-uuid` → INSERT path → violates `setlists_one_catalog_per_band` partial unique index `(band_id) WHERE is_catalog = true`.

**Why the implemented fix partially resolves this but fails for the specific backup:**

The implemented fix (Task 3 of original plan) adds:

```dart
final backupCatalogId = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .firstOrNull;                           // ← only the FIRST is_catalog row

final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null && backupCatalogId != null) {
  setlistIdRemap[backupCatalogId] = triggerCatalogId;  // ← single entry
}
```

This works when the backup has **exactly one** `is_catalog: true` row: `backup-catalog-uuid` is remapped to `trigger-catalog-uuid`, the upsert hits the UPDATE path, no INSERT, no violation. ✓

This fails when the backup has **two or more** `is_catalog: true` rows.

---

### RC-2 (HIGH — primary, confirmed) — Backup contains more than one `is_catalog: true` setlist row; `firstOrNull` only remaps the first

**File:** `lib/features/settings/data_backup_service.dart`, `_restoreBandData`,
missing-band path, `setlistIdRemap` construction.

**Mechanism:**

The backup JSON contains two `is_catalog: true` rows: `backup-catalog-A` (first) and
`backup-catalog-B` (second). This is a pre-existing data-integrity defect in the source
band — it predates the `setlists_one_catalog_per_band` constraint. The constraint was
added by `068_ensure_catalog_setlist_rpc_standalone.sql` after the band was created
and prevents future duplicates but does not retroactively clean up existing ones.

With the implemented fix:

1. `triggerCatalogId = trigger-catalog-uuid` (SELECT succeeds — the `setlists` SELECT
   RLS policy is a simple band-membership check, confirmed from
   `20260302000000_band_user_roles.sql` Phase 5: "Contributors get SELECT only (via
   existing/unchanged SELECT policy)". No role filter on SELECT → the newly-created
   admin can read the trigger row immediately).
2. `backupCatalogId = backup-catalog-A` (`firstOrNull` picks the first match).
3. `setlistIdRemap = {backup-catalog-A → trigger-catalog-uuid}`.
4. Setlists upsert — batch contains both rows:
   - `backup-catalog-A` → remapped to `trigger-catalog-uuid` → `ON CONFLICT (id) DO UPDATE` → **UPDATE** the trigger row. Now the DB has `(id = trigger-catalog-uuid, band_id = newBandId, is_catalog = true)`. ✓
   - `backup-catalog-B` → NOT in `setlistIdRemap` → retains original UUID → INSERT with `band_id = newBandId, is_catalog = true` → **conflicts with `(band_id = newBandId, is_catalog = true)` row** that was just updated → **constraint violation** → identical error to the pre-fix run.

**Evidence for RC-2 being the cause:**

- The error message is character-for-character identical before and after the fix. The
  fix visibly works (no regression on normal backups), but Tony's specific backup
  triggers a case the fix doesn't handle.
- The `setlists` SELECT policy is not RLS-blocking (membership check only; the
  `triggerCatalogId` SELECT is confirmed to work).
- The mechanism matches exactly: fix handles first catalog, second catalog is the new
  conflicting INSERT.

**Verification (run against the actual backup file before coding):**

```bash
cat <backup_file>.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
setlists = data['band_data']['setlists']
print('Total setlists:', len(setlists))
catalogs = [s for s in setlists if s.get('is_catalog') == True]
print('is_catalog=true count:', len(catalogs))
for c in catalogs:
    print('  id:', c['id'], '| name:', c.get('name'))
"
# Expected for Tony's backup: count = 2 (or more)
```

---

### RC-3 (MEDIUM — defensive, secondary) — `triggerCatalogId` null in environments where trigger fires but SELECT is blocked

If `ensure_catalog_setlist` is SECURITY INVOKER and `auth.uid()` is unavailable in the
trigger's execution context (edge deployment/pooling scenario), the catalog setlist
INSERT may fail silently (common `EXCEPTION WHEN OTHERS THEN NULL` guard pattern in
trigger functions), leaving no trigger catalog row. In that case `triggerCatalogId =
null`, `setlistIdRemap = {}`, backup's first catalog inserts without conflict (no
trigger row to collide with) — but backup's second catalog INSERT conflicts with the
first. The deduplication fix (see §6) handles this case without needing `triggerCatalogId`.

RC-3 does not explain Tony's observed failure (it requires a two-catalog backup
regardless), but the fix must handle it defensively.

---

### Why the existing-band path is unaffected

In the existing-band path, all catalog UUIDs in the backup match existing DB rows
regardless of how many there are — upsert hits `ON CONFLICT (id) → UPDATE`. No INSERT.
Unaffected.

### Why band deletion does not leave orphaned catalog setlists

`delete_band` (as updated by `20260607000000_fix_delete_band_cascade.sql`) includes
`DELETE FROM public.setlists WHERE band_id = band_uuid`. The constraint violation does
not arise from orphaned setlists — it arises from the trigger creating a new catalog on
`create_band`, combined with the backup having duplicate catalog rows.

### Why `setlist_songs` remapping must cover ALL catalog UUIDs

If the backup has two catalog setlists (`backup-catalog-A`, `backup-catalog-B`), songs
may be in `setlist_songs` with `setlist_id` pointing to either. After the fix, both
catalogs are merged into the single trigger catalog row. All `setlist_songs` rows with
`setlist_id` in `{backup-catalog-A, backup-catalog-B}` must be remapped to
`trigger-catalog-uuid`. With the current single-entry `setlistIdRemap`, songs belonging
to `backup-catalog-B` are left pointing to `backup-catalog-B` which no longer exists
after deduplication → FK violation.

---

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/architecture/database_schema.md`
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` (migration history — `068_ensure_catalog_setlist_rpc_standalone.sql` reference)
- `lib/features/settings/data_backup_service.dart` (full — including the implemented remap fix)
- `lib/features/bands/band_form_screen.dart` (lines 930–970, `_performImport`)
- `lib/features/shell/no_band_shell.dart` (lines 390–420, `_performRestore`)
- `supabase/migrations/20260302000000_band_user_roles.sql` — Phase 5 (setlists RLS policies confirmed: SELECT is existing/unchanged membership check, no role filter)
- `supabase/migrations/20260607000000_fix_delete_band_cascade.sql` (`delete_band` updated)
- `supabase/migrations/087_fix_create_band_no_profile.sql` (`create_band` RPC — full)
- `supabase/migrations/20260221000000_setlist_special_items.sql` (schema — no `setlist_id` on `setlist_special_items`)
- `docs/features/bug-restore-fails-after-band-deletion/ARCHITECT_PLAN.md` (prior restore fix context)
- `docs/features/feature-restore-backup-from-welcome-screen/ARCHITECT_PLAN.md` (welcome-screen context)
- `docs/features/backup-member-role-access/ARCHITECT_PLAN.md` (confirmed no setlists SELECT policy change)

No `docs/reference/` folder specific to backup/restore exists.

---

## 5. Existing System Analysis

### Current call chain (after first implementation — the failing state)

```
DataBackupService._restoreBandData(entry, null, userId, bandExists=false)
  ├─> supabase.rpc('create_band', ...)       → newBandId
  │     └─> TRIGGER: auto_create_catalog_for_band()
  │           └─> INSERT INTO setlists (id=trigger-uuid, band_id=newBandId, is_catalog=true)
  │
  ├─> SELECT setlists WHERE band_id=newBandId AND is_catalog=true → triggerCatalogId ✓
  │
  ├─> backupCatalogId = rawSetlists.where(is_catalog==true).firstOrNull
  │     → backup-catalog-A   (first only — backup-catalog-B MISSED)
  │
  ├─> setlistIdRemap = {backup-catalog-A → trigger-uuid}  (single entry)
  │
  ├─> _upsertRows('setlists', remappedSetlists):
  │     ── backup-catalog-A → trigger-uuid → ON CONFLICT(id) UPDATE ✓
  │     ── backup-catalog-B → unchanged UUID, band_id=newBandId, is_catalog=true
  │           → INSERT → CONFLICTS with trigger-uuid row → PostgrestException ✗
  │
  └─> throws DataBackupException('Database error during restore: duplicate key ...')
```

### `setlist_special_items` schema

`setlist_special_items` has `band_id` but **no `setlist_id` column** — it is a
band-level template table. The link to setlists is only through
`setlist_songs.special_item_id`. No `setlist_id` remapping is needed for
`setlist_special_items` — only `band_id` remapping (already done by `remapBandId`).

### `setlist_songs` schema

`setlist_songs` has `setlist_id` (FK to `setlists.id`) but no `band_id`. Songs from
both `backup-catalog-A` and `backup-catalog-B` carry `setlist_id` pointing to one or
the other. Both must be remapped to `trigger-uuid` after the fix so all catalog songs
resolve to the single restored catalog row.

### `setlists` SELECT RLS policy

Confirmed from `20260302000000_band_user_roles.sql` Phase 5: the SELECT policy on
`setlists` is an "existing/unchanged" band-membership check with no role restriction.
Any active band member can SELECT all setlists for their band. The creator (admin) added
by `create_band` can read the trigger-created catalog row immediately in the next HTTP
request. `triggerCatalogId` is **not null** at runtime — the first implementation's
SELECT succeeds. The failure is in the remap logic, not the lookup.

### Workspace state at plan time

Current branch: `bug/restore-duplicate-catalog-setlist`. The first implementation
(original Task 3) is present in `data_backup_service.dart` on branch
`feature/restore-backup-from-welcome-screen`. The Engineer must apply the revised Task 3
on this branch instead.

---

## 6. Proposed Solution

### Design decision: map ALL `is_catalog: true` backup UUIDs to the trigger UUID; deduplicate before upsert

The first implementation correctly identifies the trigger-created catalog UUID
(`triggerCatalogId`) and remaps one backup catalog UUID onto it. The fix to the fix is
to:

1. Collect **all** `is_catalog: true` UUIDs from the backup (not just the first).
2. Map **all** of them to `triggerCatalogId` in `setlistIdRemap`.
3. **Deduplicate** during the setlists upsert: after the first `is_catalog: true` row
   is included (remapped to `trigger-uuid`), all subsequent `is_catalog: true` rows are
   dropped. Only one catalog row is upserted, which takes the UPDATE path. No INSERT.
4. `setlist_songs` remapping already uses `setlistIdRemap` with `containsKey` — once all
   catalog UUIDs are in the map, songs from all duplicate catalog setlists automatically
   remap to `trigger-uuid`. No structural change needed for setlist_songs.

**Defensive fallback for RC-3 (`triggerCatalogId` null):**
If `triggerCatalogId` is null (trigger did not fire / SELECT unexpectedly blocked),
`setlistIdRemap` is empty and no remapping occurs. The deduplication still runs,
keeping only the first `is_catalog: true` row from the backup. This row will INSERT
into the DB. If the trigger DID create an invisible catalog row, this INSERT would
still conflict — but this case is ruled out as Tony's observed failure (the SELECT is
confirmed to work). For belt-and-suspenders, the plan prescribes the `ensure_catalog_setlist`
RPC as an alternative query path in the pre-deploy verification (§15 PRE-DEPLOY TEST 4).

---

### Revised Step A — build `setlistIdRemap` over ALL catalog UUIDs (replaces current implementation)

```dart
// Already present (correct): query trigger-created catalog UUID.
final triggerCatalogRow = await supabase
    .from('setlists')
    .select('id')
    .eq('band_id', newBandId)
    .eq('is_catalog', true)
    .maybeSingle();
final triggerCatalogId = triggerCatalogRow?['id'] as String?;

final rawSetlists =
    (entry['setlists'] as List? ?? []).cast<Map<String, dynamic>>();

// FIX: collect ALL backup catalog UUIDs (was: .firstOrNull — single UUID only).
final backupCatalogIds = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .whereType<String>()
    .toSet();

// FIX: map ALL backup catalog UUIDs → trigger UUID (was: single-entry map).
final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null) {
  for (final id in backupCatalogIds) {
    setlistIdRemap[id] = triggerCatalogId;
  }
}
```

### Revised Step B — deduplicate `is_catalog: true` rows in setlists upsert

```dart
// FIX: deduplicate — only one is_catalog=true row may be upserted.
// The first is included (remapped to trigger-uuid → UPDATE path).
// All subsequent is_catalog=true rows are dropped to prevent INSERT conflicts.
var catalogIncluded = false;
final remappedSetlists = rawSetlists.expand<Map<String, dynamic>>((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  if (mapped['is_catalog'] == true) {
    if (catalogIncluded) return const [];  // drop duplicate catalog rows
    catalogIncluded = true;
  }
  return [mapped];
}).toList();
await _upsertRows('setlists', remappedSetlists);
```

### Step C — `setlist_songs` remap (unchanged in structure; now covers all catalog UUIDs)

```dart
// Structure unchanged from first implementation.
// With setlistIdRemap now containing ALL catalog UUIDs, songs belonging to
// any duplicate catalog setlist are correctly remapped to trigger-uuid.
final rawSetlistSongs =
    (entry['setlist_songs'] as List? ?? []).cast<Map<String, dynamic>>();
final remappedSetlistSongs = rawSetlistSongs.map((s) {
  final mapped = Map<String, dynamic>.from(s);
  final oldSetlistId = s['setlist_id'] as String?;
  if (oldSetlistId != null && setlistIdRemap.containsKey(oldSetlistId)) {
    mapped['setlist_id'] = setlistIdRemap[oldSetlistId];
  }
  return mapped;
}).toList();
await _upsertRows('setlist_songs', remappedSetlistSongs);
```

### Edge case matrix

| Backup catalog count | `triggerCatalogId` | Outcome                                                                                              |
| -------------------- | ------------------ | ---------------------------------------------------------------------------------------------------- |
| 0 (no catalog)       | any                | `backupCatalogIds` empty; `setlistIdRemap` empty; no catalog upsert; no conflict. ✓                  |
| 1 (normal)           | non-null           | First catalog remapped to trigger-uuid → UPDATE; no INSERT. Same as original fix. ✓                  |
| 2+ (duplicate)       | non-null           | First catalog remapped → UPDATE; second and further dropped by dedup. No INSERT. **Fixed.** ✓        |
| 1 (normal)           | null (RC-3)        | `setlistIdRemap` empty; first catalog inserts (no trigger row to conflict with). ✓                   |
| 2+ (duplicate)       | null (RC-3)        | First inserts; second and further dropped by dedup. No INSERT conflict from second row. **Fixed.** ✓ |

### What does NOT change

- No migration required.
- `_upsertRows` method: unchanged.
- `remapBandId` local closure: unchanged.
- Existing-band path (`bandExists == true`): completely unchanged.
- `importBandData`, `_parseAndValidate`, `exportBandData`, `previewBackup`,
  `_buildBandExport`, `_generateUuid`: all unchanged.
- `band_form_screen.dart`, `no_band_shell.dart`: unchanged.

---

## 7. Database Impact

**No migration required.** The fix is entirely in Dart.

| Object                                               | Impact                                               |
| ---------------------------------------------------- | ---------------------------------------------------- |
| `setlists_one_catalog_per_band` partial unique index | Unaffected — constraint remains correct and in place |
| `auto_create_catalog_for_band()` trigger             | Unaffected — trigger remains correct                 |
| `ensure_catalog_setlist` RPC                         | Unaffected                                           |
| `create_band` RPC                                    | Unaffected — called as-is, no signature change       |
| `delete_band` RPC                                    | Unaffected                                           |
| All RLS policies                                     | Unaffected                                           |
| All other RPCs                                       | Unaffected                                           |
| All migrations                                       | Unaffected — no new migration                        |

---

## 8. Flutter Architecture Changes

### State management

No changes to providers or controllers. `_restoreBandData` is a private static method.

### Providers

No changes.

### Repositories

No changes.

### Widgets

No changes.

---

## 9. Files to Create

| File                                                                    | Justification                               |
| ----------------------------------------------------------------------- | ------------------------------------------- |
| `docs/features/bug-restore-duplicate-catalog-setlist/ARCHITECT_PLAN.md` | This document — required by operating model |

No new Dart files.

---

## 10. Files to Modify

| File                                             | What changes                                                                                                                                                                                                                                      |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | In `_restoreBandData`, missing-band path only: add catalog UUID query after `create_band` call, build `setlistIdRemap`, remap setlist IDs when upserting setlists (step g.5) and setlist_songs (step g.7). Detailed implementation in §14 Task 3. |

---

## 11. Files Off-Limits

| File                                                                                                                                                          | Reason                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `lib/main.dart`                                                                                                                                               | Initialization order must not change     |
| `lib/features/settings/data_backup_service.dart` — `exportBandData`, `previewBackup`, `_buildBandExport`, `_parseAndValidate`, `_upsertRows`, `_generateUuid` | Correct and must not be modified         |
| `lib/features/settings/data_backup_service.dart` — existing-band path (`bandExists == true`)                                                                  | Behaviour is correct; must not change    |
| `lib/features/settings/data_backup_service.dart` — `importBandData`                                                                                           | Must not change                          |
| `lib/features/bands/band_form_screen.dart`                                                                                                                    | No changes required                      |
| `lib/features/shell/no_band_shell.dart`                                                                                                                       | No changes required                      |
| All migrations                                                                                                                                                | No migration required; do not create one |
| `supabase/functions/**`                                                                                                                                       | No edge function changes required        |
| `pubspec.yaml`                                                                                                                                                | No new packages required                 |
| All other `lib/features/**` files                                                                                                                             | Not in scope                             |

---

## 12. System Impact Map

| System                                 | Impact                                                       |
| -------------------------------------- | ------------------------------------------------------------ |
| Band management (create/edit/delete)   | Unaffected                                                   |
| Backup / Restore                       | Affected — primary fix target                                |
| Gigs                                   | Unaffected                                                   |
| Rehearsals                             | Unaffected                                                   |
| Setlists / Catalog                     | Affected (catalog setlist correctly restored after deletion) |
| Songs / Catalog                        | Unaffected                                                   |
| Members / RBAC                         | Unaffected                                                   |
| Auth / Session                         | Unaffected                                                   |
| Routing                                | Unaffected                                                   |
| Notifications                          | Unaffected                                                   |
| Calendar / Block-out dates             | Unaffected                                                   |
| Print templates                        | Unaffected                                                   |
| Platform (iOS / Android / Web / macOS) | Unaffected — Dart fix is cross-platform                      |

---

## 13. Regression Risk

**LOW**

Rationale:

- The change modifies only the `setlistIdRemap` construction and the setlists upsert
  loop in the missing-band path of `_restoreBandData`. No other method changes.
- For the normal (one-catalog) case, the behaviour is identical to the first
  implementation: a single UUID is in `setlistIdRemap`, the loop emits one catalog row,
  the dedup fires once. Output is identical.
- For zero-catalog backups: `backupCatalogIds` is empty, `setlistIdRemap` is empty,
  the dedup flag never fires. Output is identical to no-remap behaviour.
- `setlist_songs` remap is structurally unchanged. The only difference is the map now
  has more entries (all catalog UUIDs instead of one), which only increases the correct
  remapping surface.
- No migration, no RLS change, no RPC change.
- Auth, routing, initialization order, and all non-backup features are untouched.

---

## 14. Engineer Task Breakdown

Execute in strict order. Do not skip or reorder.

### Task 0 — Confirm the backup has duplicate catalog setlists (diagnostic — before any code change)

Run the following against Tony's actual backup file to confirm RC-2:

```bash
cat <backup_file>.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
setlists = data['band_data']['setlists']
print('Total setlists:', len(setlists))
catalogs = [s for s in setlists if s.get('is_catalog') == True]
print('is_catalog=true count:', len(catalogs))
for c in catalogs:
    print('  id:', c['id'], '  name:', c.get('name'))
"
```

**Expected (confirms RC-2):** `is_catalog=true count: 2` (or more).

Record the output in `ENGINEER_REPORT.md`. If count is 1 (only one catalog row), stop
and escalate to the Architect — the diagnosis requires revision before proceeding.

### Task 1 — Confirm constraint and trigger definitions

Run against production Supabase (unchanged from original plan):

```sql
-- Confirm constraint definition
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'setlists'
  AND schemaname = 'public'
  AND indexname = 'setlists_one_catalog_per_band';
-- Expected: one row; indexdef contains 'WHERE (is_catalog = true)'

-- Confirm trigger on bands
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'bands'
  AND trigger_schema = 'public';
-- Expected: includes auto_create_catalog_for_band (or similar name) for INSERT

-- Confirm ensure_catalog_setlist signature (for reference)
SELECT proname, pg_get_function_arguments(oid) AS args,
       pg_get_function_result(oid) AS return_type
FROM pg_proc
WHERE proname = 'ensure_catalog_setlist'
  AND pronamespace = 'public'::regnamespace;
-- Record return_type in ENGINEER_REPORT.md (expected: uuid or void)
```

Record full outputs in `ENGINEER_REPORT.md`.

### Task 2 — Read the current `_restoreBandData` method in full

Read `lib/features/settings/data_backup_service.dart` and locate `_restoreBandData`.
Confirm the **current** (first-implementation) state of the missing-band path:

```dart
// Should currently contain (first implementation):
final backupCatalogId = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .firstOrNull;

final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null && backupCatalogId != null) {
  setlistIdRemap[backupCatalogId] = triggerCatalogId;
}
```

And the setlists upsert step:

```dart
// Should currently contain:
final remappedSetlists = rawSetlists.map((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  return mapped;
}).toList();
await _upsertRows('setlists', remappedSetlists);
```

If the file does not contain these exact blocks, document the actual state in
`ENGINEER_REPORT.md` before proceeding.

### Task 3 — Replace `setlistIdRemap` construction and setlists upsert (the actual fix)

In `lib/features/settings/data_backup_service.dart`, `_restoreBandData`,
missing-band path:

**3a.** Replace the `backupCatalogId` + `setlistIdRemap` block:

```dart
// REMOVE:
final backupCatalogId = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .firstOrNull;

// Empty when either UUID is absent — safe no-op fallback.
final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null && backupCatalogId != null) {
  setlistIdRemap[backupCatalogId] = triggerCatalogId;
}

// REPLACE WITH:
// Collect ALL backup catalog UUIDs — handles pre-existing duplicates.
final backupCatalogIds = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .whereType<String>()
    .toSet();

// Map ALL of them to the trigger-created catalog UUID.
// Empty when triggerCatalogId is null — safe no-op fallback.
final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null) {
  for (final id in backupCatalogIds) {
    setlistIdRemap[id] = triggerCatalogId;
  }
}
```

**3b.** Replace the setlists upsert block (step g.5):

```dart
// REMOVE:
final remappedSetlists = rawSetlists.map((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  return mapped;
}).toList();
await _upsertRows('setlists', remappedSetlists);

// REPLACE WITH:
// 5. Setlists — remap band_id; remap ALL catalog ids → trigger-uuid;
//    deduplicate so only one is_catalog=true row is upserted.
var catalogIncluded = false;
final remappedSetlists = rawSetlists.expand<Map<String, dynamic>>((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  if (mapped['is_catalog'] == true) {
    if (catalogIncluded) return const [];  // drop duplicate catalog rows
    catalogIncluded = true;
  }
  return [mapped];
}).toList();
await _upsertRows('setlists', remappedSetlists);
```

**3c.** The setlist_songs upsert (step g.7) is **unchanged in structure** — no edit
required. The `setlistIdRemap` now contains all catalog UUIDs, so songs from all
duplicate catalog setlists are automatically remapped. Verify the block still reads:

```dart
// 7. Setlist songs — remap setlist_id for songs belonging to the catalog setlist
final rawSetlistSongs =
    (entry['setlist_songs'] as List? ?? []).cast<Map<String, dynamic>>();
final remappedSetlistSongs = rawSetlistSongs.map((s) {
  final mapped = Map<String, dynamic>.from(s);
  final oldSetlistId = s['setlist_id'] as String?;
  if (oldSetlistId != null &&
      setlistIdRemap.containsKey(oldSetlistId)) {
    mapped['setlist_id'] = setlistIdRemap[oldSetlistId];
  }
  return mapped;
}).toList();
await _upsertRows('setlist_songs', remappedSetlistSongs);
```

If this block is already present unchanged, no edit is needed.

Do not change any other part of `_restoreBandData`, the existing-band path, or any
other method.

### Task 4 — `flutter analyze` — zero errors

Run `flutter analyze` and fix any analysis errors introduced by the changes. Do not
modify files not listed in this plan to fix pre-existing errors.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (run before any Flutter app build or deployment)

All Tier 1 tests are read-only queries against the existing database.

```sql
-- PRE-DEPLOY TEST 1: Confirm setlists_one_catalog_per_band constraint exists
-- Expected: one row with indexdef containing 'WHERE (is_catalog = true)'
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'setlists'
  AND schemaname = 'public'
  AND indexname = 'setlists_one_catalog_per_band';

-- PRE-DEPLOY TEST 2: Confirm auto_create_catalog_for_band trigger exists on bands
-- Expected: at least one row for INSERT with trigger name referencing catalog creation
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'bands'
  AND trigger_schema = 'public';

-- PRE-DEPLOY TEST 3: Confirm create_band RPC signature is unchanged
-- Expected: p_name text, p_avatar_color text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text
SELECT proname, pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname = 'create_band' AND pronamespace = 'public'::regnamespace;

-- PRE-DEPLOY TEST 4: Confirm ensure_catalog_setlist signature (informational)
-- Record return_type for ENGINEER_REPORT.md
SELECT proname, pg_get_function_arguments(oid) AS args,
       pg_get_function_result(oid) AS return_type
FROM pg_proc
WHERE proname = 'ensure_catalog_setlist'
  AND pronamespace = 'public'::regnamespace;

-- PRE-DEPLOY TEST 5: Confirm setlists.is_catalog column exists and is boolean
-- Expected: is_catalog | boolean
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'setlists'
  AND column_name = 'is_catalog';

-- PRE-DEPLOY TEST 6: Identify all bands with duplicate catalog setlists in production
-- (confirms the pre-existing data integrity issue motivating the fix)
-- Expected: Tony's source band appears here; run before any restore attempt
SELECT band_id, COUNT(*) AS catalog_count,
       array_agg(id) AS catalog_ids,
       array_agg(name) AS catalog_names
FROM public.setlists
WHERE is_catalog = true
GROUP BY band_id
HAVING COUNT(*) > 1;
-- If 0 rows: Tony's band cleanup may have happened; still proceed (defensive fix is
-- correct regardless). Document result in ENGINEER_REPORT.md.
```

### Tier 2 — Post-deployment (run after Flutter app is deployed with fix)

```sql
-- POST-DEPLOY TEST 1: Confirm no band has more than one catalog setlist
-- Run immediately after any restore test. Expected: 0 rows.
SELECT band_id, COUNT(*) AS catalog_count
FROM public.setlists
WHERE is_catalog = true
GROUP BY band_id
HAVING COUNT(*) > 1;

-- POST-DEPLOY TEST 2: Verify every active band has exactly one catalog setlist
-- Expected: every row has catalog_count = 1 (or 0 for bands without any setlists)
SELECT b.name AS band_name, b.id AS band_id, COUNT(s.id) AS catalog_count
FROM public.bands b
LEFT JOIN public.setlists s ON s.band_id = b.id AND s.is_catalog = true
GROUP BY b.id, b.name
ORDER BY catalog_count DESC
LIMIT 20;

-- POST-DEPLOY TEST 3: Verify restored catalog setlist has ALL songs from backup
-- Replace <restored-band-id> with actual ID after restore test.
-- Expected: row count matches total songs in backup's catalog setlists (combined)
SELECT ss.id, ss.song_id, ss.special_item_id, ss.item_type, ss.position
FROM public.setlist_songs ss
JOIN public.setlists sl ON sl.id = ss.setlist_id
WHERE sl.band_id = '<restored-band-id>'
  AND sl.is_catalog = true
ORDER BY ss.position;

-- POST-DEPLOY TEST 4: Verify no orphaned setlist_songs (songs pointing to
-- non-existent setlist_id — would indicate missing setlist_id remap)
-- Expected: 0 rows
SELECT ss.id, ss.setlist_id
FROM public.setlist_songs ss
LEFT JOIN public.setlists sl ON sl.id = ss.setlist_id
WHERE sl.id IS NULL
LIMIT 20;
```

---

## 16. QA Regression Areas

### Primary — restore a backup that contains duplicate catalog setlists (the failing case)

This test must use Tony's actual backup file (or a synthetic backup with two
`is_catalog: true` rows):

1. Confirm the backup JSON has ≥ 2 rows with `"is_catalog": true` (run Task 0 script).
2. Delete the source band if it still exists.
3. Restore using **Path A** (band settings) or **Path B** (welcome screen).
4. **Expected:** Restore succeeds — success snackbar shown, no error toast.
5. **Expected:** The restored band's Catalog setlist contains all songs from the backup
   (songs from BOTH duplicate catalog setlists merged into one). Verify song count
   matches the total from both `is_catalog: true` rows in the backup.
6. **Expected (SQL POST-DEPLOY TEST 1):** Zero rows with `catalog_count > 1`.

### Secondary — restore after deletion, single-catalog backup (regression of original fix)

1. Create a fresh test band, add 3 songs to the Catalog.
2. Export. Confirm backup has exactly `is_catalog=true count: 1`.
3. Delete the band.
4. Restore via either entry point.
5. **Expected:** Restore succeeds. Songs present in the Catalog. No error.

### Regression — restore when source band still exists (existing-band path)

1. Export a band's data.
2. Do NOT delete the band.
3. Navigate to the same band's Settings → Backup / Restore → select backup → confirm.
4. **Expected:** Restore succeeds identically to pre-fix. Catalog setlist and its songs
   are preserved.

### Edge case — empty catalog setlist (no songs)

1. Create band, add no songs. Export. Delete. Restore.
2. **Expected:** Restore succeeds. Catalog setlist exists and is empty.

### Edge case — non-catalog setlists unaffected

1. Band with 2 regular setlists + 1 catalog (songs in all three). Export, delete, restore.
2. **Expected:** All 3 setlists restored correctly with their songs.

### Welcome-screen entry point (end-to-end)

1. Delete all bands (user lands on welcome screen).
2. Use "Restore from backup" button with a backup from a deleted band that had catalog songs.
3. **Expected:** Restore succeeds. Band appears with correct catalog content.

---

## 17. Rollout / Migration Strategy

No migration required.

Deploy the Flutter app as usual:

- Web: `./tools/deploy_web.sh`
- Mobile: `./tools/build_mobile_release.sh`

No database changes. No data backfill. The fix is backward-compatible with all
existing backups (schema v1 unchanged).

---

## 18. Out of Scope

- Cleaning up **existing** duplicate `is_catalog: true` rows in the live database.
  The `setlists_one_catalog_per_band` constraint prevents future duplicates but rows
  that predate it may still exist (confirmed by PRE-DEPLOY TEST 6). A separate
  one-time maintenance migration or SQL script can clean these up, but this is not
  required for the bug fix — the restore now handles duplicates defensively.
- Adding `068_ensure_catalog_setlist_rpc_standalone.sql` to the tracked
  `supabase/migrations/` directory (documentation gap — separate maintenance work).
- Adding unit tests for `_restoreBandData` (no existing test infrastructure).
- Improving user-facing error messages beyond the current `DataBackupException` wrapping.
- Changes to the backup file schema/format (schema v1 unchanged).
- `prevent_catalog_deletion` / `prevent_catalog_rename` triggers (correct and unaffected).
- Any behavior of the `setlist_special_items` table (no `setlist_id` remapping needed, confirmed).
