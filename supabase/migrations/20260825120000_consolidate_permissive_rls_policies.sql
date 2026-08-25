-- Feature: feature/rls-consolidate-permissive-policies
-- Issue: 102 multiple_permissive_policies Performance Advisor warnings
-- Description: Consolidate redundant/overlapping RLS PERMISSIVE policies
-- to achieve one policy per (table, action) combination. Preserves current
-- effective access by OR'ing all existing predicates for non-equivalent pairs.
-- Rollback reference: docs/features/rls-consolidate-permissive-policies/PRE_MIGRATION_RLS_STATE.md

-- ============================================================================
-- Table: bands (9 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Only admins can delete bands" ON public.bands;
DROP POLICY IF EXISTS "bands: delete creator" ON public.bands;
DROP POLICY IF EXISTS "bands_delete_admins" ON public.bands;
DROP POLICY IF EXISTS "bands: insert own" ON public.bands;
DROP POLICY IF EXISTS "bands_insert_authenticated" ON public.bands;
DROP POLICY IF EXISTS "Band members can view bands" ON public.bands;
DROP POLICY IF EXISTS "bands: select my bands" ON public.bands;
DROP POLICY IF EXISTS "bands_select_members" ON public.bands;
DROP POLICY IF EXISTS "bands_update_admins" ON public.bands;

-- CREATE consolidated policies
CREATE POLICY "bands_delete_creator_or_admin" ON public.bands
FOR DELETE TO authenticated
USING (is_band_admin(id) OR created_by = (select auth.uid()));

CREATE POLICY "bands_insert_authenticated" ON public.bands
FOR INSERT TO authenticated
WITH CHECK (created_by = (select auth.uid()));

CREATE POLICY "bands_select_members" ON public.bands
FOR SELECT TO authenticated
USING (is_deleted = false AND is_band_member(id));

CREATE POLICY "bands_update_admins" ON public.bands
FOR UPDATE TO authenticated
USING (is_band_admin(id))
WITH CHECK (is_band_admin(id));

-- ============================================================================
-- Table: setlists (11 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Admins and members can delete setlists" ON public.setlists;
DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
DROP POLICY IF EXISTS "setlists_delete_creator_or_admin" ON public.setlists;
DROP POLICY IF EXISTS "Admins and members can create setlists" ON public.setlists;
DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
DROP POLICY IF EXISTS "setlists_insert_members" ON public.setlists;
DROP POLICY IF EXISTS "Band members can view setlists" ON public.setlists;
DROP POLICY IF EXISTS "setlists_select_members" ON public.setlists;
DROP POLICY IF EXISTS "Admins and members can update setlists" ON public.setlists;
DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
DROP POLICY IF EXISTS "setlists_update_creator_or_admin" ON public.setlists;

-- CREATE consolidated policies
-- Known Issue — Not Fixed Here: This preserves contributor-role DELETE access, which is broader than PROJECT_CONTEXT.md RBAC table suggests. Fixing this over-permissiveness is out of scope for this performance-focused feature.
CREATE POLICY "setlists_delete_members" ON public.setlists
FOR DELETE TO authenticated
USING (is_band_member(band_id) OR created_by = (select auth.uid()));

-- Known Issue — Not Fixed Here: This preserves contributor-role INSERT access, which is broader than PROJECT_CONTEXT.md RBAC table suggests.
CREATE POLICY "setlists_insert_members" ON public.setlists
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));

CREATE POLICY "setlists_select_members" ON public.setlists
FOR SELECT TO authenticated
USING (is_band_member(band_id));

-- Known Issue — Not Fixed Here: This preserves contributor-role UPDATE access, which is broader than PROJECT_CONTEXT.md RBAC table suggests.
CREATE POLICY "setlists_update_members" ON public.setlists
FOR UPDATE TO authenticated
USING (is_band_member(band_id) OR created_by = (select auth.uid()))
WITH CHECK (is_band_member(band_id) OR created_by = (select auth.uid()));

