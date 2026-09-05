-- ============================================================================
-- Migration: 20260904120004_exit_and_heartbeat_demo_session_rpc.sql
-- exit_demo_session()     — teardown: deletes demo_sessions row + cascades
-- heartbeat_demo_session() — extends session expiry by 30 min
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- exit_demo_session()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.exit_demo_session()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT ((auth.jwt() ->> 'is_anonymous')::boolean IS TRUE) THEN
    RAISE EXCEPTION 'Not an anonymous session';
  END IF;

  -- Deleting the demo_sessions row cascades to:
  --   bands.demo_session_id → ON DELETE CASCADE → deletes both clone bands
  --   clone bands' band_id FK → ON DELETE CASCADE → deletes all child rows
  DELETE FROM demo_sessions WHERE auth_user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.exit_demo_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.exit_demo_session() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- heartbeat_demo_session()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.heartbeat_demo_session()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT ((auth.jwt() ->> 'is_anonymous')::boolean IS TRUE) THEN
    RAISE EXCEPTION 'Not an anonymous session';
  END IF;

  UPDATE demo_sessions
  SET last_seen_at = now(),
      expires_at   = now() + interval '30 minutes'
  WHERE auth_user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.heartbeat_demo_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_demo_session() TO authenticated;
