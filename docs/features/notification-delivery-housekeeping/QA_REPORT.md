# QA Report

## Feature Slug

`notification-delivery-housekeeping`

## Feature Title

Notification Delivery Housekeeping

## Final Verdict

**APPROVED**

## Validation Summary

Validated implementation against Architect plan via code-path analysis. All seven Architect tasks completed. Migration correctly implements device-scoped stale token cleanup with proper RBAC guardrails (SECURITY DEFINER + SET search_path). Client changes properly track FCM tokens in SharedPreferences and pass old token on refresh. PROJECT_CONTEXT.md accurately reflects current architecture. Formatting-only changes verified as semantic no-ops. Deployment sequencing requirement confirmed: migration must be applied before new client code is released.

## Architect Scope Review

- **Scope adherence**: compliant
- **Files modified**: as expected (3 tracked files modified, 1 migration created, 1 directory deleted)
- **Files off-limits**: not touched (send-push/index.ts, secure_push_notification_trigger migration, original notifications migration all untouched)

**Files in scope:**

- ✅ `lib/features/notifications/push_notification_service.dart` — SharedPreferences tracking added
- ✅ `lib/features/notifications/notification_repository.dart` — optional oldToken parameter added
- ✅ `docs/agents/PROJECT_CONTEXT.md` — Edge Functions table corrected, rehearsal_dates added
- ✅ `supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql` — new migration created
- ✅ `supabase/functions/deliver-notifications/` — untracked directory deleted (verified absent)

**Out of scope verification:**

- ✅ `supabase/functions/send-push/index.ts` — NOT modified (off-limits, correctly avoided)
- ✅ `supabase/migrations/20260220120000_secure_push_notification_trigger.sql` — NOT modified (off-limits)
- ✅ `supabase/migrations/20260109_notifications.sql` — NOT modified (correctly created new migration instead of editing original)

## Completeness Check

- **All Architect tasks implemented**: yes
- **Missing tasks**: none

**Task completion verification:**

1. ✅ Task 1 — Delete untracked `deliver-notifications/` directory
   - Verified: `ls supabase/functions/ | grep deliver-notifications` returns empty

2. ✅ Task 2 — Create migration to fix `upsert_device_token` RPC
   - File: `supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql`
   - DROP statement targets old 3-param signature: `DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT, TEXT);`
   - New function has 4 params: p_fcm_token, p_platform, p_device_name, p_old_token (last param DEFAULT NULL)
   - Conditional DELETE logic present: only fires when `p_old_token IS NOT NULL`
   - Device-scoped DELETE: `WHERE user_id = auth.uid() AND fcm_token = p_old_token`
   - SECURITY DEFINER + SET search_path = public present (RBAC guardrail compliance)

3. ✅ Task 3 — Update push_notification_service.dart
   - SharedPreferences import added (line 10)
   - registerToken() reads last token from SharedPreferences (line 157)
   - Passes old token when token differs (lines 174-175)
   - Saves current token after successful registration (line 184)
   - onTokenRefresh listener updated with same pattern (lines 188-203)

4. ✅ Task 4 — Update notification_repository.dart
   - Optional `String? oldToken` parameter added to upsertDeviceToken() (line 70)
   - Parameter passed to RPC via params map: `'p_old_token': oldToken` (line 78)

5. ✅ Task 5 — Fix PROJECT_CONTEXT.md
   - Edge Functions table: "All 11 deployed functions" → "All 10 deployed functions" (line 253)
   - deliver-notifications row removed from table (function will be decommissioned per Ops Runbook)
   - send-push description changed from "older arch" to "current production push delivery" (line 267)
   - rehearsal_dates added to Events section (line 158)

6. ✅ Task 6 — Run `flutter analyze`
   - Command executed: `flutter analyze lib`
   - Result: 0 errors, 4 pre-existing deprecation warnings in setlist files (not modified by this implementation)

7. ✅ Task 7 — Generate git diff
   - Diff captured in Engineer report

## Behavior Verification

