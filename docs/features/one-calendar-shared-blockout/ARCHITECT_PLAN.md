# ARCHITECT PLAN — One Calendar / Shared Block-Out Dates

## Feature Slug

`feature/one-calendar-shared-blockout`

---

## Problem Summary

**Problem:** Users who belong to multiple bands must enter the same unavailability dates separately on each band's calendar. This creates friction, risks missed conflicts, and wastes time. Users need a way to mark themselves unavailable once and have that availability propagated to all (or selected) bands they belong to.

**Why:** Multi-band members currently have no way to share their personal unavailability across bands. Each block-out date is scoped to a single band via the `block_dates` table's `(user_id, band_id, date)` unique constraint.

**Desired behavior:**

1. **One Calendar toggle** — shown only if user belongs to 2+ bands
2. **Apply block-out dates to** — All bands OR Selected bands only
3. **Automatic conflict blocking** — when a gig/rehearsal is scheduled in one band, automatically block that date/time on other band calendars

---

## Root Cause

**Current Architecture:**

The `block_dates` table enforces band isolation via a unique constraint on `(user_id, band_id, date)`. Each block-out date is explicitly tied to a single band. The current `BlockOutDrawer` creates block-out dates only for the currently active band.

There is no mechanism for:

- Storing user-level calendar preferences (e.g., "apply block-out dates to all bands")
- Propagating block-out dates across multiple bands when a user creates one
- Automatically blocking dates when a gig/rehearsal is confirmed in one band

**Root Cause Confidence:** `HIGH` — confirmed by direct code observation.

---

## Reference Docs Consulted

**Architecture and Schema:**

- `docs/reference/architecture/database_schema.md` — Reviewed `block_dates` table schema, `band_members` table, and notification system
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — Reviewed multi-band support, event management, and settings architecture

**Code Review:**

- `lib/features/calendar/block_out_repository.dart` — Block-out date repository (creates dates for single band)
- `lib/features/calendar/widgets/add_block_out_drawer.dart` — UI for creating block-out dates (single band only)
- `lib/features/bands/active_band_controller.dart` — Active band state management
- `lib/features/settings/settings_screen.dart` — User settings UI structure
- `lib/features/notifications/models/notification_preferences.dart` — Example of per-user preferences table
- `lib/app/models/block_out.dart` — Block-out date model

---

## Existing System Analysis

### Current Block-Out Date Flow

1. **User Action:** User taps "+ Block Out" on calendar screen
2. **Drawer Opens:** `BlockOutDrawer.show()` displays bottom sheet
3. **User Input:** User selects start date, optional end date, and reason
4. **Save Action:** Drawer calls `BlockOutRepository.createBlockOut()` with `bandId` set to the currently active band
5. **Database Write:** Inserts row(s) into `block_dates` table with `(user_id, band_id, date)` for the active band only
6. **Notification:** Database trigger fires, notifies other band members via `notify_blockout_created()` RPC
7. **UI Update:** Calendar refreshes and displays the new block-out date(s)

**Key Limitation:** Every operation is scoped to the active band. There is no cross-band propagation.

### Multi-Band Membership

- Users can belong to multiple bands via the `band_members` table
- Active band is managed by `ActiveBandNotifier` in `active_band_controller.dart`
- State includes `List<Band> userBands` and `Band? activeBand`
- Band switching is common — users frequently switch between bands via `BandSwitcherOverlay`

### Settings Architecture

- `SettingsScreen` is the main settings entry point
- Currently contains:
  - Notifications (links to `NotificationSettingsScreen`)
  - Light mode toggle
  - Delete Account
- Notification preferences are per-user, stored in `notification_preferences` table
- Settings items are extensible via `SettingsItem` model

---

## Proposed Solution

### Overview

Add a **user-level calendar preferences system** that allows users to:

1. Enable "One Calendar" mode (visible only if user belongs to 2+ bands)
2. Choose whether block-out dates apply to "All bands" or "Selected bands only"
3. Enable automatic conflict blocking (gigs/rehearsals in one band automatically block dates in other bands)

When a user creates or edits a block-out date, the system will check their One Calendar preferences and propagate the block-out date to the appropriate bands.

### Database Changes

Create a new table to store user-level calendar preferences:

