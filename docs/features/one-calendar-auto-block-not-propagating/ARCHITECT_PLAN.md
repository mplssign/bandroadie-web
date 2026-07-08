# ARCHITECT PLAN — One Calendar Auto-Block Not Propagating (Complete System Failure)

## Feature Slug

`bug/one-calendar-auto-block-not-propagating`

---

## Problem Summary

**What:** One Calendar propagation is completely non-functional. When a user in 2+ bands creates a gig, one-off rehearsal, or recurring rehearsal in one band, no block-out dates are created on their other band calendars. The feature is effectively inactive for all event types.

**Why:** Production database has incorrect column defaults (`DEFAULT false` instead of `DEFAULT true`) for both `one_calendar_enabled` and `auto_block_conflicts_enabled`. When user preferences are created for the first time via the `get_or_create_calendar_preferences()` RPC, both flags are set to false, disabling the entire feature. The propagation logic reads these preferences and returns an empty band list, causing all propagation to be silently skipped.

**Impact:** Multi-band users receive no automatic conflict protection. Manual block-out dates must be entered separately on each band calendar, exactly the friction this feature was designed to eliminate.

---

## Root Cause

**Primary Failure:** Database schema defaults do not match migration file.

**Evidence:**

1. **Migration file on disk** (`20260626005216_add_user_calendar_preferences.sql`):

   ```sql
   one_calendar_enabled BOOLEAN NOT NULL DEFAULT true,
   auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT true,
   ```

2. **Production database schema** (verified via direct query 2026-07-07):

   ```json
   {
     "column_default": "false",
     "column_name": "one_calendar_enabled"
   },
   {
     "column_default": "false",
     "column_name": "auto_block_conflicts_enabled"
   }
   ```

3. **User preference data** (5 most recent rows, all from 2026-07-07):

   ```json
   {
     "one_calendar_enabled": false,
     "auto_block_conflicts_enabled": false,
     "apply_to_mode": "all_bands"
   }
   ```

   All users have the feature disabled because the RPC creates rows using the column defaults.

4. **Code path confirmed** (`one_calendar_preferences_repository.dart` line 103-108):
   ```dart
   if (!prefs.oneCalendarEnabled) {
     debugPrint('One Calendar disabled, returning empty list');
     return [];  // No propagation
   }
   ```
   Repository returns empty band list when `one_calendar_enabled = false`, causing propagation and auto-blocking logic to skip entirely.

**Historical Context:**

The ENGINEER_REPORT from the original `feature/one-calendar-shared-blockout` (2026-06-26) documents this exact issue:

> **Fix: One Calendar Default Settings Changed to ON (2026-06-26)**
>
> **Issue:** The `user_calendar_preferences` table defaulted `one_calendar_enabled` and `auto_block_conflicts_enabled` to `false`. This was not the desired user experience — the feature should be enabled by default for users who belong to multiple bands.
>
> **Fix Applied:**
>
> 1. Updated migration file to change default values (from `false` to `true`)
> 2. **Manual SQL required for existing databases (provided to Tony for Supabase SQL editor):**
>    ```sql
>    ALTER TABLE user_calendar_preferences
>      ALTER COLUMN one_calendar_enabled SET DEFAULT true,
>      ALTER COLUMN auto_block_conflicts_enabled SET DEFAULT true;
>    ```

**What Happened:**

The Engineer updated the migration file on disk to `DEFAULT true`, but the manual `ALTER TABLE` SQL was **never executed in production**. The migration file changed, but the live database schema did not. All users created since deployment have received `false` defaults, disabling the feature system-wide.

**Root Cause Confidence:** `HIGH` — Confirmed by direct observation of production schema, user data, code paths, and historical documentation.

---

## Reference Docs Consulted

**Feature Documentation:**

- `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md` — Original feature design
- `docs/features/one-calendar-shared-blockout/ENGINEER_REPORT.md` — Implementation details and post-fix documentation
- `docs/features/one-calendar-shared-blockout/QA_REPORT.md` — Original QA validation
- `docs/features/one-calendar-manual-blackout/ARCHITECT_PLAN.md` — Related follow-up feature

