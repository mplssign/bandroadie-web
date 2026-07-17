# ARCHITECT PLAN — invite-role-selection

**Branch:** `feature/invite-role-selection`  
**Date:** 2026-07-17  
**Status:** Ready for Engineer tasks  

---

## 1. Feature Slug

`feature/invite-role-selection`

---

## 2. Problem Summary

**What:**  
Tony invites new band members by entering their email on the Invite Members screen. Currently there is no way to set the invitee's RBAC role (admin / member / contributor) at invite time. Invited members always join with the default `member` role, and Tony can only change it afterward via the Role Management UI accessed through the member's kebab menu.

**Why this is a problem:**  
For members Tony intends to restrict to `contributor` from the start, this creates a window between invite acceptance and manual role adjustment where they have broader access than intended. Tony wants to select the role at invite time, defaulting to `member` ("Band Member"), changeable before the invite is sent.

---

## 3. Root Cause

**Confidence:** `HIGH` — Confirmed in code.

The invitation system was not designed with RBAC in mind. When RBAC was added in migration `20260302000000_band_user_roles.sql`, the invitation flow was not updated to support role selection.

**Specific failures:**

1. **Schema gap:** The `band_invitations` table has no column to store the intended role (columns: id, band_id, email, invited_by, token, status, expires_at, accepted_at).

2. **UI gap:** The Invite Members screen (`lib/features/contacts/widgets/invite_members_screen.dart`) has only an email input field, no role selector.

3. **RPC hardcoded role:** The `accept_band_invite` RPC (`supabase/migrations/20260328000000_accept_band_invite_rpc.sql` line 49) hardcodes the role as `'member'::band_role_type` when creating the `band_members` row:
   ```sql
   INSERT INTO band_members (band_id, user_id, role, status)
   VALUES (v_band_id, p_user_id, 'member'::band_role_type, 'active')
   ```

4. **No role persistence in invite flow:** When creating an invitation, the Flutter app inserts a row into `band_invitations` with no role field, and the Edge Function `send-band-invite` just sends an email without any role context.

---

## 4. Reference Docs Consulted

- `docs/features/band_user_roles/ARCHITECT_PLAN.md` — Original RBAC architecture, role ENUM definition, RPC patterns
- `docs/reference/architecture/database_schema.md` — Current schema for `band_invitations`, `band_members`, `band_role_type` ENUM
- Existing code:
  - `supabase/migrations/20260328000000_accept_band_invite_rpc.sql` — Current RPC implementation
  - `supabase/functions/accept-invite/index.ts` — Edge Function that calls the RPC
  - `supabase/functions/send-band-invite/index.ts` — Email sending Edge Function
  - `lib/features/contacts/widgets/invite_members_screen.dart` — Current invite UI
  - `lib/features/members/widgets/role_management_sheet.dart` — Reference UI pattern for role selector

---

## 5. Existing System Analysis

**Current invitation flow (no role selection):**

1. **Invite creation (Flutter):**
   - Admin opens Invite Members screen
   - Admin enters email in text field
   - App validates email, checks for duplicates, checks active membership
   - App calls `INSERT INTO band_invitations` with: `band_id`, `email`, `invited_by`, `status='pending'`
   - **No role is specified or stored**

2. **Email sending (Edge Function `send-band-invite`):**
   - Flutter calls `send-band-invite` Edge Function with `bandInvitationId`
   - Edge Function fetches invitation details (email, token, band name, inviter name)
   - Edge Function sends email via Resend with invite link: `https://app.bandroadie.com/invite?token={token}`
   - Edge Function updates invitation `status='sent'`
   - **Role is not involved at this step**

