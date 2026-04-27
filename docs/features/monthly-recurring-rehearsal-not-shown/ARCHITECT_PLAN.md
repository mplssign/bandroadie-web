# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/monthly-recurring-rehearsal-not-shown`

## 2. Problem Summary

Monthly recurring rehearsals do not appear on the calendar. When a user creates a rehearsal with recurring enabled and frequency set to "Monthly," only the parent rehearsal (the initial date) is created — no recurring child instances are generated. Weekly recurrence works correctly. The bug is isolated to the monthly frequency path and affects all platforms.

## 3. Root Cause

**Two root causes confirmed, working together to produce the observed symptom.**

### Root Cause A — Empty `daysOfWeek` causes zero instance generation

**Confidence: HIGH** (confirmed by direct code observation)

**Location:** `lib/features/events/events_repository.dart` line 173, `lib/features/events/widgets/event_editor_drawer.dart` lines 231 and 741.

The `_generateRecurringDates` function iterates over `recurrence.daysOfWeek` to produce dates. When `daysOfWeek` is empty, the inner loop executes zero times, and the fallback `return dates.isEmpty ? [formData.date] : dates` returns only the start date — producing exactly one rehearsal (the parent) with no recurring instances.

**How `daysOfWeek` becomes empty:**

1. `initState()` (line 231) pre-sets `_selectedDays = {Weekday.values[_selectedDate.weekday % 7]}` — e.g., `{Monday}` for a Monday date. This runs _before_ the user enables recurring.
2. When the user enables recurring via `_toggleRecurring(true)` (line 741), the guard `if (value && _selectedDays.isEmpty)` evaluates to `false` because `_selectedDays` was already set in `initState`. The auto-select code is **dead code** in create mode.
3. The user sees Monday highlighted in the day picker. They tap Monday to "confirm" their day selection (step 4 of reproduction). The toggle logic removes it: `_selectedDays.remove(day)` → `_selectedDays = {}`.
4. The user changes frequency to Monthly, then saves. The form data has `daysOfWeek: {}`.
5. `_generateRecurringDates` returns `[formData.date]` → only 1 row inserted → zero recurring instances on the calendar.

**Why weekly works:** In the typical weekly flow, users enable recurring and save immediately with defaults. They accept the pre-selected day without tapping it. The day chip stays highlighted, `daysOfWeek` is non-empty, and dates generate correctly.

**Why monthly fails:** The reproduction flow explicitly involves tapping the day chip ("Select Monday"), then changing frequency. Tapping the already-highlighted chip deselects it. No validation prevents saving with empty `daysOfWeek`.

### Root Cause B — Monthly approximated as "every 4 weeks" instead of true calendar months

**Confidence: HIGH** (confirmed in code — `events_repository.dart` line 161)

```dart
final weekInterval = switch (recurrence.frequency) {
  RecurrenceFrequency.weekly => 1,
  RecurrenceFrequency.biweekly => 2,
  RecurrenceFrequency.monthly => 4, // Approximate monthly as 4 weeks
};
```

Monthly recurrence uses `weekInterval = 4`, producing events every 28 days instead of true calendar-month intervals. Even when `daysOfWeek` is correctly populated, the generated dates diverge from expected monthly cadence:

- Months have 28–31 days; 28 ≠ 1 month.
- Example: A "3rd Monday" rehearsal starting Jan 19 generates dates: Jan 19, Feb 16, Mar 16, Apr 13, May 11... By April, the event falls on the _2nd_ Monday, not the 3rd. The user checks the expected date and finds nothing.
- After fixing Root Cause A, this bug would surface as "events appear on wrong dates."

### Combined effect

Root Cause A produces the primary symptom: "no instances appear" (zero child rows created). Root Cause B would produce a secondary symptom after A is fixed: events on incorrect monthly dates. Both must be fixed.

## 4. Reference Docs Consulted

| Path                                             | Status                                                                  |
| ------------------------------------------------ | ----------------------------------------------------------------------- |
| `docs/reference/rehearsals/`                     | **Does not exist**                                                      |
| `docs/reference/calendar/`                       | **Does not exist**                                                      |
| `docs/reference/general/AI_DECISIONS.md`         | Read — no decisions related to rehearsal recurrence or calendar display |
| `docs/reference/architecture/database_schema.md` | Read — confirmed rehearsals table schema and recurrence fields          |

