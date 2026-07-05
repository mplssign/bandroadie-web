# Architect Plan — Notification Delivery Housekeeping

## Feature Slug

`bug/notification-delivery-housekeeping`

---

## Problem Summary

The notification delivery path has accumulated dead infrastructure and stale documentation that actively corrupts delivery bookkeeping and misleads debugging efforts. Production delivery works correctly via the Feb 2026 architecture (database trigger → pg_net → `send-push` Edge Function → FCM HTTP v1 API), confirmed end-to-end 2026-07-05. However:

1. **Zombie cron jobs**: Two duplicate pg_cron jobs (jobid 5 and 7) run every 5 minutes, invoking the legacy `deliver-notifications` Edge Function that uses the deprecated FCM API (`fcm.googleapis.com/fcm/send`) shut down by Google in June 2024.

2. **Fabricated bookkeeping**: Every send the zombie attempts fails (404 from FCM), yet it stamps `sent_at` on notification rows anyway. `sent_at` values at 5-minute marks are fiction, not delivery evidence. This cost hours of misdiagnosis during the 2026-07-05 iOS investigation.

3. **Uncommitted deployed source**: The `deliver-notifications` Edge Function was never committed to the repo. A downloaded copy sits untracked at `supabase/functions/deliver-notifications/`.

4. **Dead secret**: Legacy `FCM_SERVER_KEY` secret is still configured in Supabase Dashboard, unused by production.

5. **Backwards documentation**: `docs/agents/PROJECT_CONTEXT.md` states `deliver-notifications` is "current arch" and `send-push` is "older arch" — exactly backwards. Edge Functions table claims 11 functions; after cleanup it will be 10. Missing `rehearsal_dates` table from table list (exists since migration 20260519160119).

6. **Stale device tokens accumulate**: When an FCM token refreshes on a device (tokenA → tokenB), the app registers tokenB but doesn't clean up the old tokenA row. Both remain active until send-push tries the stale token and FCM returns UNREGISTERED. During this window, duplicate pushes are sent to the same device, inflating delivery counts and wasting FCM quota. Example: user zowize@gmail.com has 2 active `ios` rows in `device_tokens` — may be 2 physical devices (legitimate) or 1 device with a stale token (the bug).

---

## Root Cause

**Confidence: HIGH** — Directly observed in code and confirmed by production evidence.

### RC1: Zombie pg_cron jobs never decommissioned (jobid 5, 7)

When the notification architecture was migrated from pg_cron → deliver-notifications (Jan 2026) to database trigger → send-push (Feb 2026, migration `20260220120000_secure_push_notification_trigger.sql`), the old cron jobs were never unscheduled. They continue to invoke deliver-notifications every 5 minutes.

### RC2: Legacy `deliver-notifications` function still deployed

The Edge Function deployed at `https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/deliver-notifications` was never deleted after the Feb 2026 migration. It queries `WHERE sent_at IS NULL`, calls the deprecated FCM API, and stamps `sent_at` regardless of FCM outcome (line 159: `UPDATE notifications SET sent_at = now()`).

### RC3: `sent_at` is zombie-only bookkeeping

Grep confirms `sent_at` is ONLY read/written by `deliver-notifications/index.ts`. Production function `send-push` does not read or write it. Removing the zombie will leave `sent_at` NULL for all notifications — with zero semantic impact because nothing reads it.

### RC4: `upsert_device_token` RPC accumulates stale tokens

RPC definition (migration `20260109_notifications.sql` line 177):

```sql
ON CONFLICT (fcm_token)
DO UPDATE SET user_id = auth.uid(), platform = p_platform, ...
```

Upserts by token alone. When a token refreshes on a device (tokenA → tokenB), the app registers tokenB. The RPC:

