# Architect Plan — Bug Report Email User Address

## Feature Slug

`feature/bug-report-email-user-address`

---

## Problem Summary

When a BandRoadie user submits a bug report or feature request, an email notification is sent to Tony (hello@bandroadie.com) via the `send-bug-report` edge function and Resend API. The email currently includes the submitting user's name but **does not include their email address**. This makes it impossible for Tony to reply to users who submit feedback.

The email should:

1. Set the `Reply-To` header to the user's email address
2. Display the user's email in the email body for visibility
3. Maintain all existing functionality without changing the user-facing submission flow

---

## Root Cause

**Diagnosis:** The edge function (`supabase/functions/send-bug-report/index.ts`) receives `userId` from the Flutter client but does not fetch the user's email address from the `auth.users` table. The Resend API call explicitly sets `reply_to: userId ? undefined : undefined` (line 188), which is a placeholder that was never implemented.

**Evidence:**

- Line 188 comment: `// Could add user email if available`
- The edge function fetches user's `first_name` and `last_name` from `public.users` (lines 108-122)
- The edge function never queries `auth.users` for the email address
- The email body displays user name but not email (line 149)

**Confidence:** HIGH — Confirmed by direct code observation

---

## Reference Docs Consulted

**Notification Domain Reference:**

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md` (not relevant — covers push notification permissions)
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` (not relevant — covers push notifications to band members)
- `docs/reference/notifications/notifications.md` (not relevant — covers notification delivery architecture)

**Finding:** The notification reference docs cover push notifications only. Bug report emails are a separate system and are not documented in the notifications domain. This feature operates independently of the push notification system.

---

## Existing System Analysis

### Current Data Flow

1. **User Submission:**
   - User opens `lib/features/feedback/bug_report_screen.dart`
   - Fills out bug report or feature request form
   - Taps "Submit Bug Report" / "Submit Feature Request"

2. **Client Processing:**
   - `BugReportScreen._submitFeedback()` calls `BugReportEmailService.send()`
   - Service gathers diagnostic info (app version, platform, band name, user name)
   - Service extracts `userId` from `supabase.auth.currentUser.id`
   - Service invokes edge function with payload including `userId`

3. **Edge Function Processing:**
   - `send-bug-report` edge function receives payload
   - Fetches band names from `public.band_members` → `public.bands`
   - Fetches user name from `public.users` (`first_name`, `last_name`)
   - **Does NOT fetch user email** from `auth.users`
   - Formats HTML email with diagnostic info
   - Calls Resend API with:
     - `from: "BandRoadie <noreply@bandroadie.com>"`
     - `to: ["hello@bandroadie.com"]`
     - `reply_to: undefined` ← **Problem**
     - `subject: "BandRoadie Bug Report — ..."`
     - `html: <formatted email body>`

4. **Email Delivery:**
   - Resend sends email to Tony
   - Email contains user's name but not email address
   - Reply-To header is not set
   - Tony cannot reply to the user

### Why User Email Is Available

In Supabase:

- The `auth.users` table is a system table that stores authenticated user data
- Every authenticated user has an `id` (UUID) and `email` (TEXT NOT NULL)
- The edge function runs with `SUPABASE_SERVICE_ROLE_KEY` which has full read access to `auth.users`
- The client already passes `userId` to the edge function

**Conclusion:** The user's email address is available and accessible. The edge function just needs to query for it.

---

## Proposed Solution

Modify the edge function to:

1. **Query `auth.users` for email address:**

   ```typescript
   // After fetching user name from public.users (line ~122)
   let userEmail = undefined;
   if (userId) {
     const { data: authUser } = await supabase.auth.admin.getUserById(userId);
     if (authUser?.user?.email) {
       userEmail = authUser.user.email;
     }
   }
   ```

2. **Set Reply-To header:**

   ```typescript
   // Replace line 188
   reply_to: userEmail ? [userEmail] : undefined,
   ```

