# Architect Plan: Notification Tap Navigation

## Feature Slug

`bug/notification-tap-navigation`

## Problem Summary

Tapping a push notification dismisses it without opening the app or navigating to the relevant item (gig, rehearsal, calendar). The FCM payload contains all necessary metadata (`notification_id`, `type`, `band_id`, `gig_id`, `rehearsal_id`, etc.), but the notification tap handlers are not wired to any navigation logic. Users tap notifications and nothing happens except dismissal.

## Root Cause

**Confidence: HIGH** (confirmed by direct code inspection)

The notification tap handling infrastructure exists but is completely disconnected:

1. **`PushNotificationService.onNotificationTap` callback is never set** — The callback property exists (line 47) and handlers call it (foreground line 218, background line 299, terminated line 90), but nothing in `auth_gate.dart` or `main.dart` sets this callback. When tapped, the callback is `null` and nothing happens.

2. **FCM payload structure mismatch** — The handlers extract `message.data['deep_link']` (lines 260, 298) but the actual FCM payload (confirmed in `supabase/functions/send-push/index.ts` lines 229-237) sends structured data instead:
   - `notification_id` (the notification table PK)
   - `type` (e.g., "gig_created", "rehearsal_created")
   - `band_id`
   - Plus all metadata fields (`gig_id`, `rehearsal_id`, etc.)

   There is no `deep_link` field in the FCM payload.

3. **Navigation infrastructure exists but is unused** — `ViewGigDrawer.show()` and `ViewRehearsalDrawer.show()` can display the correct UI, and `AppNotification.deepLink` getter already constructs deep link paths like `/gig/{gigId}`, `/rehearsal/{rehearsalId}`, `/calendar`. But nothing connects notification taps to this navigation.

**Primary failure layer:** Foreground, background, and terminated state tap handlers all fail because `onNotificationTap` is `null` and even if it were set, the FCM data is not structured as expected.

## Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` — FCM HTTP v1 API, notification types, copy patterns, webhook architecture
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md` — Permission flow (not directly relevant to tap handling)
- `docs/reference/notifications/notifications.md` — pg_cron architecture, delivery flow (not directly relevant to tap handling)

## Production Push Delivery Architecture (Architecture Gate Item 1)

**Confirmed delivery path:** `supabase/functions/send-push/index.ts` (webhook-triggered via pg_net)

**Verification:**
- Migration `20260220120000_secure_push_notification_trigger.sql` sets up AFTER INSERT trigger on `notifications` table
- Trigger calls `pg_net.http_post` to `send-push` Edge Function with `X-Internal-Secret` header
- No pg_cron batch delivery exists in production (no `deliver-notifications` function deployed)

**FCM `data` payload structure (lines 229-237 in `send-push/index.ts`):**
```typescript
data: {
  notification_id: notification.id,          // UUID
  type: notification.type,                   // e.g. "gig_created"
  band_id: notification.band_id,             // UUID
  click_action: 'FLUTTER_NOTIFICATION_CLICK',
  ...Object.fromEntries(
    Object.entries(notification.metadata || {}).map(([k, v]) => [k, String(v)])
  ),
}
```

**Metadata fields (stringified in FCM payload):**
- `gig_id` (for gig_created, potential_gig_created)
- `rehearsal_id` (for rehearsal_created)
- Other notification-type-specific fields

**Conclusion:** Single payload format. Navigation handler parses `data` map directly. No second format to handle.

## Existing System Analysis

**Current behavior:**

1. User creates a gig/rehearsal/block-out
2. Database trigger creates notification record
3. Webhook calls `send-push` Edge Function
4. Edge Function sends FCM payload with structured data to user's device(s)
5. Push notification appears on device
6. **User taps notification:**
   - **Foreground (app open):** `_showLocalNotification` displays it via `flutter_local_notifications`, tap handler extracts `payload` (the `deep_link` field) and calls `onNotificationTap?.call(payload)` → but `onNotificationTap` is `null` → nothing happens
   - **Background (app in background):** `FirebaseMessaging.onMessageOpenedApp` fires, `_handleNotificationOpen` extracts `message.data['deep_link']` and calls `onNotificationTap?.call(deepLink)` → but `onNotificationTap` is `null` and `deep_link` doesn't exist in payload → nothing happens
   - **Terminated (app closed):** `getInitialMessage()` returns the message, same handler as background → nothing happens

**Data flow gap:** FCM data → no parsing → null callback → no navigation

## Proposed Solution

**Minimal change: Wire notification tap to navigation without modifying FCM payload or notification creation.**

### Changes Required

1. **Add a notification navigation handler** (`lib/features/notifications/notification_navigation_handler.dart`)
   - Parse FCM `data` map to extract notification metadata
   - Switch on notification type to determine target (gig, rehearsal, calendar)
   - Ensure correct band context is selected before navigation
   - Fetch the entity (gig/rehearsal) by ID
   - Show the appropriate drawer (`ViewGigDrawer.show()`, `ViewRehearsalDrawer.show()`) or navigate to calendar tab
   - Handle errors gracefully (entity not found, network failure, no band access)

2. **Modify `PushNotificationService`** to accept structured notification data
   - Change `onNotificationTap` signature from `void Function(String? deepLink)?` to `void Function(Map<String, dynamic> data)?`
   - Update `_showLocalNotification` to pass full `message.data` as payload (JSON-encoded string)
   - Update `_handleNotificationOpen` to pass full `message.data` directly

3. **Wire handler in `auth_gate.dart`**
   - In `_registerPushToken()`, after `service.initialize()`, set `service.onNotificationTap = _handleNotificationTap`
   - Implement `_handleNotificationTap(Map<String, dynamic> data)` to call the navigation handler with context

4. **Buffer initial message to close terminated-state timing gap (Architecture Gate Item 2)**
   - Problem: `getInitialMessage()` is called in `PushNotificationService.initialize()` (line 88-91), which runs before `onNotificationTap` is assigned in `auth_gate.dart`. A cold-start tap would be silently dropped.
   - Solution: Add `Map<String, dynamic>? _pendingInitialMessage` field to `PushNotificationService`
   - In `initialize()`: if `initialMessage != null`, buffer it in `_pendingInitialMessage` instead of immediately calling `_handleNotificationOpen`
   - Add setter for `onNotificationTap` that flushes the pending message when callback is assigned:
     ```dart
     set onNotificationTap(void Function(Map<String, dynamic>)? callback) {
       _onNotificationTap = callback;
       if (_pendingInitialMessage != null && callback != null) {
         callback(_pendingInitialMessage!);
         _pendingInitialMessage = null;
       }
     }
     ```
   - When `auth_gate.dart` sets the callback, any buffered initial message is immediately processed

**Why this works:**

- FCM payload already includes all necessary data — no backend changes needed
- Navigation handler is band-context aware — switches band if notification is for non-selected band (respects existing band switching behavior, does not introduce new logic)
- Graceful degradation — if entity is deleted, user sees error; if network fails, user sees error; if user no longer has access to band, navigation is skipped with a snackbar
- Isolated change — only affects notification tap path, does not touch notification creation or delivery
- Terminated-state timing is guaranteed — initial message is buffered until callback is ready, ensuring cold-start taps always fire

## Database Impact

**Not applicable** — this is client-side only. No migrations, no RLS changes, no RPC changes.

## Flutter Architecture Changes

**New file:**

- `lib/features/notifications/notification_navigation_handler.dart` — Stateless helper that takes notification data + context, switches band if needed, fetches entity, shows drawer

**Modified files:**

- `lib/features/notifications/push_notification_service.dart`
  - Change `onNotificationTap` signature to accept `Map<String, dynamic>`
  - Update foreground and background handlers to pass full data map instead of extracting `deep_link`
- `lib/features/auth/auth_gate.dart`
  - Wire `service.onNotificationTap` to a new handler method `_handleNotificationTap`
  - Implement `_handleNotificationTap` to call `NotificationNavigationHandler.navigate(context, data)`

**Affected providers/controllers:**

- `activeBandProvider` — navigation handler will call `ref.read(activeBandProvider.notifier).selectBand(bandId)` if notification is for a different band
- `gigProvider` / `rehearsalProvider` — used to fetch entity by ID before showing drawer

**State changes:**

- Band selection may change if notification is for a non-selected band
- Navigation to gig/rehearsal drawer or calendar tab occurs

## Files to Create

| File                                                              | Justification                                                                                                                                                                                                   |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/notifications/notification_navigation_handler.dart` | Encapsulates all navigation logic. Keeps `push_notification_service.dart` focused on FCM integration. Single responsibility: parse notification data → determine target → switch band → fetch entity → show UI. |

