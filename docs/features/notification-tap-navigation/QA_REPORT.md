# QA Report

## Feature Slug

bug/notification-tap-navigation

## Feature Title

Notification Tap Navigation

## Final Verdict

**APPROVED**

## Validation Summary

Implementation matches Architect plan scope and completes all required tasks. Code-path analysis confirms terminated-state buffering works correctly, callback wiring order is safe, band switching uses existing logic without introducing new state management, and all async gaps are guarded with `context.mounted` checks. Model compatibility verified for both Gig and Rehearsal queries. All known accepted deviations are correctly implemented. Flutter analyzer passes with 0 errors.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected (auth_gate.dart, push_notification_service.dart)
- **Files created:** As expected (notification_navigation_handler.dart)
- **Files off-limits:** Not touched (main.dart, send-push Edge Function, app_shell.dart)

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

**Task verification:**

1. ✓ Create NotificationNavigationHandler — Complete at lib/features/notifications/notification_navigation_handler.dart
2. ✓ Modify PushNotificationService to accept structured data and buffer initial message — Complete with setter/buffer pattern
3. ✓ Wire handler in auth_gate.dart — Complete with mounted guard
4. ✗ Test all three app states — MANUAL REQUIRED (foreground, background, terminated)
5. ✗ Test all notification types — MANUAL REQUIRED (gig_created, potential_gig_created, rehearsal_created, blockout_created)
6. ✗ Test band context switching — MANUAL REQUIRED

## Behavior Verification

- **Validation method:** Code-path analysis only (device testing not performed)
- **Result:** Matches expected behavior per Architect plan

**Code-path analysis findings:**

1. **Terminated-state timing fix verified:**
   - `_pendingInitialMessage` buffer field added (push_notification_service.dart:51)
   - Initial message buffered in `initialize()` instead of immediately handled (line 104)
   - Setter flushes pending message exactly once when callback is assigned (lines 54-58)
   - No code path still calls `_handleNotificationOpen` for initial message
   - Guarantees cold-start tap is not dropped due to timing gap

2. **Callback wiring order verified:**
   - Callback assigned after `service.initialize()` in auth_gate.dart (line 180)
   - Mounted guard present in closure (line 181)
   - Context and ref safely captured from surrounding method scope

3. **Band switching uses existing logic:**
   - Calls `ref.read(activeBandProvider.notifier).selectBand(targetBand)` (notification_navigation_handler.dart:48)
   - No new band switching logic introduced
   - Known stale-state issue not worsened (same method as rest of app)

4. **Model/query compatibility verified:**
   - Gig query uses `SELECT *` with `gig_dates` join — matches `Gig.fromJson` requirements
   - Rehearsal query uses `SELECT *` with `rehearsal_dates` join — matches `Rehearsal.fromJson` requirements
   - Both queries filter by `id` and `band_id` using `.eq()` and `.maybeSingle()`

5. **Error handling verified:**
   - All async gaps followed by `context.mounted` checks (11 locations verified)
   - Network failures handled with try/catch and error snackbars
   - Entity-not-found cases handled gracefully
   - No-band-access cases handled with error snackbar and early return
   - Malformed foreground payloads handled with try/catch and silent drop (stale notifications)

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:** Notifications, Gigs, Rehearsals, Band switching, Auth/session
- **Regressions found:** None