3. **Add email to diagnostic info in email body:**

   ```html
   <!-- Add after "User:" row in HTML table (line ~150) -->
   <tr>
     <td style="padding: 4px 8px 4px 0; font-weight: 600;">Email:</td>
     <td>${userEmail || "not available"}</td>
   </tr>
   ```

4. **Add email to plain text body:**
   ```
   User: ${userName}
   Email: ${userEmail || "not available"}
   ```

**Why this is minimal:**

- Single file change (edge function only)
- No Flutter client changes required
- No database schema changes
- No new dependencies
- Uses existing Supabase Admin API (`auth.admin.getUserById`)
- Backward compatible (gracefully handles missing email)

**Edge Cases Handled:**

- User not authenticated (`userId` is null) → No Reply-To, email shows "not available"
- Email fetch fails → No Reply-To, email shows "not available"
- User email is null (should never happen in Supabase) → No Reply-To, email shows "not available"

---

## Database Impact

**Status:** Not applicable

This change does not touch the database:

- No migrations required
- No RLS policy changes
- No RPC functions modified
- Only reads from existing `auth.users` table (system table)

The `auth.users` table is:

- A built-in Supabase system table
- Always contains `id` and `email` for authenticated users
- Readable by edge functions with service role key

---

## Flutter Architecture Changes

**Status:** None

No changes to Flutter code are required:

- `BugReportScreen` — No changes
- `BugReportEmailService` — No changes
- No state management changes
- No widget changes
- No model changes

The Flutter client already sends `userId` to the edge function. No additional data needs to be passed.

---

## Files to Create

**Status:** None

No new files are required for this feature.

---

## Files to Modify

| File                                          | What changes                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------ |
| `supabase/functions/send-bug-report/index.ts` | Add email fetch from `auth.users`, set `reply_to` field, add email to HTML/text body |

**Detailed Changes:**

1. **After line 122** (after fetching user name):
   - Add `userEmail` variable declaration
   - Query `auth.admin.getUserById(userId)` to fetch email
   - Extract email from result

2. **Line 150** (in HTML table):
   - Add new `<tr>` row displaying user email

3. **Line 173** (in plain text body):
   - Add new line displaying user email

4. **Line 188** (in Resend API call):
   - Replace `reply_to: userId ? undefined : undefined` with `reply_to: userEmail ? [userEmail] : undefined`

---

## Files Off-Limits

| File                                                  | Reason                                                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `lib/main.dart`                                       | Init order must not change                                                         |
| `lib/features/feedback/bug_report_screen.dart`        | No UI changes required — acceptance criteria specify no change to user-facing flow |
| `lib/features/feedback/bug_report_email_service.dart` | No client changes required — already sends userId                                  |
| `lib/app/constants/app_constants.dart`                | Support email address unchanged                                                    |
| All migration files                                   | No database changes                                                                |

---

## System Impact Map

| System                                 | Impact                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                |
| Rehearsals                             | unaffected                                                                |
| Setlists / Catalog                     | unaffected                                                                |
| Members / RBAC                         | unaffected                                                                |
| Auth / Session                         | unaffected                                                                |
| Routing                                | unaffected                                                                |
| Notifications (push)                   | unaffected — bug report emails are separate from push notification system |
| Platform (iOS / Android / Web / macOS) | unaffected — server-side only change                                      |
| Bug Report / Feature Request           | **affected** — adds user email to notification emails                     |

---

## Regression Risk

**Level:** LOW

**Rationale:**

1. **Single file change** — Only the edge function is modified
2. **Read-only database access** — No writes, no schema changes
3. **Backward compatible** — Gracefully handles missing email (falls back to `undefined`)
4. **No client changes** — Flutter app behavior unchanged
5. **Isolated system** — Bug report emails do not interact with other features
6. **No auth changes** — Uses existing Admin API, no permission changes
7. **Resend API compatibility** — `reply_to` is an optional field, always supported

**Potential Risks:**

- Edge function deploy failure → Bug reports would not be sent (existing failure mode)
- `auth.admin.getUserById()` fails → Email would show "not available" (graceful degradation)

**Mitigation:**

- Test edge function locally before deploy
- Monitor edge function logs post-deploy
- Submit test bug report to verify email delivery

