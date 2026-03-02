# ARCHITECT PLAN — band_user_roles

**Branch:** `feature/band_user_roles`  
**Date:** 2026-03-02  
**Status:** Ready for Engineer tasks  

---

## 1. Problem Summary

BandRoadie currently has a `role` column on `band_members` with values `owner`, `admin`, and `member`, but this is only checked in two places:

- `remove_band_member` RPC (production version ignores role, just checks `status = 'active'`)
- `isCurrentUserAdmin()` in `MembersRepository` (controls kebab menu visibility)

There is **no meaningful RBAC enforcement** anywhere:
- Any band member can delete the band (`082_allow_any_member_delete_band.sql`)
- Any band member can create/edit/delete gigs, setlists, songs (RLS only checks membership)
- Any band member can remove other members (production RPC only checks active status)
- No "Contributor" role exists
- No sub-permission system exists

The feature request introduces three roles (**Admin**, **Band Member**, **Contributor**) with graduated permissions and a Contributor sub-permission model.

---

## 2. Root Cause

- RLS policies are membership-only (no role checks)
- RPC functions in production bypass role checks
- Flutter app has no permission abstraction layer
- The `BandRole` enum in Dart has `owner/admin/member` but is only used cosmetically
- No database table or column exists for Contributor sub-permissions

---

## 3. Proposed Solution

### 3.1 Role Mapping

Current → New mapping:

| Current | New | Notes |
|---------|-----|-------|
| `owner` | `admin` | Merge owner → admin. First member / band creator gets admin. |
| `admin` | `admin` | No change |
| `member` | `member` | "Band Member" in UI |
| _(new)_ | `contributor` | New role with sub-permissions |

**Decision:** Collapse `owner` into `admin`. The `owner` concept adds complexity without user value — any Admin can do everything. The migration will UPDATE existing `owner` rows to `admin`.

### 3.2 Database Migration

**New migration file:** `supabase/migrations/YYYYMMDD_band_user_roles.sql`

#### 3.2.1 Update role values

```sql
-- Collapse owner → admin
UPDATE public.band_members SET role = 'admin' WHERE role = 'owner';

-- Add CHECK constraint for valid roles
ALTER TABLE public.band_members
  DROP CONSTRAINT IF EXISTS band_members_role_check;
ALTER TABLE public.band_members
  ADD CONSTRAINT band_members_role_check
  CHECK (role IN ('admin', 'member', 'contributor'));

-- Default new members to 'member'
ALTER TABLE public.band_members
  ALTER COLUMN role SET DEFAULT 'member';
```

#### 3.2.2 Contributor sub-permissions table

```sql
CREATE TABLE public.contributor_permissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  band_member_id UUID NOT NULL REFERENCES public.band_members(id) ON DELETE CASCADE,
  can_create_gigs BOOLEAN NOT NULL DEFAULT TRUE,
  can_create_potential_gigs_only BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_setlists BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_calendar BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_members BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(band_member_id)
);

ALTER TABLE public.contributor_permissions ENABLE ROW LEVEL SECURITY;

-- RLS: band members can read permissions for members in their bands
CREATE POLICY "Band members can view contributor permissions"
  ON public.contributor_permissions FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm1
      JOIN public.band_members bm2 ON bm1.band_id = bm2.band_id
      WHERE bm2.id = contributor_permissions.band_member_id
      AND bm1.user_id = auth.uid()
      AND bm1.status = 'active'
    )
  );

-- RLS: only admins can modify contributor permissions
CREATE POLICY "Admins can manage contributor permissions"
  ON public.contributor_permissions FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.band_members admin_bm
      JOIN public.band_members target_bm ON admin_bm.band_id = target_bm.band_id
      WHERE target_bm.id = contributor_permissions.band_member_id
      AND admin_bm.user_id = auth.uid()
      AND admin_bm.role = 'admin'
      AND admin_bm.status = 'active'
    )
  );
```

#### 3.2.3 Helper function for role checks

