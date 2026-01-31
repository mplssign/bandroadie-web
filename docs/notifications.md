# Notification System

## Overview

BandRoadie sends push notifications to band members when events are created (gigs, rehearsals, block-out dates). The system is designed to be **reliable, observable, and non-blocking**—database writes never fail due to notification delivery issues.

**Key Principle**: The database creates notification records. An Edge Function delivers them asynchronously. These two operations are completely decoupled.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ User creates gig/rehearsal/block-out                        │
└─────────────────┬───────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Database Trigger: notify_band_members()                     │
│ • Checks user preferences (master toggle + category)        │
│ • Inserts notification record (sent_at = NULL)              │
│ • Returns immediately                                       │
└─────────────────┬───────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ pg_cron runs every 5 minutes                                │
│ Calls: deliver-notifications Edge Function via HTTP         │
└─────────────────┬───────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Edge Function: deliver-notifications                        │
│ 1. Queries: WHERE sent_at IS NULL LIMIT 100                 │
│ 2. Fetches device tokens for recipients                     │
│ 3. Sends FCM push notifications                             │
│ 4. Updates: SET sent_at = NOW()                             │
│ 5. Cleans up invalid tokens                                 │
│ 6. Returns { status: "ok" } (always succeeds)               │
└─────────────────┬───────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ User's device receives push notification                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Notification Lifecycle

### 1. Creation

When a user creates a gig, rehearsal, or block-out date:

1. **Row inserted** into `gigs`, `rehearsals`, or `block_out_dates` table
2. **Trigger fires** (`notify_band_members_on_gig_insert`, etc.)
3. **Function executes** (`notify_band_members()`)
   - Loops through band members
   - Checks notification preferences (master toggle + category)
   - Inserts notification record for each eligible recipient:
     ```
     {
       type: 'gig_created',
       title: 'New Gig Scheduled',
       body: 'The Eagles at Red Rocks - Feb 15',
       recipient_user_id: '...',
       band_id: '...',
       metadata: { gig_id: '...' },
       sent_at: NULL  ← Key: Not yet sent
     }
     ```
4. **Trigger returns** immediately (no HTTP calls, no waiting)

**Database Impact**: ~5-10ms per notification created. Fast and predictable.

---

### 2. Storage

Unsent notifications sit in the `notifications` table with `sent_at IS NULL`.

**Index**: `idx_notifications_unsent` on `(created_at) WHERE sent_at IS NULL` ensures fast lookups.

This creates a **queue** that the delivery system polls.

---

### 3. Scheduling

A **pg_cron job** runs every 5 minutes:

```sql
SELECT cron.schedule(
  'deliver-notifications-cron',
  '*/5 * * * *',  -- Every 5 minutes
  $$ ... $$
);
```

The cron job:
- Uses `pg_net.http_post` to call the Edge Function
- Reads `service_role_key` from Supabase Vault (never inlined)
- Sends `Authorization: Bearer <service_role_key>` header
- Posts empty JSON body `{}`

**Why pg_cron?**
- Built into Supabase
- Reliable scheduling with logs
- No external dependencies
- Runs in the database (low latency)

---

### 4. Delivery

The **deliver-notifications Edge Function** is invoked by the cron job:

**Step 1: Fetch Unsent Notifications**
```sql
SELECT * FROM notifications
WHERE sent_at IS NULL
ORDER BY created_at ASC
LIMIT 100
```

**Step 2: Group by Recipient**

For efficiency, notifications are grouped by `recipient_user_id` to batch device token lookups.

**Step 3: Fetch Device Tokens**
```sql
SELECT user_id, fcm_token
FROM device_tokens
WHERE user_id IN (...)
```

**Step 4: Send FCM Push**

For each recipient:
- Build FCM multicast payload
- POST to `https://fcm.googleapis.com/fcm/send`
- Include `registration_ids` (all devices for that user)
- Include `notification` (title, body) and `data` (metadata)

**Step 5: Mark as Sent**
```sql
UPDATE notifications
SET sent_at = NOW()
WHERE id IN (...)
```

**Step 6: Clean Up Invalid Tokens**

FCM returns `InvalidRegistration` or `NotRegistered` for expired tokens:
```sql
DELETE FROM device_tokens
WHERE fcm_token IN (...)
```

**Step 7: Return Success**
```json
{ "status": "ok" }
```

**Guarantees**:
- Function **always** returns `200 OK`
- Errors are logged but never thrown
- Cron job never fails
- Worst case: notification is retried on next cron run

---

## Why This Design?

### ❌ Why NOT use pg_notify + Database Webhooks?

**Problem**: Database Webhooks are unreliable:
- No retry logic
- No visibility into failures
- Can block database operations if webhook is slow
- Requires external HTTP endpoint to be always available

**Our approach**: Database only creates records. Delivery happens asynchronously via polling.

---

### ❌ Why NOT call Edge Functions from triggers?

**Problem**: Triggers can't make HTTP calls directly. They would need:
- `pg_notify` → Database Webhook → Edge Function

