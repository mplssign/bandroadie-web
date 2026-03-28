# ARCHITECT PLAN

## Feature: Send Invite — Restore Active Member Guard

**Feature Slug:** `bug/send-invite-no-active-member-guard`
**Date:** March 28, 2026
**Architect:** AI Agent

---

## 1. Problem Summary

The `_sendInvite()` method on the Edit Band screen no longer blocks invitations sent to email addresses that belong to existing active band members.

The guard that prevented this was removed as part of `feature/edit-band-member-display-cleanup`. That change deleted the `_members` local state variable and all code that depended on it, including an email-based membership check inside `_sendInvite()`. No replacement check was added at that time.

The only pre-submit validation that remains queries `band_invitations` for existing `['pending', 'sent']` records. It has no knowledge of `band_members` and cannot detect an already-active member.

---

## 2. Existing System Analysis

### Current `_sendInvite()` validation sequence (post-cleanup):

```
1. Email format validation (regex)
2. Self-invite check (compares email to current user's auth email)
3. Duplicate pending invite check (queries band_invitations for ['pending', 'sent'])
4. → Insert band_invitations record
5. → Call send-band-invite edge function
```

**Missing:** a check between steps 2 and 3 that queries `band_members` to confirm the email does not belong to an existing active member.

### Previous guard (removed):

```dart
// Check if already a member
final memberEmails = _members
    .map((m) => (m['user_info']?['email'] as String?)?.toLowerCase())
    .whereType<String>()
    .toSet();
if (memberEmails.contains(email)) {
  _showErrorSnackBar('This person is already a band member');
  return;
}
```

This relied on `_members` — a local state list populated from `band_members` + `users` at screen load time. That state no longer exists.

### Data model:

- `band_members` table: `band_id`, `user_id`, `status`, `role`
- `users` table: `id`, `email`
- Email is on `users`, not `band_members` — a lookup requires resolving email → user_id, then checking band_members

### Existing query pattern (from `_loadPendingInvites()` and pre-cleanup code):

The codebase already uses two-step lookups: query one table, use results to query a second. The new check should follow this same pattern.

---

## 3. Root Cause

The membership guard was tightly coupled to local state (`_members`) rather than being a self-contained database check. When the local state was removed for architectural reasons, the guard was removed with it. No stateless replacement was added.

**Root Cause Confidence: HIGH** — Confirmed by direct code inspection.

---

## 4. Proposed Solution

Add a two-step inline database check to `_sendInvite()`, inserted between the self-invite check and the existing duplicate pending invite check.

**Step 1:** Query `users` table for a record matching the invite email. If no user record exists, the person has no account and cannot be a band member — skip to the next check.

**Step 2:** If a user record is found, query `band_members` for an active membership record matching that `user_id` and the current `band_id`. If found, block the invite with `'This person is already a band member'`.

```dart
// Check if email belongs to an existing active band member
try {
  final userLookup = await supabase
      .from('users')
      .select('id')
      .eq('email', email)
      .maybeSingle();

  if (userLookup != null) {
    final userId = userLookup['id'] as String;
    final memberLookup = await supabase
        .from('band_members')
        .select('id')
        .eq('band_id', bandId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (memberLookup != null) {
      _showErrorSnackBar('This person is already a band member');
      return;
    }
  }
} catch (e) {
  debugPrint('[Invite] Failed to check active membership: $e');
}
```

**Error handling:** If the check fails (network/DB error), log and continue — consistent with the existing duplicate invite check which also catches and continues. Do not block the invite on a failed guard query.

**Insertion point:** After `final bandId = widget.initialBand!.id;` (line 1122), before the `// Check for existing pending invite` block (line 1124).

**Why this approach:**
- Stateless — no local state required
- Follows existing two-step query pattern already used in this file
- `maybeSingle()` is already used elsewhere in the codebase for nullable single-row lookups
- Minimal diff — no new methods, no new state, no lifecycle changes
- Consistent error handling with the existing duplicate invite check

---

## 5. Database Impact

**Not applicable** — read-only queries against existing tables. No schema changes, migrations, or new indexes required.

---

## 6. RLS / RPC Changes

**Not applicable** — both `users` and `band_members` tables are already queried elsewhere in this screen with the authenticated user's session. Existing RLS permits these reads.

---

## 7. Flutter Architecture Changes

**Affected:**
- `_sendInvite()` method in `lib/features/bands/band_form_screen.dart` — inline validation block added

**Unchanged:**
- No state variables added or modified
- No lifecycle methods changed
- No widget tree changes
- No new methods or classes

---

## 8. Exact Files to Create

**None.**

---

## 9. Exact Files to Modify

| File | Change |
|------|--------|
| `lib/features/bands/band_form_screen.dart` | Insert active member check block inside `_sendInvite()` after line 1122, before line 1124 |

---

## 10. Risks / Edge Cases

**Email not in `users` table:** The invitee has no BandRoadie account. `maybeSingle()` returns null, guard is skipped, invite proceeds normally. Correct behavior.

