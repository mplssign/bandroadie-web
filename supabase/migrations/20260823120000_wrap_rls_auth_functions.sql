-- ============================================================================
-- Wrap auth function calls in RLS policies for performance optimization
-- ============================================================================
-- Feature: rls-policy-performance-hardening
-- Issue: RLS policies call auth.uid() and auth.role() directly, causing
--        Postgres to re-evaluate per row instead of per query (InitPlan)
-- Fix: Wrap auth function calls in (select ...) subselects to force
--      plan-time evaluation and cache result for query lifetime
-- ============================================================================
-- Performance Advisor: 124 auth_rls_initplan warnings (auth.uid())
--                      2 policies with auth.role() (songs table)
--                      32 tables affected
-- ============================================================================
-- Rollback: See PRE_MIGRATION_RLS_STATE.md for exact policy definitions
-- ============================================================================


-- ===========================================================================
-- TABLE: band_access_events
-- ===========================================================================

-- Policy: Allow insert for authenticated
-- Old WITH CHECK: ((auth.uid() IS NOT NULL) AND (user_id = auth.uid()))...
-- New WITH CHECK: (((select auth.uid()) IS NOT NULL) AND (user_id = (select auth.uid())))...
DROP POLICY IF EXISTS "Allow insert for authenticated" ON public.band_access_events;
CREATE POLICY "Allow insert for authenticated" ON public.band_access_events
FOR INSERT
WITH CHECK ((((select auth.uid()) IS NOT NULL) AND (user_id = (select auth.uid()))))
;

-- Policy: Users can read own access events
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can read own access events" ON public.band_access_events;
CREATE POLICY "Users can read own access events" ON public.band_access_events
FOR SELECT
USING ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: band_calendar_subscriptions
-- ===========================================================================

-- Policy: Users manage own calendar subscriptions
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users manage own calendar subscriptions" ON public.band_calendar_subscriptions;
CREATE POLICY "Users manage own calendar subscriptions" ON public.band_calendar_subscriptions
FOR ALL
USING ((user_id = (select auth.uid())))
WITH CHECK ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: band_invitations
-- ===========================================================================

-- Policy: Admins can create invitations
-- Old WITH CHECK: ((EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) ...
-- New WITH CHECK: ((EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) ...
DROP POLICY IF EXISTS "Admins can create invitations" ON public.band_invitations;
CREATE POLICY "Admins can create invitations" ON public.band_invitations
FOR INSERT
WITH CHECK (((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.role = 'admin'::band_role_type) AND (band_members.status = 'active'::text)))) AND (invited_by = (select auth.uid()))))
;

-- Policy: band_invitations_delete_member
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
DROP POLICY IF EXISTS "band_invitations_delete_member" ON public.band_invitations;
CREATE POLICY "band_invitations_delete_member" ON public.band_invitations
FOR DELETE
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: band_invitations_select_member
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
DROP POLICY IF EXISTS "band_invitations_select_member" ON public.band_invitations;
CREATE POLICY "band_invitations_select_member" ON public.band_invitations
FOR SELECT
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: band_invitations_update_member
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = band_invitations.band_id) A...
DROP POLICY IF EXISTS "band_invitations_update_member" ON public.band_invitations;
CREATE POLICY "band_invitations_update_member" ON public.band_invitations
FOR UPDATE
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = (select auth.uid()))))))
;


-- ===========================================================================
-- TABLE: band_members
-- ===========================================================================

