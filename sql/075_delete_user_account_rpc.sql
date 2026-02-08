-- Migration: Create delete_user_account RPC function
-- This function safely deletes a user's account and all associated data
-- Uses SECURITY DEFINER to bypass RLS and ensure complete cleanup
-- Handles missing tables gracefully to work across all environments

CREATE OR REPLACE FUNCTION public.delete_user_account(user_id_to_delete UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email TEXT;
BEGIN
  -- Verify the caller is the user being deleted (security check)
  IF auth.uid() IS NULL OR auth.uid() != user_id_to_delete THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  -- Get the user's email for invitation cleanup (before deleting user)
  SELECT email INTO user_email FROM public.users WHERE id = user_id_to_delete;

  -- Delete from gig_responses if table exists
  IF to_regclass('public.gig_responses') IS NOT NULL THEN
    DELETE FROM public.gig_responses WHERE user_id = user_id_to_delete;
  END IF;

  -- Delete from block_out_dates if table exists
  IF to_regclass('public.block_out_dates') IS NOT NULL THEN
    DELETE FROM public.block_out_dates WHERE user_id = user_id_to_delete;
  END IF;

  -- Delete from band_members if table exists
  IF to_regclass('public.band_members') IS NOT NULL THEN
    DELETE FROM public.band_members WHERE user_id = user_id_to_delete;
  END IF;

  -- Delete from band_invitations if table exists
  IF to_regclass('public.band_invitations') IS NOT NULL AND user_email IS NOT NULL THEN
    DELETE FROM public.band_invitations WHERE email = user_email;
  END IF;

  -- Delete the user's profile from the users table (required)
  DELETE FROM public.users WHERE id = user_id_to_delete;

  -- Note: The auth.users deletion should be handled by Supabase Auth
  -- after this function completes, or by calling auth.admin.deleteUser()
  -- from an Edge Function if needed for complete removal

END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION public.delete_user_account(UUID) IS 
'Safely deletes a user account and all associated data. Only the user themselves can call this function.';
