# ARCHITECT PLAN — One Calendar Recurring Auto-Block (Incomplete Coverage)

## Feature Slug

`bug/one-calendar-recurring-auto-block`

---

## Problem Summary

**What:** With One Calendar and auto-conflict blocking enabled (functional since the 2026-07-07 column-defaults fix), creating a recurring rehearsal in one band creates a block-out in the user's other bands for the first occurrence only. Subsequent occurrences create no block-outs. Similarly, multi-date potential gigs only auto-block the main date, not additional dates.

**Why:** The auto-blocking integration was designed for single-date events. When recurring rehearsal support was added, the integration point at `events_repository.dart` line 164 was not updated to iterate all generated occurrence dates. The code calls `autoBlockConflictingDate()` once with `firstRehearsal.date` instead of looping through the `dates` list that was generated at line 91.

**Impact:** Multi-band users with recurring rehearsals or multi-date gigs receive incomplete conflict protection. Only the first/main date blocks; subsequent occurrences are not protected, leaving gaps in the conflict blocking that this feature was designed to provide.

---

## Root Cause

**Primary Failure:** Auto-blocking integration calls single-date method once instead of iterating all occurrence dates.

**Evidence:**

1. **Rehearsal creation flow** (`lib/features/events/events_repository.dart` lines 86-177):

   ```dart
   // Line 91: Generate all dates for recurring events
   final dates = _generateRecurringDates(formData);

   // Lines 98-145: Loop creates rehearsal records for ALL dates
   for (var i = 0; i < dates.length; i++) {
     final date = dates[i];
     // ... create rehearsal record ...
     if (isFirst) {
       firstRehearsal = Rehearsal.fromJson(response);
       // ...
     }
   }

   // Line 164: Auto-blocking called ONCE with first date only
   await _autoConflictBlockingService.autoBlockConflictingDate(
     userId: userId,
     eventBandId: bandId,
     eventDate: firstRehearsal.date,  // ⚠️ Only the first date
     // ...
   );
   ```

   The `dates` list containing all occurrences is available but never passed to the blocking service.

2. **Gig creation flow** (`lib/features/events/events_repository.dart` lines 627-657):

   ```dart
   // Line 627: Additional dates stored in gig_dates table
   if (formData.isPotentialGig && formData.additionalDates.isNotEmpty) {
     await _createGigDates(gigId, formData.additionalDates);
   }

   // Line 647: Auto-blocking called ONCE with main date only
   await _autoConflictBlockingService.autoBlockConflictingDate(
     userId: userId,
     eventBandId: bandId,
     eventDate: formData.date,  // ⚠️ Only the main date, not additionalDates
     // ...
   );
   ```

3. **Auto-blocking service signature** (`lib/features/calendar/auto_conflict_blocking_service.dart` lines 30-40):

   ```dart
   Future<void> autoBlockConflictingDate({
     required String userId,
     required String eventBandId,
     required DateTime eventDate,  // ⚠️ Single date parameter
     // ...
   }) async
   ```

   Method designed for single date; no overload accepting `List<DateTime>`.

4. **N+1 concern** (`auto_conflict_blocking_service.dart` lines 49-66):

   ```dart
   // Each call reads preferences and queries band_members
   final prefs = await _prefsRepository.getPreferences();  // DB read
   final bandsResponse = await supabase
       .from('band_members')
       .select('band_id')
       .eq('user_id', userId);  // DB read
   ```

   Calling the single-date method in a loop would cause N× preference reads for N occurrences.

**Historical Context:**

The "Secondary Issue" section of `docs/features/one-calendar-auto-block-not-propagating/ARCHITECT_PLAN.md` (2026-07-07) documented this exact problem but marked it out of scope while fixing the column defaults issue:

> **Observation:** Auto-conflict blocking only fires for the **first occurrence** of a recurring rehearsal, not for all occurrences.
>
> **Evidence** (`events_repository.dart` lines 150-177): [shows same code pattern]
>
> **Recommendation:** This is a **separate bug** that should be addressed in a follow-up feature: `bug/one-calendar-recurring-rehearsal-auto-block-incomplete`

That fix enabled One Calendar system-wide by changing column defaults. This fix completes the recurring rehearsal coverage.

**Root Cause Confidence:** `HIGH` — Confirmed by direct code observation in this session.

---

## Reference Docs Consulted

**Feature Documentation:**

- `docs/features/one-calendar-auto-block-not-propagating/ARCHITECT_PLAN.md` — Prior fix (column defaults), identified this as secondary issue
- `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md` — Original One Calendar design, considered database triggers vs. client-side approach

**Code Inspection:**

- `lib/features/events/events_repository.dart` — Rehearsal and gig creation flows (lines 86-177, 569-667)
- `lib/features/calendar/auto_conflict_blocking_service.dart` — Auto-blocking service implementation (lines 30-113)
- `lib/features/calendar/one_calendar_preferences_repository.dart` — Preference reads and band resolution
- `lib/features/calendar/block_out_repository.dart` — Block-out creation (referenced by service)

