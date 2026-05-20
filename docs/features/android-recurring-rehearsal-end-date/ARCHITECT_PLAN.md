# Architect Plan: Android Recurring Rehearsal End Date Bug

## Feature Slug

`bug/android-recurring-rehearsal-end-date`

## Problem Summary

An Android user reported that creating a weekly recurring rehearsal starting June 4 and ending June 11 only created the June 4 rehearsal, not both expected dates. Tony confirmed the same recurring rehearsal flow works successfully on iOS and web, initially suggesting an Android-only issue. However, code inspection reveals this is a **platform-agnostic logic bug** that affects all platforms. The issue likely went unnoticed on iOS/web due to specific testing conditions or date selections that masked the symptom.

The root cause is a **time-of-day mismatch** in date comparisons within the recurring date generation logic. The date picker returns midnight (`00:00:00`), but recurring dates are generated at noon (`12:00:00`). When the last occurrence falls on the until date, the noon time is considered "after" midnight, causing the final occurrence to be excluded.

## Root Cause

**Confidence Level:** `HIGH` (confirmed by direct code inspection)

When a user selects an "until" date for a recurring rehearsal:

1. `showDatePicker()` returns a `DateTime` at midnight (`2026-06-11T00:00:00`)
2. The date is stored in `_untilDate` without normalization
3. During recurring date generation in `_generateRecurringDates()`, dates are created at noon:
   ```dart
   final dateForDay = DateTime(
     currentWeekStart.year,
     currentWeekStart.month,
     currentWeekStart.day + day.dayIndex,
     12,  // ← Generated at noon
   );
   ```
4. The comparison `!dateForDay.isAfter(untilDate)` excludes dates at noon on the until date because `DateTime(2026-06-11T12:00:00).isAfter(DateTime(2026-06-11T00:00:00))` returns `true`
5. Result: The last occurrence is excluded from the generated list

**Example scenario (bug reproduction):**

- Start: June 4, 2026 (Wednesday)
- Until: June 11, 2026 (user picks this date → stored as `2026-06-11T00:00:00`)
- Frequency: Weekly on Wednesdays

**Generation trace:**

1. First week: June 4 at 12:00 → included ✓
2. Second week: June 11 at 12:00 → `12:00 > 00:00` → excluded ✗

**Why iOS/web appeared to work:**
The code path is identical across platforms (no platform-specific logic found). Likely explanations for the discrepancy in Tony's testing:

- Different date selections where the until date was beyond the last occurrence
- Testing a monthly recurrence where the logic differs
- Timezone differences affecting DST or date display (though the core bug still exists)

## Reference Docs Consulted

No domain-specific reference docs exist for rehearsals or recurring events in `docs/reference/`. The investigation relied entirely on source code inspection.

## Existing System Analysis

**Current data flow (rehearsal creation with recurrence):**

1. **UI Layer** (`event_editor_drawer.dart`):
   - User toggles "Make this recurring"
   - User selects days of week, frequency, and taps "Until (optional)"
   - `_showUntilDatePicker()` displays native date picker
   - Returned date stored in `_untilDate` state at midnight (`00:00:00`)

2. **Form Serialization** (`_buildFormData()`):
   - Creates `RecurrenceConfig` with `untilDate: _untilDate` (midnight)
   - Wraps in `EventFormData`

3. **Repository Layer** (`events_repository.dart`):
   - `createRehearsal()` calls `_generateRecurringDates(formData)`
   - **Bug occurs here:** Dates generated at noon but compared against midnight until date
   - Returns list of dates to create (missing last occurrence)
   - Creates one `rehearsals` row per date with `parent_rehearsal_id` linkage

4. **Database**:
   - First rehearsal inserted with `parent_rehearsal_id = null`
   - Subsequent rehearsals inserted with `parent_rehearsal_id = firstRehearsalId`

**Time normalization pattern observed:**

- All recurring dates are generated at noon (12:00) for consistency
- Monthly recurrence uses `DateTime(year, month, dayOfMonth, 12)`
- Weekly/biweekly use `DateTime(year, month, day + dayIndex, 12)`
- **Missing:** Until date normalization to match this pattern

## Proposed Solution

**Normalize the until date to noon (`12:00`) when the user selects it from the date picker.**

This ensures the until date uses the same time-of-day as the generated recurring dates, allowing inclusive end-date comparisons.

