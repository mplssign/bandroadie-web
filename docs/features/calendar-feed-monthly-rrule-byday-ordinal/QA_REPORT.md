# QA Report

## Feature Slug

bug/calendar-feed-monthly-rrule-byday-ordinal

## Final Verdict

APPROVED

## Tasks Verified

- Task 1 (computeFirstOccurrenceDate): PASS
- Task 2 (ordinal BYDAY): PASS
- Task 3 (DTSTART alignment): PASS

## Five Trace Results

1. `computeFirstOccurrenceDate('2026-11-01', 1)` -> `'2026-11-02'`, N=1 -> `BYDAY=1MO` (PASS)
2. `computeFirstOccurrenceDate('2026-11-02', 1)` -> `'2026-11-02'`, N=1 -> `BYDAY=1MO` (PASS)
3. `computeFirstOccurrenceDate('2026-11-09', 1)` -> `'2026-11-09'`, N=2 -> `BYDAY=2MO` (PASS)
4. Weekly with `recurrence_days=[1]` -> `FREQ=WEEKLY;BYDAY=MO` (bare token, no ordinal) (PASS)
5. Monthly with no `recurrence_days` -> `FREQ=MONTHLY` (no BYDAY) (PASS)

## Regression Check

Untouched sections:

- `BYDAY_MAP` declaration: confirmed untouched
- `formatRruleUntil`: confirmed untouched
- `buildRehearsalRrule` weekly/biweekly branch: confirmed unchanged behavior (bare BYDAY)
- Gig VEVENT section: confirmed untouched
- Block-out VEVENT section: confirmed untouched
- Header / `VTIMEZONE`: confirmed untouched
- Child row VEVENT path: confirmed unchanged behavior (no RRULE for child rows, date path unchanged)
- ETag computation: confirmed untouched

Regressions found: none

## Diff Scope

Files modified:

- `docs/features/calendar-feed-monthly-recurring-rehearsal/QA_REPORT_REGRESSION.md`
- `supabase/functions/calendar-feed/index.ts`

Off-limits violations: none

## Diff Safety

Secrets: none
Debug artifacts: none
Unrelated changes: found (`docs/features/calendar-feed-monthly-recurring-rehearsal/QA_REPORT_REGRESSION.md` is outside this feature slug but is documentation-only and does not affect runtime logic)

## Deno Check

unavailable (`deno` command not present in environment)

## Issues Found

None
