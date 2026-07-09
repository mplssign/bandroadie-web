# ARCHITECT PLAN — Cross-Band Block-Out Visibility

**Feature Identifier:** `bug/cross-band-blockout-visibility`  
**Type:** Bug  
**Date:** 2026-07-08  
**Status:** **ROOT CAUSE CONFIRMED — Ready for Implementation**

---

## Problem Summary

Tony is a member of multiple bands. He sets a block-out (unavailability) date while viewing one band's calendar and expects that date to also show as blocked/unavailable on his other bands' calendars, since he physically cannot be in two places on the same date. Currently the block-out only appears on the band it was created under.

**Critical Context:**  
Tony just deployed a new production web build to app.bandroadie.com today (2026-07-08) and wants this diagnosed before shipping matching mobile builds. This is a diagnosis-first investigation — do not assume a fix direction without presenting findings and tradeoffs for confirmation.

---

## Diagnosis

### Phase 0 — Workspace Verification ✅

```bash
Branch: main
Status: working tree clean
```

Git state is clean. No uncommitted changes to block investigation.

---

### Phase 1 — Schema Analysis ✅

**Table: `block_dates`**

Schema (from `lib/app/models/block_out.dart` header comment and repository code):

```sql
id          UUID PRIMARY KEY
user_id     UUID NOT NULL REFERENCES auth.users(id)
band_id     UUID NOT NULL REFERENCES bands(id)
date        DATE NOT NULL
reason      TEXT NOT NULL
created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
UNIQUE(user_id, band_id, date)
```

**Key Finding:**  
The `block_dates` table is **inherently band-scoped**. Each row is explicitly tied to a single `(user_id, band_id)` pair. The unique constraint `(user_id, band_id, date)` allows the same date to be blocked multiple times for a user — once per band.

**Calendar Display Query:**  
`lib/features/calendar/calendar_notifier.dart` queries block-out dates filtered by `band_id`:

```dart
supabase.from('block_dates').select().eq('band_id', bandId).order('date');
```

This means:

- Block-out created in Band A writes to `block_dates` with `band_id = Band A ID`
- Band B's calendar queries `block_dates` with `band_id = Band B ID`
- **Without additional propagation logic, Band B will never see Band A's block-out**

**Verdict:**  
Per-band isolation is the **default architectural behavior** of the `block_dates` table. Cross-band visibility requires explicit duplication of rows.

---

### Phase 2 — One Calendar Feature Investigation ✅

**Discovery:**  
A feature called "One Calendar" was designed, implemented, QA'd, and deployed on **2026-06-26** (11 days ago) to solve this exact problem.

**Migration:** `supabase/migrations/20260626005216_add_user_calendar_preferences.sql`

**Table: `user_calendar_preferences`**

```sql
CREATE TABLE user_calendar_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  one_calendar_enabled BOOLEAN NOT NULL DEFAULT true,              -- ✅ DEFAULT TRUE
  apply_to_mode TEXT NOT NULL DEFAULT 'all_bands',                 -- 'all_bands' or 'selected_bands'
  selected_band_ids UUID[] DEFAULT '{}',
  auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT true,      -- ✅ DEFAULT TRUE
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);
```

**How One Calendar Works:**

1. **Manual block-out propagation** (`lib/features/events/widgets/event_editor_drawer.dart` lines 1104-1127):
   - After creating a block-out in the current band, the code checks One Calendar preferences
   - If `one_calendar_enabled = true`, it fetches the user's bands via `getBandIdsToApplyBlockOut()`
   - For each other band, it creates a duplicate block-out row with the same date/reason
   - Wrapped in try-catch (non-blocking — must not fail primary save)

2. **Auto-conflict blocking** (`lib/features/calendar/auto_conflict_blocking_service.dart`):
   - When a gig or rehearsal is created, auto-creates block-outs in other bands
   - Only if `one_calendar_enabled = true` AND `auto_block_conflicts_enabled = true`
   - Reason: `"Unavailable (scheduled with [Band Name])"`

**Settings UI Visibility:**  
`lib/features/settings/settings_screen.dart` lines 59-71:

