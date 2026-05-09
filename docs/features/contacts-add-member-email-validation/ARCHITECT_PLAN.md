# ARCHITECT_PLAN.md

## Feature Slug

`bug/contacts-add-member-email-validation`

## Problem Summary

Users attempting to invite band members from the Contacts page (or band creation flow) receive the error "Please enter a valid email address" when using valid email addresses that contain plus addressing (e.g., `user+tag@gmail.com`) or other RFC 5322-compliant special characters. The email validation regex is too restrictive and rejects legitimate email formats commonly used for testing, filtering, and tracking.

## Root Cause

**Confidence: HIGH** — Directly observed in code.

The email validation regex pattern in both `invite_members_screen.dart` (line 98) and `band_form_screen.dart` (line 261) is:

```dart
final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
```

This pattern:

- Only allows word characters (`[a-zA-Z0-9_]`), dots (`.`), and hyphens (`-`)
- **Explicitly excludes plus signs (`+`)**, preventing plus addressing
- Excludes other valid RFC 5322 special characters: `! # $ % & ' * = ? ^ { } ~`

**Why it fails:**

1. User enters a valid email with plus addressing: `john+band@gmail.com`
2. Validation attempts to match against `[\w\.-]+` in the local part
3. The `+` character is not in the character class, so the match fails
4. Error snackbar displays: "Please enter a valid email address"
5. User cannot complete the invitation

Plus addressing is supported by Gmail, Outlook, and most major email providers. Users commonly use it for:

- Testing multiple accounts (e.g., `user+test1@example.com`, `user+test2@example.com`)
- Email filtering rules
- Tracking email sources

## Reference Docs Consulted

No reference documentation found for members/contacts/invitations domain in `docs/reference/`.

## Existing System Analysis

### Current Email Validation Flow

**InviteMembersScreen (Contacts → Add Member):**

1. User navigates to Contacts tab
2. Taps "Add" button in Band Members view
3. `InviteMembersScreen` opens with email input field
4. User types email and taps "Invite" button (or presses Enter on keyboard)
5. `_sendInvite()` method is called
6. Email is trimmed and converted to lowercase: `email = _inviteEmailController.text.trim().toLowerCase()`
7. Email is validated against regex: `if (!emailRegex.hasMatch(email))`
8. **If validation fails:** Error snackbar displays "Please enter a valid email address", method returns early
9. **If validation passes:** Additional checks run (duplicate invite, existing member), then invitation is inserted into `band_invitations` table and edge function `send-band-invite` is invoked

**BandFormScreen (Band Creation/Edit):**

1. User creates or edits a band
2. In the "Invite Members" section, user types email and taps "Add" button
3. `_addEmail()` method is called
4. Email is trimmed and converted to lowercase
5. Same regex validation runs
6. **If validation fails:** Error snackbar displays "Please enter a valid email address"
7. **If validation passes:** Email is added to local `_inviteEmails` list and sent when band is saved

### Data Flow After Validation Passes

- Email is inserted into `band_invitations` table (band_id, email, invited_by, status='pending')
- Edge function `send-band-invite` is invoked with the invitation ID
- Edge function fetches invitation details and sends email via Resend API
- **No additional validation occurs** in the edge function — it accepts the email as-is

### Current Validation Logic Location

- **Client-side only** — both files use identical in-line validation
- No shared validation helper or utility function
- No server-side validation in edge function or database constraints
- Database `band_invitations.email` column is a plain text field with no format constraints

## Proposed Solution

Update the email validation regex in both affected files to support RFC 5322-compliant email addresses.

**New regex pattern:**

```dart
final emailRegex = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
);
```

This pattern:

- Allows all RFC 5322-compliant special characters in the local part: `. ! # $ % & ' * + / = ? ^ _ \` { | } ~ -`
- Supports plus addressing (e.g., `user+tag@example.com`)
- Properly validates domain structure with optional subdomains
- Prevents edge cases like consecutive dots, leading/trailing hyphens in domain labels
- Still rejects obviously invalid formats (no @ symbol, no TLD, whitespace, etc.)