```sql
-- Returns the role of the current user in a given band
CREATE OR REPLACE FUNCTION public.get_user_band_role(p_band_id UUID)
RETURNS TEXT AS $$
  SELECT role FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

#### 3.2.4 Updated RLS Policies

**Gigs — INSERT (restrict contributor):**
```sql
DROP POLICY IF EXISTS "Band members can create gigs" ON public.gigs;
CREATE POLICY "Band members can create gigs" ON public.gigs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND (
        bm.role IN ('admin', 'member')
        OR (
          bm.role = 'contributor'
          AND EXISTS (
            SELECT 1 FROM public.contributor_permissions cp
            WHERE cp.band_member_id = bm.id
            AND cp.can_create_gigs = TRUE
          )
        )
      )
    )
  );
```

**Gigs — UPDATE/DELETE (admin & member only):**
```sql
DROP POLICY IF EXISTS "Band members can update gigs" ON public.gigs;
CREATE POLICY "Admins and members can update gigs" ON public.gigs
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Setlists — INSERT/UPDATE/DELETE (admin & member only):**
```sql
-- Contributors get SELECT only (via existing/unchanged SELECT policy)
DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
CREATE POLICY "Admins and members can create setlists" ON public.setlists
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
-- (same pattern for UPDATE and DELETE)
```

**Bands — DELETE (admin only, via updated RPC):**
```sql
-- delete_band RPC: restrict to admin role
CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS BOOLEAN ...
  -- Check: caller must be admin
  SELECT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = band_uuid
      AND user_id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  ) INTO v_is_admin;
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Permission denied: only admins can delete this band';
  END IF;
  ...
```

#### 3.2.5 Role change RPC

```sql
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_member_id UUID,
  p_band_id UUID,
  p_new_role TEXT,
  p_sub_permissions JSONB DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_caller_role TEXT;
  v_target_current_role TEXT;
  v_admin_count INT;
BEGIN
  -- Caller must be admin
  SELECT role INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can change roles';
  END IF;

  -- Validate new role
  IF p_new_role NOT IN ('admin', 'member', 'contributor') THEN
    RAISE EXCEPTION 'Invalid role: %', p_new_role;
  END IF;

  -- Get target's current role
  SELECT role INTO v_target_current_role
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id AND status = 'active';

  IF v_target_current_role IS NULL THEN
    RAISE EXCEPTION 'Member not found in this band';
  END IF;

  -- Prevent last admin demotion
  IF v_target_current_role = 'admin' AND p_new_role != 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.band_members
    WHERE band_id = p_band_id AND role = 'admin' AND status = 'active';

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot demote: at least one admin must remain';
    END IF;
  END IF;

  -- Update role
  UPDATE public.band_members
  SET role = p_new_role
  WHERE id = p_member_id AND band_id = p_band_id;

  -- Handle contributor permissions
  IF p_new_role = 'contributor' THEN
    -- Upsert contributor permissions
    INSERT INTO public.contributor_permissions (band_member_id)
    VALUES (p_member_id)
    ON CONFLICT (band_member_id) DO NOTHING;

    -- Apply sub-permissions if provided
    IF p_sub_permissions IS NOT NULL THEN
      UPDATE public.contributor_permissions
      SET
        can_create_gigs = COALESCE((p_sub_permissions->>'can_create_gigs')::boolean, TRUE),
        can_create_potential_gigs_only = COALESCE((p_sub_permissions->>'can_create_potential_gigs_only')::boolean, TRUE),
        can_view_setlists = COALESCE((p_sub_permissions->>'can_view_setlists')::boolean, TRUE),
        can_view_calendar = COALESCE((p_sub_permissions->>'can_view_calendar')::boolean, TRUE),
        can_view_members = COALESCE((p_sub_permissions->>'can_view_members')::boolean, TRUE),
        updated_at = NOW()
      WHERE band_member_id = p_member_id;
    END IF;
  ELSE
    -- Clean up contributor permissions if role changed away from contributor
    DELETE FROM public.contributor_permissions WHERE band_member_id = p_member_id;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;
```

