-- ============================================================================
-- NOTIFICATION TRIGGERS
-- Created: 2026-01-28
-- Purpose: Automatically send notifications when band events are created
-- ============================================================================

-- Helper function to call the Edge Function for sending notifications
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
AS $$
BEGIN
  -- Call Edge Function asynchronously via pg_net (if available)
  -- For now, just insert the notification record - Edge Function will be called separately
  -- This is a placeholder for future async trigger implementation
  
  PERFORM pg_notify(
    'band_notification',
    json_build_object(
      'band_id', p_band_id,
      'actor_user_id', p_actor_user_id,
      'notification_type', p_notification_type,
      'title', p_title,
      'body', p_body,
      'metadata', p_metadata
    )::text
  );
END;
$$;

-- Trigger function for gig creation
CREATE OR REPLACE FUNCTION notify_gig_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name TEXT;
  v_gig_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_notification_type TEXT;
BEGIN
  -- Get actor name
  SELECT name INTO v_actor_name
  FROM users
  WHERE id = auth.uid();
  
  -- Format date as "MAR 17, 2026"
  v_gig_date := TO_CHAR(NEW.date, 'MON DD, YYYY');
  v_gig_date := UPPER(v_gig_date);
  
  -- Determine notification type and body
  IF NEW.is_potential THEN
    v_notification_type := 'potential_gig_created';
    v_body := v_actor_name || ' created a potential gig for ' || v_gig_date;
  ELSE
    v_notification_type := 'gig_created';
    v_body := v_actor_name || ' created a gig for ' || v_gig_date;
  END IF;
  
  v_title := NEW.name;
  
  -- Send notification
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

-- Trigger function for rehearsal creation
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
BEGIN
  -- Get actor name
  SELECT name INTO v_actor_name
  FROM users
  WHERE id = auth.uid();
  
  -- Format date as "JUN 24, 2026"
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

-- Trigger function for block-out creation
CREATE OR REPLACE FUNCTION notify_blockout_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name TEXT;
  v_date_text TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Get actor name
  SELECT name INTO v_actor_name
  FROM users
  WHERE id = auth.uid();
  
  v_title := 'Member Unavailable';
  
  -- Format date or date range
  IF NEW.end_date IS NOT NULL AND NEW.end_date != NEW.start_date THEN
    -- Multi-day block out: "MAY 3 – JUN 5, 2026"
    DECLARE
      v_start_month TEXT;
      v_start_day TEXT;
      v_end_month TEXT;
      v_end_day TEXT;
      v_year TEXT;
    BEGIN
      v_start_month := UPPER(TO_CHAR(NEW.start_date, 'MON'));
      v_start_day := TO_CHAR(NEW.start_date, 'DD');
      v_end_month := UPPER(TO_CHAR(NEW.end_date, 'MON'));
      v_end_day := TO_CHAR(NEW.end_date, 'DD');
      v_year := TO_CHAR(NEW.end_date, 'YYYY');
      
      -- Remove leading zeros from days
      v_start_day := LTRIM(v_start_day, '0');
      v_end_day := LTRIM(v_end_day, '0');
      
      IF TO_CHAR(NEW.start_date, 'MON') = TO_CHAR(NEW.end_date, 'MON') THEN
        -- Same month: "MAY 3 – 5, 2026"
        v_date_text := v_start_month || ' ' || v_start_day || ' – ' || v_end_day || ', ' || v_year;
      ELSE
        -- Different months: "MAY 3 – JUN 5, 2026"
        v_date_text := v_start_month || ' ' || v_start_day || ' – ' || v_end_month || ' ' || v_end_day || ', ' || v_year;
      END IF;
    END;
    
    v_body := v_actor_name || ' is unavailable ' || v_date_text;
  ELSE
    -- Single day: "APR 18, 2026"
    v_date_text := TO_CHAR(NEW.start_date, 'MON DD, YYYY');
    v_date_text := UPPER(v_date_text);
    v_date_text := REPLACE(v_date_text, ' 0', ' '); -- Remove leading zero from day
    
    v_body := v_actor_name || ' is unavailable on ' || v_date_text;
  END IF;
  
  -- Send notification
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
  
  RETURN NEW;
END;
$$;

-- Create triggers (only fire on INSERT, not UPDATE or DELETE)
DROP TRIGGER IF EXISTS gig_created_notification ON gigs;
CREATE TRIGGER gig_created_notification
  AFTER INSERT ON gigs
  FOR EACH ROW
  EXECUTE FUNCTION notify_gig_created();

DROP TRIGGER IF EXISTS rehearsal_created_notification ON rehearsals;
CREATE TRIGGER rehearsal_created_notification
  AFTER INSERT ON rehearsals
  FOR EACH ROW
  EXECUTE FUNCTION notify_rehearsal_created();

-- Only create block_out_dates trigger if the table exists
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'block_out_dates') THEN
    DROP TRIGGER IF EXISTS blockout_created_notification ON block_out_dates;
    CREATE TRIGGER blockout_created_notification
      AFTER INSERT ON block_out_dates
      FOR EACH ROW
      EXECUTE FUNCTION notify_blockout_created();
  END IF;
END $$;

-- Note: These triggers use pg_notify to send events. A separate listener 
-- (realtime subscription or Supabase Realtime) would call the Edge Function.
-- For now, this creates the notification records in the database.
-- The Edge Function can be called manually or via a separate polling mechanism.