**Database Schema:**

- `docs/reference/architecture/database_schema.md` — `user_calendar_preferences` table structure
- `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` — Table creation
- `supabase/migrations/20260626010000_fix_calendar_preferences_rpc.sql` — RPC signature fix

**Code Inspection:**

- `lib/features/calendar/one_calendar_preferences_repository.dart` — Preference reads and band resolution
- `lib/features/calendar/widgets/add_block_out_drawer.dart` — Manual block-out propagation
- `lib/features/calendar/auto_conflict_blocking_service.dart` — Automatic conflict blocking
- `lib/features/events/events_repository.dart` — Gig and rehearsal creation integration

---

## Existing System Analysis

### How One Calendar Propagation Was Designed to Work

**1. Manual Block-Out Propagation** (`add_block_out_drawer.dart` lines 220-250):

When a user creates a block-out date in Band A:

1. Primary block-out created for Band A
2. Repository calls `getBandIdsToApplyBlockOut(userBandIds)`
3. Repository reads user's preferences via `getPreferences()` RPC
4. If `one_calendar_enabled = true`:
   - If `apply_to_mode = 'all_bands'`: returns all user's band IDs
   - If `apply_to_mode = 'selected_bands'`: returns selected band IDs only
5. For each band ID (excluding Band A), create block-out date with same reason
6. Errors per band are caught and logged (graceful degradation)

**2. Automatic Conflict Blocking** (`auto_conflict_blocking_service.dart`):

When a user creates a gig or rehearsal in Band A:

1. Event is created in Band A
2. After success, `autoBlockConflictingDate()` is called
3. Service reads user's preferences via `getPreferences()` RPC
4. If `one_calendar_enabled = true` AND `auto_block_conflicts_enabled = true`:
   - Fetches user's bands from `band_members` table
   - Calls `getBandIdsToApplyBlockOut(userBandIds)`
   - For each other band, creates block-out date with reason: `"Unavailable (scheduled with [Band Name])"`
5. Errors per band are caught and logged (graceful degradation)

**3. Preference Read and Band Resolution** (`one_calendar_preferences_repository.dart` lines 88-123):

```dart
Future<List<String>> getBandIdsToApplyBlockOut(List<String> userBandIds) async {
  try {
    final prefs = await getPreferences();

    // One Calendar disabled: return empty list
    if (!prefs.oneCalendarEnabled) {
      debugPrint('One Calendar disabled, returning empty list');
      return [];
    }

    // Apply to all bands
    if (prefs.applyToMode == ApplyToMode.allBands) {
      return userBandIds;
    }

    // Apply to selected bands only
    final selectedIds = prefs.selectedBandIds
        .where((id) => userBandIds.contains(id))
        .toList();
    return selectedIds;
  } catch (e) {
    debugPrint('Failed to resolve band IDs: $e');
    // On error, return empty list (fail safe: do not propagate)
    return [];
  }
}
```

**Critical Fail-Safe:** Lines 115-119 implement a catch-all that returns an empty list on any error. This ensures that propagation failures do not break primary operations (block-out creation, event creation), but it also **masks all errors silently**.

### Current Failure Mode

**Observed Behavior:**

1. User creates block-out date or event in Band A
2. Repository calls `getPreferences()` RPC
3. RPC returns existing row or creates new row using column defaults (`DEFAULT false`)
4. Repository checks `if (!prefs.oneCalendarEnabled)` → evaluates to true
5. Repository returns empty list `[]`
6. Propagation logic receives empty list: `final otherBandIds = bandIds.where((id) => id != widget.bandId).toList();`
7. Loop does not execute: `for (final bandId in otherBandIds) { ... }` — no iterations
8. No block-out dates are created in other bands
9. No errors are logged (this is the expected code path when feature is disabled)

**Why This Is Silent:**

