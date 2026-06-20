-- ===========================================================================
-- Migration: restore_band_members RPC (SECURITY DEFINER)
-- Feature: bug/restore-fails-multi-member-band
-- Date: 2026-06-20
--
-- Introduces a trusted RPC for atomically restoring band members during
-- backup restore. The RPC bypasses RLS for the INSERT/UPDATE but validates
-- caller authority server-side (creator of band + active admin member).
--
-- See docs/features/restore-fails-multi-member-band/ARCHITECT_PLAN.md
-- See docs/reference/general/AI_DECISIONS.md — DECISION-003
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.restore_band_members(
  p_band_id uuid,
  p_members jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate: caller must be the creator of this band
  IF NOT EXISTS (
    SELECT 1 FROM bands
    WHERE id = p_band_id AND created_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Permission denied: you did not create this band';
  END IF;

  -- Validate: caller must be an active admin member of this band
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Permission denied: you are not an admin of this band';
  END IF;

  -- Insert or update all members from the JSONB array
  -- ON CONFLICT handles the case where a member row already exists (shouldn't happen
  -- during restore, but defensive)
  INSERT INTO band_members (id, band_id, user_id, role, status, joined_at)
  SELECT
    (m->>'id')::uuid,
    p_band_id,
    (m->>'user_id')::uuid,
    (m->>'role')::band_role_type,
    (m->>'status')::text,
    COALESCE((m->>'joined_at')::timestamptz, NOW())
  FROM jsonb_array_elements(p_members) AS m
  ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    joined_at = EXCLUDED.joined_at;
END;
$$;

-- Grant execute to authenticated users (admins who are restoring)
GRANT EXECUTE ON FUNCTION public.restore_band_members(uuid, jsonb) TO authenticated;

-- Documentation
COMMENT ON FUNCTION public.restore_band_members IS
  'SECURITY DEFINER RPC for atomically restoring band members during backup restore. Validates caller is band creator and active admin. See DECISION-003 in AI_DECISIONS.md.';
