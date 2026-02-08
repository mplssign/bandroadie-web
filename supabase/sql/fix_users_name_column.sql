-- FIX: Update notify_rehearsal_created to use first_name and last_name
CREATE OR REPLACE FUNCTION public.notify_rehearsal_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Get actor name - FIX: use first_name and last_name, not name
  SELECT COALESCE(first_name || ' ' || last_name, email) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();
  
  -- Format date as "FEB 04, 2026"
  v_rehearsal_date := TO_CHAR(NEW.date, 'MON DD, YYYY');
  v_rehearsal_date := UPPER(v_rehearsal_date);
  
  v_title := 'Rehearsal Scheduled';
  v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
  
  -- Send notification
  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'rehearsal_created',
    v_title,
    v_body,
    jsonb_build_object('rehearsal_id', NEW.id, 'rehearsal_date', NEW.date)
  );
  
  RETURN NEW;
END;
$$;
