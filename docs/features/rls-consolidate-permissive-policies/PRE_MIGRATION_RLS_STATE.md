# Pre-Migration RLS State

**Feature:** `feature/rls-consolidate-permissive-policies`

**Purpose:** This file captures the exact RLS policy definitions for all 11 affected tables before migration execution. It serves as the **sole rollback reference** for this feature. Supabase managed branches cannot be used (migrations 001-072 were never committed to version control, causing branch creation to fail replaying migration 073 against an empty database). Local `supabase start` is unavailable (Tony does not run Docker). This capture is the only way to restore pre-migration policy state if rollback is required.

**Source:** Live `pg_policies` query against project `nekwjxvgbveheooyorjo`, executed 2026-08-25.

**Total Policies:** 78 policies across 11 tables

**Policy Counts by Table:**
- bands: 9 policies
- band_members: 4 policies
- setlists: 11 policies
- setlist_songs: 9 policies
- songs: 6 policies
- rehearsals: 9 policies
- gig_responses: 8 policies
- profiles: 8 policies
- users: 8 policies
- contributor_permissions: 2 policies
- user_band_roles: 4 policies

---

## Table: bands

**Current Policy Count:** 9

CREATE POLICY "Only admins can delete bands" ON public.bands
FOR DELETE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.role = 'admin'::band_role_type) AND (bm.status = 'active'::text)))));

CREATE POLICY "bands: delete creator" ON public.bands
FOR DELETE TO public
USING ((created_by = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bands_delete_admins" ON public.bands
FOR DELETE TO authenticated
USING (is_band_admin(id));

CREATE POLICY "bands: insert own" ON public.bands
FOR INSERT TO public
WITH CHECK ((created_by = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bands_insert_authenticated" ON public.bands
FOR INSERT TO authenticated
WITH CHECK ((created_by = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Band members can view bands" ON public.bands
FOR SELECT TO public
USING (((is_deleted = false) AND is_band_member(id)));

CREATE POLICY "bands: select my bands" ON public.bands
FOR SELECT TO public
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text])))))));

CREATE POLICY "bands_select_members" ON public.bands
FOR SELECT TO authenticated
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) AND (bm.status = 'active'::text))))));

CREATE POLICY "bands_update_admins" ON public.bands
FOR UPDATE TO authenticated
USING (is_band_admin(id))
WITH CHECK (is_band_admin(id));

## Table: band_members

**Current Policy Count:** 4

CREATE POLICY "Band members can insert band members" ON public.band_members
FOR INSERT TO public
WITH CHECK ((is_band_member(band_id) OR (user_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "Active members can view band co-members" ON public.band_members
FOR SELECT TO public
USING (is_band_member(band_id));

CREATE POLICY "Users can view own memberships" ON public.band_members
FOR SELECT TO public
USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Admins can update band members" ON public.band_members
FOR UPDATE TO public
USING ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = ( SELECT auth.uid() AS uid)) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))))
WITH CHECK ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = ( SELECT auth.uid() AS uid)) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))));

## Table: setlists

**Current Policy Count:** 11

CREATE POLICY "Admins and members can delete setlists" ON public.setlists
FOR DELETE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "Band members can delete setlists" ON public.setlists
FOR DELETE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlists_delete_creator_or_admin" ON public.setlists
FOR DELETE TO authenticated
USING ((is_band_admin(band_id) OR (created_by = ( SELECT auth.uid() AS uid))));

CREATE POLICY "Admins and members can create setlists" ON public.setlists
FOR INSERT TO public
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "Band members can create setlists" ON public.setlists
FOR INSERT TO public
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlists_insert_members" ON public.setlists
FOR INSERT TO authenticated
WITH CHECK ((is_band_member(band_id) AND (created_by = ( SELECT auth.uid() AS uid))));

CREATE POLICY "Band members can view setlists" ON public.setlists
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlists_select_members" ON public.setlists
FOR SELECT TO authenticated
USING (is_band_member(band_id));

CREATE POLICY "Admins and members can update setlists" ON public.setlists
FOR UPDATE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "Band members can update setlists" ON public.setlists
FOR UPDATE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlists_update_creator_or_admin" ON public.setlists
FOR UPDATE TO authenticated
USING ((is_band_admin(band_id) OR (created_by = ( SELECT auth.uid() AS uid))))
WITH CHECK ((is_band_admin(band_id) OR (created_by = ( SELECT auth.uid() AS uid))));