## Files to Modify

| File                                                        | What changes                                                                                                                                                                                                                                                                                                        |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/notifications/push_notification_service.dart` | Change `onNotificationTap` callback signature to accept `Map<String, dynamic>` instead of `String?`. Update `_showLocalNotification` to JSON-encode full `message.data` and pass as payload. Update `_handleNotificationOpen` to pass full `message.data` map.                                                      |
| `lib/features/auth/auth_gate.dart`                          | After `service.initialize()` in `_registerPushToken()`, set `service.onNotificationTap = _handleNotificationTap`. Add method `_handleNotificationTap(Map<String, dynamic> data)` that calls the navigation handler. Requires `BuildContext` — use a `GlobalKey<NavigatorState>` or pass context via Riverpod state. |

## Files Off-Limits

| File                                    | Reason                                                                                                                                                                                                      |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                         | Init order must not change. Routing logic lives in `onGenerateRoute` and is pattern-based, not programmatic. Adding notification navigation there would violate separation of concerns.                     |
| `supabase/functions/send-push/index.ts` | FCM payload already contains all necessary data. Changing it would risk breaking existing foreground notification display and would require re-deploying the Edge Function.                                 |
| `lib/features/shell/app_shell.dart`     | Tab switching should not be modified for notification navigation. Navigation handler will use `currentTabProvider.notifier.setTab()` if targeting calendar, but no changes to `AppShell` itself are needed. |

## System Impact Map

| System                                 | Impact                                                                                                                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **Affected** — notification tap for gig notifications will fetch gig by ID and show `ViewGigDrawer`                                                                                          |
| Rehearsals                             | **Affected** — notification tap for rehearsal notifications will fetch rehearsal by ID and show `ViewRehearsalDrawer`                                                                        |
| Setlists / Catalog                     | **Unaffected** — no notification types target setlists                                                                                                                                       |
| Members / RBAC                         | **Unaffected** — band permissions are checked by drawer components (existing behavior)                                                                                                       |
| Auth / Session                         | **Unaffected** — navigation only occurs after user is authenticated (auth gate is already passed)                                                                                            |
| Routing                                | **Unaffected** — no changes to `main.dart` routing. Navigation uses existing `showModalBottomSheet` and tab switching.                                                                       |
| Notifications                          | **Affected** — notification tap path is entirely new behavior. All notification types (gig_created, potential_gig_created, rehearsal_created, blockout_created) will now navigate correctly. |
| Platform (iOS / Android / Web / macOS) | **Affected: iOS and Android only** — Web and macOS push notifications are not yet implemented (confirmed in PROJECT_CONTEXT.md). Changes are mobile-only.                                    |

## Regression Risk

**Level: MEDIUM**

**Rationale:**

- **Multiple app states affected:** Foreground, background, and terminated states all share the same navigation logic — a bug affects all three
- **Band context switching:** Navigation handler must switch bands if notification is for non-selected band. Known issue from PROJECT_CONTEXT.md: "Band switching does not fully reset band-scoped state" — this fix must not worsen that issue. Navigation handler will use existing `selectBand()` method, which already has stale-state problems, but will not introduce new switching logic.
- **Shared notification types:** All four notification types (gigs, potential gigs, rehearsals, block-outs) use the same tap handler — a logic error could break all types
- **Network dependency:** Fetching gig/rehearsal by ID requires network call — must handle failures gracefully

**Mitigation:**

- Navigation handler is stateless and testable
- Error handling is explicit (entity not found, network failure, permission denied)
- Graceful degradation — worst case is user sees an error snackbar, not a crash
- Band switching uses existing `selectBand()` — no new state management logic

## Engineer Task Breakdown

1. **Create `NotificationNavigationHandler`**
   - Accept `BuildContext`, `WidgetRef`, and `Map<String, dynamic> data` as parameters
   - Extract `type`, `band_id`, `gig_id`, `rehearsal_id` from data map
   - Implement `navigate()` method:
     - Check if `band_id` matches currently selected band; if not, call `ref.read(activeBandProvider.notifier).selectBand(bandId)`
     - Switch on `type`:
       - `gig_created`, `potential_gig_created`: Fetch gig by `gig_id`, show `ViewGigDrawer.show()`
       - `rehearsal_created`: Fetch rehearsal by `rehearsal_id`, show `ViewRehearsalDrawer.show()`
       - `blockout_created`: Call `ref.read(currentTabProvider.notifier).setTab(NavTabIndex.calendar)`
     - Handle errors: entity not found, network failure, user no longer has band access
   - Use `try/catch` with error snackbars for graceful failure

2. **Modify `PushNotificationService` to accept structured data and buffer initial message**
   - Add field: `Map<String, dynamic>? _pendingInitialMessage;`
   - Add backing field: `void Function(Map<String, dynamic>)? _onNotificationTap;`
   - Replace `onNotificationTap` property with a setter that flushes pending message:
     ```dart
     set onNotificationTap(void Function(Map<String, dynamic>)? callback) {
       _onNotificationTap = callback;
       if (_pendingInitialMessage != null && callback != null) {
         callback(_pendingInitialMessage!);
         _pendingInitialMessage = null;
       }
     }
     ```
   - In `initialize()`, replace immediate `_handleNotificationOpen(initialMessage)` call with buffer:
     ```dart
     final initialMessage = await _messaging.getInitialMessage();
     if (initialMessage != null) {
       _pendingInitialMessage = initialMessage.data;
     }
     ```
   - In `_showLocalNotification`:
     - Change `final deepLink = message.data['deep_link'] as String?;` to `final dataJson = jsonEncode(message.data);`
     - Pass `dataJson` as `payload` parameter to `_localNotifications.show()`
   - In `_initializeLocalNotifications`:
     - Change `onDidReceiveNotificationResponse` handler:
       ```dart
       final payload = response.payload;
       if (payload != null && _onNotificationTap != null) {
         final data = jsonDecode(payload) as Map<String, dynamic>;
         _onNotificationTap!(data);
       }
       ```
   - In `_handleNotificationOpen`:
     - Change `final deepLink = message.data['deep_link'] as String?;` to `final data = message.data;`
     - Change `onNotificationTap?.call(deepLink);` to `_onNotificationTap?.call(data);`
   - Add import: `import 'dart:convert';`

3. **Wire handler in `auth_gate.dart`**
   - In `_registerPushToken()`, after `await service.initialize();`, set the callback:
     ```dart
     service.onNotificationTap = (data) {
       if (mounted) {
         NotificationNavigationHandler.navigate(context, ref, data);
       }
     };
     ```
   - Add import: `import '../notifications/notification_navigation_handler.dart';`
   - **Note:** The setter will automatically flush any pending initial message from terminated state. No post-frame callback needed — the buffer in `PushNotificationService` ensures correct timing.

4. **Test all three app states**
   - Foreground: Open app, create gig as User B, tap notification on User A's device while app is open
   - Background: Open app, send to background, create gig as User B, tap notification on User A's device
   - Terminated: Close app completely, create gig as User B, tap notification on User A's device from lock screen

5. **Test all notification types**
   - Gig created (confirmed gig) → should open gig drawer
   - Potential gig created → should open gig drawer (potential gig is still a gig)
   - Rehearsal scheduled → should open rehearsal drawer
   - Block-out date created → should navigate to calendar tab

6. **Test band context switching**
   - User A is in Band 1, currently viewing Band 1
   - User B creates a gig in Band 2 (where User A is also a member)
   - User A taps notification → app should switch to Band 2, then show gig drawer

## Verification Plan

### Tier 1 — Pre-deployment (Client-Side Only — No Database Changes)

**All tests run locally on iOS/Android devices before committing.**

```
-- PRE-DEPLOY TEST 1: FCM payload structure verification
-- Verify that production FCM payloads contain the expected fields
-- Run on iOS Simulator or Android Emulator with Edge Function logs visible

