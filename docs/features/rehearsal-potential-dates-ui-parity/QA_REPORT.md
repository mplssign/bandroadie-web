# QA Report: Rehearsal Potential Dates UI Parity

**Feature Slug:** `rehearsal-potential-dates-ui-parity`  
**QA Run:** 2 (second pass — verifying F1–F7 fixes from Run 1)  
**QA Date:** 2026-05-22  
**Verdict:** ✅ APPROVED  
**Validation Method:** Code-path analysis only. No runtime device testing performed.

---

## Phase 1 — Workspace State

| Check        | Result                                                                  |
| ------------ | ----------------------------------------------------------------------- |
| Branch       | `feature/rehearsal-potential-dates-ui-parity` ✓ (F7 resolved)           |
| Working tree | 4 modified files (all within Architect-approved scope) + untracked docs |

Branch correction confirmed via `git branch --show-current`. The 4 modified files are unstaged but within the expected feature scope. One committed change exists on the branch from a prior merged PR (`bug/potential-rehearsal-dates-not-displaying`, commit `3bd0d0c`): it adds `start_time` to `_rehearsalSelectClause` in `rehearsal_repository.dart`. This was merged independently and is outside this feature's approved file scope — it is pre-existing and not part of this feature's implementation.

---

## Phase 2 — Documents

| Check                      | Result                                          |
| -------------------------- | ----------------------------------------------- |
| `ARCHITECT_PLAN.md` slug   | `feature/rehearsal-potential-dates-ui-parity` ✓ |
| `ENGINEER_REPORT.md` slug  | `rehearsal-potential-dates-ui-parity` ✓         |
| Both refer to same feature | ✓                                               |

---

## Phase 3 — Validation Baseline (Extracted from Architect Plan)

**Problem:** Edit Rehearsal screen with Potential ON renders a flat date list + single shared availability grid. Edit Gig shows one section per proposed date with per-date availability pills and YES/NO buttons.

**Expected behavior after fix:**

- Edit Rehearsal with Potential ON + multiple dates → one section per date, each with member availability pills and scoped YES/NO buttons.
- Single-date potential rehearsals → unchanged.
- Create mode → unchanged.
- Primary-date queries not contaminated by per-date rows.

**Approved files to modify:**

1. `lib/app/models/rehearsal_response.dart`
2. `lib/features/rehearsals/rehearsal_response_repository.dart`
3. `lib/features/events/widgets/rehearsal_form_fields.dart`
4. `lib/features/events/widgets/event_editor_drawer.dart`

**Database impact:** Not applicable (schema already complete).

**QA regression areas:** Rehearsal edit path; gig edit path (unaffected); primary-date response reads/writes; per-date response persistence on Save.

---

## Phase 4 — Engineer Implementation Review

### Files Modified (confirmed via `git diff`)

All four files in the working-tree diff are Architect-approved. No files outside the approved list were modified in this Engineer run. Minor line-wrapping reformatting (function call wrapping) in `event_editor_drawer.dart` is inconsequential.

---

## Phase 5 — Completeness Check (F1–F7 Verification)

### F1 — `fetchUserResponse`: primary-date null scoping

**Status: ✅ RESOLVED**

`.isFilter('rehearsal_date_id', null)` added after `.eq('user_id', userId)` and before `.maybeSingle()`. Confirmed in diff at line 215.

### F2 — `fetchAllMemberResponses`: primary-date null scoping

**Status: ✅ RESOLVED**

`.isFilter('rehearsal_date_id', null)` added after `.eq('rehearsal_id', rehearsalId)` in the member responses query. Confirmed in diff at line 432.

### F3 — `_performUpsert`: primary-date null scoping (3 sub-fixes)

**Status: ✅ RESOLVED**

All three sub-fixes confirmed in diff:

- `select('id')` lookup: `.isFilter('rehearsal_date_id', null)` added after `.eq('user_id', userId)` (diff line 291)
- `update(...)` call: `.isFilter('rehearsal_date_id', null)` added after `.eq('user_id', userId)` (diff line 303)
- `insert({...})` map: `'rehearsal_date_id': null` added as explicit key (diff line 313)

### F4 — `_savePerDateResponses`: branch on `_eventType`

**Status: ✅ RESOLVED**

`_savePerDateResponses()` now branches on `_eventType`:

- `EventType.rehearsal` path calls `rehearsalResponseRepositoryProvider.upsertResponseForDate` with `rehearsalId` and `rehearsalDateId` parameters.
- All other event types call `gigResponseRepositoryProvider.upsertResponseForDate` (unchanged from original).

Local variables renamed `gigId → eventId` and `gigDateId → dateId`; the `repo` local variable removed in favour of inline `ref.read(...)` calls per branch. Confirmed in diff at lines 2466–2501.

Note: `ref.read(...)` is now called inside the loop per branch. This is slightly less efficient than the previous single assignment outside the loop but is functionally identical (provider instances are stable). Not a defect.

### F5 — Rehearsal save path: calls `_savePerDateResponses()`

**Status: ✅ RESOLVED**

