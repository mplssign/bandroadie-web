-- ============================================================================
-- FIX: Add exception handlers to notification trigger functions
-- Created: 2026-02-20
-- Purpose: Prevent notification failures from blocking event creation
--
-- ROOT CAUSE:
--   After replacing notify_band_members() to INSERT into notifications
--   (instead of the old pg_notify()), any failure in the notification chain
--   propagates back and blocks the gig/rehearsal INSERT. The original fix
--   only wrapped the PERFORM call, leaving the SELECT FROM users outside
--   the exception handler.
--
-- FIX:
--   Wrap the ENTIRE body of every trigger function in a single
--   BEGIN ... EXCEPTION WHEN OTHERS block so that NO error in the
--   notification path can ever block event creation.
-- ============================================================================

-- 1. Fix notify_band_members: add EXCEPTION handler around INSERT loop
CREATE OR REPLACE FUNCTION notify_band_members(
  p_band_id UUID,
  p_actor_user_id UUID,
  p_notification_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
BEGIN
  FOR v_member IN
    SELECT user_id
      FROM band_members
     WHERE band_id = p_band_id
       AND user_id != COALESCE(p_actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    BEGIN
      INSERT INTO notifications (
        band_id,
        recipient_user_id,
        type,
        title,
        body,
        metadata,
        actor_user_id
      ) VALUES (
        p_band_id,
        v_member.user_id,
        p_notification_type,
        COALESCE(p_title, 'New Activity'),
        COALESCE(p_body, 'Something happened in your band'),
        COALESCE(p_metadata, '{}'::jsonb),
        p_actor_user_id
      );
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_band_members: failed for user %: %',
          v_member.user_id, SQLERRM;
    END;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_band_members failed entirely: %', SQLERRM;
END;
$$;

-- 2. Fix notify_gig_created: ENTIRE body in exception handler
CREATE OR REPLACE FUNCTION notify_gig_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_gig_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_notification_type TEXT;
BEGIN
  -- Everything in one exception block — nothing can block the gig INSERT
  BEGIN
    -- Get actor name (with fallback)
    BEGIN
      SELECT COALESCE(name, 'A band member') INTO v_actor_name
      FROM users
      WHERE id = auth.uid();
    EXCEPTION
      WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    IF v_actor_name IS NULL THEN
      v_actor_name := 'A band member';
    END IF;

    v_gig_date := UPPER(TO_CHAR(NEW.date, 'MON DD, YYYY'));

    IF NEW.is_potential THEN
      v_notification_type := 'potential_gig_created';
      v_body := v_actor_name || ' created a potential gig for ' || v_gig_date;
    ELSE
      v_notification_type := 'gig_created';
      v_body := v_actor_name || ' created a gig for ' || v_gig_date;
    END IF;

    v_title := COALESCE(NEW.name, 'New Gig');

    PERFORM notify_band_members(
      NEW.band_id,
      auth.uid(),
      v_notification_type,
      v_title,
      v_body,
      jsonb_build_object('gig_id', NEW.id, 'gig_date', NEW.date)
    );
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'notify_gig_created failed (gig % still created): %',
        NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- 3. Fix notify_rehearsal_created: ENTIRE body in exception handler
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
BEGIN
  BEGIN
    BEGIN
      SELECT COALESCE(name, 'A band member') INTO v_actor_name
      FROM users
      WHERE id = auth.uid();
    EXCEPTION
      WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    IF v_actor_name IS NULL THEN
      v_actor_name := 'A band member';
    END IF;

    v_rehearsal_date := UPPER(TO_CHAR(NEW.date, 'MON DD, YYYY'));
    v_title := 'Rehearsal Scheduled';
    v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;

    PERFORM notify_band_members(
      NEW.band_id,
      auth.uid(),
      'rehearsal_created',
      v_title,
      v_body,
      jsonb_build_object('rehearsal_id', NEW.id, 'rehearsal_date', NEW.date)
    );
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'notify_rehearsal_created failed (rehearsal % still created): %',
        NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- 4. Fix notify_blockout_created: ENTIRE body in exception handler
CREATE OR REPLACE FUNCTION notify_blockout_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_date_text TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  BEGIN
    BEGIN
      SELECT COALESCE(name, 'A band member') INTO v_actor_name
      FROM users
      WHERE id = auth.uid();
    EXCEPTION
      WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    IF v_actor_name IS NULL THEN
      v_actor_name := 'A band member';
    END IF;

    v_title := 'Member Unavailable';

    IF NEW.end_date IS NOT NULL AND NEW.end_date != NEW.start_date THEN
      DECLARE
        v_start_month TEXT;
        v_start_day TEXT;
        v_end_month TEXT;
        v_end_day TEXT;
        v_year TEXT;
      BEGIN
        v_start_month := UPPER(TO_CHAR(NEW.start_date, 'MON'));
        v_start_day := LTRIM(TO_CHAR(NEW.start_date, 'DD'), '0');
        v_end_month := UPPER(TO_CHAR(NEW.end_date, 'MON'));
        v_end_day := LTRIM(TO_CHAR(NEW.end_date, 'DD'), '0');
        v_year := TO_CHAR(NEW.end_date, 'YYYY');

        IF TO_CHAR(NEW.start_date, 'MON') = TO_CHAR(NEW.end_date, 'MON') THEN
          v_date_text := v_start_month || ' ' || v_start_day || ' – ' || v_end_day || ', ' || v_year;
        ELSE
          v_date_text := v_start_month || ' ' || v_start_day || ' – ' || v_end_month || ' ' || v_end_day || ', ' || v_year;
        END IF;
      END;
      v_body := v_actor_name || ' is unavailable ' || v_date_text;
    ELSE
      v_date_text := UPPER(TO_CHAR(NEW.start_date, 'MON DD, YYYY'));
      v_date_text := REPLACE(v_date_text, ' 0', ' ');
      v_body := v_actor_name || ' is unavailable on ' || v_date_text;
    END IF;

    PERFORM notify_band_members(
      NEW.band_id,
      auth.uid(),
      'blockout_created',
      v_title,
      v_body,
      jsonb_build_object(
        'blockout_id', NEW.id,
        'start_date', NEW.start_date,
        'end_date', NEW.end_date
      )
    );
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'notify_blockout_created failed (blockout % still created): %',
        NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- No trigger changes needed — they already point to these functions.
-- This migration only replaces function bodies.
