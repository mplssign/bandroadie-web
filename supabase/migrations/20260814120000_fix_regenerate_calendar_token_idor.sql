-- ============================================================================
-- Fix IDOR vulnerability in regenerate_calendar_token
-- ============================================================================
-- Issue: Any authenticated user can regenerate another user's calendar token
-- Fix: Add authorization check to verify p_user_id matches auth.uid()
-- Also: Add SET search_path to function definition for security hardening
-- ============================================================================

CREATE OR REPLACE FUNCTION regenerate_calendar_token(p_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_token UUID;
BEGIN
    -- Authorization check: only allow users to regenerate their own token
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Permission denied: cannot regenerate another user''s calendar token';
    END IF;
    
    new_token := gen_random_uuid();
    
    UPDATE users 
    SET calendar_token = new_token
    WHERE id = p_user_id;
    
    RETURN new_token;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION regenerate_calendar_token(UUID) TO authenticated;