```dart
final bandCount = ref.watch(activeBandProvider).userBands.length;
if (bandCount >= 2) {
  regularItems.add(SettingsItem(
    icon: AppIcons.calendar,
    label: 'One Calendar',
    subtitle: 'Share block-out dates across bands',
    onTap: _openOneCalendar,
  ));
}
```

**Critical Finding:**  
The "One Calendar" settings item is **only visible if the user belongs to 2+ bands**. If Tony has only 1 band, he would never see this setting.

---

### Phase 3 — Bug History Analysis ✅

**Timeline:**

1. **2026-06-26** — Commit `b6c833c`: `feat: One Calendar / shared block-out dates across bands`
   - Initial implementation and deployment
   - Migration deployed to production database (confirmed in QA report)
   - Defaults: `one_calendar_enabled = true`, `auto_block_conflicts_enabled = true`

2. **Later (exact date unknown)** — Bug discovered: Manual block-out propagation was broken
   - Feature identifier: `bug/one-calendar-manual-blackout`
   - Root cause: The live code path (`event_editor_drawer.dart`) initially lacked propagation logic
   - A separate file (`add_block_out_drawer.dart`) had correct propagation but was dead code

3. **Commit `bb3e9d0`**: `fix(calendar): propagate manual blockout dates across bands when One Calendar enabled (#39)`
   - Fix applied to `event_editor_drawer.dart`
   - Propagation logic added at lines 1104-1127
   - Fix is present in current `main` branch

4. **Multiple subsequent fixes:**
   - Commit `25c2b57`: `docs(calendar): architect plan for one-calendar propagation fix (db-only, applied manually 2026-07-07)` — yesterday
   - Commit `e3e60ec`: `fix(calendar): auto-block all occurrences of recurring rehearsals...`

**Verdict:**  
The One Calendar feature exists in production code and has undergone multiple bug fixes. The manual block-out propagation fix IS present in the codebase.

---

### Phase 4 — Current Code Verification ✅

**File:** `lib/features/events/widgets/event_editor_drawer.dart` lines 1104-1127

```dart
// One Calendar propagation: if enabled, replicate blockout to other bands.
// Wrapped in try-catch — must not fail the primary save.
try {
  final prefsRepo = ref.read(oneCalendarPreferencesRepositoryProvider);
  final userBandIds =
      ref.read(activeBandProvider).userBands.map((b) => b.id).toList();
  final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userBandIds);
  final otherBandIds =
      bandIds.where((id) => id != widget.bandId).toList();
  for (final bandId in otherBandIds) {
    try {
      await repository.createBlockOut(
        bandId: bandId,
        userId: userId,
        startDate: _selectedDate,
        untilDate: _blockOutUntilDate,
        reason: _notesController.text.trim(),
      );
    } catch (e) {
      debugPrint(
        '[EventEditorDrawer] Propagation failed for band $bandId: $e',
      );
    }
  }
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}
```

**Verdict:**  
Manual block-out propagation logic is present and correct. If One Calendar is enabled, it will propagate block-outs to other bands.

---

### Phase 5 — Root Cause Hypothesis ✅

**Confidence: HIGH (confirmed by code evidence)**

The `block_dates` table is **designed to be per-band by default**. Cross-band visibility was **never part of the original design** — it was added later via the One Calendar feature (2026-06-26).

Tony's issue can be caused by one of the following:

| Root Cause                                        | Likelihood | Evidence                                                                                                                                 |
| ------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **RC-1: One Calendar is disabled**                | HIGH       | Default is TRUE, but Tony may have toggled it OFF in settings, or preferences row may not exist / RPC may have failed to create defaults |
| **RC-2: Tony is unaware of One Calendar feature** | HIGH       | Settings item is only visible for users with 2+ bands; Tony may not have discovered it or may not know it needs to be enabled            |
| **RC-3: Tony has only 1 band**                    | MEDIUM     | If Tony has only 1 band, the settings item is hidden AND cross-band propagation is irrelevant (no other bands to propagate to)           |
| **RC-4: Browser cache serving old code**          | MEDIUM     | Tony just deployed web to production; PWA service worker may be serving cached pre-One-Calendar code; requires hard refresh              |
| **RC-5: Preferences RPC is broken**               | LOW        | Migration deployed 11 days ago; if RPC was broken, other users would have reported it; manual SQL verification needed                    |
| **RC-6: Propagation logic has a regression**      | LOW        | Code inspection shows logic is present and correct; would require runtime debugging to confirm                                           |

