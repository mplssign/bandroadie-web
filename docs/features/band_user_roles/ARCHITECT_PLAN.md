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
| `member` | `admin` | **Promoted during migration only** — see compatibility strategy below |
| _(new post-migration)_ | `member` | "Band Member" in UI — default for newly invited members going forward |
| _(new)_ | `contributor` | New role with sub-permissions |

**Decision:** Collapse `owner` into `admin`. The `owner` concept adds complexity without user value — any Admin can do everything.

**Compatibility-first rollout:** During migration, **all existing active band members** are promoted to `admin` regardless of their current role. This is a deliberate zero-regression strategy: before RBAC existed, every member had full access. Immediately restricting members to lower roles would silently remove capabilities they currently have, causing confusion and support load. Instead, every existing user retains full access after deployment, and band admins can then manually reorganize roles at their own pace using the new Role Management UI.

**Going forward (post-migration):**
- Only the **band creator** receives `admin` by default when creating a new band.
- All **invited members** default to `member` when they join.

**Roles are scoped per band.** A user who is `admin` in Band A can simultaneously be `member` in Band B. There is no global role — every permission check queries `band_members` filtered by `band_id`. Role changes in one band have zero effect on the user's role in other bands.

### 3.2 Database Migration

**New migration file:** `supabase/migrations/YYYYMMDD_band_user_roles.sql`

#### 3.2.1 Update role values

```sql
-- Step 1: Collapse owner → admin (before bulk promotion)
UPDATE public.band_members SET role = 'admin' WHERE role = 'owner';

-- Step 2: COMPATIBILITY MIGRATION — promote ALL existing active members to admin.
-- Before RBAC, every band member had unrestricted access. Promoting everyone to
-- admin ensures zero permission loss at deployment time. Band admins can then
-- reorganize roles manually using the Role Management UI.
-- Non-active rows (status = 'invited', 'inactive', 'removed') are left as-is
-- since they don't have functional access anyway.
UPDATE public.band_members SET role = 'admin' WHERE status = 'active';

-- Step 3: Create a PostgreSQL ENUM type for band roles
-- ENUM is stronger than a CHECK constraint: it is a distinct type enforced
-- at the storage layer, prevents typos in future queries, and is indexable.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'band_role_type') THEN
    CREATE TYPE public.band_role_type AS ENUM ('admin', 'member', 'contributor');
  END IF;
END $$;

-- Step 4: Alter column from TEXT to ENUM
-- Requires an explicit USING cast since the column currently holds TEXT values.
-- All active rows are now 'admin'; non-active rows may still be 'member'.
-- Both are valid ENUM values, so the cast is safe.
ALTER TABLE public.band_members
  ALTER COLUMN role TYPE public.band_role_type
  USING role::public.band_role_type;

-- Step 5: Default new members to 'member' (applies to future INSERTs only)
-- The band creator flow must explicitly set role = 'admin' for the creator.
ALTER TABLE public.band_members
  ALTER COLUMN role SET DEFAULT 'member'::public.band_role_type;

-- Step 6: Drop any legacy CHECK constraint (now redundant with ENUM)
ALTER TABLE public.band_members
  DROP CONSTRAINT IF EXISTS band_members_role_check;
```

> **Design decision — ENUM vs CHECK:** A PostgreSQL ENUM type was chosen over a
> CHECK constraint because it provides type-level enforcement (impossible to
> insert an unlisted value even via raw SQL), self-documents valid values in
> `pg_type`, and avoids silent string mismatches. Adding a new role in the
> future requires `ALTER TYPE band_role_type ADD VALUE 'new_role'`.

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