1. Create a test gig as User B in Band 1
2. Observe Edge Function logs (supabase functions logs send-push)
3. Confirm payload includes:
   - data.notification_id (UUID)
   - data.type (e.g., "gig_created")
   - data.band_id (UUID)
   - data.gig_id (UUID)
   - data.click_action ("FLUTTER_NOTIFICATION_CLICK")
4. Confirm NO field named "deep_link" exists
```

```
-- PRE-DEPLOY TEST 2: Foreground notification tap (app open)
-- User A has app open, User B creates gig, notification appears, User A taps

1. Open app as User A (iOS or Android device)
2. Navigate to Dashboard
3. As User B, create a confirmed gig in shared band
4. Observe notification appears in foreground (flutter_local_notifications)
5. Tap the notification
6. Expected: Gig drawer opens, showing the created gig
7. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 3: Background notification tap (app backgrounded)
-- User A sends app to background, User B creates gig, User A taps from notification center

1. Open app as User A, then send to background (home button / app switcher)
2. As User B, create a confirmed gig in shared band
3. Notification appears in notification center
4. Tap notification from notification center
5. Expected: App opens to foreground, gig drawer opens
6. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 4: Terminated notification tap (app completely closed)
-- User A force-quits app, User B creates gig, User A taps from lock screen

