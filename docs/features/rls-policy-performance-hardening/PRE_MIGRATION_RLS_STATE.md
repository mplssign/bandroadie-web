# Pre-Migration RLS State

**Feature:** rls-policy-performance-hardening  
**Capture Date:** 2026-08-24  
**Source:** Production database (`nekwjxvgbveheooyorjo`)  
**Purpose:** Rollback reference for RLS policy auth function wrapping migration

## Summary

This document captures the exact CREATE POLICY definitions for all 126 RLS policies affected by the auth function wrapping optimization (124 policies with `auth.uid()`, 2 policies with `auth.role()`).

**Tables affected:** 32  
**Total policies:** 126

## Rollback Procedure

If the migration must be rolled back:

1. For each policy listed below, execute:
   ```sql
   DROP POLICY IF EXISTS "<policyname>" ON public.<tablename>;
   ```

2. Then execute the exact CREATE POLICY statement shown below for that policy.

3. Verify policy count:
   ```sql
   SELECT COUNT(*) FROM pg_policies 
   WHERE schemaname = 'public' 
     AND (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%'
          OR qual LIKE '%auth.role()%' OR with_check LIKE '%auth.role()%');
   -- Expected: 126
   ```

## Table of Contents


- [`band_access_events`](#band-access-events) (2 policies)
- [`band_calendar_subscriptions`](#band-calendar-subscriptions) (1 policies)
- [`band_invitations`](#band-invitations) (4 policies)
- [`band_members`](#band-members) (3 policies)
- [`bands`](#bands) (6 policies)
- [`block_dates`](#block-dates) (3 policies)
- [`contacts`](#contacts) (4 policies)
- [`contributor_permissions`](#contributor-permissions) (2 policies)
- [`device_tokens`](#device-tokens) (4 policies)
- [`enrichment_settings`](#enrichment-settings) (3 policies)
- [`feedback`](#feedback) (2 policies)
- [`financial_entries`](#financial-entries) (3 policies)
- [`gig_dates`](#gig-dates) (4 policies)
- [`gig_responses`](#gig-responses) (7 policies)
- [`gigs`](#gigs) (4 policies)
- [`notification_preferences`](#notification-preferences) (3 policies)
- [`notifications`](#notifications) (2 policies)
- [`print_templates`](#print-templates) (1 policies)
- [`profiles`](#profiles) (8 policies)
- [`rehearsal_dates`](#rehearsal-dates) (3 policies)
- [`rehearsal_responses`](#rehearsal-responses) (4 policies)
- [`rehearsals`](#rehearsals) (5 policies)
- [`setlist_songs`](#setlist-songs) (5 policies)
- [`setlist_special_items`](#setlist-special-items) (4 policies)
- [`setlists`](#setlists) (10 policies)
- [`song_notes`](#song-notes) (3 policies)
- [`songs`](#songs) (3 policies)
- [`user_band_roles`](#user-band-roles) (4 policies)
- [`user_calendar_preferences`](#user-calendar-preferences) (3 policies)
- [`users`](#users) (8 policies)
- [`venue_contacts`](#venue-contacts) (4 policies)
- [`venues`](#venues) (4 policies)

---

## `band_access_events`

### Allow insert for authenticated

```sql
CREATE POLICY "Allow insert for authenticated" ON public.band_access_events
FOR INSERT
WITH CHECK (((auth.uid() IS NOT NULL) AND (user_id = auth.uid())));
```

### Users can read own access events

```sql
CREATE POLICY "Users can read own access events" ON public.band_access_events
FOR SELECT
USING ((user_id = auth.uid()));
```


## `band_calendar_subscriptions`

### Users manage own calendar subscriptions

```sql
CREATE POLICY "Users manage own calendar subscriptions" ON public.band_calendar_subscriptions
FOR ALL
USING ((user_id = auth.uid()))
WITH CHECK ((user_id = auth.uid()));
```


## `band_invitations`

### Admins can create invitations

```sql
CREATE POLICY "Admins can create invitations" ON public.band_invitations
FOR INSERT
WITH CHECK (((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid()) AND (band_members.role = 'admin'::band_role_type) AND (band_members.status = 'active'::text)))) AND (invited_by = auth.uid())));
```

### band_invitations_delete_member

```sql
CREATE POLICY "band_invitations_delete_member" ON public.band_invitations
FOR DELETE
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid())))));
```

### band_invitations_select_member

```sql
CREATE POLICY "band_invitations_select_member" ON public.band_invitations
FOR SELECT
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid())))));
```

### band_invitations_update_member

```sql
CREATE POLICY "band_invitations_update_member" ON public.band_invitations
FOR UPDATE
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = band_invitations.band_id) AND (band_members.user_id = auth.uid())))));
```


## `band_members`

### Admins can update band members

```sql
CREATE POLICY "Admins can update band members" ON public.band_members
FOR UPDATE
USING ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = auth.uid()) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))))
WITH CHECK ((is_band_member(band_id) AND (EXISTS ( SELECT 1
   FROM band_members admin_check
  WHERE ((admin_check.band_id = band_members.band_id) AND (admin_check.user_id = auth.uid()) AND (admin_check.role = 'admin'::band_role_type) AND (admin_check.status = 'active'::text))))));
```

### Band members can insert band members

```sql
CREATE POLICY "Band members can insert band members" ON public.band_members
FOR INSERT
WITH CHECK ((is_band_member(band_id) OR (user_id = auth.uid())));
```

### Users can view own memberships

```sql
CREATE POLICY "Users can view own memberships" ON public.band_members
FOR SELECT
USING ((user_id = auth.uid()));
```


## `bands`

### Only admins can delete bands

```sql
CREATE POLICY "Only admins can delete bands" ON public.bands
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = auth.uid()) AND (bm.role = 'admin'::band_role_type) AND (bm.status = 'active'::text)))));
```

### bands: delete creator

```sql
CREATE POLICY "bands: delete creator" ON public.bands
FOR DELETE
USING ((created_by = auth.uid()));
```

### bands: insert own

```sql
CREATE POLICY "bands: insert own" ON public.bands
FOR INSERT
WITH CHECK ((created_by = auth.uid()));
```

### bands: select my bands

```sql
CREATE POLICY "bands: select my bands" ON public.bands
FOR SELECT
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = auth.uid()) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text])))))));
```

### bands_insert_authenticated

```sql
CREATE POLICY "bands_insert_authenticated" ON public.bands
FOR INSERT
TO authenticated
WITH CHECK ((created_by = auth.uid()));
```

### bands_select_members

```sql
CREATE POLICY "bands_select_members" ON public.bands
FOR SELECT
TO authenticated
USING (((is_deleted = false) AND (EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = bands.id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text))))));
```


## `block_dates`

### block_dates_delete_own_or_admin

```sql
CREATE POLICY "block_dates_delete_own_or_admin" ON public.block_dates
FOR DELETE
TO authenticated
USING ((((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id)));
```

### block_dates_insert_own

```sql
CREATE POLICY "block_dates_insert_own" ON public.block_dates
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (user_id = auth.uid())));
```

### block_dates_update_own_or_admin

```sql
CREATE POLICY "block_dates_update_own_or_admin" ON public.block_dates
FOR UPDATE
TO authenticated
USING ((((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id)))
WITH CHECK ((((user_id = auth.uid()) AND is_band_member(band_id)) OR is_band_admin(band_id)));
```


## `contacts`

### Admins and members can create contacts

```sql
CREATE POLICY "Admins and members can create contacts" ON public.contacts
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can delete contacts

```sql
CREATE POLICY "Admins and members can delete contacts" ON public.contacts
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update contacts

```sql
CREATE POLICY "Admins and members can update contacts" ON public.contacts
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Band members can view contacts

```sql
CREATE POLICY "Band members can view contacts" ON public.contacts
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```


## `contributor_permissions`

### Admins can manage contributor permissions

```sql
CREATE POLICY "Admins can manage contributor permissions" ON public.contributor_permissions
FOR ALL
USING ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = auth.uid()) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM (band_members admin_bm
     JOIN band_members target_bm ON ((admin_bm.band_id = target_bm.band_id)))
  WHERE ((target_bm.id = contributor_permissions.band_member_id) AND (admin_bm.user_id = auth.uid()) AND (admin_bm.role = 'admin'::band_role_type) AND (admin_bm.status = 'active'::text)))));
```

### Band members can view contributor permissions

```sql
CREATE POLICY "Band members can view contributor permissions" ON public.contributor_permissions
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm2.id = contributor_permissions.band_member_id) AND (bm1.user_id = auth.uid()) AND (bm1.status = 'active'::text)))));
```


## `device_tokens`

### Users can delete own device tokens

```sql
CREATE POLICY "Users can delete own device tokens" ON public.device_tokens
FOR DELETE
USING ((auth.uid() = user_id));
```

### Users can insert own device tokens

```sql
CREATE POLICY "Users can insert own device tokens" ON public.device_tokens
FOR INSERT
WITH CHECK ((auth.uid() = user_id));
```

### Users can update own device tokens

```sql
CREATE POLICY "Users can update own device tokens" ON public.device_tokens
FOR UPDATE
USING ((auth.uid() = user_id));
```

### Users can view own device tokens

```sql
CREATE POLICY "Users can view own device tokens" ON public.device_tokens
FOR SELECT
USING ((auth.uid() = user_id));
```


## `enrichment_settings`

### Admins and members can update enrichment settings

```sql
CREATE POLICY "Admins and members can update enrichment settings" ON public.enrichment_settings
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Band members can insert enrichment settings

```sql
CREATE POLICY "Band members can insert enrichment settings" ON public.enrichment_settings
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```

### Band members can view enrichment settings

```sql
CREATE POLICY "Band members can view enrichment settings" ON public.enrichment_settings
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = enrichment_settings.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```


## `feedback`

### Users can insert own feedback

```sql
CREATE POLICY "Users can insert own feedback" ON public.feedback
FOR INSERT
TO authenticated
WITH CHECK ((user_id = auth.uid()));
```

### Users can read own feedback

```sql
CREATE POLICY "Users can read own feedback" ON public.feedback
FOR SELECT
TO authenticated
USING ((user_id = auth.uid()));
```


## `financial_entries`

### Admins and members can create financial entries

```sql
CREATE POLICY "Admins and members can create financial entries" ON public.financial_entries
FOR INSERT
WITH CHECK (((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))) AND (created_by = auth.uid())));
```

### Admins and members can delete financial entries

```sql
CREATE POLICY "Admins and members can delete financial entries" ON public.financial_entries
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update financial entries

```sql
CREATE POLICY "Admins and members can update financial entries" ON public.financial_entries
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = financial_entries.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```


## `gig_dates`

### Band members can create gig dates

```sql
CREATE POLICY "Band members can create gig dates" ON public.gig_dates
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = auth.uid())))));
```

### Band members can delete gig dates

```sql
CREATE POLICY "Band members can delete gig dates" ON public.gig_dates
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = auth.uid())))));
```

### Band members can update gig dates

```sql
CREATE POLICY "Band members can update gig dates" ON public.gig_dates
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = auth.uid())))));
```

### Band members can view gig dates

```sql
CREATE POLICY "Band members can view gig dates" ON public.gig_dates
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_dates.gig_id) AND (bm.user_id = auth.uid())))));
```


## `gig_responses`

### Band members can create gig responses

```sql
CREATE POLICY "Band members can create gig responses" ON public.gig_responses
FOR INSERT
WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text))))));
```

### Band members can delete gig responses

```sql
CREATE POLICY "Band members can delete gig responses" ON public.gig_responses
FOR DELETE
USING ((user_id = auth.uid()));
```

### Band members can view gig responses

```sql
CREATE POLICY "Band members can view gig responses" ON public.gig_responses
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (gigs
     JOIN band_members ON ((band_members.band_id = gigs.band_id)))
  WHERE ((gigs.id = gig_responses.gig_id) AND (band_members.user_id = auth.uid()) AND (band_members.status = 'active'::text)))));