-- Policy: Admins can update band members
-- Old USING: (is_band_member(band_id) AND (EXISTS ( SELECT 1 FROM band_members admin_check WHERE ((admin_che...
-- New USING: (is_band_member(band_id) AND (EXISTS ( SELECT 1 FROM band_members admin_check WHERE ((admin_che...
-- Old WITH CHECK: (is_band_member(band_id) AND (EXISTS ( SELECT 1 FROM band_members admin_check WHERE ((admin_che...
-- New WITH CHECK: (is_band_member(band_id) AND (EXISTS ( SELECT 1 FROM band_members admin_check WHERE ((admin_che...
DROP POLICY IF EXISTS "Admins can update band members" ON public.band_members;
CREATE POLICY "Admins can update band members" ON public.band_members
FOR UPDATE
USING ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = (select auth.uid())) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))))
WITH CHECK ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = (select auth.uid())) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))))
;

-- Policy: Band members can insert band members
-- Old WITH CHECK: (is_band_member(band_id) OR (user_id = auth.uid()))...
-- New WITH CHECK: (is_band_member(band_id) OR (user_id = (select auth.uid())))...
DROP POLICY IF EXISTS "Band members can insert band members" ON public.band_members;
CREATE POLICY "Band members can insert band members" ON public.band_members
FOR INSERT
WITH CHECK ((is_band_member(band_id) OR (user_id = (select auth.uid()))))
;

-- Policy: Users can view own memberships
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can view own memberships" ON public.band_members;
CREATE POLICY "Users can view own memberships" ON public.band_members
FOR SELECT
USING ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: bands
-- ===========================================================================

-- Policy: Only admins can delete bands
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id) AND (bm.user_id = auth.u...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id) AND (bm.user_id = (selec...
DROP POLICY IF EXISTS "Only admins can delete bands" ON public.bands;
CREATE POLICY "Only admins can delete bands" ON public.bands
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = (select auth.uid())) AND (bm.role = 'admin'::band_role_type) AND (bm.status = 'active'::text)))))
;

-- Policy: bands: delete creator
-- Old USING: (created_by = auth.uid())...
-- New USING: (created_by = (select auth.uid()))...
DROP POLICY IF EXISTS "bands: delete creator" ON public.bands;
CREATE POLICY "bands: delete creator" ON public.bands
FOR DELETE
USING ((created_by = (select auth.uid())))
;

-- Policy: bands: insert own
-- Old WITH CHECK: (created_by = auth.uid())...
-- New WITH CHECK: (created_by = (select auth.uid()))...
DROP POLICY IF EXISTS "bands: insert own" ON public.bands;
CREATE POLICY "bands: insert own" ON public.bands
FOR INSERT
WITH CHECK ((created_by = (select auth.uid())))
;

-- Policy: bands: select my bands
-- Old USING: ((is_deleted = false) AND (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id...
-- New USING: ((is_deleted = false) AND (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id...
DROP POLICY IF EXISTS "bands: select my bands" ON public.bands;
CREATE POLICY "bands: select my bands" ON public.bands
FOR SELECT
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = (select auth.uid())) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text])))))))
;

-- Policy: bands_insert_authenticated
-- Old WITH CHECK: (created_by = auth.uid())...
-- New WITH CHECK: (created_by = (select auth.uid()))...
DROP POLICY IF EXISTS "bands_insert_authenticated" ON public.bands;
CREATE POLICY "bands_insert_authenticated" ON public.bands
FOR INSERT
TO authenticated
WITH CHECK ((created_by = (select auth.uid())))
;

-- Policy: bands_select_members
-- Old USING: ((is_deleted = false) AND (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id...
-- New USING: ((is_deleted = false) AND (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = bands.id...
DROP POLICY IF EXISTS "bands_select_members" ON public.bands;
CREATE POLICY "bands_select_members" ON public.bands
FOR SELECT
TO authenticated
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = ( SELECT (select auth.uid()) AS uid)) AND (bm.status = 'active'::text))))))
;


-- ===========================================================================
-- TABLE: block_dates
-- ===========================================================================