---

### Phase 6 — Tier 1 Verification (COMPLETE) ✅

**Tony confirmed via settings UI:**
- ✅ One Calendar is **ON**
- ✅ Mode is set to **"All bands"**
- ✅ Auto-conflict blocking is **ON**
- ✅ Tony has **3 active bands** ("Open Mic", "The Second Summer", "Toxic Crayon")

**SQL Verification (user_id: `671b32e8-60eb-448a-8167-106bf835297f`):**

```sql
-- Preferences state (confirmed)
one_calendar_enabled: true
apply_to_mode: all_bands
auto_block_conflicts_enabled: true
created_at: 2026-06-26 21:55:31 (11 days ago — correct migration date)

-- Band membership (confirmed)
3 active bands:
- "Open Mic" (6740246d-ba9b-493e-936d-ba733ce2101d)
- "The Second Summer" (6d71a662-f1a4-4fb9-a611-9b2c8e7716d3)
- "Toxic Crayon" (003be463-e63a-4ec5-b152-4f64c60afcbf)
```

**RC-1, RC-2, RC-3 ruled out.** Tier 1 checks passed. Moving to Tier 2.

---

### Phase 7 — Tier 2 Database Verification (COMPLETE) ✅

**Reproduction Test:**  
Tony created a block-out in an incognito window, then checked his regular (already-open) browser window showing a different band — the block-out did not appear.

**Database Query Results:**

**Test 1 — Recent block-out with "Test" reason (2026-10-01):**
```
Created: 2026-07-09 03:26:20 (all within 200ms)
✅ Open Mic:         03:26:20.990461
✅ The Second Summer: 03:26:20.935362  
✅ Toxic Crayon:     03:26:20.822075
```
**Verdict:** Propagation **WORKED** — all 3 bands received the block-out.

**Test 2 — Earlier block-out (2026-08-04):**
```
Created: 2026-07-09 03:25:23
✅ Open Mic:         03:25:23.990926
❌ The Second Summer: (pre-existing from 2026-05-24 22:41:30)
✅ Toxic Crayon:     03:25:23.616281
```
**Verdict:** Propagation **PARTIAL** — skipped "The Second Summer" due to unique constraint violation (block-out for that date already existed from May 24th). This is **correct behavior** — propagation code has try-catch that gracefully skips duplicates.

**RLS Policy Check:**
```sql
INSERT policy: is_band_member(band_id) AND (user_id = auth.uid())
```
This is correct. Tony is a member of all 3 bands, so cross-band writes are permitted.

**Unique Constraint:**
```sql
UNIQUE (user_id, band_id, date)
```
Prevents duplicate block-outs for the same user/band/date. Working as designed.

---

### Phase 8 — Git History Verification ✅

**Deployed Code Verification:**

All three critical commits are present in `main` branch:
- ✅ `bb3e9d0` — Manual block-out propagation fix (deployed)
- ✅ `25c2b57` — DB-only propagation fix documentation (2026-07-07)
- ✅ `e3e60ec` — Recurring rehearsal auto-block fix (deployed)

**Verdict:** Propagation logic is present and correct in deployed code.

---

### Phase 9 — Root Cause Confirmed ✅

**Confidence: HIGH (confirmed by database + code evidence)**

**The propagation logic works correctly** — block-outs DO propagate to all other bands at the database level. The issue Tony experienced is a **stale cache / no realtime sync** problem:

**How the bug manifests:**

1. Tony creates a block-out in **Browser Window A** (incognito, viewing Band A)
2. Propagation writes rows to all 3 bands in the database ✅ (confirmed by SQL)
3. `event_editor_drawer.dart` calls `ref.read(calendarProvider.notifier).invalidateAndRefresh(bandId: widget.bandId)` at line 1134
4. This invalidates the cache **ONLY** for Band A in Window A's Riverpod state
5. Tony switches to **Browser Window B** (already-open regular browser, viewing Band B)
6. Window B's `calendarProvider` state is **NOT invalidated** because:
   - Riverpod state is **not shared across browser tabs/windows**
   - There is **no realtime subscription** to database changes
   - Window B's calendar is using **cached data** from its last load
