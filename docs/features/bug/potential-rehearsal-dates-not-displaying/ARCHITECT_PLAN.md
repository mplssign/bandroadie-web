# ARCHITECT PLAN: Potential Rehearsal Dates Not Displaying

**Slug:** `bug/potential-rehearsal-dates-not-displaying`  
**Branch:** `bug/potential-rehearsal-dates-not-displaying`  
**Type:** Bug Fix  
**Confidence:** HIGH (root cause confirmed in code)  
**Database changes required:** None  
**STOP required:** No

---

## 1. Bug Summary

When a rehearsal is marked as potential and additional date/time options are saved, the `RehearsalCard` on the home screen does not display those dates. The card shows only the primary date and presents single-date YES/NO availability buttons — no multi-date navigation arrows, no "Multiple Dates" chip label, no per-date cycling.

The equivalent flow for **Potential Gigs works correctly**: `PotentialGigCard` receives `gig.additionalDates` and shows per-date pagination.

---

## 2. Root Causes

### Root Cause A — PRIMARY (HIGH confidence, confirmed)

**File:** `lib/features/home/home_tab_content.dart` (line ~1082)  
**Nature:** Missing prop wiring — `additionalDates` is never passed to `RehearsalCard`

`RehearsalCard` has a full multi-date implementation — `_sortedDates`, date-navigation arrows, the "Multiple Dates" chip suffix, and per-date YES/NO responses. But the constructor parameter `additionalDates` defaults to `const []` and the call site in `home_tab_content.dart` never sets it.

The code even has a comment acknowledging the gap:

```dart
// home_tab_content.dart  ~line 1082
return SizedBox(
  width: Spacing.potentialGigCardWidth,
  child: RehearsalCard(
    rehearsal: rehearsal,
    setlistName: setlistName,
    bandTimezone: bandTimezone,
    // additionalDates defaults to [] until Rehearsal model is extended  ← stale comment
    perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
    onRespondForDate: ...,
    onTap: () => _openEditRehearsalSheet(rehearsal),
  ),
);
```

The `Rehearsal` model **was** extended — it has `additionalDates: List<RehearsalDate>` populated from the `rehearsal_dates` join in the `get_band_full_state` RPC. The comment was never removed and the prop was never wired up.

**Fix (one line):** Add `additionalDates: rehearsal.additionalDates` to the `RehearsalCard` constructor call and remove the stale comment.

**Comparison with working gig flow:**

```dart
// home_tab_content.dart — gig path (WORKING)
return PotentialGigCard(
  gig: gig,
  ...
  perDateUserResponses: gigAllDateResponses[gig.id],  // ← passed correctly
  ...
);
```

`PotentialGigCard` takes the gig directly and accesses `gig.additionalDates` internally. `RehearsalCard` instead takes `additionalDates` as an explicit prop — but it was never provided.

---

### Root Cause B — SECONDARY (HIGH confidence, confirmed)

**File:** `lib/features/rehearsals/rehearsal_repository.dart`  
**Nature:** Missing `start_time` column in `_rehearsalSelectClause`

`_rehearsalSelectClause` (used by `CalendarController` via `RehearsalRepository.fetchRehearsalsForBand`) does not include `start_time` in the `rehearsal_dates` sub-select:

```dart
// CURRENT (broken)
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    created_at,
    updated_at
  )
''';
```

The `start_time` column was added to `rehearsal_dates` in migration `20260521000000_add_start_time_to_date_tables.sql`. That migration also updated the `get_band_full_state` RPC to include `start_time`. The Dart client `_rehearsalSelectClause` was not updated.

**Impact:** When a potential rehearsal is opened for editing **from the calendar**, each `RehearsalDate.startTime` is `null`. `EventFormData.fromRehearsal` falls back to the primary rehearsal start time for all dates, so per-date times are shown incorrectly in the edit form.

> **Note:** The home screen is unaffected by this bug because `RehearsalNotifier` sources data from `bandFullStateProvider` (the RPC), which correctly includes `start_time`. The calendar path is the sole affected consumer.

**Comparison with correct implementation:**

```dart
// events_repository.dart line 512 — CORRECT
.select('*, rehearsal_dates(id, rehearsal_id, date, start_time, created_at, updated_at)')
```

**Fix:** Add `start_time` between `date` and `created_at` in `_rehearsalSelectClause`.

---

### Root Cause C — TERTIARY (MEDIUM confidence, no code change required)

**File:** `lib/features/calendar/models/calendar_event.dart`  
**Nature:** `isPotentialGig` getter never returns true for rehearsals

```dart
// CalendarEvent
bool get isPotentialGig => isGig && (gig?.isPotential ?? false);
```

This getter is used in edit-permission gating:

```dart
canEditEvent = editPerms.canEditGigs ||
    (event.isPotentialGig && editPerms.canEditPotentialGigs);
```

For a potential rehearsal, `event.isPotentialGig` is always `false`. The `canEditPotentialGigs` shortcut never applies. However, `canEditGigs` alone still grants edit access to rehearsals in the current permission model, so no functional regression is observed. This is a naming/semantic inconsistency worth documenting but is **out of scope** for this bug fix — it requires a permission-model design decision.

---

