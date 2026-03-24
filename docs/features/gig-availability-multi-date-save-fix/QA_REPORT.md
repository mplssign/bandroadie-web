# QA_REPORT.md

## Feature Slug

`bug/gig-availability-multi-date-save-fix`

## Feature Title

Bug: Gig Availability Only Saves First Date When Multiple Dates Present + Feature: Replace "Multiple" Button with Always-Visible "+ Add Another Date" UX

## Validation Summary

QA validation completed via code-path analysis and static analysis. All 12 Architect tasks verified as fully implemented. No runtime/UI validation was performed — all behavior verification is based on source code inspection and diff review.

## Architect Scope Review

- **Problem:** Multi-date potential gig availability only saved for primary date due to three defects in the repository/service layer. UX: hidden "Multiple" button needed replacing with always-visible "+ Add Another Date".
- **Approved solution:** Fix `_performUpsert` and `fetchUserResponse` with `.isFilter('gig_date_id', null)`. Expand `PendingPotentialGig` with `additionalDateIds`. Fix prompt service to save all dates. Remove toggle mechanism, always show "+ Add Another Date".
- **Files approved for modification:** `gig_response_repository.dart`, `potential_gig_prompt_service.dart`, `event_form_fields.dart`, `event_editor_drawer.dart`
- **Files approved for creation:** None
- **Database impact:** None (no schema, RLS, RPC, or migration changes)
- **Out of scope:** Backfills, per-date prompt modals, re-prompting, refactoring, notifications, test creation

## Implementation Review

### Sub-feature 1 — Bug Fix

| Task | Description                                                                                    | Status      |
| ---- | ---------------------------------------------------------------------------------------------- | ----------- |
| 1.1  | Fix `_performUpsert`: `.isFilter('gig_date_id', null)` on SELECT and UPDATE                    | ✅ Verified |
| 1.2  | Fix `fetchUserResponse`: `.isFilter('gig_date_id', null)` on SELECT                            | ✅ Verified |
| 1.3  | Add `additionalDateIds` field to `PendingPotentialGig` with default `const []`                 | ✅ Verified |
| 1.4  | Update `fetchPendingPotentialGigs` select to include `gig_dates(id)` join                      | ✅ Verified |
| 1.5  | Parse `additionalDateIds` from joined `gig_dates` array in `fromJson`                          | ✅ Verified |
| 1.6  | Replace `upsertResponse()` with `upsertResponseForDate()` calls for primary + additional dates | ✅ Verified |

### Sub-feature 2 — UX Feature

| Task | Description                                                                                                  | Status      |
| ---- | ------------------------------------------------------------------------------------------------------------ | ----------- |
| 2.1  | Remove `onMultiDateToggled` from `EventFormFields` constructor and field                                     | ✅ Verified |
| 2.2  | Delete `_buildMultipleDatesToggle()` method entirely                                                         | ✅ Verified |
| 2.3  | Restructure `_buildDatePicker()`: remove toggle, remove `isMultiDate` gate, always show "+ Add Another Date" | ✅ Verified |
| 2.4  | Add `_isMultiDate = true` in `_addAdditionalDate()` inside setState                                          | ✅ Verified |
| 2.5  | Add `if (_additionalDates.isEmpty) _isMultiDate = false` in `_removeAdditionalDate()` inside setState        | ✅ Verified |
| 2.6  | Remove `onMultiDateToggled` parameter from `_createEventFormFields()` call                                   | ✅ Verified |

## Files Verified

| File                                                   | Expected Change                         | Verified |
| ------------------------------------------------------ | --------------------------------------- | -------- |
| `lib/features/gigs/gig_response_repository.dart`       | Bug fix queries + model expansion       | ✅       |
| `lib/features/gigs/potential_gig_prompt_service.dart`  | Multi-date save in prompt onRespond     | ✅       |
| `lib/features/events/widgets/event_form_fields.dart`   | Remove toggle, restructure date picker  | ✅       |
| `lib/features/events/widgets/event_editor_drawer.dart` | Auto-manage \_isMultiDate, remove param | ✅       |

No files outside the approved list were modified.

## Bug Reproduction Result

**Code-path analysis only — no runtime verification performed.**

### Defect A — Prompt service saves only primary date

- **Root cause addressed:** `onRespond` callback now calls `upsertResponseForDate()` for primary date (null) AND loops through `gig.additionalDateIds` for each additional date.
- **`PendingPotentialGig`** now carries `additionalDateIds` populated from `gig_dates(id)` join in `fetchPendingPotentialGigs`.
- **Failure path eliminated:** The single `upsertResponse()` call that only saved primary date no longer exists at this call site.

### Defect B — `_performUpsert` does not filter by `gig_date_id`