```

### Users can update their own gig responses

```sql
CREATE POLICY "Users can update their own gig responses" ON public.gig_responses
FOR UPDATE
USING (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (gigs g
     JOIN band_members bm ON ((g.band_id = bm.band_id)))
  WHERE ((g.id = gig_responses.gig_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text))))));
```

### gig_responses_delete_own

```sql
CREATE POLICY "gig_responses_delete_own" ON public.gig_responses
FOR DELETE
TO authenticated
USING ((user_id = auth.uid()));
```

### gig_responses_insert_own

```sql
CREATE POLICY "gig_responses_insert_own" ON public.gig_responses
FOR INSERT
TO authenticated
WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))));
```

### gig_responses_update_own

```sql
CREATE POLICY "gig_responses_update_own" ON public.gig_responses
FOR UPDATE
TO authenticated
USING (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))))
WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM gigs g
  WHERE ((g.id = gig_responses.gig_id) AND is_band_member(g.band_id))))));
```


## `gigs`

### Band members can create gigs

```sql
CREATE POLICY "Band members can create gigs" ON public.gigs
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (EXISTS ( SELECT 1
           FROM contributor_permissions cp
          WHERE ((cp.band_member_id = bm.id) AND (cp.can_create_gigs = true) AND ((cp.can_create_potential_gigs_only = false) OR (gigs.is_potential = true)))))))))));
