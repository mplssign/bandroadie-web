# Engineer Report

## Feature Slug

`bug/setlist-card-duration-set-break-fix`

## Feature Title

Setlist Card Duration Excludes Set Break Duration

## Goal

Fix the setlist list view cards to include set break and pause durations in the displayed total duration, matching the correct behavior already present in the setlist detail screen header.

## Architect Tasks Completed

- [x] Task 1 — Expand nested select in primary query variant (is_catalog + position) — **complete**
- [x] Task 2 — Expand nested select in fallback variant without position — **complete**
- [x] Task 3 — Expand nested select in fallback variant without position and is_catalog — **complete**
- [x] Task 4 — Expand nested select in fallback variant without is_catalog, with position — **complete**
- [x] Task 5 — Add totalDurationSeconds accumulator and duration computation to parsing loop — **complete**
- [x] Task 6 — Override flatJson['total_duration'] with computed value — **complete**
- [x] Task 7 — Run flutter analyze — **complete** (0 errors, 0 warnings)
- [x] Task 8 — Run flutter test — **complete** (6 tests passed)
- [ ] Task 9 — Manual verification per Verification Plan — **not performed** (requires running app with live Supabase data; deferred to QA)

## Files Created

- `docs/features/setlist-card-duration-set-break-fix/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/setlists/setlist_repository.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!"

## Test Results

Command: `flutter test`
Result: All 6 tests passed.

## Verification

Manual steps performed:

- Verified all 4 query variants were expanded with identical nested select syntax
- Verified duration computation logic matches Architect plan specification exactly
- Verified defensive null/type checks follow existing codebase patterns (`as int? ?? 0`, `is Map` guards)
- Verified `flatJson['total_duration']` override is placed after parsing loop and before `Setlist.fromSupabase()`
- Verified no other files were modified
- Confirmed `flutter analyze` passes with 0 errors
- Confirmed `flutter test` passes with 0 failures
- Manual app verification (Task 9) deferred to QA phase

## Deviations From Architect Plan

None.

## Blockers Encountered

- Branch `bug/setlist-card-duration-set-break-fix` did not exist. Created from `main` to proceed with implementation.
- `COMMIT_GATE.md` and `HANDOFF_TEMPLATE.md` referenced in Phase 0 do not exist as standalone files. Their content is covered by `GUARDRAILS.md` (Section 11) and `ENGINEER.md` (Phase 7). Non-blocking.

## Ready For QA

Yes

---

## Hotfix — Regression Correction

### Regression

Song durations were not included in totalDurationSeconds because
setlist_songs.duration_seconds is NULL for all song rows in production.
Only set break durations were being summed.

### Root Cause (confirmed via DB query)

setlist_songs.duration_seconds = NULL for song rows.
Song duration lives on songs.duration_seconds (via songs table join).

### Fix Applied

- Nested select updated in all 4 query variants: added `song:songs(duration_seconds)`,
  removed `duration_seconds` from setlist_songs level.
- Song accumulation updated: reads `item['song']['duration_seconds']` via
  `is Map` guard and `?? 0` fallback.

### Validation

- flutter analyze: 0 errors, 0 warnings — "No issues found!"
- flutter test: All 6 tests passed

### Ready For QA

Yes