**Why this pattern:**

- **More permissive than current** — reduces false negatives without introducing new false positives
- **Industry standard** — aligns with RFC 5322 email specification
- **Common use case support** — enables plus addressing for testing and email management
- **Minimal change** — only the regex pattern changes; no logic, state, or architecture modifications

**Alternative considered and rejected:**

```dart
final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
```

This ultra-permissive pattern (allows any non-whitespace) would work but provides less validation. The RFC 5322-compliant pattern strikes a better balance between permissiveness and format enforcement.

## Database Impact

**Not applicable** — this is a client-side validation issue only.

- The `band_invitations` table has no email format constraints or CHECK constraints
- The database will accept any string in the `email` column
- No migrations required
- No RLS policy changes required
- No RPC function changes required

## Flutter Architecture Changes

### State

- No state management changes
- No new providers or controllers
- No changes to existing state models

### Widgets

- `InviteMembersScreen`: Update regex constant within `_sendInvite()` method
- `BandFormScreen`: Update regex constant within `_addEmail()` method
- No widget structure or lifecycle changes
- No new widgets created

### Repositories

- No repository changes
- No Supabase query changes

## Files to Create

**None**

## Files to Modify

| File                                                       | Line(s) | Change Description                                                                     |
| ---------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/invite_members_screen.dart` | ~98     | Replace `emailRegex` pattern in `_sendInvite()` method with RFC 5322-compliant pattern |
| `lib/features/bands/band_form_screen.dart`                 | ~261    | Replace `emailRegex` pattern in `_addEmail()` method with RFC 5322-compliant pattern   |

**Detailed changes:**

**1. `lib/features/contacts/widgets/invite_members_screen.dart`**

```dart
// BEFORE (line 98)
final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');

// AFTER
final emailRegex = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
);
```

**2. `lib/features/bands/band_form_screen.dart`**

```dart
// BEFORE (line 261)
final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');