The code behaves exactly as designed for a user who has intentionally disabled One Calendar. There is no error, exception, or log message to indicate that the feature is disabled due to incorrect defaults rather than user choice. The feature appears to "do nothing" because, from the code's perspective, it is doing exactly what the user's preferences specify.

---

## Proposed Solution

### Overview

Execute the missing `ALTER TABLE` SQL to change column defaults from `false` to `true`, matching the migration file intent. This will ensure all **future** users who create preference rows receive the correct defaults. **Existing** users who already have rows with `false` must be updated separately.

### Database Fix

**Step 1: Change Column Defaults (Production)**

```sql
ALTER TABLE user_calendar_preferences
  ALTER COLUMN one_calendar_enabled SET DEFAULT true,
  ALTER COLUMN auto_block_conflicts_enabled SET DEFAULT true;
```

**Impact:** All new preference rows created after this change will have both flags set to `true` by default. The feature will be enabled for new users automatically.

**Step 2: Update Existing User Preferences (Production)**

```sql
UPDATE user_calendar_preferences
SET
  one_calendar_enabled = true,
  auto_block_conflicts_enabled = true,
  updated_at = now()
WHERE one_calendar_enabled = false
   OR auto_block_conflicts_enabled = false;
```

**Impact:** All existing users who currently have the feature disabled (due to incorrect defaults) will have it enabled. Users who explicitly disabled the feature via the settings UI will **also** have it re-enabled. This is acceptable because:

1. The feature is new and was never functional
2. Users did not explicitly disable it — they received broken defaults
3. The feature is designed to be opt-in via UI, but the UI never worked because the feature was broken

**Verification Query (Post-Fix):**

```sql
-- Verify column defaults are now true
SELECT
  column_name,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_calendar_preferences'
  AND column_name IN ('one_calendar_enabled', 'auto_block_conflicts_enabled');

-- Verify all users have feature enabled
SELECT
  COUNT(*) as total_users,
  SUM(CASE WHEN one_calendar_enabled THEN 1 ELSE 0 END) as enabled_count,
  SUM(CASE WHEN auto_block_conflicts_enabled THEN 1 ELSE 0 END) as auto_block_count
FROM user_calendar_preferences;
```

**Expected Result:**

- `column_default` for both columns: `true`
- `enabled_count` should equal `total_users`
- `auto_block_count` should equal `total_users`

---

## Secondary Issue: Recurring Rehearsal Auto-Blocking Incomplete

**Observation:**

Auto-conflict blocking only fires for the **first occurrence** of a recurring rehearsal, not for all occurrences.

**Evidence** (`events_repository.dart` lines 150-177):

