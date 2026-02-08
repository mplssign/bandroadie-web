-- Run this in Supabase SQL Editor to update the remove_band_member function
-- This allows ANY active band member to remove other members (not just admins)

CREATE OR REPLACE FUNCTION public.remove_band_member(
  p_member_id UUID,
  p_band_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_caller_is_member BOOLEAN;
  v_target_user_id UUID;
BEGIN
  -- Verify the caller is an active member of this band
  SELECT EXISTS(
    SELECT 1 FROM public.band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND status = 'active'
  ) INTO v_caller_is_member;

  IF NOT v_caller_is_member THEN
    RAISE EXCEPTION 'Permission denied: only band members can remove members';
  END IF;

  -- Get the user_id of the member being removed
  SELECT user_id INTO v_target_user_id
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Member not found in this band';
  END IF;

  -- Prevent removing yourself
  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot remove yourself from the band';
  END IF;

  -- Perform the hard delete
  DELETE FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users (in case it's missing)
GRANT EXECUTE ON FUNCTION public.remove_band_member(UUID, UUID) TO authenticated;
