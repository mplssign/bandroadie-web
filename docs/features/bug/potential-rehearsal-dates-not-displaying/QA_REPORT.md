# QA Report: Potential Rehearsal Dates Not Displaying

**Branch:** `bug/potential-rehearsal-dates-not-displaying`  
**QA Date:** 2026-05-22 (re-review)  
**Result:** ✅ APPROVED  
**Validated by:** Code-path analysis and `git` history review. No runtime testing performed.

---

## Re-Review Context

This is a re-review following a prior **REQUIRES CHANGES** result. The three blocking findings from the previous QA pass were:

| Prior Finding                                | Resolution Claimed   |
| -------------------------------------------- | -------------------- |
| No commits on branch                         | 1 commit now present |
| `assets/images/phone_hands.png` out-of-scope | Reverted             |
| Engineer report inaccurate re Fix A          | Corrected            |

This review confirms or denies each resolution and validates the committed change.

---

## Phase 1 — Workspace State

```
Branch: bug/potential-rehearsal-dates-not-displaying  ✓
```

```
git log --oneline main..HEAD:
3bd0d0c fix(rehearsals): add start_time to _rehearsalSelectClause for calendar path
```

```
git status:
On branch bug/potential-rehearsal-dates-not-displaying
Untracked files:
  docs/features/bug/potential-rehearsal-availability-nav/
  docs/features/bug/potential-rehearsal-dates-not-displaying/

nothing added to commit but untracked files present
```

**Branch is reviewable.** 1 commit on branch. Working tree is clean (untracked docs directories are not source changes and are excluded from scope).

### Prior Blocker 1 — No commits on branch

**RESOLVED.** Commit `3bd0d0c` is present.

Commit message: `fix(rehearsals): add start_time to _rehearsalSelectClause for calendar path`  
Format compliance: `fix(scope): short description` — ✓ matches GUARDRAILS §10 convention.

---

## Phase 2 — Document Validation

| Check                                          | Result                                           |
| ---------------------------------------------- | ------------------------------------------------ |
| Feature slug matches branch name               | ✓ `bug/potential-rehearsal-dates-not-displaying` |
| ARCHITECT_PLAN.md exists at correct slug path  | ✓                                                |
| ENGINEER_REPORT.md exists at correct slug path | ✓                                                |
| Both documents refer to the same feature       | ✓                                                |

---

## Phase 3 — Validation Baseline (from Architect Plan)

- **Problem:** `RehearsalCard` never received `additionalDates` (home screen); `_rehearsalSelectClause` missing `start_time` (calendar edit path)
- **Expected files modified:** `lib/features/home/home_tab_content.dart` and `lib/features/rehearsals/rehearsal_repository.dart` — no others
- **Database changes:** None — migration `20260521000000` pre-existing and correct
- **Off-limits:** All files not in the approved list
- **QA regression areas:** Potential rehearsal card display, calendar edit path for multi-date rehearsals, gig flows (must be unaffected)

---

## Phase 4 — Engineer Implementation Review

### git diff main (full)

```diff
diff --git a/lib/features/rehearsals/rehearsal_repository.dart b/lib/features/rehearsals/rehearsal_repository.dart
index 14c1ab6..a5f7c4e 100644
--- a/lib/features/rehearsals/rehearsal_repository.dart
+++ b/lib/features/rehearsals/rehearsal_repository.dart
@@ -24,6 +24,7 @@ const _rehearsalSelectClause = '''
     id,
     rehearsal_id,
     date,
+    start_time,
     created_at,
     updated_at
   )
```

That is the entirety of the diff. Exactly one file changed. Exactly one line added.

### Prior Blocker 2 — `assets/images/phone_hands.png` out-of-scope

**RESOLVED.** `git diff main` shows no change to `assets/images/phone_hands.png`. The file exists in both `main` and `HEAD` at identical content (committed to `main` in a prior release). No out-of-scope binary change is present on this branch.