## Table: setlist_songs

**Current Policy Count:** 9

CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
FOR DELETE TO public
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlist_songs_delete_members" ON public.setlist_songs
FOR DELETE TO authenticated
USING ((EXISTS ( SELECT 1
   FROM setlists s
  WHERE ((s.id = setlist_songs.setlist_id) AND is_band_member(s.band_id)))));

CREATE POLICY "Users can create setlist songs if they can access the setlist" ON public.setlist_songs
FOR INSERT TO public
WITH CHECK ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlist_songs_insert_members" ON public.setlist_songs
FOR INSERT TO authenticated
WITH CHECK ((EXISTS ( SELECT 1
   FROM setlists s
  WHERE ((s.id = setlist_songs.setlist_id) AND is_band_member(s.band_id)))));

CREATE POLICY "Band members can view setlist songs" ON public.setlist_songs
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM (setlists
     JOIN band_members ON ((band_members.band_id = setlists.band_id)))
  WHERE ((setlists.id = setlist_songs.setlist_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid)) AND (band_members.status = 'active'::text)))));

CREATE POLICY "Users can view setlist songs if they can view the setlist" ON public.setlist_songs
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlist_songs_select_members" ON public.setlist_songs
FOR SELECT TO authenticated
USING ((EXISTS ( SELECT 1
   FROM setlists s
  WHERE ((s.id = setlist_songs.setlist_id) AND is_band_member(s.band_id)))));

CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
FOR UPDATE TO public
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "setlist_songs_update_members" ON public.setlist_songs
FOR UPDATE TO authenticated
USING ((EXISTS ( SELECT 1
   FROM setlists s
  WHERE ((s.id = setlist_songs.setlist_id) AND is_band_member(s.band_id)))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM setlists s
  WHERE ((s.id = setlist_songs.setlist_id) AND is_band_member(s.band_id)))));

## Table: songs

**Current Policy Count:** 6

CREATE POLICY "Songs can be created by authenticated users" ON public.songs
FOR INSERT TO public
WITH CHECK ((( SELECT auth.role() AS role) = 'authenticated'::text));

CREATE POLICY "songs: insert if member" ON public.songs
FOR INSERT TO authenticated
WITH CHECK (((band_id IS NOT NULL) AND is_band_member(band_id)));

CREATE POLICY "Band members can view songs" ON public.songs
FOR SELECT TO public
USING (((band_id IS NULL) OR (EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = songs.band_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid)) AND (band_members.status = 'active'::text))))));

CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
FOR SELECT TO public
USING ((( SELECT auth.role() AS role) = 'authenticated'::text));

CREATE POLICY "songs_select_authenticated" ON public.songs
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "authenticated_members_can_update_songs" ON public.songs
FOR UPDATE TO authenticated
USING (is_band_member(band_id))
WITH CHECK (is_band_member(band_id));

## Table: rehearsals

**Current Policy Count:** 9

CREATE POLICY "Admins and members can delete rehearsals" ON public.rehearsals
FOR DELETE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "rehearsals_delete_admin" ON public.rehearsals
FOR DELETE TO authenticated
USING (is_band_admin(band_id));

CREATE POLICY "Admins and members can create rehearsals" ON public.rehearsals
FOR INSERT TO public
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "rehearsals_insert_members" ON public.rehearsals
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));

CREATE POLICY "Band members can view rehearsals" ON public.rehearsals
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text)))));

CREATE POLICY "rehearsals_select_band_members" ON public.rehearsals
FOR SELECT TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) AND (bm.status = 'active'::text)))));

CREATE POLICY "rehearsals_select_members" ON public.rehearsals
FOR SELECT TO authenticated
USING (is_band_member(band_id));

CREATE POLICY "Admins and members can update rehearsals" ON public.rehearsals
FOR UPDATE TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));

CREATE POLICY "rehearsals_update_admin" ON public.rehearsals
FOR UPDATE TO authenticated
USING (is_band_admin(band_id))
WITH CHECK (is_band_admin(band_id));

## Table: gig_responses