7. Tony refreshes the view or switches months → still shows cached data
8. Tony must **manually reload the page** (Cmd+R) or navigate away and back to trigger a fresh database query

**The same issue occurs within a single tab:**  
If Tony creates a block-out while viewing Band A, then switches to Band B's calendar view in the same tab, Band B's calendar will use cached data unless the cache TTL (5 minutes) has expired or a manual refresh is triggered.

**File: `lib/features/calendar/calendar_controller.dart` lines 433-443:**

```dart
Future<void> invalidateAndRefresh({required String bandId}) async {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();

  for (final key in keysToRemove) {
    _cache.remove(key);
  }

  await loadEvents(forceRefresh: true);
}
```

This method only invalidates cache keys for the **specified bandId**. Other bands' caches remain untouched.

**Root Cause Summary:**

| Component | Behavior | Issue |
|-----------|----------|-------|
| **Propagation logic** | ✅ CORRECT | Writes to all bands successfully |
| **Database writes** | ✅ CORRECT | Rows exist for all target bands |
| **RLS policies** | ✅ CORRECT | Cross-band writes permitted |
| **Cache invalidation** | ❌ **INCOMPLETE** | Only invalidates current band's cache |
| **Realtime sync** | ❌ **MISSING** | No Supabase Realtime subscription for `block_dates` changes |

**Why this wasn't caught earlier:**

One Calendar was designed and QA'd using code-path analysis, not runtime testing with multiple browser tabs open simultaneously. The QA report explicitly states: "Validation Method: Code-path analysis only (runtime testing blocked by migration deployment failure)."

---

## Proposed Solution

### Path: Multi-Band Cache Invalidation

**Approach:**  
When a block-out is created with One Calendar enabled, invalidate the calendar cache for **all bands** the user belongs to, not just the current band.

**Implementation:**

Modify `lib/features/events/widgets/event_editor_drawer.dart` at line 1134 (after propagation completes):

**Current code:**
```dart
// Refresh calendar
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);
```

**Proposed code:**
```dart
// Refresh calendar for current band
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);

// One Calendar cross-band cache invalidation: if One Calendar is enabled,
// invalidate cache for all other bands so they pick up the propagated block-out
// when user switches bands (within this tab/window)
if (otherBandIds.isNotEmpty) {
  for (final bandId in otherBandIds) {
    // Invalidate only — don't await loadEvents() for other bands
    // (user isn't viewing them right now)
    final keysToRemove = CalendarNotifier._cache.keys
        .where((key) => key.startsWith('$bandId-'))
        .toList();
    for (final key in keysToRemove) {
      CalendarNotifier._cache.remove(key);
    }
  }
}
```

**Alternative (cleaner):** Add a helper method to `CalendarNotifier`:

```dart
void invalidateCacheForBand(String bandId) {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();
  for (final key in keysToRemove) {
    _cache.remove(key);
  }
}
```

Then call it from `event_editor_drawer.dart`:

```dart
// Refresh calendar for current band
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);

// One Calendar: invalidate cache for other bands
if (otherBandIds.isNotEmpty) {
  final notifier = ref.read(calendarProvider.notifier);
  for (final bandId in otherBandIds) {
    notifier.invalidateCacheForBand(bandId);
  }
}
```

**What this fixes:**
- ✅ Within the same browser tab: switching from Band A to Band B will show the new block-out
- ❌ Across browser tabs/windows: still requires manual page reload (no cross-tab state sync)

**What this doesn't fix:**
- Cross-tab/window sync (requires Supabase Realtime subscription — separate feature)
- Other users' calendars updating when you create a block-out (requires Realtime)

**Blast Radius:** LOW  
**Files Modified:** 2 (`calendar_controller.dart`, `event_editor_drawer.dart`)  
**Regression Risk:** LOW (cache invalidation is safe; worst case = more database queries)

---

## Path Analysis

### Path A: Cross-Band Sharing is the Correct Fix (One Calendar Enforcement)

**Assumption:**  
Tony's expectation is correct — musicians cannot be in two places at once. Block-outs should be shared across all bands a user belongs to by default.

