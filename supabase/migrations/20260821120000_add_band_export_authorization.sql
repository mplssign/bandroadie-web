-- Add server-side authorization check for band data export
--
-- Creates a SECURITY DEFINER function to enforce role-based access control
-- for the band data export feature.
--
-- Authorization policy:
--   - admin role: allowed
--   - member role: allowed
--   - contributor role: blocked (regardless of contributor_permissions grants)
--   - non-members: blocked
--   - unauthenticated: blocked
--
-- This function is called by DataBackupService.exportBandData() before any
-- data is queried, ensuring the export policy is enforced server-side.

CREATE OR REPLACE FUNCTION check_band_export_permission(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role TEXT;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Get user's role in the band
  SELECT role INTO v_role
  FROM band_members
  WHERE band_id = p_band_id
    AND user_id = v_user_id
    AND status = 'active';

  -- If not a member, deny access
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Admin and member roles are allowed to export
  IF v_role IN ('admin', 'member') THEN
    RETURN TRUE;
  END IF;

  -- Contributor role is explicitly blocked, regardless of permissions
  -- (This is a role-level restriction, not a fine-grained permission check)
  IF v_role = 'contributor' THEN
    RETURN FALSE;
  END IF;

  -- Default deny for any unexpected role value
  RETURN FALSE;
END;
$$;

-- Explicitly revoke from PUBLIC to prevent anon execution (C6 hardening)
REVOKE EXECUTE ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC;

-- Grant only to authenticated users
GRANT EXECUTE ON FUNCTION check_band_export_permission(UUID) TO authenticated;