3. **Invite acceptance (Edge Function `accept-invite` + RPC):**
   - User clicks invite link, is authenticated (or redirected to auth first)
   - Flutter or Edge Function calls `accept-invite` Edge Function
   - Edge Function finds all pending/sent invitations for user's email
   - For each invitation, Edge Function calls RPC: `accept_band_invite(p_invite_id, p_user_id)`
   - RPC locks invitation row, checks status, **hardcodes role as `'member'`**, inserts/updates `band_members` row with status `'active'` and role `'member'`, marks invitation `status='accepted'`
   - **Gap:** The role is always `member`, regardless of what the inviter intended

4. **Post-acceptance role change (manual):**
   - Tony opens Members tab, taps kebab menu on the new member's card
   - Tony opens Role Management sheet
   - Tony changes role from `member` to `admin` or `contributor`
   - App calls `update_member_role` RPC
   - **This is the only way to set a non-default role today**

**Current data flow:**
```
[Invite Members Screen]
  ↓ (INSERT with no role)
[band_invitations table: email, status='pending', NO ROLE]
  ↓ (send-band-invite Edge Function)
[Email sent with invite link]
  ↓ (User clicks link, authenticates)
[accept-invite Edge Function]
  ↓ (calls RPC)
[accept_band_invite RPC: hardcodes 'member']
  ↓
[band_members row created: role='member', status='active']
```

---

## 6. Proposed Solution

**Minimal changes to add role selection at invite time:**

1. **Database migration** — Add `intended_role` column to `band_invitations`:
   - Type: `band_role_type` (reuse existing ENUM: admin, member, contributor)
   - Default: `'member'::band_role_type`
   - NOT NULL (defensive — forces explicit choice)
   - No RLS policy change needed (existing INSERT policy already checks admin status via RBAC)

2. **Update `accept_band_invite` RPC** — Read `intended_role` from the invitation and use it when creating the `band_members` row (instead of hardcoded `'member'`)

3. **Flutter UI** — Add role selector to Invite Members screen:
   - Copy toggle button pattern from `role_management_sheet.dart` (three toggle buttons: Admin, Band Member, Contributor)
   - Place selector below email input, above domain shortcut bar
   - Default to `member`
   - Show all three roles (confirmed with Tony: all roles selectable at invite time)
   - **No sub-permissions at invite time** (simplified UX; contributor sub-permissions can be adjusted post-acceptance via Role Management if needed)
   - Persist selected role when calling `INSERT INTO band_invitations`

4. **No Edge Function changes needed** — Edge Functions (`send-band-invite`, `accept-invite`) do not need to be modified; they operate on invitation rows and call the RPC, which will handle the new column transparently

**Why this is minimal:**
- Reuses existing ENUM type (`band_role_type`)
- Reuses existing RPC permissions model (admin-only invite creation already enforced by RLS)
- Reuses existing UI pattern (role selector from Role Management sheet)
- No new tables, no new RPC signatures (just internal logic change)
- Edge Functions unchanged (role is database-side concern)
- No changes to auth flow, session handling, or routing

---

## 7. Database Impact

**Migration required:** Yes

**New migration file:** `supabase/migrations/YYYYMMDD_add_intended_role_to_invitations.sql`

**Changes:**

1. **Add column to `band_invitations`:**
   ```sql
   ALTER TABLE public.band_invitations
     ADD COLUMN intended_role public.band_role_type NOT NULL DEFAULT 'member'::public.band_role_type;
   ```

   **Design decision — DEFAULT 'member':**  
   This ensures backward compatibility with any in-flight invitations that were created before the migration. If an invitation is accepted after the migration but was created before (and thus has `intended_role = NULL`), the DEFAULT ensures it becomes `'member'`. The NOT NULL constraint is added after the DEFAULT is set, so existing rows will be backfilled automatically.