**What This Means:**

The One Calendar feature already solves this. The issue is:

1. **User Awareness:** Tony may not know about One Calendar or that it needs to be checked in settings
2. **Preferences State:** Tony's `user_calendar_preferences` row may have `one_calendar_enabled = false` (either manually toggled or RPC failed to create defaults)
3. **Cache Issue:** Tony's browser may be serving old code from before One Calendar was deployed

**Required Actions (if this path is chosen):**

1. **Tier 1 Verification (SQL):**

   ```sql
   -- Check if Tony has a preferences row and what the values are
   SELECT
     one_calendar_enabled,
     apply_to_mode,
     auto_block_conflicts_enabled,
     created_at
   FROM user_calendar_preferences
   WHERE user_id = 'TONY_USER_ID';
   -- Expected: Row exists with one_calendar_enabled = true

   -- Check Tony's band membership
   SELECT
     bm.band_id,
     b.name as band_name,
     bm.role,
     bm.status
   FROM band_members bm
   JOIN bands b ON b.id = bm.band_id
   WHERE bm.user_id = 'TONY_USER_ID'
     AND bm.status = 'active';
   -- Expected: 2+ rows (Tony must have 2+ bands for cross-band to matter)

   -- Check if block-outs exist in only one band
   SELECT
     bd.band_id,
     b.name as band_name,
     bd.date,
     bd.reason
   FROM block_dates bd
   JOIN bands b ON b.id = bd.band_id
   WHERE bd.user_id = 'TONY_USER_ID'
   ORDER BY bd.date, b.name;
   -- Expected: If One Calendar is OFF, dates appear in only one band
   ```

2. **If preferences row doesn't exist or is FALSE:**
   - Option A: Enable One Calendar for Tony via SQL update
   - Option B: Guide Tony to enable it via Settings UI
   - Option C: Change migration default (affects all future users, not retroactive)

3. **If preferences row is TRUE but propagation didn't happen:**
   - Check browser console for JavaScript errors
   - Verify RPC `get_or_create_calendar_preferences` returns correct data
   - Check if `getBandIdsToApplyBlockOut()` repository method is working
   - Test in incognito mode (bypass cache)

4. **If this is a cache issue:**
   - Tony needs to hard refresh (Cmd+Shift+R on macOS Chrome/Firefox)
   - Or clear PWA cache / reinstall PWA

**Blast Radius:** LOW — existing feature, no code changes required  
**Effort:** LOW — SQL verification + settings check  
**Risk:** LOW — feature already exists and is working for other users (presumably)

---

### Path B: Per-Band Isolation is Correct by Design (No Fix Required)

**Assumption:**  
The original per-band design was intentional. Block-outs are band-specific because:

- Different bands may have different scheduling contexts
- A user may want to mark unavailability for one band but not another
- Cross-band sharing should be opt-in, not automatic

**What This Means:**

Tony's expectation doesn't match the product design. The One Calendar feature already exists as an **opt-in** solution for users who want cross-band sharing. If Tony hasn't enabled it, the app is working as designed.

**Required Actions (if this path is chosen):**

1. **Confirm Intent:**
   - Is cross-band sharing supposed to be opt-in or automatic?
   - Should new users have One Calendar ON or OFF by default?
   - Current default: ON (migration default is TRUE)

2. **If opt-in is correct:**
   - Educate Tony about One Calendar feature
   - Ensure settings UI is discoverable
   - Verify Tony has 2+ bands (required for feature visibility)
   - No code changes needed

3. **If automatic is correct:**
   - Change product strategy: remove One Calendar toggle, make cross-band sharing always-on
   - Requires migration to remove `one_calendar_enabled` flag
   - Simplifies UX but removes user choice
   - Blast radius: MEDIUM (affects all users)

**Blast Radius:** NONE if opt-in is correct; MEDIUM if changing to always-on  
**Effort:** NONE if opt-in is correct; MEDIUM if changing to always-on  
**Risk:** NONE if no changes; MEDIUM if changing behavior for all users

---

## Recommendation

**Confidence: HIGH (root cause confirmed)**