- **Root cause addressed:** Both SELECT (`.maybeSingle()`) and UPDATE queries in `_performUpsert` now include `.isFilter('gig_date_id', null)`, constraining to primary-date-only rows.
- **Failure path eliminated:** `.maybeSingle()` will no longer return multiple rows when per-date responses exist.

### Defect C — `fetchUserResponse` does not filter by `gig_date_id`

- **Root cause addressed:** SELECT query now includes `.isFilter('gig_date_id', null)`, returning only the primary date response.
- **Failure path eliminated:** `.maybeSingle()` will no longer throw when per-date responses exist.

## Feature Validation Result

**Code-path analysis only — no runtime verification performed.**

- "Multiple" button removed: `_buildMultipleDatesToggle()` deleted, no call site remains.
- "+ Add Another Date" always visible when `isPotentialGig`: Renders inside `if (eventType == EventType.gig && isPotentialGig)` unconditionally.
- Additional dates shown when present: Gate changed from `if (isMultiDate)` to `if (additionalDates.isNotEmpty)`.
- Auto-management of `_isMultiDate`: `_addAdditionalDate()` sets true, `_removeAdditionalDate()` clears when empty.
- Non-potential gigs unaffected: Button only appears inside potential gig conditional.

## Completeness Check

All 12 Architect tasks fully implemented. No skipped requirements, no partial implementations, no missing edge-case handling.

## Regression Check

### Affected Systems

| System         | Status                                                                                                                                                                            |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs           | Changes are localized to response repository queries, prompt service save, and event form UI. No changes to gig creation, deletion, or core gig model. No regressions identified. |
| Platform (all) | UI changes affect all platforms equally. No platform-specific code changed. No entitlements, manifests, or configs touched.                                                       |

### Unaffected Systems

| System             | Status               |
| ------------------ | -------------------- |
| Rehearsals         | ✅ No files modified |
| Setlists / Catalog | ✅ No files modified |
| Members / RBAC     | ✅ No files modified |
| Auth / Session     | ✅ No files modified |
| Routing            | ✅ No files modified |
| Notifications      | ✅ No files modified |
| Calendar           | ✅ No files modified |
| Dashboard          | ✅ No files modified |

### Guardrail Checks

- No initialization order changes
- No new controllers or FocusNodes introduced
- No `setState` after async gaps introduced
- No new dependencies added
- No RPC signature changes

## Regression Risk Level

**LOW**

Architect estimated MEDIUM for sub-feature 1. After inspection: the `.isFilter('gig_date_id', null)` additions are narrowly scoped, consistent with the existing `_performUpsertForDate` pattern already in the codebase, and constrained to a single data path. The formatting churn is cosmetic. Revised to LOW overall.

## Database Safety Review

Not applicable. No schema, RLS, RPC, or migration changes. The implementation writes additional rows to `gig_responses` using existing columns and constraints. The unique index `(gig_id, user_id, COALESCE(gig_date_id, ...))` already supports per-date responses.

## Analyzer Results

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 4.2s)
```

0 errors, 0 warnings.

## Test Results

```
flutter test
00:04 +6: All tests passed!
```

6 tests passed. No regressions.

## Diff Safety Review

- [x] No secrets, API keys, or credentials
- [x] No hardcoded environment values outside approved scope
- [x] No accidental deletions of existing functionality
- [x] No debug artifacts (no new print/debugPrint beyond one modified debug message enhancing existing logging)
- [x] No modifications to off-limits files
- [x] All old code replaced as specified (no old code left behind alongside new code)
- [ ] Minor formatting churn: whitespace-only changes in `gig_response_repository.dart` to `GigResponseSummary.empty()` constructor indentation (lines ~78-82), `memberIds` variable (lines ~500-502), and `potentialGigResponseSummariesProvider` body indentation (lines ~730-767). These are cosmetic, do not affect logic, but are technically outside Architect plan scope. **Non-blocking.**

## Known Deviations Assessment

Engineer report states "None" for deviations.

**Verification against diff:**

- All functional changes match the Architect plan exactly.
- Minor formatting churn in `gig_response_repository.dart` exists (whitespace/indentation normalization in unrelated code blocks). This was not listed as a deviation by the Engineer. It is cosmetic, does not change behavior, and is consistent with auto-formatter output. **Verdict: Acceptable — non-blocking observation.**

## Issues Found

1. **Minor (non-blocking):** Formatting-only changes to unrelated code in `gig_response_repository.dart` (constructor indentation, variable declaration, provider body indentation). These appear to be auto-formatter normalization. Does not affect functionality or introduce regressions, but technically exceeds the minimal diff surface specified by the Architect plan.

## Final Verdict

**APPROVED**

All Architect tasks are implemented correctly. All three root-cause defects are addressed. The UX feature matches the specified behavior. No critical regressions found. Database safety is not applicable. Flutter analyze passes with 0 errors. All tests pass. No out-of-scope or unsafe changes exist. The one observation (formatting churn) is cosmetic and non-blocking.
