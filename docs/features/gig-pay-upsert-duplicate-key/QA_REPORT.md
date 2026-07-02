# QA Report

## Feature Slug
`gig-pay-upsert-duplicate-key`

## Feature Title
Fix gig-pay upsert duplicate key error on event editor save

## Final Verdict
**REQUIRES CHANGES** — pending manual Tier 2 on-device verification (see below). All static checks pass. The implementation is correct and the code is ready to ship; this verdict is held open solely because the financial write path requires runtime testing before approval can be granted per QA protocol.

---

## Validation Summary

All static checks pass: diff matches the Architect plan exactly (including the deliberate `.eq('band_id', bandId)` improvement on the SELECT), only one source file was modified, all off-limits files are untouched, no migrations were added, `flutter analyze` shows exactly 2 errors (both pre-existing, unrelated), no secrets or debug artifacts were introduced, and the RLS query shape is consistent with other safe patterns in the same file. Runtime on-device verification (Tier 2 tests 1–6 from the Architect plan) could not be executed by QA and must be completed by Tony before this branch can be merged.

---

## Architect Scope Review

- **Scope adherence:** compliant
- **Files modified:** as expected — `lib/features/financials/financial_entry_repository.dart` only
- **Files off-limits:** not touched — confirmed via `git diff main` against `event_editor_drawer.dart`, `financial_entry.dart`, `event_permission_helper.dart`, and `supabase/migrations/`. All returned empty output.

### All files changed vs main (`git diff main --name-only`):
```
docs/features/gig-pay-upsert-duplicate-key/ARCHITECT_PLAN.md   ← docs only
docs/features/gig-pay-upsert-duplicate-key/ENGINEER_REPORT.md  ← docs only
lib/features/financials/financial_entry_repository.dart         ← only source file
```
The two docs files are expected (added during planning/engineering). No unexpected files.

---

## Completeness Check

- **All Architect tasks implemented:** yes
- **Missing tasks:** none

### Task-by-task:

**Task 1** — Confirmed in code (`financial_entry_repository.dart:93–124`). The bare INSERT else-branch has been replaced with the check-then-write pattern:

```dart
} else {
  // No existingEntryId — query for an existing gig_pay row before inserting
  // to avoid violating the uniq_gig_pay_entry unique partial index.
  final existingRow = await supabase
      .from('financial_entries')
      .select('id')
      .eq('gig_id', gigId)
      .eq('entry_type', 'gig_pay')
      .eq('band_id', bandId)       // ← deliberate improvement, confirmed present
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

This matches the Architect plan's Task 1 code block verbatim. Specifically confirmed:
- SELECT filters on `gig_id` + `entry_type` + `band_id` ✓
- `.eq('band_id', bandId)` present on SELECT (plan's deliberate improvement over `feat/gig-address-field` reference) ✓
- UPDATE uses `existingRow['id'] as String` + `.eq('band_id', bandId)` ✓
- `'updated_at': DateTime.now().toIso8601String()` present in UPDATE payload ✓
- INSERT path (no existing row) is unchanged ✓
- No other methods in the file were modified ✓

**Task 2** — `flutter analyze` run independently by QA. Result: 2 errors (see Analyzer Results). Zero new errors/warnings from this change.

**Task 3** — `git diff --stat` equivalent via `git diff main --name-only` confirms exactly one source file changed.

---

## Behavior Verification

- **Validation method:** code-path analysis only
- **Result:** matches expected — the root cause (bare INSERT with null `existingEntryId` violating `uniq_gig_pay_entry`) is addressed. The else-branch now performs a SELECT before deciding whether to UPDATE or INSERT, making `upsertGigPayEntry` genuinely idempotent regardless of how `_gigPayDetails` was seeded.

Runtime behavior has **not** been exercised. See Manual Verification section.

---

## Regression Check

- **Risk level:** LOW (per Architect plan; QA concurs)
- **Systems reviewed:** Gigs, Financials write path (upsertGigPayEntry), Rehearsals, Financials dashboard, Auth/Session, Routing
- **Regressions found:** none (code-path analysis only)

The existing `existingEntryId != null` UPDATE branch (lines 80–92) is untouched. The INSERT path within the new else-block is the same SQL as before. The only net change is one extra SELECT round-trip in the case where `existingEntryId == null`.

`upsertGigPayEntry` is not called for rehearsals — no rehearsal regression risk.

`insertEntry`, `updateEntry`, and `deleteEntry` are unchanged — financials dashboard write paths unaffected.

---

## Database Safety

**No migrations added.** Confirmed via `git diff main -- supabase/migrations/` returning empty output.

**RLS safety — assessed via code-path analysis:**

The new SELECT query (`financial_entries` filtered by `gig_id` + `entry_type` + `band_id`) matches the shape of other RLS-safe reads already present in this file. The `financial_entries_select` RLS policy permits reads for authenticated band members. Filtering on `band_id` in the SELECT provides defense-in-depth even though RLS would already constrain visibility to the caller's band. The new UPDATE path adds `.eq('band_id', bandId)` as a second predicate alongside `.eq('id', existingRow['id'])`, which matches the existing UPDATE pattern in the `existingEntryId != null` branch.

No privilege escalation, no destructive behavior, no RLS self-reference, no partial-parameter RPC calls. The `trg_sync_gig_pay` trigger will fire on the new UPDATE path as it did before — correct behavior.

---

## Analyzer Results

Command: `flutter analyze`
```
Analyzing bandroadie...

  error • Target of URI doesn't exist: 'gig_notes_sheet.dart' • lib/features/gigs/widgets/view_gig_drawer.dart:13:8 • uri_does_not_exist
  error • Undefined name 'GigNotesSheet' • lib/features/gigs/widgets/view_gig_drawer.dart:245:36 • undefined_identifier

