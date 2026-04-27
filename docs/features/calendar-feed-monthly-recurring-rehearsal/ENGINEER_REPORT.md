# Engineer Report

## Feature Slug
bug/calendar-feed-monthly-recurring-rehearsal

## Feature Title
Calendar subscription feed does not include monthly recurring rehearsal instances

## Goal
Make the `calendar-feed` Edge Function recurrence-aware so monthly (and weekly/biweekly) recurring rehearsals appear reliably in external iCal/webcal subscribers via RRULE, regardless of whether materialized child rows exist.

## Architect Tasks Completed
- [x] Task 1 — Updated rehearsal `select(...)` and `RehearsalEvent` interface to include `is_recurring`, `recurrence_frequency`, `recurrence_days`, `recurrence_until`, `parent_rehearsal_id`.
- [x] Task 2 — Added `BYDAY_MAP` (0=Sun..6=Sat → SU..SA) recurrence-day mapping helper.
- [x] Task 3 — Added inline RRULE builder (`buildRehearsalRrule`) supporting weekly (`FREQ=WEEKLY`), biweekly (`FREQ=WEEKLY;INTERVAL=2`), monthly (`FREQ=MONTHLY`), optional `BYDAY=...`, optional `UNTIL=YYYYMMDDT235959Z`.
- [x] Task 4 — VEVENT loop now: skips recurring child rows, emits `RRULE` for recurring parent rows, falls back to a flat VEVENT (with `X-BANDROADIE-NOTE:RECURRENCE-DATA-INCOMPLETE`) when recurrence metadata is incomplete, and keeps non-recurring rows on the existing single-instance path.
- [x] Task 5 — `computeEtag` rehearsal source now includes `is_recurring`, `recurrence_frequency`, `recurrence_until`, `recurrence_days`, and `parent_rehearsal_id` so RRULE/recurrence changes invalidate the cache.
- [x] Task 6 — `RRULE:` line is emitted via the existing `foldLine(...)` helper, preserving RFC 5545 75-char line-folding.

## Files Created
none

## Files Modified
- supabase/functions/calendar-feed/index.ts

## Analyzer Results
Command: `deno check supabase/functions/calendar-feed/index.ts`
Result: unavailable (Deno not installed in this environment). TypeScript correctness to be verified by Copilot review of the diff and by `supabase functions deploy calendar-feed` validation step.

No Flutter files changed, so `flutter analyze` is not applicable for this change.

## Test Results
Not run (Tier 1 and Tier 2 verification are manual — see Verification Plan in ARCHITECT_PLAN.md).

## Verification
Manual steps performed:
- Re-read `supabase/functions/calendar-feed/index.ts` end-to-end to confirm gig, block-out, header, and VTIMEZONE logic remain byte-identical.
- Confirmed RRULE emission only triggers for `is_recurring === true && parent_rehearsal_id == null`, child-instance skip only triggers for recurring children, non-recurring rehearsal path is unchanged.
- Confirmed UNTIL value is a valid `YYYYMMDDT235959Z` UTC end-of-day form.
- Confirmed `RRULE:` is wrapped with `foldLine(...)` like all other ICS output lines.
- Confirmed ETag source now incorporates recurrence fields so cache key changes when recurrence metadata changes.

Manual subscriber testing in Apple Calendar / Google Calendar is part of QA Tier 2 (post-deploy).

## Deviations From Architect Plan
None.

## Blockers Encountered
None.

## Ready For QA
Yes
