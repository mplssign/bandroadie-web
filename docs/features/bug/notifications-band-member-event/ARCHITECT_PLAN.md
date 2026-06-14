# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/notifications-band-member-event`

## 2. Problem Summary

When a non-owner band member creates a gig, rehearsal, or block-out date, other band members receive no notification. The failure is silent: event creation succeeds, no user-facing error appears, and no notification is delivered.

The repo shows that notification creation happens in database trigger functions, then delivery is delegated to the push pipeline. The most likely root failure in the current code is earlier than push delivery: recipients can be excluded before a `notifications` row is ever inserted.

## 3. Root Cause

**Primary root cause:** `should_receive_notification()` returns `false` when a recipient has no row in `notification_preferences`, even though all relevant preference columns default to enabled and the Flutter app only creates that row lazily when the settings flow fetches preferences.

**Confidence:** `MEDIUM`

### Evidence from code

1. `notify_band_members()` currently checks `should_receive_notification(v_member.user_id, p_notification_type)` before inserting into `notifications`.
   - Source: `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260408000000_fix_notification_preferences_check.sql`

2. `should_receive_notification()` explicitly treats a missing preferences row as opt-out:

```sql
SELECT * INTO v_prefs
FROM notification_preferences
WHERE user_id = p_user_id;

IF v_prefs IS NULL OR NOT v_prefs.notifications_enabled THEN
  RETURN false;
END IF;
```

   - Source: `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260128205900_notification_categories.sql`

3. The app creates the row lazily via `get_or_create_notification_preferences()` only when the notification preferences flow runs.
   - SQL RPC source: `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260109_notifications.sql`
   - Flutter caller source: `/Users/tonyholmes/apps/bandroadie/lib/features/notifications/notification_repository.dart`

4. Recipient selection does not branch on owner vs. member. The helper loops all band members except the actor:

```sql
SELECT user_id
  FROM band_members
 WHERE band_id = p_band_id
   AND user_id != COALESCE(p_actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
```

   - Source: `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260408000000_fix_notification_preferences_check.sql`

### Why confidence is not HIGH yet

The repo proves the failure mode exists, but this session does not have direct access to the live Supabase dashboard or database to confirm that the affected recipients in production actually lack `notification_preferences` rows. A focused SQL check is required before implementation proceeds.

### Secondary findings

- `auth.uid()` is used uniformly in `notify_gig_created()`, `notify_rehearsal_created()`, and `notify_blockout_created()` to identify the actor. There is no owner-only branch.
- `notify_band_members()` is `SECURITY DEFINER`, so the intent is for the helper to bypass end-user insert restrictions on `notifications`.
- The repo does **not** contain the `deliver-notifications` function source file, even though docs and `supabase/config.toml` still reference it. That makes the cron path impossible to verify from source alone.

## 4. Reference Docs Consulted

