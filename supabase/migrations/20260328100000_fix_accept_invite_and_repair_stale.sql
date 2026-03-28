-- ============================================================================
-- MIGRATION: Fix accept_band_invite RPC + repair stale accepted invites
-- Date: 2026-03-28
--
-- Problems fixed:
--   1. ON CONFLICT DO NOTHING silently skipped re-invitations for
--      removed/inactive members. Changed to DO UPDATE SET status = 'active'.
--   2. Stale 'accepted' invites exist where band_invitations.status = 'accepted'
--      but no corresponding band_members row was created (due to the old
--      non-atomic edge function that updated invite status separately from
--      inserting the member).
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: Replace the RPC with the fixed version
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.accept_band_invite(
  p_invite_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band_id UUID;
  v_status TEXT;
BEGIN
  -- Lock the invite row and fetch band_id + status.
  -- FOR UPDATE prevents concurrent accept attempts from racing.
  SELECT band_id, status
    INTO v_band_id, v_status
    FROM band_invitations
   WHERE id = p_invite_id
     FOR UPDATE;

  -- Invite not found
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found';
  END IF;

  -- Already accepted — idempotent success, no re-write
  IF v_status = 'accepted' THEN
    RETURN;
  END IF;

  -- Only pending or sent invites may be accepted
  IF v_status NOT IN ('pending', 'sent') THEN
    RAISE EXCEPTION 'Invitation is not eligible for acceptance (status: %)', v_status;
  END IF;

  -- Upsert band membership.
  -- If a row already exists (e.g. previously removed member being re-invited),
  -- reactivate them with 'member' role. Active admins/contributors keep their
  -- current role because the UPDATE only fires when status is NOT 'active'.
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, p_user_id, 'member'::band_role_type, 'active')
  ON CONFLICT (band_id, user_id) DO UPDATE
    SET status = 'active',
        role = CASE
                 WHEN band_members.status = 'active' THEN band_members.role
                 ELSE EXCLUDED.role
               END;

  -- Mark invitation as accepted
  UPDATE band_invitations
     SET status = 'accepted',
         accepted_at = NOW()
   WHERE id = p_invite_id;
END;
$$;

-- Permissions (idempotent)
REVOKE ALL ON FUNCTION public.accept_band_invite(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_band_invite(UUID, UUID) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: Repair stale accepted invites
-- For every invitation marked 'accepted' where the user exists in auth.users
-- but has no corresponding band_members row, insert the missing membership.
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO band_members (band_id, user_id, role, status)
SELECT bi.band_id, u.id, 'member'::band_role_type, 'active'
  FROM band_invitations bi
  JOIN auth.users u ON lower(u.email) = lower(bi.email)
 WHERE bi.status = 'accepted'
   AND NOT EXISTS (
     SELECT 1 FROM band_members bm
      WHERE bm.band_id = bi.band_id
        AND bm.user_id = u.id
   )
ON CONFLICT (band_id, user_id) DO UPDATE
  SET status = 'active';