-- Policy: block_dates_delete_own_or_admin
-- Old USING: (((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id))...
-- New USING: (((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id))...
DROP POLICY IF EXISTS "block_dates_delete_own_or_admin" ON public.block_dates;
CREATE POLICY "block_dates_delete_own_or_admin" ON public.block_dates
FOR DELETE
TO authenticated
USING ((((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id)))
;

-- Policy: block_dates_insert_own
-- Old WITH CHECK: (is_band_member(band_id) AND (user_id = auth.uid()))...
-- New WITH CHECK: (is_band_member(band_id) AND (user_id = (select auth.uid())))...
DROP POLICY IF EXISTS "block_dates_insert_own" ON public.block_dates;
CREATE POLICY "block_dates_insert_own" ON public.block_dates
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (user_id = (select auth.uid()))))
;

-- Policy: block_dates_update_own_or_admin
-- Old USING: (((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id))...
-- New USING: (((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id))...
-- Old WITH CHECK: (((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id))...
-- New WITH CHECK: (((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id))...
DROP POLICY IF EXISTS "block_dates_update_own_or_admin" ON public.block_dates;
CREATE POLICY "block_dates_update_own_or_admin" ON public.block_dates
FOR UPDATE
TO authenticated
USING ((((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id)))
WITH CHECK ((((user_id = (select auth.uid())) AND is_band_member(band_id)) OR is_band_admin(band_id)))
;


-- ===========================================================================
-- TABLE: contacts
-- ===========================================================================

-- Policy: Admins and members can create contacts
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can create contacts" ON public.contacts;
CREATE POLICY "Admins and members can create contacts" ON public.contacts
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can delete contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can delete contacts" ON public.contacts;
CREATE POLICY "Admins and members can delete contacts" ON public.contacts
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can update contacts" ON public.contacts;
CREATE POLICY "Admins and members can update contacts" ON public.contacts
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Band members can view contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Band members can view contacts" ON public.contacts;
CREATE POLICY "Band members can view contacts" ON public.contacts
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: contributor_permissions
-- ===========================================================================

-- Policy: Admins can manage contributor permissions
-- Old USING: (EXISTS ( SELECT 1 FROM (band_members admin_bm JOIN band_members target_bm ON ((admin_bm.ban...
-- New USING: (EXISTS ( SELECT 1 FROM (band_members admin_bm JOIN band_members target_bm ON ((admin_bm.ban...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM (band_members admin_bm JOIN band_members target_bm ON ((admin_bm.ban...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM (band_members admin_bm JOIN band_members target_bm ON ((admin_bm.ban...
DROP POLICY IF EXISTS "Admins can manage contributor permissions" ON public.contributor_permissions;
CREATE POLICY "Admins can manage contributor permissions" ON public.contributor_permissions
FOR ALL
USING ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = (select auth.uid())) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = (select auth.uid())) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))))
;

-- Policy: Band members can view contributor permissions
-- Old USING: (EXISTS ( SELECT 1 FROM (band_members bm1 JOIN band_members bm2 ON ((bm1.band_id = bm2.band_...
-- New USING: (EXISTS ( SELECT 1 FROM (band_members bm1 JOIN band_members bm2 ON ((bm1.band_id = bm2.band_...
DROP POLICY IF EXISTS "Band members can view contributor permissions" ON public.contributor_permissions;
CREATE POLICY "Band members can view contributor permissions" ON public.contributor_permissions
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm2.id = contributor_permissions.band_member_id) AND (bm1.user_id = (select auth.uid())) AND (bm1.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: device_tokens
-- ===========================================================================

-- Policy: Users can delete own device tokens
-- Old USING: (auth.uid() = user_id)...
-- New USING: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can delete own device tokens" ON public.device_tokens;
CREATE POLICY "Users can delete own device tokens" ON public.device_tokens
FOR DELETE
USING (((select auth.uid()) = user_id))
;

-- Policy: Users can insert own device tokens
-- Old WITH CHECK: (auth.uid() = user_id)...
-- New WITH CHECK: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can insert own device tokens" ON public.device_tokens;
CREATE POLICY "Users can insert own device tokens" ON public.device_tokens
FOR INSERT
WITH CHECK (((select auth.uid()) = user_id))
;

-- Policy: Users can update own device tokens
-- Old USING: (auth.uid() = user_id)...
-- New USING: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can update own device tokens" ON public.device_tokens;
CREATE POLICY "Users can update own device tokens" ON public.device_tokens
FOR UPDATE
USING (((select auth.uid()) = user_id))
;

-- Policy: Users can view own device tokens
-- Old USING: (auth.uid() = user_id)...
-- New USING: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can view own device tokens" ON public.device_tokens;
CREATE POLICY "Users can view own device tokens" ON public.device_tokens
FOR SELECT
USING (((select auth.uid()) = user_id))
;


-- ===========================================================================
-- TABLE: enrichment_settings
-- ===========================================================================

-- Policy: Admins and members can update enrichment settings
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
DROP POLICY IF EXISTS "Admins and members can update enrichment settings" ON public.enrichment_settings;
CREATE POLICY "Admins and members can update enrichment settings" ON public.enrichment_settings
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Band members can insert enrichment settings
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
DROP POLICY IF EXISTS "Band members can insert enrichment settings" ON public.enrichment_settings;
CREATE POLICY "Band members can insert enrichment settings" ON public.enrichment_settings
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;

-- Policy: Band members can view enrichment settings
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = enrichment_settings.band_id) AND (...
DROP POLICY IF EXISTS "Band members can view enrichment settings" ON public.enrichment_settings;
CREATE POLICY "Band members can view enrichment settings" ON public.enrichment_settings
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: feedback
-- ===========================================================================

-- Policy: Users can insert own feedback
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can insert own feedback" ON public.feedback;
CREATE POLICY "Users can insert own feedback" ON public.feedback
FOR INSERT
TO authenticated
WITH CHECK ((user_id = (select auth.uid())))
;

-- Policy: Users can read own feedback
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can read own feedback" ON public.feedback;
CREATE POLICY "Users can read own feedback" ON public.feedback
FOR SELECT
TO authenticated
USING ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: financial_entries
-- ===========================================================================

-- Policy: Admins and members can create financial entries
-- Old WITH CHECK: ((EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (b...
-- New WITH CHECK: ((EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (b...
DROP POLICY IF EXISTS "Admins and members can create financial entries" ON public.financial_entries;
CREATE POLICY "Admins and members can create financial entries" ON public.financial_entries
FOR INSERT
WITH CHECK (((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))) AND (created_by = (select auth.uid()))))
;

-- Policy: Admins and members can delete financial entries
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
DROP POLICY IF EXISTS "Admins and members can delete financial entries" ON public.financial_entries;
CREATE POLICY "Admins and members can delete financial entries" ON public.financial_entries
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update financial entries
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = financial_entries.band_id) AND (bm...
DROP POLICY IF EXISTS "Admins and members can update financial entries" ON public.financial_entries;
CREATE POLICY "Admins and members can update financial entries" ON public.financial_entries
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;


-- ===========================================================================
-- TABLE: gig_dates
-- ===========================================================================

-- Policy: Band members can create gig dates
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
DROP POLICY IF EXISTS "Band members can create gig dates" ON public.gig_dates;
CREATE POLICY "Band members can create gig dates" ON public.gig_dates
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Band members can delete gig dates
-- Old USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
-- New USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
DROP POLICY IF EXISTS "Band members can delete gig dates" ON public.gig_dates;
CREATE POLICY "Band members can delete gig dates" ON public.gig_dates
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Band members can update gig dates
-- Old USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
-- New USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
DROP POLICY IF EXISTS "Band members can update gig dates" ON public.gig_dates;
CREATE POLICY "Band members can update gig dates" ON public.gig_dates
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Band members can view gig dates
-- Old USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
-- New USING: (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band_id = bm.band_id))) WHERE ...
DROP POLICY IF EXISTS "Band members can view gig dates" ON public.gig_dates;
CREATE POLICY "Band members can view gig dates" ON public.gig_dates
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = (select auth.uid()))))))
;


-- ===========================================================================
-- TABLE: gig_responses
-- ===========================================================================

-- Policy: Band members can create gig responses
-- Old WITH CHECK: ((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band...
-- New WITH CHECK: ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON...
DROP POLICY IF EXISTS "Band members can create gig responses" ON public.gig_responses;
CREATE POLICY "Band members can create gig responses" ON public.gig_responses
FOR INSERT
WITH CHECK (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text))))))
;

-- Policy: Band members can delete gig responses
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Band members can delete gig responses" ON public.gig_responses;
CREATE POLICY "Band members can delete gig responses" ON public.gig_responses
FOR DELETE
USING ((user_id = (select auth.uid())))
;

-- Policy: Band members can view gig responses
-- Old USING: (EXISTS ( SELECT 1 FROM (gigs JOIN band_members ON ((band_members.band_id = gigs.band_id))) ...
-- New USING: (EXISTS ( SELECT 1 FROM (gigs JOIN band_members ON ((band_members.band_id = gigs.band_id))) ...
DROP POLICY IF EXISTS "Band members can view gig responses" ON public.gig_responses;
CREATE POLICY "Band members can view gig responses" ON public.gig_responses
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (gigs
     JOIN band_members ON ((band_members.band_id = gigs.band_id)))
  WHERE ((gigs.id = gig_responses.gig_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text)))))
;

-- Policy: Users can update their own gig responses
-- Old USING: ((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON ((g.band...
-- New USING: ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1 FROM (gigs g JOIN band_members bm ON...
DROP POLICY IF EXISTS "Users can update their own gig responses" ON public.gig_responses;
CREATE POLICY "Users can update their own gig responses" ON public.gig_responses
FOR UPDATE
USING (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text))))))
;

-- Policy: gig_responses_delete_own
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "gig_responses_delete_own" ON public.gig_responses;
CREATE POLICY "gig_responses_delete_own" ON public.gig_responses
FOR DELETE
TO authenticated
USING ((user_id = (select auth.uid())))
;

-- Policy: gig_responses_insert_own
-- Old WITH CHECK: ((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_responses.gig_id)...
-- New WITH CHECK: ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_response...
DROP POLICY IF EXISTS "gig_responses_insert_own" ON public.gig_responses;
CREATE POLICY "gig_responses_insert_own" ON public.gig_responses
FOR INSERT
TO authenticated
WITH CHECK (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))))
;

-- Policy: gig_responses_update_own
-- Old USING: ((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_responses.gig_id)...
-- New USING: ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_response...
-- Old WITH CHECK: ((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_responses.gig_id)...
-- New WITH CHECK: ((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1 FROM gigs g WHERE ((g.id = gig_response...
DROP POLICY IF EXISTS "gig_responses_update_own" ON public.gig_responses;
CREATE POLICY "gig_responses_update_own" ON public.gig_responses
FOR UPDATE
TO authenticated
USING (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))))
WITH CHECK (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))))
;


-- ===========================================================================
-- TABLE: gigs
-- ===========================================================================

-- Policy: Band members can create gigs
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = au...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (s...
DROP POLICY IF EXISTS "Band members can create gigs" ON public.gigs;
CREATE POLICY "Band members can create gigs" ON public.gigs
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (EXISTS ( SELECT 1
           FROM contributor_permissions cp
          WHERE ((cp.band_member_id = bm.id) AND (cp.can_create_gigs = true) AND ((cp.can_create_potential_gigs_only = false) OR (gigs.is_potential = true)))))))))))
;

-- Policy: Band members can delete gigs
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = au...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (s...
DROP POLICY IF EXISTS "Band members can delete gigs" ON public.gigs;
CREATE POLICY "Band members can delete gigs" ON public.gigs
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = (select auth.uid()))))))))
;

-- Policy: Band members can update gigs
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = au...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (s...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = au...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (s...
DROP POLICY IF EXISTS "Band members can update gigs" ON public.gigs;
CREATE POLICY "Band members can update gigs" ON public.gigs
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = (select auth.uid()))))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = (select auth.uid()))))))))
;