**Guardrails:**

- `docs/agents/GUARDRAILS.md` — Code change discipline, no opportunistic refactors
- `docs/agents/OPERATING_MODEL.md` — Minimal diff surface principle

---

## Existing System Analysis

### How Recurring Rehearsals Are Created

**Date Generation** (`events_repository.dart` line 198+):

The `_generateRecurringDates()` method generates all occurrence dates based on recurrence config (weekly, biweekly, monthly). Returns a `List<DateTime>` containing all dates from start date through `untilDate` or 1 year maximum.

**Rehearsal Record Creation** (`events_repository.dart` lines 98-145):

```dart
for (var i = 0; i < dates.length; i++) {
  final date = dates[i];
  final isFirst = i == 0;

  // Create rehearsal record with parent_rehearsal_id linkage
  final data = {
    'band_id': bandId,
    'date': date.toIso8601String().split('T')[0],
    // ... other fields ...
    'parent_rehearsal_id': isFirst ? null : parentId,
  };

  final response = await supabase.from('rehearsals').insert(data).select().single();

  if (isFirst) {
    firstRehearsal = Rehearsal.fromJson(response);
    parentId = firstRehearsal.id;
  }
}
```

Each occurrence gets its own row in the `rehearsals` table. The first becomes the parent; others link via `parent_rehearsal_id`.

**Auto-Blocking Call** (`events_repository.dart` lines 150-177):

```dart
if (firstRehearsal != null) {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      final bandResponse = await supabase
          .from('bands')
          .select('name')
          .eq('id', bandId)
          .single();
      final bandName = bandResponse['name'] as String;

      await _autoConflictBlockingService.autoBlockConflictingDate(
        userId: userId,
        eventBandId: bandId,
        eventDate: firstRehearsal.date,  // ⚠️ Gap: only first date
        eventStartTime: null,
        eventEndTime: null,
        eventName: 'Rehearsal',
        bandName: bandName,
      );
    }
  } catch (e) {
    debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
  }
}
```

The service is called after the loop completes, using only `firstRehearsal.date`. The `dates` list is still in scope but not passed.

### How Multi-Date Gigs Are Created

**Gig Record Creation** (`events_repository.dart` lines 569-627):

Multi-date potential gigs store the main date in the `gigs` table and additional dates in the `gig_dates` table:

```dart
// Create main gig record
final response = await supabase.from('gigs').insert(data).select().single();
final gigId = response['id'] as String;

// Create additional dates for multi-date potential gigs
if (formData.isPotentialGig && formData.additionalDates.isNotEmpty) {
  await _createGigDates(gigId, formData.additionalDates);
}
```

**Auto-Blocking Call** (`events_repository.dart` lines 633-657):

```dart
try {
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    final bandResponse = await supabase
        .from('bands')
        .select('name')
        .eq('id', bandId)
        .single();
    final bandName = bandResponse['name'] as String;

    await _autoConflictBlockingService.autoBlockConflictingDate(
      userId: userId,
      eventBandId: bandId,
      eventDate: formData.date,  // ⚠️ Gap: only main date, not additionalDates
      eventStartTime: null,
      eventEndTime: null,
      eventName: formData.name ?? formData.displayName,
      bandName: bandName,
    );
  }
} catch (e) {
  debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
}
```

Same pattern: only the main date is passed. The `formData.additionalDates` list is available but not used for auto-blocking.

### How Auto-Blocking Service Works

**Preference and Band Resolution** (`auto_conflict_blocking_service.dart` lines 49-77):

```dart
// Check if user has auto-conflict blocking enabled
final prefs = await _prefsRepository.getPreferences();

if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) {
  return;
}

// Fetch user's bands from database
final bandsResponse = await supabase
    .from('band_members')
    .select('band_id')
    .eq('user_id', userId);

final userBandIds = (bandsResponse as List)
    .map((row) => row['band_id'] as String)
    .toList();

// Get band IDs where block-out should be propagated
final bandIds = await _prefsRepository.getBandIdsToApplyBlockOut(userBandIds);

// Remove the event band (user is already busy in that band)
final otherBandIds = bandIds.where((id) => id != eventBandId).toList();
```

**Block-Out Creation Loop** (`auto_conflict_blocking_service.dart` lines 82-103):

```dart
for (final bandId in otherBandIds) {
  try {
    await _blockOutRepository.createBlockOut(
      bandId: bandId,
      userId: userId,
      startDate: blockOutDate,
      untilDate: null, // Single day
      reason: reason,
    );
    debugPrint('[AutoConflictBlockingService] Auto-blocked date for band: $bandId');
  } catch (e) {
    // Skip duplicates or errors for individual bands
    debugPrint('[AutoConflictBlockingService] Failed to auto-block for band $bandId: $e');
  }
}
```

**Error Handling:**

