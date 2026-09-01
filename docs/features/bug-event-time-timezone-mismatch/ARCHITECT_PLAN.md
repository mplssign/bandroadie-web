# ARCHITECT_PLAN

## 1. Feature Slug

`bug/event-time-timezone-mismatch`

## 2. Problem Summary

Gig and rehearsal times are rendered through two different display paths. Dashboard/home cards, calendar cards, and availability prompt modals currently convert band-timezone wall-clock strings into device-local time, while detail drawers display raw band-timezone wall-clock times. When the viewing device timezone differs from `bands.timezone`, users see inconsistent times for the same event.

Product decision is explicit: event times must always display in the band's configured timezone, never converted to viewer-local timezone.

## 3. Root Cause

**Cause:** six display call sites use `TimeFormatter.formatRangeLocal(...)`, which calls `TimezoneHelper.toLocal(...)` and shifts displayed clock time into device timezone. Detail drawers use `gig.timeRange` / `rehearsal.timeRange`, which use `TimeFormatter.formatRange(...)` and do not shift the stored wall-clock values.

**Confidence:** `HIGH` (directly confirmed in code).

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/architecture/database_schema.md` (confirmed `bands.timezone` exists and this feature is display-only)
- `docs/reference/audits/CODEBASE_AUDIT.md` (timezone consistency risk noted in audit)

No dedicated event-time display reference doc was found under `docs/reference/` that changes the product decision above.

## 5. Existing System Analysis

Current display flow for impacted surfaces:

1. UI widgets call `TimeFormatter.formatRangeLocal(start, end, date, bandTimezone)`.
2. `formatRangeLocal` calls `TimezoneHelper.toLocal(...)` for start/end.
3. UI renders converted local-clock strings.

Current display flow for detail drawers:

1. Drawer renders `gig.timeRange` / `rehearsal.timeRange`.
2. Model getter uses `TimeFormatter.formatRange(start, end)`.
3. UI renders stored wall-clock strings (band-time intent), no conversion.

Mismatch appears only when `device timezone != bands.timezone`.

## 6. Proposed Solution

Apply the smallest safe display-layer fix:

1. Replace all six UI call sites of `TimeFormatter.formatRangeLocal(...)` with `TimeFormatter.formatRange(...)`.
2. Keep timezone-aware UTC conversion logic untouched for filtering/sorting (`TimezoneHelper.toUtc(...)` paths remain exactly as-is).
3. Prevent future misuse by deprecating local display conversion APIs (do not remove in this bug fix):
   - Add deprecation/doc guidance on `TimeFormatter.formatRangeLocal(...)`.
   - Add deprecation/doc guidance on `TimezoneHelper.toLocal(...)`.

Why this is minimal and safe:

- No persistence changes.
- No repository/controller query logic changes.
- No auth/RLS changes.
- Aligns all surfaces to already-correct drawer behavior.

## 7. Database Impact

`not applicable`

- Migrations: unaffected
- RLS: unaffected
- RPC signatures/functions: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

No architectural changes.

- State management: unaffected
- Repositories/controllers: unaffected
- Widget layer: affected (time-string formatter call replacement)
- Utility API annotations/comments: affected (`TimeFormatter`, `TimezoneHelper` doc/deprecation only)

## 9. Files to Create

- `none` (implementation)

## 10. Files to Modify

| File                                                                       | What changes                                                                                                            |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/widgets/rehearsal_card.dart`                            | Replace `formatRangeLocal` usage with `formatRange` for displayed rehearsal time.                                       |
| `lib/features/home/widgets/confirmed_gig_card.dart`                        | Replace `formatRangeLocal` usage with `formatRange` for displayed gig time.                                             |
| `lib/features/home/widgets/potential_gig_card.dart`                        | Replace `formatRangeLocal` usage with `formatRange` for displayed potential gig time.                                   |
| `lib/features/calendar/widgets/calendar_event_card.dart`                   | Replace `formatRangeLocal` usage with `formatRange` for event card time display.                                        |
| `lib/features/gigs/widgets/availability_prompt_modal.dart`                 | Replace `formatRangeLocal` usage with `formatRange` in prompt details.                                                  |
| `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart` | Replace `formatRangeLocal` usage with `formatRange` in prompt details.                                                  |
| `lib/app/utils/time_formatter.dart`                                        | Mark `formatRangeLocal` as deprecated for UI display and document band-timezone display policy.                         |
| `lib/app/utils/timezone_helper.dart`                                       | Mark `toLocal` as deprecated for UI display and document that `toUtc` remains authoritative for filtering/sorting only. |

## 11. Files Off-Limits