---

## Engineer Task Breakdown

Execute tasks in order. Do not proceed to the next task until the previous one is complete and verified.

### Task 1: Add User Email Fetch

**What:** Query `auth.users` for the user's email address
**Where:** `supabase/functions/send-bug-report/index.ts` (after line 122)
**How:**

- Declare `let userEmail: string | undefined = undefined;`
- Add conditional block: `if (userId) { ... }`
- Call `supabase.auth.admin.getUserById(userId)`
- Extract email from result: `authUser?.user?.email`
- Assign to `userEmail` variable

### Task 2: Add Email to HTML Body

**What:** Display user email in the diagnostic info table
**Where:** `supabase/functions/send-bug-report/index.ts` (after line 149, inside HTML table)
**How:**

- Add new table row: `<tr><td>Email:</td><td>${userEmail || "not available"}</td></tr>`
- Place after the "User:" row for logical grouping
- Use same styling as other diagnostic rows

### Task 3: Add Email to Plain Text Body

**What:** Display user email in the plain text version
**Where:** `supabase/functions/send-bug-report/index.ts` (after line ~173, in textBody)
**How:**

- Add new line: `Email: ${userEmail || "not available"}`
- Place after "User:" line

### Task 4: Set Reply-To Header

**What:** Configure Resend to set Reply-To header to user's email
**Where:** `supabase/functions/send-bug-report/index.ts` (line 188)
**How:**

- Replace `reply_to: userId ? undefined : undefined` with `reply_to: userEmail ? [userEmail] : undefined`
- Note: Resend expects `reply_to` as an array of strings or `undefined`

### Task 5: Test Edge Function Locally

**What:** Verify changes work correctly before deploying
**How:**

- Run edge function locally via Supabase CLI
- Send test payload with valid `userId`
- Verify email is fetched correctly
- Verify Reply-To header is set
- Verify email body includes user email
- Test with missing `userId` (graceful degradation)

### Task 6: Deploy Edge Function

**What:** Deploy updated edge function to production
**How:**

- Run: `npx supabase functions deploy send-bug-report --project-ref nekwjxvgbveheooyorjo`
- Verify deployment succeeds (check logs)
- Confirm function is live

### Task 7: Production Verification

**What:** Submit real bug report from staging/production to verify end-to-end
**How:**

- Open BandRoadie app (any platform)
- Navigate to Settings → Report a Bug
- Submit test bug report
- Check email received at hello@bandroadie.com
- Verify Reply-To header is set correctly
- Verify email body displays user email
- Verify reply works (send reply to confirm)

---

## Verification Plan

### Tier 1 — Pre-deployment

**Status:** Not applicable

This feature modifies only the edge function. There are no database migrations or RPC functions to test pre-deployment.

---

### Tier 2 — Post-deployment

**Requirement:** All tests must pass after `npx supabase functions deploy send-bug-report` succeeds.

#### TEST 1: Verify Edge Function Deployment

**Objective:** Confirm updated function is live
**Steps:**

1. Check Supabase Dashboard → Edge Functions → `send-bug-report`
2. Verify "Last Deployed" timestamp matches deployment time
3. Check function logs for any startup errors

**Expected:** Function is live, no errors in logs

---

#### TEST 2: Submit Bug Report with Authenticated User

**Objective:** Verify email includes user email and Reply-To header
**Steps:**

1. Log into BandRoadie app (iOS, Android, or Web)
2. Navigate to Settings → Report a Bug
3. Select "Bug Report"
4. Enter description: "Test bug report — verify user email in notification"
5. Submit
6. Check hello@bandroadie.com inbox

**Expected:**

- Email received
- Subject: "BandRoadie Bug Report — Report Bugs — [Platform]"
- Email body includes:
  - User: [First Last]
  - Email: [user@example.com]
- Reply-To header is set to [user@example.com]
- Clicking "Reply" pre-fills user's email address

---

#### TEST 3: Submit Feature Request

**Objective:** Verify feature requests also include user email
**Steps:**