1. Force quit app on User A's device (swipe up from app switcher)
2. As User B, create a confirmed gig in shared band
3. Notification appears on lock screen
4. Tap notification from lock screen
5. Expected: App launches, gig drawer opens after AuthGate passes
6. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 4a: Cold-start tap timing verification (Architecture Gate Item 2)
-- Verify that terminated-state tap works even with timing gap

1. Add debug logging to PushNotificationService.initialize() to log when _pendingInitialMessage is set
2. Add debug logging to onNotificationTap setter to log when pending message is flushed
3. Force quit app on User A's device
4. As User B, create a gig
5. Tap notification from lock screen
6. Expected: Logs show:
   - "initialize: buffered initial message with type=gig_created"
   - "onNotificationTap setter: flushing pending message"
   - Gig drawer opens
7. Actual: [record result]
8. Remove debug logging after verification
```

```
-- PRE-DEPLOY TEST 5: Rehearsal notification tap
-- Verify rehearsal notifications navigate correctly

1. Open app as User A
2. As User B, schedule a rehearsal in shared band
3. Tap notification (test in foreground or background state)
4. Expected: Rehearsal drawer opens
5. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 6: Block-out notification tap
-- Verify block-out notifications navigate to calendar tab

1. Open app as User A, navigate to Dashboard tab
2. As User B, create a block-out date in shared band
3. Tap notification (test in foreground or background state)
4. Expected: App navigates to Calendar tab
5. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 7: Band context switching
-- Verify notification for Band 2 switches context from Band 1