| File                                                                | Reason                                                                   |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `lib/app/utils/timezone_helper.dart` (`toUtc` implementation block) | Filtering/sorting UTC conversion is correct and explicitly out of scope. |
| `lib/features/gigs/gig_repository.dart`                             | Repository filtering/sorting behavior is unrelated and must not change.  |
| `lib/features/gigs/gig_controller.dart`                             | Controller filtering/sorting behavior is unrelated and must not change.  |
| `lib/features/rehearsals/rehearsal_repository.dart`                 | Repository filtering/sorting behavior is unrelated and must not change.  |
| `lib/features/rehearsals/rehearsal_controller.dart`                 | Controller filtering/sorting behavior is unrelated and must not change.  |
| `lib/features/gigs/widgets/view_gig_drawer.dart`                    | Already correct (`gig.timeRange`), used as reference behavior.           |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`        | Already correct (`rehearsal.timeRange`), used as reference behavior.     |

## 12. System Impact Map

| System                                 | Impact                                    |
| -------------------------------------- | ----------------------------------------- |
| Gigs                                   | affected                                  |
| Rehearsals                             | affected                                  |
| Setlists / Catalog                     | unaffected                                |
| Members / RBAC                         | unaffected                                |
| Auth / Session                         | unaffected                                |
| Routing                                | unaffected                                |
| Notifications                          | unaffected                                |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter display widgets) |

## 13. Regression Risk

`LOW`

Rationale:

- Scoped to six display call sites plus deprecation comments/annotations.
- No behavior change in writes, reads, filtering, sorting, auth, or routing.
- Uses existing formatter (`formatRange`) already proven in detail drawers.

## 14. Engineer Task Breakdown

1. Update all six listed widget files to use `TimeFormatter.formatRange(startTime, endTime)`.
2. Remove now-unused date/timezone arguments in those calls and clean any resulting unused locals/imports.
3. Add deprecation/doc comments to `TimeFormatter.formatRangeLocal` and `TimezoneHelper.toLocal` clarifying they must not be used for event-time display.
4. Confirm `TimezoneHelper.toUtc` and all repository/controller filtering logic are unchanged.
5. Run analyzer/tests per project norms and produce `ENGINEER_REPORT.md` with before/after behavior notes.

## 15. Verification Plan

This bug does not involve database schema/function changes; `supabase db push` is not part of this fix. Two-tier verification is still required for pre-release and post-release confidence.

### Tier 1 — Pre-deployment (must pass before release)

- `-- PRE-DEPLOY TEST 1:` Static verification: search codebase for `TimeFormatter.formatRangeLocal(` usage in `lib/` and confirm no remaining call sites in event display widgets.
- `-- PRE-DEPLOY TEST 2:` Device timezone mismatch scenario setup:
  - Band timezone: `America/Chicago`
  - Device timezone: `America/New_York`
  - Test event time: `6:30 PM` to `9:00 PM`
- `-- PRE-DEPLOY TEST 3:` For one rehearsal, compare Dashboard card time vs View Rehearsal drawer time; values must match exactly and remain `6:30 PM - 9:00 PM`.
- `-- PRE-DEPLOY TEST 4:` For one confirmed gig, compare Dashboard card time vs View Gig drawer time; values must match exactly and remain `6:30 PM - 9:00 PM`.
- `-- PRE-DEPLOY TEST 5:` Validate each impacted surface independently shows identical band-time value:
  - Home `rehearsal_card`
  - Home `confirmed_gig_card`
  - Home `potential_gig_card`
  - `calendar_event_card`
  - Gig `availability_prompt_modal`
  - Rehearsal `rehearsal_availability_prompt_modal`
- `-- PRE-DEPLOY TEST 6:` Control case: when device timezone equals band timezone, displayed values remain unchanged from current expected band-time display.

### Tier 2 — Post-deployment (run after release/deploy)

- `-- POST-DEPLOY TEST 1:` Repeat mismatch scenario (`America/Chicago` band, `America/New_York` device) against production build; confirm all six affected surfaces and both drawers show identical times for the same event.
- `-- POST-DEPLOY TEST 2:` Cross-platform smoke (Web, iOS, Android, macOS where available): validate no surface reverts to device-local conversion.
- `-- POST-DEPLOY TEST 3:` Regression check around temporal ordering views (upcoming/past sections) to confirm display fix did not alter filtering/sorting behavior.
- `-- POST-DEPLOY TEST 4:` Production data sanity check for sampled events: stored `start_time`/`end_time` values are unchanged; only UI rendering behavior changed.

## 16. QA Regression Areas

- Primary: event-time consistency between cards/calendar/prompts and drawers under timezone mismatch.
- Rehearsals and gigs both covered in all impacted surfaces.
- Availability prompts still show correct event metadata and submit responses normally.
- Detail drawers remain unchanged and continue to represent source-of-truth display.
- Cross-platform parity: Web, iOS, Android, macOS.
- No regressions in upcoming/past event grouping and sorting.

## 17. Rollout / Migration Strategy

- Rollout as normal Flutter client update.
- No DB migration.
- No edge-function deploy.
- No feature flag required.

## 18. Out of Scope

- Any change to `TimezoneHelper.toUtc`.
- Any repository/controller filtering/sorting refactor.
- Any change to stored event time model or database schema.
- Any timezone conversion feature for user-local display.
- Any unrelated cleanup outside listed files.