1. Navigate to Settings → Report a Bug
2. Switch to "Feature Request" tab
3. Enter description: "Test feature request — verify user email"
4. Submit
5. Check hello@bandroadie.com inbox

**Expected:**

- Email received
- Subject: "BandRoadie Feature Request — Report Bugs — [Platform]"
- Email body includes user email
- Reply-To header is set correctly

---

#### TEST 4: Verify Reply Functionality

**Objective:** Confirm Tony can reply to users
**Steps:**

1. Open email from TEST 2 or TEST 3
2. Click "Reply" in email client
3. Verify "To:" field is pre-filled with user's email address
4. Send reply
5. Verify user receives reply at their email address

**Expected:**

- Reply is addressed to user's email (not to noreply@bandroadie.com)
- User receives Tony's reply

---

#### TEST 5: Graceful Degradation (Unauthenticated User)

**Objective:** Verify edge function handles missing userId gracefully
**Steps:**

1. Use curl to invoke edge function directly with no `userId`:
   ```bash
   curl -X POST https://[project-ref].supabase.co/functions/v1/send-bug-report \
     -H "Authorization: Bearer [anon-key]" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "bug",
       "description": "Test without userId",
       "screenName": "Test",
       "platform": "Web"
     }'
   ```
2. Check email received

**Expected:**

- Email received
- User: "Unknown"
- Email: "not available"
- Reply-To header is NOT set (undefined)
- No errors in edge function logs

---

#### TEST 6: Check Edge Function Logs

**Objective:** Verify no errors during email fetch
**Steps:**

1. Run: `npx supabase functions logs send-bug-report --project-ref nekwjxvgbveheooyorjo`
2. Review logs from TEST 2, TEST 3, TEST 4, TEST 5
3. Look for errors related to `getUserById` or email fetch

**Expected:**

- No errors
- Logs show successful email sends
- Resend API returns 200 OK

---

## QA Regression Areas

QA must specifically test:

1. **Bug Report Submission (All Platforms)**
   - iOS: Submit bug report, verify email received with Reply-To
   - Android: Submit bug report, verify email received with Reply-To
   - Web: Submit bug report, verify email received with Reply-To
   - macOS: Submit bug report, verify email received with Reply-To

2. **Feature Request Submission**
   - Submit feature request, verify email includes user email

3. **Email Content Verification**
   - User's full name appears in email body
   - User's email address appears in email body
   - All diagnostic info is present (band, platform, OS, app version, timestamp)
   - Email is formatted correctly (HTML and plain text)

4. **Reply Functionality**
   - Click "Reply" in email client
   - Verify Reply-To is user's email (not noreply@bandroadie.com)
   - Send test reply, confirm user receives it

5. **User Experience (No Change)**
   - Confirm bug report screen UI is unchanged
   - Confirm submission flow is unchanged
   - Confirm success/error messages are unchanged
   - Confirm clipboard fallback still works (if email fails to send)

6. **Edge Cases**
   - User with no email (should not be possible in Supabase, but test graceful degradation)
   - User not authenticated (edge function should handle gracefully)
   - Network failure (edge function should return 500, client should show fallback)

---

## Rollout / Migration Strategy

**Status:** Not applicable

This is a pure code change with no database migrations or data backfills.

**Deployment:**

1. Deploy updated edge function: `npx supabase functions deploy send-bug-report`
2. No app update required (client code unchanged)
3. Feature is live immediately after edge function deployment

**Rollback:**

- If issues arise, redeploy previous version of edge function
- No data cleanup required (no writes to database)

---

## Out of Scope

The following are explicitly NOT part of this feature:

- ❌ Changing the recipient email address (remains hello@bandroadie.com)
- ❌ Adding CC or BCC recipients
- ❌ Storing bug reports in the database
- ❌ Creating an in-app bug report history screen
- ❌ Sending confirmation emails to users
- ❌ Adding attachments (screenshots, logs, etc.)
- ❌ Modifying the bug report form UI
- ❌ Adding email validation to the submission flow
- ❌ Changing the email service provider (remains Resend)
- ❌ Adding email analytics or tracking