1. User A is member of Band 1 and Band 2
2. User A opens app, selects Band 1, navigates to Dashboard
3. As User B, create a gig in Band 2
4. User A taps notification
5. Expected: Band switcher changes to Band 2, gig drawer opens
6. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 8: Error handling — entity deleted
-- Verify graceful failure when gig/rehearsal is deleted before tap

1. As User B, create a gig in shared band
2. Notification is sent to User A
3. As User B, delete the gig (before User A taps)
4. User A taps notification
5. Expected: Error snackbar "Gig not found" or similar, no crash
6. Actual: [record result]
```

```
-- PRE-DEPLOY TEST 9: Error handling — network failure
-- Verify graceful failure when network is unavailable

1. As User B, create a gig in shared band
2. User A receives notification
3. User A disconnects from network (airplane mode)
4. User A taps notification
5. Expected: Error snackbar or loading timeout, no crash
6. Actual: [record result]
```

### Tier 2 — Post-deployment

**Client-side changes only — no backend deployment. Run after merging to main and deploying to production.**

```
-- POST-DEPLOY TEST 1: Production notification delivery (end-to-end)
-- Full flow from gig creation to navigation in production environment

1. On production app, User A logs in (iOS or Android)
2. User B creates a gig in shared band
3. Observe notification appears on User A's device
4. Tap notification
5. Expected: Gig drawer opens
6. Actual: [record result]
```

```
-- POST-DEPLOY TEST 2: iOS badge clearing
-- Verify app icon badge clears when notification is tapped and app opens

1. On iOS device, User A receives notification while app is closed
2. Observe badge count on app icon (should be >0)
3. Tap notification
4. App opens, gig drawer appears
5. Expected: Badge count clears to 0
6. Actual: [record result]
```

```
-- POST-DEPLOY TEST 3: Regression check — notification delivery still works
-- Verify that notification tap changes did not break notification delivery

1. User A opens app, enables notifications in Settings
2. User B creates gig, rehearsal, block-out date
3. Expected: User A receives all three notifications
4. Actual: [record result]
```

## QA Regression Areas

**Primary:**

- Notification tap navigation for all notification types (gigs, potential gigs, rehearsals, block-outs)
- All three app states: foreground, background, terminated
- Band context switching when notification is for non-selected band

**Regression concerns:**

- **Notification delivery** — Verify that notifications still arrive correctly (not affected by tap handling changes)
- **Foreground notification display** — Verify that foreground notifications still display via `flutter_local_notifications` (only payload encoding changed)
- **Permission flow** — Verify that notification permission request still works (no changes to permission code)
- **Badge clearing** — Verify that iOS badge count still clears when app opens (existing behavior, should not regress)
- **Drawer display** — Verify that gig/rehearsal drawers display correctly when opened via notification (uses existing `ViewGigDrawer.show()` and `ViewRehearsalDrawer.show()`, but test with notification-sourced data)
- **Calendar navigation** — Verify that block-out notifications navigate to Calendar tab without breaking tab state

## Rollout / Migration Strategy

Not applicable — client-side change only, no data migration, no backend deployment.

**Deployment:**

1. Merge PR to `main`
2. Deploy to iOS App Store and Google Play Store via standard release process
3. Users receive update
4. Notification tap navigation works immediately for all new and existing notifications

**Backward compatibility:** Not applicable — mobile apps are version-locked to the installed build.

## Out of Scope

**Explicitly not included in this fix:**

- Web push notification support — Web push is not yet implemented (confirmed in PROJECT_CONTEXT.md)
- macOS push notification support — macOS push is not yet implemented (confirmed in PROJECT_CONTEXT.md)
- In-app notification center — No UI for viewing notification history (future feature)
- Deep link routing via `main.dart` — Navigation uses existing modal/drawer display, not route-based navigation
- Notification read state — Tapping a notification does not mark it as read (future feature)
- FCM payload changes — No changes to Edge Function or notification creation logic
- Band stale-state fix — Known issue with band switching is not addressed by this fix (separate issue)