### Prior Blocker 3 — Engineer report inaccurate re Fix A

**RESOLVED.** The corrected Engineer report accurately states:

- Fix A (`additionalDates: rehearsal.additionalDates` wiring) was already present in `main` before this branch was created.
- It was applied in commit `2b2111b` ("release: v1.2.16+156") — confirmed by `git show 2b2111b -- lib/features/home/home_tab_content.dart`.
- No change to `home_tab_content.dart` was made on this branch.
- The "Files Modified" table in the Engineer report lists only `rehearsal_repository.dart`. Accurate.

### Fix A — `lib/features/home/home_tab_content.dart`

Not changed on this branch. Present and correct in the codebase.

Confirmed in code at `home_tab_content.dart` line 1062:

```dart
child: RehearsalCard(
  rehearsal: rehearsal,
  setlistName: setlistName,
  bandTimezone: bandTimezone,
  additionalDates: rehearsal.additionalDates,   // ← present and correct
  perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
  ...
)
```

Stale comment (`// additionalDates defaults to [] until Rehearsal model is extended`) confirmed absent.

### Fix B — `lib/features/rehearsals/rehearsal_repository.dart`

**Committed in `3bd0d0c`. Correctly applied.**

`start_time` was added between `date` and `created_at` in `_rehearsalSelectClause` (line 27):

```dart
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    start_time,      // ← added
    created_at,
    updated_at
  )
''';
```

Column order matches the reference implementation in `events_repository.dart` line 512 exactly:

```dart
.select('*, rehearsal_dates(id, rehearsal_id, date, start_time, created_at, updated_at)')
```

The clause is used by `fetchRehearsalsForBand` via `.select(_rehearsalSelectClause)` at lines 49, 70, and 112. All three call sites are updated automatically by the constant change.

---

## Phase 5 — Completeness Check

| Architect Task                                                                       | Status                                                                       |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| Fix A: Add `additionalDates: rehearsal.additionalDates` to `RehearsalCard(...)` call | ✓ Present in codebase (applied to `main` in `2b2111b` before branch was cut) |
| Fix A: Remove stale comment                                                          | ✓ Present in codebase (same commit)                                          |
| Fix B: Add `start_time` to `_rehearsalSelectClause`                                  | ✓ Committed in `3bd0d0c`                                                     |
| No other files modified                                                              | ✓ Confirmed — `git diff main` shows exactly one file                         |
| No database changes                                                                  | ✓ Confirmed — no migrations changed on this branch                           |

All Architect-required tasks are complete.

---

## Phase 6 — Behavior Verification

**Validation method: Code-path analysis only. No runtime testing performed.**

### Root Cause A — Home screen multi-date display

Code path:

```
bandFullStateProvider (RPC get_band_full_state)
  └─ rehearsalProvider.potentialRehearsals  [Rehearsal.additionalDates populated ✓]
       └─ home_tab_content._buildHorizontalPotentialEvents()
            └─ RehearsalCard(additionalDates: rehearsal.additionalDates)  ← ✓ WIRED
```

`RehearsalCard` has a complete multi-date implementation: `_sortedDates`, date-navigation arrows, "Multiple Dates" chip suffix, and per-date YES/NO responses. With `additionalDates` now supplied, these will activate for rehearsals where `additionalDates.isNotEmpty`. For rehearsals with no additional dates, `additionalDates` is `const []`, `isMultiDate` is false, and single-date display is unchanged.

Root cause A is addressed. Validated via code-path analysis.

### Root Cause B — Calendar edit path per-date start times

Code path after Fix B:

```
RehearsalRepository.fetchRehearsalsForBand()  [_rehearsalSelectClause now includes start_time]
  └─ CalendarController._loadEventsForBand()
       └─ CalendarEvent.fromRehearsal(rehearsal)  [RehearsalDate.startTime now populated ✓]
            └─ AddEditEventBottomSheet: per-date times shown correctly
```