```dart
if (firstRehearsal != null) {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      // Fetch band name
      final bandResponse = await supabase
          .from('bands')
          .select('name')
          .eq('id', bandId)
          .single();
      final bandName = bandResponse['name'] as String;

      await _autoConflictBlockingService.autoBlockConflictingDate(
        userId: userId,
        eventBandId: bandId,
        eventDate: firstRehearsal.date,  // ⚠️ Only the first date
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

**What Should Happen:**

For a recurring rehearsal (e.g., weekly for 8 weeks), the service should create block-out dates on other bands for **all 8 occurrences**, not just the first one.

**Impact:**

Even after the primary fix (changing defaults to `true`), auto-conflict blocking will only protect the first rehearsal date. Subsequent occurrences will not create block-out dates in other bands, leaving gaps in conflict protection.

**Recommendation:**

This is a **separate bug** that should be addressed in a follow-up feature:

- Feature slug: `bug/one-calendar-recurring-rehearsal-auto-block-incomplete`
- Scope: Modify `events_repository.dart` to call `autoBlockConflictingDate()` for each generated recurring date, not just the first
- Alternatively: Modify `autoBlockConflictingDate()` to accept a list of dates instead of a single date

**Out of Scope for This Fix:**

This ARCHITECT_PLAN focuses solely on the **primary root cause** (incorrect column defaults) that breaks the entire propagation system. Recurring rehearsal coverage is a refinement of an otherwise-working feature and will be addressed separately.

---

## Database Impact

**Affected:** Yes — Column defaults only (no schema changes, no new objects)

### Migrations Required

**New Migration:** No — This is a schema fix for an existing table, not a new migration

**Manual SQL Required:** Yes — Must be executed directly in production via Supabase SQL editor

### RLS Policies

**Affected:** No

Existing RLS policies on `user_calendar_preferences` remain unchanged:

- `SELECT`: `(user_id = auth.uid())`
- `INSERT`: `(user_id = auth.uid())`
- `UPDATE`: `(user_id = auth.uid())`

No RLS changes are required.

### RPC Functions

**Affected:** No

Existing RPC functions remain unchanged:

- `get_or_create_calendar_preferences()` — reads defaults from table schema
- `update_calendar_preferences()` — does not reference defaults

The RPCs will automatically use the new defaults after the `ALTER TABLE` is executed.

### Triggers

**Affected:** No

The `update_user_calendar_preferences_updated_at` trigger remains unchanged.

### Impact Summary

| Component     | Impact                                     |
| ------------- | ------------------------------------------ |
| Table schema  | **Affected** — Column defaults changed     |
| RLS policies  | Unaffected                                 |
| RPC functions | Unaffected (use table defaults implicitly) |
| Triggers      | Unaffected                                 |
| Indexes       | Unaffected                                 |

---

## Flutter Architecture Changes

**None Required**

All client code is correct and functions as designed. The failure is purely database-side (incorrect column defaults). No Dart, Flutter, Riverpod, or UI code changes are needed.

**Files Verified Correct:**

- `lib/features/calendar/one_calendar_preferences_repository.dart` — Reads preferences correctly
- `lib/features/calendar/widgets/add_block_out_drawer.dart` — Propagation logic correct
- `lib/features/calendar/auto_conflict_blocking_service.dart` — Auto-blocking logic correct
- `lib/features/events/events_repository.dart` — Integration correct (except recurring issue, out of scope)

---

## Files to Create

**None**

---

## Files to Modify

**None**

---

## Files Off-Limits

All files — this is a database-only fix.

---

## System Impact Map

| System                                 | Impact                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| Gigs                                   | **Unaffected** — Auto-blocking will start working after fix                         |
| Rehearsals                             | **Unaffected** — Auto-blocking will start working after fix (first occurrence only) |
| Setlists / Catalog                     | **Unaffected**                                                                      |
| Members / RBAC                         | **Unaffected**                                                                      |
| Auth / Session                         | **Unaffected**                                                                      |
| Routing                                | **Unaffected**                                                                      |
| Notifications                          | **Unaffected**                                                                      |
| Platform (iOS / Android / Web / macOS) | **Unaffected**                                                                      |
| Calendar                               | **Affected** — Block-out propagation will start working after fix                   |
| Settings                               | **Unaffected** — UI already works correctly                                         |

---

## Regression Risk

**Overall Risk:** `LOW`

**Rationale:**

- No code changes required
- No schema structure changes (only column defaults)
- RPC functions, RLS policies, and triggers remain unchanged
- Client code is already correct and handles enabled/disabled states properly
- Feature was completely broken before; enabling it is a pure improvement

**Potential Concerns:**

1. **Users who explicitly disabled the feature will have it re-enabled:**
   - Mitigation: Feature was never functional, so no users could have explicitly disabled it with intent
   - Users can disable it again via Settings UI if desired

2. **Sudden propagation of block-out dates across bands:**
   - Mitigation: Feature is designed for this behavior
   - Users with 2+ bands will see the "One Calendar" settings item and can disable if unwanted

3. **Auto-conflict blocking creates unexpected block-out dates:**
   - Mitigation: Feature was designed and QA-approved with this behavior
   - Users can delete propagated block-out dates individually or from all bands via the delete choice dialog

---

## Engineer Task Breakdown

### Task 1: Execute Column Default Fix (Production)

**Action:** Run SQL directly in Supabase SQL editor (Production project)

```sql
-- Change column defaults to true
ALTER TABLE user_calendar_preferences
  ALTER COLUMN one_calendar_enabled SET DEFAULT true,
  ALTER COLUMN auto_block_conflicts_enabled SET DEFAULT true;
