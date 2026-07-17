# Engineer Report

## Feature Slug

invite-role-selection

## Feature Title

Invite Role Selection

## Goal

Allow band admins to select the RBAC role (admin / member / contributor) when creating an invitation, defaulting to "Band Member". The selected role is persisted in the `band_invitations` table and applied when the invitee accepts the invitation, eliminating the window where a new member has broader access than intended.

## Architect Tasks Completed

- [x] E1: Write and apply SQL migration for intended_role column and RPC update
- [x] E2: Verify RLS policy on band_invitations INSERT enforces admin-only invite creation
- [x] E3: Copy \_buildRoleButton() method from role_management_sheet.dart
- [x] E4: Add \_selectedRole state variable to \_InviteMembersScreenState, default 'member'
- [x] E5: Build \_buildRoleSelector() widget with three toggle buttons
- [x] E6: Update \_sendInvite() to include 'intended_role': \_selectedRole in INSERT payload

Testing tasks E7-E12 are delegated to the QA agent per the BandRoadie pipeline protocol.

## Files Created

- `supabase/migrations/20260717085528_add_intended_role_to_invitations.sql`
  - Adds `intended_role` column to `band_invitations` table (type: band_role_type, default: 'member', NOT NULL)
  - **Fixes RLS policy:** Replaces `band_invitations_insert_member` policy (which only checked membership) with `Admins can create invitations` policy (enforces admin role check per E2)
  - Updates `accept_band_invite` RPC to read `intended_role` from invitation and apply it when creating/updating `band_members` row

## Files Modified

- `lib/features/contacts/widgets/invite_members_screen.dart`
  - Added `_selectedRole` state variable (line 33), defaulting to 'member'
  - Added `_buildRoleSelector()` method (lines 425-449) returning role selector UI with three toggle buttons
  - Added `_buildRoleButton()` method (lines 451-526) implementing role button widget with selection state
  - Updated `_sendInvite()` method to include `'intended_role': _selectedRole` in INSERT payload (line 174)
  - **Bug fix:** Added `setState(() => _selectedRole = 'member')` after successful invite to reset role selector (line 183)
  - **Layout change:** Reordered build() method to place role selector above email input (lines 576-579) per Tony's request

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings** (re-verified after post-implementation refinements)

```
Analyzing bandroadie...
No issues found! (ran in 3.9s)
```

## Test Results

Not run — testing is delegated to QA agent per BandRoadie pipeline protocol.

Manual testing will be performed by QA agent to verify:

- Role selector UI renders correctly on all platforms
- Invitation creation with all three roles (admin, member, contributor)
- Invitation acceptance applies the correct role
- Existing in-flight invitations default to 'member' role
- Role Management sheet continues to work without regression

## Verification

### Database Migration Verification (Staging Environment: hpjvbagybmmaykamsgpd)

**Note:** Migration applied to staging environment for verification only. Production deployment will occur at the Release Gate after QA approval, applied via tracked migration file through standard `supabase db push` workflow (not MCP `apply_migration`).

**Pre-Deploy Test — RLS Policy Verification:**
Query: `SELECT schemaname, tablename, policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname='public' AND tablename='band_invitations' AND cmd='INSERT'`

Result (BEFORE fix):
```
policyname: band_invitations_insert_member
cmd: INSERT
with_check: ((EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid())))) AND (invited_by = auth.uid()))
```

**Finding:** Policy only checked band membership, NOT admin role. This violated the security requirement in Architect Plan section 7. Per E2, updated migration to replace policy with admin-only check.

Result (AFTER fix):
```
policyname: Admins can create invitations
cmd: INSERT
with_check: ((EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid()) AND (band_members.role = 'admin'::band_role_type) AND (band_members.status = 'active'::text)))) AND (invited_by = auth.uid()))
```

**Post-Deploy Tests — Migration Applied Successfully:**

Test 1 — Column verification:
```
column_name: intended_role
data_type: USER-DEFINED (band_role_type ENUM)
column_default: 'member'::band_role_type
is_nullable: NO
```
✅ Column created correctly with expected type and default.

Test 2 — RPC update verification:
```
contains_intended_role: true
```
✅ RPC function `accept_band_invite` successfully updated to include `intended_role` logic.

Test 3 — Data integrity check:
```
invalid_roles: 0
```
✅ No invalid role values in existing invitation data. All rows backfilled with default 'member'.

### Manual Code Verification

- Confirmed `_selectedRole` state variable is correctly initialized to 'member'
- Confirmed role selector UI follows the same pattern as role_management_sheet.dart
- Confirmed `intended_role` is passed to INSERT statement
- Confirmed `flutter analyze` reports 0 errors and 0 warnings
- Confirmed `dart format` completed successfully

## Deviations From Architect Plan

1. **RLS Policy Fix Required (E2):**  
   The existing `band_invitations` INSERT policy (`band_invitations_insert_member`) only checked for band membership, not admin role. Per Architect Plan section 7 and task E2 instructions ("If not, update policy"), the migration was extended to replace the policy with an admin-only check. This was an anticipated issue per the plan.

2. **Testing Tasks Deferred (E7-E12):**  
   Functional testing tasks (E7-E12) including invitation creation, acceptance, UI validation, and regression testing are deferred to the QA agent per BandRoadie's four-role pipeline protocol (Manager → Architect → Engineer → QA). The Engineer role is responsible for implementation and static analysis (flutter analyze), not functional testing.

3. **Post-Implementation Refinements:**  
   - **Bug fix:** Added role selector reset (`_selectedRole = 'member'`) after successful invite to prevent accidental elevated-role invites across multiple invites in the same session
   - **Layout change:** Reordered UI per Tony's request — role selector now appears above email input (original placement was below)

## Blockers Encountered

None — the RLS policy gap was anticipated in the Architect Plan and resolved during implementation per E2 instructions.

## Ready For QA

**Yes**

Implementation is complete. All code changes are within scope, analyzer reports no issues, and the implementation follows existing UI patterns. The feature is ready for comprehensive testing by the QA agent.

---

**Engineer:** Claude (Sonnet 4.5)  
**Completed:** 2026-07-17  
**Branch:** `feature/invite-role-selection`
