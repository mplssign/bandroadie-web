# Engineer Report

## Feature Slug

notification-delivery-housekeeping

## Feature Title

Notification Delivery Housekeeping

## Goal

Clean up notification delivery infrastructure by removing zombie pg_cron jobs and uncommitted legacy code. Fix token registration to proactively delete stale device tokens on refresh, preventing duplicate push notifications. Update PROJECT_CONTEXT.md to accurately reflect current architecture.

## Architect Tasks Completed

- [x] Task 1 — Delete untracked `deliver-notifications/` directory
- [x] Task 2 — Create migration to fix `upsert_device_token` RPC with optional `p_old_token` parameter
- [x] Task 3 — Update `push_notification_service.dart` to track tokens in SharedPreferences and pass old token on refresh
- [x] Task 4 — Update `notification_repository.dart` to accept and pass `oldToken` parameter to RPC
- [x] Task 5 — Fix PROJECT_CONTEXT.md (update Edge Functions table, add `rehearsal_dates` to Events table)
- [x] Task 6 — Run `flutter analyze` (0 errors)
- [x] Task 7 — Generate git diff

## Files Created

- `supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql` — Migration that replaces `upsert_device_token` RPC with 4-parameter signature (added `p_old_token TEXT DEFAULT NULL`). When old token provided, deletes it device-scoped (user_id + fcm_token match) before upserting new token.

## Files Modified

- `lib/features/notifications/push_notification_service.dart:10` — Added SharedPreferences import
- `lib/features/notifications/push_notification_service.dart:152-207` — Modified `registerToken()` method to read/write last token from SharedPreferences (key: `last_fcm_token`). Passes old token to repository when token refresh detected. Updated onTokenRefresh listener with same pattern.
- `lib/features/notifications/notification_repository.dart:66-81` — Added optional `String? oldToken` parameter to `upsertDeviceToken()` method. Passes `p_old_token` to RPC via params map.
- `docs/agents/PROJECT_CONTEXT.md:158` — Added `rehearsal_dates` table to Events section
- `docs/agents/PROJECT_CONTEXT.md:253-268` — Updated Edge Functions table: changed function count from 11 to 10, removed `deliver-notifications` row, updated `send-push` description from "older arch" to "current production push delivery"

## Analyzer Results

**Command:** `flutter analyze lib`

**Result:** 0 errors, 4 pre-existing info-level deprecation warnings (unrelated to this implementation)

The 4 deprecation warnings are in setlist files (`new_setlist_screen.dart`, `setlist_detail_screen.dart`, `setlists_tab_content.dart`) which were not modified by this implementation. All warnings existed before our changes.

## Test Results

Not run — tests will be executed during QA phase per Verification Plan (Tier 2 tests require device testing and post-deployment verification)

## Verification

Manual steps performed:

- Verified `deliver-notifications/` directory was deleted from `supabase/functions/`
- Confirmed migration file created with correct timestamp format (20260705143000)
- Verified migration content matches Architect plan specification exactly (4-parameter signature, conditional DELETE)
- Confirmed SharedPreferences import added to push_notification_service.dart
- Confirmed client changes preserve backward compatibility (optional parameter defaults to null)
- Verified PROJECT_CONTEXT.md changes reflect correct architecture (send-push as current production)
- Ran `flutter analyze lib` and confirmed 0 errors
- Ran `dart format` on modified Dart files
- Generated complete git diff for Architect review

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

## Git Diff Summary

```
 docs/agents/PROJECT_CONTEXT.md                     |  6 ++--
 .../notifications/notification_repository.dart     | 35 +++++++++++-----------
 .../notifications/push_notification_service.dart   | 22 +++++++++++++-
 3 files changed, 41 insertions(+), 22 deletions(-)
```

**Modified files:**

- docs/agents/PROJECT_CONTEXT.md
- lib/features/notifications/notification_repository.dart
- lib/features/notifications/push_notification_service.dart

**Untracked files:**

- docs/features/notification-delivery-housekeeping/ (this report directory)
- supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql (new migration)

**Deleted:**

- supabase/functions/deliver-notifications/ (removed from filesystem, was never tracked)

All changes match the Architect plan specification. No files outside the plan's Files to Modify table were touched. The implementation is ready for QA testing and deployment according to the plan's Verification Plan and Ops Runbook.
