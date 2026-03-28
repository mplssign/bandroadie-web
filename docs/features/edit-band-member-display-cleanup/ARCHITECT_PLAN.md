# ARCHITECT PLAN

## Feature: Edit Band Screen — Remove Member List, Restrict Removal to Members Page

**Feature Slug:** `feature/edit-band-member-display-cleanup`
**Date:** March 28, 2026
**Architect:** AI Agent

---

## 1. Problem Summary

The Edit Band screen currently displays two sections related to band membership:

1. **"Members" section** — Lists all band members with removal controls
2. **"Invited" section** — Lists pending email invitations

This mixing of member management with band settings is architecturally inconsistent with the intended permissions model. Member removal is a separate workflow that should belong exclusively on the dedicated Members page, where it is properly restricted to band admins.

**Required Changes:**
- Remove the "Members" section entirely from Edit Band screen
- Remove member removal capability from Edit Band screen
- Keep the "Invited" section (already correctly filtered to pending invites only)
- Member removal remains admin-only on the Members page

---

## 2. Existing System Analysis

### Current Data Flow

**Edit Band Screen** (`lib/features/bands/band_form_screen.dart`):

```
initState()
  └─> _loadMembersAndInvites()
        ├─> Query band_members (status: ['active', 'invited'])
        ├─> Query users table for member details
        ├─> Query band_invitations (status: ['pending', 'sent'])
        ├─> Filter invites excluding existing member emails
        └─> setState: _members, _pendingInvites

build()
  ├─> Invite Members input
  ├─> Invited section (if _pendingInvites.isNotEmpty)
  │     └─> _buildPendingInvitesList()
  └─> Members section
        └─> _buildMembersSection()
              └─> _MemberChip (onRemove: _removeMember)
```

**Members Page** (`lib/features/members/members_tab_content.dart`):

```
- Displays all band members
- Admin menu (⋮) on each member card
- RoleManagementSheet provides:
    ├─> Role change (admin-only, RBAC guarded)
    └─> Remove member (admin-only, RBAC guarded)
```

### Current Invitation Filtering

The invitation list query at line 1117 filters by `status: ['pending', 'sent']`, which correctly excludes:
- `'accepted'` — User has joined the band
- `'declined'` — User declined the invitation
- `'expired'` — Invitation has expired

When an invitation is accepted:
1. `accept-invite` edge function updates status to `'accepted'`
2. User is added to `band_members` table with `status='active'`
3. Invitation no longer appears in Edit Band's Invited section (correctly filtered out)

**Verdict:** Invitation filtering logic is already correct and requires no changes.

---

## 3. Root Cause

**Diagnosis:** Architectural boundary violation — Edit Band screen mixes band settings editing with member management concerns.

**Confidence Level:** HIGH — Confirmed by direct code inspection

**Evidence:**
- Lines 2027–2032 in `band_form_screen.dart` render the Members section
- Line 2671+ defines `_buildMembersSection()` that renders member chips with remove controls
- Line 1396+ defines `_removeMember()` method that handles member removal from Edit Band
- `lib/features/members/members_tab_content.dart` already provides proper admin-only member management

The current implementation creates duplicate functionality with inconsistent permission enforcement.

---

## 4. Proposed Solution

**Minimal Change Approach:** Remove all member management functionality from Edit Band screen.

1. **Delete Member Section Rendering** (lines ~2027–2032): Remove section label, spacing, and `_buildMembersSection()` call
2. **Delete Member Section Widget** (line ~2671+): Delete `_buildMembersSection()` method entirely
3. **Delete Member Removal Logic** (line ~1396+): Delete `_removeMember()` method entirely
4. **Delete Member Helper Widgets**: Delete `_MemberChip` class (line ~2941+) and `_getMemberDisplayName()` helper (line ~1393+)
5. **Simplify State Variables**: Remove `_members` list and `_isLoadingMembers` boolean; keep `_pendingInvites`
6. **Simplify Data Loading**: Remove band_members query and user info fetching from `_loadMembersAndInvites()`; rename to `_loadPendingInvites()`; keep only invitation loading with filter `['pending', 'sent']`