**Change location:** `lib/features/events/widgets/event_editor_drawer.dart` in `_showUntilDatePicker()`

**Before:**

```dart
if (picked != null) {
  setState(() {
    _untilDate = picked;
  });
  _markDirty();
}
```

**After:**

```dart
if (picked != null) {
  setState(() {
    // Normalize to noon to match recurring date generation time
    _untilDate = DateTime(picked.year, picked.month, picked.day, 12);
  });
  _markDirty();
}
```

**Rationale:**

- **Minimal change:** Single-line modification in one method
- **Preserves existing patterns:** Noon is already the standard time for recurring dates
- **No database impact:** Time component is stripped when persisting (`toIso8601String().split('T')[0]`)
- **No breaking changes:** Existing recurring rehearsals unaffected (they already have the bug and will continue to behave as before until edited)
- **Platform-agnostic:** Fix applies uniformly across iOS, Android, web, and macOS

## Database Impact

**Not applicable.**

The until date is persisted to `rehearsals.recurrence_until` as a date-only string (time component stripped). The fix only affects in-memory date generation before persistence. No migration, RPC changes, or RLS updates required.

## Flutter Architecture Changes

**Affected:**

- `lib/features/events/widgets/event_editor_drawer.dart` - state management (date picker handler)

**Unaffected:**

- Event form data models (no signature changes)
- Event repository (date generation logic remains unchanged)
- Rehearsal controllers and providers

## Files to Create

`none`

## Files to Modify

| File                                                   | What changes                                                                                                                                                                                       |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | In `_showUntilDatePicker()`, normalize picked date to noon (12:00) when setting `_untilDate` to match the time used in recurring date generation. Add inline comment explaining the normalization. |

## Files Off-Limits