-- ============================================================================
-- Table: setlist_songs (9 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs;
DROP POLICY IF EXISTS "setlist_songs_delete_members" ON public.setlist_songs;
DROP POLICY IF EXISTS "Users can create setlist songs if they can access the setlist" ON public.setlist_songs;
DROP POLICY IF EXISTS "setlist_songs_insert_members" ON public.setlist_songs;
DROP POLICY IF EXISTS "Band members can view setlist songs" ON public.setlist_songs;
DROP POLICY IF EXISTS "Users can view setlist songs if they can view the setlist" ON public.setlist_songs;
DROP POLICY IF EXISTS "setlist_songs_select_members" ON public.setlist_songs;
DROP POLICY IF EXISTS "Users can update setlist songs if they can access the setlist" ON public.setlist_songs;
DROP POLICY IF EXISTS "setlist_songs_update_members" ON public.setlist_songs;

-- CREATE consolidated policies
CREATE POLICY "setlist_songs_delete_members" ON public.setlist_songs
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM setlists s
  WHERE s.id = setlist_songs.setlist_id
    AND is_band_member(s.band_id)
));

CREATE POLICY "setlist_songs_insert_members" ON public.setlist_songs
FOR INSERT TO authenticated
WITH CHECK (EXISTS (
  SELECT 1 FROM setlists s
  WHERE s.id = setlist_songs.setlist_id
    AND is_band_member(s.band_id)
));

CREATE POLICY "setlist_songs_select_members" ON public.setlist_songs
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM setlists s
  WHERE s.id = setlist_songs.setlist_id
    AND is_band_member(s.band_id)
));

CREATE POLICY "setlist_songs_update_members" ON public.setlist_songs
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM setlists s
  WHERE s.id = setlist_songs.setlist_id
    AND is_band_member(s.band_id)
))
WITH CHECK (EXISTS (
  SELECT 1 FROM setlists s
  WHERE s.id = setlist_songs.setlist_id
    AND is_band_member(s.band_id)
));

-- ============================================================================
-- Table: rehearsals (9 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Admins and members can delete rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "rehearsals_delete_admin" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "rehearsals_insert_members" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can view rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "rehearsals_select_band_members" ON public.rehearsals;
DROP POLICY IF EXISTS "rehearsals_select_members" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "rehearsals_update_admin" ON public.rehearsals;

-- CREATE consolidated policies
-- Note: Preserves member-role DELETE access per PROJECT_CONTEXT.md RBAC table (not just admin)
CREATE POLICY "rehearsals_delete_members" ON public.rehearsals
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = rehearsals.band_id
    AND bm.user_id = (select auth.uid())
    AND bm.status = 'active'
    AND bm.role IN ('admin', 'member')
));

CREATE POLICY "rehearsals_insert_members" ON public.rehearsals
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));

CREATE POLICY "rehearsals_select_members" ON public.rehearsals
FOR SELECT TO authenticated
USING (is_band_member(band_id));

-- Note: Preserves member-role UPDATE access per PROJECT_CONTEXT.md RBAC table (not just admin)
CREATE POLICY "rehearsals_update_members" ON public.rehearsals
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = rehearsals.band_id
    AND bm.user_id = (select auth.uid())
    AND bm.status = 'active'
    AND bm.role IN ('admin', 'member')
))
WITH CHECK (EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = rehearsals.band_id
    AND bm.user_id = (select auth.uid())
    AND bm.status = 'active'
    AND bm.role IN ('admin', 'member')
));

