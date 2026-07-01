# Architect Plan

## Feature Slug
`gig-pay-upsert-duplicate-key`

## Problem Summary
Saving an edit to a gig that already has a `gig_pay` financial entry fails with the
generic error "Failed to update event. Please try again." This affects any confirmed gig
where pay was previously recorded, making it impossible to save changes through the
event editor.

---

## Root Cause
**Confidence: HIGH — confirmed by direct code tracing.**

The event editor initialises `_gigPayDetails` at open time using
`GigPayDetails.fromAmountOnly(amountCents: data.gigPayCents!, gigDate: data.date)` (
`event_editor_drawer.dart:282`). This factory does not look up the existing
`financial_entries` row and therefore leaves `existingEntryId = null`.

When the user saves (`event_editor_drawer.dart:1418–1428`), `_gigPayDetails != null`
so `upsertGigPayEntry()` is called (`financial_entry_repository.dart:51`). Because
`existingEntryId == null`, the method takes the `else` branch (line 93) and executes a
raw `INSERT` into `financial_entries`.

This INSERT violates the `uniq_gig_pay_entry` unique partial index
(`financial_entries(gig_id) WHERE entry_type = 'gig_pay'`), which allows at most one
`gig_pay` row per gig. Supabase throws a `PostgrestException` (Postgres error code
`23505 unique_violation`).

The exception propagates to the `catch` block at `event_editor_drawer.dart:1481`, is
passed through `_mapErrorToMessage → mapEventErrorToMessage → classifyError`. The error
string `"duplicate key value violates unique constraint 'uniq_gig_pay_entry'"` does not
match any keyword in the permission / network / validation branches of `classifyError`
(`event_permission_helper.dart:152–182`), so it falls through to
`EventErrorType.unknown` → "Failed to update event. Please try again."

### Trigger scenario
The bug fires whenever:
- A gig already has a `financial_entries` row with `entry_type = 'gig_pay'`, AND
- The user opens the event editor (which seeds `_gigPayDetails` via `fromAmountOnly`,
  leaving `existingEntryId = null`), AND
- The user saves without first opening the pay sheet (which would call
  `fetchGigPayEntry` and populate `existingEntryId` via `GigPayDetails.fromEntry`).

Opening the pay sheet before saving re-loads the entry ID and takes the correct UPDATE
path. Saving without opening the pay sheet always takes the broken INSERT path.

---

## Reference Docs Consulted
None applicable — this is a financial data write path bug, not a notifications or
routing issue. No `docs/reference/financials/` directory exists.

---

## Existing System Analysis

### Data flow: event save with gig pay (edit mode)
```
event_editor_drawer.dart:_saveEvent()
  │
  ├─ repository.updateGig(...)                    ← gig row update, always
  │
  └─ if (_gigPayDetails != null)                  ← line 1419
       financialRepo.upsertGigPayEntry(
         details: _gigPayDetails!,                ← existingEntryId is null
       )
         │
         └─ else branch (line 93):
              INSERT INTO financial_entries ...
              ↳ violates uniq_gig_pay_entry
              ↳ PostgrestException 23505
              ↳ caught at event_editor_drawer.dart:1481
              ↳ "Failed to update event. Please try again."
```

### How `_gigPayDetails` is seeded on open (edit mode)
`event_editor_drawer.dart:280–286`:
```dart
if (data.gigPayCents != null) {
  _gigPayDetails = GigPayDetails.fromAmountOnly(
    amountCents: data.gigPayCents!,
    gigDate: data.date,
  );
}
```
`GigPayDetails.fromAmountOnly` never queries `financial_entries`; `existingEntryId`
is always `null` when populated this way.

### How `existingEntryId` can be populated correctly
`event_editor_drawer.dart:1929–1932` (inside the pay sheet opener):
```dart
final existing = await repo.fetchGigPayEntry(widget.existingEventId!);
if (existing != null) {
  initialDetails = GigPayDetails.fromEntry(existing);  // sets existingEntryId
}
```
This path is only exercised when the user taps the pay field to open the
`GigPaySheet`. It is never called during the normal open + save flow.