2. **Update `accept_band_invite` RPC:**
   ```sql
   CREATE OR REPLACE FUNCTION public.accept_band_invite(
     p_invite_id UUID,
     p_user_id UUID
   )
   RETURNS VOID
   LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public
   AS $$
   DECLARE
     v_band_id UUID;
     v_status TEXT;
     v_intended_role TEXT;  -- NEW: read intended role from invitation
   BEGIN
     -- Lock the invite row and fetch band_id, status, and intended_role
     SELECT band_id, status, intended_role::TEXT
       INTO v_band_id, v_status, v_intended_role
       FROM band_invitations
      WHERE id = p_invite_id
        FOR UPDATE;

     -- ... existing validation logic (NOT FOUND, already accepted, etc.) ...

     -- Upsert band membership with the intended role
     INSERT INTO band_members (band_id, user_id, role, status)
     VALUES (v_band_id, p_user_id, v_intended_role::band_role_type, 'active')
     ON CONFLICT (band_id, user_id) DO UPDATE
       SET status = 'active',
           role = CASE
                    WHEN band_members.status = 'active' THEN band_members.role
                    ELSE EXCLUDED.role
                  END;

     -- Mark invitation as accepted (existing code unchanged)
     UPDATE band_invitations
        SET status = 'accepted',
            accepted_at = NOW()
      WHERE id = p_invite_id;
   END;
   $$;
   ```

   **Key change:** Replace the hardcoded `'member'::band_role_type` with `v_intended_role::band_role_type` read from the invitation.

   **ON CONFLICT behavior preserved:** If a member already exists with status `'active'`, their current role is preserved (no accidental downgrade). If status is not `'active'` (e.g., `'removed'`, `'inactive'`), they are reactivated with the new invited role.

**RLS impact:**

- **Existing RLS on `band_invitations` (presumed):** INSERT policy already restricts invitation creation to band admins (inferred from error code `42501` in `invite_members_screen.dart` line 224). This same policy will govern the `intended_role` column — only admins can set it.
- **No new RLS policies required:** The `intended_role` column is part of the same row that's already protected. If a non-admin somehow bypassed RLS to INSERT an invitation (which should be impossible), they also couldn't set a restricted role — but this is defense-in-depth; the primary gate is the existing admin-only INSERT policy.
- **Verification required:** Engineer must confirm that the existing INSERT policy on `band_invitations` checks for admin role in the band. If not, the policy must be updated to enforce admin-only invite creation.

**RPC signature changes:** None (function signature unchanged, only internal logic updated)

**Triggers affected:** None

**Migration rollback plan:**  
If the migration fails or needs to be reverted:
1. `ALTER TABLE band_invitations DROP COLUMN intended_role;`
2. Restore previous version of `accept_band_invite` RPC
3. No data loss (role defaults to `'member'` in the old code path)

---

## 8. Flutter Architecture Changes

**New files:** None

**Modified files:**

| File | Changes |
|------|---------|
| `lib/features/contacts/widgets/invite_members_screen.dart` | Add role selector widget (toggle buttons for Admin / Band Member / Contributor), default `member`. Add state variable `_selectedRole`. Include `intended_role` field in `INSERT INTO band_invitations`. |

**State changes:**
- `_InviteMembersScreenState` gains a new state field: `String _selectedRole = 'member'`
- No provider changes needed (invitation creation is local to this screen)

**Widget changes:**
- Add `_buildRoleSelector()` method copied from `role_management_sheet.dart`, returning three toggle buttons
- Add the role selector widget between email input and domain shortcut bar
- Modify `_sendInvite()` to include `intended_role: _selectedRole` in the INSERT payload

**No changes to:**
- `MembersRepository` (role is persisted at database layer, no Dart model changes needed)
- `MembersController` (role is set at invite creation, not fetched separately)
- `MemberVM` (member role comes from `band_members.role`, unchanged)
- Role Management sheet (post-acceptance role changes are separate concern)

---

## 9. Files to Create

**None** — All changes are modifications to existing files.