`RehearsalDate.fromJson` reads `start_time` as `String?` (nullable). Rows created before the migration have `start_time = null`; the model handles this gracefully by falling back to the parent rehearsal's start time in `EventFormData.fromRehearsal`. Correct behaviour.

Root cause B is addressed. Validated via code-path analysis.

### Root Cause C — `CalendarEvent.isPotentialGig` naming inconsistency

Architect-documented as out of scope. No change made. Confirmed not touched.

---

## Phase 7 — Regression Check

| System                                      | Risk | Notes                                                                                                               |
| ------------------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------- |
| Potential Rehearsal card (home screen)      | LOW  | Fix A functional; `RehearsalCard` multi-date implementation was pre-existing and complete                           |
| Calendar edit flow for potential rehearsals | LOW  | Fix B adds a column to an existing select clause; `RehearsalDate.fromJson` handles nullable `start_time` gracefully |
| Regular (non-potential) rehearsal cards     | LOW  | `additionalDates` defaults to `const []`; `isMultiDate` is false; no visual change for non-potential rehearsals     |
| `fetchRehearsalsForBand` callers            | LOW  | Adding a column to a select clause is additive and non-breaking                                                     |
| Gigs                                        | NONE | No gig code changed                                                                                                 |
| Setlists / Catalog                          | NONE | No setlist code changed                                                                                             |
| Auth / Session                              | NONE | No auth code changed                                                                                                |
| Initialization order                        | NONE | Not touched                                                                                                         |
| Supabase RPC signatures                     | NONE | No RPC calls added or modified; select clause is a REST query parameter                                             |

**Overall regression risk: LOW.** Both changes are additive and minimal.

---

## Phase 8 — Database Safety

**Database safety: not applicable to changes on this branch.**

No migrations were created or modified. The `rehearsal_dates` table schema is correct as-is; `start_time TEXT` was added in migration `20260521000000_add_start_time_to_date_tables.sql`, which predates this branch. Adding `start_time` to the select clause is safe because the column already exists and is nullable.

---

## Phase 9 — Baseline Validation

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 3.7s)
```

✓ Zero analyzer errors. Zero new warnings.

No tests were run. The Architect plan does not require tests. The Engineer report does not claim tests were run. The changed file (`rehearsal_repository.dart`) has no existing test coverage.

---

## Phase 10 — Diff Safety Review

| Check                                   | Result |
| --------------------------------------- | ------ |
| Secrets or API keys                     | None   |
| Hardcoded credentials                   | None   |
| Debug artifacts (`print`, `debugPrint`) | None   |
| TODO/HACK/FIXME introduced              | None   |
| Test scaffolding in production code     | None   |
| Accidental file deletions               | None   |
| Out-of-scope env/config changes         | None   |
| Out-of-scope binary or asset changes    | None   |

---

## Findings Summary

| #   | Severity | Finding                                                                                                                                                                                                |
| --- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | RESOLVED | No commits on branch — **1 commit now present** (`3bd0d0c`)                                                                                                                                            |
| 2   | RESOLVED | `assets/images/phone_hands.png` out-of-scope — **not in `git diff main`; revert confirmed**                                                                                                            |
| 3   | RESOLVED | Engineer report inaccurate re Fix A — **corrected; report now accurately reflects that Fix A was already in `main`**                                                                                   |
| 4   | INFO     | Fix A was applied to `main` directly in a release commit (`2b2111b`) rather than through a dedicated branch/PR workflow (GUARDRAILS §10). Historical process note — not actionable within this branch. |

No new findings.

---

## Verdict

**✅ APPROVED**

All three prior blocking findings are resolved. The single committed change (`start_time` added to `_rehearsalSelectClause`) is correct, minimal, and safe. The full data chain for both root causes is sound in the current codebase. No out-of-scope changes are present. Analyzer passes clean. The branch is ready to push and open a PR per GUARDRAILS §10–11.