- **Validation method**: code-path analysis
- **Result**: matches expected behavior

**Feature-specific verification (from session brief):**

### 1. Migration Correctness ✅

**Multi-device same-platform support preserved:**

- DELETE logic is device-scoped, not platform-wide
- Deletion only occurs when `p_old_token IS NOT NULL` (lines 23-27)
- Scope: `WHERE user_id = auth.uid() AND fcm_token = p_old_token`
- Multi-device scenario (e.g., user with iPhone + iPad both on iOS): each device has unique token, only the specific old token from a given device is deleted when that device's token refreshes
- Platform-wide deletion avoided: no `WHERE platform = p_platform` without token match

**RBAC guardrails compliance:**

- ✅ SECURITY DEFINER present (line 16)
- ✅ SET search_path = public present (line 17)
- ✅ DROP targets old 3-param signature: `DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT, TEXT);` (line 5)

**RPC logic correctness:**

- Conditional DELETE only fires when old token provided (line 23)
- DELETE scoped to user_id + fcm_token (device-scoped, not platform-wide)
- Upsert follows DELETE (no race condition — single transaction)
- RETURNING clause correctly returns new token_id

### 2. Client Null-Path Equivalence ✅

When `oldToken` is null (first run after update, fresh install, or no token change):

- SharedPreferences read: `prefs.getString('last_fcm_token')` returns null
- oldToken computed as null: `(lastToken != null && lastToken != token) ? lastToken : null` evaluates to null
- RPC call includes: `'p_old_token': null`
- RPC conditional DELETE does not fire: `IF p_old_token IS NOT NULL THEN` skips DELETE block
- Upsert proceeds as before (no deletion)
- SharedPreferences write: `prefs.setString('last_fcm_token', token)` stores token for next run

**Behavioral equivalence confirmed:** apart from SharedPreferences read/write (side effects with no semantic impact on registration) and the RPC params map gaining `'p_old_token': null` (ignored by RPC), the flow is identical to pre-change behavior.

### 3. Known Formatting Deviations ✅

**All formatting changes verified as semantic no-ops:**

**notification_repository.dart:**

- Lines 48-52 (`markAsRead`): Reformatted `.update().eq()` chain from multi-line to inline — semantic no-op ✅
- Lines 100-116 (`updatePreferences`): Reformatted `.from().update().eq()` chain — semantic no-op ✅

**push_notification_service.dart:**

- Lines 254-257: Split long debugPrint into multi-line string — semantic no-op ✅

**PROJECT_CONTEXT.md:**

- Table alignment changes throughout (whitespace-only) — semantic no-op ✅

**Conclusion:** All formatting changes are purely whitespace/reflow adjustments with zero semantic impact. No logic altered by dart format.

### 4. Deployment Sequencing Risk ✅

**Understanding verified from code:**

**Current state (before deployment):**

- Old RPC signature: `upsert_device_token(TEXT, TEXT, TEXT)` (3 params)
- Old client: calls with params `{ p_fcm_token, p_platform, p_device_name }` (3 params)

**After migration (new RPC deployed):**

- New RPC signature: `upsert_device_token(TEXT, TEXT, TEXT DEFAULT NULL, TEXT DEFAULT NULL)` (4 params, last 2 default NULL)
- Old client: calls with 3 params → PostgREST matches to 4-param function, uses defaults for missing params ✅
- New client: calls with 4 params → PostgREST matches perfectly ✅

**If new client deployed BEFORE migration:**

- New client: calls with params `{ p_fcm_token, p_platform, p_device_name, p_old_token }` (4 params)
- Old RPC: signature has 3 params
- PostgREST: cannot match 4-param call to 3-param function
- Result: PGRST202 error "Could not find the function..." → token registration fails ❌

**CRITICAL DEPLOYMENT SEQUENCING REQUIREMENT:**

🚨 **The migration MUST be applied to production (via `supabase db push`) BEFORE any app build containing this client code is released to users.** 🚨

**Safe deployment sequence:**

