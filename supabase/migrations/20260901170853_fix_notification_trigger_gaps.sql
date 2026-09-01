-- ============================================================================
-- Fix notification trigger gaps
-- Purpose: repair gig/rehearsal/blockout trigger functions and bind the missing
-- blockout trigger to the live block_dates table.
-- ============================================================================

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
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_gig_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_gig_date := UPPER(v_gig_date);

  IF NEW.is_potential THEN
    v_notification_type := 'potential_gig_created';
    v_body := v_actor_name || ' created a potential gig for ' || v_gig_date;
    v_title := COALESCE(NEW.name, 'New Gig');
  ELSE
    v_notification_type := 'gig_created';
    v_body := v_actor_name || ' created a gig for ' || v_gig_date;
    v_title := 'Gig Scheduled';
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    v_notification_type,
    v_title,
    v_body,
    jsonb_build_object('gig_id', NEW.id, 'gig_date', NEW.date)
  );

  RETURN NEW;
END;
$$;

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
  IF NEW.parent_rehearsal_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_rehearsal_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_rehearsal_date := UPPER(v_rehearsal_date);

  v_title := 'Rehearsal Scheduled';

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

  RETURN NEW;
END;
$$;

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
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_title := 'Member Unavailable';
  v_date_text := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_date_text := UPPER(v_date_text);

  v_body := v_actor_name || ' is unavailable on ' || v_date_text;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'blockout_created',
    v_title,
    v_body,
    jsonb_build_object(
      'blockout_id', NEW.id,
      'date', NEW.date
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS blockout_created_notification ON public.block_dates;
CREATE TRIGGER blockout_created_notification
  AFTER INSERT ON public.block_dates
  FOR EACH ROW
  EXECUTE FUNCTION notify_blockout_created();