- Per-band try-catch ensures one band's failure doesn't prevent blocking on other bands
- Duplicate date handling: unique constraint on `block_dates (user_id, band_id, date)` causes insert error; caught and logged gracefully
- Top-level try-catch in calling code ensures event creation succeeds even if all auto-blocking fails

**N+1 Database Pattern:**
Each call to `autoBlockConflictingDate()` performs:

1. One `getPreferences()` query
2. One `band_members` SELECT query
3. N× `createBlockOut()` inserts (one per other band)

Calling this method in a loop for 52 recurring dates would perform 52 preference reads and 52 band_members queries—unnecessary duplication.

### Current Failure Mode

**User Scenario:**

1. User belongs to Band A and Band B
2. User has One Calendar enabled with auto-conflict blocking on
3. User creates a weekly recurring rehearsal in Band A (4 occurrences: June 1, 8, 15, 22)
4. Band B's calendar shows a block-out on June 1 only
5. June 8, 15, and 22 show no block-outs in Band B

**What Happens in Code:**

1. `_generateRecurringDates()` returns `[June 1, June 8, June 15, June 22]`
2. Loop creates 4 rehearsal records in Band A
3. `autoBlockConflictingDate(eventDate: June 1)` called once
4. Service creates block-out in Band B for June 1 only
5. No iteration over remaining dates—loop never executes for dates[1], dates[2], dates[3]

---

## Proposed Solution

### Overview

Add `autoBlockConflictingDates(List<DateTime> eventDates)` method to the auto-blocking service that reads preferences and band memberships once, then iterates all dates to create block-outs. Update both `createRehearsal()` and `createGig()` to call the new multi-date method with the full list of occurrence dates.

This avoids N+1 database queries while maintaining the existing error-handling pattern (per-band-per-date isolation).

### Multi-Date Auto-Blocking Method

**New Method Signature:**

```dart
Future<void> autoBlockConflictingDates({
  required String userId,
  required String eventBandId,
  required List<DateTime> eventDates,
  DateTime? eventStartTime,
  DateTime? eventEndTime,
  required String eventName,
  required String bandName,
}) async
```

**Implementation Pattern:**

1. Read preferences once (early return if disabled)
2. Query `band_members` once to get user's bands
3. Resolve target bands via `getBandIdsToApplyBlockOut()` once
4. Nested loop: for each date, for each band, create block-out
5. Maintain per-band-per-date try-catch for error isolation

**Pseudo-code:**

```dart
// Read preferences and bands once
final prefs = await _prefsRepository.getPreferences();
if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) return;

final userBandIds = await _fetchUserBands(userId);
final bandIds = await _prefsRepository.getBandIdsToApplyBlockOut(userBandIds);
final otherBandIds = bandIds.where((id) => id != eventBandId).toList();

if (otherBandIds.isEmpty) return;

final reason = 'Unavailable (scheduled with $bandName)';

// Loop through all dates
for (final eventDate in eventDates) {
  final blockOutDate = DateTime(eventDate.year, eventDate.month, eventDate.day);

  // Loop through all other bands
  for (final bandId in otherBandIds) {
    try {
      await _blockOutRepository.createBlockOut(
        bandId: bandId,
        userId: userId,
        startDate: blockOutDate,
        untilDate: null,
        reason: reason,
      );
    } catch (e) {
      // Log and continue (duplicate date or other error)
      debugPrint('[AutoConflictBlockingService] Failed for band $bandId date $blockOutDate: $e');
    }
  }
}
```

**Why Not Modify Existing Method:**

The existing `autoBlockConflictingDate()` (singular) may be called from other locations (manual block-out propagation, one-off events). Adding the new method preserves backward compatibility and avoids refactoring unrelated code paths.

### Integration Points

**1. Rehearsal Creation** (`events_repository.dart` line 164):

**Before:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDate(
  userId: userId,
  eventBandId: bandId,
  eventDate: firstRehearsal.date,
  eventStartTime: null,
  eventEndTime: null,
  eventName: 'Rehearsal',
  bandName: bandName,
);
```

**After:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDates(
  userId: userId,
  eventBandId: bandId,
  eventDates: dates,  // Use the full dates list from line 91
  eventStartTime: null,
  eventEndTime: null,
  eventName: 'Rehearsal',
  bandName: bandName,
);
```

**2. Gig Creation** (`events_repository.dart` line 647):

**Before:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDate(
  userId: userId,
  eventBandId: bandId,
  eventDate: formData.date,
  eventStartTime: null,
  eventEndTime: null,
  eventName: formData.name ?? formData.displayName,
  bandName: bandName,
);
```

**After:**

```dart
// Build date list: main date + additional dates
final allDates = [
  formData.date,
  ...formData.additionalDates.map((e) => e.date),
];

