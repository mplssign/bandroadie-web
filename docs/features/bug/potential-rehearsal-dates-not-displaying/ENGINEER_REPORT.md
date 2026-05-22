# Engineer Report: Potential Rehearsal Dates Not Displaying

**Branch:** `bug/potential-rehearsal-dates-not-displaying`  
**Date:** 2026-05-22  
**Status:** Complete — post-QA corrections applied

---

## Changes Made

### Fix A — `lib/features/home/home_tab_content.dart`

**Not a change made on this branch.**

`git` history confirms that `additionalDates: rehearsal.additionalDates` was wired and the stale comment was removed in commit `2b2111b` ("release: v1.2.16+156 — new splash/login branding, remove video splash"), which was merged to `main` before this branch was created. `git diff main` shows no change to this file on this branch.

The fix is correct in the current codebase and the code path is functioning as intended. It was simply already present when the branch was cut.

**Confirmed in code (`home_tab_content.dart` ~line 1065):**

```dart
RehearsalCard(
  rehearsal: rehearsal,
  setlistName: setlistName,
  bandTimezone: bandTimezone,
  additionalDates: rehearsal.additionalDates,   // ← present and correct
  perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
  ...
)
```

Stale comment (`// additionalDates defaults to [] until Rehearsal model is extended`) confirmed absent.

---

### Fix B — `lib/features/rehearsals/rehearsal_repository.dart`

`_rehearsalSelectClause` was missing `start_time` in the `rehearsal_dates` sub-select. The column was added to the `rehearsal_dates` table in migration `20260521000000_add_start_time_to_date_tables.sql` but the Dart select clause was not updated.

**Change:** Added `start_time` between `date` and `created_at` in `_rehearsalSelectClause`.

```dart
// BEFORE
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    created_at,
    updated_at
  )
''';

// AFTER
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    start_time,
    created_at,
    updated_at
  )
''';
```

---

## Validation

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 3.7s)
```

---

## Files Modified

| File                                                | Change                                         |
| --------------------------------------------------- | ---------------------------------------------- |
| `lib/features/rehearsals/rehearsal_repository.dart` | Added `start_time` to `_rehearsalSelectClause` |

`lib/features/home/home_tab_content.dart` is **not** listed — the `additionalDates` wiring was already present in `main` (commit `2b2111b`) before this branch was created. No change was made to that file on this branch.

No other files were modified.