```

### Band members can delete gigs

```sql
CREATE POLICY "Band members can delete gigs" ON public.gigs
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = auth.uid())))))));
```

### Band members can update gigs

```sql
CREATE POLICY "Band members can update gigs" ON public.gigs
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = auth.uid())))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = gigs.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND ((bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type])) OR ((bm.role = 'contributor'::band_role_type) AND (gigs.is_potential = true) AND (gigs.created_by = auth.uid())))))));
```

### Band members can view gigs

```sql
CREATE POLICY "Band members can view gigs" ON public.gigs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = gigs.band_id) AND (band_members.user_id = auth.uid()) AND (band_members.status = 'active'::text)))));
```


## `notification_preferences`

### Users can insert own notification preferences

```sql
CREATE POLICY "Users can insert own notification preferences" ON public.notification_preferences
FOR INSERT
WITH CHECK ((auth.uid() = user_id));
```

### Users can update own notification preferences

```sql
CREATE POLICY "Users can update own notification preferences" ON public.notification_preferences
FOR UPDATE
USING ((auth.uid() = user_id));
```

### Users can view own notification preferences

```sql
CREATE POLICY "Users can view own notification preferences" ON public.notification_preferences
FOR SELECT
USING ((auth.uid() = user_id));
```


## `notifications`

### Users can update own notifications

```sql
CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE
USING ((auth.uid() = recipient_user_id));
```

### Users can view own notifications

```sql
CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT
USING ((auth.uid() = recipient_user_id));
```


## `print_templates`

### Users can manage print templates for their bands

```sql
CREATE POLICY "Users can manage print templates for their bands" ON public.print_templates
FOR ALL
USING ((band_id IN ( SELECT bm.band_id
   FROM band_members bm
  WHERE (bm.user_id = auth.uid()))))