await _autoConflictBlockingService.autoBlockConflictingDates(
  userId: userId,
  eventBandId: bandId,
  eventDates: allDates,
  eventStartTime: null,
  eventEndTime: null,
  eventName: formData.name ?? formData.displayName,
  bandName: bandName,
);
```

### Database Interaction Pattern

**Query Complexity (Example: 4-week recurring rehearsal, user in 3 bands):**

**Current (Broken) Behavior:**

- 1 preference read
- 1 `band_members` query
- 3 block-out inserts (one per other band, for first date only)
- **Result:** Only 1 occurrence blocked

**Naive Loop Fix (N+1 Problem):**

- 4 preference reads (one per date)
- 4 `band_members` queries
- 12 block-out inserts (4 dates × 3 bands)
- **Result:** All 4 occurrences blocked, but with redundant DB reads

**Proposed Solution (Optimal):**

- 1 preference read
- 1 `band_members` query
- 12 block-out inserts (4 dates × 3 bands)
- **Result:** All 4 occurrences blocked with minimal queries

**Worst-Case Scenario (52-week recurring rehearsal, user in 5 bands):**

- 1 preference read
- 1 `band_members` query
- 260 block-out inserts (52 dates × 5 other bands)
- Still acceptable: 2 reads + 260 writes vs. 104 reads + 260 writes

### Unique Constraint Handling

**Constraint:** `block_dates (user_id, band_id, date)` is unique

**Scenario:** User manually blocked June 8 in Band B, then creates weekly recurring rehearsal in Band A (June 1, 8, 15, 22)

**Behavior:**

1. June 1: insert succeeds (new block-out created)
2. June 8: insert fails (unique constraint violation), caught by try-catch, logged
3. June 15: insert succeeds (try-catch isolated failure for June 8)
4. June 22: insert succeeds

**Result:** 3 of 4 dates blocked automatically. June 8 already manually blocked. No failures propagate to calling code.

**Evidence:** Existing error handling at `auto_conflict_blocking_service.dart` lines 94-101 already implements this pattern.

---

## Database Impact

**Database: Not Applicable**

No schema changes, migrations, RLS policies, RPC functions, or triggers are modified by this fix.

**Affected Areas:**

| Component          | Impact                                          |
| ------------------ | ----------------------------------------------- |
| Table schema       | Unaffected                                      |
| RLS policies       | Unaffected                                      |
| RPC functions      | Unaffected                                      |
| Triggers           | Unaffected                                      |
| Indexes            | Unaffected                                      |
| Unique constraints | Utilized by existing error handling (no change) |

**Constraint Verification:**

The unique constraint on `block_dates (user_id, band_id, date)` is already handled gracefully by the existing per-band try-catch pattern in `auto_conflict_blocking_service.dart`. No changes to constraint handling are required.

**Database Trigger Alternative Considered:**

The original One Calendar design (`docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md`) considered database triggers that fire after INSERT on `rehearsals` or `gigs` and call an RPC to propagate block-outs. The client-side approach was chosen for flexibility (user preferences accessed via RLS, no service-role elevation needed). This fix maintains that architectural decision.

---

## Flutter Architecture Changes

**Affected Repositories:**

- `AutoConflictBlockingService` — Add new method accepting `List<DateTime>`
- `EventsRepository` — Update two call sites to use new method with full date lists

**State Management:**

- No Riverpod provider changes required
- No widget rebuilds triggered
- No controller state modified

**Data Flow:**

- Block-out creation is fire-and-forget (non-blocking)
- No return values consumed by calling code
- Cache invalidation unchanged (`invalidateCache(bandId)` already called after event creation)

---

## Files to Create

**None**

---

## Files to Modify

| File                                                        | What Changes                                                                                                                                                                                                                                                                     |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/calendar/auto_conflict_blocking_service.dart` | **Add** `autoBlockConflictingDates()` method accepting `List<DateTime> eventDates` parameter. Reads preferences/bands once, nested loop through dates and bands. Maintain per-band-per-date try-catch error isolation.                                                           |
| `lib/features/events/events_repository.dart`                | **Update** `createRehearsal()` (line ~164): Call `autoBlockConflictingDates()` passing `dates` list from line 91.<br>**Update** `createGig()` (line ~647): Build date list from `formData.date` + `formData.additionalDates`, call `autoBlockConflictingDates()` with full list. |

---

## Files Off-Limits

| File                                                             | Reason                                                 |
| ---------------------------------------------------------------- | ------------------------------------------------------ |
| `lib/main.dart`                                                  | Init order must not change (guardrail)                 |
| `lib/features/setlists/**`                                       | Not relevant to calendar blocking                      |
| `lib/features/calendar/one_calendar_preferences_repository.dart` | Preference logic is correct; no changes needed         |
| `lib/features/calendar/block_out_repository.dart`                | Block-out creation logic is correct; no changes needed |
| `supabase/migrations/**`                                         | No schema changes required                             |

---

## System Impact Map

