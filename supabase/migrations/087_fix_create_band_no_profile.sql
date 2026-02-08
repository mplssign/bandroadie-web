-- 087_fix_create_band_no_profile.sql
-- Ensure create_band RPC works without requiring a completed profile.
-- Users who skip profile completion should still be able to create bands.
-- Also handles case where user doesn't exist in public.users table yet.

-- Drop and recreate the create_band function with proper handling for
-- users without profile data (first_name/last_name may be null)

CREATE OR REPLACE FUNCTION public.create_band(
  p_name TEXT,
  p_avatar_color TEXT DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_email TEXT;
  v_band_id UUID;
BEGIN
  -- Get the current authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  
  -- Ensure user exists in public.users table
  -- This handles cases where the handle_new_user trigger didn't fire
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id) THEN
    -- Get email from auth.users
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    
    IF v_user_email IS NULL THEN
      RAISE EXCEPTION 'User not found in auth system';
    END IF;
    
    -- Create the user row
    INSERT INTO users (id, email)
    VALUES (v_user_id, v_user_email);
  END IF;
  
  -- Create the band
  INSERT INTO bands (
    name,
    avatar_color,
    image_url,
    created_by
  )
  VALUES (
    p_name,
    COALESCE(p_avatar_color, '#F43F5E'),
    p_image_url,
    v_user_id
  )
  RETURNING id INTO v_band_id;
  
  -- Add the creator as a band member with 'active' status
  -- Note: user may not have a complete profile (first_name/last_name may be null)
  -- This is intentional - users can create bands before completing their profile
  INSERT INTO band_members (
    band_id,
    user_id,
    status,
    role
  )
  VALUES (
    v_band_id,
    v_user_id,
    'active',
    'admin'
  );
  
  -- Return the new band ID
  RETURN v_band_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.create_band(TEXT, TEXT, TEXT) TO authenticated;

-- Add a comment for documentation
COMMENT ON FUNCTION public.create_band IS 'Creates a new band and adds the current user as an admin member. Works for users with incomplete profiles.';
