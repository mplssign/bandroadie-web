# ARCHITECT_PLAN.md — Event Created Notification Missing

## Feature Slug

`bug/event-created-notification-missing`

## Problem Summary

Users do not receive push notifications when band members create events (gigs, rehearsals, block-outs), despite having notifications fully enabled at both the app level (in-app settings toggle ON, all event categories checked) and system level (iOS Settings → BandRoadie → Allow Notifications ON).

**Why this happens**: The notification system creates notification records and sends FCM pushes for ALL band members without checking whether each recipient has notifications enabled or the specific event category enabled in their preferences.

## Root Cause

**Confidence Level: HIGH** (confirmed through direct code inspection)

The `notify_band_members()` database function (defined in migration `20260220120000_secure_push_notification_trigger.sql`, lines 172-213) blindly inserts notification records for all band members except the actor, without checking user notification preferences.

**Failure Chain:**

1. User creates event → database trigger fires
2. Trigger calls `notify_band_members(band_id, actor_id, type, title, body, metadata)`
3. `notify_band_members()` loops through ALL band members: `SELECT user_id FROM band_members WHERE band_id = p_band_id AND user_id != p_actor_user_id`
4. For each member, it INSERTs a row in `notifications` table **without checking preferences**
5. AFTER INSERT trigger on `notifications` fires → calls `send-push` Edge Function via `pg_net.http_post`
6. `send-push` Edge Function fetches FCM tokens and sends push **without checking preferences**
7. User receives unwanted push notification

**The Missing Link:**
The `should_receive_notification(user_id UUID, notification_type TEXT) RETURNS BOOLEAN` helper function exists (created in migration `20260128205900_notification_categories.sql`) and correctly checks:

- `notification_preferences.notifications_enabled` (master toggle)
- Category-specific toggles (`gigs_enabled`, `potential_gigs_enabled`, `rehearsals_enabled`, `blockouts_enabled`)

**But this function is never called** in the notification delivery pipeline.

## Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md` — Explains app-level vs system-level permissions
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` — Describes intended architecture (webhook-based delivery)
- `docs/reference/notifications/notifications.md` — Describes alternative architecture (pg_cron polling)

**Discrepancy Found:** The reference docs state that the system "checks user preferences (master toggle + category)" before creating notifications, but the implemented code does not do this.

## Existing System Analysis

### Current Notification Flow

```
User creates gig/rehearsal/block-out
        ↓
Database trigger fires:
  - notify_gig_created()
  - notify_rehearsal_created()
  - notify_blockout_created()
        ↓
Trigger function calls:
  notify_band_members(band_id, actor_id, type, title, body, metadata)
        ↓
notify_band_members() loops:
  FOR v_member IN SELECT user_id FROM band_members WHERE band_id = X AND user_id != actor
    → INSERT INTO notifications (...) — NO PREFERENCE CHECK HERE
        ↓
AFTER INSERT trigger on notifications table fires:
  trigger_send_push_notification()
        ↓
pg_net.http_post() calls send-push Edge Function
        ↓
send-push fetches device_tokens and sends FCM push — NO PREFERENCE CHECK HERE
        ↓