| System                                 | Impact                                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Gigs                                   | **Affected** — Multi-date potential gigs will now auto-block all dates (main date + additional dates) |
| Rehearsals                             | **Affected** — Recurring rehearsals will now auto-block all occurrences (all dates in series)         |
| Setlists / Catalog                     | **Unaffected**                                                                                        |
| Members / RBAC                         | **Unaffected**                                                                                        |
| Auth / Session                         | **Unaffected**                                                                                        |
| Routing                                | **Unaffected**                                                                                        |
| Notifications                          | **Unaffected**                                                                                        |
| Platform (iOS / Android / Web / macOS) | **Unaffected** — Behavior change is data-layer only; no platform-specific code touched                |

---

## Regression Risk

**Overall Risk:** `MEDIUM`

**Rationale:**

**Risk Factors:**

1. **Data Volume Increase:** Recurring rehearsals will create N× more block_dates rows (52× for weekly recurring through 1 year)
2. **Multi-System Touch:** Both gigs and rehearsals affected
3. **No Rollback Mechanism:** Block-outs created by this fix cannot be auto-deleted if series is later edited/deleted (documented out of scope)
4. **Unique Constraint Edge Cases:** User manually blocking a date before creating recurring event (already handled gracefully but increases likelihood of constraint violations)

**Mitigating Factors:**

1. **No Schema Changes:** Database structure unchanged
2. **Existing Error Handling:** Per-band-per-date try-catch prevents cascading failures
3. **Non-Blocking Design:** Event creation succeeds even if all auto-blocking fails
4. **Opt-In Feature:** Users can disable One Calendar or auto-conflict blocking via settings
5. **No Auth/Session Changes:** Core app stability unaffected
6. **Feature Was Broken:** Any working behavior is an improvement over current state (only first occurrence blocks)

**Specific Regression Scenarios:**

| Scenario                                                            | Risk Level | Mitigation                                                             |
| ------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------- |
| 52-week recurring creates 260 block_dates rows (5 bands)            | LOW        | Database handles this volume; inserts are already per-band isolated    |
| User creates recurring, then manually deletes one future occurrence | LOW        | Block-out remains (manual cleanup required); documented out of scope   |
| User manually blocked June 8, then creates recurring June 1-22      | LOW        | June 8 insert fails gracefully (logged); other dates succeed           |
| Auto-blocking fails mid-loop (network error)                        | LOW        | Per-date try-catch isolates failure; partial block-outs created        |
| User disables One Calendar after recurring created                  | LOW        | Existing block-outs remain (no retroactive cleanup); expected behavior |

---

## Engineer Task Breakdown

### Task 1: Add Multi-Date Auto-Blocking Method

**File:** `lib/features/calendar/auto_conflict_blocking_service.dart`

**Action:** Add new method `autoBlockConflictingDates()` accepting `List<DateTime> eventDates`

**Implementation Steps:**

1. Copy existing `autoBlockConflictingDate()` method signature
2. Change `eventDate` parameter to `eventDates` (List)
3. Extract preference/band resolution logic (lines 49-77) outside the date loop
4. Add outer loop: `for (final eventDate in eventDates)`
5. Keep inner loop: `for (final bandId in otherBandIds)`
6. Maintain per-band try-catch pattern (lines 94-101)
7. Add debug print showing date count: `'[AutoConflictBlockingService] Auto-blocking ${eventDates.length} date(s)...'`

**Validation:**

- Method signature matches existing method except `List<DateTime>` parameter
- Early returns for disabled features unchanged
- Per-band-per-date error isolation preserved
- No duplicate preference reads

---

### Task 2: Update Rehearsal Creation to Use Multi-Date Method

**File:** `lib/features/events/events_repository.dart`

**Action:** Replace single-date auto-blocking call with multi-date call (line ~164)

**Before:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDate(
  userId: userId,
  eventBandId: bandId,
  eventDate: firstRehearsal.date,
  eventStartTime: null,
  eventEndTime: null,
  eventName: 'Rehearsal',
  bandName: bandName,
);
```

**After:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDates(
  userId: userId,
  eventBandId: bandId,
  eventDates: dates,  // Use full dates list from line 91
  eventStartTime: null,
  eventEndTime: null,
  eventName: 'Rehearsal',
  bandName: bandName,
);
```

**Validation:**

- `dates` list is in scope (generated at line 91)
- For one-off rehearsals: `dates` contains 1 element (no behavior change)
- For recurring: `dates` contains N elements (all occurrences blocked)
- Error handling unchanged (try-catch already wraps call)

---

### Task 3: Update Gig Creation to Use Multi-Date Method

**File:** `lib/features/events/events_repository.dart`

**Action:** Replace single-date auto-blocking call with multi-date call (line ~647)

**Before:**

```dart
await _autoConflictBlockingService.autoBlockConflictingDate(
  userId: userId,
  eventBandId: bandId,
  eventDate: formData.date,
  eventStartTime: null,
  eventEndTime: null,
  eventName: formData.name ?? formData.displayName,
  bandName: bandName,
);
```

