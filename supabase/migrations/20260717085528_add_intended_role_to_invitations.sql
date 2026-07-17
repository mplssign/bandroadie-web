-- Add intended_role column to band_invitations
-- This allows admins to specify the role (admin/member/contributor) when creating an invitation.
-- The role is applied when the invitee accepts the invitation.

-- Step 1: Add the column with a default value to backfill existing rows
ALTER TABLE public.band_invitations
  ADD COLUMN intended_role public.band_role_type NOT NULL DEFAULT 'member'::public.band_role_type;

-- Step 1.5: Fix RLS policy to enforce admin-only invite creation
-- The existing policy (band_invitations_insert_member) only checks band membership,
-- not admin role. Per Architect Plan E2, this must be corrected.
DROP POLICY IF EXISTS band_invitations_insert_member ON public.band_invitations;

CREATE POLICY "Admins can create invitations" ON public.band_invitations
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members
      WHERE band_members.band_id = band_invitations.band_id
        AND band_members.user_id = auth.uid()
        AND band_members.role = 'admin'
        AND band_members.status = 'active'
    )
    AND invited_by = auth.uid()
  );

-- Step 2: Update accept_band_invite RPC to read and apply intended_role
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
  v_intended_role TEXT;
BEGIN
  -- Lock the invite row and fetch band_id, status, and intended_role.
  -- FOR UPDATE prevents concurrent accept attempts from racing.
  SELECT band_id, status, intended_role::TEXT
    INTO v_band_id, v_status, v_intended_role
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

  -- Upsert band membership with the intended role.
  -- If a row already exists (e.g. previously removed member being re-invited),
  -- reactivate them with the new intended role. Active admins/contributors keep their
  -- current role because the UPDATE only fires when status is NOT 'active'.
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, p_user_id, v_intended_role::band_role_type, 'active')
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