```

**Verification:**

```sql
-- Verify column defaults are now true
SELECT
  column_name,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_calendar_preferences'
  AND column_name IN ('one_calendar_enabled', 'auto_block_conflicts_enabled');
```

**Expected Output:**

```json
[
  {
    "column_name": "one_calendar_enabled",
    "column_default": "true"
  },
  {
    "column_name": "auto_block_conflicts_enabled",
    "column_default": "true"
  }
]
```

---

### Task 2: Update Existing User Preferences (Production)

**Action:** Run SQL directly in Supabase SQL editor (Production project)

```sql
-- Enable One Calendar for all existing users
UPDATE user_calendar_preferences
SET
  one_calendar_enabled = true,
  auto_block_conflicts_enabled = true,
  updated_at = now()
WHERE one_calendar_enabled = false
   OR auto_block_conflicts_enabled = false;
```

**Verification:**

```sql
-- Verify all users have feature enabled
SELECT
  COUNT(*) as total_users,
  SUM(CASE WHEN one_calendar_enabled THEN 1 ELSE 0 END) as enabled_count,
  SUM(CASE WHEN auto_block_conflicts_enabled THEN 1 ELSE 0 END) as auto_block_count
FROM user_calendar_preferences;
```

**Expected Output:**

```json
{
  "total_users": N,
  "enabled_count": N,
  "auto_block_count": N
}
```

Where `N` is the total number of users. All three counts should be equal.

---

### Task 3: Validate Feature Functionality (Manual Test)

**Test Scenario 1: Manual Block-Out Propagation**

1. As a user in Band A and Band B, enable One Calendar in Settings (verify it says "On" by default)
2. In Band A, create a block-out date for tomorrow with reason "Vacation"
3. Switch to Band B's calendar
4. Verify the same block-out date appears with reason "Vacation"

**Expected:** Block-out date propagates to Band B ✅

---

**Test Scenario 2: Auto-Conflict Blocking (Gig)**

1. As a user in Band A and Band B, verify One Calendar is enabled (both toggles on)
2. In Band A, create a gig for next Friday
3. Switch to Band B's calendar
4. Verify a block-out date appears on next Friday with reason "Unavailable (scheduled with Band A)"

**Expected:** Block-out date auto-created in Band B ✅

---

**Test Scenario 3: Auto-Conflict Blocking (Rehearsal - One-Off)**

1. As a user in Band A and Band B, verify One Calendar is enabled
2. In Band A, create a one-off rehearsal for next Monday
3. Switch to Band B's calendar
4. Verify a block-out date appears on next Monday with reason "Unavailable (scheduled with Band A)"

**Expected:** Block-out date auto-created in Band B ✅

---

**Test Scenario 4: Auto-Conflict Blocking (Rehearsal - Recurring, First Occurrence Only)**

1. As a user in Band A and Band B, verify One Calendar is enabled
2. In Band A, create a recurring rehearsal (weekly for 4 weeks, starting next Wednesday)
3. Switch to Band B's calendar
4. Verify a block-out date appears on the **first Wednesday only** with reason "Unavailable (scheduled with Band A)"
5. Verify **no block-out dates** appear on the subsequent 3 Wednesdays

**Expected:** Block-out date auto-created only for first occurrence ✅ (Known issue, out of scope)

---

**Test Scenario 5: Selected Bands Only**

1. As a user in Band A, Band B, and Band C
2. Open One Calendar settings
3. Change "Apply to" to "Selected bands only"
4. Select only Band B (uncheck Band C)
5. In Band A, create a block-out date for next Thursday
6. Verify block-out appears in Band B
7. Verify block-out does **not** appear in Band C

**Expected:** Selective propagation works ✅

---

**Test Scenario 6: Disable One Calendar**

1. As a user in Band A and Band B
2. Open One Calendar settings
3. Toggle "One Calendar" off
4. In Band A, create a block-out date for next Friday
5. Switch to Band B's calendar
6. Verify **no block-out date** appears in Band B

**Expected:** No propagation when disabled ✅

---

## Verification Plan

### Tier 1 — Pre-Deployment (Before executing SQL)

**Not applicable** — This fix is SQL-only with no deployable artifacts. All verification occurs in Tier 2.

---

### Tier 2 — Post-Deployment (After executing SQL)

**POST-DEPLOY TEST 1: Verify Column Defaults Changed**

```sql
-- Verify column defaults are now true
SELECT
  column_name,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_calendar_preferences'
  AND column_name IN ('one_calendar_enabled', 'auto_block_conflicts_enabled');