**After:**

```dart
// Build date list: main date + additional dates
final allDates = [
  formData.date,
  ...formData.additionalDates.map((e) => e.date),
];

await _autoConflictBlockingService.autoBlockConflictingDates(
  userId: userId,
  eventBandId: bandId,
  eventDates: allDates,
  eventStartTime: null,
  eventEndTime: null,
  eventName: formData.name ?? formData.displayName,
  bandName: bandName,
);
```

**Validation:**

- For one-date gigs: `allDates` contains 1 element (no behavior change)
- For multi-date potential gigs: `allDates` contains main date + additional dates
- `additionalDates` may be empty (safe: spread operator on empty list is no-op)
- Error handling unchanged (try-catch already wraps call)

---

### Task 4: Manual Testing — Recurring Rehearsal Full Coverage

**Prerequisites:**

- Test user belongs to at least 2 bands (Band A, Band B)
- One Calendar enabled with auto-conflict blocking on

**Steps:**

1. In Band A, create a weekly recurring rehearsal starting next Monday (4 occurrences: June 1, 8, 15, 22)
2. Switch to Band B's calendar
3. Verify block-out dates appear on ALL 4 Mondays with reason "Unavailable (scheduled with Band A)"
4. Tap one block-out to view details: confirm reason and date match

**Expected:** ✅ All 4 occurrences blocked in Band B

---

### Task 5: Manual Testing — Multi-Date Potential Gig

**Prerequisites:**

- Test user belongs to at least 2 bands (Band A, Band B)
- One Calendar enabled with auto-conflict blocking on

**Steps:**

1. In Band A, create a potential gig with main date June 10 and additional dates June 11, June 12
2. Switch to Band B's calendar
3. Verify block-out dates appear on ALL 3 dates (June 10, 11, 12) with reason "Unavailable (scheduled with Band A)"

**Expected:** ✅ All 3 dates blocked in Band B

---

### Task 6: Manual Testing — Unique Constraint (Manual Block + Recurring)

**Prerequisites:**

- Test user belongs to at least 2 bands (Band A, Band B)
- One Calendar enabled

**Steps:**

1. In Band B, manually create a block-out date for June 15 with reason "Vacation"
2. In Band A, create a weekly recurring rehearsal (June 8, 15, 22, 29)
3. Switch to Band B's calendar
4. Verify block-out dates appear on June 8, 22, and 29 with reason "Unavailable (scheduled with Band A)"
5. Verify June 15 shows "Vacation" (original manual block-out, not overwritten)
6. Check debug logs: confirm "Failed to auto-block for band ... date 2026-06-15" logged (duplicate insert caught)

**Expected:** ✅ Manual block-out preserved; other dates auto-blocked; no error surfaced to user

---

## Verification Plan

### Tier 1 — Pre-Deployment

**Not applicable** — This is a client-side Dart code change with no database migrations or edge functions.

---

### Tier 2 — Post-Deployment

**POST-DEPLOY TEST 1: Verify Multi-Date Method Added**

**Action:** Code review

**Check:**

1. `auto_conflict_blocking_service.dart` contains `autoBlockConflictingDates()` method accepting `List<DateTime> eventDates`
2. Method reads preferences once (early in method)
3. Method reads user bands once
4. Nested loops: outer loop through `eventDates`, inner loop through `otherBandIds`
5. Per-band-per-date try-catch preserved

**Expected:** ✅ Method signature and structure match design

---

**POST-DEPLOY TEST 2: Verify Rehearsal Integration**

**Action:** Code review

**Check:**

1. `events_repository.dart` line ~164 calls `autoBlockConflictingDates()` (plural)
2. Parameter passed is `eventDates: dates` (from line 91)
3. One-off rehearsals: `dates` contains 1 element
4. Recurring rehearsals: `dates` contains N elements

**Expected:** ✅ Integration uses multi-date method with full dates list

---

**POST-DEPLOY TEST 3: Verify Gig Integration**

**Action:** Code review

**Check:**

1. `events_repository.dart` line ~647 calls `autoBlockConflictingDates()` (plural)
2. Date list built from `formData.date` + `formData.additionalDates`
3. One-date gigs: list contains 1 element
4. Multi-date gigs: list contains main date + additional dates

**Expected:** ✅ Integration uses multi-date method with full dates list

---

**POST-DEPLOY TEST 4: End-to-End Recurring Rehearsal**

**Prerequisites:**

- Test user in Band A and Band B
- One Calendar + auto-conflict blocking enabled

**Steps:**

1. Create weekly recurring rehearsal in Band A (4 occurrences)
2. Query Band B's `block_dates` table for test user

**SQL:**

```sql
SELECT
  bd.date,
  bd.reason,
  b.name as band_name
FROM block_dates bd
JOIN bands b ON bd.band_id = b.id
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.date >= 'FIRST_OCCURRENCE_DATE'
  AND bd.date <= 'LAST_OCCURRENCE_DATE'
ORDER BY bd.date;
```

