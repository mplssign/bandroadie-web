# Band Roadie Notification System

## Overview
Lightweight, event-driven push notification system that informs band members of important activity:
- **Gig created** (confirmed gigs only)
- **Potential gig created**
- **Rehearsal scheduled**
- **Block-out dates created**

**Critical constraints:**
- ✅ Notifications only on **CREATE** (not edit/delete)
- ✅ **Never notify the actor** (person who performed the action)
- ✅ Non-blocking - does not gate core functionality
- ✅ Respects user preferences (master toggle + per-category)

---

## Data Model

### 1. Notification Preferences (per user)

**Table:** `notification_preferences`

```sql
-- Master toggle
notifications_enabled BOOLEAN DEFAULT true

-- Category toggles (only visible when notifications_enabled = true)
gigs_enabled BOOLEAN DEFAULT true
potential_gigs_enabled BOOLEAN DEFAULT true
rehearsals_enabled BOOLEAN DEFAULT true
blockouts_enabled BOOLEAN DEFAULT true

-- Legacy fields (backwards compatibility)
push_enabled BOOLEAN DEFAULT true
in_app_enabled BOOLEAN DEFAULT true
```

**Dart Model:** `NotificationPreferences`
- Located: `lib/features/notifications/models/notification_preferences.dart`
- Fields map directly to database columns
- Uses `copyWith` pattern for immutable updates

**Repository:** `NotificationRepository`
- `getOrCreatePreferences()` - Fetches or creates default preferences
- `updatePreferences(prefs)` - Saves changes to Supabase

**Controller:** `NotificationPreferencesController` (Riverpod StateNotifier)
- Methods: `updateNotificationsEnabled()`, `updateGigsEnabled()`, etc.
- Optimistic updates with error rollback

---

### 2. Device Tokens (for FCM)

**Table:** `device_tokens`

```sql
user_id UUID
fcm_token TEXT UNIQUE
platform TEXT (ios, android, web, macos)
device_name TEXT (optional)
last_seen TIMESTAMPTZ
```

**Registration:** Handled by `PushNotificationService`
- Registers token on app launch/login
- Updates token on refresh
- Removes token on logout

---

### 3. Notifications (in-app activity feed)

**Table:** `notifications`

```sql
recipient_user_id UUID
band_id UUID
type TEXT (gig_created, potential_gig_created, rehearsal_created, blockout_created)
title TEXT
body TEXT
metadata JSONB (deep link data)
read_at TIMESTAMPTZ (null = unread)
actor_user_id UUID (who triggered it)
```

**Notification Types:**
- `gig_created` - "{Name} created a gig for MAR 17, 2026"
- `potential_gig_created` - "{Name} created a potential gig for MAR 17, 2026"
- `rehearsal_created` - "{Name} scheduled a rehearsal for JUN 24, 2026"
- `blockout_created` - "{Name} is unavailable on APR 18, 2026" OR "{Name} is unavailable MAY 3 – JUN 5, 2026"

---

## Settings UI

**Screen:** `NotificationSettingsScreen`
- Location: `lib/features/notifications/notification_settings_screen.dart`
- Route: Settings → Notifications

**Layout:**
1. **Master toggle card** (always visible)
   - Icon + "Notifications" label + Switch
   - Subtitle: "You'll receive updates" / "All notifications off"

2. **Category checkboxes** (only shown when master = ON)
   - "Notify me when:" header
   - 4 checkboxes:
     - ☑️ Gigs - "Someone schedules a confirmed gig"
     - ☑️ Potential Gigs - "Someone creates a potential gig"
     - ☑️ Rehearsals - "Someone schedules a rehearsal"
     - ☑️ Block-out Dates - "Someone marks themselves unavailable"

**Behavior:**
- Toggling master OFF disables all categories (visually disabled, preferences preserved)
- Each checkbox updates immediately (optimistic UI with error handling)
- Changes persist to `notification_preferences` table via repository

---

## Backend Logic

### Edge Function: `send-notification`

**Location:** `supabase/functions/send-notification/index.ts`

**Input (POST):**
```json
{
  "bandId": "uuid",
  "actorUserId": "uuid",
  "notificationType": "gig_created",
  "title": "Gig at Blue Note",
  "body": "Tony created a gig for MAR 17, 2026",
  "metadata": { "gig_id": "uuid", "gig_date": "2026-03-17" }
}
```