---

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `supabase/migrations/YYYYMMDD_add_intended_role_to_invitations.sql` | **NEW FILE** — Add `intended_role` column to `band_invitations`, update `accept_band_invite` RPC to read and apply the intended role. |
| `lib/features/contacts/widgets/invite_members_screen.dart` | Add role selector toggle buttons (Admin / Band Member / Contributor), add `_selectedRole` state, modify `_sendInvite()` to include `intended_role` in INSERT. Copy `_buildRoleButton()` method from `role_management_sheet.dart`. |

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `supabase/functions/accept-invite/index.ts` | Edge Function does not need changes — role is handled by the RPC it calls. Touching this would add unnecessary risk. |
| `supabase/functions/send-band-invite/index.ts` | Email sending is role-agnostic. No changes required. |
| `lib/features/members/widgets/role_management_sheet.dart` | Post-acceptance role management is a separate concern. Do not modify existing role change flow. |
| `lib/features/members/members_repository.dart` | Role is persisted at database layer during invite acceptance. No repository changes needed. |
| `lib/features/members/permissions/band_permissions.dart` | Permission abstraction layer is for runtime checks, not invite creation. Do not modify. |
| `lib/features/bands/band_form_screen.dart` | Deprecated invite UI (if any). Invite Members screen is the canonical location. |
| `lib/app/models/band_member.dart` | BandRole enum is already correct (admin, member, contributor). No changes needed. |

---

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | Unaffected — Role is applied at invite acceptance, not gig creation |
| Rehearsals | Unaffected |
| Setlists / Catalog | Unaffected |
| Members / RBAC | **Affected** — New members will join with the role selected at invite time instead of always defaulting to `member` |
| Auth / Session | Unaffected — Auth flow unchanged |
| Routing | Unaffected |
| Notifications | Unaffected |
| Platform (iOS / Android / Web / macOS) | **Affected** — UI change on all platforms (role selector on Invite Members screen) |

---

## 13. Regression Risk

**Level:** `MEDIUM`

**Rationale:**

- **Single system affected:** Members/RBAC only. Invitation flow is isolated from other features.
- **Database schema change:** Adding a column is low-risk (default value ensures backward compatibility), but any schema change requires careful testing.
- **RPC modification:** Changing `accept_band_invite` logic is medium-risk — this RPC is the sole gate for invite acceptance. A bug here could break invite acceptance entirely or assign wrong roles.
- **UI change across all platforms:** Role selector will be visible on Web, iOS, Android, macOS. Layout or state bugs could affect all platforms.
- **No auth/session/routing risk:** Core app flows unchanged.
- **Mitigation:** Thorough testing of invite creation → acceptance → member list refresh cycle, including all three roles and edge cases (duplicate invites, expired tokens, role changes post-acceptance).

**Known failure modes to test:**
1. **Role not persisted:** Invitation created with `intended_role='admin'` but member joins as `member` → RPC did not read the column correctly.
2. **RLS policy blocks non-admin role selection:** Non-admin user (if they somehow bypassed UI guards) creates invitation with `intended_role='admin'` → RLS should block or default to `member`.
3. **Existing invitations break:** In-flight invitations created before migration are accepted after migration → DEFAULT ensures they become `member`.
4. **UI state desync:** Role selector shows `admin` but INSERT payload sends `member` → state variable not wired to INSERT call.
5. **Contributor sub-permissions confusion:** User invites as `contributor`, member accepts, but has no sub-permissions row → contributor default permissions should apply (all enabled per RBAC plan).

---

## 14. Engineer Task Breakdown