-- ============================================================================
-- Table: songs (6 policies → 3 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Songs can be created by authenticated users" ON public.songs;
DROP POLICY IF EXISTS "songs: insert if member" ON public.songs;
DROP POLICY IF EXISTS "Band members can view songs" ON public.songs;
DROP POLICY IF EXISTS "Songs are viewable by authenticated users" ON public.songs;
DROP POLICY IF EXISTS "songs_select_authenticated" ON public.songs;
DROP POLICY IF EXISTS "authenticated_members_can_update_songs" ON public.songs;

-- CREATE consolidated policies
-- Known Issue — Not Fixed Here: Effective access is unrestricted for any authenticated user (no band-membership check). Likely intentional for "Legacy songs with NULL band_id" global-catalog design, but out of scope to verify or fix here.
CREATE POLICY "songs_insert_authenticated" ON public.songs
FOR INSERT TO authenticated
WITH CHECK (true);

-- Known Issue — Not Fixed Here: Unrestricted SELECT for any authenticated user regardless of band membership
CREATE POLICY "songs_select_authenticated" ON public.songs
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "songs_update_members" ON public.songs
FOR UPDATE TO authenticated
USING (is_band_member(band_id))
WITH CHECK (is_band_member(band_id));

-- ============================================================================
-- Table: profiles (8 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles: insert own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles: select bandmates" ON public.profiles;
DROP POLICY IF EXISTS "profiles: select own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles: update own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

-- CREATE consolidated policies
CREATE POLICY "profiles_delete_own" ON public.profiles
FOR DELETE TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY "profiles_insert_own" ON public.profiles
FOR INSERT TO authenticated
WITH CHECK (id = (select auth.uid()));

CREATE POLICY "profiles_select_own_or_bandmates" ON public.profiles
FOR SELECT TO authenticated
USING (id = (select auth.uid()) OR id IN (
  SELECT bm2.user_id
  FROM band_members bm1
  JOIN band_members bm2 ON bm1.band_id = bm2.band_id
  WHERE bm1.user_id = (select auth.uid())
    AND bm1.status IN ('active', 'invited')
    AND bm2.status IN ('active', 'invited')
));

CREATE POLICY "profiles_update_own" ON public.profiles
FOR UPDATE TO authenticated
USING (id = (select auth.uid()))
WITH CHECK (id = (select auth.uid()));

-- ============================================================================
-- Table: users (8 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "users_delete_own" ON public.users;
DROP POLICY IF EXISTS "users: insert own" ON public.users;
DROP POLICY IF EXISTS "users_insert_own" ON public.users;
DROP POLICY IF EXISTS "users: select bandmates" ON public.users;
DROP POLICY IF EXISTS "users: select own" ON public.users;
DROP POLICY IF EXISTS "users_select_own" ON public.users;
DROP POLICY IF EXISTS "users: update own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;

-- CREATE consolidated policies
CREATE POLICY "users_delete_own" ON public.users
FOR DELETE TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY "users_insert_own" ON public.users
FOR INSERT TO authenticated
WITH CHECK (id = (select auth.uid()));

CREATE POLICY "users_select_own_or_bandmates" ON public.users
FOR SELECT TO authenticated
USING (id = (select auth.uid()) OR id IN (
  SELECT get_bandmate_user_ids((select auth.uid()))
));

CREATE POLICY "users_update_own" ON public.users
FOR UPDATE TO authenticated
USING (id = (select auth.uid()))
WITH CHECK (id = (select auth.uid()));

-- ============================================================================
-- Table: gig_responses (8 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Band members can delete gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "gig_responses_delete_own" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can create gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "gig_responses_insert_own" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can view gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "gig_responses_select_members" ON public.gig_responses;
DROP POLICY IF EXISTS "Users can update their own gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "gig_responses_update_own" ON public.gig_responses;

-- CREATE consolidated policies
CREATE POLICY "gig_responses_delete_own" ON public.gig_responses
FOR DELETE TO authenticated
USING (user_id = (select auth.uid()));

CREATE POLICY "gig_responses_insert_own" ON public.gig_responses
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()) AND EXISTS (
  SELECT 1 FROM gigs g
  WHERE g.id = gig_responses.gig_id
    AND is_band_member(g.band_id)
));

CREATE POLICY "gig_responses_select_members" ON public.gig_responses
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM gigs g
  WHERE g.id = gig_responses.gig_id
    AND is_band_member(g.band_id)
));

CREATE POLICY "gig_responses_update_own" ON public.gig_responses
FOR UPDATE TO authenticated
USING (user_id = (select auth.uid()) AND EXISTS (
  SELECT 1 FROM gigs g
  WHERE g.id = gig_responses.gig_id
    AND is_band_member(g.band_id)
))
WITH CHECK (user_id = (select auth.uid()) AND EXISTS (
  SELECT 1 FROM gigs g
  WHERE g.id = gig_responses.gig_id
    AND is_band_member(g.band_id)
));

-- ============================================================================
-- Table: band_members (4 policies → 3 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Band members can insert band members" ON public.band_members;
DROP POLICY IF EXISTS "Active members can view band co-members" ON public.band_members;
DROP POLICY IF EXISTS "Users can view own memberships" ON public.band_members;
DROP POLICY IF EXISTS "Admins can update band members" ON public.band_members;

-- CREATE consolidated policies
CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id) OR user_id = (select auth.uid()));

CREATE POLICY "band_members_select_own_or_bandmates" ON public.band_members
FOR SELECT TO authenticated
USING (user_id = (select auth.uid()) OR is_band_member(band_id));