#### 3.2.6 Update remove_band_member RPC

```sql
-- Only admins can remove members (not self-remove)
CREATE OR REPLACE FUNCTION public.remove_band_member(p_member_id UUID, p_band_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_caller_role TEXT;
  v_target_user_id UUID;
BEGIN
  SELECT role INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can remove members';
  END IF;

  SELECT user_id INTO v_target_user_id
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot remove yourself';
  END IF;

  DELETE FROM public.band_members WHERE id = p_member_id AND band_id = p_band_id;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

### 3.3 Flutter Permission Abstraction Layer

**New file:** `lib/features/members/permissions/band_permissions.dart`

A pure-Dart permission helper (no Supabase calls) that takes a role + optional sub-permissions and returns boolean checks:

```
class BandPermissions:
  - BandPermissions.fromRole(String role, {ContributorPermissions? subPerms})
  - bool canEditBandSettings
  - bool canInviteMembers
  - bool canRemoveMembers
  - bool canChangeRoles
  - bool canDeleteBand
  - bool canCreateGigs
  - bool canEditGigs
  - bool canCreateSetlists
  - bool canEditSetlists
  - bool canViewSetlists
  - bool canViewCalendar
  - bool canViewMembers
  - bool get isAdmin
  - bool get isMember
  - bool get isContributor
```

This is a **client-side convenience** — backend RLS is the final authority.

**New file:** `lib/features/members/permissions/contributor_permissions.dart`

```
class ContributorPermissions:
  - bool canCreateGigs (default: true)
  - bool canCreatePotentialGigsOnly (default: true)
  - bool canViewSetlists (default: true)
  - bool canViewCalendar (default: true)
  - bool canViewMembers (default: true)
  - factory fromJson(Map<String, dynamic>)
  - Map<String, dynamic> toJson()