**Process:**
1. Fetch all band members (exclude actor)
2. Check each member's `notification_preferences`:
   - Skip if `notifications_enabled = false`
   - Skip if category-specific toggle = false (e.g., `gigs_enabled = false`)
3. Get FCM tokens for eligible members
4. Create in-app notification records (always, regardless of push)
5. Send FCM push notifications (multicast to all tokens)

**Output:**
```json
{
  "success": true,
  "recipients": 4,  // eligible users
  "sent": 3         // successful FCM sends
}
```

**Environment Variables:**
- `FCM_SERVER_KEY` - Firebase Cloud Messaging server key
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

---

### Database Triggers

**Migration:** `20260128_notification_triggers.sql`

**Triggers:**
1. `gig_created_notification` → `notify_gig_created()`
2. `rehearsal_created_notification` → `notify_rehearsal_created()`
3. `blockout_created_notification` → `notify_blockout_created()`

**How they work:**
- Fire AFTER INSERT only (not UPDATE or DELETE)
- Read `auth.uid()` to get actor
- Format notification title/body with proper date formatting
- Call `notify_band_members()` helper function
- Use `pg_notify` to publish event (for async processing)

**Date Formatting Examples:**
- Single date: "MAR 17, 2026" (uppercase month abbreviation)
- Date range (same month): "MAY 3 – 5, 2026"
- Date range (different months): "MAY 3 – JUN 5, 2026"

---

## Client-Side Components

### 1. Notification Preferences Controller
**File:** `lib/features/notifications/notification_preferences_controller.dart`

**Provider:** `notificationPreferencesProvider`
- Type: `StateNotifierProvider<AsyncValue<NotificationPreferences>>`
- Loads preferences on init
- Exposes update methods for each toggle

**Usage:**
```dart
// Watch preferences
final prefs = ref.watch(notificationPreferencesProvider);

// Update master toggle
await ref.read(notificationPreferencesProvider.notifier)
  .updateNotificationsEnabled(true);

// Update category
await ref.read(notificationPreferencesProvider.notifier)
  .updateGigsEnabled(false);
```

### 2. Notification Repository
**File:** `lib/features/notifications/notification_repository.dart`

**Methods:**
- `getOrCreatePreferences()` - Returns `NotificationPreferences`
- `updatePreferences(prefs)` - Saves to Supabase
- `upsertDeviceToken()` - Registers FCM token
- `removeDeviceToken()` - Cleanup on logout

**Provider:** `notificationRepositoryProvider`
```dart
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});
```

### 3. Push Notification Service
**File:** `lib/features/notifications/push_notification_service.dart`

**Handles:**
- FCM token registration
- Token refresh
- Foreground notification display (mobile)
- Token cleanup on logout

**Usage:**
```dart
final service = PushNotificationService();
await service.initialize();
await service.requestPermission();
await service.registerToken(); // Happens on login
```

---

## Notification Copy Patterns

Follow these exact patterns for consistency:

### Gigs (Confirmed)
```
Title: {Gig Name}
Body: {Name} created a gig for MAR 17, 2026
```

### Potential Gigs
```
Title: {Gig Name}
Body: {Name} created a potential gig for MAR 17, 2026
```

### Rehearsals
```
Title: Rehearsal Scheduled
Body: {Name} scheduled a rehearsal for JUN 24, 2026
```

### Block-outs (Single Day)
```
Title: Member Unavailable
Body: {Name} is unavailable on APR 18, 2026
```

### Block-outs (Date Range)
```
Title: Member Unavailable
Body: {Name} is unavailable MAY 3 – JUN 5, 2026
```

**Rules:**
- Month abbreviations: UPPERCASE, 3 letters (JAN, FEB, MAR...)
- No leading zeros on days (3, not 03)
- Year: 4 digits (2026)
- Use "–" (en dash) for date ranges, not "-" (hyphen)

---

## Migration Steps

### Database Migrations

Run in order:

1. **20260128_notification_categories.sql**
   - Adds new preference columns (`notifications_enabled`, `gigs_enabled`, etc.)
   - Updates notification types (adds `potential_gig_created`, `blockout_created`)
   - Creates `should_receive_notification()` helper function