- Looks for conflict on tokenB (doesn't find it)
- Inserts new row (user_id, tokenB, platform)
- Old row (user_id, tokenA, platform) remains active

Result: stale tokens accumulate per device. Send-push sends to all active tokens (including stale ones from the same device) until FCM returns UNREGISTERED, at which point send-push auto-deletes the stale token (line 291-296). But during the window between token refresh and first failed send, duplicate pushes to the same device occur.

**Note**: Multi-device same-platform (e.g., user with iPhone + iPad) is legitimate and MUST keep working — each physical device should maintain its own active token. The fix must scope deletion to the specific device (via old token), not platform-wide.

### RC5: Stale PROJECT_CONTEXT.md

Edge Functions table (line 253-270) lists:

- `send-push` as "webhook-triggered, older arch" (WRONG — it's current production)
- `deliver-notifications` as "pg_cron every 5 min (current arch)" (WRONG — it's the zombie)
- "All 11 deployed functions" (will be 10 after cleanup)

Database Tables section (line 136-189) omits `rehearsal_dates` (exists since migration 20260519160119).

---

## Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md` — Client permission flow, not directly relevant
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` (Feb 2026) — Documents current arch: webhook → send-push → FCM HTTP v1
- `docs/reference/notifications/notifications.md` (Jan 2026) — Documents OLD arch: pg_cron → deliver-notifications. Contains warning at top noting legacy FCM API deprecation.

---

## Existing System Analysis

### Current Production Flow (Feb 2026 → present)

```
1. User creates gig/rehearsal/blockout
       ↓
2. Database trigger (notify_band_members_on_*_insert) fires
       ↓
3. notify_band_members() inserts notification row
       ↓
4. AFTER INSERT trigger (on_notification_inserted) fires
       ↓
5. trigger_send_push_notification() calls pg_net.http_post
       ↓
6. send-push Edge Function receives webhook
       ↓
7. Validates X-Internal-Secret header (Vault: push_trigger_secret)
       ↓
8. Fetches device_tokens for recipient_user_id
       ↓
9. Generates OAuth2 access token from FIREBASE_SERVICE_ACCOUNT_KEY
       ↓
10. Sends FCM HTTP v1 API request per token
       ↓
11. Logs per-token success ("FCM sent to token f-O14...")
       ↓
12. Auto-deletes UNREGISTERED/INVALID_ARGUMENT tokens
```

This flow is **correct and working**. Evidence from 2026-07-05 function_logs shows per-token success logging.

### Zombie Parallel Flow (Jan 2026 → present, running but failing)

```
1. pg_cron job (jobid 5, 7) fires every 5 minutes
       ↓
2. Calls deliver-notifications Edge Function
       ↓
3. Queries: WHERE sent_at IS NULL LIMIT 100
       ↓
4. Reads FCM_SERVER_KEY from env
       ↓
5. POSTs to https://fcm.googleapis.com/fcm/send (legacy API)
       ↓
6. FCM returns 404 Not Found (API shut down June 2024)
       ↓
7. Stamps sent_at = now() anyway (line 159)
       ↓
8. Returns { success: true }
```

This flow is **actively harmful**: it fabricates `sent_at` timestamps for notifications that were never delivered via this path.

### Token Registration Flow (client-side)

```
1. App calls PushNotificationService.registerToken()
       ↓
2. Calls NotificationRepository.upsertDeviceToken(fcmToken, platform, deviceName)
       ↓
3. Calls RPC: upsert_device_token(p_fcm_token, p_platform, p_device_name)
       ↓
4. RPC: INSERT ... ON CONFLICT (fcm_token) DO UPDATE
       ↓
5. Returns token_id
```

**Gap**: If token refreshes (tokenA → tokenB), RPC inserts tokenB but does NOT delete tokenA. Stale tokenA remains in `device_tokens` until send-push tries to send to it and FCM returns UNREGISTERED.

**Mitigation in place**: send-push auto-deletes invalid tokens (line 291-296). This is a cleanup mechanism, but it's reactive, not proactive — during the window between token refresh and first failed send, duplicate pushes occur.

---

## Proposed Solution

### Part A: Repo Changes (committable)

**A1. Delete local untracked `deliver-notifications/` directory**

- Path: `supabase/functions/deliver-notifications/`
- Rationale: Never committed, never deployed from repo. Keeping it as "historical reference" has no value — the function is deployed remotely, and the repo already has git history of the Feb 2026 migration that replaced it.

**A2. Fix `upsert_device_token` RPC to accept optional old token for device-scoped cleanup**

- File: `supabase/migrations/20260109_notifications.sql` (modify via new migration)
- Change: Add optional `p_old_token TEXT DEFAULT NULL` parameter. When non-null, DELETE the row where `fcm_token = p_old_token AND user_id = auth.uid()` before upserting the new token. No platform-wide deletion.
- Rationale: Proactive cleanup of stale tokens from the SAME device (token refresh scenario) without breaking multi-device same-platform support (e.g., user with iPhone + iPad).
- Migration file: `supabase/migrations/YYYYMMDDHHMMSS_cleanup_stale_device_tokens.sql`

**A3. Update client to pass old token on registration**

- File: `lib/features/notifications/push_notification_service.dart`
- Change: Store last-registered token in SharedPreferences (key: `last_fcm_token`). On registration, if stored token exists and differs from current token, pass it as `oldToken` to repository. Update stored token after successful registration.
- Rationale: Enables device-scoped cleanup — each device tracks its own prior token.

**A4. Update repository to accept old token parameter**

- File: `lib/features/notifications/notification_repository.dart`
- Change: Add optional `String? oldToken` parameter to `upsertDeviceToken()`, pass to RPC as `p_old_token`.
- Rationale: Plumbing for client → RPC communication.

**Reinstall case**: If app is reinstalled (SharedPreferences wiped), the stale row remains until send-push's existing UNREGISTERED auto-cleanup handles it. This is the accepted fallback — no additional logic required.

**A5. Fix PROJECT_CONTEXT.md**

- Swap send-push / deliver-notifications descriptions in Edge Functions table
- Update function count: "All 11 deployed functions" → "All 10 deployed functions"
- Add `rehearsal_dates` to Database Tables section under Events category
- Justification: Authoritative project context must match reality

### Part B: Ops Runbook (manual execution by Tony)

Execute in this order:

**B1. Verify production delivery is working**

```sql
-- Check that notifications have been created recently
SELECT COUNT(*) FROM notifications WHERE created_at > now() - interval '24 hours';

-- Check that send-push Edge Function is logging successes (Supabase Dashboard → Edge Functions → send-push → Logs)
-- Look for: "FCM sent to token..." entries
```

If no recent notifications or no send-push logs, STOP and investigate before proceeding.

**B2. Unschedule zombie cron jobs**

```sql
-- List cron jobs to confirm jobids
SELECT jobid, schedule, command, active FROM cron.job;

-- Unschedule job 5
SELECT cron.unschedule(5);

-- Unschedule job 7
SELECT cron.unschedule(7);

-- Verify deletion
SELECT jobid, schedule, command, active FROM cron.job;
-- Expected: jobs 5 and 7 are gone
```

**Why this order?** Unschedule jobs BEFORE deleting the function so we don't leave orphaned cron jobs pointing at a 404.

**B3. Delete deployed `deliver-notifications` Edge Function**

```bash
# Via Supabase CLI
supabase functions delete deliver-notifications --project-ref nekwjxvgbveheooyorjo
```

**Verification**: Visit `https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/deliver-notifications` → should return 404.

**B4. Remove legacy `FCM_SERVER_KEY` secret**

```
Supabase Dashboard → Edge Functions → Secrets → delete FCM_SERVER_KEY
```

**Why last?** The zombie function reads this secret. Delete it only after the function is gone so we don't cause errors in zombie logs (purely cosmetic, but cleaner).

**B5. Verify production still works**
Create a test notification and confirm delivery:

```sql
-- Insert test notification for your user
INSERT INTO notifications (band_id, recipient_user_id, type, title, body, metadata)
VALUES (
  '<your-band-id>',
  '<your-user-id>',
  'gig_created',
  'Test Notification',
  'Verifying delivery after cleanup',
  '{}'::jsonb
);
```

Check send-push logs for "FCM sent..." confirmation.

---

## Database Impact

**Migrations required:**

1. New migration to replace `upsert_device_token` RPC with stale-token cleanup logic

**RLS policies:** Not affected

**RPC functions affected:**

- `upsert_device_token` — modified (drop and recreate in new migration)

**Triggers:** Not affected

**Tables modified:** None (RPC logic change only)

**pg_cron jobs:** Deleted (jobid 5, 7) — manual ops step, not in migration

---

## Flutter Architecture Changes

**Token registration flow updated:**
- `PushNotificationService.registerToken()` now stores/retrieves last token from SharedPreferences
- Passes old token to `NotificationRepository.upsertDeviceToken()` when token refresh is detected
- No new state management or providers — uses existing SharedPreferences pattern already in use by `NotificationPermissionService`

**Changes are minimal and localized:**
- Add SharedPreferences import to `push_notification_service.dart` (package already in use)
- Add 3-4 lines to read stored token before registration
- Add 1 line to update stored token after registration
- Add optional parameter to repository method (backward compatible — defaults to null)

**No impact on:**
- Notification preferences
- Notification display
- Foreground/background handling
- Existing token refresh listener (still works, now passes old token)

---

## Files to Create

**Migration file:**

```
supabase/migrations/YYYYMMDDHHMMSS_cleanup_stale_device_tokens.sql
```

**Purpose:** Replace `upsert_device_token` RPC to add optional `p_old_token` parameter for device-scoped stale token cleanup.

**Structure:**

```sql
-- Drop old RPC
DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT, TEXT);

-- Recreate with optional p_old_token parameter
CREATE OR REPLACE FUNCTION upsert_device_token(
  p_fcm_token TEXT,
  p_platform TEXT,
  p_device_name TEXT DEFAULT NULL,
  p_old_token TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_id UUID;
BEGIN
  -- If old token provided, delete it (device-scoped cleanup for token refresh)
  IF p_old_token IS NOT NULL THEN
    DELETE FROM device_tokens
     WHERE user_id = auth.uid()
       AND fcm_token = p_old_token;
  END IF;

  -- Upsert the new token
  INSERT INTO device_tokens (user_id, fcm_token, platform, device_name, last_seen)
  VALUES (auth.uid(), p_fcm_token, p_platform, p_device_name, now())
  ON CONFLICT (fcm_token)
  DO UPDATE SET
    user_id = auth.uid(),
    platform = p_platform,
    device_name = COALESCE(p_device_name, device_tokens.device_name),
    last_seen = now()
  RETURNING id INTO v_token_id;

  RETURN v_token_id;
END;
$$;
```

**Backward compatibility:** The new signature is backward compatible. Existing calls without `p_old_token` will work (defaults to NULL, no deletion occurs). This allows safe rollback if needed.

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/features/notifications/push_notification_service.dart` | **Line 1**: Add `import 'package:shared_preferences/shared_preferences.dart';` (package already in use). **Line 152-188 (registerToken method)**: Read last token from SharedPreferences (key `last_fcm_token`) before calling getToken(). If stored token exists and differs from current token, pass it as `oldToken` parameter to `upsertDeviceToken()`. After successful registration, save current token to SharedPreferences. **Line 177-184 (onTokenRefresh listener)**: Update to read old token and pass to repository (same pattern as initial registration). |
| `lib/features/notifications/notification_repository.dart` | **Line 66-80 (upsertDeviceToken method)**: Add optional `String? oldToken` parameter (defaults to null). Pass `oldToken` to RPC via params map: `'p_old_token': oldToken`. No other changes — existing logic remains. |
| `docs/agents/PROJECT_CONTEXT.md` | **Line 253-270 (Edge Functions table)**: Swap descriptions for send-push (mark as current arch) and deliver-notifications (remove from table entirely after decommission). Update "All 11 deployed functions" → "All 10 deployed functions". **Line 158 (Database Tables → Events)**: Add `rehearsal_dates` entry: "`rehearsal_dates` — Multi-date support for rehearsals (rehearsal_id, date, RLS by band membership)" |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `supabase/functions/send-push/index.ts` | Production function working correctly — do not modify |
| `supabase/migrations/20260220120000_secure_push_notification_trigger.sql` | Current production trigger — do not modify |
| `supabase/migrations/20260109_notifications.sql` | Original migration — modify via new migration, not direct edit |

---

## System Impact Map

| System                                 | Impact                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| Gigs                                   | **unaffected** — notification creation unchanged                                      |
| Rehearsals                             | **unaffected** — notification creation unchanged                                      |
| Setlists / Catalog                     | **unaffected**                                                                        |
| Members / RBAC                         | **unaffected**                                                                        |
| Auth / Session                         | **unaffected**                                                                        |
| Routing                                | **unaffected**                                                                        |
| Notifications                          | **affected** — zombie removed, token cleanup improved, delivery bookkeeping corrected |
| Platform (iOS / Android / Web / macOS) | **affected** — client token registration logic updated, SharedPreferences storage added               |

---

## Regression Risk

**MEDIUM**

**Rationale:**

- Notification delivery and token registration are the affected systems
- The zombie removal is pure deletion of inactive code paths — production path is untouched
- Token cleanup adds client-side SharedPreferences storage (minimal, isolated change)
- RPC change is conservative (optional parameter, device-scoped deletion only when old token provided)
- Multi-device same-platform support preserved (e.g., iPhone + iPad both keep working)
- No changes to triggers, send-push function, or notification creation flow
- Risk is isolated to: (a) RPC logic error in old token deletion, (b) SharedPreferences read/write failure, (c) ops runbook executed out of order

**Mitigation:**

- Tier 1 pre-deploy tests verify RPC logic before push
- Client changes are backward compatible (optional parameter defaults to null)
- Ops runbook includes verification steps after each deletion
- send-push auto-cleanup remains in place as a fallback if RPC/client fails
- `flutter analyze` will catch client compilation errors before deployment

---

## Engineer Task Breakdown

### Task 1: Delete untracked `deliver-notifications/` directory

```bash
rm -rf supabase/functions/deliver-notifications/
```

Verify deletion: `ls supabase/functions/` should not list `deliver-notifications/`

### Task 2: Create migration to fix `upsert_device_token` RPC

- Create file: `supabase/migrations/YYYYMMDDHHMMSS_cleanup_stale_device_tokens.sql`
- Drop old RPC
- Recreate RPC with optional `p_old_token` parameter and device-scoped DELETE (see Files to Create section)
- Add migration header comment explaining the change

### Task 3: Update push_notification_service.dart

- Add SharedPreferences import
- In `registerToken()` method (line ~152): Read last token from SharedPreferences (key `last_fcm_token`) before calling getToken()
- If stored token exists and differs from current token, pass it as `oldToken` to repository
- After successful registration, save current token to SharedPreferences
- In `onTokenRefresh` listener (line ~177): Apply same pattern (read old token, pass to repository, update storage)

### Task 4: Update notification_repository.dart

- In `upsertDeviceToken()` method (line ~66): Add optional `String? oldToken` parameter
- Pass `oldToken` to RPC via params map: `'p_old_token': oldToken`
- No other changes

### Task 5: Fix PROJECT_CONTEXT.md

- Line 265: Change `deliver-notifications` description from "current arch" to remove row entirely (function will be decommissioned)
- Line 264: Change `send-push` description from "older arch" to "current production push delivery"
- Line 253: Update "All 11 deployed functions" → "All 10 deployed functions"
- Line 158: Add `rehearsal_dates` row to Events table:
  ```markdown
  | `rehearsal_dates` | Multi-date support for rehearsals (rehearsal_id, date) |
  ```

### Task 6: Run `flutter analyze`

Verify 0 errors. Dart code changes are minimal (SharedPreferences usage, optional parameter), but this ensures no compilation issues.

### Task 7: Generate git diff

For Architect review.

---

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

**PRE-DEPLOY TEST: Verify migration syntax is valid**

```bash
# Parse the migration file to ensure no syntax errors
supabase db diff --schema public --use-migra | grep "upsert_device_token"
# Should show the function replacement
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

**POST-DEPLOY TEST 1: Verify RPC exists and contains DELETE logic**

```sql
-- POST-DEPLOY TEST 1: Verify RPC was replaced
SELECT pg_get_functiondef(oid)
  FROM pg_proc
 WHERE proname = 'upsert_device_token'
   AND pg_get_functiondef(oid) LIKE '%DELETE FROM device_tokens%';
-- Expected: 1 row (function exists and contains DELETE)
```

**POST-DEPLOY TEST 2: End-to-end token cleanup test (DEVICE TEST)**

This test must be run on a physical device or emulator (cannot use SQL Editor due to auth.uid() requirement):

1. **Setup**: Install the app with the new code on a test device, log in
2. **Initial registration**: App registers initial token (stored in SharedPreferences)
3. **Verify initial state**: Query database (SQL Editor):
   ```sql
   SELECT fcm_token, platform, device_name, created_at 
   FROM device_tokens 
   WHERE user_id = '<test-user-id>' 
   ORDER BY created_at DESC;
   -- Expected: 1 row with current token
   ```
4. **Simulate token refresh**: Force app restart or wait for natural Firebase token refresh (typically happens on app updates or after ~60 days)
5. **Verify cleanup**: Query database again:
   ```sql
   SELECT fcm_token, platform, device_name, created_at 
   FROM device_tokens 
   WHERE user_id = '<test-user-id>' 
   ORDER BY created_at DESC;
   -- Expected: Still 1 row, but fcm_token may have changed (old token deleted)
   ```
6. **Multi-device test**: Log in on a second iOS device (e.g., iPad if initial was iPhone)
7. **Verify multi-device**: Query database:
   ```sql
   SELECT fcm_token, platform, device_name, created_at 
   FROM device_tokens 
   WHERE user_id = '<test-user-id>' 
   ORDER BY created_at DESC;
   -- Expected: 2 rows (both ios platform, different tokens) — multi-device preserved
   ```

**Alternative SQL-only test** (limited — cannot test RPC auth.uid() path, but verifies table structure):
```sql
-- Verify old token deletion logic exists in RPC (no execution, just inspection)
SELECT pg_get_functiondef(oid)
  FROM pg_proc
 WHERE proname = 'upsert_device_token'
   AND pg_get_functiondef(oid) LIKE '%IF p_old_token IS NOT NULL THEN%';
-- Expected: 1 row (confirms conditional deletion logic present)
```

**POST-DEPLOY TEST 3: Verify no regression in production token registration**

```sql
-- POST-DEPLOY TEST 3: Production data sanity check
-- Verify no user has more than 4 active tokens per platform (reasonable upper bound)
SELECT user_id, platform, COUNT(*) AS token_count
  FROM device_tokens
 GROUP BY user_id, platform
HAVING COUNT(*) > 4
 ORDER BY COUNT(*) DESC;
-- Expected: 0 rows (or investigate if any users have excessive tokens)
```

**POST-DEPLOY TEST 4: Verify send-push still works after migration**

```sql
-- POST-DEPLOY TEST 4: Insert test notification and verify send-push handles it
-- (Run this only if you have a test user with a real device token)
INSERT INTO notifications (band_id, recipient_user_id, type, title, body, metadata)
VALUES (
  '<test-band-id>',
  '<test-user-id>',
  'gig_created',
  'Post-Migration Test Push',
  'Verifying send-push after token cleanup migration',
  '{}'::jsonb
);

-- Then check: Supabase Dashboard → Edge Functions → send-push → Logs
-- Look for: "FCM sent to token..." within 1-2 seconds
-- Expected: Success log entry
```

---

## QA Regression Areas

QA must verify:

### Primary: Notification Delivery (Post-Migration)

1. **Token registration** — Log in on iOS/Android, verify push notifications arrive
2. **Token refresh** — Force app reinstall (or wait for natural token refresh), verify old token is cleaned up
3. **Multiple devices** — Log in on 2 iOS devices, verify each receives pushes independently
4. **No duplicates** — Create a gig, verify each band member receives exactly ONE push notification

### Secondary: Notification Creation (Unchanged Path)

5. **Gig created** — Create confirmed gig, verify other members receive notification
6. **Potential gig created** — Create potential gig, verify other members receive notification
7. **Rehearsal scheduled** — Schedule rehearsal, verify other members receive notification
8. **Block-out date** — Add block-out date, verify other members receive notification
9. **Actor exclusion** — Verify the person creating the event does NOT receive a notification

### Tertiary: Preference Filtering (Unchanged Path)

10. **Master toggle OFF** — Disable notifications in settings, verify no pushes received
11. **Category disabled** — Disable gigs category, verify gig pushes not received but rehearsal pushes are

---

## Rollout / Migration Strategy

**Pre-deployment:**

1. Engineer runs Tier 1 tests locally to validate migration syntax and RPC logic
2. Architect reviews migration file and git diff
3. QA reviews verification plan

**Deployment:**

1. Tony runs `supabase db push` to apply migration to production
2. Tony runs Tier 2 POST-DEPLOY TEST 1 (SQL verification)
3. Tony executes Ops Runbook Part B (unschedule cron, delete function, remove secret)
4. Tony verifies production delivery still works (Ops Runbook B5)
5. QA runs Tier 2 POST-DEPLOY TEST 2 (device test) and regression tests (see QA Regression Areas)

**Rollback plan:**

If RPC breaks token registration after deployment:

1. Create corrective forward migration to restore previous RPC behavior (copy-paste ready SQL below)
2. Apply via `supabase db push`
3. Corrective migration keeps the 4-parameter signature to avoid breaking deployed clients, but removes the DELETE logic

**Corrective migration SQL** (restores previous behavior, keeps 4-param signature):
```sql
-- Rollback: restore previous upsert_device_token behavior
-- IMPORTANT: Keep 4-param signature to avoid PGRST202 from deployed clients
DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION upsert_device_token(
  p_fcm_token TEXT,
  p_platform TEXT,
  p_device_name TEXT DEFAULT NULL,
  p_old_token TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_id UUID;
BEGIN
  -- Accept p_old_token but ignore it (no deletion — original behavior restored)
  -- Multi-device same-platform works; stale tokens accumulate until send-push cleanup
  
  INSERT INTO device_tokens (user_id, fcm_token, platform, device_name, last_seen)
  VALUES (auth.uid(), p_fcm_token, p_platform, p_device_name, now())
  ON CONFLICT (fcm_token) 
  DO UPDATE SET 
    user_id = auth.uid(),
    platform = p_platform,
    device_name = COALESCE(p_device_name, device_tokens.device_name),
    last_seen = now()
  RETURNING id INTO v_token_id;
  
  RETURN v_token_id;
END;
$$;
```

If production delivery fails after ops cleanup: zombie is already deleted (no rollback needed), investigate send-push logs.

---

## Out of Scope

Explicitly NOT included in this cleanup:

1. **The recurring `/rest/v1/band_calendar_subscriptions` 406 issue** — separate bug, unrelated to notification delivery
2. **Notification-tap-navigation PR** — merged/merging separately, different feature
3. **Web push notifications** — not yet implemented, future feature
4. **macOS push notifications** — not yet implemented, future feature
5. **Reworking send-push logging** — current per-token logging is adequate ("FCM sent to token f-O14...")
6. **Sent_at column removal** — While unused, removing the column is not required for correctness and would be a schema-breaking change. Leave it NULL as harmless vestigial data.
7. **Migration to consolidate duplicate tokens in existing data** — The RPC fix prevents NEW duplicates. Existing duplicates will self-heal when send-push deletes UNREGISTERED tokens on next send attempt.

---

## Base Commit

`94d160a3cdcc10a7e775e27844e6eff6b565b18b` (tip of `origin/main` as of 2026-07-05)

Branch: `bug/notification-delivery-housekeeping`
