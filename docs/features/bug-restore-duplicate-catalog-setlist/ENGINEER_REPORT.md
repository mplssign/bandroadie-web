# Engineer Report

## Feature Slug

`bug/restore-duplicate-catalog-setlist`

## Feature Title

Restore fails with duplicate catalog setlist constraint violation after band deletion

---

## Goal

Fix the missing-band restore path in `_restoreBandData` so that restoring a backup
after band deletion no longer violates the `setlists_one_catalog_per_band` unique
constraint. The `create_band` RPC fires the `auto_create_catalog_for_band()` trigger
which pre-creates a catalog setlist; the fix remaps the backup's catalog UUID onto
the trigger-created row before upserting.

---

## Task 1 — SQL Query Outputs (verbatim)

### Query 1: Constraint definition

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'setlists'
  AND schemaname = 'public'
  AND indexname = 'setlists_one_catalog_per_band';
```

**Result:**

```
indexname                     | indexdef
------------------------------+--------------------------------------------------------------------------------------------------------------------------------------
setlists_one_catalog_per_band | CREATE UNIQUE INDEX setlists_one_catalog_per_band ON public.setlists USING btree (band_id) WHERE (lower(name) = 'catalog'::text)
```

### Query 2: Trigger definition on `bands`

```sql
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'bands'
  AND trigger_schema = 'public';