```sql
CREATE TABLE user_calendar_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  one_calendar_enabled BOOLEAN NOT NULL DEFAULT false,
  apply_to_mode TEXT NOT NULL DEFAULT 'all_bands' CHECK (apply_to_mode IN ('all_bands', 'selected_bands')),
  selected_band_ids UUID[] DEFAULT '{}',
  auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);
```

**RLS Policies:**

- Users can `SELECT`, `INSERT`, `UPDATE` their own preferences (filter by `user_id = auth.uid()`)
- Users cannot delete preferences (row should persist even if empty)

**RPC Functions:**

- `get_or_create_calendar_preferences(p_user_id UUID)` — Returns existing preferences or creates default row
- `update_calendar_preferences(...)` — Updates user's calendar preferences

**Triggers:**

- `update_updated_at_column()` on UPDATE (standard pattern)

### Flutter Architecture Changes

#### 1. New Model: `OneCalendarPreferences`

Path: `lib/features/calendar/models/one_calendar_preferences.dart`

```dart
enum ApplyToMode { allBands, selectedBands }

class OneCalendarPreferences {
  final String id;
  final String userId;
  final bool oneCalendarEnabled;
  final ApplyToMode applyToMode;
  final List<String> selectedBandIds;
  final bool autoBlockConflictsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  // fromJson, toJson, copyWith...
}
```

#### 2. New Repository: `OneCalendarPreferencesRepository`

Path: `lib/features/calendar/one_calendar_preferences_repository.dart`

**Methods:**

- `Future<OneCalendarPreferences> getPreferences(String userId)` — Fetches preferences, creates default if missing
- `Future<void> updatePreferences(OneCalendarPreferences prefs)` — Updates preferences via RPC
- `Future<List<String>> getBandIdsToApplyBlockOut(String userId, List<String> userBandIds)` — Returns list of band IDs where block-out dates should be created based on preferences

#### 3. New Controller: `OneCalendarPreferencesController`

Path: `lib/features/calendar/one_calendar_preferences_controller.dart`

Riverpod `Notifier<AsyncValue<OneCalendarPreferences>>` pattern (similar to `NotificationPreferencesController`)

**Methods:**

- `Future<void> toggleOneCalendar(bool enabled)`
- `Future<void> setApplyToMode(ApplyToMode mode)`
- `Future<void> updateSelectedBands(List<String> bandIds)`
- `Future<void> toggleAutoBlockConflicts(bool enabled)`

#### 4. New UI Screen: `OneCalendarSettingsScreen`

Path: `lib/features/calendar/one_calendar_settings_screen.dart`

**Layout:**

- App bar with "One Calendar" title
- Section 1: Master toggle — "One Calendar" (shown only if user belongs to 2+ bands)
- Section 2: Apply To (visible only when toggle is ON)
  - Radio button: "All bands"
  - Radio button: "Selected bands only"
  - If "Selected bands only", display multi-select list of user's bands
- Section 3: Automatic Conflict Blocking (visible only when toggle is ON)
  - Toggle: "Automatically block dates for other bands"
  - Description text

**Visibility Rule:**

- This entire screen is only accessible if the user belongs to 2+ bands
- If user belongs to only 1 band, the "One Calendar" settings item is hidden from the main Settings screen

#### 5. Modify `SettingsScreen`

Path: `lib/features/settings/settings_screen.dart`

**Changes:**

- Add new settings item: "One Calendar" (conditionally visible)
- Visibility: Only show if user belongs to 2+ bands
- Action: Navigate to `OneCalendarSettingsScreen`

**Implementation:**

```dart
// In _buildSettingsItems():
final bandCount = ref.watch(activeBandProvider).userBands.length;

if (bandCount >= 2) {
  regularItems.add(SettingsItem(
    icon: AppIcons.calendar,
    label: 'One Calendar',
    subtitle: 'Share block-out dates across bands',
    onTap: _openOneCalendarSettings,
  ));
}
```

#### 6. Modify `BlockOutDrawer` — Propagation Logic

Path: `lib/features/calendar/widgets/add_block_out_drawer.dart`

**Changes in `_handleSave()`:**

After creating the block-out date for the active band, check One Calendar preferences:

