-- ============================================================================
-- EMERGENCY FIX: Fix blockout notification trigger
-- This is the MINIMUM fix needed to stop the crash
-- Apply the full fix_notification_safety.sql after this for comprehensive protection
-- ============================================================================

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
  -- SAFETY: Wrap everything in exception handler so blockout creation never fails
  BEGIN
    -- FIX: Use first_name and last_name, NOT name (which doesn't exist)
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