This adds:
- Failure points
- Invisible error states
- Blocking potential

**Our approach**: Triggers insert records. Edge Function polls records.

---

### ✅ Why polling with pg_cron?

**Benefits**:
- **Decoupled**: Database writes never wait for delivery
- **Observable**: Edge Function logs every invocation
- **Retry-safe**: If notification fails, it stays `sent_at IS NULL` and retries on next cron run
- **Idempotent**: Marking as sent prevents double-delivery
- **Batch-friendly**: Process 100 notifications per run (efficient)

**Trade-off**: Maximum 5-minute delay before delivery (acceptable for our use case)

---

### ✅ Why always return success?

If the Edge Function throws an error, pg_cron logs it but **does not retry** automatically. By always returning `{ status: "ok" }`:

- Cron job never appears "failed"
- Unsent notifications remain `sent_at IS NULL`
- Next cron run retries them
- Natural retry loop without custom logic

---

## Observability

### Edge Function Logs

View logs in Supabase Dashboard → Edge Functions → deliver-notifications:

**Normal run**:
```
[Deliver Notifications] Starting...
[Deliver Notifications] Found 3 unsent notifications
[Deliver Notifications] Fetched tokens for 2 users (3 devices)
[Deliver Notifications] Sending to user abc123: 2 devices
[Deliver Notifications] FCM multicast success: 2 devices reached
[Deliver Notifications] Marked 3 notifications as sent
[Deliver Notifications] Completed successfully
```

**No unsent notifications**:
```
[Deliver Notifications] Starting...
[Deliver Notifications] No unsent notifications found
[Deliver Notifications] Completed successfully
```

**Partial failure** (some devices unreachable):
```
[Deliver Notifications] FCM multicast partial failure: 1 success, 1 failure
[Deliver Notifications] Removed 1 invalid device token
[Deliver Notifications] Marked 2 notifications as sent (even with failures)
```

---

### Database Queries

**Check unsent notifications**:
```sql
SELECT COUNT(*) FROM notifications WHERE sent_at IS NULL;
```

**View recent unsent**:
```sql
SELECT type, title, body, recipient_user_id, created_at
FROM notifications
WHERE sent_at IS NULL
ORDER BY created_at DESC
LIMIT 20;
```

**Delivery stats (last 24 hours)**:
```sql
SELECT
  type,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE sent_at IS NOT NULL) AS sent,
  AVG(EXTRACT(EPOCH FROM (sent_at - created_at))) AS avg_delivery_seconds
FROM notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY type;
```

**Find stuck notifications** (created >1 hour ago, still unsent):
```sql
SELECT * FROM notifications
WHERE sent_at IS NULL
  AND created_at < NOW() - INTERVAL '1 hour'
ORDER BY created_at ASC;
```

---

### pg_cron Logs

Check cron execution history:
```sql
SELECT * FROM cron.job_run_details
WHERE jobname = 'deliver-notifications-cron'
ORDER BY start_time DESC
LIMIT 20;
```

Expected output (every 5 minutes):
```
| start_time          | status  | return_message |
|---------------------|---------|----------------|
| 2026-01-30 14:05:00 | success | null           |
| 2026-01-30 14:00:00 | success | null           |
| 2026-01-30 13:55:00 | success | null           |
```

If `status = 'failed'`, the Edge Function URL or auth may be wrong.

---

## Debugging

### Notifications not being created?

**Check 1**: Are triggers installed?
```sql
SELECT * FROM pg_trigger
WHERE tgname LIKE '%notify_band_members%';
```

Expected: 3 triggers (gigs, rehearsals, block_out_dates)

**Check 2**: Are user preferences enabled?
```sql
SELECT * FROM notification_preferences
WHERE user_id = '<user_id>';
```

Fields:
- `notifications_enabled` (master toggle)
- `gigs_enabled`, `potential_gigs_enabled`, `rehearsals_enabled`, `blockouts_enabled`

All must be `true` for notifications to be created.

---

### Notifications created but not delivered?

**Check 1**: Is cron running?
```sql
SELECT * FROM cron.job WHERE jobname = 'deliver-notifications-cron';
```

Expected: `active = true`

**Check 2**: Are cron executions succeeding?
```sql
SELECT status, COUNT(*) FROM cron.job_run_details
WHERE jobname = 'deliver-notifications-cron'
  AND start_time > NOW() - INTERVAL '1 hour'
GROUP BY status;
```

Expected: All `success`

**Check 3**: Does user have device tokens?
```sql
SELECT * FROM device_tokens WHERE user_id = '<user_id>';
```

If empty: User has not enabled push notifications in the app.

**Check 4**: Is FCM server key configured?
```sql
SELECT name FROM vault.decrypted_secrets WHERE name = 'FCM_SERVER_KEY';
```

Expected: One row

If missing: Set via `supabase secrets set FCM_SERVER_KEY="..."`

---

### Notifications stuck unsent?

**Symptom**: `sent_at IS NULL` for old notifications