WITH CHECK ((band_id IN ( SELECT bm.band_id
   FROM band_members bm
  WHERE (bm.user_id = auth.uid()))));
```


## `profiles`

### profiles: insert own

```sql
CREATE POLICY "profiles: insert own" ON public.profiles
FOR INSERT
WITH CHECK ((id = auth.uid()));
```

### profiles: select bandmates

```sql
CREATE POLICY "profiles: select bandmates" ON public.profiles
FOR SELECT
USING ((id IN ( SELECT bm2.user_id
   FROM (band_members bm1
     JOIN band_members bm2 ON ((bm1.band_id = bm2.band_id)))
  WHERE ((bm1.user_id = auth.uid()) AND (bm1.status = ANY (ARRAY['active'::text, 'invited'::text])) AND (bm2.status = ANY (ARRAY['active'::text, 'invited'::text]))))));
```

### profiles: select own

```sql
CREATE POLICY "profiles: select own" ON public.profiles
FOR SELECT
USING ((id = auth.uid()));
```

### profiles: update own

```sql
CREATE POLICY "profiles: update own" ON public.profiles
FOR UPDATE
USING ((id = auth.uid()))
WITH CHECK ((id = auth.uid()));
```

### profiles_delete_own

```sql
CREATE POLICY "profiles_delete_own" ON public.profiles
FOR DELETE
TO authenticated
USING ((id = auth.uid()));
```

### profiles_insert_own

```sql
CREATE POLICY "profiles_insert_own" ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK ((id = auth.uid()));
```

### profiles_select_own

```sql
CREATE POLICY "profiles_select_own" ON public.profiles
FOR SELECT
TO authenticated
USING ((id = auth.uid()));
```

### profiles_update_own

```sql
CREATE POLICY "profiles_update_own" ON public.profiles
FOR UPDATE
TO authenticated
USING ((id = auth.uid()))
WITH CHECK ((id = auth.uid()));
```


## `rehearsal_dates`

### Band members can delete rehearsal dates

```sql
CREATE POLICY "Band members can delete rehearsal dates" ON public.rehearsal_dates
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```

### Band members can insert rehearsal dates

```sql
CREATE POLICY "Band members can insert rehearsal dates" ON public.rehearsal_dates
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```

### Band members can view rehearsal dates

```sql
CREATE POLICY "Band members can view rehearsal dates" ON public.rehearsal_dates
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (rehearsals r
     JOIN band_members bm ON ((bm.band_id = r.band_id)))
  WHERE ((r.id = rehearsal_dates.rehearsal_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```


## `rehearsal_responses`

### Band members can view rehearsal responses

```sql
CREATE POLICY "Band members can view rehearsal responses" ON public.rehearsal_responses
FOR SELECT
USING (check_rehearsal_response_access(rehearsal_id, auth.uid()));
```

### Users can delete own rehearsal responses

```sql
CREATE POLICY "Users can delete own rehearsal responses" ON public.rehearsal_responses
FOR DELETE
USING (((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid())));
```

### Users can insert own rehearsal responses

```sql
CREATE POLICY "Users can insert own rehearsal responses" ON public.rehearsal_responses
FOR INSERT
WITH CHECK (((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid())));
```

### Users can update own rehearsal responses

```sql
CREATE POLICY "Users can update own rehearsal responses" ON public.rehearsal_responses
FOR UPDATE
USING (((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid())))
WITH CHECK (((user_id = auth.uid()) AND check_rehearsal_response_access(rehearsal_id, auth.uid())));
```


## `rehearsals`

### Admins and members can create rehearsals

```sql
CREATE POLICY "Admins and members can create rehearsals" ON public.rehearsals
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can delete rehearsals

```sql
CREATE POLICY "Admins and members can delete rehearsals" ON public.rehearsals
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update rehearsals

```sql
CREATE POLICY "Admins and members can update rehearsals" ON public.rehearsals
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Band members can view rehearsals

```sql
CREATE POLICY "Band members can view rehearsals" ON public.rehearsals
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```

### rehearsals_select_band_members

```sql
CREATE POLICY "rehearsals_select_band_members" ON public.rehearsals
FOR SELECT
TO authenticated
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = rehearsals.band_id) AND (bm.user_id = ( SELECT auth.uid() AS uid)) AND (bm.status = 'active'::text)))));
```


## `setlist_songs`

### Band members can view setlist songs

```sql
CREATE POLICY "Band members can view setlist songs" ON public.setlist_songs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (setlists
     JOIN band_members ON ((band_members.band_id = setlists.band_id)))
  WHERE ((setlists.id = setlist_songs.setlist_id) AND (band_members.user_id = auth.uid()) AND (band_members.status = 'active'::text)))));
```

### Users can create setlist songs if they can access the setlist

```sql
CREATE POLICY "Users can create setlist songs if they can access the setlist" ON public.setlist_songs
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = auth.uid())))));
```

### Users can delete setlist songs if they can access the setlist

```sql
CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = auth.uid())))));
```

### Users can update setlist songs if they can access the setlist

```sql
CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = auth.uid())))));
```

### Users can view setlist songs if they can view the setlist

```sql
CREATE POLICY "Users can view setlist songs if they can view the setlist" ON public.setlist_songs
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM (setlists s
     JOIN band_members bm ON ((s.band_id = bm.band_id)))
  WHERE ((s.id = setlist_songs.setlist_id) AND (bm.user_id = auth.uid())))));
```


## `setlist_special_items`

### Band members can create special items

```sql
CREATE POLICY "Band members can create special items" ON public.setlist_special_items
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can delete special items

```sql
CREATE POLICY "Band members can delete special items" ON public.setlist_special_items
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can update special items

```sql
CREATE POLICY "Band members can update special items" ON public.setlist_special_items
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can view special items

```sql
CREATE POLICY "Band members can view special items" ON public.setlist_special_items
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = auth.uid())))));
```


## `setlists`

### Admins and members can create setlists

```sql
CREATE POLICY "Admins and members can create setlists" ON public.setlists
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can delete setlists