**User exists but membership check DB error:** Guard catch block logs and continues. The existing duplicate invite check still runs. Worst case: a redundant invite is sent to an existing member. Acceptable — the alternative (blocking on error) would prevent legitimate invites.

**User has `status='invited'` in band_members (not 'active'):** Guard only checks `status='active'`. A user with `status='invited'` means they haven't accepted yet and may never do so. Treating them as an existing member would be incorrect — the guard correctly ignores them.

**Race condition:** Two admins simultaneously invite the same person who is not yet a member. Both checks pass, two invites are created. The existing `23505` unique constraint handling in the PostgrestException catch block addresses this. No change needed.

**User is band admin inviting themselves via a different email alias:** Self-invite check uses the auth user's email directly. The new check uses a DB lookup. These are independent — both remain in place.

---

## 11. Verification Plan

### Automated:

```bash
flutter analyze   # Must pass with 0 errors
```

### Manual — Edit Band Screen:

1. Open Edit Band for a band you admin
2. Enter the email of an existing active member → expect: "This person is already a band member" error, no invite created
3. Enter an email not associated with any user account → expect: invite sent successfully
4. Enter an email of a user who was invited but hasn't accepted → expect: "User already invited" (existing check), no duplicate
5. Enter your own email → expect: "You cannot invite yourself" (existing check)
6. Enter a valid email for a non-member user → expect: invite sent successfully
7. Confirm invite appears in the Invited section after successful send

### Database state to verify after test 2:
- No new record in `band_invitations` for that email
- No email sent (check send-band-invite function was not called)

---

## 12. Engineer Task Breakdown

**Task 1 — Insert active member check into `_sendInvite()`**

File: `lib/features/bands/band_form_screen.dart`

Insertion point: after `final bandId = widget.initialBand!.id;` (line 1122), before `// Check for existing pending invite in the database` comment (line 1124)

Insert this block exactly:

```dart
    // Check if email belongs to an existing active band member
    try {
      final userLookup = await supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (userLookup != null) {
        final userId = userLookup['id'] as String;
        final memberLookup = await supabase
            .from('band_members')
            .select('id')
            .eq('band_id', bandId)
            .eq('user_id', userId)
            .eq('status', 'active')
            .maybeSingle();

        if (memberLookup != null) {
          _showErrorSnackBar('This person is already a band member');
          return;
        }
      }
    } catch (e) {
      debugPrint('[Invite] Failed to check active membership: $e');
    }
```

**Task 2 — Run static analysis**

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings.

**Task 3 — Manual verification**

Run app and execute the manual verification steps above.

---

## 13. Rollout / Migration Strategy

**Not applicable** — no database changes, no feature flags required. Standard Flutter build and deploy.

---

## 14. Out of Scope

- Changes to `_loadPendingInvites()` or any other method
- Changes to the Members page
- Changes to the `accept-invite` edge function (separate bug: `bug/accept-invite-partial-failure-stale-invite`)
- Adding `status='invited'` members to the guard (they have not accepted; inviting them again is a separate UX decision)
- Any new state variables or loading patterns
- Database schema changes

---

## 15. Widget Contracts (Public API)

**Not applicable** — no public widget APIs created or modified.

---

## 16. Data Flow Architecture

### Before (current broken state):

```
_sendInvite()
  ├─> email format check
  ├─> self-invite check
  ├─> band_invitations check (pending/sent only)
  └─> insert band_invitations + send email
      ← NO active member check exists
```

### After (fixed):

```
_sendInvite()
  ├─> email format check
  ├─> self-invite check
  ├─> NEW: users lookup by email
  │     └─> if found: band_members active membership check
  │           └─> if active member: block with error
  ├─> band_invitations check (pending/sent) — unchanged
  └─> insert band_invitations + send email
```

---

## 17. Exact Code Locations

### Insertion point in `band_form_screen.dart`:

**Before (lines 1122–1124):**

```dart
    final bandId = widget.initialBand!.id;

    // Check for existing pending invite in the database (not just local state)
```

**After:**

```dart
    final bandId = widget.initialBand!.id;

    // Check if email belongs to an existing active band member
    try {
      final userLookup = await supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (userLookup != null) {
        final userId = userLookup['id'] as String;
        final memberLookup = await supabase
            .from('band_members')
            .select('id')
            .eq('band_id', bandId)
            .eq('user_id', userId)
            .eq('status', 'active')
            .maybeSingle();

        if (memberLookup != null) {
          _showErrorSnackBar('This person is already a band member');
          return;
        }
      }
    } catch (e) {
      debugPrint('[Invite] Failed to check active membership: $e');
    }

    // Check for existing pending invite in the database (not just local state)
```

---

## Summary

| Metric | Value |
|--------|-------|
| Files Modified | 1 |
| Files Created | 0 |
| Lines Added | ~20 |
| Regression Risk | LOW |
| Database Impact | None |
| RLS Impact | None |

Single insertion point. No state changes. No architectural changes. Restores a guard that was lost as a side effect of a prior cleanup.

---

**ARCHITECT SIGN-OFF** — Plan approved for Engineer implementation.