**Why This Works:**
- Members page already provides complete member management (viewing, role change, removal)
- Members page properly enforces admin-only removal via RBAC
- Edit Band screen focuses solely on band settings (name, avatar, timezone, invitations)
- Invited section remains functional and correctly filtered

---

## 5. Database Impact

**Not applicable** — This is a UI-only change. No database modifications required.

---

## 6. RLS / RPC Changes

**Not applicable** — No changes to Row Level Security policies or RPC functions.

Existing RLS on `band_members` and `band_invitations` tables continues to work as-is.

---

## 7. Flutter Architecture Changes

**Affected Layers:**
- UI Layer: Edit Band screen widget (`band_form_screen.dart`)
- State Management: Remove member-related state variables
- Data Loading: Simplify to load only invitations

**Unchanged Layers:**
- Repository Pattern: No repository changes
- Controllers: No state controller changes
- Models: No model changes
- Services: No service changes

---

## 8. Exact Files to Create

**None** — This is a deletion-only change.

---

## 9. Exact Files to Modify

| File Path | Changes Required |
|-----------|-----------------|
| `lib/features/bands/band_form_screen.dart` | Remove `_members` variable, `_isLoadingMembers` boolean, Members section rendering, `_buildMembersSection()` method, `_removeMember()` method, `_getMemberDisplayName()` helper, `_MemberChip` class. Simplify `_loadMembersAndInvites()` → rename to `_loadPendingInvites()`. |

---

## 10. Risks / Edge Cases

- **Member email deduplication logic**: The current `_loadMembersAndInvites()` filters pending invites against existing member emails. After removing the member query, this filter is no longer applicable. Ensure the invite query itself is sufficient (status filter already handles this — accepted invites are excluded).
- **`_isLoadingMembers` usage**: Confirm this boolean is only used to gate the Members section rendering. If it gates any shared loading indicator, the loading state logic may need adjustment.
- **No empty state needed**: The Invited section already handles the no-invites case by hiding entirely. No new empty state UI is required.

---

## 11. Verification Plan

### Automated:

```bash
flutter analyze   # Must pass with 0 errors
flutter test      # Run if member-related tests exist
```

### Manual — Edit Band Screen:

1. Members section no longer rendered
2. Invited section appears only when pending invites exist
3. Invited section header hidden when no pending invites
4. Cancel invite functionality still works
5. Send new invite functionality still works
6. Band name/avatar/timezone editing still works
7. Form submission still works

### Manual — Members Page:

8. All band members displayed correctly
9. Admin can access role management sheet
10. Admin can remove members (with confirmation)
11. Non-admin cannot access removal controls
12. Last admin cannot be removed

### Manual — Invitation Flow:

13. Send invitation from Edit Band → invitation appears in Invited section
14. Accept invitation via email link → invitation disappears from Invited section on next load
15. Accepted user appears in Members page

---

## 12. Engineer Task Breakdown

Execute tasks in order:

**Task 1 — Remove Member Section Rendering**
File: `band_form_screen.dart`
Action: Delete lines ~2027–2032 (Members section label, spacing, `_buildMembersSection()` call)
Verify: Code compiles; build method no longer references Members section

**Task 2 — Delete `_buildMembersSection()` Widget**
File: `band_form_screen.dart`
Action: Delete the entire `_buildMembersSection()` method (line ~2671+)
Verify: Code compiles

**Task 3 — Delete `_removeMember()` Method**
File: `band_form_screen.dart`
Action: Delete the entire `_removeMember()` method (line ~1396+)
Verify: Code compiles

**Task 4 — Delete Helper Methods and Widgets**
File: `band_form_screen.dart`
Action: Delete `_getMemberDisplayName()` helper (line ~1393+) and `_MemberChip` class (line ~2941+)
Verify: Code compiles; no unused code warnings

**Task 5 — Remove Member State Variables**
File: `band_form_screen.dart`
Action: Delete `_members` list variable (line ~135) and `_isLoadingMembers` boolean (line ~136)
Verify: Code compiles; no undefined variable errors