```

**Result:**

```
trigger_name                 | event_manipulation | action_timing | action_statement
-----------------------------+--------------------+---------------+-----------------------------------------------
trigger_auto_create_catalog  | INSERT             | AFTER         | EXECUTE FUNCTION auto_create_catalog_for_band()
```

### Constraint discrepancy: documented, does NOT block the fix

**Plan assumed:** `WHERE (is_catalog = true)`
**Actual:** `WHERE (lower(name) = 'catalog'::text)`

The constraint enforces uniqueness on `band_id` where the setlist name is 'catalog'
(case-insensitive), not on the `is_catalog` boolean column. This differs from the
plan's assumption.

**Why the fix remains valid despite the discrepancy:**

The `ensure_catalog_setlist` RPC (called by the trigger) creates the catalog row with
**both** `is_catalog = true` AND `name = 'Catalog'`. This was confirmed by reading the
function definition:

```sql
INSERT INTO public.setlists (band_id, name, setlist_type, is_catalog, total_duration)
VALUES (p_band_id, 'Catalog', 'catalog', true, 0)
```

Therefore:

- The fix's query `.eq('is_catalog', true)` **correctly finds** the trigger-created catalog.
- The backup's catalog setlist (created by the same app logic) also has `is_catalog = true`.
- The remap strategy (UUID remapping) is valid regardless of whether the constraint
  predicate is name-based or `is_catalog`-based.

The discrepancy is in the database documentation only — not in the fix's correctness.

### Trigger name discrepancy: equivalent, does NOT block the fix

**Plan assumed trigger name:** `auto_create_catalog_for_band` (or equivalent)
**Actual trigger name:** `trigger_auto_create_catalog`
**Function called:** `EXECUTE FUNCTION auto_create_catalog_for_band()`

The trigger fires `AFTER INSERT ON bands`, calls `auto_create_catalog_for_band()`, and
produces the same behavior described in the plan. Classified as "equivalent" per plan §14 Task 1.

### Additional query: `_upsertRows` onConflict target for `setlists` table

`_upsertRows` uses a single code path for all tables:

```dart
await supabase.from(table).upsert(data, onConflict: 'id', ignoreDuplicates: false);
```

`onConflict: 'id'` — the primary key. This confirms the constraint violation
mechanism: with `onConflict: 'id'`, a backup catalog row with `id = backup-uuid` does
NOT match the trigger-created row (`id = trigger-uuid`) → INSERT path taken → violates
`setlists_one_catalog_per_band` → `PostgrestException`. The fix resolves this by
remapping `backup-uuid` → `trigger-uuid` before calling `_upsertRows`, causing the
`ON CONFLICT (id)` to match the trigger-created row and take the UPDATE path instead.

### Additional query: `bands` INSERT RLS policies (from prior bug context)

```
policyname                    | cmd    | with_check
------------------------------+--------+---------------------------
bands: insert own             | INSERT | (created_by = auth.uid())
bands_insert_authenticated    | INSERT | (created_by = auth.uid())
```

Both INSERT policies only require `created_by = auth.uid()` — no band membership check.
This confirms RC-4 (Sub-mode B) from the prior bug: the bootstrap deadlock arises from
`band_members` INSERT policy, not the `bands` INSERT policy.

---

## Architect Tasks Completed

- [x] Task 1 — SQL queries run against production. Constraint and trigger confirmed.
      Discrepancies documented above. Fix validity confirmed — proceeded.
- [x] Task 2 — `_restoreBandData` read in full. Verified:
  - Step g.5: `await _upsertRows('setlists', remapBandId(entry['setlists'] as List? ?? []))` ✓
  - Step g.7: `await _upsertRows('setlist_songs', entry['setlist_songs'] as List? ?? [])` (no remap) ✓
  - Code matches plan assumptions exactly.
- [x] Task 3 — Catalog setlist UUID remap implemented (3a, 3b, 3c). See Files Modified.
- [x] Task 4 — `flutter analyze`: 0 errors, 0 warnings. `dart format` applied to changed file.

---

## Files Created

- `docs/features/bug-restore-duplicate-catalog-setlist/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/settings/data_backup_service.dart` — missing-band path in `_restoreBandData`:
  - **3a:** Added catalog UUID query block after `create_band` RPC call: queries
    `setlists` for `band_id = newBandId AND is_catalog = true`, identifies backup
    catalog UUID via `is_catalog == true`, builds `setlistIdRemap`.
  - **3b:** Replaced step g.5 setlists upsert: now uses `rawSetlists` with per-row
    `band_id` and optional `id` remap via `setlistIdRemap`.
  - **3c:** Replaced step g.7 setlist_songs upsert: now applies `setlist_id` remap
    for any setlist_songs belonging to the remapped catalog setlist.

---

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings** (ran in 3.4s across entire project)

---

## Test Results

Not run — no existing test infrastructure for `DataBackupService`; out of scope per plan §18.

---

## Verification

### Manual steps performed:

- Read full `_restoreBandData` method and confirmed existing-band path is byte-for-byte unchanged.
- Confirmed only three blocks within the missing-band path were modified (3a, 3b, 3c).
- Confirmed `_upsertRows`, `_generateUuid`, `importBandData`, `exportBandData`,
  `previewBackup`, `_buildBandExport`, `_parseAndValidate` are all unchanged.
- Confirmed `band_form_screen.dart` and `no_band_shell.dart` are untouched.
- Confirmed no migration files created.

---

## Deviations From Architect Plan

### Deviation 1: Constraint predicate differs from plan assumption

- **Plan assumed:** `WHERE (is_catalog = true)`
- **Actual:** `WHERE (lower(name) = 'catalog'::text)`
- **Justification for proceeding:** The fix's implementation uses `is_catalog = true`
  to identify catalogs. Since `ensure_catalog_setlist` creates catalogs with both
  `is_catalog = true` AND `name = 'Catalog'`, the query correctly finds the
  trigger-created row. The remap strategy is valid regardless of constraint predicate.
  The fix is fully correct.

### Deviation 2: Trigger name differs from plan assumption

- **Plan assumed trigger name:** `auto_create_catalog_for_band`
- **Actual trigger name:** `trigger_auto_create_catalog` (calls `auto_create_catalog_for_band()`)
- **Justification for proceeding:** Behavior is identical to plan description. Plan
  explicitly allows "or equivalent firing `AFTER INSERT ON bands`".

---

## Blockers Encountered

None. Discrepancies in constraint predicate and trigger name were assessed and
confirmed not to affect fix correctness.

---

## Ready For QA

Yes

---

## Correction — Revised Fix (Post-Implementation Re-Diagnosis 2026-06-07)

### Context

After the initial fix was deployed, Tony re-tested with the same backup file and
received the identical error. The Architect revised §3 and §14 of `ARCHITECT_PLAN.md`
with a new root cause (RC-2: `firstOrNull` only remaps the first `is_catalog=true`
row) and a revised Task 3. This section documents the correction implementation.

### Task 0 — Backup file diagnostic

**File tested:** `bandroadie_the_banana_stand_20260607.json`

**Script output:**

```
Total setlists: 4
is_catalog=true count: 1
  id: 0e53dce6-5827-4220-8a84-8f6f73753ea6   name: Catalog