User receives push (even if they have notifications disabled)
```

### Notification Preferences Schema

**Table:** `notification_preferences`

| Column                   | Type    | Default | Description                 |
| ------------------------ | ------- | ------- | --------------------------- |
| `notifications_enabled`  | BOOLEAN | `true`  | Master toggle               |
| `gigs_enabled`           | BOOLEAN | `true`  | Confirmed gig notifications |
| `potential_gigs_enabled` | BOOLEAN | `true`  | Potential gig notifications |
| `rehearsals_enabled`     | BOOLEAN | `true`  | Rehearsal notifications     |
| `blockouts_enabled`      | BOOLEAN | `true`  | Block-out notifications     |

### Existing Helper Function

```sql
CREATE OR REPLACE FUNCTION should_receive_notification(
  p_user_id UUID,
  p_notification_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_prefs notification_preferences;
  v_should_receive BOOLEAN := false;
BEGIN
  SELECT * INTO v_prefs FROM notification_preferences WHERE user_id = p_user_id;

  IF v_prefs IS NULL OR NOT v_prefs.notifications_enabled THEN
    RETURN false;
  END IF;

  CASE p_notification_type
    WHEN 'gig_created', 'gig_confirmed' THEN
      v_should_receive := v_prefs.gigs_enabled;
    WHEN 'potential_gig_created' THEN
      v_should_receive := v_prefs.potential_gigs_enabled;
    WHEN 'rehearsal_created' THEN
      v_should_receive := v_prefs.rehearsals_enabled;
    WHEN 'blockout_created' THEN
      v_should_receive := v_prefs.blockouts_enabled;
    ELSE
      v_should_receive := true;
  END CASE;

  RETURN v_should_receive;
END;
$$;
```

**Location:** 20260128205900_notification_categories.sql (lines 49-86)

**Status:** ✅ Exists and works correctly, but ❌ is never called

## Proposed Solution

**Minimal Fix:** Modify `notify_band_members()` to call `should_receive_notification()` BEFORE inserting each notification record.

**Why at this layer:**

- Prevents unnecessary database writes for users who don't want notifications
- Reduces processing overhead (no trigger fired, no edge function called, no FCM request)
- Maintains single source of truth for preference logic (the existing helper function)
- Follows reference architecture documented in NOTIFICATION_SYSTEM.md

**Alternative (rejected):** Check preferences in `send-push` Edge Function

- ❌ Still creates notification records users don't want → database bloat
- ❌ Still fires triggers and calls edge functions unnecessarily → wasted processing
- ❌ Duplicates preference-checking logic across SQL and TypeScript
- ❌ Harder to test and maintain

### Updated notify_band_members() Function

```sql
CREATE OR REPLACE FUNCTION notify_band_members(
  p_band_id UUID,
  p_actor_user_id UUID,
  p_notification_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
BEGIN
  FOR v_member IN
    SELECT user_id
      FROM band_members
     WHERE band_id = p_band_id
       AND user_id != COALESCE(p_actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    -- ✅ NEW: Check if user wants this notification type
    IF should_receive_notification(v_member.user_id, p_notification_type) THEN
      BEGIN
        INSERT INTO notifications (
          band_id,
          recipient_user_id,
          type,
          title,
          body,
          metadata,
          actor_user_id
        ) VALUES (
          p_band_id,
          v_member.user_id,
          p_notification_type,
          COALESCE(p_title, 'New Activity'),
          COALESCE(p_body, 'Something happened in your band'),
          COALESCE(p_metadata, '{}'::jsonb),
          p_actor_user_id
        );
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_band_members: failed for user %: %',
            v_member.user_id, SQLERRM;
      END;
    END IF;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_band_members failed entirely: %', SQLERRM;
END;
$$;
```

**Key Change:** Added conditional `IF should_receive_notification(v_member.user_id, p_notification_type) THEN` before INSERT.

## Database Impact

### Migration Required: YES

**New Migration:** `supabase/migrations/20260408000000_fix_notification_preferences_check.sql`

**Changes:**

1. Update `notify_band_members()` function to check `should_receive_notification()` before inserting

**No changes to:**

- Table schemas (all tables already exist)
- RLS policies (no policy changes needed)
- Indexes (existing indexes sufficient)
- Triggers (trigger definitions unchanged, only the function they call is modified)

**RLS Consideration:** No infinite recursion risk. The `should_receive_notification()` function:

- Uses `STABLE` (not `SECURITY DEFINER`)
- Only reads from `notification_preferences` (no writes)
- No self-referencing queries

## Flutter Architecture Changes

**Files Affected:** NONE

**Reasoning:** This is a pure backend fix. The bug is in the database function, not the Flutter app. The Flutter notification preference UI already works correctly — it saves preferences to the database, but the database was ignoring them when creating notifications.

**Verification:** No Flutter code changes required. After deploying the migration, the existing Flutter UI will work as expected.

## Files to Create

**1. New Migration File**

**Path:** `supabase/migrations/20260408000000_fix_notification_preferences_check.sql`

**Purpose:** Update `notify_band_members()` to check user preferences before inserting notification records

**Justification:** This is a bug fix migration. Per project conventions, notification-related migrations follow the `YYYYMMDD` naming pattern. This migration modifies an existing function to add the missing preference check.

## Files to Modify

| File                                                                        | What Changes                                                                                                            |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260408000000_fix_notification_preferences_check.sql` | **CREATE (not modify)** — New migration that replaces `notify_band_members()` function with preference-checking version |

**That's it.** No other files require modification.

## Files Off-Limits

| File                                                            | Reason                                                                                                                |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| main.dart                                                       | Initialization order must not change (GUARDRAILS.md §1)                                                               |
| notification_settings_screen.dart                               | Settings UI already works correctly — bug is backend-only                                                             |
| notification_preferences_controller.dart                        | Preference saving already works — bug is in notification creation, not preference storage                             |
| push_notification_service.dart                                  | FCM token management unrelated to this bug                                                                            |
| index.ts                                                        | Edge function correctly sends to device tokens — preference check must happen before notification records are created |
| 20260220120000_secure_push_notification_trigger.sql             | Do NOT modify old migrations — create new migration that replaces the function                                        |
| 20260220130000_fix_notification_triggers_exception_handling.sql | Do NOT modify old migrations                                                                                          |

**Why no Flutter changes:** The user-facing notification settings already save preferences correctly to `notification_preferences` table. The bug is that the backend ignores these saved preferences when creating notifications.

## System Impact Map

| System                                 | Impact         | Explanation                                                             |
| -------------------------------------- | -------------- | ----------------------------------------------------------------------- |
| Gigs                                   | **affected**   | Gig creation triggers check `gigs_enabled` and `potential_gigs_enabled` |
| Rehearsals                             | **affected**   | Rehearsal creation triggers check `rehearsals_enabled`                  |
| Setlists / Catalog                     | **unaffected** | No notification triggers attached to setlist operations                 |
| Members / RBAC                         | **unaffected** | Member join/leave notifications not yet implemented                     |
| Auth / Session                         | **unaffected** | No changes to authentication or session management                      |
| Routing                                | **unaffected** | No changes to navigation or deep linking                                |
| Notifications                          | **affected**   | Core fix — notification creation now respects user preferences          |
| Platform (iOS / Android / Web / macOS) | **unaffected** | Backend-only change, no platform-specific code modified                 |

## Regression Risk

**Overall Risk: LOW**

**Rationale:**

1. **Change is localized**: Only modifies one database function (`notify_band_members()`)
2. **Change is additive**: Adds a conditional check before INSERT — does not remove or restructure existing logic
3. **Change is defensive**: Maintains existing exception handling that prevents notification failures from blocking event creation
4. **Safe pattern**: Uses existing, tested helper function (`should_receive_notification()`)
5. **No client changes**: Flutter app behavior unchanged — users will simply stop receiving unwanted notifications

**Why LOW not ZERO:**

- Notification creation behavior changes (by design — that's the fix)
- If `should_receive_notification()` has bugs, those bugs are now exposed (but function already tested via other queries)
- Performance impact: adds one function call + one SELECT per band member per event (negligible — typical bands have 3-8 members)

**Mitigation:**

- Add explicit error handling around `should_receive_notification()` (already present in outer EXCEPTION block)
- Test with band members who have:
  - All notifications enabled (should work as before)
  - All notifications disabled (should stop receiving any)
  - Mixed category settings (should receive only enabled categories)

## Engineer Task Breakdown

### Prerequisites

1. Verify `should_receive_notification()` function exists:

   ```sql
   SELECT routine_name FROM information_schema.routines
   WHERE routine_schema = 'public'
   AND routine_name = 'should_receive_notification';
   ```

   Expected: 1 row returned

2. Verify `notification_preferences` table has required columns:
   ```sql
   SELECT column_name FROM information_schema.columns
   WHERE table_name = 'notification_preferences'
   AND column_name IN ('notifications_enabled', 'gigs_enabled', 'potential_gigs_enabled', 'rehearsals_enabled', 'blockouts_enabled');
   ```
   Expected: 5 rows returned

### Task 1: Create Migration File

- Create `supabase/migrations/20260408000000_fix_notification_preferences_check.sql`
- Add migration header:
  ```sql
  -- ============================================================================
  -- FIX: Respect user notification preferences when creating notifications
  -- Created: 2026-04-08
  -- Purpose: Modify notify_band_members() to check should_receive_notification()
  --          before inserting notification records
  -- Bug: bug/event-created-notification-missing
  -- ============================================================================
  ```
- Copy the updated `notify_band_members()` function from "Proposed Solution" section

### Task 2: Test Migration Locally

- Run migration against local Supabase instance
- Verify function replaced successfully:
  ```sql
  SELECT pg_get_functiondef('notify_band_members(uuid,uuid,text,text,text,jsonb)'::regprocedure);
  ```
- Confirm output contains `IF should_receive_notification(...) THEN`

### Task 3: Integration Testing

**Test Scenario A: All notifications enabled**

```sql
-- Setup
UPDATE notification_preferences
SET notifications_enabled = true, gigs_enabled = true, rehearsals_enabled = true, blockouts_enabled = true
WHERE user_id = '<test_user_id>';

-- Create gig as another band member
-- (via app UI or direct INSERT)

-- Verify notification created
SELECT * FROM notifications
WHERE recipient_user_id = '<test_user_id>'
ORDER BY created_at DESC LIMIT 1;
-- Expected: 1 row with type = 'gig_created' or 'potential_gig_created'
```

**Test Scenario B: Master toggle disabled**

```sql
-- Setup
UPDATE notification_preferences
SET notifications_enabled = false
WHERE user_id = '<test_user_id>';

-- Create gig as another band member

-- Verify NO notification created
SELECT COUNT(*) FROM notifications
WHERE recipient_user_id = '<test_user_id>'
AND created_at > now() - interval '1 minute';
-- Expected: 0
```

**Test Scenario C: Category-specific disabled**

```sql
-- Setup
UPDATE notification_preferences
SET notifications_enabled = true, gigs_enabled = false, rehearsals_enabled = true
WHERE user_id = '<test_user_id>';

-- Create gig → Expected: NO notification
-- Create rehearsal → Expected: notification created

-- Verify
SELECT COUNT(*) FROM notifications
WHERE recipient_user_id = '<test_user_id>'
AND type IN ('gig_created', 'potential_gig_created')
AND created_at > now() - interval '5 minutes';
-- Expected: 0 (gig blocked)

SELECT COUNT(*) FROM notifications
WHERE recipient_user_id = '<test_user_id>'
AND type = 'rehearsal_created'
AND created_at > now() - interval '5 minutes';
-- Expected: 1 (rehearsal allowed)
```

**Test Scenario D: Event creation never fails**

```sql
-- Temporarily break should_receive_notification to verify exception handling
CREATE OR REPLACE FUNCTION should_receive_notification(p_user_id UUID, p_notification_type TEXT)
RETURNS BOOLEAN AS $$
  SELECT nonexistent_column FROM notification_preferences WHERE user_id = p_user_id;
$$ LANGUAGE sql;

-- Create gig → should succeed despite notification error
-- Check PostgreSQL logs for WARNING

-- Restore correct function
-- (re-run migration)
```

### Task 4: Deploy Migration

```bash
# Apply to production
supabase db push --project-ref nekwjxvgbveheooyorjo

# Verify deployment
supabase db remote commit --project-ref nekwjxvgbveheooyorjo
```

### Task 5: Monitor Edge Function Logs

```bash
# Monitor for 48 hours post-deployment
supabase functions logs send-push --project-ref nekwjxvgbveheooyorjo
```

Expected:

- ✅ Fewer invocations (only for enabled notifications)
- ✅ No increase in error rates
- ✅ FCM send success rate unchanged

## Verification Plan

### Automated Tests (SQL)

Run in Supabase SQL Editor before deploying:

```sql
-- Test 1: Enabled notifications → should receive
DO $$
DECLARE
  v_test_user UUID := gen_random_uuid();
  v_test_band UUID := gen_random_uuid();
  v_count INT;
BEGIN
  INSERT INTO notification_preferences (user_id, notifications_enabled, gigs_enabled)
  VALUES (v_test_user, true, true);

  PERFORM notify_band_members(v_test_band, 'actor', 'gig_created', 'Test', 'Body', '{}'::jsonb);

  SELECT COUNT(*) INTO v_count FROM notifications WHERE recipient_user_id = v_test_user;
  IF v_count != 1 THEN
    RAISE EXCEPTION 'Test 1 failed: expected 1, got %', v_count;
  END IF;

  DELETE FROM notifications WHERE recipient_user_id = v_test_user;
  DELETE FROM notification_preferences WHERE user_id = v_test_user;
  RAISE NOTICE 'Test 1 passed';
END $$;

-- Test 2: Disabled notifications → should NOT receive
DO $$
DECLARE
  v_test_user UUID := gen_random_uuid();
  v_test_band UUID := gen_random_uuid();
  v_count INT;
BEGIN
  INSERT INTO notification_preferences (user_id, notifications_enabled)
  VALUES (v_test_user, false);

  PERFORM notify_band_members(v_test_band, 'actor', 'gig_created', 'Test', 'Body', '{}'::jsonb);

  SELECT COUNT(*) INTO v_count FROM notifications WHERE recipient_user_id = v_test_user;
  IF v_count != 0 THEN
    RAISE EXCEPTION 'Test 2 failed: expected 0, got %', v_count;
  END IF;

  DELETE FROM notification_preferences WHERE user_id = v_test_user;
  RAISE NOTICE 'Test 2 passed';
END $$;

-- Test 3: Category disabled → should NOT receive
DO $$
DECLARE
  v_test_user UUID := gen_random_uuid();
  v_test_band UUID := gen_random_uuid();
  v_count INT;
BEGIN
  INSERT INTO notification_preferences (user_id, notifications_enabled, gigs_enabled)
  VALUES (v_test_user, true, false);

  PERFORM notify_band_members(v_test_band, 'actor', 'gig_created', 'Test', 'Body', '{}'::jsonb);

  SELECT COUNT(*) INTO v_count FROM notifications WHERE recipient_user_id = v_test_user;
  IF v_count != 0 THEN
    RAISE EXCEPTION 'Test 3 failed: expected 0, got %', v_count;
  END IF;

  DELETE FROM notification_preferences WHERE user_id = v_test_user;
  RAISE NOTICE 'Test 3 passed';
END $$;
```

### Manual Tests (iOS)

**Prerequisites:**

- Two iOS devices with BandRoadie installed
- Both logged in to separate accounts in same band
- Device A = test recipient
- Device B = event creator

**Test 1: Master toggle OFF**

1. Device A: Settings → Notifications → Toggle OFF
2. Device B: Create new gig
3. Device A: **Expected: NO push notification**

**Test 2: Category disabled**

1. Device A: Settings → Notifications → Toggle ON, uncheck "Gigs", keep "Rehearsals" checked
2. Device B: Create gig
3. Device A: **Expected: NO push**
4. Device B: Create rehearsal
5. Device A: **Expected: Push received**

**Test 3: Re-enabling**

1. Device A: Settings → Notifications → Check "Gigs"
2. Device B: Create gig
3. Device A: **Expected: Push received**

### Production Monitoring

**1. Verify preferences respected (post-deploy):**

```sql
SELECT
  CASE
    WHEN np.notifications_enabled = false THEN 'Master Disabled'
    WHEN n.type = 'gig_created' AND np.gigs_enabled = false THEN 'Gig Disabled'
    WHEN n.type = 'rehearsal_created' AND np.rehearsals_enabled = false THEN 'Rehearsal Disabled'
    ELSE 'Should Exist'
  END as state,
  COUNT(*)
FROM notifications n
LEFT JOIN notification_preferences np ON n.recipient_user_id = np.user_id
WHERE n.created_at > now() - interval '1 hour'
GROUP BY state;
```

Expected: All in "Should Exist", none in "Disabled" buckets

**2. Check event creation success:**

```sql
SELECT
  'gigs' as type, COUNT(*) as created,
  (SELECT COUNT(*) FROM notifications WHERE type IN ('gig_created','potential_gig_created') AND created_at > now() - interval '24h') as notifs
FROM gigs WHERE created_at > now() - interval '24h'
UNION ALL
SELECT
  'rehearsals', COUNT(*),
  (SELECT COUNT(*) FROM notifications WHERE type = 'rehearsal_created' AND created_at > now() - interval '24h')
FROM rehearsals WHERE created_at > now() - interval '24h';
```

**3. PostgreSQL logs:**

```bash
supabase logs postgres --project-ref nekwjxvgbveheooyorjo | grep "notify_band_members"
```

Expected: No "failed entirely" warnings

**4. Edge function rate:**

```bash
supabase functions logs send-push | grep "Processing push notification" | wc -l
```

Expected: Fewer invocations than before

## QA Regression Areas

### Primary (Must Pass)

1. **Preference respect:**
   - Notifications disabled → NO push received
   - Category disabled → NO push for that category
   - All enabled → push received (no regression)

2. **Event creation never fails:**
   - Gig creation succeeds even if notification fails
   - Rehearsal creation succeeds even if notification fails
   - No user-facing errors

3. **All notification types:**
   - Confirmed gigs → check `gigs_enabled`
   - Potential gigs → check `potential_gigs_enabled`
   - Rehearsals → check `rehearsals_enabled`
   - Block-outs → check `blockouts_enabled`

### Secondary (Should Not Regress)

4. **Settings UI:**
   - Master toggle saves correctly
   - Category checkboxes save correctly
   - Preferences persist after restart

5. **System permissions:**
   - iOS permission denied → no push (system level)
   - iOS granted + app enabled → push delivered
   - iOS granted + app disabled → no push

6. **Push quality:**
   - Title/body format unchanged
   - Deep link metadata intact
   - Badge count accurate
   - Invalid token cleanup works

7. **Multi-user:**
   - Band with mixed preferences → only enabled users receive
   - All scenarios tested

8. **Performance:**
   - Event creation latency unchanged
   - No UI delays

### Edge Cases

9. **No preferences row:**
   - User never opened settings
   - Expected: No notification (no prefs = disabled)

10. **Unknown notification type:**
    - Expected: Default to enabled

11. **Single-member band:**
    - Expected: No notifications (actor excluded)

12. **RLS interaction:**
    - `SECURITY DEFINER` bypasses RLS
    - No permission errors

## Rollout / Migration Strategy

### Pre-Deployment

- [ ] Migration file created
- [ ] Tested locally (unit tests pass)
- [ ] Function includes preference check
- [ ] Exception handling preserved
- [ ] `SET search_path = public` present

### Deployment

1. **Deploy:**

   ```bash
   supabase db push --project-ref nekwjxvgbveheooyorjo
   ```

2. **Verify function replaced:**

   ```sql
   SELECT pg_get_functiondef('notify_band_members(uuid,uuid,text,text,text,jsonb)'::regprocedure);
   ```

3. **Monitor 30 minutes:**
   - PostgreSQL logs
   - send-push logs
   - Database dashboard

4. **Run verification query:**

   ```sql
   -- Should return 0 rows
   SELECT n.* FROM notifications n
   JOIN notification_preferences np ON n.recipient_user_id = np.user_id
   WHERE n.created_at > now() - interval '1h'
   AND (np.notifications_enabled = false
     OR (n.type IN ('gig_created','potential_gig_created') AND np.gigs_enabled = false)
     OR (n.type = 'rehearsal_created' AND np.rehearsals_enabled = false)
     OR (n.type = 'blockout_created' AND np.blockouts_enabled = false));
   ```

5. **Manual iOS test:**
   - Disable gig notifications
   - Create gig
   - Verify no push
   - Re-enable
   - Verify push received

### Rollback

If issues occur:

```sql
-- Restore previous version (without preference check)
CREATE OR REPLACE FUNCTION notify_band_members(
  p_band_id UUID,
  p_actor_user_id UUID,
  p_notification_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
BEGIN
  FOR v_member IN
    SELECT user_id FROM band_members
    WHERE band_id = p_band_id AND user_id != COALESCE(p_actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    BEGIN
      INSERT INTO notifications (band_id, recipient_user_id, type, title, body, metadata, actor_user_id)
      VALUES (p_band_id, v_member.user_id, p_notification_type, COALESCE(p_title, 'New Activity'),
              COALESCE(p_body, 'Something happened'), COALESCE(p_metadata, '{}'::jsonb), p_actor_user_id);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_band_members: failed for user %: %', v_member.user_id, SQLERRM;
    END;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_band_members failed entirely: %', SQLERRM;
END;
$$;
```

### Post-Deployment (48h)

**Monitor:**

1. Notification creation rate (should decrease)
2. Edge function invocations (should decrease)
3. Event creation success (should remain 100%)
4. User reports (should NOT increase "not receiving" complaints)

**Success Criteria:**

- ✅ No errors in notify_band_members
- ✅ Event creation 100% success
- ✅ Disabled preferences respected
- ✅ Enabled preferences work

## Out of Scope

Explicitly NOT addressed:

1. ❌ **System permission denial** — iOS/Android permissions take precedence; this only fixes app-level preferences
2. ❌ **FCM delivery failures** — Network/token issues outside this fix's scope
3. ❌ **In-app notification history** — Separate feature
4. ❌ **Additional notification categories** — Only 4 implemented (gigs, potential, rehearsals, blockouts)
5. ❌ **Retroactive cleanup** — Existing unwanted notifications remain in DB
6. ❌ **Quiet hours** — Not implemented
7. ❌ **Web/macOS push** — Only iOS/Android fully supported
8. ❌ **Edge function preference check** — Unnecessary since records not created