| Task # | Description | Dependencies |
|--------|-------------|--------------|
| E1 | Write and apply SQL migration: add `intended_role` column to `band_invitations`, update `accept_band_invite` RPC | None |
| E2 | Verify RLS policy on `band_invitations` INSERT enforces admin-only invite creation. If not, update policy. | E1 |
| E3 | Copy `_buildRoleButton()` method from `role_management_sheet.dart` to `invite_members_screen.dart` | None |
| E4 | Add `_selectedRole` state variable to `_InviteMembersScreenState`, default `'member'` | None |
| E5 | Build `_buildRoleSelector()` widget with three toggle buttons (Admin, Band Member, Contributor), place below email input | E3, E4 |
| E6 | Update `_sendInvite()` method to include `'intended_role': _selectedRole` in INSERT payload | E4 |
| E7 | Test: Create invitation with each role (admin, member, contributor), verify column is persisted in database | E1, E6 |
| E8 | Test: Accept invitation with each role, verify `band_members.role` matches invitation's `intended_role` | E1, E7 |
| E9 | Test: Existing in-flight invitation (created before migration) is accepted after migration, verify it defaults to `member` | E1, E8 |
| E10 | Test: UI on all platforms (Web, iOS, Android, macOS) — role selector renders correctly, tap states work | E5 |
| E11 | Test: Role change post-acceptance via Role Management sheet still works (no regression) | E8 |
| E12 | Run verification plan SQL queries (Tier 1 pre-deploy, Tier 2 post-deploy) | E1, E8 |

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

**Goal:** Verify migration syntax and logic without applying schema changes to production.

These tests run against the **current** database schema (before the migration) or against a local/staging replica with the migration applied.

```sql
-- PRE-DEPLOY TEST 1: Confirm band_role_type ENUM exists and has correct values
-- (This should already be true from the band_user_roles migration)
SELECT enumlabel
FROM pg_enum
JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
WHERE typname = 'band_role_type'
ORDER BY enumsortorder;
-- Expected output:
-- admin
-- member
-- contributor

-- PRE-DEPLOY TEST 2: Confirm RLS policy on band_invitations restricts INSERT to admins
-- (If this query returns no policies or permissive policies, STOP and fix RLS first)
SELECT schemaname, tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'band_invitations' AND cmd = 'INSERT';
-- Expected: At least one INSERT policy that checks band_members.role = 'admin'
-- If no such policy exists, Engineer must create one before proceeding.

-- PRE-DEPLOY TEST 3: Dry-run the column addition syntax (local/staging only)
-- DO NOT RUN IN PRODUCTION YET — this is syntax validation only.
DO $$
BEGIN
  -- Simulate column addition
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'band_invitations'
      AND column_name = 'intended_role'
  ) THEN
    RAISE NOTICE 'Column intended_role does not exist yet (expected before migration)';
  ELSE
    RAISE NOTICE 'Column intended_role already exists (already migrated or unexpected state)';
  END IF;
END $$;
-- Expected output (before migration): "Column intended_role does not exist yet"
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

**Goal:** Verify the migration applied correctly and the RPC behaves as expected.

```sql
-- POST-DEPLOY TEST 1: Confirm intended_role column exists with correct type and default
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'band_invitations'
  AND column_name = 'intended_role';
-- Expected output:
-- column_name: intended_role
-- data_type: USER-DEFINED (maps to band_role_type ENUM)
-- column_default: 'member'::band_role_type
-- is_nullable: NO

-- POST-DEPLOY TEST 2: Confirm accept_band_invite RPC was updated (check function definition)
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'accept_band_invite'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: Function body contains "intended_role" and reads it from band_invitations.
-- Use LIKE to check:
SELECT pg_get_functiondef(oid) LIKE '%intended_role%' AS contains_intended_role
FROM pg_proc
WHERE proname = 'accept_band_invite'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: contains_intended_role = true

-- POST-DEPLOY TEST 3: End-to-end invitation flow (creates test data, cleans up after)
-- This test must be run by an admin-level user.
DO $$
DECLARE
  test_band_id UUID;
  test_invite_id UUID;
  test_user_id UUID;
  test_email TEXT := 'test+invite_role_' || gen_random_uuid()::TEXT || '@example.com';
  created_role TEXT;