| File                                              | Reason                                                                                                                                |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/events_repository.dart`      | Date generation logic is correct and consistent. The bug is in the input data (until date at midnight), not the generation algorithm. |
| `lib/features/events/models/event_form_data.dart` | No model changes required. The `RecurrenceConfig` accepts `DateTime?` for `untilDate` and does not enforce time normalization.        |
| `lib/app/models/rehearsal.dart`                   | Database model unaffected. The until date is persisted as date-only.                                                                  |
| `lib/main.dart`                                   | Initialization order must not change.                                                                                                 |

## System Impact Map

| System                                 | Impact                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------- |
| Gigs                                   | `unaffected` — Gigs do not support recurrence yet (`isRecurring` throws "not yet supported") |
| Rehearsals                             | `affected` — Recurring rehearsal creation will now correctly include the last occurrence     |
| Setlists / Catalog                     | `unaffected` — No interaction with recurring events                                          |
| Members / RBAC                         | `unaffected` — No permission or role changes                                                 |
| Auth / Session                         | `unaffected` — No authentication flow changes                                                |
| Routing                                | `unaffected` — No navigation changes                                                         |
| Notifications                          | `unaffected` — Notification triggers are per-event, not per-series                           |
| Platform (iOS / Android / Web / macOS) | `affected` — All platforms benefit from the fix; behavior becomes uniform                    |

## Regression Risk

**Level:** `LOW`

**Rationale:**

- Single-line change in a date picker handler
- No database mutations
- No changes to shared services, providers, or state management
- No changes to form validation or submission logic
- Recurring rehearsals are already partially broken (missing last occurrence), so the fix only improves behavior
- Non-recurring rehearsals and all other event types are unaffected

**Risk mitigation:**

- The time normalization pattern (noon) is already used consistently in date generation
- Test coverage will validate that all dates in the recurrence range are created, including the first and last

## Engineer Task Breakdown

**Task 1:** Apply the date normalization fix

- Open `lib/features/events/widgets/event_editor_drawer.dart`
- Locate the `_showUntilDatePicker()` method (around line 2435)
- Replace the date assignment in the `if (picked != null)` block to normalize to noon
- Add an inline comment explaining the normalization matches recurring date generation

**Task 2:** Verify the fix locally

- Run `flutter analyze` to confirm no new errors
- Test creating a weekly recurring rehearsal with:
  - Start date: any Wednesday
  - Until date: exactly one week later (should create 2 rehearsals)
  - Until date: two weeks later (should create 3 rehearsals)
- Test on at least two platforms (iOS and Android preferred, or web if physical devices unavailable)
- Confirm that the last occurrence on the until date is now included

**Task 3:** Write Engineer Report

- Document the change made
- Include before/after code snippets
- List platforms tested and results
- Note any edge cases discovered during testing

## Verification Plan

### Tier 1 — Pre-deployment (n/a for client-side fix)

_No database changes to verify. This fix is entirely client-side._

### Tier 2 — Post-deployment (manual testing required)

**Test 1: Basic weekly recurrence with inclusive end date**

```
Platform: Android (primary), iOS (secondary)
1. Open event editor
2. Select event type: Rehearsal
3. Toggle "Make this recurring" ON
4. Select day: [current weekday]
5. Frequency: Weekly
6. Start date: [any date, e.g., June 4, 2026]
7. Until date: [exactly 1 week later, e.g., June 11, 2026]
8. Save
Expected: 2 rehearsals created (June 4, June 11)
Actual before fix: 1 rehearsal created (June 4 only)
Actual after fix: 2 rehearsals created ✓
```

**Test 2: Multi-week recurrence**

```
Platform: iOS or web
1. Create weekly recurring rehearsal
2. Start date: [any date]
3. Until date: [3 weeks later]
4. Expected: 4 rehearsals created (weeks 0, 1, 2, 3)
```

**Test 3: Multiple days selected (edge case)**

```
Platform: Android
1. Create weekly recurring rehearsal
2. Start date: Monday, June 2, 2026
3. Select days: Monday, Wednesday, Friday
4. Until date: Friday, June 6, 2026 (end of first week)
5. Expected: 3 rehearsals (Mon 6/2, Wed 6/4, Fri 6/6)
```

**Test 4: Biweekly recurrence**

```
Platform: Any
1. Create biweekly recurring rehearsal
2. Start date: June 4, 2026
3. Until date: June 18, 2026 (exactly 2 weeks later)
4. Expected: 2 rehearsals (June 4, June 18)
```

**Test 5: Monthly recurrence (confirm no regression)**

```
Platform: Any
1. Create monthly recurring rehearsal
2. Start date: First Monday of June 2026
3. Until date: First Monday of August 2026
4. Expected: 3 rehearsals (June, July, August)
```

**Test 6: Edit mode does not break**

```
Platform: Any
1. Create a simple non-recurring rehearsal
2. Edit it and toggle recurrence ON
3. Set until date
4. Expected: Series is generated correctly
```

**Test 7: Until date before start date (validation check)**

```
Platform: Any
1. Attempt to set until date BEFORE start date
2. Expected: Validation error or graceful handling (check existing validation logic)
```

## QA Regression Areas

**Primary:**

- Recurring rehearsal creation with various until dates (same day, 1 week, 2 weeks, 1 month, 1 year)
- All recurrence frequencies (weekly, biweekly, monthly)
- Multiple days of week selected for weekly/biweekly
- Cross-platform consistency (Android must match iOS/web behavior)

**Secondary:**

- Non-recurring rehearsals still create correctly
- Editing existing recurring rehearsals does not break
- Deleting a recurring rehearsal (single vs. entire series) works correctly
- Recurring rehearsal display on calendar matches created dates
- Potential rehearsals with recurrence (if supported)

**Edge cases:**

- Until date very far in future (e.g., 1 year) - should not generate excessive dates (check safety limit in code: `maxIterations = 52`)
- Until date = start date (should create only 1 rehearsal)
- No until date specified (should default to 1 year from start - existing behavior)
- DST transitions during recurrence range (ensure dates remain consistent)

## Rollout / Migration Strategy

**Deployment:** Standard web deployment via `./tools/deploy_web.sh`

**No migration required:**

- Client-side fix only
- Existing recurring rehearsals in database are unaffected
- Users who previously created recurring rehearsals with missing occurrences will need to delete and recreate them to get the correct series (or manually add the missing rehearsals)

**Communication:**

- No user-facing announcement needed (bug fix)
- Internal note: Existing recurring rehearsals may still have missing dates if created before this fix

## Out of Scope

- Retroactively fixing existing recurring rehearsals with missing dates (requires manual correction or deletion/recreation by users)
- Adding UI indication of how many rehearsals will be created before save
- Supporting recurring gigs (architecture exists but explicitly disabled with "not yet supported" error)
- Changing the time-of-day for recurring dates from noon to midnight (noon is the established pattern and works correctly)
- Timezone-aware recurrence (current implementation uses local device time consistently)