-- RLS: only admins can INSERT/UPDATE/DELETE contributor permissions
-- Uses separate USING and WITH CHECK to cover both read-path and write-path.
CREATE POLICY "Admins can manage contributor permissions"
  ON public.contributor_permissions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members admin_bm
      JOIN public.band_members target_bm ON admin_bm.band_id = target_bm.band_id
      WHERE target_bm.id = contributor_permissions.band_member_id
      AND admin_bm.user_id = auth.uid()
      AND admin_bm.role = 'admin'
      AND admin_bm.status = 'active'
    )
  )
  WITH CHECK (
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
-- Returns the role of the current user in a given band.
--
-- SECURITY DECISION: SECURITY DEFINER is REMOVED.
-- Rationale: This function only reads band_members where user_id = auth.uid(),
-- which is already permitted by the existing SELECT RLS policy on band_members.
-- Using SECURITY DEFINER here would allow the function to bypass RLS for no
-- benefit, while introducing a privilege-escalation surface. Running as
-- SECURITY INVOKER (the default) ensures the caller's own RLS policies apply.
--
-- If future RLS changes block this query, re-evaluate — but prefer fixing RLS
-- over adding SECURITY DEFINER.
CREATE OR REPLACE FUNCTION public.get_user_band_role(p_band_id UUID)
RETURNS TEXT AS $$
  SELECT role::TEXT FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Grant to authenticated (no SECURITY DEFINER, runs under caller's RLS)
GRANT EXECUTE ON FUNCTION public.get_user_band_role(UUID) TO authenticated;
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

**Gigs — UPDATE (admin & member only):**
```sql
DROP POLICY IF EXISTS "Band members can update gigs" ON public.gigs;
CREATE POLICY "Admins and members can update gigs" ON public.gigs
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Gigs — DELETE (admin & member only):**
```sql
DROP POLICY IF EXISTS "Band members can delete gigs" ON public.gigs;
CREATE POLICY "Admins and members can delete gigs" ON public.gigs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Gigs — INSERT hardening for `can_create_potential_gigs_only`:**

> **Design decision — `can_create_potential_gigs_only` enforcement:**
> This flag is enforced at **both** the RLS layer and the UI layer.
> When a contributor has `can_create_gigs = TRUE` and
> `can_create_potential_gigs_only = TRUE`, the RLS INSERT policy additionally
> requires `gigs.is_potential = TRUE`. This prevents a modified client from
> creating confirmed gigs. The UI also hides the "confirmed gig" option for
> these contributors as a convenience.

```sql
-- Extended INSERT policy: if contributor has can_create_potential_gigs_only,
-- the inserted row MUST have is_potential = true.
DROP POLICY IF EXISTS "Band members can create gigs" ON public.gigs;
CREATE POLICY "Band members can create gigs" ON public.gigs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND (
        -- Admin & member: unrestricted
        bm.role IN ('admin', 'member')
        OR (
          -- Contributor: must have can_create_gigs
          bm.role = 'contributor'
          AND EXISTS (
            SELECT 1 FROM public.contributor_permissions cp
            WHERE cp.band_member_id = bm.id
            AND cp.can_create_gigs = TRUE
            AND (
              -- If potential-only flag is set, enforce is_potential = true
              cp.can_create_potential_gigs_only = FALSE
              OR gigs.is_potential = TRUE
            )
          )
        )
      )
    )
  );
```

**Setlists — INSERT/UPDATE/DELETE (admin & member only):**
```sql
-- Contributors get SELECT only (via existing/unchanged SELECT policy)

-- INSERT
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

-- UPDATE (WITH CHECK ensures post-update row still passes)
DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
CREATE POLICY "Admins and members can update setlists" ON public.setlists
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE
DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
CREATE POLICY "Admins and members can delete setlists" ON public.setlists
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Bands — DELETE (admin only, via updated RPC + explicit RLS):**

> **Hardening note:** Band deletion uses an RPC (`delete_band`) with
> SECURITY DEFINER because it must cascade-delete across multiple tables.
> As a defense-in-depth measure, we also drop any permissive DELETE policy
> on `public.bands` and add an admin-only DELETE policy. This ensures that
> even direct `DELETE FROM bands` (bypassing the RPC) is blocked for
> non-admins.

```sql
-- Step 1: Remove any permissive DELETE policy on bands
DROP POLICY IF EXISTS "Band members can delete bands" ON public.bands;
DROP POLICY IF EXISTS "Anyone can delete bands" ON public.bands;
DROP POLICY IF EXISTS "Active members can delete bands" ON public.bands;

-- Step 2: Admin-only DELETE policy on bands table
CREATE POLICY "Only admins can delete bands" ON public.bands
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = bands.id
      AND bm.user_id = auth.uid()
      AND bm.role = 'admin'
      AND bm.status = 'active'
    )
  );

-- Step 3: delete_band RPC — restrict to admin role
CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_band_exists BOOLEAN;
  v_is_admin BOOLEAN;