**Expected:**

```json
[
  {
    "date": "2026-06-01",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  },
  {
    "date": "2026-06-08",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  },
  {
    "date": "2026-06-15",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  },
  {
    "date": "2026-06-22",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  }
]
```

4 rows, one per occurrence. All have the auto-generated reason.

---

**POST-DEPLOY TEST 5: End-to-End Multi-Date Gig**

**Prerequisites:**

- Test user in Band A and Band B
- One Calendar + auto-conflict blocking enabled

**Steps:**

1. Create potential gig in Band A with main date June 10 and additional dates June 11, June 12
2. Query Band B's `block_dates` table for test user

**SQL:**

```sql
SELECT
  bd.date,
  bd.reason,
  b.name as band_name
FROM block_dates bd
JOIN bands b ON bd.band_id = b.id
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.date IN ('2026-06-10', '2026-06-11', '2026-06-12')
ORDER BY bd.date;
```

**Expected:**

```json
[
  {
    "date": "2026-06-10",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  },
  {
    "date": "2026-06-11",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  },
  {
    "date": "2026-06-12",
    "reason": "Unavailable (scheduled with Band A)",
    "band_name": "Band B"
  }
]
```

3 rows, one per date.

---

**POST-DEPLOY TEST 6: Unique Constraint Handling**

**Prerequisites:**

- Test user in Band A and Band B
- One Calendar + auto-conflict blocking enabled

**Steps:**

1. Manually create block-out in Band B for June 15 with reason "Vacation"
2. Create weekly recurring rehearsal in Band A (June 8, 15, 22, 29)
3. Query Band B's `block_dates` table

**SQL:**

```sql
SELECT
  bd.date,
  bd.reason
FROM block_dates bd
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.band_id = 'BAND_B_UUID'
  AND bd.date IN ('2026-06-08', '2026-06-15', '2026-06-22', '2026-06-29')
ORDER BY bd.date;
```

**Expected:**

```json
[
  { "date": "2026-06-08", "reason": "Unavailable (scheduled with Band A)" },
  { "date": "2026-06-15", "reason": "Vacation" }, // Original manual block-out preserved
  { "date": "2026-06-22", "reason": "Unavailable (scheduled with Band A)" },
  { "date": "2026-06-29", "reason": "Unavailable (scheduled with Band A)" }
]
```

June 15 retains "Vacation" reason (manual block-out not overwritten). Other dates auto-blocked.

4. Check debug logs for error message:

```
[AutoConflictBlockingService] Failed to auto-block for band <BAND_B_UUID> date 2026-06-15: <duplicate key error>
```

---

**POST-DEPLOY TEST 7: No Regression on One-Off Events**

**Prerequisites:**

- Test user in Band A and Band B
- One Calendar + auto-conflict blocking enabled

**Steps:**

1. Create one-off rehearsal in Band A (single date, not recurring)
2. Query Band B's `block_dates` table

**SQL:**

```sql
SELECT
  bd.date,
  bd.reason
FROM block_dates bd
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.band_id = 'BAND_B_UUID'
  AND bd.date = 'REHEARSAL_DATE'
ORDER BY bd.date;
```

**Expected:**

```json
[{ "date": "2026-06-10", "reason": "Unavailable (scheduled with Band A)" }]
```

One row. Same behavior as before (no regression).

---

## QA Regression Areas

**Primary:**

1. **Recurring Rehearsal Auto-Blocking** — All occurrences create block-outs in other bands
2. **Multi-Date Gig Auto-Blocking** — All dates (main + additional) create block-outs in other bands
3. **Unique Constraint Handling** — Manual block-out on same date preserves original reason; auto-block for that date fails gracefully
4. **One-Off Events** — No regression (single date still blocks correctly)

**Regression:**

1. **Manual Block-Out Propagation** — Verify manual block-out creation still propagates to all applicable bands (unchanged code path)
2. **One Calendar Settings Toggle** — Verify disabling One Calendar prevents auto-blocking on new events
3. **Selected Bands Mode** — Verify "Selected bands only" setting still propagates to correct bands only
4. **Gig Creation (One-Date)** — Verify single-date gigs still auto-block correctly
5. **Rehearsal Creation (One-Off)** — Verify one-off rehearsals still auto-block correctly
6. **Event Delete** — Verify deleting recurring series works (note: block-outs NOT cleaned up, documented out of scope)
7. **Calendar Display** — Verify all events and block-out dates display correctly
8. **Block-Out Deletion** — Verify delete choice dialog works ("This band only" vs "All bands")

**Known Limitations (Not Tested):**

1. **Recurring Series Edit** — Editing a recurring series does not update previously auto-created block-outs (out of scope)
2. **Recurring Series Delete** — Deleting a recurring series does not clean up auto-created block-outs (out of scope)
3. **Stale Block-Outs** — If user creates recurring, then disables One Calendar, old block-outs remain (expected behavior)