BEGIN
  -- Find a test band where the current user is admin
  SELECT bm.band_id INTO test_band_id
  FROM band_members bm
  WHERE bm.user_id = auth.uid()
    AND bm.role = 'admin'
    AND bm.status = 'active'
  LIMIT 1;

  IF test_band_id IS NULL THEN
    RAISE EXCEPTION 'Test aborted: current user is not admin in any band';
  END IF;

  -- Create a test invitation with intended_role = 'contributor'
  INSERT INTO band_invitations (band_id, email, invited_by, status, intended_role)
  VALUES (test_band_id, test_email, auth.uid(), 'pending', 'contributor'::band_role_type)
  RETURNING id INTO test_invite_id;

  RAISE NOTICE 'Created test invitation: % for email: %', test_invite_id, test_email;

  -- Simulate invite acceptance by creating a dummy user and calling the RPC
  -- (In production, auth.users is managed by Supabase Auth; for testing, we simulate)
  -- WARNING: This requires service_role privileges. If running as authenticated user,
  -- skip the RPC call and just verify the column exists.
  -- For full integration testing, use a real invite flow in staging.

  -- Clean up test data
  DELETE FROM band_invitations WHERE id = test_invite_id;
  RAISE NOTICE 'Test invitation deleted';

END $$;
-- Expected: No errors, NOTICE messages confirm creation and cleanup.
-- If RPC call is included, verify band_members row was created with role='contributor'.