BEGIN
  SET search_path = public;

  -- Check band exists
  SELECT EXISTS (
    SELECT 1 FROM public.bands WHERE id = band_uuid
  ) INTO v_band_exists;
  IF NOT v_band_exists THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

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

  -- Cascade delete (same as existing 082 migration)
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.setlists WHERE band_id = band_uuid;
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;
```

#### 3.2.5 Role change RPC

```sql
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_member_id UUID,
  p_band_id UUID,
  p_new_role TEXT,
  p_sub_permissions JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_role TEXT;
  v_target_current_role TEXT;
  v_admin_count INT;
BEGIN
  SET search_path = public;

  -- Caller must be admin
  SELECT role::TEXT INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can change roles';
  END IF;

  -- Validate new role (defense-in-depth; ENUM type also enforces this)
  IF p_new_role NOT IN ('admin', 'member', 'contributor') THEN
    RAISE EXCEPTION 'Invalid role: %', p_new_role;
  END IF;

  -- Get target's current role
  SELECT role::TEXT INTO v_target_current_role
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id AND status = 'active';

  IF v_target_current_role IS NULL THEN
    RAISE EXCEPTION 'Member not found in this band';
  END IF;

  -- Prevent last admin demotion
  -- FOR UPDATE locks matching admin rows to prevent concurrent demotion race.
  IF v_target_current_role = 'admin' AND p_new_role != 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.band_members
    WHERE band_id = p_band_id AND role = 'admin' AND status = 'active'
    FOR UPDATE;

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot demote: at least one admin must remain';
    END IF;
  END IF;

  -- Update role (cast text to enum)
  UPDATE public.band_members
  SET role = p_new_role::public.band_role_type
  WHERE id = p_member_id AND band_id = p_band_id;

  -- Handle contributor permissions
  IF p_new_role = 'contributor' THEN
    -- Upsert contributor permissions (defaults all to TRUE)
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
$$;

GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;
```

#### 3.2.6 Update remove_band_member RPC

```sql
-- Only admins can remove members (not self-remove)
-- Also prevents removing the last admin.
CREATE OR REPLACE FUNCTION public.remove_band_member(p_member_id UUID, p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_role TEXT;
  v_target_user_id UUID;
  v_target_role TEXT;
  v_admin_count INT;
BEGIN
  SET search_path = public;

  -- Verify caller is admin
  SELECT role::TEXT INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can remove members';
  END IF;

  -- Get target member info
  SELECT user_id, role::TEXT INTO v_target_user_id, v_target_role
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot remove yourself';
  END IF;

  -- Prevent removing the last admin
  IF v_target_role = 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.band_members
    WHERE band_id = p_band_id AND role = 'admin' AND status = 'active'
    FOR UPDATE;

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot remove the last admin';
    END IF;
  END IF;

  DELETE FROM public.band_members WHERE id = p_member_id AND band_id = p_band_id;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_band_member(UUID, UUID) TO authenticated;
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
- **Mitigation:** The `update_member_role` and `remove_band_member` RPCs use `SELECT COUNT(*) ... FOR UPDATE` when checking admin count. The `FOR UPDATE` clause takes an exclusive row lock on the admin rows, serializing concurrent demotion/removal attempts. The second transaction will block until the first commits or rolls back, then re-count — correctly seeing the updated admin count. This is stronger than relying on PostgreSQL's default READ COMMITTED isolation and does not require SERIALIZABLE mode.

### 5.5 Owner → Admin Migration
- **Risk:** Existing `owner` rows need updating. If migration fails mid-way, some rows still say `owner`.
- **Mitigation:** Migration runs `UPDATE ... SET role = 'admin' WHERE role = 'owner'` before the `ALTER COLUMN ... TYPE` cast to the ENUM. The ENUM creation will fail if any unconverted value remains (e.g., `'owner'`), which acts as an automatic safety gate — the migration is atomic.
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

### 5.9 search_path Injection in SECURITY DEFINER Functions
- **Risk:** SECURITY DEFINER functions execute with the definer's privileges. If `search_path` is not pinned, an attacker could create a schema with identically named tables/functions and hijack queries.
- **Mitigation:** Every SECURITY DEFINER function in this feature (`delete_band`, `update_member_role`, `remove_band_member`) begins with `SET search_path = public`. The helper function `get_user_band_role` does NOT use SECURITY DEFINER (see §3.2.3 decision).

### 5.10 Permissive DELETE Policies on Bands
- **Risk:** A leftover permissive DELETE policy on `public.bands` (from earlier migrations or manual edits) would allow any member to delete a band even if the RPC is locked down.
- **Mitigation:** The migration explicitly drops all known permissive DELETE policies on bands before creating the admin-only DELETE policy (see §3.2.4). The Engineer must verify in production with `SELECT * FROM pg_policies WHERE tablename = 'bands' AND cmd = 'DELETE'` after deployment.

### 5.11 Compatibility-First Rollout (All Existing Members → Admin)
- **Risk:** Promoting all existing active members to `admin` means every current user can delete bands, remove members, and change roles immediately after deployment.
- **Accepted trade-off:** This is intentional. Before RBAC, every member already had unrestricted access (RLS only checked membership). Promoting to `admin` preserves the status quo. Silently demoting users would cause unexpected permission errors and support load.
- **Post-deployment expectation:** Band admins (i.e., everyone initially) are expected to use the Role Management UI to assign `member` or `contributor` roles to other members as desired. This is a manual, opt-in process — no automated demotion occurs.
- **No permission reduction at deploy time:** This is a hard constraint. The migration must not leave any active member with fewer capabilities than they had before RBAC was introduced.
- **Non-active rows:** Members with `status != 'active'` (invited, inactive, removed) are not promoted. They retain their existing role value, which transitions safely through the ENUM cast.

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
| 14 | contributor | Create confirmed gig (potential_only=true) | ❌ RLS blocked |
| 15 | contributor | Create potential gig (potential_only=true) | ✅ Allowed |
| 16 | admin | Remove last admin | ❌ Exception |

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

### 6.5 Post-Migration Verification Queries

Run immediately after migration to confirm the compatibility-first rollout:

```sql
-- Confirm role distribution after migration
-- Expected: all active rows are 'admin'; no 'owner' rows remain
SELECT role, status, COUNT(*)
FROM public.band_members
GROUP BY role, status
ORDER BY role, status;

-- Verify: zero active members with role != 'admin'
SELECT COUNT(*) AS non_admin_active
FROM public.band_members
WHERE status = 'active' AND role != 'admin';
-- Expected: 0

-- Verify: column default is 'member' for new inserts
SELECT column_default
FROM information_schema.columns
WHERE table_name = 'band_members' AND column_name = 'role';
-- Expected: 'member'::band_role_type

-- Verify: ENUM type exists with correct values
SELECT enumlabel
FROM pg_enum
JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
WHERE typname = 'band_role_type'
ORDER BY enumsortorder;
-- Expected: admin, member, contributor
```

### 6.6 Regression Checks
- Band switching still works (activeBandProvider unaffected)
- All existing active members now have `admin` role (not broken by migration)
- Former `owner` rows migrated to `admin`
- Invitation flow still creates `member` role for new members
- New band creation sets creator to `admin`

### 6.7 Rollout Strategy

The RBAC deployment follows a three-phase rollout to ensure zero UX disruption:

**Phase 1 — Migrate and promote (SQL migration deployment)**
- Deploy the SQL migration to production.
- All existing active `band_members` rows are promoted to `admin`.
- ENUM type enforced, RLS policies updated, RPCs hardened.
- No app update required yet — existing app continues to work because all users are admin.
- Verify with §6.5 queries.

**Phase 2 — Release app with Role Management UI**
- Deploy the Flutter app update containing the permissions provider, role management modal, and all UI guards.
- All users see the Role Management UI in the kebab menu.
- Since all users start as `admin`, the UI guards impose no new restrictions.
- Band admins can now begin assigning `member` and `contributor` roles.

**Phase 3 — Steady state (normal defaults for new members)**
- New members joining via invitation receive `member` role by default.
- New band creators receive `admin` by default.
- The `contributor` role is available for admins to assign.
- No further migration action needed — this is the ongoing behavior.

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

Below is your finalized ARCHITECT PLAN with the Safe Production Rollout Checklist appended as a new section.

I preserved all numbering and structure exactly as-is and added this as Section 9 so it cleanly attaches to the existing plan without modifying prior content.

⸻

9. Safe Production Rollout Checklist

This checklist must be executed in order. Do not skip steps. Do not combine phases.

This rollout assumes:
	•	Compatibility-first strategy (all existing active members → admin)
	•	Zero permission regression at deployment
	•	ENUM conversion + RLS tightening + RPC hardening in one migration

⸻

9.1 Pre-Deployment Safety Checks (Staging or Local Replica)

Before running the migration in production:

1. Snapshot production
	•	Confirm automated Supabase backups are active.
	•	Optionally export a manual snapshot:

supabase db dump -f pre_rbac_backup.sql

This is rollback insurance.

⸻

2. Audit current role values
Run in production SQL editor:

SELECT role, COUNT(*)
FROM public.band_members
GROUP BY role;

Expected:
	•	owner
	•	admin
	•	member

If any unexpected values appear, STOP and investigate.

⸻

3. Confirm no direct DELETE policies on bands exist

SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'bands';

If a permissive DELETE policy exists, confirm your migration drops it.

⸻

9.2 Migration Deployment (Phase 1)

Deploy the SQL migration only.

Do NOT deploy app update yet.

supabase migration up

or via CI/CD.

⸻

9.3 Immediate Post-Migration Verification (Production)

Run the following immediately after deployment:

⸻

1. Confirm ENUM exists

SELECT enumlabel
FROM pg_enum
JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
WHERE typname = 'band_role_type'
ORDER BY enumsortorder;

Expected:

admin
member
contributor


⸻

2. Confirm all active members are admin

SELECT COUNT(*) AS non_admin_active
FROM public.band_members
WHERE status = 'active'
AND role != 'admin';

Expected:

0

If not zero, STOP and investigate.

⸻

3. Confirm no owner values remain

SELECT COUNT(*)
FROM public.band_members
WHERE role::TEXT = 'owner';

Expected:

0


⸻

4. Confirm default role is member

SELECT column_default
FROM information_schema.columns
WHERE table_name = 'band_members'
AND column_name = 'role';

Expected:

'member'::band_role_type


⸻

5. Verify RLS DELETE policy on bands

SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'bands'
AND cmd = 'DELETE';

Expected:
Only:

Only admins can delete bands

No other DELETE policies should exist.

⸻

9.4 Smoke Tests (Before App Release)

Using an existing production account:
	•	Create gig → should succeed
	•	Edit gig → should succeed
	•	Delete gig → should succeed
	•	Delete band → should succeed
	•	Remove member → should succeed

Why? Because all active users are now admin.

If any of these fail, STOP.

⸻

9.5 App Release (Phase 2)

Only after database validation:
	•	Release Flutter update with:
	•	BandPermissions abstraction
	•	Role management sheet
	•	UI guards
	•	Contributor enforcement UI

Because all users are admin at this point:
	•	No existing workflow breaks
	•	No user sees unexpected permission denial
	•	All restrictions are opt-in via role reassignment

⸻

9.6 Post-App Release Validation

After app rollout:

1. Create test band
	•	Creator should be admin.

2. Invite new user
	•	Invited user should default to member.

Verify:

SELECT role
FROM public.band_members
WHERE band_id = '<new_band_id>';

Expected:
	•	Creator → admin
	•	Invited user → member

⸻

3. Test role reassignment
From UI:
	•	Change member → contributor
	•	Toggle sub-permissions
	•	Attempt restricted action
	•	Confirm RLS blocks correctly

⸻

9.7 Monitoring Window (First 48 Hours)

Watch for:
	•	RPC permission denied errors
	•	Unexpected RLS violations
	•	Support tickets mentioning:
	•	“Can’t delete band”
	•	“Can’t create gig”
	•	“Lost access”

If errors appear:
	•	Check band_members.role distribution
	•	Confirm RLS policies in pg_policies
	•	Verify ENUM cast succeeded

⸻

9.8 Rollback Plan (Emergency Only)

If catastrophic issue occurs:
	1.	Restore from backup:

supabase db reset --db-url <production_backup>

	2.	Or manually revert:
	•	Drop ENUM
	•	Revert RLS policies
	•	Restore original RPCs
	•	Restore role column to TEXT

Rollback is invasive — backup restoration is safer.

⸻

9.9 Deployment Invariants (Must Never Be Violated)
	•	No active member loses permissions at migration time.
	•	At least one admin must always exist per band.
	•	ENUM conversion must not partially apply.
	•	SECURITY DEFINER functions must always set search_path = public.
	•	No permissive DELETE policy may exist on public.bands.

If any invariant fails, halt rollout.

⸻

Final State Summary

After full rollout:
	•	All existing active members start as admin.
	•	Only band creators are admin by default going forward.
	•	Invited members default to member.
	•	Roles are scoped per band — a user can hold different roles in different bands.
	•	Contributor role available with sub-permissions.
	•	RLS enforces all critical permissions.
	•	UI reflects permission state.
	•	No surprise permission regressions.