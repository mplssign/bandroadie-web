# QA Report

**Feature Slug:** `bug/restore-fails-after-band-deletion`
**QA Date:** 2026-06-07
**Branch:** `bug/restore-fails-after-band-deletion`
**Architect Plan:** `docs/features/bug-restore-fails-after-band-deletion/ARCHITECT_PLAN.md`
**Engineer Report:** `docs/features/bug-restore-fails-after-band-deletion/ENGINEER_REPORT.md`

---

## Final Verdict

**APPROVED**

All Tier 1 pre-deployment SQL checks passed against the live database. All code
changes were independently verified from `git diff` and match the Architect plan
exactly. `flutter analyze` passes with zero errors and zero new warnings across the
full workspace. Scope discipline is confirmed. Tier 2 manual app testing could not
be performed in this environment (explicitly noted below); however, code-path
analysis confirms the root causes are correctly addressed.

---

## Phase 1 — Workspace State

| Check                                        | Result                                                                                                                                                     |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch                                       | `bug/restore-fails-after-band-deletion` ✓                                                                                                                  |
| Working tree state                           | Two modified files (`data_backup_service.dart`, `band_form_screen.dart`), one untracked directory (`docs/features/bug-restore-fails-after-band-deletion/`) |
| Feature slugs match (plan ↔ report ↔ branch) | ✓                                                                                                                                                          |

The working tree is in a reviewable state. The Engineer's changes are uncommitted
(working tree modifications, not staged). The untracked `docs/` directory is
expected (plan and report files).

---

## Phase 2 — Tier 1 Pre-Deployment SQL Checks

All five queries were run directly against the live linked Supabase project using
`supabase db query --linked`. Results are actual output — not inferred.

### Test 1 — `gig_responses` INSERT RLS requires `user_id = auth.uid()`

**Expected:** At least one active INSERT policy with `user_id = auth.uid()` in
`with_check`.

**Actual result (live DB):**

| policyname                              | cmd    | with_check (summary)                                                                         |
| --------------------------------------- | ------ | -------------------------------------------------------------------------------------------- |
| `Band members can create gig responses` | INSERT | `(user_id = auth.uid()) AND (EXISTS (... bm.user_id = auth.uid() AND bm.status = 'active'))` |
| `gig_responses_insert_own`              | INSERT | `(user_id = auth.uid()) AND (EXISTS (... is_band_member(g.band_id)))`                        |

**Verdict: PASS** — both active INSERT policies require `user_id = auth.uid()`.
The `gig_responses` filter in the fix is confirmed necessary and correct.

---

### Test 2 — `block_dates` INSERT RLS requires `user_id = auth.uid()`

**Expected:** `block_dates_insert_own` with `user_id = auth.uid()` in `with_check`.

**Actual result (live DB):**

| policyname               | cmd    | with_check                                             |
| ------------------------ | ------ | ------------------------------------------------------ |
| `block_dates_insert_own` | INSERT | `(is_band_member(band_id) AND (user_id = auth.uid()))` |

**Verdict: PASS** — INSERT policy confirmed; defensive filter is justified.

---

### Test 3 — `delete_band` explicitly deletes `gig_responses` but not `block_dates` or `rehearsals`

**Expected:** `deletes_gig_responses = true`, `deletes_block_dates = false`,
`deletes_rehearsals = false`.

**Actual result (live DB):**

| deletes_gig_responses | deletes_block_dates | deletes_rehearsals |
| --------------------- | ------------------- | ------------------ |
| `true`                | `false`             | `false`            |

**Verdict: PASS** — Confirms the Architect's table of post-deletion INSERT vs UPDATE
paths. After `delete_band`, all `gig_responses` rows are gone (INSERT on restore),
while `block_dates` rows remain orphaned (UPDATE on restore in normal case).

---

### Test 4 — `is_band_member` is `STABLE`

**Expected:** `provolatile = 's'` (STABLE — uses command-start snapshot, cannot see
intra-statement inserts).

**Actual result (live DB):**

| proname          | provolatile |
| ---------------- | ----------- |
| `is_band_member` | `s`         |

**Verdict: PASS** — Confirms the latent multi-member `band_members` issue described
in Architect §18 is real: `is_band_member` cannot see the admin's own newly-inserted
`band_members` row during the same statement's evaluation of other members' rows.
This is documented as out of scope per §18 and is not addressed by this fix.

---

### Test 5 — `bands` INSERT policy checks only `created_by`

**Expected:** `with_check = '(created_by = auth.uid())'`; no `band_members`
reference.

**Actual result (live DB):**