## 5. Existing System Analysis

### Data flow: creation → storage → calendar query → display

```
1. EVENT EDITOR (event_editor_drawer.dart)
   └─ _buildFormData() assembles EventFormData with RecurrenceConfig
      └─ RecurrenceConfig { daysOfWeek: Set<Weekday>, frequency, untilDate }

2. EVENTS REPOSITORY (events_repository.dart)
   └─ createRehearsal() calls _generateRecurringDates(formData)
      └─ Returns List<DateTime> of all occurrence dates
   └─ For each date: INSERT into rehearsals table
      └─ First row: parent (parent_rehearsal_id = null)
      └─ Subsequent rows: children (parent_rehearsal_id = parent.id)

3. REHEARSAL REPOSITORY (rehearsal_repository.dart)
   └─ fetchRehearsalsForBand(): SELECT * FROM rehearsals WHERE band_id = ?
      └─ No recurrence expansion — returns raw rows

4. CALENDAR CONTROLLER (calendar_controller.dart)
   └─ _loadEventsForBand() fetches rehearsals, gigs, block_outs
   └─ Maps each Rehearsal → CalendarEvent.fromRehearsal()
      └─ One CalendarEvent per DB row, no virtual expansion

5. CALENDAR UI (calendar_screen.dart, calendar_grid.dart)
   └─ Displays CalendarEvent list on date cells
   └─ No frequency-based branching — all rehearsals treated identically
```

### Architecture: Fan-out at creation time

Recurrence instances are **materialized as physical rows** at creation time. There is no virtual recurrence expansion. The calendar, the rehearsal repository, the calendar-feed edge function, and the `get_band_full_state` RPC all read flat rows. If rows aren't inserted, nothing appears.

### Weekly vs. Monthly comparison

