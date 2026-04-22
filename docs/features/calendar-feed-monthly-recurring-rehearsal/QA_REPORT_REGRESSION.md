# QA Report — Regression Fix

## Fix

Hybrid child/RRULE strategy replacing always-skip-children approach

## Final Verdict

REQUIRES CHANGES

## Four Code Paths Verified

1. Recurring parent with children: FAIL. No child-row index (Map keyed by parent_rehearsal_id) is built before VEVENT emission, and recurring parents are not conditionally skipped based on child presence. Parent rows still emit RRULE when recurring and not child ([supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L832), [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L845)).
2. Recurring parent without children: PASS. Recurring non-child rows call buildRehearsalRrule and emit RRULE when valid ([supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L833), [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L845)).
3. Recurring child: FAIL. Recurring child rows are skipped, not emitted as flat VEVENTs using child date/start_time/end_time ([supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L810)).
4. Non-recurring: PASS. Non-recurring rows follow the existing flat VEVENT path (DTSTART/DTEND from row date/time, no RRULE unless recurring branch sets one) ([supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L822), [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L844)).

## Double-emission check

No direct parent+child double-emission observed in current logic because recurring child rows are skipped. However, required hybrid behavior is not met: recurring parents with child rows are not skipped and can still emit RRULE, while child rows are suppressed globally.

## ETag check

PASS. ETag source maps over the full rehearsal array and includes recurrence + parent/child linkage fields, so child-row data participates in hash computation ([supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L150), [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L159), [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L696)).

## Diff scope

Files modified: none (working tree clean; no staged or unstaged changes)
Off-limits violations: none

## Diff safety

Secrets: none found
Debug artifacts: none found
Unrelated changes: none found

## Deno check

unavailable (deno not installed in this environment: command not found)

## Issues Found

1. Critical: Missing hybrid routing logic. No precomputed child index keyed by parent_rehearsal_id before VEVENT loop.
2. Critical: Recurring child rows are skipped instead of being emitted as deletion-safe flat VEVENTs.
3. Critical: Recurring parents are not conditionally skipped when child rows exist; current behavior remains parent-RRULE centric.
4. Suggestion: Add explicit branch ordering in rehearsal VEVENT loop to enforce mutually exclusive paths:
   - recurring parent with children => skip parent
   - recurring parent without children => RRULE
   - recurring child => flat VEVENT
   - non-recurring => flat VEVENT