```

### 3.4 BandRole Enum Update

**File:** `lib/app/models/band_member.dart`

Update the enum:
```dart
enum BandRole { admin, member, contributor }
```

Remove `owner` — `_parseRole` fallback for `'owner'` returns `BandRole.admin` for backward safety.

### 3.5 Provider for Current User Permissions

**New file:** `lib/features/members/permissions/band_permissions_provider.dart`

A Riverpod provider that:
1. Reads current user's `band_members.role` for the active band
2. If contributor, fetches `contributor_permissions` row
3. Exposes a `BandPermissions` object

```
final currentUserPermissionsProvider = FutureProvider<BandPermissions>((ref) async { ... });
```

### 3.6 UI — Role Management Modal

**New file:** `lib/features/members/widgets/role_management_sheet.dart`

Full-screen modal shown when Admin taps kebab menu ⋯ on a member card:
- Large heading (21px): Member Name
- Current role displayed under name
- "Change role" section with 3 toggle buttons: Admin, Band Member, Contributor
- If Contributor selected: sub-permission toggles (all enabled by default)
- "Remove from band" destructive action with confirmation
- Full-width Save button at bottom
- Centered Cancel text button below Save

### 3.7 UI Guard Integration

Existing files will be modified to conditionally show/hide/disable actions based on `BandPermissions`:

- **Gig creation**: Check `canCreateGigs` before showing "Create Gig" button
- **Setlist mutation**: Check `canEditSetlists` before showing edit controls
- **Band settings**: Check `canEditBandSettings` before showing edit option
- **Delete band**: Check `canDeleteBand` — show only for Admin
- **Member removal**: Check `canRemoveMembers` — show only for Admin
- **Kebab menu on member card**: Show role management option for Admin (replaces current "Remove" only)

---

## 4. Exact Files to Modify

### New Files

| # | Path | Purpose |
|---|------|---------|
| 1 | `supabase/migrations/YYYYMMDD_band_user_roles.sql` | Migration: role constraint, contributor_permissions table, RLS updates, RPCs |
| 2 | `lib/features/members/permissions/band_permissions.dart` | Permission abstraction class |
| 3 | `lib/features/members/permissions/contributor_permissions.dart` | Contributor sub-permissions model |
| 4 | `lib/features/members/permissions/band_permissions_provider.dart` | Riverpod provider for current user permissions |
| 5 | `lib/features/members/widgets/role_management_sheet.dart` | Full-screen role management modal |

### Modified Files

| # | Path | Change |
|---|------|--------|
| 6 | `lib/app/models/band_member.dart` | Update `BandRole` enum (remove `owner`, add `contributor`); update `_parseRole` |
| 7 | `lib/features/members/member_vm.dart` | Update `isAdmin`/`isOwner` getters; add `isContributor`; remove `isOwner` or alias to `isAdmin` |
| 8 | `lib/features/members/members_repository.dart` | Add `fetchContributorPermissions()`, `updateMemberRole()` methods |
| 9 | `lib/features/members/members_controller.dart` | Add `updateRole()` action; expose permissions state |
| 10 | `lib/features/members/widgets/member_card.dart` | Update kebab menu to open role management sheet instead of just "Remove" |
| 11 | `lib/features/members/members_tab_content.dart` | Pass permissions to member cards; update `showRemoveOption` → permission-based |
| 12 | `lib/features/events/widgets/event_editor_drawer.dart` | Guard gig creation with permission check |
| 13 | `lib/features/bands/band_form_screen.dart` | Guard band delete with `canDeleteBand` check |
| 14 | `lib/features/home/widgets/quick_actions_row.dart` | Guard "Create Gig" button visibility |
| 15 | `lib/features/home/home_tab_content.dart` | Pass permissions for gig creation guard |
| 16 | `lib/features/home/home_screen.dart` | Pass permissions for gig creation guard |

### SQL files superseded (production updates via new migration)

| # | Path | Notes |
|---|------|-------|
| — | `supabase/migrations/20260206_remove_band_member_rpc.sql` | Replaced by new RPC in migration |
| — | `lib/supabase/migrations/082_allow_any_member_delete_band.sql` | Replaced by admin-only delete_band |

---

## 5. Risks / Edge Cases

### 5.1 Self-Demotion
- **Risk:** Admin demotes themselves when they are the only admin.
- **Mitigation:** `update_member_role` RPC counts admins before allowing demotion. If `admin_count <= 1`, raise exception.
- **UI:** Disable the "Band Member" and "Contributor" buttons when viewing self AND there is only 1 admin. Show tooltip: "You are the only admin."

### 5.2 Last Admin Removal
- **Risk:** Removing the last admin leaves band unmanageable.
- **Mitigation:** `remove_band_member` RPC should also check: if target is admin AND admin_count <= 1, raise exception.

### 5.3 Stale Role Cache
- **Risk:** User's role changes but their local session still uses old permissions.
- **Mitigation:**
  - `MembersRepository._cache` is cleared on role update
  - `currentUserPermissionsProvider` should be invalidated after role change
  - RLS is the real authority — stale client cache only affects UI visibility, never actual data access
  - Cache TTL is 5 minutes (existing)

### 5.4 Race Conditions
- **Risk:** Two admins simultaneously demote each other → zero admins.
- **Mitigation:** The `update_member_role` RPC counts admins inside a single SQL statement within the same transaction. PostgreSQL serializable isolation prevents this.

### 5.5 Owner → Admin Migration
- **Risk:** Existing `owner` rows need updating. If migration fails mid-way, some rows still say `owner`.
- **Mitigation:** Migration runs `UPDATE ... SET role = 'admin' WHERE role = 'owner'` before adding the CHECK constraint. The CHECK constraint prevents any future `owner` values.
- **Backward safety:** Dart `_parseRole` still maps `'owner'` → `BandRole.admin` as fallback.

### 5.6 Contributor with No Permissions Row
- **Risk:** A contributor is created but the `contributor_permissions` row insert fails.
- **Mitigation:** The `update_member_role` RPC handles this atomically. The Flutter permission layer defaults to "all enabled" if no row is found (matching the "defaults: all sub-permissions enabled" requirement).

### 5.7 Invitation Flow
- **Risk:** What role do invited members get?
- **Decision:** Invited members default to `member` role. Admins can change role after the member accepts.

### 5.8 Band Creation
- **Risk:** Who gets `admin` on a new band?
- **Decision:** The band creator automatically gets `admin`. Check `087_fix_create_band_no_profile.sql` to ensure the create-band flow sets `role = 'admin'`.

---

## 6. Verification Plan

### 6.1 SQL Migration Check
```bash
# Review migration syntax
cat supabase/migrations/YYYYMMDD_band_user_roles.sql

