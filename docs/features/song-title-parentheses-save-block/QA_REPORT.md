# QA Report — song-title-parentheses-save-block

## Feature Slug

`song-title-parentheses-save-block`

## Feature Title

Song title with parentheses blocks Save button

## Validation Summary

All phases completed. Implementation matches the Architect plan exactly. Behavior verified via standalone Dart execution of the fixed logic against all Architect-defined test cases. Analyzer passes. All existing tests pass. Diff is clean and minimal.

---

## Architect Scope Review

The Architect plan defines a single-file bug fix in `lib/shared/utils/title_case_formatter.dart`:

- **Problem:** `toTitleCase()` and `TitleCaseTextFormatter` treat non-letter punctuation (parentheses, apostrophes, quotes) as word constituents that consume the `capitalizeNext` flag, lowercasing the next actual letter. This prevents users from saving correctly-capitalized song titles that begin with punctuation.
- **Approved fix:** Make non-letter, non-space, non-hyphen characters pass through without affecting the `capitalizeNext` state.
- **Scope:** 1 file, 2 code locations, docstring updates, verification run.
- **Constraints:** No new files, no new dependencies, no database changes, no architecture changes.
- **Out of scope:** Decomposing `song_details_bottom_sheet.dart`, adding new unit tests, bulk data migration, "small words" title case rules.

The Architect plan is clear and unambiguous.

---

## Implementation Review

### Files changed (expected)

