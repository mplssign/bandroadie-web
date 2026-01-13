# Notification System Setup Guide

This document describes how to complete the notification system setup for Band Roadie.

## 1. Firebase Project Setup

### Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use an existing one
3. Enable Cloud Messaging in Project Settings

### Configure Platforms

#### iOS
1. In Firebase Console, add an iOS app with bundle ID: `com.bandroadie.app`
2. Download `GoogleService-Info.plist`
3. Add to `ios/Runner/` directory
4. Add to Xcode project (drag into Runner target)
5. In `ios/Runner/Info.plist`, add:
   ```xml
   <key>FirebaseAppDelegateProxyEnabled</key>
   <false/>
   ```

#### Android  
1. In Firebase Console, add an Android app with package: `com.bandroadie.app`
2. Download `google-services.json`
3. Add to `android/app/` directory
4. In `android/build.gradle.kts`, add to buildscript dependencies:
   ```kotlin
   classpath("com.google.gms:google-services:4.4.0")
   ```
5. In `android/app/build.gradle.kts`, add at bottom:
   ```kotlin
   apply(plugin = "com.google.gms.google-services")
   ```

#### Web
1. In Firebase Console, add a web app
2. Copy the config values to `web/firebase-messaging-sw.js`
3. Replace the placeholder values with your actual Firebase config

#### macOS
1. Download `GoogleService-Info.plist` (same as iOS)
2. Add to `macos/Runner/` directory
3. Add to Xcode project

## 2. Run Database Migration

Apply the Supabase migration to create notification tables:

```sql
-- Run the contents of:
-- supabase/migrations/20260109_notifications.sql
```

Or using Supabase CLI:
```bash
supabase db push
```

## 3. Generate Firebase Options

Run FlutterFire CLI to generate platform configs:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This creates `lib/firebase_options.dart` with platform-specific configs.

## 4. Initialize in main.dart

Update `lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/notifications/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // ... rest of initialization
  
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
```

## 5. Register FCM Token on Login

After successful authentication, register the device token:

```dart
// In auth success handler
final pushService = ref.read(pushNotificationServiceProvider);
await pushService.initialize();

// Request permission with soft prompt first
final granted = await pushService.requestPermission();
if (granted) {
  await pushService.registerToken();
}
```

## 6. Unregister on Logout

When user logs out, unregister the device token:

```dart
// In logout handler
final pushService = ref.read(pushNotificationServiceProvider);
await pushService.unregisterToken();
```

## 7. Add Notification Bell to App Bar

Add the notification bell widget to your app bar:

```dart
import 'features/notifications/widgets/notification_bell.dart';

AppBar(
  actions: [
    const NotificationBell(),
    // ... other actions
  ],
)
```

## 8. Backend Integration

Push notifications are sent from the backend (Supabase Edge Functions).

### Create Edge Function for Sending Notifications

Create `supabase/functions/send-notification/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { recipientUserId, type, title, body, metadata } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // 1. Store notification in database
  await supabase.from('notifications').insert({
    recipient_user_id: recipientUserId,
    type,
    title,
    body,
    metadata,
  })
  
  // 2. Get user's device tokens
  const { data: tokens } = await supabase
    .from('device_tokens')
    .select('fcm_token')
    .eq('user_id', recipientUserId)
  
  // 3. Check user preferences
  const { data: prefs } = await supabase.rpc(
    'get_or_create_notification_preferences'
  )
  
  if (!prefs?.push_enabled) {
    return new Response(JSON.stringify({ sent: false, reason: 'push_disabled' }))
  }
  
  // 4. Send FCM push to each device
  // Use Firebase Admin SDK or HTTP API
  // ...
  
  return new Response(JSON.stringify({ sent: true }))
})
```

## File Structure

```
lib/features/notifications/
├── models/
│   ├── app_notification.dart       # Notification data model
│   ├── notification_preferences.dart # User preferences model  
│   └── notification_type.dart       # Notification type enum
├── widgets/
│   ├── notification_bell.dart       # App bar bell with badge
│   └── notification_card.dart       # Activity feed item
├── notification_controller.dart     # Riverpod state management
├── notification_repository.dart     # Supabase data access
├── notifications_screen.dart        # Activity feed screen
├── notification_preferences_screen.dart # Settings screen
└── push_notification_service.dart   # FCM integration

supabase/
├── migrations/
│   └── 20260109_notifications.sql   # Database schema
└── functions/
    └── send-notification/           # Backend push sender (TODO)

web/
└── firebase-messaging-sw.js         # Web push service worker
```

## Testing Checklist

- [ ] Firebase project created and configured
- [ ] GoogleService-Info.plist added (iOS/macOS)
- [ ] google-services.json added (Android)
- [ ] firebase-messaging-sw.js configured (Web)
- [ ] Database migration applied
- [ ] FlutterFire CLI configured
- [ ] Firebase initialized in main.dart
- [ ] Token registration working on login
- [ ] Notification bell appears in app bar
- [ ] Activity feed loads notifications
- [ ] Notification preferences can be toggled
- [ ] Push notifications received (requires backend)
