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

## Implementation Status (Updated February 2026)

### ✅ Fully Implemented
- **iOS Push Notifications**: Working on iOS 15+ devices
- **Android Push Notifications**: Configured, requires app update for users
- **FCM HTTP v1 API**: Modern OAuth2-based authentication (replaced deprecated legacy API)
- **Database Triggers**: Auto-create notifications on gig/rehearsal/blockout INSERT
- **Webhook Integration**: Supabase webhook fires Edge Function on notification INSERT
- **Device Token Management**: Register/unregister tokens on login/logout

### Platform Requirements
| Platform | Min Version | Update Required |
|----------|-------------|-----------------|
| iOS | iOS 15+ | Yes (for UIBackgroundModes) |
| Android | API 21+ | Yes (for google-services.json) |
| Web | N/A | Not yet implemented |
| macOS | macOS 12+ | Not yet implemented |

---

## Firebase Configuration

### Required Supabase Secrets

Configure in **Supabase Dashboard → Edge Functions → Secrets**:

| Secret Name | Value | Source |
|-------------|-------|--------|
| `FIREBASE_PROJECT_ID` | `bandroadie-65b18` | Firebase Console → Project Settings → General |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Entire JSON file contents | Firebase Console → Project Settings → Service Accounts → Generate New Private Key |

### Firebase Console Setup

1. **Project**: `bandroadie-65b18`
2. **Apps Registered**:
   - iOS: `com.bandroadie.app` (Bundle ID)
   - Android: `com.bandroadie.app` (Package Name)

### Platform-Specific Configuration

