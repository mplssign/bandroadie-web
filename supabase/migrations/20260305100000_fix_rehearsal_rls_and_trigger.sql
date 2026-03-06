-- ============================================================================
-- MIGRATION: Fix rehearsal insert failure
-- Date: 2026-03-05
--
-- ROOT CAUSE:
--   1. The RBAC migration (20260302) updated RLS policies for gigs, setlists,
--      and bands but missed the rehearsals table entirely. The dynamic policy
--      drop in Step 3.5 may have removed the old rehearsal policies (they
--      reference band_members), and no new policies were created.
--   2. The notify_rehearsal_created trigger references a non-existent "name"
--      column on the users table (should be first_name/last_name). While the
--      20260220 migration added exception handling, the 20260207 migration
--      may be the active version (no exception handling), causing the AFTER
--      INSERT trigger to roll back the entire rehearsal insert.
--
-- FIX:
--   1. Recreate rehearsal RLS policies with RBAC-aware checks (role + status)
--   2. Fix notify_rehearsal_created to use correct column names AND keep
--      exception handling so triggers never block writes
--
-- SECURITY:
--   - RLS remains enforced on rehearsals
--   - Band membership + active status required for all operations
--   - Admin & member roles can create/edit/delete rehearsals
--   - Contributors cannot create rehearsals (same as gig restriction pattern)
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: Rehearsal RLS Policies (RBAC-aware)
-- ═══════════════════════════════════════════════════════════════════════════

-- Ensure RLS is enabled
ALTER TABLE public.rehearsals ENABLE ROW LEVEL SECURITY;

-- Drop all existing rehearsal policies to start clean
DROP POLICY IF EXISTS "Band members can view rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can delete rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can delete rehearsals" ON public.rehearsals;

-- SELECT: Any active band member can view rehearsals
CREATE POLICY "Band members can view rehearsals" ON public.rehearsals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
    )
  );

-- INSERT: Admin & member can create rehearsals (matches gig pattern)
CREATE POLICY "Admins and members can create rehearsals" ON public.rehearsals
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: Admin & member can update rehearsals
CREATE POLICY "Admins and members can update rehearsals" ON public.rehearsals
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: Admin & member can delete rehearsals
CREATE POLICY "Admins and members can delete rehearsals" ON public.rehearsals
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: Fix notify_rehearsal_created trigger function
-- ═══════════════════════════════════════════════════════════════════════════
-- Uses first_name (correct column) instead of name (does not exist).
-- Preserves recurring rehearsal logic from 20260207 migration.
-- Wraps entire body in exception handler so trigger NEVER blocks inserts.

CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
BEGIN
  -- Entire body wrapped in exception handler: trigger must NEVER block inserts
  BEGIN
    -- Skip notifications for child rehearsals in a recurring series
    IF NEW.parent_rehearsal_id IS NOT NULL THEN
      RETURN NEW;
    END IF;

    -- Get actor first name (uses first_name column, NOT "name")
    BEGIN
      SELECT COALESCE(
        NULLIF(TRIM(first_name), ''),
        SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
        'Someone'
      ) INTO v_actor_name
      FROM users
      WHERE id = auth.uid();
    EXCEPTION
      WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    IF v_actor_name IS NULL OR v_actor_name = '' THEN
      v_actor_name := 'A band member';
    END IF;

    -- Format date as "MAR 4" (uppercase month, no leading zero on day)
    v_rehearsal_date := UPPER(TO_CHAR(NEW.date, 'MON FMDD'));

    v_title := 'Rehearsal Scheduled';

    -- Build recurrence description if this is a recurring rehearsal
    IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
      v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

      IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
        SELECT string_agg(v_day_names[d + 1], ', ')
        INTO v_recurrence_text
        FROM unnest(NEW.recurrence_days) AS d
        ORDER BY d;

        v_recurrence_text := CASE NEW.recurrence_frequency
          WHEN 'weekly' THEN 'on ' || v_recurrence_text
          WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
          WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
          ELSE 'recurring'
        END;
      ELSE
        v_recurrence_text := CASE NEW.recurrence_frequency
          WHEN 'weekly' THEN 'weekly'
          WHEN 'biweekly' THEN 'biweekly'
          WHEN 'monthly' THEN 'monthly'
          ELSE 'recurring'
        END;
      END IF;

      v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
    END IF;

    -- Send notification
    PERFORM notify_band_members(
      NEW.band_id,
      auth.uid(),
      'rehearsal_created',
      v_title,
      v_body,
      jsonb_build_object(
        'rehearsal_id', NEW.id,
        'rehearsal_date', NEW.date,
        'is_recurring', COALESCE(NEW.is_recurring, FALSE),
        'recurrence_frequency', NEW.recurrence_frequency
      )
    );

  EXCEPTION
    WHEN OTHERS THEN
      -- Log warning but NEVER block the rehearsal insert
      RAISE WARNING 'notify_rehearsal_created failed (rehearsal % still created): %',
        NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION notify_rehearsal_created() IS
  'Sends notification when a rehearsal is created. Uses first_name/last_name
   (not name) from users table. For recurring rehearsals, only the parent
   instance triggers a notification. Entire body wrapped in exception handler
   so trigger never blocks inserts.';
