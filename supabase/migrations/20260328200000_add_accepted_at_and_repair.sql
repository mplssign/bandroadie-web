-- ============================================================================
-- MIGRATION: Add accepted_at column + re-repair stale invites
-- Date: 2026-03-28
--
-- Root cause:
--   The accept_band_invite RPC references band_invitations.accepted_at 
--   but that column does not exist. PL/pgSQL defers column validation to
--   call time, so CREATE OR REPLACE FUNCTION succeeded but every RPC call
--   raised: "column band_invitations.accepted_at does not exist".
--   This means NO invite has ever been accepted via the RPC path.
--
-- Fixes:
--   1. Add the missing accepted_at column to band_invitations
--   2. Re-run the stale invite repair (the previous repair migration
--      itself was fine but the RPC it replaced still had the same bug)
-- ============================================================================

-- STEP 1: Add accepted_at column if it doesn't exist
ALTER TABLE public.band_invitations
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- STEP 2: Repair stale accepted invites (re-run for safety)
-- For every invitation marked 'accepted' where the user exists in auth.users
-- but has no corresponding active band_members row, insert the membership.
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

-- STEP 3: Also process any invites still stuck in 'pending'/'sent' where
-- the user already has an auth account. These are invites where the edge
-- function's RPC call failed silently due to the missing column.
-- For each such invite: create the band_members row and mark accepted.
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT bi.id AS invite_id, bi.band_id, u.id AS user_id
      FROM band_invitations bi
      JOIN auth.users u ON lower(u.email) = lower(bi.email)
     WHERE bi.status IN ('pending', 'sent')
       AND NOT EXISTS (
         SELECT 1 FROM band_members bm
          WHERE bm.band_id = bi.band_id
            AND bm.user_id = u.id
            AND bm.status = 'active'
       )
  LOOP
    -- Insert band member (or reactivate if removed)
    INSERT INTO band_members (band_id, user_id, role, status)
    VALUES (rec.band_id, rec.user_id, 'member'::band_role_type, 'active')
    ON CONFLICT (band_id, user_id) DO UPDATE
      SET status = 'active',
          role = CASE
                   WHEN band_members.status = 'active' THEN band_members.role
                   ELSE 'member'::band_role_type
                 END;

    -- Mark the invitation as accepted
    UPDATE band_invitations
       SET status = 'accepted',
           accepted_at = NOW()
     WHERE id = rec.invite_id;
  END LOOP;
END $$;