CREATE POLICY "band_members_update_admins" ON public.band_members
FOR UPDATE TO authenticated
USING (is_band_member(band_id) AND EXISTS (
  SELECT 1 FROM band_members admin_check
  WHERE admin_check.band_id = band_members.band_id
    AND admin_check.user_id = (select auth.uid())
    AND admin_check.role = 'admin'
    AND admin_check.status = 'active'
))
WITH CHECK (is_band_member(band_id) AND EXISTS (
  SELECT 1 FROM band_members admin_check
  WHERE admin_check.band_id = band_members.band_id
    AND admin_check.user_id = (select auth.uid())
    AND admin_check.role = 'admin'
    AND admin_check.status = 'active'
));

-- ============================================================================
-- Table: contributor_permissions (2 policies → 4 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "Admins can manage contributor permissions" ON public.contributor_permissions;
DROP POLICY IF EXISTS "Band members can view contributor permissions" ON public.contributor_permissions;

-- CREATE consolidated policies
-- Note: Split original ALL-command policy into per-command policies (INSERT/UPDATE/DELETE only) to achieve one policy per action
CREATE POLICY "contributor_permissions_insert_admins" ON public.contributor_permissions
FOR INSERT TO authenticated
WITH CHECK (EXISTS (
  SELECT 1 FROM band_members admin_bm
  JOIN band_members target_bm ON admin_bm.band_id = target_bm.band_id
  WHERE target_bm.id = contributor_permissions.band_member_id
    AND admin_bm.user_id = (select auth.uid())
    AND admin_bm.role = 'admin'
    AND admin_bm.status = 'active'
));

CREATE POLICY "contributor_permissions_update_admins" ON public.contributor_permissions
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members admin_bm
  JOIN band_members target_bm ON admin_bm.band_id = target_bm.band_id
  WHERE target_bm.id = contributor_permissions.band_member_id
    AND admin_bm.user_id = (select auth.uid())
    AND admin_bm.role = 'admin'
    AND admin_bm.status = 'active'
))
WITH CHECK (EXISTS (
  SELECT 1 FROM band_members admin_bm
  JOIN band_members target_bm ON admin_bm.band_id = target_bm.band_id
  WHERE target_bm.id = contributor_permissions.band_member_id
    AND admin_bm.user_id = (select auth.uid())
    AND admin_bm.role = 'admin'
    AND admin_bm.status = 'active'
));

CREATE POLICY "contributor_permissions_delete_admins" ON public.contributor_permissions
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members admin_bm
  JOIN band_members target_bm ON admin_bm.band_id = target_bm.band_id
  WHERE target_bm.id = contributor_permissions.band_member_id
    AND admin_bm.user_id = (select auth.uid())
    AND admin_bm.role = 'admin'
    AND admin_bm.status = 'active'
));

CREATE POLICY "contributor_permissions_select_members" ON public.contributor_permissions
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members bm1
  JOIN band_members bm2 ON bm1.band_id = bm2.band_id
  WHERE bm2.id = contributor_permissions.band_member_id
    AND bm1.user_id = (select auth.uid())
    AND bm1.status = 'active'
));

-- ============================================================================
-- Table: user_band_roles (4 policies → 3 consolidated)
-- ============================================================================

-- DROP existing policies
DROP POLICY IF EXISTS "ubr: insert own" ON public.user_band_roles;
DROP POLICY IF EXISTS "ubr: select bandmates" ON public.user_band_roles;
DROP POLICY IF EXISTS "ubr: select own" ON public.user_band_roles;
DROP POLICY IF EXISTS "ubr: update own" ON public.user_band_roles;

-- CREATE consolidated policies
CREATE POLICY "user_band_roles_insert_own" ON public.user_band_roles
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "user_band_roles_select_own_or_bandmates" ON public.user_band_roles
FOR SELECT TO authenticated
USING (user_id = (select auth.uid()) OR EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = user_band_roles.band_id
    AND bm.user_id = (select auth.uid())
    AND bm.status IN ('active', 'invited')
));

CREATE POLICY "user_band_roles_update_own" ON public.user_band_roles
FOR UPDATE TO authenticated
USING (user_id = (select auth.uid()))
WITH CHECK (user_id = (select auth.uid()));