| policyname                   | cmd    | with_check                  |
| ---------------------------- | ------ | --------------------------- |
| `bands: insert own`          | INSERT | `(created_by = auth.uid())` |
| `bands_insert_authenticated` | INSERT | `(created_by = auth.uid())` |

**Verdict: PASS** — No `band_members` join in the `bands` INSERT policy. Step 1
of `_restoreBandData` succeeds as long as `band.created_by == auth.uid()`, which is
correct for the scenario where Tony restores his own backup.

---

## Phase 3 — Independent Diff Verification

All diffs were obtained via `git diff` — not taken from the Engineer's report.

### Files modified (confirmed via `git diff --name-only`)

```
lib/features/bands/band_form_screen.dart
lib/features/settings/data_backup_service.dart
```

Exactly two files. No other files modified. No migrations. No new files created.
No `pubspec.yaml` changes.

---

### `data_backup_service.dart` — diff verified

**1. `supabase_flutter` import addition (line 5):**

```diff
+import 'package:supabase_flutter/supabase_flutter.dart';
```

Confirmed present at line 5, correctly placed in alphabetical import order.

**Import justification independently verified:** `lib/app/services/supabase_client.dart`
imports `package:supabase_flutter/supabase_flutter.dart` but does not re-export it.
In Dart, a library import is not automatically re-exported to importers of that
library. `data_backup_service.dart` imports `supabase_client.dart` but cannot access
`PostgrestException` from that transitive import. The direct import is necessary.
The Engineer's deviation from the plan's import note is justified; the plan's premise
("already present") was factually incorrect. This is confirmed — not merely accepted
from the Engineer's assertion.

**2. `gig_responses` filter (step 10):**

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