```dart
// After initial save to active band
final prefs = await ref.read(oneCalendarPreferencesRepositoryProvider)
    .getPreferences(userId);

if (prefs.oneCalendarEnabled) {
  final userBands = ref.read(activeBandProvider).userBands;
  final bandIds = await ref.read(oneCalendarPreferencesRepositoryProvider)
      .getBandIdsToApplyBlockOut(userId, userBands.map((b) => b.id).toList());

  // Remove current band (already created)
  final otherBandIds = bandIds.where((id) => id != widget.bandId).toList();

  // Create block-out dates for other bands
  final repository = ref.read(blockOutRepositoryProvider);
  for (final bandId in otherBandIds) {
    await repository.createBlockOut(
      bandId: bandId,
      userId: userId,
      startDate: _startDate,
      untilDate: _untilDate,
      reason: _reasonController.text.trim(),
    );
  }
}
```

**Edit Mode:**
When editing an existing block-out date, if One Calendar is enabled and the span was originally created via One Calendar propagation, update all bands. Otherwise, only update the current band.

**Delete Mode:**
When deleting a block-out date, if One Calendar is enabled, prompt user:

- "Delete from this band only"
- "Delete from all bands"

#### 7. Automatic Conflict Blocking Service

Path: `lib/features/calendar/auto_conflict_blocking_service.dart`

**Purpose:** When a gig or rehearsal is created/confirmed in one band, automatically create block-out dates on the user's other bands for the same date(s).

**Implementation:**

- Listen to gig/rehearsal creation events (via database triggers or client-side after save)
- Check user's One Calendar preferences: `autoBlockConflictsEnabled`
- If enabled, calculate the date(s) covered by the event
- Create block-out dates on other bands with reason: "Unavailable (scheduled with [Band Name])"

**Integration Point:**

- Call this service from `GigRepository.createGig()` and `RehearsalRepository.createRehearsal()` after successful save
- Alternatively, create a database trigger that fires after INSERT on `gigs` or `rehearsals` and calls an RPC function to propagate block-out dates

---

## Database Impact

**Affected:** Yes