2. **20260128_notification_triggers.sql**
   - Creates trigger functions for gig/rehearsal/block-out creation
   - Attaches triggers to `gigs`, `rehearsals`, `block_out_dates` tables
   - Uses `pg_notify` for async event publishing

### Edge Function Deployment

```bash
# Deploy the send-notification function
supabase functions deploy send-notification

# Set environment variables
supabase secrets set FCM_SERVER_KEY=your_fcm_server_key_here
```

---

## Testing Checklist

### Settings UI
- [ ] Master toggle shows/hides category checkboxes
- [ ] Master OFF disables all checkboxes (grayed out)
- [ ] Each checkbox updates immediately
- [ ] Preferences persist after app restart
- [ ] Error handling shows snackbar on failure

### Notification Delivery
- [ ] Create gig → other members receive notification
- [ ] Create potential gig → other members receive notification
- [ ] Schedule rehearsal → other members receive notification
- [ ] Add block-out → other members receive notification
- [ ] Actor does NOT receive their own notifications

### Preference Filtering
- [ ] Master OFF → no notifications sent
- [ ] Gigs disabled → gig notifications not sent
- [ ] Potential gigs disabled → potential gig notifications not sent
- [ ] Rehearsals disabled → rehearsal notifications not sent
- [ ] Block-outs disabled → block-out notifications not sent

### Copy Formatting
- [ ] Dates formatted correctly (MAR 17, 2026)
- [ ] Date ranges formatted correctly (MAY 3 – JUN 5, 2026)
- [ ] Actor name appears in body
- [ ] Title matches event type

---

## Future Enhancements (Out of Scope)

These were explicitly NOT implemented to keep the system lightweight:

- ❌ Edit notifications (only CREATE events)
- ❌ Delete notifications
- ❌ Gig response notifications
- ❌ Setlist update notifications
- ❌ Member join/leave notifications
- ❌ Quiet hours
- ❌ Email notifications
- ❌ SMS notifications
- ❌ In-app notification badge/count
- ❌ Notification history screen
- ❌ Mark as read/unread from UI

These can be added later without breaking existing functionality.

---

## Troubleshooting

### Notifications not sending

1. Check FCM_SERVER_KEY is set:
   ```bash
   supabase secrets list
   ```

2. Verify Edge Function is deployed:
   ```bash
   supabase functions list
   ```

3. Check trigger fired:
   ```sql
   SELECT * FROM notifications 
   WHERE created_at > now() - interval '1 hour'
   ORDER BY created_at DESC;
   ```

4. Check user preferences:
   ```sql
   SELECT * FROM notification_preferences 
   WHERE user_id = 'uuid';
   ```

### UI not loading preferences

1. Check Riverpod provider initialization
2. Verify Supabase client is initialized
3. Check browser console for errors
4. Verify RLS policies allow SELECT on `notification_preferences`

### Date formatting issues

- Ensure timezone consistency (database stores UTC)
- Check `TO_CHAR` format strings match required output
- Test edge cases: first/last day of month, year boundary

---

## File Inventory

### Flutter (Client)
```
lib/features/notifications/
├── models/
│   └── notification_preferences.dart     # Data model
├── notification_repository.dart           # Supabase data access
├── notification_preferences_controller.dart  # Riverpod state
├── notification_settings_screen.dart      # Settings UI
└── push_notification_service.dart         # FCM integration (existing)

lib/features/settings/
└── settings_screen.dart                   # Added Notifications item
```

### Backend (Supabase)
```
supabase/migrations/
├── 20260109_notifications.sql             # Base tables (existing)
├── 20260128_notification_categories.sql   # New preference columns
└── 20260128_notification_triggers.sql     # Auto-send triggers

supabase/functions/
└── send-notification/
    └── index.ts                           # FCM delivery logic
```

---

## Summary

This notification system is:
- **Lightweight**: Minimal code changes, no complex state management
- **Flexible**: Easy to add new notification types
- **Respectful**: Users control what they see via granular preferences
- **Reliable**: Degrades gracefully (in-app notifications always work, push is best-effort)
- **Non-blocking**: Failures don't break core app functionality

The implementation follows Band Roadie's architecture patterns (Riverpod, Repository, Supabase RLS) and maintains the app's brand voice in notification copy.