Per-date save block added immediately after the `potentialRehearsalResponseSummariesProvider` invalidation in the rehearsal edit path:

```dart
// Save per-date availability for multi-date potential rehearsals
if (_isPotentialGig &&
    _isMultiDate &&
    _perDateAvailability.isNotEmpty) {
  await _savePerDateResponses();
}
```

Placement confirmed by reading `event_editor_drawer.dart` lines 1295–1365. This mirrors the identical block in the gig edit path.

### F6 — Analyzer warnings (`curly_braces_in_flow_control_structures`)

**Status: ✅ RESOLVED**

The two bare `if` statements in the `availabilityState` lambda (previously at lines 402–404) now have curly braces. Confirmed in diff.

`flutter analyze` result: **No issues found.** Verified directly.

Note: `_buildPerDateSection` (new method) also contains bare `if` returns in its `availabilityState` lambda (`if (r == 'yes') return X;`). These follow the same compact single-return style present elsewhere in the codebase. `flutter analyze` does not flag them.

### F7 — Branch mismatch

**Status: ✅ RESOLVED**

Branch is `feature/rehearsal-potential-dates-ui-parity`. Confirmed via `git branch --show-current`.

---

## Phase 5 (continued) — Original Feature Gap Completeness

### Gap 1 — `RehearsalResponse` model: `rehearsalDateId` field

**Status: ✅ COMPLETE (carried forward from Run 1, unmodified)**

All four locations confirmed in diff: field declaration, constructor parameter, `fromJson`, `toJson`.

### Gap 2 — `fetchAllDateResponses` method

**Status: ✅ COMPLETE (carried forward from Run 1, unmodified)**

Method present. Queries `band_members` for active members, seeds result map keyed by `'primary'` and each `rehearsalDateId`, populates from `rehearsal_responses`. Mirrors gig equivalent correctly.

### Gap 3 — Primary-date null scoping

**Status: ✅ COMPLETE (fixed in Run 2; see F1–F3 above)**

### Gap 4 — `RehearsalFormFields` per-date parameters and new methods

**Status: ✅ COMPLETE (carried forward from Run 1; F6 curly braces fix applied in Run 2)**

Five constructor parameters and field declarations present and correctly typed. `_buildMultiDateAvailabilitySection` and `_buildPerDateSection` implemented. `isMultiDateEditMode` guard correctly limits multi-date mode to edit + existing event + `additionalDates` non-empty. Minor deviations D1–D5 remain (acknowledged, non-blocking).

### Gap 5 — `_loadPerDateAvailability` branches on `_eventType`

**Status: ✅ COMPLETE (carried forward from Run 1, unmodified)**

`EventType.gig` path unchanged. `EventType.rehearsal` path calls `rehearsalResponseRepositoryProvider.fetchAllDateResponses`. `else` branch clears loading state. `mounted` guards present on all `setState` calls.

### Gap 6 — Rehearsal save path calls `_savePerDateResponses()`

**Status: ✅ COMPLETE (fixed in Run 2; see F5 above)**

### Gap 7 — `_createRehearsalFormFields` passes per-date params

**Status: ✅ COMPLETE (carried forward from Run 1, unmodified)**

All five parameters passed: `perDateAvailability`, `isLoadingPerDateAvailability`, `existingDateIds`, `onPerDateResponseChanged`, `currentUserId`.

---

## Phase 6 — Behavior Verification

**Validation method:** Code-path analysis only.

| Acceptance Criterion                                                      | Status                                                                                          |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Edit Rehearsal (Potential ON + multiple dates) shows one section per date | ✅ `_buildMultiDateAvailabilitySection` + `isMultiDateEditMode` guard confirmed                 |
| Each section shows member availability pills                              | ✅ `ButtonGroupGrid` in `_buildPerDateSection` keyed to `perDateAvailability[dateKey]`          |
| Each section shows YES/NO buttons scoped to that date                     | ✅ `AvailabilityButton` row calls `onPerDateResponseChanged(date, isPrimaryDate, response)`     |
| Tapping YES/NO updates state                                              | ✅ `_updatePerDateResponse` in drawer updates `_perDateAvailability`                            |
| Tapping YES/NO **persists on Save** (rehearsal path)                      | ✅ Rehearsal edit path now calls `_savePerDateResponses()` after single-date upsert             |
| `_savePerDateResponses()` writes to correct repository for rehearsals     | ✅ Branches on `_eventType == EventType.rehearsal` → `rehearsalResponseRepositoryProvider`      |
| Primary-date responses not contaminated by per-date rows                  | ✅ `fetchUserResponse`, `fetchAllMemberResponses`, `_performUpsert` all scoped with null filter |
| Single-date potential rehearsals unchanged                                | ✅ `isMultiDateEditMode` guard confirmed                                                        |
| Create mode unchanged                                                     | ✅ `existingEventId == null` guard confirmed                                                    |

---

## Phase 7 — Regression Check