#### iOS (`ios/Runner/Info.plist`)
```xml
<!-- Required for background push notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

#### iOS (`ios/Runner/AppDelegate.swift`)
```swift
// Register for remote notifications on launch
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
    if granted {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
```

#### Android (`android/app/google-services.json`)
- Download from Firebase Console → Project Settings → Android app
- Place in `android/app/google-services.json`

#### Android (`android/settings.gradle.kts`)
```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

#### Android (`android/app/build.gradle.kts`)
```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2"
}
```

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

### Edge Function: `send-push`

**Location:** `supabase/functions/send-push/index.ts`

**Trigger:** Database webhook fires on INSERT to `notifications` table

**Authentication:** FCM HTTP v1 API with OAuth2 service account authentication
- Generates JWT signed with service account private key (RS256)
- Exchanges JWT for short-lived access token via Google OAuth2
- Uses access token for FCM API calls

**Process:**
1. Receive webhook payload with notification record
2. Fetch FCM tokens from `device_tokens` for recipient user
3. Generate OAuth2 access token from service account key
4. Send individual FCM requests to each device token
5. Clean up invalid/unregistered tokens automatically
6. Log success/failure counts

**FCM Payload Structure:**
```json
{
  "message": {
    "token": "device_fcm_token",
    "notification": {
      "title": "Gig at Blue Note",
      "body": "Tony created a gig for MAR 17, 2026"
    },
    "data": {
      "notification_id": "uuid",
      "type": "gig_created",
      "band_id": "uuid",
      "click_action": "FLUTTER_NOTIFICATION_CLICK"
    },
    "apns": {
      "payload": {
        "aps": { "sound": "default", "badge": 1 }
      }
    },
    "android": {
      "priority": "high",
      "notification": {
        "sound": "default",
        "click_action": "FLUTTER_NOTIFICATION_CLICK"
      }
    }
  }
}
```

**Environment Variables:**
| Variable | Description |
|----------|-------------|
| `FIREBASE_PROJECT_ID` | Firebase project ID (e.g., `bandroadie-65b18`) |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Full JSON service account key (stringified) |
| `SUPABASE_URL` | Auto-provided by Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-provided by Supabase |

### Database Webhook

**Name:** `send_push_on_notification`
- **Table:** `notifications`
- **Event:** INSERT
- **Method:** POST
- **URL:** `https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/send-push`
- **Headers:** `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`

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
# Deploy the send-push function
npx supabase functions deploy send-push --project-ref nekwjxvgbveheooyorjo

# Set Firebase credentials (in Supabase Dashboard → Edge Functions → Secrets)
# FIREBASE_PROJECT_ID = bandroadie-65b18
# FIREBASE_SERVICE_ACCOUNT_KEY = <entire JSON file from Firebase Console>
```

**To get service account key:**
1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Download JSON file
4. Copy entire contents to `FIREBASE_SERVICE_ACCOUNT_KEY` secret

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

1. **Check Firebase secrets are set:**
   - Go to Supabase Dashboard → Edge Functions → Secrets
   - Verify `FIREBASE_PROJECT_ID` and `FIREBASE_SERVICE_ACCOUNT_KEY` exist

2. **Check Edge Function logs:**
   ```bash
   npx supabase functions logs send-push --project-ref nekwjxvgbveheooyorjo
   ```
   
   Common errors:
   - `Firebase not configured: missing FIREBASE_PROJECT_ID...` → Secrets not set
   - `Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY` → Invalid JSON in secret
   - `Failed to get access token` → Service account key is invalid or expired
   - `UNREGISTERED` → Device token is stale (auto-cleaned)

3. **Verify webhook is configured:**
   - Go to Supabase Dashboard → Database → Webhooks
   - Look for `send_push_on_notification` webhook on `notifications` table

4. **Check notification was created:**
   ```sql
   SELECT * FROM notifications 
   WHERE created_at > now() - interval '1 hour'
   ORDER BY created_at DESC;
   ```

5. **Check device has registered token:**
   ```sql
   SELECT * FROM device_tokens 
   WHERE user_id = 'recipient-user-id';
   ```

### iOS notifications not appearing

1. **Check Info.plist has UIBackgroundModes:**
   ```xml
   <key>UIBackgroundModes</key>
   <array>
       <string>fetch</string>
       <string>remote-notification</string>
   </array>
   ```

2. **Check iOS notification settings:**
   - Settings → Notifications → BandRoadie
   - Ensure "Allow Notifications" is ON
   - Enable Banners, Lock Screen, Notification Center

3. **Check Focus mode / Do Not Disturb** is not blocking notifications

4. **Test with app closed** (not in foreground)

### Android notifications not appearing

1. **Verify google-services.json exists:**
   - File: `android/app/google-services.json`
   - Must match package name `com.bandroadie.app`

2. **Verify Gradle plugin is applied:**
   - `android/settings.gradle.kts` has `com.google.gms.google-services`
   - `android/app/build.gradle.kts` applies the plugin

3. **Rebuild app after adding google-services.json**

### FCM Legacy API Error (404)

If you see `Not Found` or `404` errors in logs:
- The legacy FCM API (`fcm.googleapis.com/fcm/send`) was deprecated June 2024
- Solution: Use FCM HTTP v1 API with OAuth2 authentication (current implementation)

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
│   └── notification_preferences.dart       # Data model
├── notification_repository.dart            # Supabase data access + device token management
├── notification_preferences_controller.dart  # Riverpod state
├── notification_settings_screen.dart       # Settings UI
└── push_notification_service.dart          # FCM integration + foreground notifications

lib/features/auth/
└── auth_gate.dart                          # Initializes push service + registers token on login

lib/features/settings/
└── settings_screen.dart                    # Links to notification settings
```

### Backend (Supabase)
```
supabase/migrations/
├── 20260109_notifications.sql              # Base tables (existing)
├── 20260128_notification_categories.sql    # New preference columns
└── 20260128_notification_triggers.sql      # Auto-send triggers

supabase/functions/
└── send-push/
    └── index.ts                            # FCM HTTP v1 API delivery
```

### iOS Configuration
```
ios/Runner/
├── Info.plist                              # UIBackgroundModes for remote-notification
├── AppDelegate.swift                       # UNUserNotificationCenter registration
└── GoogleService-Info.plist                # Firebase iOS config (from Firebase Console)
```

### Android Configuration
```
android/
├── settings.gradle.kts                     # Google Services plugin declaration
├── build.gradle.kts                        # Buildscript classpath
└── app/
    ├── build.gradle.kts                    # Google Services plugin applied
    └── google-services.json                # Firebase Android config (from Firebase Console)
```

---

## Summary

This notification system is:
- **Lightweight**: Minimal code changes, no complex state management
- **Flexible**: Easy to add new notification types
- **Respectful**: Users control what they see via granular preferences
- **Reliable**: Degrades gracefully (failures don't break core app functionality)
- **Non-blocking**: Push delivery failures never gate writes

### Architecture Flow
```
1. User creates gig/rehearsal/blockout
        ↓
2. Database trigger (notify_band_members) fires
        ↓
3. Notification record inserted into `notifications` table
        ↓
4. Webhook (send_push_on_notification) fires
        ↓
5. Edge Function (send-push) called
        ↓
6. OAuth2 token generated from service account
        ↓
7. FCM HTTP v1 API sends to each device token
        ↓
8. Push notification appears on user's device
```

### Key Technical Decisions
1. **FCM HTTP v1 API** - Uses modern OAuth2 authentication instead of deprecated server keys
2. **Individual sends** - Each device gets its own FCM request (no multicast) for better error handling
3. **Auto-cleanup** - Invalid/unregistered tokens automatically deleted from `device_tokens`
4. **Webhook-triggered** - Edge Function fires on database INSERT, not API call
5. **Never blocks writes** - All triggers use `RETURN NEW` pattern

The implementation follows Band Roadie's architecture patterns (Riverpod, Repository, Supabase RLS) and maintains the app's brand voice in notification copy.