-- Policy: Band members can view gigs
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = gigs.band_id) AND (band_mem...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = gigs.band_id) AND (band_mem...
DROP POLICY IF EXISTS "Band members can view gigs" ON public.gigs;
CREATE POLICY "Band members can view gigs" ON public.gigs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = gigs.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: notification_preferences
-- ===========================================================================

-- Policy: Users can insert own notification preferences
-- Old WITH CHECK: (auth.uid() = user_id)...
-- New WITH CHECK: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can insert own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can insert own notification preferences" ON public.notification_preferences
FOR INSERT
WITH CHECK (((select auth.uid()) = user_id))
;

-- Policy: Users can update own notification preferences
-- Old USING: (auth.uid() = user_id)...
-- New USING: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can update own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can update own notification preferences" ON public.notification_preferences
FOR UPDATE
USING (((select auth.uid()) = user_id))
;

-- Policy: Users can view own notification preferences
-- Old USING: (auth.uid() = user_id)...
-- New USING: ((select auth.uid()) = user_id)...
DROP POLICY IF EXISTS "Users can view own notification preferences" ON public.notification_preferences;
CREATE POLICY "Users can view own notification preferences" ON public.notification_preferences
FOR SELECT
USING (((select auth.uid()) = user_id))
;


-- ===========================================================================
-- TABLE: notifications
-- ===========================================================================

-- Policy: Users can update own notifications
-- Old USING: (auth.uid() = recipient_user_id)...
-- New USING: ((select auth.uid()) = recipient_user_id)...
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE
USING (((select auth.uid()) = recipient_user_id))
;

-- Policy: Users can view own notifications
-- Old USING: (auth.uid() = recipient_user_id)...
-- New USING: ((select auth.uid()) = recipient_user_id)...
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT
USING (((select auth.uid()) = recipient_user_id))
;


-- ===========================================================================
-- TABLE: print_templates
-- ===========================================================================

-- Policy: Users can manage print templates for their bands
-- Old USING: (band_id IN ( SELECT bm.band_id FROM band_members bm WHERE (bm.user_id = auth.uid())))...
-- New USING: (band_id IN ( SELECT bm.band_id FROM band_members bm WHERE (bm.user_id = (select auth.uid()))))...
-- Old WITH CHECK: (band_id IN ( SELECT bm.band_id FROM band_members bm WHERE (bm.user_id = auth.uid())))...
-- New WITH CHECK: (band_id IN ( SELECT bm.band_id FROM band_members bm WHERE (bm.user_id = (select auth.uid()))))...
DROP POLICY IF EXISTS "Users can manage print templates for their bands" ON public.print_templates;
CREATE POLICY "Users can manage print templates for their bands" ON public.print_templates
FOR ALL
USING ((band_id IN ( SELECT bm.band_id
   FROM band_members bm
  WHERE (bm.user_id = (select auth.uid())))))
WITH CHECK ((band_id IN ( SELECT bm.band_id
   FROM band_members bm
  WHERE (bm.user_id = (select auth.uid())))))
;


-- ===========================================================================
-- TABLE: profiles
-- ===========================================================================

-- Policy: profiles: insert own
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles: insert own" ON public.profiles;
CREATE POLICY "profiles: insert own" ON public.profiles
FOR INSERT
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: profiles: select bandmates
-- Old USING: (id IN ( SELECT bm2.user_id FROM (band_members bm1 JOIN band_members bm2 ON ((bm1.band_id = ...
-- New USING: (id IN ( SELECT bm2.user_id FROM (band_members bm1 JOIN band_members bm2 ON ((bm1.band_id = ...
DROP POLICY IF EXISTS "profiles: select bandmates" ON public.profiles;
CREATE POLICY "profiles: select bandmates" ON public.profiles
FOR SELECT
USING ((id IN ( SELECT bm2.user_id
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm1.user_id = (select auth.uid())) AND (bm1.status = ANY (ARRAY['active'::text, 'invited'::text])) AND (bm2.status = ANY (ARRAY['active'::text, 'invited'::text]))))))
;

-- Policy: profiles: select own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles: select own" ON public.profiles;
CREATE POLICY "profiles: select own" ON public.profiles
FOR SELECT
USING ((id = (select auth.uid())))
;

-- Policy: profiles: update own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles: update own" ON public.profiles;
CREATE POLICY "profiles: update own" ON public.profiles
FOR UPDATE
USING ((id = (select auth.uid())))
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: profiles_delete_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
CREATE POLICY "profiles_delete_own" ON public.profiles
FOR DELETE
TO authenticated
USING ((id = (select auth.uid())))
;

-- Policy: profiles_insert_own
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: profiles_select_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles
FOR SELECT
TO authenticated
USING ((id = (select auth.uid())))
;

-- Policy: profiles_update_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
FOR UPDATE
TO authenticated
USING ((id = (select auth.uid())))
WITH CHECK ((id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: rehearsal_dates
-- ===========================================================================

-- Policy: Band members can delete rehearsal dates
-- Old USING: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
-- New USING: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
DROP POLICY IF EXISTS "Band members can delete rehearsal dates" ON public.rehearsal_dates;
CREATE POLICY "Band members can delete rehearsal dates" ON public.rehearsal_dates
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;

-- Policy: Band members can insert rehearsal dates
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
DROP POLICY IF EXISTS "Band members can insert rehearsal dates" ON public.rehearsal_dates;
CREATE POLICY "Band members can insert rehearsal dates" ON public.rehearsal_dates
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;

-- Policy: Band members can view rehearsal dates
-- Old USING: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
-- New USING: (EXISTS ( SELECT 1 FROM (rehearsals r JOIN band_members bm ON ((bm.band_id = r.band_id))) ...
DROP POLICY IF EXISTS "Band members can view rehearsal dates" ON public.rehearsal_dates;
CREATE POLICY "Band members can view rehearsal dates" ON public.rehearsal_dates
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: rehearsal_responses
-- ===========================================================================

-- Policy: Band members can view rehearsal responses
-- Old USING: check_rehearsal_response_access(rehearsal_id, auth.uid())...
-- New USING: check_rehearsal_response_access(rehearsal_id, (select auth.uid()))...
DROP POLICY IF EXISTS "Band members can view rehearsal responses" ON public.rehearsal_responses;
CREATE POLICY "Band members can view rehearsal responses" ON public.rehearsal_responses
FOR SELECT
USING (check_rehearsal_response_access(rehearsal_id, (select auth.uid())))
;

-- Policy: Users can delete own rehearsal responses
-- Old USING: ((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid()))...
-- New USING: ((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid(...
DROP POLICY IF EXISTS "Users can delete own rehearsal responses" ON public.rehearsal_responses;
CREATE POLICY "Users can delete own rehearsal responses" ON public.rehearsal_responses
FOR DELETE
USING (((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid()))))
;

-- Policy: Users can insert own rehearsal responses
-- Old WITH CHECK: ((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid()))...
-- New WITH CHECK: ((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid(...
DROP POLICY IF EXISTS "Users can insert own rehearsal responses" ON public.rehearsal_responses;
CREATE POLICY "Users can insert own rehearsal responses" ON public.rehearsal_responses
FOR INSERT
WITH CHECK (((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid()))))
;

-- Policy: Users can update own rehearsal responses
-- Old USING: ((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid()))...
-- New USING: ((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid(...
-- Old WITH CHECK: ((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid()))...
-- New WITH CHECK: ((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid(...
DROP POLICY IF EXISTS "Users can update own rehearsal responses" ON public.rehearsal_responses;
CREATE POLICY "Users can update own rehearsal responses" ON public.rehearsal_responses
FOR UPDATE
USING (((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid()))))
WITH CHECK (((user_id = (select auth.uid())) AND check_rehearsal_response_access(rehearsal_id, (select auth.uid()))))
;


-- ===========================================================================
-- TABLE: rehearsals
-- ===========================================================================

-- Policy: Admins and members can create rehearsals
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
DROP POLICY IF EXISTS "Admins and members can create rehearsals" ON public.rehearsals;
CREATE POLICY "Admins and members can create rehearsals" ON public.rehearsals
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can delete rehearsals
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
DROP POLICY IF EXISTS "Admins and members can delete rehearsals" ON public.rehearsals;
CREATE POLICY "Admins and members can delete rehearsals" ON public.rehearsals
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update rehearsals
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
DROP POLICY IF EXISTS "Admins and members can update rehearsals" ON public.rehearsals;
CREATE POLICY "Admins and members can update rehearsals" ON public.rehearsals
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Band members can view rehearsals
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
DROP POLICY IF EXISTS "Band members can view rehearsals" ON public.rehearsals;
CREATE POLICY "Band members can view rehearsals" ON public.rehearsals
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;

-- Policy: rehearsals_select_band_members
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_i...
DROP POLICY IF EXISTS "rehearsals_select_band_members" ON public.rehearsals;
CREATE POLICY "rehearsals_select_band_members" ON public.rehearsals
FOR SELECT
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT (select auth.uid()) AS uid)) AND (bm.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: setlist_songs
-- ===========================================================================

-- Policy: Band members can view setlist songs
-- Old USING: (EXISTS ( SELECT 1 FROM (setlists JOIN band_members ON ((band_members.band_id = setlists.ban...
-- New USING: (EXISTS ( SELECT 1 FROM (setlists JOIN band_members ON ((band_members.band_id = setlists.ban...
DROP POLICY IF EXISTS "Band members can view setlist songs" ON public.setlist_songs;
CREATE POLICY "Band members can view setlist songs" ON public.setlist_songs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (setlists
     JOIN band_members ON ((band_members.band_id = setlists.band_id)))
  WHERE ((setlists.id = setlist_songs.setlist_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text)))))
;

-- Policy: Users can create setlist songs if they can access the setlist
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
DROP POLICY IF EXISTS "Users can create setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can create setlist songs if they can access the setlist" ON public.setlist_songs
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Users can delete setlist songs if they can access the setlist
-- Old USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
-- New USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
DROP POLICY IF EXISTS "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Users can update setlist songs if they can access the setlist
-- Old USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
-- New USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
DROP POLICY IF EXISTS "Users can update setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = (select auth.uid()))))))
;

-- Policy: Users can view setlist songs if they can view the setlist
-- Old USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
-- New USING: (EXISTS ( SELECT 1 FROM (setlists s JOIN band_members bm ON ((s.band_id = bm.band_id))) WH...
DROP POLICY IF EXISTS "Users can view setlist songs if they can view the setlist" ON public.setlist_songs;
CREATE POLICY "Users can view setlist songs if they can view the setlist" ON public.setlist_songs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = (select auth.uid()))))))
;


-- ===========================================================================
-- TABLE: setlist_special_items
-- ===========================================================================

-- Policy: Band members can create special items
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
DROP POLICY IF EXISTS "Band members can create special items" ON public.setlist_special_items;
CREATE POLICY "Band members can create special items" ON public.setlist_special_items
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can delete special items
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
DROP POLICY IF EXISTS "Band members can delete special items" ON public.setlist_special_items;
CREATE POLICY "Band members can delete special items" ON public.setlist_special_items
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can update special items
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
DROP POLICY IF EXISTS "Band members can update special items" ON public.setlist_special_items;
CREATE POLICY "Band members can update special items" ON public.setlist_special_items
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can view special items
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlist_special_items.band_...
DROP POLICY IF EXISTS "Band members can view special items" ON public.setlist_special_items;
CREATE POLICY "Band members can view special items" ON public.setlist_special_items
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid()))))))
;


-- ===========================================================================
-- TABLE: setlists
-- ===========================================================================

-- Policy: Admins and members can create setlists
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can create setlists" ON public.setlists;
CREATE POLICY "Admins and members can create setlists" ON public.setlists
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can delete setlists
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can delete setlists" ON public.setlists;
CREATE POLICY "Admins and members can delete setlists" ON public.setlists
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update setlists
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id ...
DROP POLICY IF EXISTS "Admins and members can update setlists" ON public.setlists;
CREATE POLICY "Admins and members can update setlists" ON public.setlists
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Band members can create setlists
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
CREATE POLICY "Band members can create setlists" ON public.setlists
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can delete setlists
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
CREATE POLICY "Band members can delete setlists" ON public.setlists
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can update setlists
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
CREATE POLICY "Band members can update setlists" ON public.setlists
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: Band members can view setlists
-- Old USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
-- New USING: (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = setlists.band_id) AND (band...
DROP POLICY IF EXISTS "Band members can view setlists" ON public.setlists;
CREATE POLICY "Band members can view setlists" ON public.setlists
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = (select auth.uid()))))))
;

-- Policy: setlists_delete_creator_or_admin
-- Old USING: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New USING: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "setlists_delete_creator_or_admin" ON public.setlists;
CREATE POLICY "setlists_delete_creator_or_admin" ON public.setlists
FOR DELETE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
;

-- Policy: setlists_insert_members
-- Old WITH CHECK: (is_band_member(band_id) AND (created_by = auth.uid()))...
-- New WITH CHECK: (is_band_member(band_id) AND (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "setlists_insert_members" ON public.setlists;
CREATE POLICY "setlists_insert_members" ON public.setlists
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (created_by = (select auth.uid()))))
;

-- Policy: setlists_update_creator_or_admin
-- Old USING: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New USING: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
-- Old WITH CHECK: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New WITH CHECK: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "setlists_update_creator_or_admin" ON public.setlists;
CREATE POLICY "setlists_update_creator_or_admin" ON public.setlists
FOR UPDATE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
WITH CHECK ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
;


-- ===========================================================================
-- TABLE: song_notes
-- ===========================================================================

-- Policy: song_notes_delete_creator_or_admin
-- Old USING: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New USING: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "song_notes_delete_creator_or_admin" ON public.song_notes;
CREATE POLICY "song_notes_delete_creator_or_admin" ON public.song_notes
FOR DELETE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
;

-- Policy: song_notes_insert_members
-- Old WITH CHECK: (is_band_member(band_id) AND (created_by = auth.uid()))...
-- New WITH CHECK: (is_band_member(band_id) AND (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "song_notes_insert_members" ON public.song_notes;
CREATE POLICY "song_notes_insert_members" ON public.song_notes
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (created_by = (select auth.uid()))))
;

-- Policy: song_notes_update_creator_or_admin
-- Old USING: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New USING: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
-- Old WITH CHECK: (is_band_admin(band_id) OR (created_by = auth.uid()))...
-- New WITH CHECK: (is_band_admin(band_id) OR (created_by = (select auth.uid())))...
DROP POLICY IF EXISTS "song_notes_update_creator_or_admin" ON public.song_notes;
CREATE POLICY "song_notes_update_creator_or_admin" ON public.song_notes
FOR UPDATE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
WITH CHECK ((is_band_admin(band_id) OR (created_by = (select auth.uid()))))
;


-- ===========================================================================
-- TABLE: songs
-- ===========================================================================

-- Policy: Band members can view songs
-- Old USING: ((band_id IS NULL) OR (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = songs...
-- New USING: ((band_id IS NULL) OR (EXISTS ( SELECT 1 FROM band_members WHERE ((band_members.band_id = songs...
DROP POLICY IF EXISTS "Band members can view songs" ON public.songs;
CREATE POLICY "Band members can view songs" ON public.songs
FOR SELECT
USING (((band_id IS NULL) OR (EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = songs.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text))))))
;

-- Policy: Songs are viewable by authenticated users
-- Old USING: (auth.role() = 'authenticated'::text)...
-- New USING: ((select auth.role()) = 'authenticated'::text)...
DROP POLICY IF EXISTS "Songs are viewable by authenticated users" ON public.songs;
CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
FOR SELECT
USING (((select auth.role()) = 'authenticated'::text))
;

-- Policy: Songs can be created by authenticated users
-- Old WITH CHECK: (auth.role() = 'authenticated'::text)...
-- New WITH CHECK: ((select auth.role()) = 'authenticated'::text)...
DROP POLICY IF EXISTS "Songs can be created by authenticated users" ON public.songs;
CREATE POLICY "Songs can be created by authenticated users" ON public.songs
FOR INSERT
WITH CHECK (((select auth.role()) = 'authenticated'::text))
;


-- ===========================================================================
-- TABLE: user_band_roles
-- ===========================================================================

-- Policy: ubr: insert own
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "ubr: insert own" ON public.user_band_roles;
CREATE POLICY "ubr: insert own" ON public.user_band_roles
FOR INSERT
WITH CHECK ((user_id = (select auth.uid())))
;

-- Policy: ubr: select bandmates
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = user_band_roles.band_id) AND (bm.u...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = user_band_roles.band_id) AND (bm.u...
DROP POLICY IF EXISTS "ubr: select bandmates" ON public.user_band_roles;
CREATE POLICY "ubr: select bandmates" ON public.user_band_roles
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = user_band_roles.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text]))))))
;

-- Policy: ubr: select own
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "ubr: select own" ON public.user_band_roles;
CREATE POLICY "ubr: select own" ON public.user_band_roles
FOR SELECT
USING ((user_id = (select auth.uid())))
;

-- Policy: ubr: update own
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "ubr: update own" ON public.user_band_roles;
CREATE POLICY "ubr: update own" ON public.user_band_roles
FOR UPDATE
USING ((user_id = (select auth.uid())))
WITH CHECK ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: user_calendar_preferences
-- ===========================================================================

-- Policy: Users can insert their own calendar preferences
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can insert their own calendar preferences" ON public.user_calendar_preferences;
CREATE POLICY "Users can insert their own calendar preferences" ON public.user_calendar_preferences
FOR INSERT
WITH CHECK ((user_id = (select auth.uid())))
;

-- Policy: Users can update their own calendar preferences
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
-- Old WITH CHECK: (user_id = auth.uid())...
-- New WITH CHECK: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can update their own calendar preferences" ON public.user_calendar_preferences;
CREATE POLICY "Users can update their own calendar preferences" ON public.user_calendar_preferences
FOR UPDATE
USING ((user_id = (select auth.uid())))
WITH CHECK ((user_id = (select auth.uid())))
;

-- Policy: Users can view their own calendar preferences
-- Old USING: (user_id = auth.uid())...
-- New USING: (user_id = (select auth.uid()))...
DROP POLICY IF EXISTS "Users can view their own calendar preferences" ON public.user_calendar_preferences;
CREATE POLICY "Users can view their own calendar preferences" ON public.user_calendar_preferences
FOR SELECT
USING ((user_id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: users
-- ===========================================================================

-- Policy: users: insert own
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users: insert own" ON public.users;
CREATE POLICY "users: insert own" ON public.users
FOR INSERT
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: users: select bandmates
-- Old USING: (id IN ( SELECT get_bandmate_user_ids(auth.uid()) AS get_bandmate_user_ids))...
-- New USING: (id IN ( SELECT get_bandmate_user_ids((select auth.uid())) AS get_bandmate_user_ids))...
DROP POLICY IF EXISTS "users: select bandmates" ON public.users;
CREATE POLICY "users: select bandmates" ON public.users
FOR SELECT
USING ((id IN ( SELECT get_bandmate_user_ids((select auth.uid())) AS get_bandmate_user_ids)))
;

-- Policy: users: select own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users: select own" ON public.users;
CREATE POLICY "users: select own" ON public.users
FOR SELECT
USING ((id = (select auth.uid())))
;

-- Policy: users: update own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users: update own" ON public.users;
CREATE POLICY "users: update own" ON public.users
FOR UPDATE
USING ((id = (select auth.uid())))
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: users_delete_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users_delete_own" ON public.users;
CREATE POLICY "users_delete_own" ON public.users
FOR DELETE
TO authenticated
USING ((id = (select auth.uid())))
;

-- Policy: users_insert_own
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users_insert_own" ON public.users;
CREATE POLICY "users_insert_own" ON public.users
FOR INSERT
TO authenticated
WITH CHECK ((id = (select auth.uid())))
;

-- Policy: users_select_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users_select_own" ON public.users;
CREATE POLICY "users_select_own" ON public.users
FOR SELECT
TO authenticated
USING ((id = (select auth.uid())))
;

-- Policy: users_update_own
-- Old USING: (id = auth.uid())...
-- New USING: (id = (select auth.uid()))...
-- Old WITH CHECK: (id = auth.uid())...
-- New WITH CHECK: (id = (select auth.uid()))...
DROP POLICY IF EXISTS "users_update_own" ON public.users;
CREATE POLICY "users_update_own" ON public.users
FOR UPDATE
TO authenticated
USING ((id = (select auth.uid())))
WITH CHECK ((id = (select auth.uid())))
;


-- ===========================================================================
-- TABLE: venue_contacts
-- ===========================================================================

-- Policy: Admins and members can create venue contacts
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
DROP POLICY IF EXISTS "Admins and members can create venue contacts" ON public.venue_contacts;
CREATE POLICY "Admins and members can create venue contacts" ON public.venue_contacts
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can delete venue contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
DROP POLICY IF EXISTS "Admins and members can delete venue contacts" ON public.venue_contacts;
CREATE POLICY "Admins and members can delete venue contacts" ON public.venue_contacts
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update venue contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
DROP POLICY IF EXISTS "Admins and members can update venue contacts" ON public.venue_contacts;
CREATE POLICY "Admins and members can update venue contacts" ON public.venue_contacts
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Band members can view venue contacts
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.us...
DROP POLICY IF EXISTS "Band members can view venue contacts" ON public.venue_contacts;
CREATE POLICY "Band members can view venue contacts" ON public.venue_contacts
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;


-- ===========================================================================
-- TABLE: venues
-- ===========================================================================

-- Policy: Admins and members can create venues
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
DROP POLICY IF EXISTS "Admins and members can create venues" ON public.venues;
CREATE POLICY "Admins and members can create venues" ON public.venues
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins and members can update venues
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- Old WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- New WITH CHECK: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
DROP POLICY IF EXISTS "Admins and members can update venues" ON public.venues;
CREATE POLICY "Admins and members can update venues" ON public.venues
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
;

-- Policy: Admins can delete venues
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
DROP POLICY IF EXISTS "Admins can delete venues" ON public.venues;
CREATE POLICY "Admins can delete venues" ON public.venues
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text) AND (bm.role = 'admin'::band_role_type)))))
;

-- Policy: Band members can view venues
-- Old USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
-- New USING: (EXISTS ( SELECT 1 FROM band_members bm WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = ...
DROP POLICY IF EXISTS "Band members can view venues" ON public.venues;
CREATE POLICY "Band members can view venues" ON public.venues
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = (select auth.uid())) AND (bm.status = 'active'::text)))))
;

