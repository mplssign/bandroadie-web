-- ============================================================================
-- SAFETY FIX: Notification Triggers - Defensive Exception Handling
-- Purpose: Ensure notification failures NEVER break core event creation
-- ============================================================================

-- Helper function: notify_band_members
-- SAFETY: Wrapped in exception handler at top level
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
DECLARE
  v_member RECORD;
BEGIN
  -- SAFETY: All notification logic wrapped in exception handler
  -- If ANY part fails, we log and continue - NEVER break the parent transaction
  BEGIN
    -- 1. Insert notification records for all band members (except actor)
    FOR v_member IN 
      SELECT user_id 
      FROM band_members 
      WHERE band_id = p_band_id 
      AND user_id != p_actor_user_id
    LOOP
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
        p_title,
        p_body,
        p_metadata,
        p_actor_user_id
      );
    END LOOP;
    
    -- 2. Send pg_notify for potential realtime listeners
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
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Log the error but DO NOT propagate - notification failures must not break events
      RAISE WARNING 'Notification system error (non-fatal): % - %', SQLERRM, SQLSTATE;
  END;
END;
$$;

-- Trigger function: notify_gig_created
-- SAFETY: Entire function body wrapped, always returns NEW
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
  -- SAFETY: All notification logic wrapped in exception handler
  BEGIN
    -- FIX: Use first_name and last_name, not name
    SELECT COALESCE(first_name || ' ' || last_name, email, 'A band member') 
    INTO v_actor_name
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
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but DO NOT propagate - gig creation must succeed
      RAISE WARNING 'Gig notification failed (non-fatal): % - %', SQLERRM, SQLSTATE;
  END;
  
  -- CRITICAL: Always return NEW so the INSERT succeeds
  RETURN NEW;
END;
$$;

-- Trigger function: notify_rehearsal_created
-- SAFETY: Entire function body wrapped, always returns NEW
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
  -- SAFETY: All notification logic wrapped in exception handler
  BEGIN
    -- FIX: Use first_name and last_name, not name
    SELECT COALESCE(first_name || ' ' || last_name, email, 'A band member') 
    INTO v_actor_name
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
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but DO NOT propagate - rehearsal creation must succeed
      RAISE WARNING 'Rehearsal notification failed (non-fatal): % - %', SQLERRM, SQLSTATE;
  END;
  
  -- CRITICAL: Always return NEW so the INSERT succeeds
  RETURN NEW;
END;
$$;

-- Trigger function: notify_blockout_created
-- SAFETY: Entire function body wrapped, always returns NEW
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
  -- SAFETY: All notification logic wrapped in exception handler
  BEGIN
    -- FIX: Use first_name and last_name, not name
    SELECT COALESCE(first_name || ' ' || last_name, email, 'A band member') 
    INTO v_actor_name
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
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but DO NOT propagate - blockout creation must succeed
      RAISE WARNING 'Blockout notification failed (non-fatal): % - %', SQLERRM, SQLSTATE;
  END;
  
  -- CRITICAL: Always return NEW so the INSERT succeeds
  RETURN NEW;
END;
$$;