-- POST-DEPLOY TEST 4: Verify no bad data was written (sanity check)
-- Check that all band_invitations rows have valid intended_role values
SELECT COUNT(*) AS invalid_roles
FROM band_invitations
WHERE intended_role NOT IN ('admin'::band_role_type, 'member'::band_role_type, 'contributor'::band_role_type);
-- Expected: invalid_roles = 0
-- If > 0, investigate and fix data.
```

**Integration test (manual, staging only):**

1. As an admin, open Invite Members screen
2. Enter test email, select "Admin" role
3. Tap "Invite"
4. Verify invitation row in database: `SELECT intended_role FROM band_invitations WHERE email = 'test@example.com'` → should be `'admin'`
5. Accept invite (use test account or invite yourself)
6. Verify member row in database: `SELECT role FROM band_members WHERE user_id = ... AND band_id = ...` → should be `'admin'`
7. Repeat for "Band Member" and "Contributor" roles
8. Verify Role Management sheet still works to change roles post-acceptance

---

## 16. QA Regression Areas

**QA must specifically test:**

1. **Primary flow — Invite with role selection:**
   - Create invitation with each role (admin, member, contributor)
   - Verify role selector UI renders correctly on all platforms (Web, iOS, Android, macOS)
   - Verify invitation email is sent (no regression in `send-band-invite` Edge Function)
   - Accept invitation (real or test account)
   - Verify new member appears in Members tab with the correct role
   - Verify new member's permissions match their role (e.g., contributor cannot edit setlists)

2. **Role selector UI:**
   - Default selection is "Band Member"
   - All three roles are selectable (Admin, Band Member, Contributor)
   - Selected role is visually highlighted (primary color border, checkmark)
   - Tap states work correctly (no stuck selections, no double-tap required)
   - Layout does not break on small screens (mobile) or wide screens (desktop/tablet)

3. **Invite creation edge cases:**
   - Admin creates invitation with "Admin" role → invitation is created successfully
   - Admin creates invitation with "Contributor" role → invitation is created successfully
   - (Boundary test) Non-admin attempts to invite → should be blocked by RLS (existing behavior, confirm no regression)
   - Invite same email twice with different roles → second invite should be blocked (existing duplicate check, confirm no regression)
   - Cancel invitation after selecting non-default role → invitation is removed, no leftover state

4. **Invite acceptance edge cases:**
   - Accept invitation created with "Admin" role → member joins as admin
   - Accept invitation created with "Contributor" role → member joins as contributor, can only view setlists (confirm permission enforcement)
   - Accept invitation created before migration (in-flight invites) → member joins as `member` (default role)
   - Accept invitation twice (idempotent) → second acceptance is no-op, no error (existing behavior, confirm no regression)

5. **Post-acceptance role changes (no regression):**
   - After accepting invite as "Band Member", admin changes role to "Contributor" via Role Management → role updates successfully
   - After accepting invite as "Admin", admin changes role to "Band Member" (if allowed by admin-count check) → role updates successfully
   - Last admin cannot demote self (existing safeguard, confirm no regression)

6. **Members tab and permissions:**
   - New member appears in Members tab with correct role badge
   - Member card shows correct role display name (Admin, Band Member, Contributor)
   - Kebab menu on member card (admin-only) opens Role Management sheet (existing behavior, confirm no regression)
   - Non-admin does not see kebab menu (existing behavior, confirm no regression)

7. **Cross-platform UI consistency:**
   - Role selector renders identically on Web, iOS, Android, macOS
   - Tap/click interactions feel native on each platform
   - No layout overflow or clipping issues

---

## 17. Rollout / Migration Strategy

**Single-phase deployment:**

1. **Database migration first:**
   - Deploy SQL migration to production: adds `intended_role` column, updates `accept_band_invite` RPC
   - Verify post-deploy tests pass (Tier 2 verification plan)
   - At this point, all new invitations will default to `role='member'` (no Flutter change yet, so UI still has no selector)
   - Existing invite acceptance flow is unchanged (still creates members with `role='member'` from DEFAULT)

2. **Flutter app update second:**
   - Deploy Flutter app with role selector UI
   - All platforms (Web, iOS, Android, macOS) updated simultaneously
   - Users immediately see role selector on Invite Members screen
   - Admins can now select role at invite time

**Backward compatibility:**

- In-flight invitations (created before migration, accepted after migration) will default to `role='member'` due to DEFAULT value
- No data loss or breakage for existing invitations
- Existing members are unaffected (role is stored in `band_members.role`, not in invitations)

**Rollback plan:**

If critical bug discovered post-deployment:
1. Revert Flutter app to previous version (removes role selector from UI)
2. Optionally: Revert database migration (drop column, restore old RPC) if data corruption suspected
3. Investigate bug in staging before re-deploying

---

## 18. Out of Scope

**Explicitly NOT included in this feature:**

1. **Contributor sub-permissions at invite time:**  
   Invite UI will not show sub-permission toggles (can create gigs, potential gigs only, view setlists, etc.). Contributors invited via this feature will default to "all permissions enabled" (per RBAC plan). Admins can adjust sub-permissions post-acceptance via Role Management sheet.  
   **Rationale:** Simplified UX for invite flow. Sub-permissions are a detail best configured after the member joins, not during the invite.

2. **Role change validation in invite UI:**  
   No client-side validation to prevent inviting someone as "Admin" when the inviter is not an admin. RLS policy is the authoritative gate. Flutter UI assumes the user is an admin if they can access the Invite Members screen.  
   **Rationale:** RLS handles this correctly. Adding client-side guards would be redundant and increase complexity.

3. **Bulk invite with roles:**  
   No CSV upload or multi-email invite with role assignment. This feature is single-email-at-a-time.  
   **Rationale:** Bulk invite is a separate feature request. This plan addresses the single-invite flow only.

4. **Invite history / audit log:**  
   No change to how invitations are logged or displayed. Pending invites list in the UI is unchanged (shows email and status, not role).  
   **Rationale:** Audit log is a separate concern. This plan focuses on functional role assignment, not history tracking.

5. **Role preview in invite email:**  
   Invite email body does not mention the role (e.g., "You've been invited as an Admin"). Email remains generic: "You're invited to join [Band Name]".  
   **Rationale:** Role is an internal detail. Invitee sees their role after joining, in the app UI.

6. **Role-based invite expiration:**  
   All invitations expire after the same duration regardless of role (existing behavior unchanged).  
   **Rationale:** Role does not affect invite lifecycle.

---

**End of ARCHITECT_PLAN.md**
