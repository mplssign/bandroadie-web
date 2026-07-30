-- Add manual ordering support to band_members.
-- position is nullable: NULL means "no manual order set — use alphabetical".
-- Existing rows are unaffected (all start at position = NULL, no backfill).

ALTER TABLE public.band_members ADD COLUMN position INTEGER NULL;

-- Deferrable from the start (mirrors the fix retrofitted for setlist_songs in
-- 20260724143942_fix_setlist_positions_trigger_collision.sql) so a multi-row
-- reorder's two-phase update never trips this constraint mid-transaction.
-- Postgres treats each NULL as distinct, so multiple members may simultaneously
-- have position IS NULL without violating uniqueness.
ALTER TABLE public.band_members
  ADD CONSTRAINT band_members_band_id_position_key
  UNIQUE (band_id, position) DEFERRABLE INITIALLY DEFERRED;

-- Atomically reorders all members of a band. The client always sends the
-- complete, currently-rendered ordered list of member IDs.
--
-- band_members.UPDATE is RLS-gated to active admins only; because this
-- function is SECURITY DEFINER (bypassing RLS), the same rule is
-- re-implemented here inline, mirroring remove_band_member's existing
-- admin-check convention.
CREATE OR REPLACE FUNCTION public.reorder_band_members(
  p_band_id uuid,
  p_member_ids uuid[]
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_expected INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = p_band_id AND user_id = auth.uid()
      AND role = 'admin' AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Permission denied: only admins can reorder members';
  END IF;

  v_expected := array_length(p_member_ids, 1);

  -- Validate: all supplied member IDs must belong to the given band
  SELECT COUNT(*)
    INTO v_count
    FROM public.band_members
   WHERE id = ANY(p_member_ids)
     AND band_id = p_band_id;

  IF v_count <> v_expected THEN
    RAISE EXCEPTION 'Row count mismatch: expected %, found % for band %',
      v_expected, v_count, p_band_id;
  END IF;

  -- Phase 1: assign temporary negative positions to avoid UNIQUE violation
  UPDATE public.band_members
     SET position = -(ordinality::INTEGER)
    FROM unnest(p_member_ids) WITH ORDINALITY AS t(rid, ordinality)
   WHERE band_members.id = t.rid;

  -- Phase 2: flip to final 0-based positions
  UPDATE public.band_members
     SET position = (-position) - 1
   WHERE id = ANY(p_member_ids);

  RETURN json_build_object('success', TRUE, 'reordered_count', v_expected);
END;
$$;