- `/Users/tonyholmes/apps/bandroadie/docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `/Users/tonyholmes/apps/bandroadie/docs/reference/notifications/notifications.md`
- `/Users/tonyholmes/apps/bandroadie/docs/reference/architecture/supabase_functions.md`
- `/Users/tonyholmes/apps/bandroadie/docs/reference/architecture/architecture.md`

## 5. Existing System Analysis

### 5.1 Trigger and delivery flow in code

For gig creation:

1. Flutter inserts directly into `gigs`.
   - Source: `/Users/tonyholmes/apps/bandroadie/lib/features/events/events_repository.dart`
2. `notify_gig_created()` runs `AFTER INSERT`.
3. It resolves actor text from `auth.uid()` and calls `notify_band_members()`.
4. `notify_band_members()` evaluates `should_receive_notification()` for each recipient.
5. If allowed, it inserts into `notifications`.
6. `on_notification_inserted` fires `trigger_send_push_notification()`.
7. The SQL trigger POSTs to `send-push` with `X-Internal-Secret`.
8. `send-push` fetches `device_tokens`, counts unread notifications, and sends FCM HTTP v1 pushes.

The same shape applies to rehearsals and block-outs.

### 5.2 Active delivery path: what is confirmed vs. not confirmed

**Confirmed in source:**

- `send-push` exists in the repo at `/Users/tonyholmes/apps/bandroadie/supabase/functions/send-push/index.ts`.
- The secure SQL trigger path exists in `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260220120000_secure_push_notification_trigger.sql`.
- That migration explicitly says to delete the old dashboard webhook `send_push_on_notification` after moving to the SQL trigger.

**Documented but not source-backed in this repo:**

- `deliver-notifications` is referenced in:
  - `/Users/tonyholmes/apps/bandroadie/supabase/config.toml`
  - `/Users/tonyholmes/apps/bandroadie/docs/reference/notifications/notifications.md`
  - `/Users/tonyholmes/apps/bandroadie/docs/reference/architecture/supabase_functions.md`
- But `/Users/tonyholmes/apps/bandroadie/supabase/functions/deliver-notifications/index.ts` does not exist in the workspace.

**Architect conclusion:**

- The only delivery implementation that is directly verifiable from this repo is `notifications` insert -> SQL trigger `trigger_send_push_notification()` -> `send-push`.
- Whether production still has the old dashboard webhook, a live cron job, or both must be confirmed in Supabase Dashboard before any implementation is approved.

### 5.3 Trigger function audit

#### `notify_gig_created()`

- Uses `auth.uid()` to identify the actor.
- Builds the message body based on `NEW.is_potential`.
- Calls `notify_band_members()` with the actor ID and payload.
- No owner/member-specific behavior exists.

#### `notify_rehearsal_created()`

- Final repo version is in `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql`.
- Uses `auth.uid()`.
- Skips child recurring rehearsals.
- Calls `notify_band_members()` identically.
- No owner/member-specific behavior exists.

#### `notify_blockout_created()`

- Current repo trigger body comes from `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260220130000_fix_notification_triggers_exception_handling.sql`.
- Uses `auth.uid()` and delegates to `notify_band_members()`.
- No owner/member-specific behavior exists.

#### Shared `notify_band_members()` helper

- Current repo version comes from `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260408000000_fix_notification_preferences_check.sql`.
- Recipient query filters only by `band_id` and `user_id != actor`; it does **not** filter `status = 'active'`.
- The loop logic does not vary based on owner vs. member actor.
- The first exclusion point is `should_receive_notification()`.

### 5.4 `should_receive_notification()` missing-row behavior

This function currently returns `FALSE` if there is no `notification_preferences` row.

That means the system is effectively treating "no row yet" as "notifications disabled," even though:

- the table schema defaults every relevant column to enabled, and
- the app only creates a row lazily when preferences are read.

This is the most probable silent drop point.

### 5.5 RLS audit

#### `notification_preferences`

Confirmed policies from `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260109_notifications.sql`:

- `Users can view own notification preferences`
- `Users can insert own notification preferences`
- `Users can update own notification preferences`

All are self-scoped to `auth.uid() = user_id`.

#### `notifications`

Confirmed policies from `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260109_notifications.sql`:

- `Users can view own notifications`
- `Users can update own notifications`
- No end-user `INSERT` policy exists.

So cross-user notification inserts rely on the `SECURITY DEFINER` path.

#### `device_tokens`

Confirmed policies from `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260109_notifications.sql`:

- Users can only view/insert/update/delete their own device tokens.

Delivery reads therefore also rely on the service-role Supabase client inside `send-push`.

#### `band_members`

The repo does **not** contain the original migration that defines the `band_members` policies. Later migrations clearly assume an existing SELECT policy and repeatedly filter on `status = 'active'` in other tables, but the exact policy SQL for `band_members` itself is not present in the current workspace.

Architect assessment:

- Because `notify_band_members()` is `SECURITY DEFINER`, band-member visibility is **likely unaffected** by actor role in this call chain.
- The exact production `band_members` policy text remains **unknown from repo evidence** and must be confirmed live if the preference-row hypothesis is disproven.

### 5.6 Exact failure point to confirm first

The first place to verify in production is whether a member-created event produces `notifications` rows at all.

- If **no rows** are created for eligible recipients, the failure is inside `notify_band_members()`.
- If rows **are created** but no push arrives, the failure is downstream in `send-push`, dashboard webhook/trigger wiring, cron, tokens, or FCM.

## 6. Proposed Solution

### Minimal fix

Change `should_receive_notification()` so that a missing row means **default ON**, not silent exclusion.

Proposed behavior:

- If no `notification_preferences` row exists for `p_user_id`, return `TRUE` for supported event categories.
- If a row exists and `notifications_enabled = false`, return `FALSE`.
- If a row exists and the relevant category toggle is `false`, return `FALSE`.

This matches the schema defaults and avoids requiring every band member to visit Notification Settings before they can receive event notifications.

### Why this is the smallest safe change

- One SQL helper function controls the exclusion decision.
- No Flutter changes are required.
- No trigger rewiring is required.
- No RLS policy rewrite is required unless live verification disproves the helper-only diagnosis.

### What must not change

- `notify_band_members()` should remain the only place that fans out recipients.
- `send-push` should continue to be non-blocking and delivery-only.
- No client-side notification fan-out logic should be introduced.

### If live validation disproves the missing-row hypothesis

Do **not** implement the helper change blindly. Switch to the next nearest failure layer:

1. Verify `notify_band_members()` can see recipient preferences in production.
2. Verify `notifications` rows exist for member-created events.
3. Verify whether `send-push`, dashboard webhook, SQL trigger, and cron are all active or partially stale.

## 7. Database Impact

`Affected`

### Tables

- `notification_preferences`: behavior changed through helper semantics only; schema unchanged.
- `notifications`: no schema change.
- `band_members`: no schema change.

### RLS

- `notification_preferences`: unaffected initially.
- `notifications`: unaffected initially.
- `band_members`: unknown exact policy text in repo, but no planned policy change in the minimal fix.

### Triggers

- `notify_gig_created()`: unaffected.
- `notify_rehearsal_created()`: unaffected.
- `notify_blockout_created()`: unaffected.
- `trigger_send_push_notification()`: unaffected.

### RPCs / helper functions

- `should_receive_notification()`: **affected**.
- `get_or_create_notification_preferences()`: unaffected.
- `notify_band_members()`: unchanged for the minimal fix.

### Migration requirement

`required`

Implement as a new migration that replaces `should_receive_notification()`.

## 8. Flutter Architecture Changes

`Not applicable`

No Flutter state, widget, repository, or provider changes are required for the minimal fix.

The app already persists preferences and already calls `get_or_create_notification_preferences()` when the settings surface is used. The bug is in SQL semantics, not client flow.

## 9. Files to Create

| File | Justification |
|------|---------------|
| `/Users/tonyholmes/apps/bandroadie/supabase/migrations/YYYYMMDDHHMMSS_fix_notification_default_on_missing_preferences.sql` | Replace `should_receive_notification()` so missing preferences rows default to enabled instead of silent exclusion. |

## 10. Files to Modify

| File | What changes |
|------|--------------|
| `/Users/tonyholmes/apps/bandroadie/supabase/migrations/YYYYMMDDHHMMSS_fix_notification_default_on_missing_preferences.sql` | New migration that replaces `should_receive_notification()` with default-ON missing-row semantics and preserves category-specific logic. |

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `/Users/tonyholmes/apps/bandroadie/lib/main.dart` | Initialization order is guarded and unrelated. |
| `/Users/tonyholmes/apps/bandroadie/lib/features/events/events_repository.dart` | Event creation path already inserts into the correct tables; no client-side workaround. |
| `/Users/tonyholmes/apps/bandroadie/supabase/functions/send-push/index.ts` | Delivery code is not the first failure layer for the minimal fix. |
| `/Users/tonyholmes/apps/bandroadie/supabase/config.toml` | Delivery-path ambiguity must be resolved with dashboard verification, not speculative config edits. |
| `/Users/tonyholmes/apps/bandroadie/supabase/migrations/20260220120000_secure_push_notification_trigger.sql` | No trigger or webhook rewrite unless SQL verification disproves the helper-layer diagnosis. |

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | affected |
| Rehearsals | affected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | affected |
| Platform (iOS / Android / Web / macOS) | iOS affected, Android likely affected, Web unaffected, macOS unknown |

## 13. Regression Risk

`MEDIUM`

Rationale:

- The change is localized to one SQL helper.
- It affects all event-notification categories that rely on `should_receive_notification()`.
- A wrong default could either keep suppressing valid notifications or start sending notifications to users who intentionally opted out if row visibility is being masked by an RLS issue rather than true row absence.

## 14. Engineer Task Breakdown

1. Confirm the production delivery path in Supabase Dashboard:
   - Database Webhooks: verify whether `send_push_on_notification` still exists.
   - Database Cron: verify whether `deliver-notifications-cron` exists and is active.
   - If both are active, document that overlap before changing SQL.

2. Run the pre-deployment diagnostic SQL in Tier 1 to confirm the actual failure layer for a known band and a known member-created event.

3. If Tier 1 confirms recipients are being excluded before notification insert because of missing preferences rows, create a new migration that replaces `should_receive_notification()` so missing rows default to enabled.

4. Keep `notify_band_members()` unchanged unless Tier 1 proves the helper is not the failure point.

5. Apply the migration in a test/staging environment.

6. Run Tier 2 SQL checks to confirm the replaced function exists and that member-created events now produce notification rows for recipients without preference records.

7. Verify end-to-end push delivery on iOS with at least one account that has never previously opened Notification Settings.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1:
-- Confirm the current helper returns FALSE on missing preferences rows.
-- Replace :missing_user_id with a real auth.users id that has no notification_preferences row.
SELECT should_receive_notification(:missing_user_id, 'gig_created') AS should_receive;
```