Confirmed present. Filter correctly compares `r['user_id'] == userId` (string
equality; `userId` is the restoring user's UID passed in by `importBandData`).
Matches the Architect plan's Task 1 exactly (character-for-character).

**3. `block_dates` filter (step 12):**

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

Confirmed present. Filter correctly compares `r['user_id'] == userId`. Matches
the Architect plan's Task 2 exactly.

**4. `PostgrestException` → `DataBackupException` wrap:**

```dart
} on PostgrestException catch (e) {
  throw DataBackupException('Database error during restore: ${e.message}');
}
```

Confirmed present at the end of the `try` block wrapping all 12 steps. The wrap
correctly uses `e.message` (PostgrestException's error message field), not
`e.toString()`. Matches the Architect plan's Task 3 exactly.

**5. Steps 1–9 and 11 unchanged:**

Confirmed via diff review. Steps 1–9 and 11 are identical to the pre-fix version;
only their indentation changed (from no indentation to one level of `try` block
indentation). No logic changes.

---

### `band_form_screen.dart` — diff verified

```diff
-    if (mounted) _showErrorSnackBar('Restore failed. Please try again.');
+    if (mounted) {
+      final msg = e.toString().replaceFirst('Exception: ', '');
+      _showErrorSnackBar('Restore failed: $msg');
+    }
```

Confirmed present at the `catch (e)` block in `_performImport`. The `mounted` guard
is preserved. The `replaceFirst('Exception: ', '')` strips the Dart exception prefix
for a cleaner user-facing message. Matches the Architect plan's Task 4 exactly.

The diff is exactly one hunk in `band_form_screen.dart`; no other methods in this
file were touched.

---

## Phase 4 — Scope Discipline

### Off-limits methods: whitespace-only changes confirmed

The Engineer's report discloses that `dart format` reformatted `_buildBandExport`
and `_upsertRows` in `data_backup_service.dart`. These methods are listed as
off-limits in plan §11. The diff was reviewed independently:

**`_buildBandExport` (diff hunks at lines ~159–215):**

The diff shows line-length reformatting only:

- Multi-line method chains were split or consolidated differently (e.g.,
  `final band = await supabase.from('bands').select()...` moving from a single long
  line to a two-line split).
- No variable names, method calls, logic conditions, or return values were changed.
- All Supabase query chains are identical in semantics.

**Whitespace-only: CONFIRMED. No logic change.**

**`_upsertRows` (diff hunk at line ~350):**

```diff
-    final data =
-        rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
+    final data = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
```

Two lines consolidated to one. Semantically identical.

**Whitespace-only: CONFIRMED. No logic change.**

Per the session prompt, Tony has already reviewed and accepted these cosmetic
reformats. This QA confirms independently that they are indeed cosmetic.

---

## Phase 5 — `flutter analyze`

Both scoped and full-workspace runs were performed.

```
# Scoped (2 changed files)
Analyzing 2 items...
No issues found! (ran in 2.5s)

# Full workspace
Analyzing bandroadie...
No issues found! (ran in 3.6s)
```

**Result: PASS — zero errors, zero new warnings.**

---

## Phase 6 — Tier 2 Manual Verification

**I did not run the Flutter app.** No live device or simulator session is available
in this environment. The following Tier 2 tests from §15 were **not** executed:

| Test                                                                     | Status       | Reason                                                        |
| ------------------------------------------------------------------------ | ------------ | ------------------------------------------------------------- |
| POST-DEPLOY TEST 1 — Restore after deletion (multi-user `gig_responses`) | **UNTESTED** | Requires live app session with a multi-member test band       |
| POST-DEPLOY TEST 2 — Regression: restore when band still exists          | **UNTESTED** | Requires live app session                                     |
| POST-DEPLOY TEST 3 — Error surfacing (malformed backup)                  | **UNTESTED** | Requires live app session                                     |
| POST-DEPLOY TEST 4 — Row count SQL checks post-restore                   | **UNTESTED** | Requires POST-DEPLOY TEST 1 to establish a restored band UUID |

I do not claim these tests passed. They were not run.

**Code-path analysis in lieu of runtime testing:**

For POST-DEPLOY TEST 1 (primary failure path):

The root cause chain is:

1. `delete_band` deletes all `gig_responses` for the band (confirmed via Test 3 SQL).
2. On restore, all `gig_responses` rows from the backup are INSERTs (no existing rows
   to conflict with).
3. Both active INSERT policies require `user_id = auth.uid()` (confirmed via Test 1
   SQL).
4. Without the fix: rows with other members' `user_id` values fail with `42501`.
5. With the fix: those rows are filtered out before `_upsertRows`. Only the restoring
   admin's own `gig_responses` rows (where `user_id == userId`) are passed to
   `_upsertRows`. The INSERT policy check passes for all rows in the filtered list.

The fix correctly addresses the root cause. Code-path analysis only — not runtime
confirmed.

For POST-DEPLOY TEST 2 (regression, existing band):

The gig_responses UPDATE policies (`Users can update their own gig responses` and
`gig_responses_update_own`) were queried from the live DB. Both require
`user_id = auth.uid()` in their USING clause. This is an additional observation
beyond what the Architect plan explicitly noted: for the existing-band restore path,
other members' gig_responses would have been invisible to the UPDATE (RLS USING
clause hides rows where `user_id != auth.uid()`), resulting in a silent no-op for
those rows rather than a successful update. The fix filters those rows out before
the upsert, producing the same observable outcome. No regression is introduced;
the fix can only improve behavior on this path.

This observation does not block approval. It is noted for completeness.

---

## Phase 7 — §16 QA Regression Areas Checklist

### Primary — restore after deletion with multi-user `gig_responses`

- Root cause addressed in code: **YES** (filter confirmed in diff, RLS policy
  confirmed via SQL)
- Runtime verified: **NO** — untested (no live app session available)
- Risk: LOW — code-path analysis is conclusive for the described failure mode

### Regression — restore when source band still exists

- No behavioural regression introduced: **YES** (code-path analysis; filter
  silently drops rows that would have been RLS-hidden on UPDATE anyway)
- Runtime verified: **NO** — untested

### Error surfacing

- `DataBackupException` surfaces via existing `on DataBackupException catch (e)`
  handler (unchanged): **YES**
- Fallback `catch (e)` now surfaces real error message: **YES** (confirmed in diff)
- Runtime verified: **NO** — untested

### Block-out dates defensive path

- Filter applied before `_upsertRows('block_dates', ...)`: **YES** (confirmed in
  diff)
- Covers INSERT edge case (rows deleted between export and restore): **YES**
  (code-path analysis)
- Runtime verified (manual DB row deletion + restore): **NO** — untested

### Multi-band safety/UX note

- Architect §16 asks QA to document the result of restoring Band A's backup into
  Band B's settings screen.
- This test was **not performed** — no live app session available.
- This item is explicitly noted in the Architect plan as "not a blocking issue for
  this fix but should be noted." No action is required to block this fix; the concern
  is pre-existing and out of scope per §18.

---

## Phase 8 — Database Safety

No database migrations were introduced. No RLS policies were changed. No RPC
function signatures were changed. No new tables were created or modified.

**Database safety: changes are Dart-only. No database impact.**

---

## Phase 9 — Guardrails Compliance

| Guardrail                                              | Status                                                                                            |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Initialization order unchanged                         | ✓ — `main.dart` not touched                                                                       |
| Config: no new config loaders or hardcoded credentials | ✓                                                                                                 |
| Supabase safety: no RLS bypass from client             | ✓ — filter reduces scope, does not bypass                                                         |
| No `setState` after async gap without `mounted` guard  | ✓ — `_performImport` `mounted` guard preserved                                                    |
| Disposal: no new controllers or focus nodes            | ✓                                                                                                 |
| No new dependencies (pubspec.yaml unchanged)           | ✓ — `supabase_flutter` is a direct import of an existing transitive dependency, not a new package |
| Modify only Architect-approved files                   | ✓                                                                                                 |
| No opportunistic refactors                             | ✓                                                                                                 |
| No symbolic renames                                    | ✓                                                                                                 |

---

## Phase 10 — Diff Safety Review

| Check                                                  | Result                                                                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Secrets or API keys                                    | None found                                                                                                               |
| Environment variable changes                           | None                                                                                                                     |
| Debug artifacts (`print`, TODO hacks, temporary flags) | None introduced. Existing `debugPrint('[Restore] Unexpected error: $e')` was already present and is preserved unchanged. |
| Test scaffolding in production code                    | None                                                                                                                     |
| Accidental file deletions                              | None                                                                                                                     |

---

## Summary

| Verification Item                            | Method                                         | Result                  |
| -------------------------------------------- | ---------------------------------------------- | ----------------------- |
| Branch state                                 | `git branch --show-current` + `git status`     | PASS                    |
| Files modified                               | `git diff --name-only`                         | PASS — exactly 2 files  |
| `gig_responses` filter present and correct   | `git diff` code review                         | PASS                    |
| `block_dates` filter present and correct     | `git diff` code review                         | PASS                    |
| `PostgrestException` wrap present            | `git diff` code review                         | PASS                    |
| `_performImport` catch-block updated         | `git diff` code review                         | PASS                    |
| `supabase_flutter` import justified          | Examined `supabase_client.dart` for re-exports | PASS — import necessary |
| `_buildBandExport` whitespace-only           | `git diff` review                              | PASS — no logic changes |
| `_upsertRows` whitespace-only                | `git diff` review                              | PASS — no logic changes |
| Tier 1 Test 1: `gig_responses` INSERT RLS    | Live DB query                                  | PASS                    |
| Tier 1 Test 2: `block_dates` INSERT RLS      | Live DB query                                  | PASS                    |
| Tier 1 Test 3: `delete_band` behavior        | Live DB query                                  | PASS                    |
| Tier 1 Test 4: `is_band_member` STABLE       | Live DB query                                  | PASS                    |
| Tier 1 Test 5: `bands` INSERT policy         | Live DB query                                  | PASS                    |
| `flutter analyze` (scoped)                   | CLI                                            | PASS — 0 issues         |
| `flutter analyze` (full workspace)           | CLI                                            | PASS — 0 issues         |
| Guardrails compliance                        | Code review                                    | PASS                    |
| Diff safety (no secrets, no debug artifacts) | Code review                                    | PASS                    |
| Tier 2 POST-DEPLOY TEST 1                    | N/A — no live app                              | **UNTESTED**            |
| Tier 2 POST-DEPLOY TEST 2                    | N/A — no live app                              | **UNTESTED**            |
| Tier 2 POST-DEPLOY TEST 3                    | N/A — no live app                              | **UNTESTED**            |
| Tier 2 POST-DEPLOY TEST 4                    | N/A — no live app                              | **UNTESTED**            |
| §16 multi-band safety UX test                | N/A — no live app                              | **UNTESTED**            |

---

## Outstanding / Follow-On Items

1. **Tier 2 manual testing (untested — not a blocker):** The four Tier 2 app-level
   tests (§15) and the multi-band UX test (§16) were not performed. These require
   a live running Flutter app session with a multi-member test band. The code-path
   analysis is conclusive for the primary failure mode, but live device confirmation
   is recommended before or after deploying to production.

2. **Latent multi-member `band_members` issue (out of scope per §18):**
   `is_band_member` is confirmed STABLE (Test 4). The `band_members` batch upsert
   at step 2 of `_restoreBandData` remains potentially broken for admins restoring
   backups that contained multiple active members. This is explicitly deferred per
   §18. No action required for this fix; flagged for follow-on.

3. **`gig_responses` UPDATE RLS observation (informational, not a blocker):**
   Additional DB query (beyond the five required) confirmed that the `gig_responses`
   UPDATE policies also restrict by `user_id = auth.uid()`. For the existing-band
   restore path, other members' rows would have been silently skipped by RLS on
   UPDATE even without the fix. The filter is therefore safe and cannot introduce
   a regression on that path.