This is a **calendar cache invalidation bug**. The propagation logic works correctly and writes to all bands, but the calendar view doesn't refresh to show the new data unless the user:
- Reloads the page (Cmd+R)
- Waits 5 minutes for cache to expire
- Navigates away from calendar and back

**Recommended Implementation:**

Add multi-band cache invalidation to `event_editor_drawer.dart` after block-out propagation completes. See "Proposed Solution" section above for code details.

**Effort:** LOW (2-file change)  
**Risk:** LOW (cache invalidation is safe)  
**Blast Radius:** LOW (only affects calendar after creating block-outs)

---

## Database Impact

**None** — this is a frontend cache issue, not a database issue.

---

## Files Investigated

| File                                                                   | Purpose                        | Finding                                                                        |
| ---------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------ |
| `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` | One Calendar migration         | Defaults: `one_calendar_enabled = true`, `auto_block_conflicts_enabled = true` |
| `lib/features/events/widgets/event_editor_drawer.dart`                 | Manual block-out creation      | Propagation logic present at lines 1104-1127 ✅                                |
| `lib/features/calendar/auto_conflict_blocking_service.dart`            | Auto-conflict blocking         | Propagation logic present for gig/rehearsal creation ✅                        |
| `lib/features/calendar/block_out_repository.dart`                      | Block-out data layer           | Per-band by design; supports cross-band writes via multiple inserts            |
| `lib/features/calendar/one_calendar_settings_screen.dart`              | One Calendar settings UI       | Exists; only visible for users with 2+ bands                                   |
| `lib/features/settings/settings_screen.dart`                           | Main settings menu             | "One Calendar" item conditionally visible                                      |
| `lib/features/calendar/one_calendar_preferences_repository.dart`       | Preferences data layer         | `getBandIdsToApplyBlockOut()` implements propagation logic                     |
| `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md`         | Original feature design        | Feature was intentionally designed to solve this exact problem                 |
| `docs/features/one-calendar-manual-blackout/ARCHITECT_PLAN.md`         | Bug fix for manual propagation | Propagation was broken initially; fix is present in current code               |

---

## Verification Plan

### Tier 1 — Pre-Decision (SQL Verification Required)

**Tony must provide:**

1. **His user ID** (from Supabase auth dashboard or `supabase.auth.currentUser.id` in browser console)

**Run these queries in Supabase SQL Editor:**

```sql
-- QUERY 1: Check Tony's One Calendar preferences
SELECT
  id,
  user_id,
  one_calendar_enabled,
  apply_to_mode,
  selected_band_ids,
  auto_block_conflicts_enabled,
  created_at,
  updated_at
FROM user_calendar_preferences
WHERE user_id = 'TONY_USER_ID';
-- Expected: Row exists with one_calendar_enabled = true (migration default)
-- If no row: RPC failed to create defaults
-- If row exists with FALSE: Tony manually disabled it

-- QUERY 2: Check Tony's band membershipCache invalidation only for current band ❌ |
| `lib/features/calendar/calendar_controller.dart`                       | Calendar state management      | `invalidateAndRefresh()` only clears cache for one band at lines 433-443
SELECT
  bm.id as membership_id,
  bm.band_id,
  b.name as band_name,
  bm.role,
  bm.status,
  bm.joined_at
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = 'TONY_USER_ID'
ORDER BY bm.joined_at;
-- Expected: 2+ rows with status = 'active' (One Calendar requires 2+ bands)

-- QUERY 3: Check Tony's existing block-out dates
SELECT
  bd.id,
  bd.band_id,
  b.name as band_name,
  bd.date,
  bd.reason,
  bd.created_at
FROM block_dates bd
JOIN bands b ON b.id = bd.band_id
WHERE bd.user_id = 'TONY_USER_ID'
ORDER BY bd.date DESC, b.name
LIMIT 20;
-- Expected: If One Calendar is OFF, same date appears in only one band
-- If One Calendar is ON, same date appears in multiple bands with same reason

-- QUERY 4: Check if get_or_create_calendar_preferences RPC works
SELECT * FROM get_or_create_calendar_preferences('TONY_USER_ID');
-- Expected: Returns JSONB with one_calendar_enabled = true
```

### Tier 2 — Post-Decision (if technical bug confirmed)

