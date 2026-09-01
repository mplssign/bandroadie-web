-- ============================================================================
-- Fix potential rehearsal notification title/body wording
-- Purpose: preserve notification type while differentiating potential rehearsal
-- copy in notify_rehearsal_created().
-- ============================================================================

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

  IF NEW.is_potential THEN
    v_title := 'Potential Rehearsal Scheduled';
  ELSE
    v_title := 'Rehearsal Scheduled';
  END IF;

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

    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    END IF;
  ELSE
    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal for ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
    END IF;
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