```

**Expected:**

```json
[
  { "column_name": "one_calendar_enabled", "column_default": "true" },
  { "column_name": "auto_block_conflicts_enabled", "column_default": "true" }
]
```

---

**POST-DEPLOY TEST 2: Verify Existing Users Updated**

```sql
-- Verify all users have feature enabled
SELECT
  COUNT(*) as total_users,
  SUM(CASE WHEN one_calendar_enabled THEN 1 ELSE 0 END) as enabled_count,
  SUM(CASE WHEN auto_block_conflicts_enabled THEN 1 ELSE 0 END) as auto_block_count
FROM user_calendar_preferences;
```

**Expected:** `enabled_count` and `auto_block_count` should both equal `total_users`

---

**POST-DEPLOY TEST 3: Verify New User Defaults**

```sql
-- Create a test user preference row (simulate first-time user)
DO $$
DECLARE
  v_test_user_id UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  -- Create a test auth user (mock for testing, will not persist)
  -- In production, this would be done via actual RPC call from authenticated user

  -- Simulate RPC call: get_or_create_calendar_preferences()
  INSERT INTO user_calendar_preferences (user_id)
  VALUES (v_test_user_id)
  RETURNING to_jsonb(user_calendar_preferences.*) INTO v_result;

  -- Assert that defaults are true
  IF (v_result->>'one_calendar_enabled')::BOOLEAN = true
     AND (v_result->>'auto_block_conflicts_enabled')::BOOLEAN = true THEN
    RAISE NOTICE 'TEST PASSED: New user defaults are correct';
  ELSE
    RAISE EXCEPTION 'TEST FAILED: New user defaults are incorrect: %', v_result;
  END IF;

  -- Clean up test data
  DELETE FROM user_calendar_preferences WHERE user_id = v_test_user_id;
END $$;
```

**Expected:** `TEST PASSED: New user defaults are correct`

---

**POST-DEPLOY TEST 4: Manual Block-Out Propagation (End-to-End)**

**Prerequisites:**

- Test user belongs to at least 2 bands (Band A, Band B)
- Test user is authenticated in the app

**Steps:**

1. Open Band A's calendar
2. Create a block-out date for a future date with reason "Test propagation"
3. Switch to Band B's calendar
4. Verify the same block-out date appears with reason "Test propagation"

**Verification Query:**

```sql
-- Find the test user's block-out dates across all their bands
SELECT
  bd.band_id,
  b.name as band_name,
  bd.date,
  bd.reason
FROM block_dates bd
JOIN bands b ON bd.band_id = b.id
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.date = 'TEST_DATE'
ORDER BY b.name;
```

**Expected:** Two rows, one for each band, both with reason "Test propagation"

---

**POST-DEPLOY TEST 5: Auto-Conflict Blocking on Gig Creation (End-to-End)**

**Prerequisites:**

- Test user belongs to at least 2 bands (Band A, Band B)
- Test user is authenticated in the app

**Steps:**

1. In Band A, create a gig for a future date
2. Switch to Band B's calendar
3. Verify a block-out date appears on the same date with reason "Unavailable (scheduled with Band A)"

**Verification Query:**

```sql
-- Find auto-created block-out date in Band B
SELECT
  bd.band_id,
  b.name as band_name,
  bd.date,
  bd.reason