| File                                         | Change                                                                                                                                                                                                                                         |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/shared/utils/title_case_formatter.dart` | Updated `toTitleCase()` and `TitleCaseTextFormatter.formatEditUpdate()` to add `RegExp(r'[a-zA-Z]')` letter check; non-letter punctuation now passes through without consuming `capitalizeNext`. Updated docstrings with punctuation examples. |

### Files changed (unexpected)

None.

### Untracked files

| File                                                                 | Expected           |
| -------------------------------------------------------------------- | ------------------ |
| `docs/features/song-title-parentheses-save-block/ARCHITECT_PLAN.md`  | Yes — workflow doc |
| `docs/features/song-title-parentheses-save-block/ENGINEER_REPORT.md` | Yes — workflow doc |

### Architecture compliance

- No init-order changes ✓
- No config-path changes ✓
- No new dependencies ✓
- No new widgets, controllers, providers, or repositories ✓
- No platform behavior changes ✓
- Implementation stays within Architect scope ✓

---

## Files Verified

| File                                                           | Status                                                                 |
| -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `lib/shared/utils/title_case_formatter.dart`                   | Verified — diff matches Architect plan                                 |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Inspected — caller not modified, uses toTitleCase for change detection |
| `lib/features/setlists/setlist_repository.dart`                | Inspected — caller not modified, uses toTitleCase for normalization    |
| `lib/features/events/widgets/rehearsal_form_fields.dart`       | Inspected — caller not modified, uses TitleCaseTextFormatter           |
| `lib/features/events/widgets/gig_form_fields.dart`             | Inspected — caller not modified, uses TitleCaseTextFormatter           |

---

## Bug Reproduction Result

### Pre-fix path (traced from Architect plan)

1. Song title stored as `(what's So Funny 'Bout)` (old `toTitleCase` lowercases letter after `(`)
2. User edits `w` → `W` to get `(What's So Funny 'Bout)`
3. `_checkForChanges()` runs `toTitleCase()` on edited text
4. Old `toTitleCase("(What's...")` → `(what's...` — reverts the edit
5. Compare finds no difference → Save button stays disabled

### Post-fix path (verified)

1. Fixed `toTitleCase("(what's So Funny 'Bout)")` → `(What's So Funny 'Bout)` ✓
2. Fixed `toTitleCase("(What's So Funny 'Bout) Peace, Love, And Understanding")` → `(What's So Funny 'Bout) Peace, Love, And Understanding` ✓
3. User's edit is now preserved by normalization → `_hasChanges` correctly becomes `true` → Save button enables

### Behavioral verification (standalone Dart execution)

All 10 test cases passed:

| Input                                                    | Expected                                                 | Result |
| -------------------------------------------------------- | -------------------------------------------------------- | ------ |
| `(what's So Funny 'Bout)`                                | `(What's So Funny 'Bout)`                                | PASS   |
| `(What's So Funny 'Bout) Peace, Love, And Understanding` | `(What's So Funny 'Bout) Peace, Love, And Understanding` | PASS   |
| `hello world`                                            | `Hello World`                                            | PASS   |
| `new-york city`                                          | `New-York City`                                          | PASS   |
| `TESTING case`                                           | `Testing Case`                                           | PASS   |
| `the beatles`                                            | `The Beatles`                                            | PASS   |
| `o'brien`                                                | `O'brien`                                                | PASS   |
| `"hello" world`                                          | `"Hello" World`                                          | PASS   |
| `[test] value`                                           | `[Test] Value`                                           | PASS   |
| _(empty)_                                                | _(empty)_                                                | PASS   |

---

## Completeness Check

| Architect Task                                                                   | Status      |
| -------------------------------------------------------------------------------- | ----------- |
| Task 1: Fix `toTitleCase()` — add letter check before consuming `capitalizeNext` | ✅ Complete |
| Task 2: Fix `TitleCaseTextFormatter.formatEditUpdate()` — identical logic fix    | ✅ Complete |
| Task 3: Update docstring examples — parenthesis and apostrophe examples          | ✅ Complete |
| Task 4: Run verification — analyzer + tests                                      | ✅ Complete |

All Architect tasks implemented. No skipped requirements.

---

## Regression Check

### Systems inspected

| System                                               | Impact                      | Finding                                                                                          |
| ---------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------ |
| Song details — change detection (`_checkForChanges`) | Direct caller               | Fix corrects the bug; normalization now preserves punctuation-adjacent capitalization            |
| Song details — save (`_handleSave`)                  | Direct caller               | Normalized values are now more correct                                                           |
| Setlist repository — `upsertExternalSong()`          | Direct caller               | Future imports produce more correct titles; `.ilike()` lookup is case-insensitive, no duplicates |
| Setlist repository — `_createOrFindSong()`           | Direct caller               | Same as above                                                                                    |
| Rehearsal form — location field                      | Uses TitleCaseTextFormatter | Improved behavior for punctuation in location names                                              |
| Gig form — venue/city fields                         | Uses TitleCaseTextFormatter | Improved behavior for punctuation in venue names                                                 |
| Auth/session                                         | Not touched                 | No impact                                                                                        |
| Routing/deep links                                   | Not touched                 | No impact                                                                                        |
| RLS policies                                         | Not touched                 | No impact                                                                                        |
| Notifications                                        | Not touched                 | No impact                                                                                        |

### Regression Risk Level

**LOW**

Rationale: Change is confined to a single utility function and its formatter counterpart. All callers produce more correct output. No database, auth, routing, or state management changes. Existing data is unaffected. Lookup queries use case-insensitive matching.

---

## Database Safety Review

**Not applicable.** No database changes in this fix. No migrations, RLS policies, triggers, RPC functions, or schema references modified.

---

## Analyzer Results

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 3.7s)
```

**0 errors, 0 warnings** ✓

---

## Test Results

```
flutter test
00:01 +6: All tests passed!
```

**6 tests passed, 0 failures** ✓

---

## Diff Safety Review

| Check                                  | Result |
| -------------------------------------- | ------ |
| No secrets                             | ✓      |
| No environment/config drift            | ✓      |
| No unrelated refactors                 | ✓      |
| No formatting-only churn               | ✓      |
| No accidental file deletions           | ✓      |
| No debug artifacts or console spam     | ✓      |
| No temporary flags or test scaffolding | ✓      |
| No new imports or dependencies         | ✓      |

---

## Issues Found

None.

---

## Final Verdict

### **APPROVED**

Implementation matches the Architect plan exactly. Bug fix behavior verified via standalone Dart execution across all specified test cases. All existing tests pass. Analyzer clean. Diff is minimal and safe. No regressions identified. Ready for commit and review.