**Check Edge Function logs** (Supabase Dashboard):
- Look for errors
- Common issues:
  - FCM server key wrong/expired
  - Network timeout
  - Invalid FCM payload

**Manual retry**:

Trigger Edge Function manually via curl:
```bash
curl -X POST https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/deliver-notifications \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Check Edge Function logs for error details.

---

### Cron not running?

**Check if cron extension is enabled**:
```sql
SELECT * FROM pg_extension WHERE extname = 'pg_cron';
```

If missing: Contact Supabase support (pg_cron should be pre-installed)

**Check if job is scheduled**:
```sql
SELECT * FROM cron.job WHERE jobname = 'deliver-notifications-cron';
```

If missing: Re-run the cron scheduling SQL

**Check if pg_net is working**:
```sql
SELECT net.http_post(
  url := 'https://httpbin.org/post',
  headers := '{"Content-Type": "application/json"}',
  body := '{}'
) AS request_id;
```

Expected: Returns a UUID (request_id). Check `net.http_log` for result.

---

## Failure Modes

### Scenario 1: FCM is down

**Behavior**:
- Edge Function logs error
- Returns `{ status: "ok" }` anyway
- Notifications remain `sent_at IS NULL`
- Next cron run (5 minutes) retries

**User Impact**: Delayed notifications (up to 5 minutes)

**Action**: None required. System self-heals.

---

### Scenario 2: Invalid FCM server key

**Behavior**:
- All FCM requests fail with `401 Unauthorized`
- Edge Function logs error
- Returns `{ status: "ok" }`
- Notifications remain unsent indefinitely

**User Impact**: No notifications delivered

**Action**:
1. Check Edge Function logs for `401` errors
2. Verify FCM server key: Supabase Dashboard → Settings → Vault
3. Regenerate key in Firebase Console if needed
4. Update vault secret: `supabase secrets set FCM_SERVER_KEY="..."`
5. Notifications will deliver on next cron run

---

### Scenario 3: Database migration breaks trigger

**Behavior**:
- Trigger fails when event created
- **Database write fails** (user sees error)
- No notification record created

**User Impact**: User sees "Failed to create gig" error

**Action**:
1. Check Postgres logs for trigger errors
2. Fix trigger function (`notify_band_members`)
3. Re-deploy migration

---

### Scenario 4: Edge Function times out

**Behavior**:
- Supabase Edge Functions have 30-second timeout
- If processing >100 notifications takes >30s, function times out
- Partial notifications may be marked as sent
- Remaining notifications stay unsent

**User Impact**: Some notifications delayed

**Action**:
- Check if notification queue is growing: `SELECT COUNT(*) FROM notifications WHERE sent_at IS NULL`
- If consistently >100, consider increasing cron frequency to every 1 minute
- Or increase BATCH_SIZE in Edge Function (current: 100)

---

### Scenario 5: Device token is invalid

**Behavior**:
- FCM returns `InvalidRegistration` or `NotRegistered`
- Edge Function removes token from `device_tokens`
- Notification still marked as sent (no retry)

**User Impact**: User doesn't receive notification (device uninstalled or logged out)

**Action**: None required. User will re-register token when app opens again.

---

## Cost Estimation

**Edge Function invocations**:
- Frequency: Every 5 minutes = 288 invocations/day = 8,640/month
- Supabase free tier: 500,000 invocations/month
- Usage: **1.7% of free tier**

**Database queries** (per cron run):
- 1 SELECT (unsent notifications)
- 1 SELECT (device tokens)
- 1 UPDATE (mark as sent)
- 0-N DELETE (invalid tokens)

Total: ~4 queries per 5 minutes = negligible load

**pg_cron overhead**: Minimal (built-in, no extra cost)

**Conclusion**: System runs well within free tier limits.

---

## Future Enhancements

**Not yet implemented**:

- **User notification history**: Web UI to view past notifications
- **Read/unread state**: Mark notifications as read in-app
- **In-app notification center**: Show notifications without push
- **Delivery receipts**: Track which notifications were opened
- **Retry backoff**: Exponential backoff for failed deliveries
- **Priority levels**: Send urgent notifications immediately (bypass cron)
- **Notification categories**: Mute specific types (e.g., only gigs, not rehearsals)
- **Time zone awareness**: Don't notify users during sleep hours

These can be added without changing the core architecture.

---

## Summary

The notification system is designed for **reliability over speed**:

- ✅ Database writes never fail due to delivery issues
- ✅ Delivery is async and retries automatically
- ✅ Observable via Edge Function logs and SQL queries
- ✅ Scales to thousands of notifications/day
- ✅ Runs within free tier limits

**Key files**:
- **Migration**: `supabase/migrations/087_clean_notification_system.sql`
- **Edge Function**: `supabase/functions/deliver-notifications/index.ts`
- **Cron Job**: Scheduled in Supabase Dashboard → Database → Cron Jobs
- **Client**: `lib/features/notifications/` (Flutter app)

**Owner**: Backend notification pipeline
**Last Updated**: January 30, 2026