```sql
-- PRE-DEPLOY TEST 2:
-- Find active band members who have no notification_preferences row.
-- Replace :band_id with the affected band.
SELECT bm.user_id,
       bm.status,
       np.user_id AS preferences_row_present
FROM band_members bm
LEFT JOIN notification_preferences np
  ON np.user_id = bm.user_id
WHERE bm.band_id = :band_id
ORDER BY bm.status, bm.user_id;
```

```sql
-- PRE-DEPLOY TEST 3:
-- Confirm the failure point for recent member-created events:
-- does the recipient ever get a notifications row?
-- Replace :band_id and :actor_user_id.
SELECT n.id,
       n.recipient_user_id,
       n.type,
       n.created_at,
       n.actor_user_id
FROM notifications n
WHERE n.band_id = :band_id
  AND n.actor_user_id = :actor_user_id
  AND n.created_at > NOW() - INTERVAL '24 hours'
ORDER BY n.created_at DESC;
```

```sql
-- PRE-DEPLOY TEST 4:
-- Confirm current function source contains the missing-row false behavior.
SELECT pg_get_functiondef('should_receive_notification(uuid,text)'::regprocedure) AS fn_sql;
```

```sql
-- PRE-DEPLOY TEST 5:
-- Dashboard-backed checks to run manually, because repo source cannot prove them:
-- 1) Database -> Webhooks -> does send_push_on_notification exist?
-- 2) Database -> Cron -> does deliver-notifications-cron exist and is it active?
-- 3) Edge Functions -> does deliver-notifications exist in production despite missing repo source?
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1:
-- Verify the replaced function exists and now defaults missing rows to TRUE.
SELECT pg_get_functiondef('should_receive_notification(uuid,text)'::regprocedure) AS fn_sql;
-- Expected function text includes a missing-row path that returns TRUE,
-- not FALSE.
```