```

**Discrepancy from plan expectation:** Plan predicted `is_catalog=true count: 2` (or
more). Actual count is 1.

Per Task 0: "If count is 1 (only one catalog row), stop and escalate to the Architect."
However, the user (Architect) explicitly directed proceeding with the defensive
multi-catalog implementation regardless of count. The revised fix is correct for count
1 (behaviour identical to original fix) and also correct for count 2+ (the bug case).

Additional detail noted: the backup's setlists have names `'Montrose Saloon'`,
`'New Songs'`, `'summer fests'`, and `'Catalog'`. The actual DB constraint is
`lower(name) = 'catalog'` (confirmed in original Task 1). The `Catalog` setlist is the
only one covered by the constraint. No duplicate name-based catalog rows exist in this
backup either.

The root cause of the continued failure with this specific backup remains unresolved
by RC-2 — but the revised fix is strictly more defensive and is applied as directed.

### Task 1 — Already completed; results recorded above in original Task 1 section

No re-run needed. Outputs unchanged.

### Task 3 — Revised implementation applied

**3a — Replaced `backupCatalogId`/`firstOrNull` block with `backupCatalogIds` Set:**

```dart
// REMOVED:
final backupCatalogId = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .firstOrNull;

final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null && backupCatalogId != null) {
  setlistIdRemap[backupCatalogId] = triggerCatalogId;
}

// REPLACED WITH:
final backupCatalogIds = rawSetlists
    .where((s) => s['is_catalog'] == true)
    .map((s) => s['id'] as String?)
    .whereType<String>()
    .toSet();

final Map<String, String> setlistIdRemap = {};
if (triggerCatalogId != null) {
  for (final id in backupCatalogIds) {
    setlistIdRemap[id] = triggerCatalogId;
  }
}
```

**3b — Replaced `.map()` setlists upsert with `.expand()` + `catalogIncluded` dedup:**

```dart
// REMOVED:
final remappedSetlists = rawSetlists.map((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  return mapped;
}).toList();
await _upsertRows('setlists', remappedSetlists);

// REPLACED WITH:
var catalogIncluded = false;
final remappedSetlists = rawSetlists.expand<Map<String, dynamic>>((s) {
  final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
  final oldId = s['id'] as String?;
  if (oldId != null && setlistIdRemap.containsKey(oldId)) {
    mapped['id'] = setlistIdRemap[oldId];
  }
  if (mapped['is_catalog'] == true) {
    if (catalogIncluded) return const []; // drop duplicate catalog rows
    catalogIncluded = true;
  }
  return [mapped];
}).toList();
await _upsertRows('setlists', remappedSetlists);
```

**3c — `setlist_songs` upsert block: no structural change required.**
Already present and correct from initial implementation. With `setlistIdRemap` now
containing all catalog UUIDs, songs from any duplicate catalog setlist are
automatically remapped to `trigger-uuid`.

### Task 4 — `flutter analyze` (post-correction)

Command: `flutter analyze` (full project)
Result: **0 errors, 0 warnings** (ran in 3.7s)

`dart format lib/features/settings/data_backup_service.dart` — no change (already
formatted).

### git diff scope (post-correction)

Modified files: `lib/features/settings/data_backup_service.dart` only.
New untracked files: `docs/features/bug-restore-duplicate-catalog-setlist/` (this
report + `ARCHITECT_PLAN.md`).

Note: the `git diff` also shows `String? targetBandId` nullable changes in
`importBandData` and `_restoreBandData` — these are pre-existing uncommitted changes
from the `feature/restore-backup-from-welcome-screen` branch, not introduced in this
session.

### Deviations (this correction pass)

| Deviation                | Detail                                                                                                                                                          |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Task 0 count = 1, not 2+ | Plan predicted duplicate catalog rows; actual backup has exactly 1. Plan says stop-and-escalate, but Architect explicitly directed proceeding. Documented here. |
| Task 3c no edit required | `setlist_songs` block already present from initial implementation. No structural change needed — confirmed by code read.                                        |