// AFTER
final emailRegex = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
);
```

## Files Off-Limits

| File                                           | Reason                                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------------------- |
| `lib/main.dart`                                | Init order must not change                                                             |
| `supabase/functions/send-band-invite/index.ts` | Edge function performs no validation — accepts email as-is from database               |
| Any database migration files                   | No schema changes required                                                             |
| `lib/features/members/*`                       | Members feature files are not affected — invite flow is in contacts and bands features |
| `lib/app/services/supabase_client.dart`        | No Supabase client changes needed                                                      |
| Any test files                                 | No existing test coverage for email validation (add tests if requested separately)     |

## System Impact Map

| System                                 | Impact           | Notes                                                                                                |
| -------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected       | No interaction with email validation                                                                 |
| Rehearsals                             | unaffected       | No interaction with email validation                                                                 |
| Setlists / Catalog                     | unaffected       | No interaction with email validation                                                                 |
| Members / RBAC                         | **affected**     | Primary system — members cannot be invited with valid plus-addressed emails under current validation |
| Auth / Session                         | unaffected       | Email validation is post-auth, no auth flow changes                                                  |
| Routing                                | unaffected       | No route changes                                                                                     |
| Notifications                          | unaffected       | Only affects invite creation, not notification delivery                                              |
| Platform (iOS / Android / Web / macOS) | **all affected** | Validation runs on all platforms identically — fix benefits all users                                |

## Regression Risk

**Level: LOW**

**Rationale:**

- Only 2 files modified
- Changes are localized to a single line (regex pattern) in each file
- No state management, database, routing, or architectural changes
- No changes to method signatures, parameters, or return values
- No changes to UI layout or widget structure
- **Change is additive** — makes validation **more permissive**, reducing false negatives
  - Previously rejected emails will now pass validation (intended behavior)
  - Previously accepted emails will continue to pass (no new restrictions)
  - Cannot introduce new rejections of valid emails
- No impact on critical systems: auth, session, init order, RLS policies
- Edge function and database remain unchanged — they already accept any email format

**Risk factors considered:**

- Regex complexity: The new pattern is more complex but well-tested (RFC 5322 standard)
- Platform compatibility: Dart `RegExp` handles this pattern consistently across all platforms
- Performance: Regex evaluation is O(n) on email length — no performance concern for typical email lengths

## Engineer Task Breakdown

Execute in order:

**Task 1:** Update email validation regex in `invite_members_screen.dart`

- Locate line 98 in the `_sendInvite()` method
- Replace the existing `emailRegex` declaration with the RFC 5322-compliant pattern
- Ensure proper indentation and formatting

**Task 2:** Update email validation regex in `band_form_screen.dart`

- Locate line 261 in the `_addEmail()` method
- Replace the existing `emailRegex` declaration with the RFC 5322-compliant pattern
- Ensure proper indentation and formatting

**Task 3:** Run `flutter analyze`

- Confirm 0 errors
- Confirm 0 warnings related to the modified files

**Task 4:** Create `ENGINEER_REPORT.md`

- Document both changes made
- Include before/after regex patterns
- Confirm `flutter analyze` passed
- Generate `git diff` output

## Verification Plan

### Tier 1 — Pre-deployment (Pre-code-change validation)

Not applicable — no database objects to test. This is a client-side validation change only.

### Tier 2 — Post-deployment (Post-code-change validation)

**POST-DEPLOY TEST 1: Plus addressing support**

```
Manual test in Flutter app:
1. Navigate to Contacts tab
2. Tap "Add" button to open InviteMembersScreen
3. Enter email with plus addressing: test+band@gmail.com
4. Tap "Invite" button
5. Expected: No validation error, invitation is created
6. Verify: Success snackbar appears
7. Verify: Email appears in pending invites list
```

**POST-DEPLOY TEST 2: Special characters support**

```
Manual test in Flutter app:
1. Navigate to Contacts tab → Add member
2. Test each of these emails (one at a time):
   - test!user@example.com
   - user#tag@domain.com
   - first.last@company.co.uk
   - user_name@sub.domain.org
3. Expected: All pass validation
4. Verify: No "Please enter a valid email address" error
```

**POST-DEPLOY TEST 3: Invalid email rejection (regression check)**

```
Manual test in Flutter app:
1. Navigate to Contacts tab → Add member
2. Test each of these INVALID emails:
   - plaintext (no @ symbol)
   - @example.com (no local part)
   - user@ (no domain)
   - user@domain (no TLD)
   - user @example.com (contains space)
   - user@.com (domain starts with dot)
3. Expected: All are rejected with "Please enter a valid email address"
4. Verify: Error snackbar appears for each
```

**POST-DEPLOY TEST 4: Band creation flow (BandFormScreen)**

```
Manual test in Flutter app:
1. Navigate to band creation (create new band)
2. Fill in band name
3. In "Invite Members" section, add email: newuser+test@gmail.com
4. Tap "Add" button
5. Expected: Email is added to invite list (no error)
6. Complete band creation
7. Verify: Band is created and invitation is sent
```

**POST-DEPLOY TEST 5: Edge-to-edge flow verification**

```
Full integration test:
1. User A invites User B using email: userb+bandtest@gmail.com
2. Verify: Invitation is created in database (band_invitations table)
3. Verify: User B receives email at userb+bandtest@gmail.com
4. User B clicks invite link and accepts
5. Verify: User B is added to band members
6. Verify: Invitation status is marked 'accepted'
```

## QA Regression Areas

QA must specifically test:

### Primary Test Areas

1. **Contacts → Add member flow (InviteMembersScreen)**
   - Plus addressing emails: `user+tag@domain.com`
   - Multiple plus signs: `user+tag+test@domain.com`
   - Other special characters: `user!name@domain.com`, `first.last@company.co.uk`
   - Subdomain emails: `admin@api.company.com`
   - Edge cases: very long emails, international domains, hyphens

2. **Band creation/edit flow (BandFormScreen → Invite Members section)**
   - Same email formats as above
   - Verify emails are added to invite list without error
   - Verify invitations are sent when band is saved

3. **Invalid email rejection (regression check)**
   - Ensure validation still rejects obviously invalid formats:
     - No @ symbol
     - No domain
     - No TLD
     - Contains whitespace
     - Starts/ends with special characters inappropriately

4. **Edge function integration**
   - Verify emails with special characters are successfully sent via edge function
   - Check Resend API logs for successful delivery
   - Verify email content renders correctly in recipient inbox

### Regression Test Areas (no changes expected, but verify stability)

1. **Existing member invite flow**
   - Standard email formats (no special chars) continue to work
   - Duplicate detection still functions
   - Self-invite prevention still functions
   - Existing member detection still functions

2. **Pending invite management**
   - Pending invites list displays correctly
   - Cancel invite functionality works
   - Duplicate invite detection works

3. **All platforms**
   - iOS: Email validation works identically
   - Android: Email validation works identically
   - Web: Email validation works identically
   - macOS: Email validation works identically

### Test Checklist for QA

- [ ] Plus addressing emails pass validation in InviteMembersScreen
- [ ] Plus addressing emails pass validation in BandFormScreen
- [ ] Special characters (!, #, etc.) pass validation
- [ ] Subdomain emails pass validation
- [ ] Invalid emails are still rejected with appropriate error
- [ ] Standard emails (no special chars) continue to work
- [ ] Invitations are successfully created in database
- [ ] Edge function successfully sends emails with special characters
- [ ] Email delivery confirmed in recipient inbox
- [ ] All platforms (iOS, Android, Web, macOS) behave identically
- [ ] No console errors or warnings appear during validation
- [ ] No crashes or UI freezes when validating emails

## Rollout / Migration Strategy

Not applicable — no database migration, no edge function deployment.

**Deployment steps:**

1. Merge PR to main branch after QA approval
2. Standard Flutter app deployment process:
   - Web: Deploy via `./tools/deploy_web.sh` (Vercel)
   - iOS: App Store release (standard process)
   - Android: Play Store release (standard process)
   - macOS: Standard release process

**Rollback plan:**

- If regression is detected post-release, revert the PR and redeploy
- No database state to roll back (validation is client-side only)
- No edge function to redeploy

## Out of Scope

Explicitly **not** included in this fix:

1. **Extracting email validation to a shared utility function**
   - The two files currently have duplicate validation logic
   - Future cleanup could consolidate this into `lib/shared/utils/email_validator.dart`
   - Not required for bug fix — would be a separate refactoring task

2. **Server-side email validation**
   - Edge function `send-band-invite` performs no validation
   - Database has no CHECK constraints on email format
   - Not required — client-side validation is sufficient for user experience
   - Server-side validation could be added in future for defense-in-depth

3. **Test coverage for email validation**
   - No existing unit tests for `_sendInvite()` or `_addEmail()` methods
   - Test coverage could be added separately
   - Not blocking for bug fix

4. **Email deliverability validation**
   - The regex validates format only, not whether the email exists or can receive mail
   - Deliverability is handled by Resend API (bounce tracking, etc.)
   - Not in scope for this fix

5. **Internationalized domain names (IDN) / Unicode support**
   - The RFC 5322-compliant pattern uses ASCII only
   - Internationalized domains (e.g., `user@公司.中国`) are not supported
   - Low priority — most band collaboration occurs within ASCII domains
   - Could be addressed in future if user demand exists

6. **Auth screen email validation**
   - Login and signup screens (`lib/features/auth/`) have separate email validation
   - Not affected by this bug (different validation logic)
   - Should be audited separately if same issue exists there