| System               | Risk | Finding                                                                                                                                                                            |
| -------------------- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rehearsals           | LOW  | All three null-scoping fixes applied. Save path now calls `_savePerDateResponses()`. `_loadPerDateAvailability` branches correctly. No regression detected via code-path analysis. |
| Gigs                 | LOW  | `_loadPerDateAvailability` gig path unchanged. `_savePerDateResponses` gig `else` branch unchanged. No regression detected.                                                        |
| Setlists / Catalog   | LOW  | Not touched. No regression.                                                                                                                                                        |
| Members / RBAC       | LOW  | `band_members` query in `fetchAllDateResponses` mirrors gig equivalent exactly. No permission change.                                                                              |
| Auth / Session       | LOW  | No auth changes. `supabase.auth.currentUser?.id` used safely.                                                                                                                      |
| Routing              | LOW  | Not touched.                                                                                                                                                                       |
| Database             | LOW  | No migration. Schema unchanged.                                                                                                                                                    |
| Home Tab / Dashboard | LOW  | `potentialRehearsalResponseSummariesProvider` invalidated in rehearsal edit path (unchanged).                                                                                      |

**`mounted` guard:** All `setState` calls after async gaps in `_loadPerDateAvailability` are guarded. ✓  
**`FocusNode` / controller disposal:** No new controllers added. ✓  
**`setState` after async:** Pattern unchanged from existing code. ✓

---

## Phase 8 — Database Safety

**Database safety:** Not applicable — no migrations in this change.

---

## Phase 9 — Baseline Validation

```
flutter analyze: No issues found. (ran in 4.2s)
```

Verified directly. Clean. ✓

---

## Phase 10 — Diff Safety Review

| Check                                             | Result                                                                  |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| Secrets / API keys                                | None found ✓                                                            |
| Environment variables outside scope               | None ✓                                                                  |
| Debug artifacts (`print`, TODO hacks, temp flags) | None (only structured `debugPrint` calls, mirroring existing pattern) ✓ |
| Test scaffolding in production code               | None ✓                                                                  |
| Accidental file deletions                         | None ✓                                                                  |
| Files outside approved scope modified             | None (by this Engineer run) ✓                                           |

---

## Summary of Findings

### Run 1 Blocking Findings — Resolution Status

| ID  | Severity | File                                 | Resolution Status                                                                                              |
| --- | -------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| F1  | BLOCKING | `rehearsal_response_repository.dart` | ✅ RESOLVED — `.isFilter('rehearsal_date_id', null)` added to `fetchUserResponse`                              |
| F2  | BLOCKING | `rehearsal_response_repository.dart` | ✅ RESOLVED — `.isFilter('rehearsal_date_id', null)` added to `fetchAllMemberResponses`                        |
| F3  | BLOCKING | `rehearsal_response_repository.dart` | ✅ RESOLVED — all 3 sub-fixes applied to `_performUpsert` (select lookup, update, insert)                      |
| F4  | BLOCKING | `event_editor_drawer.dart`           | ✅ RESOLVED — `_savePerDateResponses()` branches on `_eventType`; rehearsal path calls rehearsal repo          |
| F5  | BLOCKING | `event_editor_drawer.dart`           | ✅ RESOLVED — rehearsal edit save path now calls `_savePerDateResponses()` for multi-date potential rehearsals |
| F6  | BLOCKING | `rehearsal_form_fields.dart`         | ✅ RESOLVED — curly braces added to `if` statements; `flutter analyze` clean                                   |
| F7  | WORKFLOW | git                                  | ✅ RESOLVED — branch is `feature/rehearsal-potential-dates-ui-parity`                                          |

### Remaining Non-Blocking Deviations (unchanged from Run 1)

These were acknowledged as out-of-scope for Run 2. They do not affect data correctness or user safety.

| ID  | Severity | File                         | Finding                                                                                                 |
| --- | -------- | ---------------------------- | ------------------------------------------------------------------------------------------------------- |
| D1  | MINOR    | `rehearsal_form_fields.dart` | `AnimatedSize` wrapper omitted — no animation on single/multi-date mode transition (Architect Plan §C2) |
| D2  | MINOR    | `rehearsal_form_fields.dart` | Missing `SizedBox(height: Spacing.space12)` at top of `_buildMultiDateAvailabilitySection` (Plan §C3)   |
| D3  | MINOR    | `rehearsal_form_fields.dart` | `ButtonGroupGrid` in `_buildPerDateSection` missing `columns: 4, buttonHeight: 48` (Plan §C4)           |
| D4  | MINOR    | `rehearsal_form_fields.dart` | Empty members text `'No members'` instead of `'No members to notify'` (Plan §C4)                        |
| D5  | MINOR    | `rehearsal_form_fields.dart` | Date header `Text` not wrapped in `Container` with vertical padding (Plan §C4)                          |

---

## Verdict

**✅ APPROVED**

All 7 blocking findings from QA Run 1 (F1–F7) are confirmed resolved via code-path analysis. `flutter analyze` is clean. No files outside the Architect-approved list were modified by this Engineer run. No new issues introduced. The feature is safe to commit, push, and open for PR review.

Non-blocking deviations D1–D5 remain and are acknowledged. They represent minor visual differences from the Architect spec (animation, spacing, grid config, copy) but do not affect correctness or data integrity.