# Apply locally via Supabase CLI
supabase db reset  # or supabase migration up
```

### 6.2 RLS Validation
Test matrix (execute via Supabase SQL editor or psql):

| Test | User Role | Action | Expected |
|------|-----------|--------|----------|
| 1 | admin | Delete band | ✅ Allowed |
| 2 | member | Delete band | ❌ Exception |
| 3 | contributor | Delete band | ❌ Exception |
| 4 | admin | Remove member | ✅ Allowed |
| 5 | member | Remove member | ❌ Exception |
| 6 | contributor | Create gig (can_create_gigs=true) | ✅ Allowed |
| 7 | contributor | Create gig (can_create_gigs=false) | ❌ RLS blocked |
| 8 | contributor | Edit setlist | ❌ RLS blocked |
| 9 | member | Edit setlist | ✅ Allowed |
| 10 | admin | Demote self (last admin) | ❌ Exception |
| 11 | admin | Demote self (other admin exists) | ✅ Allowed |
| 12 | admin | Change member → contributor | ✅ Allowed |
| 13 | member | Change roles | ❌ Exception |

### 6.3 Flutter Analysis
```bash
flutter analyze
```
Must pass with zero errors. No new dependencies introduced.

### 6.4 Manual Permission Testing Matrix

| Screen | Admin sees | Member sees | Contributor sees |
|--------|------------|-------------|------------------|
| Members tab | Kebab menu → Role management | No kebab menu | No kebab menu |
| Home (Quick Actions) | Create Gig button | Create Gig button | Create Gig (if permitted) or hidden |
| Event editor | All fields | All fields | Potential gig only (if restricted) |
| Band settings | Edit + Delete | Edit (no delete) | No edit |
| Setlists | Full CRUD | Full CRUD | View only |

### 6.5 Regression Checks
- Band switching still works (activeBandProvider unaffected)
- Existing members retain `member` role (not broken by migration)
- Former `owner` rows migrated to `admin`
- Invitation flow still creates `member` role

---

## 7. Task Breakdown for Engineer

| Task # | Description | Dependencies |
|--------|-------------|--------------|
| E1 | Write and apply SQL migration (roles, contributor_permissions table, RLS, RPCs) | None |
| E2 | Update `BandRole` enum and `BandMember` model | E1 |
| E3 | Create `BandPermissions` + `ContributorPermissions` classes | None |
| E4 | Create `band_permissions_provider.dart` | E2, E3 |
| E5 | Update `MembersRepository` (fetchContributorPermissions, updateMemberRole) | E1 |
| E6 | Update `MembersController` (expose permissions, updateRole action) | E4, E5 |
| E7 | Update `MemberVM` (remove isOwner, add isContributor) | E2 |
| E8 | Build `role_management_sheet.dart` UI | E3, E6 |
| E9 | Update `member_card.dart` kebab menu to open role management sheet | E8 |
| E10 | Guard gig creation UI (event_editor_drawer, quick_actions_row, home screens) | E4 |
| E11 | Guard band delete UI (band_form_screen) | E4 |
| E12 | Guard setlist mutation UI (setlist screens) | E4 |
| E13 | Update members_tab_content to use permissions provider | E4, E9 |
| E14 | End-to-end testing per verification plan | E1–E13 |

---

## 8. Out of Scope

- Backup band data feature (mentioned as future)
- Resend invite / Copy invite link (optional, defer)
- Audit log for role changes
- Real-time role change push notifications
- Multi-band role synchronization