```sql
CREATE POLICY "Admins and members can delete setlists" ON public.setlists
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update setlists

```sql
CREATE POLICY "Admins and members can update setlists" ON public.setlists
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = setlists.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Band members can create setlists

```sql
CREATE POLICY "Band members can create setlists" ON public.setlists
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can delete setlists

```sql
CREATE POLICY "Band members can delete setlists" ON public.setlists
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can update setlists

```sql
CREATE POLICY "Band members can update setlists" ON public.setlists
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = auth.uid())))));
```

### Band members can view setlists

```sql
CREATE POLICY "Band members can view setlists" ON public.setlists
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlists.band_id) AND (band_members.user_id = auth.uid())))));
```

### setlists_delete_creator_or_admin

```sql
CREATE POLICY "setlists_delete_creator_or_admin" ON public.setlists
FOR DELETE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = auth.uid())));
```

### setlists_insert_members

```sql
CREATE POLICY "setlists_insert_members" ON public.setlists
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (created_by = auth.uid())));
```

### setlists_update_creator_or_admin

```sql
CREATE POLICY "setlists_update_creator_or_admin" ON public.setlists
FOR UPDATE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = auth.uid())))
WITH CHECK ((is_band_admin(band_id) OR (created_by = auth.uid())));
```


## `song_notes`