## 3. Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `lib/features/home/home_tab_content.dart` | Add `additionalDates: rehearsal.additionalDates` to `RehearsalCard(...)` call; remove stale comment | PRIMARY FIX |
| `lib/features/rehearsals/rehearsal_repository.dart` | Add `start_time` to `_rehearsalSelectClause` under `rehearsal_dates (...)` | SECONDARY FIX |

**No other files need changes.** The `RehearsalCard` multi-date implementation is complete and correct. The `Rehearsal` model already exposes `additionalDates`. The `rehearsal_dates` table schema is correct (including `start_time`). The `get_band_full_state` RPC is correct.

---

## 4. Data Flow Summary

### Home screen path (Primary bug)

```
bandFullStateProvider (RPC get_band_full_state)
  └─ rehearsalProvider.potentialRehearsals  [Rehearsal.additionalDates populated ✓]
       └─ home_tab_content._buildHorizontalPotentialEvents()
            └─ RehearsalCard(additionalDates: const [])  ← BUG: should be rehearsal.additionalDates
```

### Calendar edit path (Secondary bug)

```
RehearsalRepository.fetchRehearsalsForBand()  [uses _rehearsalSelectClause]
  └─ CalendarController._loadEventsForBand()
       └─ CalendarEvent.fromRehearsal(rehearsal)  [rehearsal.additionalDates populated, startTime = null]
            └─ AddEditEventBottomSheet.show(initialData: EventFormData.fromRehearsal(...))
                 └─ EventFormData.fromRehearsal: per-date times fall back to primary time ← BUG
```

---

## 5. No Database Changes

`rehearsal_dates` table is correct. `start_time TEXT` was added in migration `20260521000000`. RLS policies are correct. The bug is **entirely client-side**.

---

## 6. System Impact

| Area | Affected? | Notes |
|------|-----------|-------|
| Potential Rehearsal card (home screen) | ✅ YES | Root Cause A fix |
| Calendar edit flow for potential rehearsals | ✅ YES | Root Cause B fix |
| Create flow (editor) | ✗ NO | `_buildProposedDatesSection` logic is correct |
| Gigs | ✗ NO | Unaffected |
| Setlists / Catalog | ✗ NO | Unaffected |
| Member responses / RBAC | ✗ NO | Unaffected |
| Auth / Session | ✗ NO | Unaffected |

---

## 7. Implementation Notes for Developer

### Fix A — `home_tab_content.dart`

Locate the `RehearsalCard(...)` constructor call inside `_buildHorizontalPotentialEvents`. Remove the stale comment and add the prop:

```dart
// BEFORE
RehearsalCard(
  rehearsal: rehearsal,
  setlistName: setlistName,
  bandTimezone: bandTimezone,
  // additionalDates defaults to [] until Rehearsal model is extended
  perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
  ...
)

// AFTER
RehearsalCard(
  rehearsal: rehearsal,
  setlistName: setlistName,
  bandTimezone: bandTimezone,
  additionalDates: rehearsal.additionalDates,
  perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
  ...
)
```

### Fix B — `rehearsal_repository.dart`

Add `start_time` to `_rehearsalSelectClause`:

```dart
// BEFORE
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    created_at,
    updated_at
  )
''';

// AFTER
const _rehearsalSelectClause = '''
  *,
  rehearsal_dates (
    id,
    rehearsal_id,
    date,
    start_time,
    created_at,
    updated_at
  )
''';
```

---

## 8. Verification Steps

1. Create a potential rehearsal with 2–3 additional dates (different times per date)
2. Save and return to the home screen
3. **Expected:** `RehearsalCard` shows "POTENTIAL REHEARSAL: Multiple Dates" chip, navigation arrows `←` / `→`, date-specific YES/NO buttons
4. Open the rehearsal from the calendar for editing
5. **Expected:** Each additional date shows its own saved time (not the primary rehearsal time)
6. Confirm single-date potential rehearsal still renders without navigation arrows and without "Multiple Dates" suffix

---

## 9. Diagnosis Reference

| Evidence | Location |
|----------|----------|
| `additionalDates = const []` default, never passed | `lib/features/home/home_tab_content.dart` ~line 1082 |
| `RehearsalCard._isMultiDate` gates multi-date UI | `lib/features/home/widgets/rehearsal_card.dart` ~line 79 |
| `_sortedDates` uses `widget.additionalDates` | `lib/features/home/widgets/rehearsal_card.dart` ~line 70 |
| Stale comment acknowledging the gap | `lib/features/home/home_tab_content.dart` ~line 1084 |
| `_rehearsalSelectClause` missing `start_time` | `lib/features/rehearsals/rehearsal_repository.dart` ~line 20 |
| `events_repository.dart` includes `start_time` correctly | `lib/features/events/events_repository.dart` ~line 512 |
| Migration adds `start_time` to `rehearsal_dates` | `supabase/migrations/20260521000000_add_start_time_to_date_tables.sql` |
| RPC `get_band_full_state` includes `start_time` | `supabase/migrations/20260521000000_add_start_time_to_date_tables.sql` |
| `Rehearsal.additionalDates` populated from RPC | `lib/features/rehearsals/rehearsal_controller.dart` + `lib/app/models/rehearsal.dart` |