1. Apply migration to production (`supabase db push`)
2. Verify RPC replacement via POST-DEPLOY TEST 1 (see Architect plan)
3. Execute Ops Runbook Part B (unschedule cron, delete function, remove secret)
4. Verify production delivery still works (Ops Runbook B5)
5. Release app builds with new client code to App Store / Google Play
6. QA runs device-dependent verification (Tier 2 POST-DEPLOY TEST 2)

**Backward compatibility:** Migration can be deployed before new client code. Old clients (3-param calls) will continue to work against new RPC (4-param with defaults).

**Forward compatibility:** New client code CANNOT be deployed before migration. New clients (4-param calls) will fail against old RPC (3-param).

### 5. Docs Diff ✅

**PROJECT_CONTEXT.md changes match plan exactly:**

- ✅ Line 253: Function count updated from "All 11 deployed functions" to "All 10 deployed functions"
- ✅ Line 264-268: deliver-notifications row removed from Edge Functions table (function will be decommissioned)
- ✅ Line 267: send-push description changed from "webhook-triggered, older arch" to "current production push delivery"
- ✅ Line 158: rehearsal_dates added to Database Tables → Events section

**Additional changes in PROJECT_CONTEXT.md:**

- Table formatting alignment adjustments throughout (whitespace-only, semantic no-op)

**No other files in docs/ modified.** ✅

### 6. Scope Police ✅

**All changes within approved scope:**

Modified tracked files (all in Files to Modify table):

- docs/agents/PROJECT_CONTEXT.md ✅
- lib/features/notifications/notification_repository.dart ✅
- lib/features/notifications/push_notification_service.dart ✅

Created files (expected per plan):

- supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql ✅
- docs/features/notification-delivery-housekeeping/ (feature docs directory) ✅

Deleted files (expected per plan):

- supabase/functions/deliver-notifications/ (untracked directory) ✅

**Files Off-Limits verification (none touched):**

- supabase/functions/send-push/index.ts ✅
- supabase/migrations/20260220120000_secure_push_notification_trigger.sql ✅
- supabase/migrations/20260109_notifications.sql ✅ (correctly created new migration instead of editing original)

**No architectural patterns changed.** ✅
**No opportunistic refactoring.** ✅
**No dependencies added.** ✅

## Regression Check

- **Risk level**: MEDIUM (matches Architect plan assessment)
- **Systems reviewed**: Notifications, Platform (iOS/Android/Web/macOS), Device token registration, Push delivery
- **Regressions found**: none

**System-by-system regression review:**

| System                               | Impact       | Regression Risk Assessment                                                                                                          |
| ------------------------------------ | ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                 | unaffected   | No regression — notification creation unchanged                                                                                     |
| Rehearsals                           | unaffected   | No regression — notification creation unchanged                                                                                     |
| Setlists / Catalog                   | unaffected   | No regression — no changes in this area                                                                                             |
| Members / RBAC                       | unaffected   | No regression — RLS policies unchanged                                                                                              |
| Auth / Session                       | unaffected   | No regression — auth flow unchanged                                                                                                 |
| Routing                              | unaffected   | No regression — no routing changes                                                                                                  |
| **Notifications**                    | **affected** | **Low regression risk** — Zombie delivery path removed (was failing), production path (send-push) untouched, token cleanup improved |
| **Platform (iOS/Android/Web/macOS)** | **affected** | **Low regression risk** — Client token registration updated with SharedPreferences tracking, minimal change scope                   |

**Specific regression safeguards:**

1. **Notification delivery path unchanged**: send-push Edge Function (production delivery) not modified
2. **Database triggers unchanged**: on_notification_inserted trigger not modified
3. **RPC backward compatible**: Old clients (3-param calls) work against new RPC (4-param with defaults)
4. **Client changes minimal**: SharedPreferences usage already established pattern in codebase (NotificationPermissionService)
5. **Multi-device support preserved**: Device-scoped deletion, not platform-wide
6. **Fallback mechanism remains**: send-push auto-cleanup of UNREGISTERED tokens (lines 291-296 per plan) still active
7. **No setState after async gaps**: Client code properly awaits async operations, no mounted guards required (no widget lifecycle interaction)
8. **No controller disposal issues**: No new controllers introduced

