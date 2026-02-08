-- Migration: Fix recurring rehearsal notifications
-- Problem: When creating a recurring rehearsal, the trigger fires for EVERY instance,
--          resulting in dozens of notifications instead of one.
-- Solution: Only send notification for the parent (first) rehearsal in a series,
--           and include recurrence pattern in the message.

-- ============================================================================
-- UPDATED TRIGGER FUNCTION
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
  v_day_index INT;
BEGIN
  -- Skip notifications for child rehearsals in a recurring series
  -- Only the parent (first) rehearsal should trigger a notification
  IF NEW.parent_rehearsal_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Get actor first name only
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(name, ' ', 1),  -- First word of full name
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();
  
  -- Format date as "MAR 4" (uppercase month, no leading zero on day, no year)
  v_rehearsal_date := TO_CHAR(NEW.date, 'MON FMDD');
  v_rehearsal_date := UPPER(v_rehearsal_date);
  
  v_title := 'Rehearsal Scheduled';
  
  -- Build recurrence description if this is a recurring rehearsal
  IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
    -- Build human-readable day list from recurrence_days array (pluralized)
    v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];
    
    IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
      -- Build comma-separated day list
      SELECT string_agg(v_day_names[d + 1], ', ')
      INTO v_recurrence_text
      FROM unnest(NEW.recurrence_days) AS d
      ORDER BY d;
      
      -- Format based on frequency: "on Mondays", "every other Monday", "monthly on Mondays"
      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'on ' || v_recurrence_text
        WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
        WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
        ELSE 'recurring'
      END;
    ELSE
      -- Fallback if no days specified
      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'weekly'
        WHEN 'biweekly' THEN 'biweekly'
        WHEN 'monthly' THEN 'monthly'
        ELSE 'recurring'
      END;
    END IF;
    
    -- Build message: "Tony scheduled a rehearsal on Mondays starting MAR 4"
    v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
  ELSE
    -- One-time rehearsal: "Tony scheduled a rehearsal for MAR 4"
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
  
  RETURN NEW;
END;
$$;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON FUNCTION notify_rehearsal_created() IS 
  'Sends notification when a rehearsal is created. For recurring rehearsals, 
   only the parent (first) instance triggers a notification, with recurrence 
   pattern included in the message.';