**Rationale for LOW risk (downgrade from Architect's MEDIUM):**

- Implementation is minimal and isolated to notification tap path only
- All async lifecycle concerns properly handled with mounted guards
- Band switching uses existing `selectBand()` method without modification
- Error handling is defensive and graceful (snackbars, no crashes)
- Foreground payload decode wrapped in try/catch for backward compatibility
- No changes to notification delivery, permission flow, or drawer display logic
- Static analysis confirms no new analyzer errors introduced

**Systems impact verification:**

| System         | Expected Impact | Verification Result                                                                         |
| -------------- | --------------- | ------------------------------------------------------------------------------------------- |
| Gigs           | Affected        | Code path verified — fetches gig by ID, shows ViewGigDrawer with view-only mode             |
| Rehearsals     | Affected        | Code path verified — fetches rehearsal by ID, shows ViewRehearsalDrawer with view-only mode |
| Notifications  | Affected        | Tap handlers now route to navigation instead of no-op                                       |
| Band switching | Affected        | Uses existing selectBand() — no new logic                                                   |
| Auth/Session   | Unaffected      | Navigation occurs after AuthGate — confirmed by callback location in auth_gate.dart         |
| Routing        | Unaffected      | No changes to main.dart or app_shell.dart                                                   |
| Setlists       | Unaffected      | No notification types target setlists                                                       |
| Members/RBAC   | Unaffected      | Drawers opened view-only (canEdit: false) — no permission checks in handler                 |

## Database Safety

Not applicable — Client-side only, no migrations, no RLS changes, no RPC changes.

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors

**Pre-existing warnings (unrelated to this implementation):**

- 4 info warnings about deprecated `onReorder` and `axisAlignment` in setlist screens (lib/features/setlists/)

## Test Results

**Not run** — Device testing per Architect plan Tier 1 tests (1-9) cannot be performed in this QA session.

**MANUAL REQUIRED (must be performed before production deployment):**

1. PRE-DEPLOY TEST 1: FCM payload structure verification
2. PRE-DEPLOY TEST 2: Foreground notification tap (app open)
3. PRE-DEPLOY TEST 3: Background notification tap (app backgrounded)
4. PRE-DEPLOY TEST 4: Terminated notification tap (app force-quit)
5. PRE-DEPLOY TEST 4a: Cold-start tap timing verification (terminated-state buffer flush)
6. PRE-DEPLOY TEST 5: Rehearsal notification tap
7. PRE-DEPLOY TEST 6: Block-out notification tap (calendar navigation)
8. PRE-DEPLOY TEST 7: Band context switching
9. PRE-DEPLOY TEST 8: Error handling — entity deleted
10. PRE-DEPLOY TEST 9: Error handling — network failure

## Diff Safety Review

- **Secrets:** None found
- **Debug artifacts:** One intentional `debugPrint` for error logging (push_notification_service.dart:237) — acceptable
- **Unrelated changes:** None
- **Formatting churn:** None
- **Accidental deletions:** None

## Known Accepted Deviations

The following deviations from the original Architect plan are documented in ENGINEER_REPORT.md and are acceptable:

1. **Permissions handling:** `canEdit: false` hardcoded in drawer calls instead of checking `canEditGigs`/`canManageRehearsals` (properties don't exist in codebase). Matches existing codebase pattern.

2. **Band timezone retrieval:** Queried directly from Supabase instead of via `displayBandProvider` for reliability (provider field is nullable).

3. **View-only drawer from notifications:** Both gig and rehearsal drawers open with `canEdit: false` to avoid showing a dead Edit button. Users can navigate via calendar/home screens for full edit flow.

4. **Foreground payload decode guard:** Wrapped `jsonDecode(payload)` in try/catch to handle stale notifications from pre-upgrade app versions (non-JSON payloads). Silent drop with debug log on failure.

## Issues Found

None

## Required Manual Testing Before Merge

Before merging to main, the following manual device tests must be performed and results recorded:

1. **All three app states** (foreground, background, terminated) — verify notification tap navigates correctly in each state
2. **All notification types** (gig_created, potential_gig_created, rehearsal_created, blockout_created) — verify each navigates to correct destination
3. **Band context switching** — verify notification for Band B switches context from Band A before showing drawer
4. **Error cases** (entity deleted, network failure) — verify graceful error handling with snackbars and no crashes
5. **Cold-start timing** — verify terminated-state tap works reliably (buffered message flushed after callback assigned)

These tests are defined in ARCHITECT_PLAN.md Verification Plan (Tier 1 tests 1-9). Results must be documented before production deployment.

## QA Notes

**Strengths:**

- Minimal, isolated change — only affects notification tap path
- Defensive error handling throughout
- Backward compatibility for stale notifications (try/catch decode)
- Proper async lifecycle management (mounted guards everywhere)
- Code is readable and follows existing patterns

**Observations:**

- Band timezone query is duplicated in `_navigateToGig` and `_navigateToRehearsal` — minor code duplication, not critical
- `activeBandId` null check after band switching is somewhat defensive (band switch already validates), but adds safety

**Recommendation:**
Implementation is production-ready from code quality perspective. Manual device testing required to validate runtime behavior before merge.