**Medium risk factors (mitigated):**

- Token registration is critical path (but changes are conservative and backward compatible)
- SharedPreferences I/O could fail (but already in use elsewhere, proven pattern)
- RPC logic error could break token cleanup (but migration verified correct, POST-DEPLOY tests will catch issues)

**Mitigation in place:**

- Backward compatibility preserves old client functionality
- Ops runbook includes verification steps after each deletion
- send-push auto-cleanup remains as fallback if RPC/client fails
- flutter analyze passes (no compilation errors)
- Device testing deferred to post-deployment per Verification Plan

## Database Safety

**Verified**

**Migration safety checklist:**

1. ✅ Migration matches Architect plan
   - RPC signature change exactly as specified
   - DELETE logic device-scoped as required
   - No unintended destructive behavior

2. ✅ RLS policies do not self-reference
   - No RLS policy changes in this migration
   - Existing device_tokens RLS policies not affected

3. ✅ No privilege escalation
   - SECURITY DEFINER used appropriately for user-scoped operation
   - SET search_path = public prevents search path attacks
   - auth.uid() used for user identity (standard pattern)

4. ✅ No unintended cascade or destructive behavior
   - DELETE scoped to user_id + fcm_token (device-specific)
   - No CASCADE behavior
   - No platform-wide or band-wide deletion

5. ✅ RPC function signature matches Dart client calls
   - Client passes: `{ p_fcm_token, p_platform, p_device_name, p_old_token }`
   - RPC signature: `(p_fcm_token TEXT, p_platform TEXT, p_device_name TEXT DEFAULT NULL, p_old_token TEXT DEFAULT NULL)`
   - Parameter names match exactly ✅
   - Parameter order matches ✅
   - PostgREST will match successfully ✅

6. ✅ Migration content matches claimed behavior
   - Header comment: "Cleanup stale device tokens on registration"
   - Behavior: DELETE old token when provided, then upsert new token
   - Logic matches description ✅

**SQL syntax validation:**

- DROP FUNCTION IF EXISTS syntax correct
- CREATE OR REPLACE FUNCTION syntax correct
- DECLARE block syntax correct
- IF...THEN...END IF syntax correct
- DELETE with WHERE clause correct
- INSERT...ON CONFLICT...DO UPDATE correct
- RETURNING clause correct

**Transactional safety:**

- All operations within single function body (implicit transaction)
- DELETE before INSERT (no partial state)
- RETURNING ensures caller receives token_id

## Analyzer Results

**Command:** `flutter analyze lib`

**Result:** 0 errors

**Warnings:** 4 pre-existing info-level deprecation warnings in setlist files (unrelated to this implementation)

```
info • 'onReorder' is deprecated and shouldn't be used. • lib/features/setlists/new_setlist_screen.dart:984:13
info • 'axisAlignment' is deprecated and shouldn't be used. • lib/features/setlists/setlist_detail_screen.dart:1716:29
info • 'onReorder' is deprecated and shouldn't be used. • lib/features/setlists/setlist_detail_screen.dart:2295:23
info • 'onReorder' is deprecated and shouldn't be used. • lib/features/setlists/setlists_tab_content.dart:511:25
```

**Analysis:** All warnings existed before implementation. Modified files (notification_repository.dart, push_notification_service.dart) introduce zero new warnings or errors. Analyzer validation passes.

## Test Results

**Not run** — Device-dependent verification (token refresh behavior, multi-device, push delivery) deferred to post-deployment per Architect plan Verification Plan (Tier 2 tests require physical device or emulator and production database access).

**Post-deployment testing required (per plan):**