```sql
-- POST-DEPLOY TEST 2:
-- Integration check for a user with no notification_preferences row.
-- Wrap in a transaction and roll back.
BEGIN;

-- Replace :test_user_id with a real band member lacking a prefs row.
SELECT should_receive_notification(:test_user_id, 'gig_created') AS should_receive_after_fix;

ROLLBACK;
```

```sql
-- POST-DEPLOY TEST 3:
-- Full-chain integration: create a member-authored event in staging,
-- then verify notification rows exist for recipients.
-- Replace :band_id and :actor_user_id with real staging values.
SELECT n.recipient_user_id,
       n.type,
       n.created_at,
       np.user_id AS prefs_row_present
FROM notifications n
LEFT JOIN notification_preferences np
  ON np.user_id = n.recipient_user_id
WHERE n.band_id = :band_id
  AND n.actor_user_id = :actor_user_id
  AND n.created_at > NOW() - INTERVAL '10 minutes'
ORDER BY n.created_at DESC;
```

```sql
-- POST-DEPLOY TEST 4:
-- Production verification query: no recipients with enabled-or-missing prefs
-- should be silently excluded after a member-created event.
-- Replace :band_id and :actor_user_id.
WITH active_recipients AS (
  SELECT bm.user_id
  FROM band_members bm
  WHERE bm.band_id = :band_id
    AND bm.status = 'active'
    AND bm.user_id <> :actor_user_id
), recent_notifications AS (
  SELECT DISTINCT recipient_user_id
  FROM notifications
  WHERE band_id = :band_id
    AND actor_user_id = :actor_user_id
    AND created_at > NOW() - INTERVAL '10 minutes'
)
SELECT ar.user_id
FROM active_recipients ar
LEFT JOIN recent_notifications rn
  ON rn.recipient_user_id = ar.user_id
LEFT JOIN notification_preferences np
  ON np.user_id = ar.user_id
WHERE rn.recipient_user_id IS NULL
  AND COALESCE(np.notifications_enabled, TRUE) = TRUE;
```

