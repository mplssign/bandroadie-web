-- ============================================================================
-- Migration: 20260908194500_reduce_demo_session_ttl_to_15min.sql
-- Reduce demo session sliding-expiration TTL from 30 minutes to 15 minutes.
-- ============================================================================

ALTER TABLE public.demo_sessions
  ALTER COLUMN expires_at SET DEFAULT now() + interval '15 minutes';

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
      expires_at   = now() + interval '15 minutes'
  WHERE auth_user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.heartbeat_demo_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_demo_session() TO authenticated;