- POST-DEPLOY TEST 1: Verify RPC replacement (SQL query)
- POST-DEPLOY TEST 2: End-to-end token cleanup test (device test)
- POST-DEPLOY TEST 3: Production data sanity check (SQL query)
- POST-DEPLOY TEST 4: Verify send-push still works (SQL + function logs)

**QA regression testing (post-deployment):**

- Token registration on iOS/Android
- Token refresh on device
- Multiple devices same platform
- No duplicate push notifications
- Gig/rehearsal/blockout notification creation
- Notification preference filtering

## Diff Safety Review

- **Secrets**: none found ✅
- **Debug artifacts**: none found ✅
- **Unrelated changes**: formatting-only changes verified as semantic no-ops ✅

**Detailed safety checks:**

1. ✅ No secrets or API keys
   - grep for common secret patterns: no matches (grep output contained only documentation references)
   - No hardcoded credentials
   - No API keys in source

2. ✅ No debug artifacts
   - No TODO comments
   - No console.log / print statements beyond existing debugPrint (standard pattern)
   - No test scaffolding
   - No temporary flags

3. ✅ No accidental file deletions
   - Only expected deletion: deliver-notifications directory (untracked, per plan)
   - All other files intact

4. ✅ Formatting churn acceptable
   - notification_repository.dart: dart format applied to markAsRead, updatePreferences (semantic no-ops)
   - push_notification_service.dart: dart format applied to debugPrint (semantic no-op)
   - PROJECT_CONTEXT.md: table alignment formatting (whitespace-only)
   - No unrelated files reformatted

## Issues Found

None

## Critical Deployment Warning

🚨 **MIGRATION-BEFORE-CLIENT SEQUENCING REQUIREMENT** 🚨

The migration in `supabase/migrations/20260705143000_cleanup_stale_device_tokens.sql` **MUST** be applied to production via `supabase db push` **BEFORE** releasing any app build (iOS/Android/Web/macOS) containing the modified client code to users.

**Why:** New client code calls the RPC with 4 parameters including `p_old_token`. The current production RPC has only 3 parameters. PostgREST cannot match a 4-parameter call to a 3-parameter function, resulting in PGRST202 error and token registration failure.

**Safe deployment sequence:**

1. Apply migration to production (`supabase db push`)
2. Verify RPC replacement (POST-DEPLOY TEST 1)
3. Execute Ops Runbook Part B (decommission zombie infrastructure)
4. Verify production delivery (Ops Runbook B5)
5. Release new app builds to users

**Backward compatibility note:** The migration can be deployed independently. Old clients (3-param calls) will continue to work against the new RPC (4-param with defaults). Only new clients require the migration to be deployed first.

## Post-Deployment Verification Required

Per Architect plan Verification Plan, the following device-dependent tests must be executed post-deployment:

1. **Token refresh behavior** — Install app, force token refresh, verify old token deleted
2. **Multi-device support** — Log in on 2 devices same platform, verify both tokens preserved
3. **Push delivery** — Create test notification, verify send-push delivers successfully
4. **No duplicates** — Verify single push per user after token refresh
5. **QA regression tests** — All 11 scenarios in plan's QA Regression Areas section

These tests require physical devices or emulators and cannot be executed pre-deployment. Mark as **DEFERRED TO POST-DEPLOY** per plan, not as failures.

## Ops Runbook Execution Required

After migration deployment, Tony must execute Ops Runbook Part B (manual steps):

- B1: Verify production delivery working
- B2: Unschedule zombie pg_cron jobs (jobid 5, 7)
- B3: Delete deployed deliver-notifications Edge Function
- B4: Remove legacy FCM_SERVER_KEY secret
- B5: Verify production still works

These manual operations are documented in the Architect plan and are NOT part of the automated migration. QA approval does not include these ops tasks — they must be executed separately per plan instructions.

---

**QA Agent:** Claude (QA.md workflow)  
**Validation Date:** 2026-07-05  
**Branch:** bug/notification-delivery-housekeeping  
**Base Commit:** 94d160a3cdcc10a7e775e27844e6eff6b565b18b