---

## Rollout / Migration Strategy

**Deployment Steps:**

1. **Build and deploy web** (if using web platform for testing):

   ```bash
   flutter build web --release
   cd build/web && vercel --prod
   ```

2. **Deploy to app stores** (if using native platforms):
   - iOS: `flutter build ios --release` → TestFlight
   - Android: `flutter build appbundle --release` → Google Play Console

3. **Monitor debug logs** for 24-48 hours:
   - Check for unexpected errors in `autoBlockConflictingDates()`
   - Monitor unique constraint violations (should be caught gracefully)
   - Look for patterns in failed block-out creation

4. **Database Monitoring:**
   - Track `block_dates` table growth: expect N× increase for recurring rehearsals (acceptable)
   - Query for orphaned block-outs if users report unexpected dates

**Rollback Plan:**

If critical issues arise:

1. **Emergency rollback** (revert code changes):

   ```bash
   git revert <commit-hash>
   git push
   flutter build web --release
   cd build/web && vercel --prod
   ```

2. **Manual block-out cleanup** (if needed):

   ```sql
   -- Find auto-created block-outs for a specific series
   SELECT *
   FROM block_dates
   WHERE reason LIKE 'Unavailable (scheduled with%)'
     AND date BETWEEN 'START_DATE' AND 'END_DATE'
     AND band_id = 'BAND_B_UUID';

   -- Delete if confirmed orphaned
   DELETE FROM block_dates
   WHERE id IN (...);
   ```

**User Communication:**

No announcement required. Feature improvement is transparent: users who create recurring rehearsals or multi-date gigs will see block-outs appear on all dates automatically. Users who already created recurring events before this fix can manually delete old single-occurrence block-outs if desired.

---

## Out of Scope

**Explicitly not included in this fix:**

1. **Stale Block-Out Cleanup on Series Edit/Delete**

   **Why Out of Scope:** Tracking which block-outs were auto-created by a specific recurring series requires either:
   - A `source_event_id` column on `block_dates` table (schema change)
   - A separate junction table linking block-outs to events (new table)
   - Heuristic matching (reason text + date range matching), which is fragile

   **User-Visible Consequence:** If a user creates a 52-week recurring rehearsal in Band A (auto-blocks 52 dates in Band B), then deletes the series, all 52 block-outs remain in Band B. User must manually delete them via "All bands" choice or individually.

   **Recommendation:** Document as known limitation. Consider future enhancement: add `source_event_type` and `source_event_id` columns to `block_dates` for cascade cleanup.

2. **Retroactive Block-Out Creation for Existing Recurring Series**

   **Why Out of Scope:** Existing recurring rehearsals created before this fix have only the first occurrence blocked. Retroactively creating block-outs for past dates would be confusing (historical dates already passed). Retroactively creating for future dates only requires:
   - One-time migration script to query all recurring series
   - Compute future occurrences per series
   - Call auto-blocking logic per series
   - Risk of duplicate inserts, partial failures

   **User-Visible Consequence:** Users with existing recurring rehearsals will continue to have incomplete block-out coverage until they create new recurring events.

   **Recommendation:** Acceptable trade-off. Feature was broken before; new events will work correctly.

3. **Historical Backfill of Block-Out Dates**

   Same as #2 above. Out of scope.

4. **Gig Recurrence Support**

   **Why Out of Scope:** Gigs do not support recurrence (see `events_repository.dart` line 579: `throw Exception('Recurring events are not yet supported.')`). This fix addresses multi-date potential gigs (explicit additional dates), not recurring gigs.

   **User-Visible Consequence:** None. Gig recurrence is not a released feature.

5. **Performance Optimization for Large Series (100+ Occurrences)**

   **Why Out of Scope:** The max iterations limit in `_generateRecurringDates()` is 52 (1 year of weekly events). Monthly recurrence is capped at 24 months. Edge case: user could theoretically create a biweekly series for 2 years (52 occurrences) in a user with 10 bands = 520 block-out inserts. This is acceptable for current user base size.

   **User-Visible Consequence:** Slight delay in event creation for large recurring series with many bands (still completes; non-blocking).

   **Recommendation:** Monitor performance. If issues arise, consider batch insert optimization (`block_out_repository.dart` currently inserts one row at a time).

6. **Notification on Auto-Block Creation**

   **Why Out of Scope:** The feature silently creates block-outs in other bands. Users only see them when viewing the calendar. Adding notifications would require:
   - Notification trigger logic after block-out creation
   - Notification preferences (user may not want notifications for auto-blocks)
   - Bundling notifications (52 occurrences = 52 notifications?)

   **User-Visible Consequence:** User may not realize block-outs were created in other bands until viewing calendar.

   **Recommendation:** Acceptable. One Calendar feature is opt-in; users who enable it expect this behavior.

---

**END OF ARCHITECT_PLAN.md**