**Current Policy Count:** 8

CREATE POLICY "Band members can delete gig responses" ON public.gig_responses
FOR DELETE TO public
USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "gig_responses_delete_own" ON public.gig_responses
FOR DELETE TO authenticated
USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Band members can create gig responses" ON public.gig_responses
FOR INSERT TO public
WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text))))));

CREATE POLICY "gig_responses_insert_own" ON public.gig_responses
FOR INSERT TO authenticated
WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))));

CREATE POLICY "Band members can view gig responses" ON public.gig_responses
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM (gigs
     JOIN band_members ON ((band_members.band_id = gigs.band_id)))
  WHERE ((gigs.id = gig_responses.gig_id) AND (band_members.user_id = ( SELECT auth.uid() AS uid)) AND (band_members.status = 'active'::text)))));

CREATE POLICY "gig_responses_select_members" ON public.gig_responses
FOR SELECT TO authenticated
USING ((EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id)))));

CREATE POLICY "Users can update their own gig responses" ON public.gig_responses
FOR UPDATE TO public
USING (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text))))));

CREATE POLICY "gig_responses_update_own" ON public.gig_responses
FOR UPDATE TO authenticated
USING (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))))
WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))));

## Table: profiles

**Current Policy Count:** 8

CREATE POLICY "profiles_delete_own" ON public.profiles
FOR DELETE TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles: insert own" ON public.profiles
FOR INSERT TO public
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles_insert_own" ON public.profiles
FOR INSERT TO authenticated
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles: select bandmates" ON public.profiles
FOR SELECT TO public
USING ((id IN ( SELECT bm2.user_id
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm1.user_id = ( SELECT auth.uid() AS uid)) AND (bm1.status = ANY (ARRAY['active'::text, 'invited'::text])) AND (bm2.status = ANY (ARRAY['active'::text, 'invited'::text]))))));

CREATE POLICY "profiles: select own" ON public.profiles
FOR SELECT TO public
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles_select_own" ON public.profiles
FOR SELECT TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles: update own" ON public.profiles
FOR UPDATE TO public
USING ((id = ( SELECT auth.uid() AS uid)))
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "profiles_update_own" ON public.profiles
FOR UPDATE TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)))
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

## Table: users

**Current Policy Count:** 8

CREATE POLICY "users_delete_own" ON public.users
FOR DELETE TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users: insert own" ON public.users
FOR INSERT TO public
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_insert_own" ON public.users
FOR INSERT TO authenticated
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users: select bandmates" ON public.users
FOR SELECT TO public
USING ((id IN ( SELECT get_bandmate_user_ids(( SELECT auth.uid() AS uid)) AS get_bandmate_user_ids)));

CREATE POLICY "users: select own" ON public.users
FOR SELECT TO public
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_select_own" ON public.users
FOR SELECT TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users: update own" ON public.users
FOR UPDATE TO public
USING ((id = ( SELECT auth.uid() AS uid)))
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_update_own" ON public.users
FOR UPDATE TO authenticated
USING ((id = ( SELECT auth.uid() AS uid)))
WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

## Table: contributor_permissions

**Current Policy Count:** 2

CREATE POLICY "Admins can manage contributor permissions" ON public.contributor_permissions
FOR ALL TO public
USING ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = ( SELECT auth.uid() AS uid)) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = ( SELECT auth.uid() AS uid)) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))));

CREATE POLICY "Band members can view contributor permissions" ON public.contributor_permissions
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm2.id = contributor_permissions.band_member_id) AND (bm1.user_id = ( SELECT auth.uid() AS uid)) AND (bm1.status = 'active'::text)))));

## Table: user_band_roles

**Current Policy Count:** 4

CREATE POLICY "ubr: insert own" ON public.user_band_roles
FOR INSERT TO public
WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ubr: select bandmates" ON public.user_band_roles
FOR SELECT TO public
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = user_band_roles.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text]))))));

CREATE POLICY "ubr: select own" ON public.user_band_roles
FOR SELECT TO public
USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ubr: update own" ON public.user_band_roles
FOR UPDATE TO public
USING ((user_id = ( SELECT auth.uid() AS uid)))
WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

---

*End of pre-migration RLS state capture — 78 policies documented*
