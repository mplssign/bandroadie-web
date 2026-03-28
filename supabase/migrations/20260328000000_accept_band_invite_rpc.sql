-- accept_band_invite_rpc.sql
-- Atomically accepts a band invitation: upserts the user into band_members
-- and marks the invitation as accepted, within a single transaction boundary.
-- Called exclusively by the accept-invite edge function via service_role.

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
  -- Use IF NOT FOUND (idiomatic PL/pgSQL) rather than checking v_band_id IS NULL.
  -- IF NOT FOUND is correct regardless of whether band_id is nullable.
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

-- Revoke default PUBLIC execute grant before adding targeted grant.
-- PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION.
-- Without this REVOKE, any role (anon, authenticated) can call this function
-- directly with arbitrary p_user_id values — bypassing all access controls.
REVOKE ALL ON FUNCTION public.accept_band_invite(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_band_invite(UUID, UUID) TO service_role;