### The unique partial index (backstop)
```sql
CREATE UNIQUE INDEX uniq_gig_pay_entry
  ON public.financial_entries(gig_id)
  WHERE entry_type = 'gig_pay';
```
This index correctly enforces at most one `gig_pay` row per gig. It is not the bug;
it is the correct database invariant that the client-side code fails to respect.

---

## Reference Fix Assessment (feat/gig-address-field)

`git diff main feat/gig-address-field -- lib/features/financials/financial_entry_repository.dart`
shows a fix that adds a pre-INSERT check in the `else` branch of `upsertGigPayEntry`:

```dart
// If existingEntryId is null, query for an existing row before inserting
final existingRow = await supabase
    .from('financial_entries')
    .select('id')
    .eq('gig_id', gigId)
    .eq('entry_type', 'gig_pay')
    .maybeSingle();

if (existingRow != null) {
  // UPDATE the existing row
  final updated = await supabase
      .from('financial_entries')
      .update({...payload, 'updated_at': DateTime.now().toIso8601String()})
      .eq('id', existingRow['id'] as String)
      .eq('band_id', bandId)
      .select()
      .single();
  result = updated;
} else {
  // INSERT (no existing row)
  final inserted = await supabase
      .from('financial_entries')
      .insert(payload)
      .select()
      .single();
  result = inserted;
}
```

### Correctness review

| Concern | Assessment |
|---------|------------|
| Race condition (two concurrent saves both pass the SELECT before either inserts) | **Not a real risk.** BandRoadie is a personal band management app; concurrent saves of the same gig by two devices simultaneously is implausible. Even if it occurred, the unique index remains in place as a backstop — the second INSERT would be rejected with a constraint violation, which is correct behavior. No data corruption would result. |
| `band_id` scoping in the SELECT | **Safe but incomplete.** The SELECT filters on `gig_id` + `entry_type` only. RLS (`check_band_member(band_id)`) already ensures only records in the user's band are visible. `gig_id` is a globally unique UUID, so the query is unambiguous. **The Engineer must add `.eq('band_id', bandId)` to the SELECT for defense-in-depth**, even though it is not strictly required. |
| `band_id` scoping in the UPDATE | **Correct.** `.eq('band_id', bandId)` is present. |
| `updated_at` in UPDATE | **Correct.** Added explicitly, consistent with the existing UPDATE branch. |
| `created_by` in UPDATE payload | **Pre-existing behavior, not a bug.** The existing UPDATE branch (when `existingEntryId != null`) also includes `created_by` in `...payload`. The reference fix is consistent with this. |

### Recommendation: client-side check-then-write vs. DB-level UPSERT

**Recommendation: adopt the client-side check-then-write (with the `band_id` SELECT fix).**

A DB-level `ON CONFLICT` UPSERT via PostgREST's `.upsert()` would require a unique
constraint (not a partial index) on the conflict target — PostgREST cannot target a
partial index (`WHERE entry_type = 'gig_pay'`) via its `onConflict` parameter. Adding a
full unique constraint on `gig_id` alone would be incorrect (multiple entry types can
legitimately share a `gig_id`). An RPC-based upsert would be correct but adds migration
scope, deployment steps, and complexity not warranted by the risk profile.

The check-then-write fix is minimal, localized, correct for this use case, and the
unique index continues to serve as the authoritative backstop against any edge-case
duplicate.

---

## Proposed Solution

**One file to change. No migration. No new dependencies. No new files.**

In `lib/features/financials/financial_entry_repository.dart`, replace the bare `else`
INSERT branch in `upsertGigPayEntry()` with a check-then-write pattern:

1. Query for an existing `gig_pay` row by `gig_id`, `entry_type`, and `band_id`.
2. If found: UPDATE that row (using its `id` and the `band_id` scope).
3. If not found: INSERT as before.