## 16. QA Regression Areas

- Event creation notification when a non-owner member creates:
  - confirmed gig
  - potential gig
  - rehearsal
  - block-out date
- Owner-created event notification still works.
- Recipient with no existing `notification_preferences` row receives default-on notifications.
- Recipient with `notifications_enabled = false` receives no notification.
- Recipient with a category disabled receives no notification for that category only.
- iOS push delivery end-to-end from `notifications` row creation through banner delivery.
- Android push delivery parity if test devices are available.
- Ensure actor never receives their own notification.

## 17. Rollout / Migration Strategy

1. Confirm the production delivery path first.
2. Run Tier 1 SQL in staging or production-read context.
3. If the missing-row hypothesis is confirmed, deploy the helper-only migration.
4. Run Tier 2 SQL immediately after deploy.
5. Perform one real member-created event test on iOS before declaring the issue closed.

No staged Flutter rollout is required because the fix is database-side.

## 18. Out of Scope

- Rewriting the notification architecture from trigger/webhook to cron polling.
- Retiring `deliver-notifications` or `send-push` without dashboard confirmation.
- Refactoring notification settings UI.
- Introducing onboarding-time backfill of `notification_preferences` rows.
- Adding new notification types.

## Stop-and-Escalate Conditions

Stop and escalate to Tony if any of the following is true:

1. Tier 1 shows recipient `notifications` rows are already being inserted for member-created events. That means the bug is downstream in delivery, not the helper gate.
2. Tier 1 shows affected recipients do have `notification_preferences` rows and `should_receive_notification()` returns `TRUE` for them. That falsifies the current root-cause hypothesis.
3. Supabase Dashboard shows `deliver-notifications-cron` is the only active production path, but the function source is absent from the repo. Live function source or export is needed before safe planning can continue.
4. Tony wants missing preference rows to default to OFF. That is a product decision and changes the fix direction.
5. Live inspection reveals `band_members` or `notification_preferences` RLS behavior contradicts the expected `SECURITY DEFINER` bypass and requires a policy or ownership change.