### song_notes_delete_creator_or_admin

```sql
CREATE POLICY "song_notes_delete_creator_or_admin" ON public.song_notes
FOR DELETE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = auth.uid())));
```

### song_notes_insert_members

```sql
CREATE POLICY "song_notes_insert_members" ON public.song_notes
FOR INSERT
TO authenticated
WITH CHECK ((is_band_member(band_id) AND (created_by = auth.uid())));
```

### song_notes_update_creator_or_admin

```sql
CREATE POLICY "song_notes_update_creator_or_admin" ON public.song_notes
FOR UPDATE
TO authenticated
USING ((is_band_admin(band_id) OR (created_by = auth.uid())))
WITH CHECK ((is_band_admin(band_id) OR (created_by = auth.uid())));
```


## `songs`

### Band members can view songs

```sql
CREATE POLICY "Band members can view songs" ON public.songs
FOR SELECT
USING (((band_id IS NULL) OR (EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = songs.band_id) AND (band_members.user_id = auth.uid()) AND (band_members.status = 'active'::text))))));
```

### Songs are viewable by authenticated users

```sql
CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
FOR SELECT
USING ((auth.role() = 'authenticated'::text));
```

### Songs can be created by authenticated users

```sql
CREATE POLICY "Songs can be created by authenticated users" ON public.songs
FOR INSERT
WITH CHECK ((auth.role() = 'authenticated'::text));
```


## `user_band_roles`

### ubr: insert own

```sql
CREATE POLICY "ubr: insert own" ON public.user_band_roles
FOR INSERT
WITH CHECK ((user_id = auth.uid()));
```