| Aspect                           | Weekly                                          | Monthly                                         |
| -------------------------------- | ----------------------------------------------- | ----------------------------------------------- |
| `weekInterval`                   | 1 (7 days)                                      | 4 (28 days)                                     |
| `_selectedDays` state at save    | Typically non-empty (user doesn't tap day chip) | Potentially empty (user taps pre-selected chip) |
| Dates generated (non-empty days) | ~52 per selected day per year                   | ~13 per selected day per year                   |
| Dates generated (empty days)     | 1 (parent only)                                 | 1 (parent only)                                 |
| Date accuracy                    | Correct (7 days = 1 week)                       | Incorrect (28 days ≠ 1 month)                   |
| Calendar display                 | Works                                           | Fails (zero child rows, or wrong dates)         |

## 6. Proposed Solution

### Fix 1: Replace monthly date generation with calendar-month logic

In `_generateRecurringDates`, add a separate monthly code path that uses true calendar-month arithmetic instead of the week-interval approach.

**Algorithm for monthly:**

1. Determine which occurrence of the weekday the start date falls on within its month (e.g., "3rd Monday" → occurrence = 3).
2. For each month from start through `untilDate`, compute the Nth occurrence of each selected weekday.
3. If the Nth occurrence doesn't exist in a given month (e.g., 5th Monday), skip that month for that day.

This preserves the existing weekly/biweekly code path unchanged. Only the monthly branch diverges.

### Fix 2: Defensive validation for empty `daysOfWeek`

In `_generateRecurringDates`, before iterating, if `daysOfWeek` is empty, auto-populate it with the weekday of `formData.date`. This ensures at minimum the start date's weekday is used for generation, preventing the zero-instance scenario regardless of UI state.

This is a **safety net inside the generation function**, not a UI change. It prevents data loss without modifying user-facing behavior.

### What must NOT change

- Weekly and biweekly date generation (existing week-interval logic)
- The insert loop in `createRehearsal` / `_updateAndGenerateRecurringSeries`
- Calendar query/display logic (no frequency-based branching needed)
- Database schema (no migration needed)
- Rehearsal model, CalendarEvent model
- Notification trigger logic
- RLS policies

## 7. Database Impact

**Database: not applicable.**

| Area                               | Status                         |
| ---------------------------------- | ------------------------------ |
| `rehearsals` table schema          | Unaffected — no column changes |
| RLS policies on `rehearsals`       | Unaffected                     |
| `notify_rehearsal_created` trigger | Unaffected                     |
| `get_band_full_state` RPC          | Unaffected                     |
| `calendar-feed` edge function      | Unaffected                     |
| Migrations                         | Not required                   |

The bug is entirely in client-side date generation logic. All DB components correctly store and retrieve whatever rows the client inserts.

## 8. Flutter Architecture Changes

| Component                                  | Change                                                                     |
| ------------------------------------------ | -------------------------------------------------------------------------- |
| `EventsRepository._generateRecurringDates` | Add monthly code path with calendar-month logic; add empty-days safety net |
| State management                           | Unaffected                                                                 |
| Widgets                                    | Unaffected                                                                 |
| Models                                     | Unaffected                                                                 |
| Other repositories                         | Unaffected                                                                 |

No new controllers, providers, repositories, or architectural patterns are introduced.

## 9. Files to Create

None.

## 10. Files to Modify

| File                                         | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/events_repository.dart` | 1. In `_generateRecurringDates`: add defensive guard at top — if `daysOfWeek` is empty, default to the weekday of `formData.date`. 2. Replace the `RecurrenceFrequency.monthly => 4` branch with a separate monthly generation block that uses calendar-month arithmetic (Nth weekday occurrence per month). 3. Add private helper `_nthWeekdayOfMonth(int year, int month, int weekday, int occurrence)` that computes the date of the Nth occurrence of a given weekday in a given month. 4. Add private helper `_weekdayOccurrenceInMonth(DateTime date)` that returns which occurrence (1st, 2nd, 3rd, etc.) of its weekday the given date is within its month. |

## 11. Files Off-Limits

| File                                                     | Reason                                                                                                                                                                                                                                              |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                          | Init order must not change                                                                                                                                                                                                                          |
| `lib/features/calendar/calendar_controller.dart`         | Calendar reads flat rows — no change needed                                                                                                                                                                                                         |
| `lib/features/calendar/models/calendar_event.dart`       | Model is correct                                                                                                                                                                                                                                    |
| `lib/features/rehearsals/rehearsal_repository.dart`      | Query is correct                                                                                                                                                                                                                                    |
| `lib/app/models/rehearsal.dart`                          | Model is correct                                                                                                                                                                                                                                    |
| `lib/features/events/models/event_form_data.dart`        | Data classes are correct                                                                                                                                                                                                                            |
| `lib/features/events/widgets/event_editor_drawer.dart`   | The `initState` day pre-selection (line 231) and dead auto-select guard (line 741) are UX issues that could be improved but are **out of scope** for this bug fix. The defensive guard in `_generateRecurringDates` covers the empty-days scenario. |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | UI widget is correct                                                                                                                                                                                                                                |
| `supabase/migrations/*`                                  | No schema changes                                                                                                                                                                                                                                   |
| `supabase/functions/*`                                   | No edge function changes                                                                                                                                                                                                                            |

## 12. System Impact Map

| System                                 | Impact                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| Rehearsals                             | **Affected** — monthly recurrence date generation is fixed     |
| Calendar                               | **Unaffected** — displays whatever rows exist; no code changes |
| Gigs                                   | Unaffected                                                     |
| Setlists / Catalog                     | Unaffected                                                     |
| Members / RBAC                         | Unaffected                                                     |
| Auth / Session                         | Unaffected                                                     |
| Notifications                          | Unaffected — trigger fires correctly for parent rehearsals     |
| Platform (iOS / Android / Web / macOS) | Unaffected — fix is in shared Dart code                        |

## 13. Regression Risk

**MEDIUM**

Rationale:

- The fix modifies `_generateRecurringDates`, which is the shared date generation function for **all** recurrence frequencies (weekly, biweekly, monthly). A mistake here could break weekly/biweekly.
- **Mitigation:** The weekly/biweekly code path (week-interval loop) is left unchanged. The monthly path branches into a new block. No shared logic is modified.
- Auth, session, routing, and init order are untouched.
- Database mutations (INSERT) are unchanged — only the _dates list_ passed to the existing insert loop changes.
- No new dependencies.

## 14. Engineer Task Breakdown

Execute in order. Each task is atomic.

### Task 1: Add `_weekdayOccurrenceInMonth` helper

In `events_repository.dart`, add a private method that, given a `DateTime`, returns which occurrence (1-based) of its weekday it is within the month.

```
Example: April 20, 2026 (Monday)
  → April has Mondays on: 6, 13, 20, 27
  → April 20 is the 3rd Monday → returns 3
```

### Task 2: Add `_nthWeekdayOfMonth` helper

In `events_repository.dart`, add a private method that, given a year, month, target weekday (0=Sun..6=Sat), and occurrence number (1-based), returns the `DateTime` of that occurrence, or `null` if it doesn't exist (e.g., 5th Monday in a month with only 4).

```
Example: _nthWeekdayOfMonth(2026, 5, 1, 3) → May 18, 2026 (3rd Monday of May)
```

**Weekday mapping note:** The `Weekday` enum uses 0=Sun, 1=Mon, ..., 6=Sat. Dart's `DateTime.weekday` uses 1=Mon, ..., 7=Sun. The helper must handle this conversion correctly.

### Task 3: Add empty-days safety net

At the top of `_generateRecurringDates`, after the `if (!formData.isRecurring || formData.recurrence == null)` guard, add:

If `recurrence.daysOfWeek` is empty, create a local copy of the recurrence config with `daysOfWeek` defaulted to the weekday of `formData.date` (using the same `_selectedDate.weekday % 7` → `Weekday` mapping). Use this local config for the rest of the function.

This prevents the zero-instance scenario regardless of UI state.

### Task 4: Implement monthly date generation branch

In `_generateRecurringDates`, replace the `RecurrenceFrequency.monthly => 4` approximation with a separate code path:

1. Remove `monthly` from the `weekInterval` switch (or keep it but skip the week-interval loop for monthly).
2. Before the existing `while` loop, add an `if (frequency == monthly)` branch:
   a. Use `_weekdayOccurrenceInMonth(formData.date)` to determine the occurrence number (N).
   b. Iterate month-by-month from `formData.date`'s month through `untilDate`'s month (with a safety cap, e.g., 24 months).
   c. For each month, for each day in `daysOfWeek`, call `_nthWeekdayOfMonth(year, month, day.dayIndex, N)`.
   d. If the result is non-null, within date range, and not before `formData.date`, add it to the dates list.
3. The existing `while` loop continues to handle weekly and biweekly unchanged.

### Task 5: Verify no changes to weekly/biweekly path

Confirm that the weekly and biweekly branches of the `weekInterval` switch and the `while` loop remain **byte-for-byte identical** to the current code. The monthly branch must diverge cleanly without affecting shared logic.

## 15. Verification Plan

### Tier 1 — Pre-deployment (no schema changes; all tests are local Dart logic)

All tests exercise `_generateRecurringDates` logic. Since this is a private method, tests should call `createRehearsal` with mock Supabase or test `_generateRecurringDates` via extraction to a testable function. Alternatively, the Engineer may make `_generateRecurringDates` `@visibleForTesting` to unit test directly.

**-- PRE-DEPLOY TEST 1: Monthly generates correct Nth-weekday dates**

- Input: start = Monday April 20, 2026 (3rd Monday); frequency = monthly; daysOfWeek = {Monday}; untilDate = null (defaults to +1 year).
- Expected: 12–13 dates, each the 3rd Monday of its month (Apr 20, May 18, Jun 15, Jul 20, Aug 17, Sep 21, Oct 19, Nov 16, Dec 21, Jan 18, Feb 15, Mar 15, Apr 19).
- Verify: No two consecutive dates are exactly 28 days apart (confirms calendar-month logic, not 4-week).

**-- PRE-DEPLOY TEST 2: Monthly with 5th-weekday handling**

- Input: start = Thursday Jan 29, 2026 (5th Thursday); frequency = monthly; daysOfWeek = {Thursday}; untilDate = July 31, 2026.
- Expected: Only months with a 5th Thursday are included (Jan 29, Apr 30, Jul 30). Months without a 5th Thursday are skipped.

**-- PRE-DEPLOY TEST 3: Monthly with multiple selected days**

- Input: start = Wednesday April 15, 2026 (3rd Wednesday); frequency = monthly; daysOfWeek = {Monday, Wednesday}; untilDate = July 31, 2026.
- Expected: Generates 3rd Monday AND 3rd Wednesday of each month from April through July.

**-- PRE-DEPLOY TEST 4: Empty daysOfWeek safety net**

- Input: start = Monday April 20, 2026; frequency = monthly; daysOfWeek = {} (empty); untilDate = null.
- Expected: Safety net populates daysOfWeek with {Monday}. Result is identical to PRE-DEPLOY TEST 1.

**-- PRE-DEPLOY TEST 5: Weekly unchanged (regression)**

- Input: start = Monday April 20, 2026; frequency = weekly; daysOfWeek = {Monday}; untilDate = null.
- Expected: 52 dates, each Monday, each exactly 7 days apart. Identical to current behavior.

**-- PRE-DEPLOY TEST 6: Biweekly unchanged (regression)**

- Input: start = Monday April 20, 2026; frequency = biweekly; daysOfWeek = {Monday}; untilDate = null.
- Expected: 26 dates, each Monday, each exactly 14 days apart. Identical to current behavior.

**-- PRE-DEPLOY TEST 7: Monthly with untilDate boundary**

- Input: start = Monday April 20, 2026; frequency = monthly; daysOfWeek = {Monday}; untilDate = June 30, 2026.
- Expected: 3 dates (Apr 20, May 18, Jun 15). No date after June 30.

### Tier 2 — Post-deployment

Not applicable. No database changes required. All verification is Dart-side.

## 16. QA Regression Areas

### Primary (must pass)

1. **Monthly recurring rehearsal creation and calendar display:**
   - Create a monthly recurring rehearsal on a Monday. Verify instances appear on the 3rd (or Nth) Monday of each subsequent month through the recurrence period.
   - Verify the correct number of child rehearsal rows exist in the database.
   - Navigate the calendar across multiple months and confirm instances appear on expected dates.

2. **Monthly recurring with "Until" date:**
   - Create a monthly recurring rehearsal with an end date 6 months out. Verify no instances appear beyond the end date.

3. **Monthly recurring with multiple days:**
   - Create a monthly recurring rehearsal with Monday and Wednesday selected. Verify both days generate instances each month.

### Regression (must not break)

4. **Weekly recurring rehearsal display:**
   - Create a weekly recurring rehearsal. Verify instances appear every 7 days on the selected day(s). Behavior must be identical to current working behavior.

5. **Biweekly recurring rehearsal display:**
   - Create a biweekly recurring rehearsal. Verify instances appear every 14 days.

6. **Recurrence form: day selection + frequency switching:**
   - Enable recurring, observe auto-selected day. Change frequency between weekly/biweekly/monthly. Verify selected days persist across frequency changes.
   - Deselect all days, then save. Verify the safety net produces at least the start date's day.

7. **Edit existing recurring rehearsal:**
   - Edit a weekly recurring rehearsal. Verify no data loss or unexpected changes.
   - Edit a monthly recurring rehearsal (created after fix). Verify instances update correctly.

8. **Calendar across multiple months:**
   - Navigate forward and backward through months. Verify monthly rehearsal instances appear in correct month cells.
   - Verify calendar markers (dots) appear on the correct dates.

9. **Notification for recurring rehearsal:**
   - Create a monthly recurring rehearsal. Verify only one notification fires (for the parent), not per child.

## 17. Rollout / Migration Strategy

**No migration required.** The fix is a client-side Dart code change in the date generation function.

- **Existing monthly recurring rehearsals** created before this fix will have incorrect or missing child rows. These are not retroactively corrected by this fix. If correction is desired, it would require a separate cleanup task (out of scope).
- **New monthly recurring rehearsals** created after the fix will generate correct dates.
- **Rollback:** Revert the single file change (`events_repository.dart`). Weekly/biweekly behavior is unaffected by rollback since their code path is unchanged.

## 18. Out of Scope

1. **Retroactive correction of existing monthly rehearsal rows** — Existing incorrectly-generated (or missing) monthly instances are not fixed by this change. A cleanup migration could address this but is a separate task.
2. **`initState` pre-selection UX fix** — The fact that `_selectedDays` is set in `initState` before recurring is enabled (making the `_toggleRecurring` auto-select dead code) is a UX issue. The defensive guard in `_generateRecurringDates` covers the data integrity concern. The UX fix is a separate enhancement.
3. **Validation UI for empty days** — Adding a visible error message when the user tries to save a recurring event with no days selected would improve UX but is not required for this bug fix.
4. **"Same date each month" recurrence mode** — Some calendar apps offer "monthly on the 20th" in addition to "monthly on the 3rd Monday." This is a feature enhancement, not part of this bug fix.
5. **Transaction wrapping for multi-insert** — The `createRehearsal` loop inserts rows one-by-one without a transaction. A failure mid-loop leaves a partial series. This is a pre-existing issue unrelated to this bug.