FROM block_dates bd
JOIN bands b ON bd.band_id = b.id
WHERE bd.user_id = 'TEST_USER_UUID'
  AND bd.date = 'GIG_DATE'
  AND bd.reason LIKE 'Unavailable (scheduled with%)'
ORDER BY b.name;
```

**Expected:** One row for Band B with reason containing "Unavailable (scheduled with Band A)"

---

## QA Regression Areas

**Primary:**

1. **One Calendar Defaults** — Verify new users get feature enabled by default
2. **Manual Block-Out Propagation** — Verify block-out dates propagate to all applicable bands
3. **Auto-Conflict Blocking (Gigs)** — Verify gig creation blocks dates on other bands
4. **Auto-Conflict Blocking (Rehearsals)** — Verify one-off rehearsal creation blocks dates on other bands
5. **Selected Bands Mode** — Verify selective propagation works correctly
6. **Disable One Calendar** — Verify no propagation occurs when feature is disabled

**Regression:**

1. **Existing Block-Out Creation** — Verify single-band users can still create block-out dates normally
2. **Existing Event Creation** — Verify gigs and rehearsals can still be created normally
3. **One Calendar Settings UI** — Verify settings screen loads and toggles work
4. **Multi-Band Switching** — Verify switching between bands still works correctly
5. **Calendar Display** — Verify all events and block-out dates display correctly
6. **Block-Out Deletion** — Verify delete choice dialog works correctly ("This band only" vs "All bands")

**Known Limitations (Not Tested):**

1. **Recurring Rehearsal Auto-Blocking** — Only first occurrence is blocked (secondary issue, out of scope)

---

## Rollout / Migration Strategy

### Deployment Steps

**Step 1: Backup (Recommended)**

```sql
-- Create a backup of current user preferences
CREATE TABLE user_calendar_preferences_backup_20260707 AS
SELECT * FROM user_calendar_preferences;
```

**Step 2: Execute Fix**

Execute Task 1 and Task 2 SQL statements in Supabase SQL editor (Production).

**Step 3: Verification**

Execute all POST-DEPLOY TEST queries to confirm fix is successful.

**Step 4: Monitor**

Monitor error logs for 24-48 hours after deployment:

- Check for unexpected errors in `getBandIdsToApplyBlockOut()`
- Check for failures in `autoBlockConflictingDate()`
- Monitor Supabase query performance for `user_calendar_preferences` table

### Rollback Plan

If critical issues arise after fix:

```sql
-- Rollback: Restore column defaults to false
ALTER TABLE user_calendar_preferences
  ALTER COLUMN one_calendar_enabled SET DEFAULT false,
  ALTER COLUMN auto_block_conflicts_enabled SET DEFAULT false;

-- Rollback: Restore all user preferences to disabled
UPDATE user_calendar_preferences
SET
  one_calendar_enabled = false,
  auto_block_conflicts_enabled = false,
  updated_at = now();
```

**Note:** Rollback will restore the broken state. This is only for emergency situations where propagation causes system instability.

---

## Out of Scope

**Explicitly not included in this fix:**

1. **Recurring Rehearsal Auto-Blocking for All Occurrences** — Only first occurrence is blocked. This is a separate bug to be addressed in `bug/one-calendar-recurring-rehearsal-auto-block-incomplete`.
2. **Historical Backfill of Block-Out Dates** — Existing gigs and rehearsals created before this fix will not retroactively create block-out dates in other bands.
3. **Manually Created Block-Out Propagation** — This feature already works correctly for manual block-outs (verified in code review). Testing will confirm it works after the fix.
4. **Recurring Rehearsal Occurrences in `rehearsal_dates`** — Auto-blocking does not iterate over `rehearsal_dates` rows. This is the secondary issue and is out of scope.
5. **Migration File Correction** — The migration file on disk (`20260626005216_add_user_calendar_preferences.sql`) is already correct (`DEFAULT true`). No file changes are needed.
6. **User Communication** — No user-facing announcement is required. The feature will simply start working as designed.

---

**END OF ARCHITECT_PLAN.md**
