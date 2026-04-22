# QA Report — Regression Fix

## Fix
Hybrid child/RRULE strategy replacing always-skip-children approach

## Final Verdict
APPROVED

## Four Code Paths Verified

1. **Recurring parent with children:** PASS. `childRowsByParent` Map is built before the VEVENT loop. In the loop, `if (isRecurring && !isChild)` is entered and `childRowsByParent.get(rehearsal.id)` returns a non-empty array → `continue` fires, parent row is skipped. No RRULE emitted.

2. **Recurring parent without children:** PASS. Same `if (isRecurring && !isChild)` block is entered, `childRowsByParent.get(rehearsal.id)` returns `[]`, `children.length === 0` → does not `continue`. Falls through to VEVENT emission where `if (isRecurring && !isChild)` calls `buildRehearsalRrule()` and emits `RRULE:...` via `foldLine`.

3. **Recurring child:** PASS. `isChild = true` → the skip block `if (isRecurring && !isChild)` is never entered. The RRULE block `if (isRecurring && !isChild)` is also never entered. Row falls through to flat VEVENT using its own `date`, `start_time`, `end_time`.

4. **Non-recurring:** PASS. `isRecurring = false` → skip block not entered, RRULE block not entered. Flat VEVENT using row’s own date/time, unchanged from before the patch.

## Double-emission check
PASS. Mutually exclusive by construction: a recurring parent with children is skipped via `continue` before any VEVENT lines are pushed, so it cannot also emit an RRULE. A recurring parent without children emits RRULE, and no child rows exist in `childRowsByParent` for it, so no flat VEVENTs are emitted for those instances.

## ETag check
PASS. `computeEtag` receives `filteredRehearsal`, which is the full rehearsal array (filtered only by the `include_rehearsals` subscription flag). The map function includes `id`, `date`, `start_time`, `end_time`, `is_recurring`, `recurrence_frequency`, `recurrence_until`, `recurrence_days`, and `parent_rehearsal_id` for every row — child rows are included in the hash.

## Diff scope
Files modified: `supabase/functions/calendar-feed/index.ts` (commit `1c4aefe`), `docs/features/calendar-feed-monthly-recurring-rehearsal/QA_REPORT_REGRESSION.md` (QA report only)
Off-limits violations: none

## Regression check
- `BYDAY_MAP`: untouched ✓
- `buildRehearsalRrule`: untouched ✓
- `formatRruleUntil`: untouched ✓
- `foldLine` on RRULE line: unchanged — `foldLine(\`RRULE:\${rrule}\`)` still present ✓
- Gig VEVENT section: untouched ✓
- Block-out VEVENT section: untouched ✓
- Header / VTIMEZONE section: untouched ✓

## Diff safety
Secrets: none
Debug artifacts: none (`console.log` absent; only pre-existing `console.error` in error boundary)
Unrelated changes: none

## Deno check
unavailable (deno not installed in this environment)

## Issues Found
None