### ubr: select bandmates

```sql
CREATE POLICY "ubr: select bandmates" ON public.user_band_roles
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = user_band_roles.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = ANY (ARRAY['active'::text, 'invited'::text]))))));
```

### ubr: select own

```sql
CREATE POLICY "ubr: select own" ON public.user_band_roles
FOR SELECT
USING ((user_id = auth.uid()));
```

### ubr: update own

```sql
CREATE POLICY "ubr: update own" ON public.user_band_roles
FOR UPDATE
USING ((user_id = auth.uid()))
WITH CHECK ((user_id = auth.uid()));
```


## `user_calendar_preferences`

### Users can insert their own calendar preferences

```sql
CREATE POLICY "Users can insert their own calendar preferences" ON public.user_calendar_preferences
FOR INSERT
WITH CHECK ((user_id = auth.uid()));
```

### Users can update their own calendar preferences

```sql
CREATE POLICY "Users can update their own calendar preferences" ON public.user_calendar_preferences
FOR UPDATE
USING ((user_id = auth.uid()))
WITH CHECK ((user_id = auth.uid()));
```

### Users can view their own calendar preferences

```sql
CREATE POLICY "Users can view their own calendar preferences" ON public.user_calendar_preferences
FOR SELECT
USING ((user_id = auth.uid()));
```


## `users`

### users: insert own

```sql
CREATE POLICY "users: insert own" ON public.users
FOR INSERT
WITH CHECK ((id = auth.uid()));
```

### users: select bandmates

```sql
CREATE POLICY "users: select bandmates" ON public.users
FOR SELECT
USING ((id IN ( SELECT get_bandmate_user_ids(auth.uid()) AS get_bandmate_user_ids)));
```

### users: select own

```sql
CREATE POLICY "users: select own" ON public.users
FOR SELECT
USING ((id = auth.uid()));
```

### users: update own

```sql
CREATE POLICY "users: update own" ON public.users
FOR UPDATE
USING ((id = auth.uid()))
WITH CHECK ((id = auth.uid()));
```

### users_delete_own

```sql
CREATE POLICY "users_delete_own" ON public.users
FOR DELETE
TO authenticated
USING ((id = auth.uid()));
```

### users_insert_own

```sql
CREATE POLICY "users_insert_own" ON public.users
FOR INSERT
TO authenticated
WITH CHECK ((id = auth.uid()));
```

### users_select_own

```sql
CREATE POLICY "users_select_own" ON public.users
FOR SELECT
TO authenticated
USING ((id = auth.uid()));
```

### users_update_own

```sql
CREATE POLICY "users_update_own" ON public.users
FOR UPDATE
TO authenticated
USING ((id = auth.uid()))
WITH CHECK ((id = auth.uid()));
```


## `venue_contacts`

### Admins and members can create venue contacts

```sql
CREATE POLICY "Admins and members can create venue contacts" ON public.venue_contacts
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can delete venue contacts

```sql
CREATE POLICY "Admins and members can delete venue contacts" ON public.venue_contacts
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update venue contacts

```sql
CREATE POLICY "Admins and members can update venue contacts" ON public.venue_contacts
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Band members can view venue contacts

```sql
CREATE POLICY "Band members can view venue contacts" ON public.venue_contacts
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venue_contacts.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```


## `venues`

### Admins and members can create venues

```sql
CREATE POLICY "Admins and members can create venues" ON public.venues
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins and members can update venues

```sql
CREATE POLICY "Admins and members can update venues" ON public.venues
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))))
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = ANY (ARRAY['admin'::band_role_type, 'member'::band_role_type]))))));
```

### Admins can delete venues

```sql
CREATE POLICY "Admins can delete venues" ON public.venues
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text) AND (bm.role = 'admin'::band_role_type)))));
```

### Band members can view venues

```sql
CREATE POLICY "Band members can view venues" ON public.venues
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members bm
  WHERE ((bm.band_id = venues.band_id) AND (bm.user_id = auth.uid()) AND (bm.status = 'active'::text)))));
```


