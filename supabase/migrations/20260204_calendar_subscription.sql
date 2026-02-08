-- Migration: Add calendar subscription token to users table
-- This token allows secure, read-only access to a user's calendar feed

-- Add calendar_token column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS calendar_token UUID DEFAULT gen_random_uuid() UNIQUE;

-- Create index for fast token lookups
CREATE INDEX IF NOT EXISTS idx_users_calendar_token ON users(calendar_token);

-- Function to regenerate calendar token (if user wants a new URL)
CREATE OR REPLACE FUNCTION regenerate_calendar_token(p_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_token UUID;
BEGIN
    new_token := gen_random_uuid();
    
    UPDATE users 
    SET calendar_token = new_token
    WHERE id = p_user_id;
    
    RETURN new_token;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION regenerate_calendar_token(UUID) TO authenticated;

-- RPC function to get or create calendar token for current user
CREATE OR REPLACE FUNCTION get_my_calendar_token()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    token UUID;
BEGIN
    SELECT calendar_token INTO token
    FROM users
    WHERE id = auth.uid();
    
    -- If no token exists, generate one
    IF token IS NULL THEN
        token := gen_random_uuid();
        UPDATE users SET calendar_token = token WHERE id = auth.uid();
    END IF;
    
    RETURN token;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_my_calendar_token() TO authenticated;

-- Comment explaining the purpose
COMMENT ON COLUMN users.calendar_token IS 'Unique token for calendar subscription URL. Allows read-only access to user calendar feed without authentication.';
