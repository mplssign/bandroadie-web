-- 079_remove_band_member_rpc.sql
-- RPC function to remove a band member (hard delete) with proper authorization.
-- Uses SECURITY DEFINER to bypass RLS since no DELETE policy exists on band_members.
-- Only band admins/owners can remove members.

CREATE OR REPLACE FUNCTION public.remove_band_member(
  p_member_id UUID,
  p_band_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_caller_role TEXT;
  v_target_user_id UUID;
BEGIN
  -- Verify the caller is an admin or owner of this band
  SELECT role INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active';

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'owner') THEN
    RAISE EXCEPTION 'Permission denied: only band admins can remove members';
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

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.remove_band_member(UUID, UUID) TO authenticated;
