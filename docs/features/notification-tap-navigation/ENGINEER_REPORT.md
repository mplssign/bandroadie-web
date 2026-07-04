# Engineer Report

## Feature Slug

bug/notification-tap-navigation

## Feature Title

Notification Tap Navigation

## Goal

Wire push notification tap handlers to navigate to the appropriate screen (gig drawer, rehearsal drawer, or calendar tab) when a user taps a notification. The issue was that notification taps would dismiss the notification without navigating anywhere. The fix implements proper navigation while preserving the terminated-state timing guarantee by buffering the initial message until the callback is assigned.

## Architect Tasks Completed

- [x] Task 1: Create NotificationNavigationHandler — COMPLETED
- [x] Task 2: Modify PushNotificationService to accept structured data and buffer initial message — COMPLETED
- [x] Task 3: Wire handler in auth_gate.dart — COMPLETED
- [x] Task 4: Test all three app states — NOT EXECUTED (no device testing performed)
- [x] Task 5: Test all notification types — NOT EXECUTED (no device testing performed)
- [x] Task 6: Test band context switching — NOT EXECUTED (no device testing performed)

## Files Created

- `lib/features/notifications/notification_navigation_handler.dart` — Stateless navigation handler that parses FCM data, switches band context if needed, fetches entity by ID, and shows appropriate drawer or navigates to calendar tab

## Files Modified

- `lib/features/notifications/push_notification_service.dart` — Changed `onNotificationTap` to accept `Map<String, dynamic>`, added `_pendingInitialMessage` buffering, added setter that flushes pending message, updated foreground handler to JSON-encode full data map, updated background/terminated handlers to pass full data map. **Implementation Gate revision:** Wrapped `jsonDecode(payload)` in try/catch to handle stale notifications with non-JSON payloads.
- `lib/features/auth/auth_gate.dart` — Wired `service.onNotificationTap` callback after `service.initialize()` to call `NotificationNavigationHandler.navigate()`
- `lib/features/notifications/notification_navigation_handler.dart` — **Implementation Gate revision:** Changed `canEdit` parameter from permissions-based value to `false` in both gig and rehearsal drawer calls; removed unused `band_permissions_provider.dart` import

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors related to this implementation

Pre-existing warnings in unrelated files:

- 4 info warnings about deprecated `onReorder` and `axisAlignment` in setlist screens (not introduced by this implementation)

## Test Results

Not run — No device testing performed per Engineer role scope. The implementation is complete and passes static analysis. QA will perform device testing per the Architect plan verification tests.

## Verification

Manual steps performed:

- Read all required files before implementation
- Verified git preconditions (branch, commit, status)
- Implemented exactly per Architect plan scope
- Ran `flutter analyze` and resolved all errors in modified files
- Verified file structure matches plan requirements

## Deviations From Architect Plan

### 1. Permissions Handling (Minor)

**Plan:** Use `permissions.canManageGigs` and `permissions.canManageRehearsals`

**Actual:** Used `permissions.canEditGigs` for both gigs and rehearsals

**Justification:** The `BandPermissions` class does not have `canManageGigs` or `canManageRehearsals` properties. Existing code in `calendar_tab_content.dart:264` and `home_screen.dart:276` uses `canEditGigs` for both gigs and rehearsals. This is the established pattern in the codebase.

### 2. Band Timezone Retrieval (Minor)

**Plan:** Use `ref.read(displayBandProvider).band?.timezone`

**Actual:** Query band timezone directly from Supabase

**Justification:** The `displayBandProvider` was not accessible without importing additional files, and the band field is nullable which required additional null handling. Directly querying the band timezone from Supabase by `activeBandId` is more reliable and matches the pattern used in the navigation handler for fetching gig/rehearsal entities.

### 3. View-Only Drawer from Notifications (Implementation Gate Revision)

**Original Implementation:** Passed `canEdit` from permissions with no-op `onEdit` callback

**Revised Implementation:** Pass `canEdit: false` to both gig and rehearsal drawers

**Justification:** The `canEdit` flag only gates the Edit button in both drawers (confirmed via code inspection — no RSVP or other user actions are gated). The original approach showed a visible Edit button that did nothing when tapped. A hidden control is better than a dead one. Users tapping notifications see a view-only drawer; users who want to edit can navigate via the calendar/home screens where the full edit flow is available.

### 4. Foreground Payload Decode Guard (Implementation Gate Revision)

**Original Implementation:** `jsonDecode(payload)` called unguarded in `onDidReceiveNotificationResponse`

**Revised Implementation:** Wrapped in try/catch with `debugPrint` and early return on failure

**Justification:** Stale tray notifications from pre-upgrade app versions can carry non-JSON payloads. The decode happens in a plugin callback with no context available for user-facing errors. On decode failure, the tap is silently dropped (no crash, no snackbar) and logged to debug console. This is safer than an uncaught exception.

## Blockers Encountered

None — All implementation requirements were met within the Architect plan scope.

## Ready For QA

Yes

The implementation is complete and passes static analysis. All files specified in the Architect plan were created or modified as required. The notification tap path now:

1. Buffers terminated-state initial messages until callback is assigned (timing fix)
2. Parses full FCM data map (not a `deep_link` field)
3. Switches band context if notification is for non-selected band
4. Fetches entity by ID from Supabase
5. Shows appropriate drawer or navigates to calendar tab
6. Handles errors gracefully with snackbars

QA should perform device testing per the Architect plan verification tests to validate all three app states (foreground, background, terminated), all notification types (gig_created, potential_gig_created, rehearsal_created, blockout_created), and band context switching.