If Tier 1 shows:

- Preferences exist and `one_calendar_enabled = true`
- Tony has 2+ bands
- Block-outs still don't propagate

Then proceed with:

**Browser Testing:**

1. Open app in incognito mode (bypass cache)
2. Create test block-out in Band A
3. Check browser console for errors
4. Switch to Band B
5. Verify if block-out appears

**Debug Logging:**

Add temporary logging to `event_editor_drawer.dart` propagation block:

```dart
debugPrint('[DEBUG] One Calendar check: bandIds=$bandIds, otherBandIds=$otherBandIds');
```

**RLS Policy Verification:**

```sql
-- Check if block_dates INSERT policy allows cross-band writes
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'block_dates';
-- Expected: INSERT policy allows writes if user is member of target band
```

---

## QA Regression Areas

---

## Engineer Tasks

**Task 1:** Add `invalidateCacheForBand()` helper method to `CalendarNotifier`

**File:** `lib/features/calendar/calendar_controller.dart`

Add after the existing `invalidateAndRefresh()` method (around line 444):

```dart
/// Invalidates cache for a specific band without triggering a reload.
/// Used for cross-band cache invalidation when One Calendar propagates block-outs.
void invalidateCacheForBand(String bandId) {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();
  for (final key in keysToRemove) {
    _cache.remove(key);
  }
}
```

**Task 2:** Call `invalidateCacheForBand()` for all propagated bands

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

Modify the block after One Calendar propagation (around line 1127, after the propagation try-catch closes):

**Current:**
```dart
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}

// Close drawer, refresh, etc.
if (mounted) {
  Navigator.of(context).pop();
}

// Refresh calendar
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);
```

**Proposed:**
```dart
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}

// Close drawer, refresh, etc.
if (mounted) {
  Navigator.of(context).pop();
}

// Refresh calendar for current band
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);

// One Calendar cross-band cache invalidation: if block-outs were propagated
// to other bands, invalidate their calendar caches so they pick up the new
// data when user switches bands (within this tab/window).
if (otherBandIds.isNotEmpty) {
  final notifier = ref.read(calendarProvider.notifier);
  for (final bandId in otherBandIds) {
    notifier.invalidateCacheForBand(bandId);
  }
}
```

**Note:** The variable `otherBandIds` is already available from the propagation logic above (line ~1112).

---

## Testing Instructions

**Manual Test 1: Same-tab band switching**

1. Navigate to Band A's calendar
2. Create a block-out for a future date (e.g., tomorrow)
3. Switch to Band B's calendar view (same browser tab)
4. **Expected:** Block-out appears on Band B's calendar immediately (no page reload required)

**Manual Test 2: Cross-tab sync (WILL NOT WORK — expected behavior)**

1. Open Band A's calendar in Tab 1
2. Open Band B's calendar in Tab 2
3. Create a block-out in Tab 1
4. Switch to Tab 2
5. **Expected:** Block-out does NOT appear until user manually reloads page (Cmd+R)
6. **Reason:** Riverpod state is not shared across tabs; would require Supabase Realtime subscription (separate feature)

**Manual Test 3: One Calendar disabled**

1. Settings → One Calendar → Turn OFF
2. Create a block-out in Band A
3. Switch to Band B's calendar
4. **Expected:** Block-out does NOT appear on Band B (no propagation when disabled)

**Manual Test 4: Cache expiration**

1. Create a block-out in Band A
2. Switch to Band B immediately
3. **Expected:** Block-out appears (cache invalidated)
4. Wait 5+ minutes
5. Create another block-out in Band A
6. Switch to Band B
7. **Expected:** Block-out still appears (cache was already stale, forced refresh)

---

## Next Steps

**Status: READY FOR IMPLEMENTATION**

1. **Engineer:** Implement Task 1 and Task 2 above
2. **Engineer:** Test per instructions above
3. **Engineer:** Submit PR with test evidence
4. **Architect:** Review PR, verify fix addresses root cause
5. **Tony:** Deploy to production web, verify in production environment

---

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-07-08  
**Updated:** 2026-07-09 (root cause confirmed)  
**Status:** ROOT CAUSE CONFIRMED — READY FOR IMPLEMENTATION