This makes `upsertGigPayEntry` genuinely idempotent — calling it with or without
`existingEntryId` produces a correct result regardless of whether a row already exists.

---

## Database Impact

| Area | Status |
|------|--------|
| Migrations | **Not required.** The unique partial index already exists and is correct. No schema change needed. |
| RLS policies | **Unaffected.** The fix adds a SELECT + conditional UPDATE — both are already covered by existing RLS policies (`financial_entries_select` and `financial_entries_update`). |
| RPC functions | **Unaffected.** No RPCs involved. |
| Triggers | **Unaffected.** `trg_sync_gig_pay` fires on INSERT and UPDATE — behavior is unchanged. On the UPDATE path it will still sync `gigs.gig_pay`. |

---

## Flutter Architecture Changes

| Layer | Change |
|-------|--------|
| Repository (`financial_entry_repository.dart`) | `upsertGigPayEntry` else-branch replaced with check-then-write |
| Controller / Widget | None |
| State / Provider | None |
| Model | None |

---

## Files to Create
None.

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/financials/financial_entry_repository.dart` | In `upsertGigPayEntry()`: replace the bare INSERT `else` branch (lines 93–100) with a check-then-write that queries for an existing `gig_pay` row by `gig_id` + `entry_type` + `band_id`, then UPDATEs if found or INSERTs if not |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Root cause is in the repository; fixing the insert logic there is correct and avoids coupling the editor to an extra async fetch at open time |
| `lib/features/financials/models/financial_entry.dart` | Model is correct; `GigPayDetails.fromAmountOnly` is valid for its purpose |
| `lib/shared/utils/event_permission_helper.dart` | Error classification is correct; the root cause is the thrown exception, not the classification |
| All migration files | No schema change required |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | **affected** — gig save flow fixed |
| Rehearsals | unaffected — `upsertGigPayEntry` is never called for rehearsals |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | all platforms affected by the fix (bug existed on all) |
| Financials dashboard | unaffected — `fetchEntriesForBand`, `insertEntry`, `updateEntry`, `deleteEntry` are unchanged |

---

## Regression Risk
**LOW**

- One method body changed in one repository file
- No state, widget, or provider changes
- No schema changes
- The existing `updateEntry` path (when `existingEntryId != null`) is untouched
- The new SELECT adds one extra Supabase round-trip only in the `existingEntryId == null`
  case — acceptable cost
- The unique index remains as a backstop in all code paths

---

## Engineer Task Breakdown

Execute in order. Do not skip or reorder.

### Task 1 — Update `upsertGigPayEntry` else-branch in `financial_entry_repository.dart`

Locate the `else` block starting at line 93:
```dart
} else {
  // INSERT new entry — rely on unique partial index to prevent duplicates
  final inserted = await supabase
      .from('financial_entries')
      .insert(payload)
      .select()
      .single();
  result = inserted;
}
```

Replace it with:
```dart
} else {
  // No existingEntryId — query for an existing gig_pay row before inserting
  // to avoid violating the uniq_gig_pay_entry unique partial index.
  final existingRow = await supabase
      .from('financial_entries')
      .select('id')
      .eq('gig_id', gigId)
      .eq('entry_type', 'gig_pay')
      .eq('band_id', bandId)
      .maybeSingle();

  if (existingRow != null) {
    final updated = await supabase
        .from('financial_entries')
        .update({
          ...payload,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', existingRow['id'] as String)
        .eq('band_id', bandId)
        .select()
        .single();
    result = updated;
  } else {
    final inserted = await supabase
        .from('financial_entries')
        .insert(payload)
        .select()
        .single();
    result = inserted;
  }
}
```

**Key differences from reference fix:**
- Added `.eq('band_id', bandId)` to the SELECT for defense-in-depth (not in the reference).
- The rest matches the reference fix exactly.

### Task 2 — Run `flutter analyze`

Confirm 0 errors, 0 warnings after the change.

### Task 3 — Verify `git diff` shows exactly one file changed

```bash
git diff --stat
```
Expected: only `lib/features/financials/financial_entry_repository.dart` appears.

---

## Verification Plan

### Tier 1 — Pre-deployment (no schema changes to apply, run immediately)

No Supabase schema changes are made by this fix. All Tier 1 verification is done by
reading the changed code before committing.

```
-- PRE-DEPLOY TEST 1:
-- Static code review: confirm the else-branch in upsertGigPayEntry now contains
-- a maybeSingle() SELECT before the INSERT, with .eq('band_id', bandId) present.
-- Read lib/features/financials/financial_entry_repository.dart lines ~93–130.
-- Confirm: SELECT filters on gig_id + entry_type + band_id.
-- Confirm: UPDATE path uses existingRow['id'] + band_id filter.
-- Confirm: INSERT path unchanged.
-- Confirm: no other methods in the file were modified.
```

```
-- PRE-DEPLOY TEST 2:
-- flutter analyze: 0 errors, 0 warnings.
```

```
-- PRE-DEPLOY TEST 3:
-- git diff --stat: only financial_entry_repository.dart appears.
```

### Tier 2 — Post-deployment (run in the app after fix is merged)

```
-- POST-DEPLOY TEST 1 — Primary regression (bug fix):
-- 1. Open any confirmed gig that already shows a pay amount.
-- 2. Change any non-pay field (e.g., venue name).
-- 3. Tap Save / Update.
-- Expected: save succeeds, "Gig updated" snackbar appears, no error.

-- POST-DEPLOY TEST 2 — Pay field edit:
-- 1. Open a confirmed gig with existing pay.
-- 2. Tap the pay field, change the amount, close the pay sheet.
-- 3. Tap Save.
-- Expected: save succeeds, new amount is reflected in ViewGigDrawer and financials.

-- POST-DEPLOY TEST 3 — New gig with pay (create flow, no existing row):
-- 1. Create a new confirmed gig, add pay.
-- 2. Tap Save.
-- Expected: gig created, pay entry created, financials dashboard reflects the entry.

-- POST-DEPLOY TEST 4 — New gig without pay (no _gigPayDetails):
-- 1. Create a confirmed gig without touching the pay field.
-- 2. Tap Save.
-- Expected: save succeeds, no financial_entries row created for this gig.

-- POST-DEPLOY TEST 5 — Rehearsal save (must not regress):
-- 1. Create or edit a rehearsal.
-- 2. Tap Save.
-- Expected: no error. (upsertGigPayEntry is never called for rehearsals.)

-- POST-DEPLOY TEST 6 — Financials dashboard integrity:
-- After TEST 1 and TEST 2, open the Financials tab.
-- Expected: only one gig_pay entry exists per gig (no duplicates). Amount correct.
```

---

## QA Regression Areas

QA must explicitly validate:

1. **Primary bug fix**: editing an existing gig with pay saves without error (Tier 2, Test 1)
2. **Pay field edit round-trip**: opening pay sheet, changing amount, saving — correct value persisted (Test 2)
3. **New gig create with pay**: no regression on the INSERT path (Test 3)
4. **Rehearsal save**: no regression (Test 5)
5. **Financials dashboard**: no duplicate `gig_pay` entries visible after any save sequence (Test 6)
6. **No other financial entry methods affected**: `insertEntry`, `updateEntry`, `deleteEntry` paths unchanged — spot-check one manual financial entry create and edit

---

## Rollout / Migration Strategy
No migration. No edge function deployment. Client-only change ships with the next
standard Flutter build.

---

## Out of Scope
- ViewGigDrawer / gig tap routing (fixed on `bug/wire-view-gig-drawer-to-gig-tap`)
- Currency formatting
- Navigate button styling
- Seeding `existingEntryId` at editor open time (fixing the repository is the correct
  layer; changing the editor would add an unnecessary async fetch on every gig open)
- Improving error message specificity for constraint violations in `classifyError`
  (separate concern; the fix eliminates the error)