**Task 6 — Simplify Data Loading**
File: `band_form_screen.dart`
Action:
- Rename `_loadMembersAndInvites()` → `_loadPendingInvites()`
- Remove band_members query (lines ~1070–1106)
- Remove user info fetching logic (lines ~1078–1095)
- Remove member email collection logic (lines ~1098–1104)
- Remove invite filtering against member emails (lines ~1128–1131)
- Keep only invitation query and deduplication logic
- Update all call sites: `initState` (~line 192), after `_sendInvite` (~line 1271), after `_cancelInvite` (~line 1353)

Verify: Code compiles; method only loads invitations

**Task 7 — Static Analysis**
Run: `flutter analyze`
Expected: 0 errors, 0 warnings from removed code

**Task 8 — Manual UI Verification**
Run: `flutter run -d chrome` (or preferred platform)
Verify all manual verification steps above

---

## 13. Rollout / Migration Strategy

**Not applicable** — UI-only change with no data migration requirements.

- Standard Flutter build and deploy
- No database migrations needed
- No feature flags required
- No rollback considerations (non-destructive)

---

## 14. Out of Scope

- Members Page modifications of any kind
- Invitation creation, sending, acceptance, or expiration logic
- Database schema, RLS policies, RPC functions, edge functions
- RBAC or role definition changes
- Styling changes, animations, responsive layout, new empty states
- Changes to `BandInvitation` or `BandMember` models
- Any repository changes

---

## 15. Widget Contracts (Public API)

**Not applicable** — No public widget APIs are created or modified. This change removes internal widget methods only.

---

## 16. Data Flow Architecture

### Before (Current State):

```
Edit Band Screen
├─> _loadMembersAndInvites()
│   ├─> Query band_members → _members
│   ├─> Query users → merge with _members
│   └─> Query band_invitations → _pendingInvites
│
└─> Build:
    ├─> Members Section
    │   └─> _buildMembersSection() → _MemberChip → _removeMember()
    └─> Invited Section
        └─> _buildPendingInvitesList()
```

### After (Target State):

```
Edit Band Screen
├─> _loadPendingInvites()
│   └─> Query band_invitations → _pendingInvites
│
└─> Build:
    └─> Invited Section (only, when _pendingInvites.isNotEmpty)
        └─> _buildPendingInvitesList()

Members Page (unchanged)
└─> Member Management
    └─> Admin removes members via RoleManagementSheet
```

---

## 17. Exact Code Locations

### Code to Delete

**State Variables (lines ~132–136):**

```dart
List<Map<String, dynamic>> _members = [];       // DELETE
bool _isLoadingMembers = false;                  // DELETE
```

**Build Method — Members Section (lines ~2027–2032):**

```dart
// DELETE THIS ENTIRE BLOCK:
const SizedBox(height: Spacing.space32),
_buildSectionLabel('Members'),
const SizedBox(height: Spacing.space12),
_buildMembersSection(),
const SizedBox(height: Spacing.space32),
```

**Methods to Delete:**

- `_loadMembersAndInvites()` (line ~1060) — DELETE, replace with simplified `_loadPendingInvites()`
- `_removeMember()` (line ~1396) — DELETE entire method
- `_getMemberDisplayName()` (line ~1393) — DELETE entire helper
- `_buildMembersSection()` (line ~2671) — DELETE entire widget method

**Widget Classes to Delete:**

- `_MemberChip` class (line ~2941) — DELETE entire class

### Method Calls to Rename

All calls to `_loadMembersAndInvites()` → rename to `_loadPendingInvites()`:

- Line ~192: in `initState`
- Line ~1271: after `_sendInvite`
- Line ~1353: after `_cancelInvite`
- Any other occurrences (search to confirm)

---

## Summary

This plan removes all member management functionality from the Edit Band screen to align with the intended architecture:

- **Edit Band** manages band settings (name, avatar, timezone, invitations)
- **Members page** manages member operations (viewing, role changes, removal) with admin-only RBAC enforcement

The change is low-risk, single-file, deletion-only, and preserves all existing member management on the Members page.

| Metric | Value |
|--------|-------|
| Files Modified | 1 |
| Files Created | 0 |
| Regression Risk | LOW |
| Database Impact | None |
| RLS Impact | None |

---

**ARCHITECT SIGN-OFF** — Plan approved for Engineer implementation.