2 issues found. (ran in 5.5s)
```

**Both errors are pre-existing and unrelated to this diff.** They exist in `view_gig_drawer.dart` due to an import of `gig_notes_sheet.dart` that has not yet been merged from the separate `bug/wire-view-gig-drawer-to-gig-tap` branch. These errors are present on `main` itself and are confirmed pre-existing (Engineer verified via `git stash` test; QA independently confirmed via `git diff main --name-only` showing `view_gig_drawer.dart` is not in the diff for this branch).

**Zero new errors or warnings introduced by this implementation.**

---

## Manual Verification — Outstanding (Tier 2 Required)

This fix touches a financial write path. Static analysis is not sufficient for approval. Tony must run all 6 Tier 2 tests from the Architect plan before this branch can be merged:

**Test 1 — Primary bug fix (core regression):**
1. Open any confirmed gig that already shows a pay amount.
2. Change any non-pay field (e.g., venue name) without opening the pay sheet.
3. Tap Save / Update.
4. **Expected:** save succeeds, "Gig updated" snackbar appears, no error dialog.

**Test 2 — Pay field edit round-trip:**
1. Open a confirmed gig with existing pay.
2. Tap the pay field, change the amount, close the pay sheet.
3. Tap Save.
4. **Expected:** save succeeds, new amount is reflected in ViewGigDrawer and Financials tab.

**Test 3 — New gig with pay (create path, no existing row — INSERT branch):**
1. Create a new confirmed gig, add a pay amount.
2. Tap Save.
3. **Expected:** gig created, pay entry created, Financials dashboard reflects the entry.

**Test 4 — New gig without pay:**
1. Create a confirmed gig without touching the pay field.
2. Tap Save.
3. **Expected:** save succeeds, no `financial_entries` row created for this gig.

**Test 5 — Rehearsal save (must not regress):**
1. Create or edit a rehearsal.
2. Tap Save.
3. **Expected:** no error. (`upsertGigPayEntry` is never called for rehearsals.)

**Test 6 — Financials dashboard duplicate-check:**
1. After Test 1 and Test 2, open the Financials tab.
2. **Expected:** only one `gig_pay` entry exists per gig, no duplicates. Amounts correct.

---

## Test Results

Not run — no unit tests cover `upsertGigPayEntry` and the Architect plan does not require `flutter test`. Tier 2 on-device tests are outstanding (see Manual Verification above).

---

## Diff Safety Review

- **Secrets:** none found
- **Debug artifacts:** none — no print statements, TODO hacks, or temporary flags
- **Unrelated changes:** none — diff is confined to the else-branch of `upsertGigPayEntry`

---

## Issues Found

### Critical (must resolve before merge)

1. **Tier 2 manual on-device tests not yet run** — This is a financial write path. All 6 Tier 2 tests listed above must pass before this branch is approved for merge. Static analysis confirms the implementation is correct; runtime confirmation is the only outstanding gate.

### Warnings

None.

### Suggestions

None.