### New Migration Required

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_user_calendar_preferences.sql`

**Contents:**

1. Create `user_calendar_preferences` table
2. Add RLS policies for user-only access
3. Create RPC function `get_or_create_calendar_preferences(p_user_id UUID)`
4. Create RPC function `update_calendar_preferences(...)`
5. Add `update_updated_at_column()` trigger

### RLS Policies

**user_calendar_preferences:**

- `SELECT`: `(user_id = auth.uid())`
- `INSERT`: `(user_id = auth.uid())`
- `UPDATE`: `(user_id = auth.uid())`
- `DELETE`: Not allowed (preferences persist)

### RPC Functions

**New RPCs:**

- `get_or_create_calendar_preferences(p_user_id UUID)` — SECURITY INVOKER
- `update_calendar_preferences(p_user_id UUID, p_one_calendar_enabled BOOLEAN, p_apply_to_mode TEXT, p_selected_band_ids UUID[], p_auto_block_conflicts_enabled BOOLEAN)` — SECURITY INVOKER

**Existing RPCs:**

- No changes to existing RPCs

### Triggers

**New Triggers:**

- `user_calendar_preferences`: `update_updated_at_column()` trigger (standard pattern)

**Existing Triggers:**

- No changes to existing triggers

---

## Files to Create

| File                                                                   | Justification                                                 |
| ---------------------------------------------------------------------- | ------------------------------------------------------------- |
| `supabase/migrations/YYYYMMDDHHMMSS_add_user_calendar_preferences.sql` | Database schema for user calendar preferences                 |
| `lib/features/calendar/models/one_calendar_preferences.dart`           | Data model for user calendar preferences                      |
| `lib/features/calendar/one_calendar_preferences_repository.dart`       | Repository for fetching/updating calendar preferences         |
| `lib/features/calendar/one_calendar_preferences_controller.dart`       | Riverpod state management for calendar preferences            |
| `lib/features/calendar/one_calendar_settings_screen.dart`              | UI screen for One Calendar settings                           |
| `lib/features/calendar/auto_conflict_blocking_service.dart`            | Service to automatically block conflicting dates across bands |

---

## Files to Modify

| File                                                      | What Changes                                                                                         |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `lib/features/settings/settings_screen.dart`              | Add "One Calendar" settings item (conditional: only if user has 2+ bands)                            |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Add cross-band propagation logic in `_handleSave()` and `_handleDelete()`                            |
| `lib/features/calendar/block_out_repository.dart`         | Add helper method `getBandIdsForPropagation()` (optional — may be in preferences repository instead) |
| `lib/features/gigs/gig_repository.dart`                   | Integrate auto-conflict blocking service after gig creation                                          |
| `lib/features/rehearsals/rehearsal_repository.dart`       | Integrate auto-conflict blocking service after rehearsal creation                                    |

---

## Files Off-Limits

| File                                       | Reason                                                      |
| ------------------------------------------ | ----------------------------------------------------------- |
| `lib/main.dart`                            | Init order must not change                                  |
| `lib/app/services/supabase_client.dart`    | No config changes                                           |
| `supabase/migrations/*_notification_*.sql` | Existing notification system migrations must not be altered |
| `lib/features/auth/*.dart`                 | Auth flow unrelated to calendar preferences                 |
| `lib/features/setlists/*.dart`             | Setlists unrelated to calendar preferences                  |

---

## System Impact Map

| System                                 | Impact                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------ |
| Gigs                                   | **affected** — auto-conflict blocking integrates with gig creation       |
| Rehearsals                             | **affected** — auto-conflict blocking integrates with rehearsal creation |
| Setlists / Catalog                     | **unaffected**                                                           |
| Members / RBAC                         | **unaffected** — permissions do not change                               |
| Auth / Session                         | **unaffected**                                                           |
| Routing                                | **affected** — new route for `OneCalendarSettingsScreen`                 |
| Notifications                          | **unaffected** — no changes to notification preferences or delivery      |
| Platform (iOS / Android / Web / macOS) | **unaffected** — all platforms supported equally                         |
| Calendar                               | **affected** — core feature                                              |
| Settings                               | **affected** — new settings screen and conditional menu item             |

---

## Regression Risk

**Overall Risk:** `MEDIUM`

**Rationale:**

- **New table and preferences:** Low risk — isolated to new code paths
- **Block-out propagation:** Medium risk — modifies existing `BlockOutDrawer` save logic, could introduce bugs if preferences are not fetched correctly
- **Auto-conflict blocking:** Medium risk — adds new side effect to gig/rehearsal creation, must not fail or block the primary operation
- **Conditional UI visibility:** Low risk — settings item visibility is straightforward logic
- **Multi-band users only:** Reduces blast radius — single-band users are unaffected

**Mitigation:**

- Feature is opt-in (default: One Calendar disabled)
- Single-band users never see the feature
- Block-out propagation is additive — does not modify existing block-out creation logic for current band
- Auto-conflict blocking should be non-blocking (run async, log errors but do not fail gig/rehearsal creation)

---

## Engineer Task Breakdown

### Phase 1: Database Migration

**Task 1.1:** Create migration file `supabase/migrations/YYYYMMDDHHMMSS_add_user_calendar_preferences.sql`

- Create `user_calendar_preferences` table
- Add RLS policies
- Create RPC functions: `get_or_create_calendar_preferences`, `update_calendar_preferences`
- Add `update_updated_at_column()` trigger

**Task 1.2:** Deploy migration

- Run `supabase db push` (local dev)
- Test RPCs work correctly

---

### Phase 2: Flutter Data Layer

**Task 2.1:** Create `lib/features/calendar/models/one_calendar_preferences.dart`

- Define `ApplyToMode` enum
- Define `OneCalendarPreferences` class with `fromJson`, `toJson`, `copyWith`

**Task 2.2:** Create `lib/features/calendar/one_calendar_preferences_repository.dart`

- Implement `getPreferences(userId)` — calls RPC, returns `OneCalendarPreferences`
- Implement `updatePreferences(prefs)` — calls RPC
- Implement `getBandIdsToApplyBlockOut(userId, userBandIds)` — applies logic based on preferences

**Task 2.3:** Create `lib/features/calendar/one_calendar_preferences_controller.dart`

- Riverpod `Notifier<AsyncValue<OneCalendarPreferences>>`
- Methods: `toggleOneCalendar`, `setApplyToMode`, `updateSelectedBands`, `toggleAutoBlockConflicts`

---

### Phase 3: Settings UI

**Task 3.1:** Create `lib/features/calendar/one_calendar_settings_screen.dart`

- App bar
- Master toggle: "One Calendar"
- Apply To section (radio buttons + band picker)
- Auto-conflict blocking toggle
- Subtext and descriptions

**Task 3.2:** Modify `lib/features/settings/settings_screen.dart`

- Add "One Calendar" settings item
- Conditional visibility: only if user belongs to 2+ bands
- Navigate to `OneCalendarSettingsScreen` on tap

---

### Phase 4: Block-Out Propagation

**Task 4.1:** Modify `lib/features/calendar/widgets/add_block_out_drawer.dart`

- In `_handleSave()`: After saving to active band, check One Calendar preferences
- If enabled, call `getBandIdsToApplyBlockOut()` and create block-out dates for other bands
- Handle errors gracefully (show snackbar, but do not block primary save)

**Task 4.2:** Modify `_handleDelete()` in `BlockOutDrawer`

- If One Calendar is enabled, prompt user: "Delete from this band only" or "Delete from all bands"
- If "all bands", delete from all bands in the propagation list

---

### Phase 5: Auto-Conflict Blocking (Optional — Can be in future phase)

**Task 5.1:** Create `lib/features/calendar/auto_conflict_blocking_service.dart`

- Method: `autoBlockConflictingDate(userId, bandId, eventDate, eventName, bandName)`
- Logic: Check One Calendar preferences, create block-out dates on other bands

**Task 5.2:** Integrate into gig creation

- Modify `lib/features/gigs/gig_repository.dart`
- After successful gig creation, call auto-conflict service if `autoBlockConflictsEnabled`

**Task 5.3:** Integrate into rehearsal creation

- Modify `lib/features/rehearsals/rehearsal_repository.dart`
- After successful rehearsal creation, call auto-conflict service if `autoBlockConflictsEnabled`

---

## Verification Plan

### Tier 1 — Pre-Deployment (Before `supabase db push`)

Not applicable — no existing functions are being replaced. All changes are additive.

---

### Tier 2 — Post-Deployment (After `supabase db push`)

**POST-DEPLOY TEST 1: Verify table and RLS policies exist**

```sql
-- Verify table exists
SELECT COUNT(*) FROM user_calendar_preferences;
-- Expected: 0 (no rows yet)

-- Verify RLS is enabled
SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'user_calendar_preferences';
-- Expected: relrowsecurity = true

-- Verify policies exist
SELECT policyname FROM pg_policies WHERE tablename = 'user_calendar_preferences';
-- Expected: SELECT, INSERT, UPDATE policies for user_id = auth.uid()
```

**POST-DEPLOY TEST 2: Test RPC — get_or_create_calendar_preferences**

```sql
-- Test RPC creates default preferences
SELECT * FROM get_or_create_calendar_preferences(auth.uid());
-- Expected: Row returned with default values (one_calendar_enabled = false, apply_to_mode = 'all_bands', etc.)

-- Verify row was inserted
SELECT * FROM user_calendar_preferences WHERE user_id = auth.uid();
-- Expected: 1 row
```

**POST-DEPLOY TEST 3: Test RPC — update_calendar_preferences**

```sql
-- Update preferences
SELECT update_calendar_preferences(
  p_user_id := auth.uid(),
  p_one_calendar_enabled := true,
  p_apply_to_mode := 'selected_bands',
  p_selected_band_ids := ARRAY['00000000-0000-0000-0000-000000000001'::UUID],
  p_auto_block_conflicts_enabled := true
);

-- Verify update
SELECT one_calendar_enabled, apply_to_mode, selected_band_ids, auto_block_conflicts_enabled
FROM user_calendar_preferences
WHERE user_id = auth.uid();
-- Expected: one_calendar_enabled = true, apply_to_mode = 'selected_bands', selected_band_ids contains the UUID, auto_block_conflicts_enabled = true
```

**POST-DEPLOY TEST 4: Verify trigger updates updated_at**

```sql
-- Note the current updated_at
SELECT updated_at FROM user_calendar_preferences WHERE user_id = auth.uid();

-- Wait 2 seconds, then update
SELECT pg_sleep(2);
SELECT update_calendar_preferences(
  p_user_id := auth.uid(),
  p_one_calendar_enabled := false,
  p_apply_to_mode := 'all_bands',
  p_selected_band_ids := '{}',
  p_auto_block_conflicts_enabled := false
);

-- Verify updated_at changed
SELECT updated_at FROM user_calendar_preferences WHERE user_id = auth.uid();
-- Expected: updated_at is at least 2 seconds later than the first query
```

---

### Flutter Integration Tests

**TEST 1: Settings item visibility**

- User with 1 band: "One Calendar" settings item is hidden
- User with 2+ bands: "One Calendar" settings item is visible

**TEST 2: One Calendar toggle**

- Toggle "One Calendar" ON → preferences saved, UI updates
- Toggle OFF → preferences saved, UI hides sub-options

**TEST 3: Apply To mode**

- Select "All bands" → preferences saved, band picker hidden
- Select "Selected bands only" → preferences saved, band picker visible
- Select bands from picker → preferences saved with correct band IDs

**TEST 4: Block-out propagation**

- Enable One Calendar, set "All bands"
- Create block-out date for Band A
- Verify block-out date appears on Band B, Band C calendars

**TEST 5: Block-out propagation (selected bands only)**

- Enable One Calendar, set "Selected bands only", select Band B
- Create block-out date for Band A
- Verify block-out date appears on Band B calendar only, not Band C

**TEST 6: Auto-conflict blocking**

- Enable auto-conflict blocking
- Create gig in Band A for date X
- Verify block-out date appears on Band B, Band C calendars for date X with reason "Unavailable (scheduled with Band A)"

**TEST 7: Delete block-out (One Calendar enabled)**

- Enable One Calendar, create block-out date for all bands
- Delete block-out date from Band A
- Prompt appears: "Delete from this band only" or "Delete from all bands"
- Select "Delete from all bands" → verify deleted from all bands

---

## QA Regression Areas

**Primary:**

1. **One Calendar settings visibility** — Verify only shown for users with 2+ bands
2. **Block-out propagation** — Verify block-out dates are correctly propagated to selected bands
3. **Auto-conflict blocking** — Verify gigs/rehearsals create block-out dates on other bands when enabled
4. **Settings UI** — Verify all toggles, radio buttons, and band picker work correctly
5. **Single-band users** — Verify no changes visible or functional for users with only 1 band

**Regression:**

1. **Existing block-out creation** — Verify block-out dates can still be created normally when One Calendar is disabled
2. **Block-out editing** — Verify existing block-out dates can be edited without issues
3. **Block-out deletion** — Verify existing block-out dates can be deleted without issues
4. **Calendar display** — Verify calendar still displays all events correctly
5. **Notifications** — Verify block-out notifications still fire correctly for band members
6. **Multi-band switching** — Verify switching bands still works correctly
7. **Settings screen** — Verify existing settings items (Notifications, Light mode, Delete Account) still work

---

## Rollout / Migration Strategy

**Phase 1: Database Migration**

- Deploy migration to production
- No user-facing changes yet

**Phase 2: Flutter Rollout**

- Deploy Flutter changes (web first, then mobile)
- Feature is opt-in (default: disabled)
- Users with 2+ bands will see the new "One Calendar" settings item
- Single-band users see no changes

**Phase 3: Monitor**

- Monitor error logs for issues with block-out propagation
- Monitor Supabase query performance for `user_calendar_preferences` table
- Gather user feedback

**Rollback Plan:**

- If critical issues arise, disable the feature by hiding the settings item (no database changes required)
- Database table can remain in place (no data loss)

---

## Out of Scope

**Explicitly not included in this feature:**

1. **External calendar sync** — No integration with Google Calendar, iCal, or other external calendars
2. **Admin controls** — Band admins cannot see or control other users' One Calendar settings (this is a personal preference)
3. **Calendar feed changes** — iCal calendar feed subscriptions are unaffected by this feature
4. **Bulk editing** — No UI for bulk editing multiple block-out dates at once
5. **Conflict resolution UI** — No visual conflict indicators or resolution flow (future enhancement)
6. **Time-based blocking** — Auto-conflict blocking only blocks the date, not specific times (future enhancement)
7. **Historical propagation** — Existing block-out dates are not retroactively propagated when One Calendar is enabled

---

**End of ARCHITECT_PLAN.md**
